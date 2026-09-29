-- Fictional worlds and synthetic prices; not a game-data export.
local UI = dofile("src/cargo_ui.lua")
local checks = 0
local function check(ok, message)
  checks = checks + 1
  assert(ok, message or debug.traceback("UI check " .. checks .. " failed"))
end
local function flat(lines)
  local out, commands, fills = {}, {}, {}
  for _, line in ipairs(lines) do
    local parts = {}
    for _, part in ipairs(line) do
      parts[#parts + 1] = part.text
      if part.command ~= nil then commands[part.command] = true end
      if part.fill then fills[part.fill] = true end
    end
    out[#out + 1] = table.concat(parts)
  end
  return table.concat(out, "\n"), out, commands, fills
end
local function contains(text, needle) return text:find(needle, 1, true) ~= nil end
local state = {
  version = "0.3.0", units = 12000, capacitySet = true, sort = "distance", maxAgeMinutes = 60,
  planetCount = 4, marketCount = 3, freshCount = 2, staleCount = 1, missingCount = 1, failedCount = 0,
  completed = 2, total = 4,
  markets = {
    {name = "Zeta", resources = 5, ageMinutes = 0.5, taxRate = 15, state = "fresh"},
    {name = "Test Moon", resources = 3, ageMinutes = 75, taxRate = 10, state = "stale"},
    {name = "Beta", resources = 8, state = "failed"},
    {name = "Delta", state = "unknown"},
  },
  planets = {
    {name = "Zeta", system = "Zeta System", galaxyX = 0, galaxyY = 0, state = "fresh", ageMinutes = 1},
    {name = "Test Moon", system = "Test System", galaxyX = -12.5, galaxyY = 1000, state = "stale", ageMinutes = 75},
  },
  fields = {"gmcp.Galaxy.Markets (table)", "gmcp.Ship.cargo (number)"},
  events = {"gmcp.Galaxy.Systems"},
  planetSource = "GMCP Galaxy.Systems",
  catalogSources = {
    {name = "gmcp.Galaxy.Systems", dataType = "table", systemCount = 2, planetCount = 4},
    {name = "lotj.galaxyMap.systems", dataType = "nil", systemCount = 0, planetCount = 0},
  },
}
local home, _, commands = flat(UI.home(state))
check(contains(home, "CARGO / HOME") and contains(home, "v0.3.0"))
check(contains(home, "12,000 units per leg"), "full cargo capacity uses grouped numbers")
check(contains(home, "2 fresh / 4 planets"))
check(contains(home, "Some prices need refreshing"))
for _, name in ipairs({"loops", "routes", "scan", "status", "planets", "settings", "help"}) do check(commands[name], "missing home action: " .. name) end
local empty, _, emptyActions = flat(UI.home({}))
check(contains(empty, "No planets loaded") and emptyActions[""] and emptyActions.diagnostics)
check(contains(empty:gsub("\n", " "), "Open the LOTJ UI galaxy map and let it load, then Refresh"), "empty home explains how to load planets")
local unscanned = flat(UI.home({planetCount = 14, freshCount = 0}))
check(contains(unscanned, "Scan planet prices to find cargo routes"))
local noCapacity, _, _, capacityFills = flat(UI.home({planetCount = 14, freshCount = 14}))
check(contains(noCapacity, "Set your cargo capacity"))
check(capacityFills["cargoscan cargocapacity "])
local ready = flat(UI.home({planetCount = 14, freshCount = 14, capacitySet = true, units = 1}))
check(contains(ready, "1 unit per leg") and contains(ready, "Prices are ready"))
local scanning, _, scanActions = flat(UI.home({active = true, current = "Test Moon", completed = 2, total = 14}))
check(contains(scanning, "Scanning Test Moon. 2 of 14 complete.") and scanActions.stop)
local help, _, helpActions, helpFills = flat(UI.help(state))
for _, command in ipairs({"scan [planet]", "loops [2|3|4|mixed] [count]", "routes [count]", "show <number>", "cargocapacity <number>", "sort distance|margin", "age <minutes>", "status", "planets", "stop", "settings", "diagnostics"}) do
  check(contains(help, "cargoscan " .. command), "missing help command: " .. command)
end
check(contains(help, "Route details"))
check(helpFills["cargoscan show "] and helpFills["cargoscan scan "] and helpActions.status, "help entries run complete commands or prefill arguments")
local settings, _, settingsActions, settingsFills = flat(UI.settings(state))
check(contains(settings, "CARGO / SETTINGS") and contains(settings, "12,000 units per leg"))
check(settingsActions["sort distance"] and settingsActions["sort margin"])
check(settingsActions["age 15"] and settingsActions["age 30"] and settingsActions["age 60"] and settingsActions["age 120"])
check(settingsFills["cargoscan cargocapacity "] and settingsFills["cargoscan age "])
check(settingsActions["output compact"] and settingsActions["output full"])
check(contains(settings, "Current: compact scan progress"))
check(contains(flat(UI.settings({scanOutput = "full"})), "Current: full planet responses"))
local status, _, statusActions = flat(UI.status(state))
check(contains(status, "Fresh") and contains(status, "Stale") and contains(status, "Scan failed") and contains(status, "Not scanned"))
check(contains(status, "15.00%") and contains(status, "just now") and contains(status, "1 hr ago"))
check(contains(status, "TAX RATE") and contains(status, "UPDATED"), "wide status uses clear table columns")
check(statusActions["scan Test Moon"] and statusActions["scan Zeta"])
local missing, _, missingActions = flat(UI.status({planets = {{name = "Mustafar"}}, markets = {}}))
check(contains(missing, "Mustafar") and contains(missing, "Not scanned") and missingActions["scan Mustafar"], "status includes known planets without saved prices")
local duplicate = flat(UI.status({planets = {{name = "TEST MOON"}}, markets = {{name = "Test Moon", state = "fresh"}}}))
check(not contains(duplicate, "TEST MOON"), "status does not duplicate saved planets by case")
check(contains(settings:gsub("\n", " "), "Sorting, price age, and scan output reset when the package reloads."))
local planets, _, planetActions = flat(UI.planets(state))
check(contains(planets, "Test System") and contains(planets, "x -12.50, y 1,000"))
check(planetActions["scan Test Moon"])
local emptyPlanets, _, emptyPlanetActions = flat(UI.planets({}))
check(contains(emptyPlanets:gsub("\n", " "), "Open the LOTJ UI galaxy map and let it load, then Refresh"))
check(emptyPlanetActions.planets and emptyPlanetActions.diagnostics, "empty planets view provides refresh and diagnostics actions")
local diag, _, diagnosticActions = flat(UI.diagnostics(state))
check(contains(diag, "gmcp.Galaxy.Markets (table)") and contains(diag, "gmcp.Galaxy.Systems"))
check(diagnosticActions.gmcp and diagnosticActions.probe)
check(contains(diag:gsub("\n", " "), "Missing fields do not rule out server support"))
check(contains(diag, "PLANET CATALOG") and contains(diag, "Source: GMCP Galaxy.Systems") and contains(diag, "Known planets: 4"))
check(contains(diag, "gmcp.Galaxy.Systems: table / 2 systems / 4 planets"), "diagnostics report the usable GMCP catalog")
check(contains(diag, "lotj.galaxyMap.systems: nil / 0 systems / 0 planets"), "diagnostics distinguish an absent map source")
check(contains(diag:gsub("\n", " "), "Use cargoscan scan [planet] to capture prices and tax rates from showplanet resources"))
check(contains(diag:gsub("\n", " "), "Probe only observes GMCP events. No event after showplanet does not mean scanning is broken"), "probe silence does not imply failed price capture")
local cachedCatalog = flat(UI.diagnostics({
  planetCount = 3, planetSource = "LOTJ UI galaxy map (may be cached)",
  catalogSources = {
    {name = "gmcp.Galaxy.Systems", dataType = "table", systemCount = 0, planetCount = 0},
    {name = "lotj.galaxyMap.systems", dataType = "table", systemCount = 2, planetCount = 3},
  },
}))
check(contains(cachedCatalog, "Source: LOTJ UI galaxy map (may be cached)") and contains(cachedCatalog, "Known planets: 3"))
check(contains(cachedCatalog, "gmcp.Galaxy.Systems: table / 0 systems / 0 planets"), "diagnostics distinguish an empty GMCP table from an absent one")
check(contains(cachedCatalog, "lotj.galaxyMap.systems: table / 2 systems / 3 planets"))
local limited = flat(UI.diagnostics({depthLimited = true, probing = true}))
check(contains(limited, "list may be incomplete") and contains(limited, "LIVE PROBE RUNNING"))
check(contains(limited, "Source: Unavailable") and contains(limited, "Known planets: 0"))
local fieldsOnly = flat(UI.diagnostics(state, {title = "GMCP FIELDS"}))
check(contains(fieldsOnly, "CARGO / GMCP FIELDS") and not contains(fieldsOnly, "LAST PROBE EVENTS"))
local eventsOnly = flat(UI.diagnostics(state, {title = "GMCP EVENTS"}))
check(contains(eventsOnly, "CARGO / GMCP EVENTS") and not contains(eventsOnly, "gmcp.Galaxy.Markets"))
local progress, progressLines = flat(UI.progress({completed = 3, total = 12, current = "Test Moon"}, {width = 80}))
check(contains(progress, "25%") and contains(progress, "3/12") and contains(progress, "Looking up Test Moon"))
check(#progressLines == 1, "ordinary scan progress stays compact")
local saved, savedLines = flat(UI.progress({completed = 3, total = 12, current = "Test Moon", resources = 3}, {width = 96}))
check(contains(saved, "Saved Test Moon / 3 prices") and #savedLines == 1, "completed quotes use a compact saved confirmation")
local noTotal = flat(UI.progress({completed = 1, total = 0}))
check(contains(noTotal, "0%"), "unknown total does not divide by zero")
local notice, _, noticeActions = flat(UI.notice("Scan stopped. Completed prices are saved.", {kind = "warning", actions = {{text = "Retry", command = "scan Test Moon"}}}))
check(contains(notice, "CARGO  Scan stopped.") and noticeActions["scan Test Moon"])
local errorLines = UI.notice("Could not save settings.", {kind = "error"})
check(errorLines[1][1].color == "error")

-- Every surface wraps dynamic content, keeps server markup literal, and produces data-only actions.
local longName = "A Very Long Planet Name With Enough Words To Wrap Around Several Lines <red>literal</red>"
local exotic = {
  version = "0.3.0", active = true, current = longName .. "\nBAD", planetCount = 14,
  completed = 3, total = 14, units = 100000000, capacitySet = true,
  markets = {{name = longName, resources = 10000, ageMinutes = 2000, taxRate = 100, state = "failed"}},
  planets = {{name = longName, system = "Very Long Star System Name With Multiple Words", galaxyX = 10000000, galaxyY = -10000000}},
  fields = {"gmcp.Galaxy." .. string.rep("X", 250), "gmcp.Char.<green>Literal\27[31m"},
  events = {"gmcp.Galaxy." .. string.rep("Y", 250)}, cachePath = "/tmp/" .. string.rep("folder/", 30),
  planetSource = "LOTJ UI galaxy map (may be cached)",
  catalogSources = {{name = "gmcp." .. string.rep("Z", 250) .. "\nBAD", dataType = "table", systemCount = 123456789, planetCount = 123456789}},
}
for _, columns in ipairs({20, 40, 41, 60, 80, 96, 100, 200}) do
  local expected = math.max(40, math.min(100, columns))
  for _, method in ipairs({"home", "help", "settings", "status", "planets", "diagnostics", "progress"}) do
    local rendered = UI[method](exotic, {width = columns})
    local text, physical = flat(rendered)
    for _, line in ipairs(physical) do check(#line <= expected, method .. " overflow at " .. columns .. ": " .. line) end
    for _, line in ipairs(rendered) do
      for _, part in ipairs(line) do
        check(type(part.text) == "string" and type(part.color) == "string", "segment contract")
        check(not part.text:find("[%c]"), "control characters neutralized")
        check(part.command == nil or type(part.command) == "string", "commands are data")
        check(part.fill == nil or type(part.fill) == "string", "fills are data")
      end
    end
    if method == "status" or method == "planets" then
      check(contains(text:gsub("\n +", " "):gsub("\n", " "), longName), "full planet name survives wrapping")
      check(contains(text, "<red>literal</red>"), "markup remains literal")
    end
  end
  local _, physical = flat(UI.notice(longName .. "\n\27payload", {width = columns, title = string.rep("TITLE", 20)}))
  for _, line in ipairs(physical) do check(#line <= expected, "notice overflow") end
  for _, method in ipairs({"home", "planets", "diagnostics"}) do
    local _, emptyLines = flat(UI[method]({}, {width = columns}))
    for _, line in ipairs(emptyLines) do check(#line <= expected, method .. " empty guidance overflow at " .. columns) end
  end
end
local unicode, unicodeLines = flat(UI.planets({planets = {{name = "Café " .. string.rep("界", 60)}}}, {width = 40}))
check(contains(unicode:gsub("\n", ""):gsub(" ", ""), string.rep("界", 60)), "UTF-8 names remain intact")
for _, line in ipairs(unicodeLines) do
  check(select(2, line:gsub("[^\128-\191]", "")) <= 40, "UTF-8 width measured by codepoints")
end
print("cargo_ui: " .. checks .. " checks passed")
