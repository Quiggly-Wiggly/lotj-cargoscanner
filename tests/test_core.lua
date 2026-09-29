-- Fictional worlds and synthetic prices; not a game-data export.
local Core = dofile("src/cargo_core.lua")
local checks = 0
local function check(condition, message)
  checks = checks + 1
  assert(condition, message or debug.traceback("check " .. checks .. " failed"))
end
local function near(actual, expected)
  check(type(actual) == "number" and math.abs(actual - expected) < 0.000001,
    "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local footer = "Use 'SHOWPLANET <planet> RESOURCES <resource>' for price history."
local zetaText = [[You use the datapad to lookup the information.
--Planet Data: -----------------------------------------
Planet: Zeta
Starsystem: Zeta System
Governed By: Example Government
Tax Rate: 15.00
Zeta is a freeport.
Electronics          ( Price per unit: 130.00)
Common metals        ( Price per unit: 127.83)
Food                 ( Price per unit: 122.03)
Spice                ( Price per unit: 193.10)
Water                ( Price per unit: 118.34)

Use 'SHOWPLANET <planet> RESOURCES <resource>' for price history.]]
local betaText = [[You use the datapad to lookup the information.
--Planet Data: -----------------------------------------
Planet: Beta
Starsystem: Betan System
Governed By: Example Government
Tax Rate: 15.00
Beta is a freeport.
Common metals        ( Price per unit: 119.97)
Electronics          ( Price per unit: 137.02)
Food                 ( Price per unit: 125.90)
Precious metals      ( Price per unit: 171.60)
Spice                ( Price per unit: 189.66)
Weapons              ( Price per unit: 153.20)
Goods                ( Price per unit: 148.17)
Medical supplies     ( Price per unit: 177.30)

Use 'SHOWPLANET <planet> RESOURCES <resource>' for price history.]]

local function parse(text, expected, at)
  local parser, status, result = Core.newParser(expected, at or 1000)
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    status, result = parser:feed(line)
    if status ~= "continue" then break end
  end
  return status, result, parser
end

local status, zeta, parser = parse(zetaText, "Zeta")
check(status == "complete", tostring(zeta))
check(zeta.name == "Zeta" and zeta.system == "Zeta System")
check(zeta.freeport and zeta.taxRate == 15 and zeta.observedAt == 1000)
near(zeta.resources["Common metals"], 127.83)
check(#zeta.resourceLines == 5 and zeta.resourceLines[1] == "Electronics          ( Price per unit: 130.00)")
local terminalStatus, terminalRecord = parser:feed("OOC prompt")
check(terminalStatus == "complete" and terminalRecord == zeta)
local betaStatus, beta = parse(betaText, "Beta", 1100)
check(betaStatus == "complete" and #beta.resourceLines == 8)
local monCalaFile = assert(io.open("tests/fixtures/test-moon-resources.txt", "r"))
local monCalaText = monCalaFile:read("*a")
monCalaFile:close()
local monCalaParser = Core.newParser("Test Moon", 1150)
local monCalaStatus, monCala
for line in monCalaText:gmatch("([^\n]*)\n") do
  monCalaStatus, monCala = monCalaParser:feed(line)
  if line ~= footer then
    check(monCalaStatus == "continue" and monCala == nil,
      "Test Moon must not commit or reject padded prices before the footer")
  end
end
check(monCalaStatus == "complete", tostring(monCala))
check(monCala.name == "Test Moon" and monCala.system == "Test System")
check(monCala.government == "Example Neutral" and monCala.freeport and monCala.taxRate == 15)
near(monCala.resources["Common metals"], 131.13)
near(monCala.resources.Electronics, 126.00)
near(monCala.resources.Water, 106.16)
check(#monCala.resourceLines == 3
  and monCala.resourceLines[3] == "Water                ( Price per unit: 106.16 )",
  "preserve the exact padded Water quote for saved market evidence")
for _, paddedPrice in ipairs({ "  106.16   ", "\t106.16\t", " \t 106.16 \t " }) do
  local paddedStatus, paddedMarket = parse(monCalaText:gsub("106%.16 ", paddedPrice), "Test Moon")
  check(paddedStatus == "complete", "allow whitespace around resource prices")
  near(paddedMarket.resources.Water, 106.16)
end
for _, invalidPrice in ipairs({ "6 .16", "6. 16", "6.1\t6", "106.16 credits", "106.16x" }) do
  check(parse(monCalaText:gsub("106%.16 ", invalidPrice), "Test Moon") == "error",
    "reject malformed price: " .. invalidPrice)
end
local replayStatus, replay = parse(zetaText, nil, 900)
check(replayStatus == "complete" and replay.name == "Zeta" and replay.observedAt == 900)
check(parse(zetaText:gsub("Zeta is a freeport%.", "Beta is a freeport."), nil) == "error")
check(not pcall(Core.newParser, false))
check(not pcall(Core.newParser, 12))
check(not pcall(Core.newParser, "  "))
local cut = zetaText:sub(1, #zetaText - #footer)
local incomplete, partial = parse(cut, "Zeta")
check(incomplete == "continue" and partial == nil, "truncated responses must not commit")
check(parse(zetaText, "Beta") == "error", "reject other planet's response")
check(parse(zetaText:gsub("Tax Rate: 15.00\n", ""), "Zeta") == "error")
check(parse(zetaText:gsub("Starsystem: Zeta System\n", ""), "Zeta") == "error")
check(parse(zetaText:gsub("Governed By: Example Government\n", ""), "Zeta") == "error")
check(parse(zetaText:gsub("Tax Rate: 15.00", "Tax Rate: 15.00\nTax Rate: 15.00"), "Zeta") == "error")
check(parse(zetaText:gsub("Tax Rate: 15.00", "Tax Rate: nonsense"), "Zeta") == "error")
check(parse(zetaText:gsub("Tax Rate: 15.00", "Tax Rate: -15.00"), "Zeta") == "error")
check(parse(zetaText:gsub("Tax Rate: 15.00", "Tax Rate: 100.01"), "Zeta") == "error")
check(parse(zetaText:gsub("Tax Rate: 15.00", "Tax Rate: 100.00"), "Zeta") == "complete")
check(parse(zetaText:gsub("130.00", "-130.00"), "Zeta") == "error")
check(parse(zetaText:gsub("130.00", "NaN"), "Zeta") == "error")
check(parse(zetaText:gsub("Water%s+%( Price per unit: 118.34%)", "electronics ( Price per unit: 2.00)"), "Zeta") == "error")
check(parse(zetaText:gsub("Zeta is a freeport%.", "Beta is a freeport."), "Zeta") == "error")
check(parse(zetaText:gsub("Zeta is a freeport%.", "a message from elsewhere"), "Zeta") == "error")
check(parse(cut .. "\n--Planet Data: ---\n" .. footer, "Zeta") == "error")
check(parse(cut .. "Use 'SHOWPLANET <planet> RESOURCES' for current resources.", "Zeta") == "error")
local noQuotes = zetaText:gsub("[^\n]+%( Price per unit: [^\n]+\n", "")
check(parse(noQuotes, "Zeta") == "error")
local noFreeportStatus, noFreeport = parse(zetaText:gsub("Zeta is a freeport%.\n", ""), "Zeta")
check(noFreeportStatus == "complete" and noFreeport.freeport == false)
check(parse("\27[32m" .. zetaText:gsub("\n", "\27[0m\r\n\27[32m") .. "\27[0m", "zeta") == "complete")

local systems = {
  ["Zeta System"] = { x = 0, y = 0, Zeta = { x = 0, y = 0, z = 0, government = "Example Group" } },
  ["Betan System"] = { x = 23, y = 3, Beta = { x = 17, y = -30, z = 22, government = "Example Group" } },
  ["Empty System"] = { x = 1, y = 2 },
  ["Missing coords"] = { Unknown = {government = "Unknown"} },
}
local planets = Core.planetsFromGMCP(systems)
check(planets.zeta.galaxyX == 0 and planets.zeta.systemX == 0)
check(planets.beta.galaxyX == 23 and planets.beta.systemX == 17)
check(planets.unknown.galaxyX == nil and planets.unknown.systemZ == nil)
check(planets["empty system"] == nil and next(Core.planetsFromGMCP(nil)) == nil)

-- The official UI augments Galaxy.Systems in place when drawing its map.
-- Its selected-planet alias must never become a showplanet "planet" target.
local mappedWorld = {x = 1, y = 2, z = 3, government = "Example Group", name = "planet"}
local mappedSystem = {
  x = 46, y = 14, name = "Gamma", Gamma = mappedWorld, planet = mappedWorld,
  planets = {
    {name = "Gamma", government = "Example Group", x = 99},
    {name = "planet", government = "Example Group", x = 1},
  },
}
local mappedCatalog = Core.planetsFromGMCP({
  ["Gamma System"] = mappedSystem,
  ["Empty System"] = {x = 1, y = 2, name = "Empty", planet = {government = "Example Neutral"}, planets = {}},
})
local mappedCount = 0
for _ in pairs(mappedCatalog) do mappedCount = mappedCount + 1 end
check(mappedCount == 1 and mappedCatalog.gamma.name == "Gamma",
  "UI helper tables and aliases must not create extra planets")
check(mappedCatalog.gamma.system == "Gamma System" and mappedCatalog.gamma.galaxyX == 46,
  "use system keys and galactic coordinates, not the map's display name")
check(mappedCatalog.gamma.systemX == 1,
  "original named records take priority over copied UI list entries")
check(mappedSystem.planet == mappedWorld and mappedWorld.name == "planet" and #mappedSystem.planets == 2,
  "reading the UI catalog must not mutate its tables")

local listCatalog = Core.planetsFromGMCP({
  ["Test System"] = {
    x = "20", y = "30", name = "Mon", planet = {government = "Neutral"},
    planets = {
      {name = "Test Moon", government = "Neutral", x = "4", y = 5, z = 6},
      {name = "Companion", government = "Neutral"},
      {name = "planet", government = "Neutral"},
      {name = "\nInvalid", government = "Neutral"},
      {name = " "}, {government = "Neutral"}, false,
    },
  },
})
local listCount = 0
for _ in pairs(listCatalog) do listCount = listCount + 1 end
check(listCount == 2 and listCatalog["test moon"].system == "Test System",
  "accept explicitly named UI planet-list entries when original records are unavailable")
check(listCatalog["test moon"].galaxyX == 20 and listCatalog["test moon"].systemX == 4)
check(listCatalog.companion.galaxyY == 30 and listCatalog.companion.systemX == nil)
check(next(Core.planetsFromGMCP({Malformed = {planets = "unavailable", planet = false}})) == nil)

local markets = { zeta = zeta, beta = beta }
local opts = { now = 1200, units = 100, sort = "distance" }
local rows = Core.routes(markets, planets, opts)
check(#rows == 4, "only four shared positive spreads, no invented resources")
check(rows[1].origin == "Beta" and rows[1].destination == "Zeta" and rows[1].resource == "Common metals")
near(rows[1].margin, 7.86)
near(rows[1].loadMargin, 786)
near(rows[1].distance, math.sqrt(538))
near(rows[1].score, 7.86 / math.sqrt(538))
check(rows[1].oldestAt == 1000 and rows[1].originTaxRate == 15 and rows[1].destinationTaxRate == 15)
check(rows[1].taxMode == "unknown" and rows[1].quoteOnly, "quoted margins must not imply tax deductions")
check(rows[2].resource == "Electronics" and rows[2].origin == "Zeta")
near(rows[2].margin, 7.02)
local trips = Core.roundTrips(markets, planets, opts)
check(#trips == 1 and trips[1].outbound.resource == "Common metals" and trips[1].inbound.resource == "Electronics")
near(trips[1].margin, 14.88)
near(trips[1].loadMargin, 1488)
near(trips[1].totalDistance, 2 * math.sqrt(538))
near(trips[1].score, 14.88 / (2 * math.sqrt(538)))
check(#Core.routes(markets, planets, { now = 4701 }) == 0, "exclude stale quotes")
check(#Core.routes(markets, planets, { now = 4600 }) == 4, "exact age boundary stays fresh")
check(#Core.routes(markets, planets, { now = 900 }) == 0, "reject future timestamps")
check(#Core.routes(markets, planets, { now = 1200, maxAgeSeconds = 0 }) == 0)
local missingCoords = Core.routes(markets, {}, { now = 1200, sort = "margin" })
check(#missingCoords == 4 and missingCoords[1].distance == nil and missingCoords[1].score == nil)
local colocated = { zeta = planets.zeta, beta = { name = "Beta", system = "Betan System", galaxyX = 0, galaxyY = 0 } }
local zeroRows = Core.routes(markets, colocated, { now = 1200 })
check(zeroRows[1].distance == 0 and zeroRows[1].score == nil)
check(Core.roundTrips(markets, colocated, { now = 1200 })[1].score == nil)
local changedSystem = { zeta = planets.zeta, beta = { name = "Beta", system = "Elsewhere", galaxyX = 23, galaxyY = 3 } }
check(Core.routes(markets, changedSystem, opts)[1].distance == nil)
local synthetic = {
  { name = "A", observedAt = 1000, resources = { ore = 10 } },
  { name = "B", observedAt = 1000, resources = { Ore = 20 } },
  { name = "C", observedAt = 1000, resources = { ore = 12 } },
}
local syntheticPlanets = {
  { name = "A", galaxyX = 0, galaxyY = 0 },
  { name = "B", galaxyX = 100, galaxyY = 0 },
  { name = "C", galaxyX = 1, galaxyY = 0 },
}
local distanceSorted = Core.routes(synthetic, syntheticPlanets, { now = 1200 })
check(distanceSorted[1].origin == "A" and distanceSorted[1].destination == "C")
local marginSorted = Core.routes(synthetic, syntheticPlanets, { now = 1200, sort = "margin" })
check(marginSorted[1].origin == "A" and marginSorted[1].destination == "B")
check(#Core.roundTrips(synthetic, syntheticPlanets, { now = 1200 }) == 0, "single-resource markets have no positive return trade")
check(not pcall(Core.routes, markets, planets, { units = 0 }))
check(not pcall(Core.routes, markets, planets, { taxMode = "assume15percent" }))

-- Each pair shares only commodities rising in one direction. Thus the first
-- fixture has a profitable trio circuit despite having no two-planet circuit.
local circuitMarkets = {
  { name = "A", observedAt = 1000, resources = { ab1 = 10, ab2 = 5, ca1 = 40, ca2 = 80 } },
  { name = "B", observedAt = 1050, resources = { ab1 = 20, ab2 = 25, bc1 = 30, bc2 = 60 } },
  { name = "C", observedAt = 1100, resources = { bc1 = 50, bc2 = 65, ca1 = 10, ca2 = 25 } },
}
local circuitPlanets = {
  { name = "A", galaxyX = 0, galaxyY = 0 },
  { name = "B", galaxyX = 3, galaxyY = 0 },
  { name = "C", galaxyX = 3, galaxyY = 4 },
}
local circuits = Core.loops(circuitMarkets, circuitPlanets, { now = 1200, units = 10 })
check(#Core.roundTrips(circuitMarkets, circuitPlanets, { now = 1200 }) == 0)
check(#circuits == 1 and circuits[1].stops == 3, "find trio without two-way pairs; remove rotations")
local circuit = circuits[1]
check(table.concat(circuit.path, ",") == "A,B,C,A", "return to the canonical starting planet")
check(circuit.legs[1].resource == "ab2" and circuit.legs[2].resource == "bc1" and circuit.legs[3].resource == "ca2",
  "choose the highest quoted spread independently on each leg")
near(circuit.margin, 95)
near(circuit.loadMargin, 950)
near(circuit.totalDistance, 12)
near(circuit.score, 95 / 12)
check(circuit.oldestAt == 1000 and circuit.quoteOnly and circuit.taxMode == "unknown")
near(circuit.legs[3].margin, 55)
near(circuit.legs[3].distance, 5)
check(#Core.loops(circuitMarkets, circuitPlanets, { now = 1200, stops = 2 }) == 0)
check(#Core.loops(circuitMarkets, circuitPlanets, { now = 1200, stops = 3 }) == 1)
check(#Core.loops(circuitMarkets, circuitPlanets, { now = 1200, stops = 4 }) == 0)
local fromC = Core.loops(circuitMarkets, circuitPlanets, { now = 1200, start = " c " })
check(#fromC == 1 and table.concat(fromC[1].path, ",") == "C,A,B,C")
near(fromC[1].margin, circuit.margin)
near(fromC[1].totalDistance, circuit.totalDistance)
check(#Core.loops(circuitMarkets, circuitPlanets, { now = 1200, start = "Unknown" }) == 0)
check(#Core.loops(circuitMarkets, circuitPlanets, { now = 4701 }) == 0, "stale quote removes required closing leg")
local noClosing = {
  { name = "A", observedAt = 1000, resources = { ab1 = 10, ab2 = 5 } }, circuitMarkets[2], circuitMarkets[3],
}
check(#Core.loops(noClosing, circuitPlanets, { now = 1200 }) == 0, "an open profitable path is not a circuit")
local unknownDistance = Core.loops(circuitMarkets, { circuitPlanets[1], circuitPlanets[2] }, { now = 1200 })[1]
check(unknownDistance.totalDistance == nil and unknownDistance.score == nil)
local sameLocation = {
  { name = "A", galaxyX = 0, galaxyY = 0 },
  { name = "B", galaxyX = 0, galaxyY = 0 },
  { name = "C", galaxyX = 0, galaxyY = 0 },
}
local zeroCircuit = Core.loops(circuitMarkets, sameLocation, { now = 1200 })[1]
check(zeroCircuit.totalDistance == 0 and zeroCircuit.score == nil)

-- Add a return commodity to one pair: pair and trio compare on full circuit
-- distance, including the last flight. The shorter pair wins distance scoring.
circuitMarkets[1].resources.ba, circuitMarkets[2].resources.ba = 50, 10
local mixedLoops = Core.loops(circuitMarkets, circuitPlanets, { now = 1200 })
check(#mixedLoops == 2 and mixedLoops[1].stops == 2 and mixedLoops[2].stops == 3)
near(mixedLoops[1].margin, 60)
near(mixedLoops[1].totalDistance, 6)
check(Core.loops(circuitMarkets, circuitPlanets, { now = 1200, sort = "margin" })[1].stops == 3)
local pairLoop = Core.loops(markets, planets, { now = 1200, stops = 2, units = 100 })[1]
near(pairLoop.margin, trips[1].margin)
near(pairLoop.loadMargin, trips[1].loadMargin)
near(pairLoop.totalDistance, trips[1].totalDistance)
near(pairLoop.score, trips[1].score)

-- Make every edge available in reverse too. The two distinct three-planet
-- directions survive, while their six rotated representations do not.
circuitMarkets[2].resources.cb, circuitMarkets[3].resources.cb = 100, 10
circuitMarkets[1].resources.ac, circuitMarkets[3].resources.ac = 1, 2
local directions = Core.loops(circuitMarkets, circuitPlanets, { now = 1200, stops = 3 })
check(#directions == 2 and table.concat(directions[1].path, ",") == "A,C,B,A"
  and table.concat(directions[2].path, ",") == "A,B,C,A")
check(#Core.loops(circuitMarkets, circuitPlanets, { now = 1200 }) == 5)
check(#Core.loops(circuitMarkets, circuitPlanets, { now = 1200, start = "A" }) == 4,
  "a specified starting planet is required in every circuit")
check(#Core.loops(circuitMarkets, circuitPlanets, { now = 1200, limit = 1 }) == 1)
check(#Core.loops(circuitMarkets, circuitPlanets, { now = 1200, limit = 0 }) == 0)

-- A fourth vertex allows four-stop circuits; a three-vertex graph must never
-- create one by revisiting a vertex before the final return.
check(#Core.loops(circuitMarkets, circuitPlanets, { now = 1200, stops = 4 }) == 0)
circuitMarkets[4] = { name = "D", observedAt = 1100, resources = { cd = 4, da = 1 } }
circuitMarkets[3].resources.cd, circuitMarkets[1].resources.da = 1, 6
circuitPlanets[4] = { name = "D", galaxyX = 0, galaxyY = 4 }
local quads = Core.loops(circuitMarkets, circuitPlanets, { now = 1200, stops = 4 })
check(#quads == 1 and table.concat(quads[1].path, ",") == "A,B,C,D,A")
near(quads[1].margin, 48)
near(quads[1].totalDistance, 14)
local allCircuits = Core.loops(circuitMarkets, circuitPlanets, { now = 1200, minStops = 2, maxStops = 4 })
check(#allCircuits > #quads)
for _, candidate in ipairs(allCircuits) do
  local seen = {}
  for i = 1, #candidate.path - 1 do
    check(not seen[candidate.path[i]], "circuit must not revisit a planet before the closing return")
    seen[candidate.path[i]] = true
  end
  check(candidate.path[#candidate.path] == candidate.path[1] and candidate.stops == #candidate.legs)
end

-- Deterministic path ordering breaks ties even when the first two vertices,
-- gains, and distances agree (A-B-C-D-A and A-B-D-C-A).
local tiedMarkets, tiedPlanets = {}, {}
for _, name in ipairs({ "A", "B", "C", "D" }) do
  tiedMarkets[name] = { name = name, observedAt = 1000, resources = {} }
  tiedPlanets[name] = { name = name, galaxyX = 0, galaxyY = 0 }
end
for _, edge in ipairs({ {"A","B"}, {"B","C"}, {"C","D"}, {"D","A"}, {"B","D"}, {"D","C"}, {"C","A"} }) do
  local resource = edge[1] .. edge[2]
  tiedMarkets[edge[1]].resources[resource] = 1
  tiedMarkets[edge[2]].resources[resource] = 2
end
local tied = Core.loops(tiedMarkets, tiedPlanets, { now = 1200, stops = 4 })
check(#tied == 2 and table.concat(tied[1].path, ",") == "A,B,C,D,A"
  and table.concat(tied[2].path, ",") == "A,B,D,C,A")
for _, invalid in ipairs({ { stops = 1 }, { stops = 5 }, { stops = 2.5 },
  { minStops = 3, maxStops = 2 }, { stops = false }, { maxStops = false },
  { start = false }, { limit = -1 }, { limit = 0.5 } }) do
  check(not pcall(Core.loops, {}, {}, invalid), "reject invalid loop options")
end
print("cargo_core: " .. checks .. " checks passed")
