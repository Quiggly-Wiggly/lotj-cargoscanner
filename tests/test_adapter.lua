-- Fictional worlds and synthetic prices; not a game-data export.
-- Behavioral smoke tests of the packaged script with simulated Mudlet events.
local checks = 0
local function check(value, why) checks = checks + 1; assert(value, why) end
local nativeRename = os.rename
local overwriteRefusals = 0
if TEST_WINDOWS_RENAME then
  -- Windows CRT rename refuses to replace a destination that already exists.
  os.rename = function(source, destination)
    local existing = io.open(destination, "rb")
    if existing then
      existing:close(); overwriteRefusals = overwriteRefusals + 1
      return nil, source .. ": File exists", 17
    end
    return nativeRename(source, destination)
  end
end
local sent, output, timers, handlers, triggers, aliases = {}, {}, {}, {}, {}, {}
local links, colorCalls, resetCalls = {}, 0, 0
local sentEcho, deleted, filled, columns = {}, {}, {}, 96
local seq = 0
local function id() seq = seq + 1; return seq end
function echo(text) output[#output + 1] = text end
function getColumnCount() return columns end
function printCmdLine(text) filled[#filled + 1] = text end
function deleteLine() deleted[#deleted + 1] = line end
function deselect() end
function setFgColor(r, g, b)
  assert(type(r) == "number" and type(g) == "number" and type(b) == "number")
  colorCalls = colorCalls + 1
end
function resetFormat() resetCalls = resetCalls + 1 end
function echoLink(text, callback, hint, keepFormat)
  assert(type(callback) == "function" and type(hint) == "string" and keepFormat == true)
  links[#links + 1] = {text=text, callback=callback, hint=hint}
  echo(text)
end
function getMudletHomeDir() return TEST_DIR end
function getConnectionInfo() return "test.invalid", 5656, true end
function tempTimer(delay, fn) local n = id(); timers[n] = {delay=delay, fn=fn}; return n end
function killTimer(n) timers[n] = nil end
function tempRegexTrigger(pattern, fn) local n = id(); triggers[n] = fn; return n end
function killTrigger(n) triggers[n] = nil end
function tempAlias(pattern, fn) local n = id(); aliases[n] = fn; return n end
function killAlias(n) aliases[n] = nil end
function registerAnonymousEventHandler(event, fn) local n = id(); handlers[n] = {event=event,fn=fn}; return n end
function killAnonymousEventHandler(n) handlers[n] = nil end
local function event(name, ...)
  local copy = {}; for _, h in pairs(handlers) do copy[#copy + 1] = h end
  for _, h in ipairs(copy) do if h.event == name or h.event == "*" then h.fn(name, ...) end end
end
function send(command, showEcho)
  event("sysDataSendRequest", command); sent[#sent + 1] = command; sentEcho[#sent] = showEcho
end
local function fire(n)
  local timer = assert(timers[n], "missing timer " .. tostring(n)); timers[n] = nil; timer.fn()
end
local function feed(filename)
  for raw in io.lines(filename) do
    line = raw
    local copy = {}; for _, fn in pairs(triggers) do copy[#copy + 1] = fn end
    for _, fn in ipairs(copy) do fn() end
  end
end
local function hasOutput(fragment) return table.concat(output, "\n"):find(fragment, 1, true) ~= nil end
local function findLink(fragment)
  for i = #links, 1, -1 do if links[i].text:find(fragment, 1, true) then return links[i].callback end end
  error("missing link: " .. fragment)
end
gmcp = {Galaxy = {Systems = {
  ["Zeta System"] = {x=0,y=0,Zeta={x=0,y=0,z=0,government="Example Group"}},
  ["Betan System"] = {x=23,y=3,Beta={x=1567,y=-10000,z=21812,government="Example Group"}},
  ["Empty System"] = {x=39,y=30},
}}}

assert(loadstring(PACKAGE_CODE))()
local c = LotJCargoScanner
check(#sent == 0, "loading must not send game commands")
c:command("")
check(#sent == 0 and #links > 0, "home has local navigation without network commands")
c:command("scan")
check(#sent == 1 and sent[1] == 'showplanet "Beta" resources', "first sequential query")
check(sentEcho[1] == false, "compact scans do not echo every outgoing lookup")
check(c.active and c.timeoutTimer and not c.nextTimer, "wait for response before next query")
local activeTimer = c.timeoutTimer
c:command("status"); c:command("help")
check(c.active and c.timeoutTimer == activeTimer and #sent == 1, "viewing menus during scan preserves capture")
feed("tests/fixtures/beta-resources.txt")
check(c.markets.beta.resources["Medical supplies"] == 177.30, "multiword resource captured")
check(#deleted > 0, "compact mode gags parsed market response lines")
for _, raw in ipairs(deleted) do
  check(not raw:find("You use the datapad", 1, true) and not raw:find("Health", 1, true), "compact capture keeps unrelated output visible")
end
check(c.nextTimer and #sent == 1, "next query must be paced")
fire(c.nextTimer)
check(#sent == 2 and sent[2] == 'showplanet "Zeta" resources', "second sequential query")
feed("tests/fixtures/zeta-resources.txt")
fire(c.nextTimer)
check(not c.active and not next(triggers), "clean up after scan")
check(#c.lastRows == 1 and math.abs(c.lastRows[1].margin - 14.88) < 0.00001, "scan shows closed loop ranking")
check(colorCalls > 0 and colorCalls == resetCalls, "colored output resets format after every segment")
check(#links > 0, "summary ranks are clickable")
local firstLoopLink = findLink("01")
c:command("show 1")
check(hasOutput("Common metals") and hasOutput("Electronics"), "detail shows cargo on each leg")
c:command("cargocapacity 1000")
check(c.capacitySet and c.units == 1000, "explicit cargo capacity accepted")
check(c.lastRows[1].units == 1000 and c.lastRows[1].capacitySet, "capacity immediately recalculates current results")
c:command("loops")
check(math.abs(c.lastRows[1].loadMargin - 14880) < 0.00001, "two profitable loads in loop")
check(hasOutput("before tax and fuel"), "profit basis is explicit")
check(hasOutput("Show the route details with cargoscan show <number>."), "clear route detail command")
check(math.abs(c.lastRows[1].totalDistance - 2 * math.sqrt(538)) < 0.00001, "complete loop uses system distance")
local capturedSnapshot
local originalDetail = c.showDetail
c.showDetail = function(self, row) capturedSnapshot = row end
firstLoopLink()
c.showDetail = originalDetail
check(capturedSnapshot.units == 1, "old report link retains its original row instead of a new ranking")

-- Reload both data and script. No duplicate triggers or aliases, no auto-scan.
local oldAlias = c.alias
assert(loadstring(PACKAGE_CODE))()
c = LotJCargoScanner
check(aliases[oldAlias] == nil, "old alias removed on package reload")
check(#sent == 2, "reload sends nothing")
check(c.markets.zeta and c.markets.beta, "saved quotes restore")
check(c.markets.zeta.resources.Electronics == 130, "restored quote value")
check(c.markets.beta.observedAt > 0, "timestamps restore")
check(c.capacitySet and c.units == 1000, "capacity persists across package reload")
local restoredDetail = c.showDetail
local restoredSnapshot
c.showDetail = function(self, row) restoredSnapshot = row end
firstLoopLink()
c.showDetail = restoredDetail
check(restoredSnapshot and restoredSnapshot.units == 1,
  "old rank links use the current package while retaining the original quote/capacity snapshot")
for _, invalid in ipairs({"0", "-10", "1.5", "NaN", "100000001", "word"}) do c:command("cargocapacity " .. invalid) end
check(c.units == 1000, "invalid capacity does not change current setting")
c:command("units 500")
check(c.units == 500 and c.capacitySet, "old units command remains a capacity alias")
c:command("cargocapacity 1")
check(c.capacitySet and c.units == 1, "one-unit ship capacity is different from unset capacity")
c:command("cargocapacity 1000")

-- Incomplete/foreign output is never assigned to the pending planet.
c:command("scan Beta")
feed("tests/fixtures/zeta-resources.txt")
check(not c.active and c.failed.beta, "mismatched response stops capture")
check(c.markets.beta.resources.Electronics == 137.02, "old quote never overwritten by mismatch")
output = {}; c:command("routes")
check(#c.lastRows == 0, "failed refresh excluded from rankings")

c:command("scan Beta")
fire(c.timeoutTimer)
check(not c.active and not c.nextTimer, "timeout stops before further commands")
c:command("scan Beta")
event("sysDisconnectionEvent")
check(not c.active and not c.timeoutTimer, "disconnect cancels pending work")
c:command("scan Beta")
event("sysDataSendRequest", "look")
check(not c.active and not next(triggers), "other command stops scan without blocking command")
c:command("scan Beta")
feed("tests/fixtures/beta-resources.txt")
local pace = c.nextTimer
event("sysDataSendRequest", "look")
check(not timers[pace] and not c.active, "cancel during pacing prevents next query")
check(not c.failed.beta, "interrupt between queries keeps the completed quote eligible")
c:command("scan Beta")
c:command("stop")
check(not c.active and not c.timeoutTimer, "manual stop cancels outstanding request")

-- Probe only observes event names, sends nothing, and stops automatically.
local before = #sent
c:command("probe")
event("gmcp.Galaxy.Markets")
event("sysWindowResizeEvent")
fire(c.probeTimer)
check(c.gmcpEvents["gmcp.Galaxy.Markets"] and not c.gmcpEvents.sysWindowResizeEvent, "GMCP event probe")
check(not c.probing and #sent == before, "probe expiration sends nothing")

-- Default freshness threshold really excludes old data.
c.markets.zeta.observedAt = os.time() - 3601
output = {}; c:command("routes")
check(#c.lastRows == 0, "stale quotes excluded")
c:command("age 120")
output = {}; c:command("routes")
check(#c.lastRows == 4 and math.abs(c.lastRows[1].margin - 7.86) < 0.00001, "explicit max-age override")

-- Synthetic padded-price regression: short prices are padded before the closing ')'.
gmcp.Galaxy.Systems["Test System"] = {
  x = -12, y = -7, ["Test Moon"] = {x=0, y=0, z=0, government="Example Neutral"},
}
c:command("scan Test Moon")
check(sent[#sent] == 'showplanet "Test Moon" resources', "multiword planet query remains quoted")
feed("tests/fixtures/test-moon-resources.txt")
check(c.active and c.nextTimer and not c.failed["test moon"], "padded price does not stop scan")
check(c.markets["test moon"].resources.Water == 106.16, "padded price captured as numeric quote")
fire(c.nextTimer)
check(not c.active, "Test Moon scan completes normally")
assert(loadstring(PACKAGE_CODE))()
c = LotJCargoScanner
check(c.version == "0.4.0" and c.markets["test moon"].resources.Water == 106.16, "updated package restores existing quote cache")
c.markets.zeta.observedAt = os.time()
c:command("loops 3")
check(#c.lastRows > 0, "three-planet loop command finds circuits")
for _, loop in ipairs(c.lastRows) do
  check(#loop.legs == 3 and loop.path[1] == loop.path[4], "trio includes return to starting planet")
end
c:command("show 1")
check(hasOutput("Test Moon"), "multiword planet in loop detail")
c:command("loops 2 1")
check(#c.lastRows == 1 and #c.lastRows[1].legs == 2, "exact two-stop filter and result count")
c:command("loops")
local hasPair, hasTrio = false, false
for _, loop in ipairs(c.lastRows) do
  hasPair = hasPair or loop.stops == 2; hasTrio = hasTrio or loop.stops == 3
end
check(hasPair and hasTrio, "default compares pairs and trios")
c:command("loops 4")
check(#c.lastRows == 0, "four-stop command does not repeat planets to invent a circuit")
local beforeInvalid = #sent
c:command("loops 9")
check(#sent == beforeInvalid and hasOutput("Use cargoscan loops"), "invalid stop count produces local usage")

-- GMCP inspection is passive and prints field names/types, not payload values.
local beforeGMCP = #sent
output = {}; c:command("gmcp")
check(#sent == beforeGMCP and hasOutput("No matching price, tax, or resource fields"), "missing price fields are reported without requests")
gmcp.Galaxy.Resources = {Zeta = {price = 987654, tax = 15}}
gmcp.Char = {password = "SHOULD_NOT_APPEAR", cargoSecret = "ALSO_PRIVATE"}
gmcp.Galaxy.cycle = gmcp.Galaxy
output = {}; c:command("gmcp")
check(hasOutput('gmcp["Galaxy"]["Resources"]') and hasOutput('(table)'), "candidate resource branch identified")
check(not hasOutput("987654") and not hasOutput("SHOULD_NOT_APPEAR") and not hasOutput("ALSO_PRIVATE"), "diagnostic never prints GMCP payload values")
check(#sent == beforeGMCP, "GMCP diagnostic never sends commands")
local deep = {}; gmcp.Deep = deep
for _ = 1, 12 do deep.child = {}; deep = deep.child end
deep.price = 123
output = {}; c:command("gmcp")
check(hasOutput("Inspection reached its size or depth limit"), "deep GMCP branches report inspection limit")

-- All menus use local callbacks; capacity input is filled without submission.
local beforeMenus = #sent
for _, menu in ipairs({"home", "help", "settings", "status", "planets", "diagnostics"}) do
  output = {}; links = {}; c:command(menu)
  check(hasOutput("CARGO") and #links > 0, menu .. " has a styled header and navigation")
end
check(#sent == beforeMenus, "browsing all menus sends nothing")
c:command("settings")
local originalCapacity = c.units
findLink("capacity")()
check(filled[#filled] == "cargoscan cargocapacity " and #sent == beforeMenus and c.units == originalCapacity,
  "capacity shortcut fills input without submitting or changing value")
c:command("loops")
c:command("settings")
c:command("cargocapacity 2000")
check(c.currentMenu == "settings" and c.lastRows[1].units == 2000,
  "changing capacity in settings keeps settings open and recalculates result snapshots")
c:command("sort margin")
check(c.currentMenu == "settings" and c.sort == "margin", "ranking control keeps settings open")
c:command("age 30")
check(c.currentMenu == "settings" and c.maxAgeSeconds == 1800, "age control keeps settings open")
local priorRows = c.lastRows
for _, bad in ipairs({"routes 0", "routes 101", "routes banana", "loops 3 0", "loops mixed 1.2", "nonesuch", "probe nope"}) do c:command(bad) end
check(c.lastRows == priorRows and #sent == beforeMenus, "invalid commands do not alter results or send game commands")

-- Full output is available; compact output never hides the error that stops a scan.
c:command("output full")
local beforeFull = #deleted
c:command("scan Beta")
check(sentEcho[#sent] == true, "full mode echoes game lookups")
feed("tests/fixtures/beta-resources.txt"); fire(c.nextTimer)
check(#deleted == beforeFull, "full mode leaves every game line visible")
c:command("output compact")
c:command("scan Beta")
local badLine = "Spice ( Price per unit: oops)"
c:onLine("--Planet Data: -----------------")
line = badLine
local beforeBad = #deleted
c:onLine(badLine)
check(not c.active and #deleted == beforeBad, "invalid resource line is never gagged")
local previousSends = #sent
c:command("planets")
findLink("Beta")()
check(#sent==previousSends and not c.active and filled[#filled]:find('scan',1,true),
  "planet scan shortcut only fills input")
c:command(filled[#filled]:gsub('^cargoscan ',''))
check(c.active and #sent == previousSends + 1 and sent[#sent] == 'showplanet "Beta" resources',
  "planet scan shortcut requests exactly the selected planet")
c:command("stop")

-- Narrow menus and the no-link fallback keep literal command text usable.
columns = 42
output = {}; c:command("help")
local physical = table.concat(output)
for row in physical:gmatch("[^\n]+") do check(#row <= 40, "narrow help fits console width") end
columns = 96
local originalLink = echoLink; echoLink = nil
output = {}; c:command("home")
check(hasOutput("CARGO"), "text menus work when clickable links are unavailable")
echoLink = originalLink

-- A working LOTJ UI map may come from its cache while live GMCP is empty.
local liveGMCP = gmcp
local uiBeta = {x=1567, y=-10000, z=21812, government="Example Group", name="Beta"}
local uiSystem = {x=23, y=3, Beta=uiBeta, planet=uiBeta, planets={uiBeta}, name="Beta"}
lotj = {galaxyMap = {systems = {["Betan System"] = uiSystem}}}
gmcp = nil
local beforeCatalog = #sent
check(c:refreshPlanets() == 1 and c.planets.beta and not c.planets.planet,
  "UI cache provides real planets without treating its planet helper as a destination")
check(c.planetSource == "LOTJ UI galaxy map (may be cached)", "fallback source is explicitly labeled")
output = {}; c:command("diagnostics")
check(hasOutput("gmcp.Galaxy.Systems") and hasOutput("lotj.galaxyMap.systems"),
  "diagnostics identify both catalog sources even when live GMCP is absent")
check(c.catalogSources[1].dataType == "nil" and c.catalogSources[1].planetCount == 0
  and c.catalogSources[2].planetCount == 1 and c.catalogSources[2].systemCount == 1,
  "diagnostics distinguish missing live GMCP from an available UI map")
check(#sent == beforeCatalog, "catalog fallback and diagnostics are passive")
c:command("scan")
check(c.active and #c.queue == 1 and sent[#sent] == 'showplanet "Beta" resources',
  "scan works with only the UI map and never queries the synthetic planet helper")
feed("tests/fixtures/beta-resources.txt"); fire(c.nextTimer)
check(not c.active and c.markets.beta.resources.Electronics == 137.02,
  "UI-only scan captures and saves ordinary resource output")
check(uiSystem.planet == uiBeta and uiSystem.planets[1] == uiBeta and uiBeta.name == "Beta",
  "scanner leaves UI catalog objects intact")
for _, unavailable in ipairs({{}, {Galaxy={Systems={}}}, {Galaxy=42}, {Galaxy={Systems="unexpected"}},
  {Galaxy={Systems={["Empty System"]={x=1,y=2}}}}}) do
  gmcp = unavailable
  check(c:refreshPlanets() == 1 and c.planets.beta, "unusable live catalog falls back without throwing")
end
gmcp = {Galaxy = {Systems = {["New System"]={x=8,y=9,Gamma={government="Neutral"}}}}}
check(c:refreshPlanets() == 1 and c.planets.gamma and not c.planets.beta,
  "usable live catalog replaces cached entries instead of merging stale planets")
check(c.planetSource == "GMCP Galaxy.Systems", "live source takes priority")
lotj = nil; gmcp = {}
beforeCatalog = #sent
output = {}; c:command("scan")
check(not c.active and #sent == beforeCatalog and hasOutput("No planets found") and hasOutput("Diagnostics"),
  "missing catalogs produce an actionable error without sending a lookup")
check(c.planetSource == "Unavailable" and not next(c.planets), "missing data clears the old catalog")
lotj = {galaxyMap=false}; gmcp = {Galaxy={Systems=false}}
check(c:refreshPlanets() == 0 and c.catalogSources[1].dataType == "boolean",
  "malformed catalog parents are safe and field types remain accurate")
gmcp = liveGMCP; lotj = nil
c:refreshPlanets()

-- Failed replacements preserve the previous file, including Windows rename semantics.
local quotePath = TEST_DIR .. "/lotj-cargoscanner-quotes.txt"
local capacityPath = TEST_DIR .. "/lotj-cargoscanner-settings.txt"
local function readFile(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("*a"); file:close(); return data
end
local function writeFile(path, data)
  local file = assert(io.open(path, "wb")); assert(file:write(data)); assert(file:close())
end
local function reload()
  assert(loadstring(PACKAGE_CODE))(); c = LotJCargoScanner
end
local function withIOFailure(path, operation, callback)
  local originalOpen = io.open
  local injected = false
  io.open = function(filename, mode)
    local file, err, code = originalOpen(filename, mode)
    if filename ~= path .. ".tmp" or mode ~= "wb" or not file then return file, err, code end
    return {
      write = function(_, data)
        if operation == "write" then
          injected = true; file:write(data:sub(1, 8)); return nil, "injected write failure"
        end
        return file:write(data)
      end,
      close = function()
        local ok, closeErr = file:close()
        if operation == "close" then injected = true; return nil, "injected close failure" end
        return ok, closeErr
      end,
    }
  end
  local ok, err = pcall(callback)
  io.open = originalOpen
  assert(ok, err)
  check(injected, operation .. " failure was exercised")
end
local function withRenameFailure(path, failRollback, callback)
  local originalRename = os.rename
  local promotionFailed, rollbackFailed = false, false
  os.rename = function(source, destination)
    if source == path .. ".tmp" and destination == path then
      promotionFailed = true; return nil, "injected promotion failure", 13
    end
    if failRollback and source == path .. ".bak" and destination == path then
      rollbackFailed = true; return nil, "injected rollback failure", 13
    end
    return originalRename(source, destination)
  end
  local ok, err = pcall(callback)
  os.rename = originalRename
  assert(ok, err)
  check(promotionFailed and (not failRollback or rollbackFailed), "requested rename failures were exercised")
end

local savedQuotes = assert(readFile(quotePath))
local savedPrice = c.markets.beta.resources.Electronics
for _, operation in ipairs({"write", "close"}) do
  c.markets.beta.resources.Electronics = savedPrice + 100
  withIOFailure(quotePath, operation, function()
    local ok, err = c:save()
    check(not ok and tostring(err):find("injected " .. operation .. " failure", 1, true),
      "quote save reports " .. operation .. " failure")
  end)
  check(readFile(quotePath) == savedQuotes, operation .. " failure preserves the prior quotes byte for byte")
  reload()
  check(c.markets.beta.resources.Electronics == savedPrice, "prior quotes reload after " .. operation .. " failure")

  local savedCapacity, savedUnits = assert(readFile(capacityPath)), c.units
  output = {}
  withIOFailure(capacityPath, operation, function() c:setCapacity(tostring(savedUnits + 1)) end)
  check(c.units == savedUnits and hasOutput("Cannot save cargo capacity"), "capacity " .. operation .. " failure does not change active setting")
  check(readFile(capacityPath) == savedCapacity, "capacity " .. operation .. " failure preserves prior file")
  reload()
  check(c.capacitySet and c.units == savedUnits, "prior capacity reloads after " .. operation .. " failure")
end

for _, path in ipairs({quotePath, capacityPath}) do
  local prior = assert(readFile(path))
  local savedUnits = c.units
  withRenameFailure(path, false, function()
    if path == quotePath then
      c.markets.beta.resources.Electronics = savedPrice + 200
      local ok, err = c:save()
      check(not ok and tostring(err):find("injected promotion failure", 1, true), "failed promotion is reported")
    else
      output = {}; c:setCapacity(tostring(savedUnits + 2))
      check(c.units == savedUnits and hasOutput("Cannot save cargo capacity"), "failed capacity promotion leaves current setting unchanged")
    end
  end)
  check(readFile(path) == prior, "failed promotion restores the prior primary file")
  reload()
  check(c.markets.beta.resources.Electronics == savedPrice and c.units == savedUnits,
    "saved values survive failed promotion and package reload")

  withRenameFailure(path, true, function()
    if path == quotePath then
      c.markets.beta.resources.Electronics = savedPrice + 300
      local ok = c:save(); check(not ok, "failed quote rollback is reported")
    else
      output = {}; c:setCapacity(tostring(savedUnits + 3))
      check(c.units == savedUnits and hasOutput("Cannot save cargo capacity"), "failed capacity rollback is reported")
    end
  end)
  check(readFile(path) == nil and readFile(path .. ".bak") == prior,
    "failed rollback retains the only previous copy in its backup")
  reload()
  check(readFile(path) == prior, "reload recovers the primary file after a failed rollback")
  check(c.markets.beta.resources.Electronics == savedPrice and c.units == savedUnits,
    "reload recovers the previous values after a failed rollback")

  -- A crash after staging the old file is the same recoverable on-disk state.
  os.remove(path .. ".bak")
  assert(os.rename(path, path .. ".bak"))
  reload()
  check(readFile(path) == prior, "missing primary is restored from backup on package load")
  check(c.markets.beta.resources.Electronics == savedPrice and c.units == savedUnits,
    "backup recovery restores the previous quote/capacity values")
end

-- A stale backup must never replace a newer, valid primary during recovery.
local latestQuotes = assert(readFile(quotePath))
local latestCapacity, latestUnits = assert(readFile(capacityPath)), c.units
writeFile(quotePath .. ".bak", "# LotJ cargo quotes 1\n")
writeFile(capacityPath .. ".bak", "capacity=54321\n")
reload()
check(c.markets.beta.resources.Electronics == savedPrice and readFile(quotePath) == latestQuotes,
  "existing primary quotes take precedence over stale backup")
check(c.units == latestUnits and readFile(capacityPath) == latestCapacity,
  "existing primary capacity takes precedence over stale backup")

-- A completed response remains useful in memory when its persistence fails.
savedQuotes = assert(readFile(quotePath))
c:command("scan Beta")
output = {}
withIOFailure(quotePath, "write", function() feed("tests/fixtures/beta-resources.txt") end)
check(not c.active and not c.timeoutTimer and not c.nextTimer and not next(triggers),
  "save failure cancels the scan before any next query")
check(c.markets.beta.resources.Electronics == 137.02 and not c.failed.beta,
  "save failure retains the completed quote in memory")
check(readFile(quotePath) == savedQuotes, "scan save failure preserves the prior on-disk quotes")
check(hasOutput("memory") and not hasOutput("Completed quotes are saved"),
  "save failure distinguishes in-memory quotes from persisted quotes")
os.remove(quotePath .. ".bak"); os.remove(capacityPath .. ".bak")
check(c:save(), "saving again succeeds after a transient filesystem failure")
reload()
check(c.markets.beta.resources.Electronics == 137.02, "retry persists the completed quote")

-- A corrupt settings file falls back to a per-unit display without execution.
c:destroy()
local badSettings = assert(io.open(TEST_DIR .. "/lotj-cargoscanner-settings.txt", "wb"))
badSettings:write("capacity=bad\n"); badSettings:close()
assert(loadstring(PACKAGE_CODE))()
c = LotJCargoScanner
check(not c.capacitySet and c.units == 1, "corrupt capacity settings are rejected")

event("sysUninstallPackage", "lotj-cargoscanner")
check(LotJCargoScanner == nil and not next(aliases) and not next(handlers), "uninstall cleans up")
if TEST_WINDOWS_RENAME then check(overwriteRefusals > 0, "Windows replacement refusal was exercised") end
print("Adapter (" .. (TEST_WINDOWS_RENAME and "Windows rename" or "native rename") .. "): " .. checks .. " checks passed")
