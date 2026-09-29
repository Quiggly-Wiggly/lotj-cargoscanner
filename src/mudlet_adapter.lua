-- The package builder embeds Core, Display, and UI before this adapter.
if LotJCargoScanner and LotJCargoScanner.destroy then LotJCargoScanner:destroy() end

local C = {version = "0.4.0", markets = {}, planets = {}, handlers = {},
  units = 1, capacitySet = false, maxAgeSeconds = 3600, sort = "distance", active = false,
  scanOutput = "compact", queue = {}, cursor = 0, completed = 0, failed = {}, gmcpEvents = {}}
LotJCargoScanner = C
local cachePath = getMudletHomeDir() .. "/lotj-cargoscanner-quotes.txt"
local settingsPath = getMudletHomeDir() .. "/lotj-cargoscanner-settings.txt"
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function key(s) return trim(s):lower() end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function msg(s, kind, actions, title) C:notify(s, kind, actions, title) end
local function keys(t)
  local out = {}; for k in pairs(t) do out[#out + 1] = k end
  table.sort(out); return out
end
local function safeName(s)
  return type(s) == "string" and #s <= 100 and s:match("^[%w][%w '%-]*$") ~= nil
end
local function cancel(field)
  if C[field] then killTimer(C[field]); C[field] = nil end
end

local function validCapacity(n)
  return type(n) == "number" and n >= 1 and n <= 100000000 and n == math.floor(n)
end

local function fileExists(path)
  local f, err, code = io.open(path, "rb")
  if f then f:close(); return true end
  if code == 2 then return false end
  return nil, err
end

-- A Windows replacement can be interrupted after the old file is moved aside.
-- Restore that committed file before reading or attempting another save.
local function recoverFile(path)
  local exists, err = fileExists(path)
  if exists == nil then return nil, err end
  if exists then return true end
  local backup = path .. ".bak"
  exists, err = fileExists(backup)
  if exists == nil then return nil, err end
  if not exists then return true end
  local ok; ok, err = os.rename(backup, path)
  if not ok then return nil, "cannot restore " .. backup .. ": " .. tostring(err) end
  return true
end

local function writeFile(path, data)
  local ok, err = recoverFile(path)
  if not ok then return nil, err end
  local temporary, backup = path .. ".tmp", path .. ".bak"
  local f; f, err = io.open(temporary, "wb")
  if not f then return nil, err end
  ok, err = f:write(data)
  if not ok then f:close(); return nil, err end
  ok, err = f:close()
  if not ok then return nil, err end

  -- POSIX can replace the target directly; Windows rename refuses to do so.
  ok, err = os.rename(temporary, path)
  if ok then return true end
  local exists, checkError = fileExists(path)
  if not exists then return nil, checkError or err end
  local hasBackup; hasBackup, checkError = fileExists(backup)
  if hasBackup == nil then return nil, checkError end
  if hasBackup then
    ok, err = os.remove(backup)
    if not ok then return nil, "cannot clear old backup: " .. tostring(err) end
  end
  ok, err = os.rename(path, backup)
  if not ok then return nil, "cannot back up saved file: " .. tostring(err) end
  ok, err = os.rename(temporary, path)
  if not ok then
    local restored, restoreError = os.rename(backup, path)
    if not restored then
      return nil, tostring(err) .. "; previous saved file retained at " .. backup
        .. "; restore failed: " .. tostring(restoreError)
    end
    return nil, err
  end
  -- Failure to remove an obsolete backup does not invalidate the new file.
  -- The next replacement will retry cleanup before moving the current file.
  os.remove(backup)
  return true
end

function C:loadCapacity()
  local restored, restoreError = recoverFile(settingsPath)
  if not restored then msg("Cannot recover cargo capacity: " .. tostring(restoreError), "error"); return end
  local f, err, code = io.open(settingsPath, "rb")
  if not f then
    if code ~= 2 then msg("Cannot read cargo capacity: " .. tostring(err), "error") end
    return
  end
  local text = f:read(128); f:close()
  local n = text and tonumber(text:match("^capacity=(%d+)%s*$"))
  if not validCapacity(n) or #text >= 128 then msg("Saved cargo capacity is invalid; using per-unit estimates.", "warning"); return end
  self.units = n; self.capacitySet = true
end

function C:setCapacity(text)
  if text == "" then
    self:showMenu("settings")
    return
  end
  local n = text:match("^%d+$") and tonumber(text)
  if not validCapacity(n) then
    msg("Enter a whole cargo capacity from 1 to 100,000,000 units.", "error",
      {{text = "Enter capacity", fill = "cargoscan cargocapacity "}}, "Capacity not changed"); return
  end
  local ok, err = writeFile(settingsPath, string.format("capacity=%.0f\n", n))
  if not ok then msg("Cannot save cargo capacity: " .. tostring(err), "error"); return end
  self.units = n; self.capacitySet = true
  self:settingsChanged("Cargo capacity saved. Estimates use a full load on every leg.")
end

-- Cache validated market fields as replayable text.
function C:save()
  self.unsavedQuotes = true
  local out = {"# LotJ cargo quotes 1"}
  for _, id in ipairs(keys(self.markets)) do
    local m = self.markets[id]
    out[#out + 1] = "# Captured-At: " .. tostring(m.observedAt)
    out[#out + 1] = "--Planet Data: -----------------------------------------"
    out[#out + 1] = "Planet: " .. m.name
    out[#out + 1] = "Starsystem: " .. m.system
    out[#out + 1] = "Governed By: " .. m.government
    out[#out + 1] = string.format("Tax Rate: %.2f", m.taxRate)
    if m.freeport then out[#out + 1] = m.name .. " is a freeport." end
    for _, resource in ipairs(keys(m.resources)) do
      out[#out + 1] = string.format("%s ( Price per unit: %.2f)", resource, m.resources[resource])
    end
    out[#out + 1] = "Use 'SHOWPLANET <planet> RESOURCES <resource>' for price history."
  end
  local ok, err = writeFile(cachePath, table.concat(out, "\n") .. "\n")
  if ok then self.unsavedQuotes = false end
  return ok, err
end

function C:load()
  local restored, restoreError = recoverFile(cachePath)
  if not restored then msg("Cannot recover saved quotes: " .. tostring(restoreError), "error"); return end
  local f, err, code = io.open(cachePath, "rb")
  if not f then if code ~= 2 then msg("Cannot read saved quotes: " .. tostring(err), "error") end; return end
  local data = f:read(2000001); f:close()
  if not data or #data > 2000000 then msg("Saved quotes are unreadable or too large.", "error"); return end
  local loaded, parser, header = {}, nil, false
  for raw in (data .. "\n"):gmatch("([^\n]*)\n") do
    local timestamp = raw:match("^# Captured%-At: (%d+)$")
    if not header then
      if raw ~= "# LotJ cargo quotes 1" then msg("Unrecognized saved quote format.", "error"); return end
      header = true
    elseif timestamp then
      if parser then msg("Incomplete saved quote block.", "error"); return end
      if tonumber(timestamp) > os.time() + 60 then msg("Saved quote timestamp is in the future.", "error"); return end
      parser = Core.newParser(nil, tonumber(timestamp))
    elseif parser then
      local status, value = parser:feed(raw)
      if status == "error" then msg("Saved quotes failed validation: " .. tostring(value), "error"); return end
      if status == "complete" then
        if loaded[key(value.name)] then msg("Duplicate saved planet quote.", "error"); return end
        loaded[key(value.name)] = value; parser = nil
      end
    elseif trim(raw) ~= "" then msg("Unexpected text in saved quotes.", "error"); return end
  end
  if parser then msg("Incomplete saved quote block.", "error"); return end
  self.markets = loaded
  self.unsavedQuotes = false
end

local function tableField(value, field)
  if type(value) == "table" then return value[field] end
end

function C:refreshPlanets()
  local sources = {
    {name = "gmcp.Galaxy.Systems", label = "GMCP Galaxy.Systems",
      data = tableField(tableField(gmcp, "Galaxy"), "Systems")},
    {name = "lotj.galaxyMap.systems", label = "LOTJ UI galaxy map (may be cached)",
      data = tableField(tableField(lotj, "galaxyMap"), "systems")},
  }
  self.planets, self.planetSource, self.catalogSources = {}, "Unavailable", {}
  for _, source in ipairs(sources) do
    local planets = Core.planetsFromGMCP(source.data)
    local systemCount = 0
    if type(source.data) == "table" then
      for name, system in pairs(source.data) do
        if type(name) == "string" and trim(name) ~= "" and type(system) == "table" then
          systemCount = systemCount + 1
        end
      end
    end
    local planetCount = count(planets)
    self.catalogSources[#self.catalogSources + 1] = {name = source.name,
      dataType = type(source.data), systemCount = systemCount, planetCount = planetCount}
    -- The UI may have restored its map from disk without populating gmcp.
    -- Use it only if live data contains no usable planets; never merge old entries.
    if not next(self.planets) and planetCount > 0 then
      self.planets, self.planetSource = planets, source.label
    end
  end
  return count(self.planets)
end

function C:stop(reason)
  self.active = false
  cancel("timeoutTimer"); cancel("nextTimer")
  if self.trigger then killTrigger(self.trigger); self.trigger = nil end
  self.parser = nil; self.expectedCommand = nil
  if reason then msg(reason, "info", {{text = "View loops", command = "loops"}, {text = "Home", command = "home"}}) end
end

function C:fail(reason)
  if self.current and self.parser then self.failed[key(self.current)] = reason end
  local planet = self.current
  self:stop()
  local actions = {{text = "Scan all", command = "scan"}, {text = "Status", command = "status"}}
  if safeName(planet) then table.insert(actions, 1, {text = "Retry " .. planet, command = "scan " .. planet}) end
  local retained = self.unsavedQuotes and " Latest quotes are in memory only; retry the scan before closing Mudlet."
    or " Previously saved quotes are retained."
  msg("Stopped at " .. tostring(planet) .. ": " .. reason .. "." .. retained,
    "error", actions, "Scan interrupted")
end

function C:nextPlanet()
  if not self.active then return end
  self.cursor = self.cursor + 1
  local name = self.queue[self.cursor]
  if not name then
    self:stop()
    msg("Scan complete: " .. self.completed .. " planets captured.", "success")
    self:showRoutes(true, 10); return
  end
  self.current = name
  if not safeName(name) then self:fail("unsupported planet name"); return end
  self.parser = Core.newParser(name, os.time())
  self.timeoutTimer = tempTimer(12, function()
    self.timeoutTimer = nil
    if self.active then self:fail("no complete resource response within 12 seconds") end
  end)
  local command = 'showplanet "' .. name .. '" resources'
  self.expectedCommand = command
  local ok, err = pcall(send, command, self.scanOutput == "full")
  self.expectedCommand = nil
  if not ok then self:fail("send failed: " .. tostring(err)) end
end

function C:onLine(raw)
  if not self.active or not self.parser then return end
  local parser = self.parser
  local status, value = self.parser:feed(raw)
  if status == "error" then self:fail(tostring(value)); return end
  -- Gag accepted resource lines before rendering, so the scanner UI stays visible.
  if self.scanOutput == "compact" and parser.started and deleteLine then deleteLine() end
  if status ~= "complete" then return end
  cancel("timeoutTimer")
  self.markets[key(value.name)] = value
  self.failed[key(value.name)] = nil
  self.parser = nil
  local ok, err = self:save()
  if not ok then self:fail("cannot save completed quotes: " .. tostring(err)); return end
  self.completed = self.completed + 1
  local state = {completed = self.completed, total = #self.queue, current = value.name,
    resources = count(value.resources), taxRate = value.taxRate, active = true}
  self:render(UI.progress(state, self:displayConfig()))
  self.nextTimer = tempTimer(1, function() self.nextTimer = nil; self:nextPlanet() end)
end

function C:scan(planet)
  if self.active then
    msg("A scan is already running.", "warning", {{text = "Stop scan", command = "stop"}, {text = "Status", command = "status"}}); return
  end
  if getConnectionInfo then
    local _, _, connected = getConnectionInfo()
    if connected == false then msg("Connect to LotJ before scanning.", "warning"); return end
  end
  if self:refreshPlanets() == 0 then
    msg("No planets found in live GMCP or the LOTJ UI map. Load the galaxy map, then check Diagnostics if the list stays empty.", "warning",
      {{text = "Diagnostics", command = "diagnostics"}}, "Planet list unavailable"); return
  end
  self.queue = {}
  if planet and planet ~= "" then
    planet = trim(planet):gsub('^"(.*)"$', "%1")
    local p = self.planets[key(planet)]
    if not p then msg("Unknown planet: " .. planet .. ". Choose a name from the planet list.", "error",
      {{text = "Planets", command = "planets"}}); return end
    self.queue[1] = p.name
  else
    for _, id in ipairs(keys(self.planets)) do self.queue[#self.queue + 1] = self.planets[id].name end
  end
  self.cursor = 0; self.completed = 0; self.current = nil; self.active = true
  self.trigger = tempRegexTrigger("^.*$", function()
    local ok, err = pcall(self.onLine, self, line)
    if not ok then self:fail("capture error: " .. tostring(err)) end
  end)
  msg("Scanning " .. #self.queue .. " planets. Each completed market is saved.", "info",
    {{text = "Stop scan", command = "stop"}, {text = "Status", command = "status"}}, "Scan started")
  self:nextPlanet()
end

function C:options()
  return {units = self.units, now = os.time(), maxAgeSeconds = self.maxAgeSeconds, sort = self.sort}
end

local palette = {
  title = {255, 190, 70}, text = {216, 225, 234}, muted = {149, 165, 180},
  accent = {238, 197, 129}, positive = {119, 224, 172}, rank = {120, 189, 255},
  warning = {238, 197, 129}, error = {244, 132, 139},
}

function C:displayConfig(kind, limit, stops, marketCount)
  local width = 96
  if getColumnCount then
    local ok, columns = pcall(getColumnCount)
    if ok and type(columns) == "number" and columns > 0 then width = math.min(100, columns - 2) end
  end
  return {kind = kind, count = limit or 10, units = self.units, capacitySet = self.capacitySet, width = width,
    sort = self.sort, stopsLabel = stops and (stops .. " planets") or "2-3 planets",
    marketCount = marketCount or 0, maxAgeMinutes = self.maxAgeSeconds / 60, now = os.time()}
end

function C:render(lines, compact)
  if not compact then echo("\n") end
  for _, segments in ipairs(lines) do
    for _, segment in ipairs(segments) do
      local color = palette[segment.color] or palette.text
      if deselect then deselect() end
      if setFgColor then setFgColor(color[1], color[2], color[3]) end
      if (segment.detail or segment.command or segment.fill) and echoLink then
        -- Capture the row itself so links in older reports keep their meaning.
        local snapshot = segment.detail
        local command, fill = segment.command, segment.fill
        local hint = segment.hint or (snapshot and "Show cargo, prices, and every leg")
          or (fill and "Fill the command line; enter a value and press Return") or ("cargoscan " .. command)
        local ok = pcall(echoLink, segment.text, function()
          local current = LotJCargoScanner
          if not current then return end
          if snapshot then current:showDetail(snapshot)
          elseif fill then
            if printCmdLine then printCmdLine(fill)
            else current:notify("Type " .. fill .. " followed by your value.", "info") end
          else
            local verb=(command or ''):match('^(%S+)') or ''
            local view={['']=true,help=true,settings=true,status=true,planets=true,loops=true,routes=true,show=true,diagnostics=true,gmcp=true}
            if view[verb] then current:command(command)
            elseif printCmdLine then printCmdLine('cargoscan '..command)
            else current:notify('Type cargoscan '..command..' to continue.','info') end
          end
        end, hint, true)
        if not ok then echo(segment.text) end
      else
        echo(segment.text)
      end
      if resetFormat then resetFormat() end
    end
    echo("\n")
  end
end

function C:notify(message, kind, actions, title)
  local config = self:displayConfig()
  config.kind = kind or "info"; config.actions = actions; config.title = title
  self:render(UI.notice(message, config))
end

function C:uiState()
  self:refreshPlanets()
  local now = os.time()
  local state = {version = self.version, active = self.active, current = self.current,
    completed = self.completed, total = #self.queue, units = self.units, capacitySet = self.capacitySet,
    maxAgeMinutes = self.maxAgeSeconds / 60, sort = self.sort, scanOutput = self.scanOutput,
    planetCount = count(self.planets), planetSource = self.planetSource, catalogSources = self.catalogSources,
    marketCount = count(self.markets), freshCount = 0,
    staleCount = 0, failedCount = count(self.failed), missingCount = 0, markets = {}, planets = {}, probing = self.probing}
  local function marketState(id)
    local market = self.markets[id]
    local age = market and (now - market.observedAt) or nil
    if self.failed[id] then return "failed", age and age / 60 end
    if not age or age < 0 then return "unknown", nil end
    return age <= self.maxAgeSeconds and "fresh" or "stale", age / 60
  end
  for _, id in ipairs(keys(self.markets)) do
    local m = self.markets[id]
    local quality, age = marketState(id)
    state.markets[#state.markets + 1] = {name = m.name, resources = count(m.resources), ageMinutes = age,
      taxRate = m.taxRate, state = quality}
    if quality == "fresh" then state.freshCount = state.freshCount + 1
    elseif quality == "stale" then state.staleCount = state.staleCount + 1 end
  end
  for _, id in ipairs(keys(self.planets)) do
    local p = self.planets[id]
    local quality, age = marketState(id)
    state.planets[#state.planets + 1] = {name = p.name, system = p.system,
      galaxyX = p.galaxyX, galaxyY = p.galaxyY, state = quality, ageMinutes = age}
    if not self.markets[id] then state.missingCount = state.missingCount + 1 end
  end
  return state
end

function C:showMenu(menu)
  self.currentMenu = menu
  self:render(UI[menu](self:uiState(), self:displayConfig()))
end

function C:settingsChanged(message)
  msg(message, "success")
  local menu = self.currentMenu
  local localMenu = menu == "settings" or menu == "home"
  if self.lastView then
    self:showRoutes(self.lastView.loops, self.lastView.limit, self.lastView.stops, localMenu)
  end
  if localMenu then self:showMenu(menu)
  elseif not self.lastView then self:showMenu("settings") end
end

function C:showDetail(rowOrIndex)
  local row = rowOrIndex
  if type(row) ~= "table" then
    local index = tonumber(rowOrIndex)
    row = index and index == math.floor(index) and self.lastRows and self.lastRows[index]
  end
  if not row then
    msg("Choose a rank from the most recent results. Show the route details with cargoscan show <number>.", "warning",
      {{text = "View loops", command = "loops"}, {text = "View routes", command = "routes"}}, "Route not found"); return
  end
  self.currentMenu = "detail"
  local config = self:displayConfig(row.legs and "loops" or "routes")
  config.units = row.units or self.units
  config.capacitySet = row.capacitySet == true
  self:render(Display.detail(row, config))
end

function C:showRoutes(loops, limit, stops, quiet)
  self:refreshPlanets()
  local markets = {}
  for id, market in pairs(self.markets) do if not self.failed[id] then markets[id] = market end end
  local options = self:options()
  limit = math.floor(math.max(1, math.min(tonumber(limit) or 10, 100)))
  options.stops = stops
  local rows = loops and Core.loops(markets, self.planets, options) or Core.routes(markets, self.planets, options)
  for _, row in ipairs(rows) do row.capacitySet = self.capacitySet end
  self.lastView = {loops = loops, limit = limit, stops = stops}
  self.lastRows = {}
  for i = 1, math.min(limit, #rows) do self.lastRows[i] = rows[i] end
  local freshCount = 0
  for _, market in pairs(markets) do
    local age = options.now - market.observedAt
    if age >= 0 and age <= self.maxAgeSeconds then freshCount = freshCount + 1 end
  end
  if quiet then return end
  self.currentMenu = loops and "loops" or "routes"
  local config = self:displayConfig(self.currentMenu, limit, stops, freshCount)
  if freshCount == 0 then config.emptyReason = "No fresh prices are available. Scan prices to get started."
  elseif freshCount < (stops or 2) then config.emptyReason = "Too few fresh markets for this search. Scan more planets or choose fewer stops."
  else config.emptyReason = "No profitable matches for this search. Try fewer stops or refresh prices." end
  self:render(Display.summary(rows, config))
end

-- Inspect cached field names without exposing payload values.
function C:inspectGMCP(overview)
  local found, visited, examined, depthLimited = {}, {}, 0, false
  local function relevant(name)
    name = name:lower()
    for _, term in ipairs({"resource", "price", "tax", "market", "cargo"}) do
      if name:find(term, 1, true) then return true end
    end
  end
  local function walk(t, path, depth)
    if type(t) ~= "table" or visited[t] or examined >= 10000 then return end
    if depth > 8 then depthLimited = true; return end
    visited[t] = true
    for k, value in pairs(t) do
      examined = examined + 1
      if examined > 10000 then return end
      if type(k) == "string" then
        local field = path .. "[" .. string.format("%q", k):gsub("[%c]", " ") .. "]"
        if relevant(k) and #found < 40 then found[#found + 1] = field .. " (" .. type(value) .. ")" end
        walk(value, field, depth + 1)
      elseif type(k) == "number" then walk(value, path .. "[" .. k .. "]", depth + 1) end
    end
  end
  walk(gmcp or {}, "gmcp", 0)
  table.sort(found)
  local state, config = self:uiState(), self:displayConfig()
  state.fields = found; state.depthLimited = depthLimited or examined >= 10000 or #found >= 40
  if overview then state.events = keys(self.gmcpEvents); state.cachePath = cachePath end
  config.title = overview and "DIAGNOSTICS" or "GMCP FIELDS"; self.currentMenu = "diagnostics"
  self:render(UI.diagnostics(state, config))
end

function C:probe(stop)
  if stop then
    cancel("probeTimer"); self.probing = false
    local state, config = self:uiState(), self:displayConfig()
    state.events = keys(self.gmcpEvents); config.title = "GMCP EVENTS"; self.currentMenu = "diagnostics"
    self:render(UI.diagnostics(state, config)); return
  end
  cancel("probeTimer"); self.probing = true; self.gmcpEvents = {}
  self.probeTimer = tempTimer(60, function() self.probeTimer = nil; self:probe(true) end)
  msg("Watching GMCP event names for 60 seconds. This probe does not collect prices; use Scan to capture showplanet resource text. A resource query may produce no GMCP events.", "info",
    {{text = "Stop probe", command = "probe stop"}}, "GMCP probe started")
end

function C:command(args)
  args = trim(args or "")
  local verb, rest = args:match("^(%S+)%s*(.-)$")
  verb = (verb or "home"):lower(); rest = rest or ""
  local function resultCount(text)
    if text == "" then return 10 end
    local n = text:match("^%d+$") and tonumber(text)
    if n and n >= 1 and n <= 100 then return n end
    msg("Choose a result count from 1 to 100.", "error", {{text = "Help", command = "help"}})
  end
  if verb == "home" or verb == "help" or verb == "settings" or verb == "status" or verb == "planets" then self:showMenu(verb)
  elseif verb == "scan" then self:scan(rest)
  elseif verb == "stop" then
    self:stop(self.active and "Scan stopped; completed quotes retained." or "No scan is running. Saved quotes are available.")
  elseif verb == "routes" then
    local limit = resultCount(rest); if limit then self:showRoutes(false, limit) end
  elseif verb == "loops" then
    local selection, countText = rest:match("^(%S+)%s*(.-)$")
    local stops = selection and tonumber(selection) or nil
    if selection and selection:lower() ~= "mixed" and stops ~= 2 and stops ~= 3 and stops ~= 4 then
      msg("Use cargoscan loops [2|3|4|mixed] [count]. Default: mixed 2-3 planet loops.", "error",
        {{text = "Mixed loops", command = "loops"}, {text = "3 planets", command = "loops 3"}}); return
    end
    local limit = resultCount(countText or "")
    if limit then self:showRoutes(true, limit, stops) end
  elseif verb == "show" then self:showDetail(rest)
  elseif verb == "gmcp" or verb == "diagnostics" then self:inspectGMCP(verb == "diagnostics")
  elseif verb == "probe" then
    if rest ~= "" and rest:lower() ~= "stop" then
      msg("Use cargoscan probe to start, or cargoscan probe stop to finish.", "error"); return
    end
    self:probe(rest:lower() == "stop")
  elseif verb == "cargocapacity" or verb == "units" then self:setCapacity(rest)
  elseif verb == "age" then
    if rest == "" then self:showMenu("settings"); return end
    local n = tonumber(rest)
    if n and n >= 1 and n <= 1440 then
      self.maxAgeSeconds = n * 60; self:settingsChanged("Price age limit updated to " .. n .. " minutes.")
    else msg("Use cargoscan age <1..1440 minutes>.", "error", {{text = "Settings", command = "settings"}}) end
  elseif verb == "sort" then
    if rest == "" then self:showMenu("settings"); return end
    rest = rest:lower()
    if rest == "distance" or rest == "margin" then
      self.sort = rest; self:settingsChanged(rest == "distance" and "Ranking by profit per distance." or "Ranking by total profit.")
    else msg("Use cargoscan sort distance or cargoscan sort margin.", "error", {{text = "Settings", command = "settings"}}) end
  elseif verb == "output" then
    if rest == "" then self:showMenu("settings"); return end
    rest = rest:lower()
    if rest == "compact" or rest == "full" then
      self.scanOutput = rest
      msg(rest == "compact" and "Compact scan output enabled." or "Full game responses enabled during scans.", "success")
      self:showMenu("settings")
    else msg("Use cargoscan output compact or cargoscan output full.", "error", {{text = "Settings", command = "settings"}}) end
  else
    msg("Unknown command: " .. verb .. ". Open Help for the command list.", "error",
      {{text = "Home", command = "home"}, {text = "Help", command = "help"}})
  end
end

function C:destroy()
  self:stop(); cancel("probeTimer"); self.probing = false
  if self.alias then killAlias(self.alias); self.alias = nil end
  for _, id in ipairs(self.handlers) do killAnonymousEventHandler(id) end
  self.handlers = {}
end
local function handler(event, fn) C.handlers[#C.handlers + 1] = registerAnonymousEventHandler(event, fn) end
handler("sysDisconnectionEvent", function() if C.active then C:fail("disconnected") end end)
handler("sysDataSendRequest", function(_, command)
  if C.expectedCommand and command == C.expectedCommand then C.expectedCommand = nil; return end
  if C.active then C:fail("another command was sent while scanning") end
end)
handler("*", function(event)
  if C.probing and type(event) == "string" and event:match("^gmcp%.") then C.gmcpEvents[event] = true end
end)
handler("sysUninstallPackage", function(_, name)
  if name == "lotj-cargoscanner" then C:destroy(); LotJCargoScanner = nil end
end)
handler("sysExitEvent", function() C:destroy() end)
C.alias = tempAlias("^cargoscan(?:\\s+(.*))?$", function() C:command(matches[2] or "") end)
C:load()
C:loadCapacity()
msg("Cargo scanner " .. C.version .. " ready. Type cargoscan to open the menu.", "success",
  {{text = "Open menu", command = "home"}, {text = "View loops", command = "loops"}})
