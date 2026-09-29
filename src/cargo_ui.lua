-- Console menus return literal text and actions for the adapter.
local UI = {}

local function finite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge and n or nil
end
local function plain(s) return tostring(s == nil and "?" or s):gsub("[%z\1-\31\127]", " ") end
local function length(s) return select(2, s:gsub("[^\128-\191]", "")) end
local function prefix(s, count)
  local i, seen = 1, 0
  while i <= #s and seen < count do
    i, seen = i + 1, seen + 1
    while i <= #s and s:byte(i) >= 128 and s:byte(i) <= 191 do i = i + 1 end
  end
  return s:sub(1, i - 1)
end
local function width(config)
  return math.max(40, math.min(100, math.floor(finite(config and config.width) or 96)))
end
local function num(n, decimals)
  if not finite(n) then return "?" end
  local value = string.format("%." .. (decimals or 0) .. "f", n)
  local sign, whole, fraction = value:match("^(-?)(%d+)(.*)$")
  whole = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return sign .. whole .. fraction
end
local function coordinate(n)
  if not finite(n) then return "?" end
  return num(n, n % 1 == 0 and 0 or 2)
end
local function pad(text, columns, right)
  text = plain(text)
  local spaces = string.rep(" ", math.max(0, columns - length(text)))
  return right and (spaces .. text) or (text .. spaces)
end
local function segment(text, color, action)
  local out = {text = plain(text), color = color or "text"}
  if action then
    if action.command then out.command = plain(action.command) end
    if action.fill then out.fill = plain(action.fill) end
    if action.hint then out.hint = plain(action.hint) end
  end
  return out
end
local function add(lines, text, color) lines[#lines + 1] = {segment(text, color)} end
local function blank(lines) if #lines == 0 or #lines[#lines] > 0 then lines[#lines + 1] = {} end end
local function wrapped(lines, text, columns, color, indent, action)
  local rest, pad = plain(text), indent or ""
  local available = math.max(1, columns - length(pad))
  repeat
    local part, nextRest = rest, ""
    if length(rest) > available then
      part = prefix(rest, available)
      local split = part:match("^.*() ")
      if split and split > 1 then
        part, nextRest = rest:sub(1, split - 1), rest:sub(split + 1):gsub("^ +", "")
      else
        nextRest = rest:sub(#part + 1)
      end
    end
    lines[#lines + 1] = {segment(pad, color), segment(part, color, action)}
    rest = nextRest
  until rest == ""
end
local function title(lines, label, state, columns)
  blank(lines)
  wrapped(lines, "CARGO / " .. label, columns, "title")
  if state and state.version and label == "HOME" then
    wrapped(lines, "Trade planner  /  v" .. plain(state.version), columns, "muted")
  end
  add(lines, string.rep("-", columns), "muted")
end
local function section(lines, label, columns)
  blank(lines)
  wrapped(lines, label:upper(), columns, "accent")
end
local function actions(lines, choices, columns)
  local line, used = {}, 0
  for _, choice in ipairs(choices or {}) do
    local label = plain(choice.text or choice.label or "Open")
    if choice.command~=nil then label=label..": cargoscan"..(choice.command~='' and (' '..choice.command) or '') end
    label='['..label..']' 
    if used > 0 and used + 2 + length(label) > columns then
      lines[#lines + 1], line, used = line, {}, 0
    end
    if length(label) > columns then
      if used > 0 then lines[#lines + 1], line, used = line, {}, 0 end
      wrapped(lines, label, columns, choice.color or "rank", nil, choice)
    else
      if used > 0 then line[#line + 1] = segment("  ", "muted"); used = used + 2 end
      line[#line + 1] = segment(label, choice.color or "rank", choice)
      used = used + length(label)
    end
  end
  if #line > 0 then lines[#lines + 1] = line end
end
local function button(text, command, hint) return {text = text, command = command, hint = hint} end
local function capacityButton()
  return {text = "Set capacity", fill = "cargoscan cargocapacity ", hint = "Enter your ship's cargo capacity, then press Enter."}
end
local function footer(lines, columns, extras)
  blank(lines)
  add(lines, string.rep("-", columns), "muted")
  local choices = {}
  for _, choice in ipairs(extras or {}) do choices[#choices + 1] = choice end
  choices[#choices + 1] = button("Home", "", "Open the cargo planner.")
  actions(lines, choices, columns)
  blank(lines)
end
local function count(state, name) return math.max(0, math.floor(finite(state[name]) or 0)) end
local function capacityText(state)
  if state.capacitySet then
    local units = finite(state.units) or 1
    return num(units) .. (units == 1 and " unit per leg" or " units per leg")
  end
  return "Not set; profit shown per unit"
end
local function ageText(minutes)
  if not finite(minutes) or minutes < 0 then return "unknown age" end
  if minutes < 1 then return "just now" end
  if minutes < 60 then return num(math.floor(minutes)) .. " min ago" end
  if minutes < 1440 then return num(math.floor(minutes / 60)) .. " hr ago" end
  return num(math.floor(minutes / 1440)) .. " days ago"
end
local function freshness(value)
  if value == "fresh" then return "Fresh", "positive" end
  if value == "stale" then return "Stale", "warning" end
  if value == "failed" then return "Scan failed", "error" end
  return "Not scanned", "muted"
end
local function overview(lines, state, columns)
  wrapped(lines, "Prices  " .. num(count(state, "freshCount")) .. " fresh / " .. num(count(state, "planetCount")) .. " planets", columns, "positive")
  local concerns = {}
  if count(state, "staleCount") > 0 then concerns[#concerns + 1] = num(state.staleCount) .. " stale" end
  if count(state, "missingCount") > 0 then concerns[#concerns + 1] = num(state.missingCount) .. " not scanned" end
  if count(state, "failedCount") > 0 then concerns[#concerns + 1] = num(state.failedCount) .. " failed" end
  if #concerns > 0 then wrapped(lines, "        " .. table.concat(concerns, " / "), columns, "warning") end
  wrapped(lines, "Hold    " .. capacityText(state), columns, state.capacitySet and "text" or "warning")
  wrapped(lines, "Rank    " .. (state.sort == "margin" and "Highest profit" or "Best profit per distance"), columns, "text")
  wrapped(lines, "Use     Prices no older than " .. num(finite(state.maxAgeMinutes) or 60) .. " min", columns, "muted")
end

function UI.home(state, config)
  state, config = state or {}, config or {}
  local lines, columns = {}, width(config)
  title(lines, "HOME", state, columns)
  overview(lines, state, columns)
  section(lines, "Next step", columns)
  if state.active then
    wrapped(lines, "Scanning " .. plain(state.current or "planets") .. ". " .. num(count(state, "completed")) .. " of " .. num(count(state, "total")) .. " complete.", columns, "accent")
    actions(lines, {button("Stop scan", "stop", "Stop scanning and keep completed prices."), button("Status", "status")}, columns)
  elseif count(state, "planetCount") == 0 then
    wrapped(lines, "No planets loaded. Open the LOTJ UI galaxy map and let it load, then Refresh. If still empty, open Diagnostics.", columns, "warning")
    actions(lines, {button("Refresh", ""), button("Diagnostics", "diagnostics")}, columns)
  elseif count(state, "freshCount") < 2 then
    wrapped(lines, "Scan planet prices to find cargo routes.", columns, "text")
    actions(lines, {button("Scan all planets", "scan", "Look up resource prices one planet at a time.")}, columns)
  elseif not state.capacitySet then
    wrapped(lines, "Set your cargo capacity to see profit for a full hold.", columns, "text")
    actions(lines, {capacityButton()}, columns)
  elseif count(state, "staleCount") + count(state, "missingCount") + count(state, "failedCount") > 0 then
    wrapped(lines, "Some prices need refreshing. You can browse routes from fresh prices now.", columns, "text")
    actions(lines, {button("Refresh prices", "scan"), button("View loops", "loops")}, columns)
  else
    wrapped(lines, "Prices are ready. Compare loops or browse one-way routes.", columns, "text")
    actions(lines, {button("View loops", "loops"), button("View routes", "routes")}, columns)
  end
  section(lines, "Explore", columns)
  actions(lines, {button("Loops", "loops", "Rank return trips through 2 or 3 planets."), button("Routes", "routes", "Rank individual cargo legs."), button("Scan", "scan"), button("Status", "status"), button("Planets", "planets"), button("Settings", "settings"), button("Help", "help")}, columns)
  blank(lines)
  wrapped(lines, "Profit estimates use listed prices, before tax and fuel.", columns, "muted")
  blank(lines)
  return lines
end

local function helpEntry(lines, columns, command, description)
  local verb = command:match("^%S+")
  local action = command == verb and {command = command, hint = "Run cargoscan " .. command .. "."}
    or {fill = "cargoscan " .. verb .. " ", hint = "Fill in the command, then press Enter."}
  wrapped(lines, "cargoscan "..command.."  - "..description, columns, "rank", "  ", action)
end
function UI.help(state, config)
  state, config = state or {}, config or {}
  local lines, columns = {}, width(config)
  title(lines, "HELP", state, columns)
  wrapped(lines, "Setup and scan clicks fill input; Enter runs the command.", columns, "muted")
  section(lines, "Find a run", columns)
  helpEntry(lines, columns, "scan [planet]", "Refresh prices")
  helpEntry(lines, columns, "loops [2|3|4|mixed] [count]", "Return trips")
  helpEntry(lines, columns, "routes [count]", "One-way routes")
  helpEntry(lines, columns, "show <number>", "Route details")
  section(lines, "Tune your results", columns)
  helpEntry(lines, columns, "cargocapacity <number>", "Hold size")
  helpEntry(lines, columns, "sort distance|margin", "Ranking")
  helpEntry(lines, columns, "age <minutes>", "Maximum price age")
  section(lines, "Manage the scanner", columns)
  helpEntry(lines, columns, "status", "Price freshness")
  helpEntry(lines, columns, "planets", "Planet list")
  helpEntry(lines, columns, "stop", "Stop scanning")
  helpEntry(lines, columns, "settings", "Edit setup")
  helpEntry(lines, columns, "output compact|full", "Scan output")
  helpEntry(lines, columns, "diagnostics", "Data sources")
  wrapped(lines, "Profit excludes tax and fuel. Prices come from your own scans.", columns, "muted", "  ")
  footer(lines, columns, {button("Settings", "settings"), button("Scan prices", "scan")})
  return lines
end

function UI.settings(state, config)
  state, config = state or {}, config or {}
  local lines, columns = {}, width(config)
  title(lines, "SETTINGS", state, columns)
  section(lines, "Cargo capacity", columns)
  wrapped(lines, capacityText(state), columns, state.capacitySet and "positive" or "warning")
  wrapped(lines, "Used on every leg. Your cargo capacity is saved between sessions.", columns, "muted")
  actions(lines, {capacityButton()}, columns)
  section(lines, "Route ranking", columns)
  wrapped(lines, state.sort == "margin" and "Current: highest total profit" or "Current: best profit per distance", columns, "text")
  actions(lines, {{text = "Profit / distance", command = "sort distance", color = state.sort ~= "margin" and "positive" or "rank"}, {text = "Total profit", command = "sort margin", color = state.sort == "margin" and "positive" or "rank"}}, columns)
  section(lines, "Price freshness", columns)
  wrapped(lines, "Use prices no older than " .. num(finite(state.maxAgeMinutes) or 60) .. " minutes.", columns, "text")
  wrapped(lines, "Older prices remain saved but are excluded from route results.", columns, "muted")
  local presets = {}
  for _, minutes in ipairs({15, 30, 60, 120}) do presets[#presets + 1] = {text = minutes .. " min", command = "age " .. minutes, color = state.maxAgeMinutes == minutes and "positive" or "rank"} end
  presets[#presets + 1] = {text = "Custom", fill = "cargoscan age ", hint = "Enter the maximum price age in minutes, then press Enter."}
  actions(lines, presets, columns)
  section(lines, "Scan output", columns)
  wrapped(lines, state.scanOutput == "full" and "Current: full planet responses" or "Current: compact scan progress", columns, "text")
  wrapped(lines, "Compact hides recognized scanner response lines. Other output and errors remain visible.", columns, "muted")
  actions(lines, {{text = "Compact", command = "output compact", color = state.scanOutput ~= "full" and "positive" or "rank"}, {text = "Full", command = "output full", color = state.scanOutput == "full" and "positive" or "rank"}}, columns)
  blank(lines)
  wrapped(lines, "Sorting, price age, and scan output reset when the package reloads.", columns, "muted")
  footer(lines, columns, {button("Loops", "loops"), button("Routes", "routes")})
  return lines
end

function UI.status(state, config)
  state, config = state or {}, config or {}
  local lines, columns = {}, width(config)
  local markets, seen = {}, {}
  for _, market in ipairs(state.markets or {}) do
    markets[#markets + 1] = market
    seen[plain(market.name):lower()] = true
  end
  for _, planet in ipairs(state.planets or {}) do
    if not seen[plain(planet.name):lower()] then
      markets[#markets + 1] = {name = planet.name, state = planet.state or "unknown", ageMinutes = planet.ageMinutes}
      seen[plain(planet.name):lower()] = true
    end
  end
  title(lines, "PRICE STATUS", state, columns)
  overview(lines, state, columns)
  if state.active then
    blank(lines)
    wrapped(lines, "Scanning " .. plain(state.current or "planets") .. "  /  " .. num(count(state, "completed")) .. " of " .. num(count(state, "total")) .. " complete", columns, "accent")
  end
  section(lines, "Planet prices", columns)
  if #markets == 0 then
    wrapped(lines, "No planet prices saved. Run a scan to collect them.", columns, "muted")
  elseif columns >= 76 then
    add(lines, pad("PLANET", columns - 46) .. "  " .. pad("STATUS", 11) .. "  " .. pad("PRICES", 7, true)
      .. "  " .. pad("UPDATED", 12) .. "  " .. pad("TAX RATE", 8, true), "muted")
  end
  for _, market in ipairs(markets) do
    local label, color = freshness(market.state)
    local resourceCount = finite(market.resources) or 0
    local tax = finite(market.taxRate) and (num(market.taxRate, 2) .. "% tax") or "tax unknown"
    local action = {command = "scan " .. plain(market.name), hint = "Refresh resource prices for " .. plain(market.name) .. "."}
    local name, amount, age = plain(market.name), num(resourceCount), ageText(market.ageMinutes)
    if columns >= 76 and length(name) <= columns - 46 and length(amount) <= 7 and length(age) <= 12 then
      lines[#lines + 1] = {segment(pad(name, columns - 46), "text", action), segment("  " .. pad(label, 11), color),
        segment("  " .. pad(amount, 7, true) .. "  " .. pad(age, 12), "muted"),
        segment("  " .. pad(finite(market.taxRate) and (num(market.taxRate, 2) .. "%") or "?", 8, true), "muted")}
    else
      wrapped(lines, name, columns, "text", nil, action)
      wrapped(lines, label .. "  /  " .. amount .. " resources  /  " .. age .. "  /  " .. tax, columns, color, "  ")
    end
  end
  blank(lines)
  wrapped(lines, "Click a planet name to refresh its prices.", columns, "muted")
  footer(lines, columns, {state.active and button("Stop scan", "stop") or button("Scan all", "scan"), button("Loops", "loops")})
  return lines
end

function UI.planets(state, config)
  state, config = state or {}, config or {}
  local lines, columns = {}, width(config)
  title(lines, "PLANETS", state, columns)
  wrapped(lines, num(count(state, "planetCount")) .. " known planets  /  galaxy map coordinates", columns, "muted")
  blank(lines)
  if #(state.planets or {}) == 0 then
    wrapped(lines, "No planets loaded. Open the LOTJ UI galaxy map and let it load, then Refresh. If still empty, open Diagnostics.", columns, "warning")
  end
  for index, planet in ipairs(state.planets or {}) do
    local label, color = freshness(planet.state)
    wrapped(lines, num(index) .. "  " .. plain(planet.name), columns, "text", nil, {command = "scan " .. plain(planet.name), hint = "Refresh resource prices for " .. plain(planet.name) .. "."})
    wrapped(lines, plain(planet.system) .. "  /  x " .. coordinate(planet.galaxyX) .. ", y " .. coordinate(planet.galaxyY), columns, "muted", "   ")
    wrapped(lines, label .. (planet.ageMinutes and ("  /  " .. ageText(planet.ageMinutes)) or ""), columns, color, "   ")
  end
  if #(state.planets or {}) > 0 then
    blank(lines)
    wrapped(lines, "Click a planet name to scan its resource prices.", columns, "muted")
  end
  local choices = #(state.planets or {}) == 0
    and {button("Refresh", "planets"), button("Diagnostics", "diagnostics")}
    or {button("Scan all", "scan")}
  choices[#choices + 1] = button("Price status", "status")
  footer(lines, columns, choices)
  return lines
end

function UI.diagnostics(state, config)
  state, config = state or {}, config or {}
  local lines, columns = {}, width(config)
  title(lines, plain(config.title or "DIAGNOSTICS"), state, columns)
  wrapped(lines, "Use cargoscan scan [planet] to capture prices and tax rates from showplanet resources.", columns, "text")
  wrapped(lines, "Probe only observes GMCP events. No event after showplanet does not mean scanning is broken.", columns, "muted")
  section(lines, "Planet catalog", columns)
  wrapped(lines, "Source: " .. plain(state.planetSource or "Unavailable"), columns, "text")
  wrapped(lines, "Known planets: " .. num(count(state, "planetCount")), columns, "text")
  for _, source in ipairs(state.catalogSources or {}) do
    wrapped(lines, plain(source.name) .. ": " .. plain(source.dataType)
      .. " / " .. num(count(source, "systemCount")) .. " systems"
      .. " / " .. num(count(source, "planetCount")) .. " planets", columns, "muted", "  ")
  end
  if config.title ~= "GMCP EVENTS" then
    section(lines, "GMCP fields", columns)
    if #(state.fields or {}) == 0 then wrapped(lines, "No matching price, tax, or resource fields in the current GMCP cache.", columns, "muted") end
    for _, field in ipairs(state.fields or {}) do wrapped(lines, field, columns, "text", "  ") end
    if state.depthLimited then wrapped(lines, "Inspection reached its size or depth limit; this list may be incomplete.", columns, "warning") end
    wrapped(lines, "These are field names, not proof of resource data. Missing fields do not rule out server support.", columns, "muted")
  end
  if config.title ~= "GMCP FIELDS" then
    section(lines, state.probing and "Live probe running" or "Last probe events", columns)
    if #(state.events or {}) == 0 then wrapped(lines, state.probing and "Listening for incoming GMCP events..." or "No GMCP events recorded.", columns, "muted") end
    for _, event in ipairs(state.events or {}) do wrapped(lines, event, columns, "text", "  ") end
  end
  if state.cachePath then
    section(lines, "Saved prices", columns)
    wrapped(lines, state.cachePath, columns, "muted")
  end
  footer(lines, columns, {button("Inspect GMCP", "gmcp"), state.probing and button("Stop probe", "probe stop") or button("Start probe", "probe"), button("Status", "status")})
  return lines
end

function UI.notice(message, config)
  config = config or {}
  local lines, columns = {}, width(config)
  local kind = config.kind or "info"
  local color = kind == "error" and "error" or kind == "warning" and "warning" or kind == "success" and "positive" or "accent"
  local label = config.title and plain(config.title) or "CARGO"
  if length(label) > 18 then label = prefix(label, 18) end
  local textLines = {}
  wrapped(textLines, message, columns - length(label) - 2, kind == "error" and "error" or "text")
  for i, line in ipairs(textLines) do
    local parts = {segment(i == 1 and (label .. "  ") or string.rep(" ", length(label) + 2), color)}
    for _, part in ipairs(line) do parts[#parts + 1] = part end
    lines[#lines + 1] = parts
  end
  if config.actions then actions(lines, config.actions, columns) end
  return lines
end

function UI.progress(state, config)
  state, config = state or {}, config or {}
  local lines, columns = {}, width(config)
  local complete, total = count(state, "completed"), count(state, "total")
  local ratio = total > 0 and math.min(1, complete / total) or 0
  local barWidth = columns >= 64 and 20 or 10
  local filled = math.floor(ratio * barWidth)
  local heading = "SCAN  " .. num(complete) .. "/" .. num(total) .. " [" .. string.rep("=", filled) .. string.rep(".", barWidth - filled) .. "] " .. math.floor(ratio * 100) .. "%"
  local detail
  if state.current then
    detail = (finite(state.resources) and "Saved " or "Looking up ") .. plain(state.current)
    if finite(state.resources) then detail = detail .. " / " .. num(state.resources) .. " prices" end
  end
  if detail and length(heading) + length(detail) + 2 <= columns then
    lines[#lines + 1] = {segment(heading, "accent"), segment("  " .. detail, "text")}
  else
    wrapped(lines, heading, columns, "accent")
    if detail then wrapped(lines, detail, columns, "muted", "      ") end
  end
  return lines
end

return UI
