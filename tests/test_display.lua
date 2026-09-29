-- Fictional worlds and synthetic prices; not a game-data export.
local Display = dofile("src/cargo_display.lua")
local checks = 0
local function check(condition, message)
  checks = checks + 1
  assert(condition, message or ("display check " .. checks .. " failed"))
end
local function flat(lines)
  local out = {}
  for _, line in ipairs(lines) do
    local parts = {}; for _, part in ipairs(line) do parts[#parts + 1] = part.text end
    out[#out + 1] = table.concat(parts)
  end
  return table.concat(out, "\n"), out
end
local a = {origin = "Delta", destination = "Zeta", resource = "Food",
  buyPrice = 14.97, sellPrice = 22.02, margin = 7.05, distance = 14.21,
  oldestAt = 900, originTaxRate = 15, destinationTaxRate = 15, score = 0.496}
local b = {origin = "Zeta", destination = "Test Moon", resource = "Common metals",
  buyPrice = 27.85, sellPrice = 31.16, margin = 3.31, distance = 13.89,
  oldestAt = 950, originTaxRate = 15, destinationTaxRate = 15}
local c = {origin = "Test Moon", destination = "Delta", resource = "Electronics",
  buyPrice = 26, sellPrice = 37.04, margin = 11.04, distance = 16.03,
  oldestAt = 910, originTaxRate = 15, destinationTaxRate = 15}
local trio = {legs = {a, b, c}, margin = 21.4, totalDistance = 44.13, score = 0.485, oldestAt = 900}
local back = {origin = "Zeta", destination = "Delta", resource = "Food",
  buyPrice = 1, sellPrice = 3, margin = 2, distance = 14.21, oldestAt = 920}
local duo = {outbound = a, inbound = back, margin = 9.05, totalDistance = 28.42, oldestAt = 900}
local config = {kind = "loops", units = 1000, width = 96, marketCount = 14,
  maxAgeMinutes = 60, now = 1020, stopsLabel = "2-3 planets"}
local lines = Display.summary({trio, duo}, config)
local summary, physical = flat(lines)
check(summary:find("CARGO / LOOPS", 1, true))
check(summary:find("PROFIT", 1, true) and not summary:find("PROFIT/UNIT", 1, true))
check(summary:find("+21.40k", 1, true) and summary:find("44.13", 1, true))
check(summary:find("Cargo capacity: 1,000 units", 1, true))
check(summary:find("Prices no older than 60 min", 1, true))
check(summary:find("PER DIST", 1, true) and summary:find("484.931", 1, true), "efficiency uses the full cargo capacity")
check(summary:find("Show the route details with cargoscan show <number>.", 1, true))
check(summary:find("Profit is estimated from listed prices, before tax and fuel.", 1, true))
check(summary:find("Distance is the total route length on the galaxy map.", 1, true))
check(not summary:find("Quoted spreads", 1, true) and not summary:find("cr/u/d", 1, true))
check(summary:find("Delta > Zeta > Test Moon > Delta", 1, true))
check(not summary:find("%[Cargo scanner%]"))
local rowWidths, references = {}, {}
for i, line in ipairs(lines) do
  check(#physical[i] <= 96, "summary line exceeds console width")
  for _, part in ipairs(line) do
    check(type(part.text) == "string" and type(part.color) == "string")
    if part.detail then references[#references + 1] = part.detail; rowWidths[#rowWidths + 1] = #physical[i] end
  end
end
check(references[1] == trio and references[2] == duo, "clickable ranks retain exact row")
check(rowWidths[1] == 96 and rowWidths[2] == 96, "summary columns align")
local detail = flat(Display.detail(trio, config))
check(detail:find("ESTIMATED LOOP PROFIT\n+21,400.00 credits\nBefore tax and fuel | 3 legs", 1, true))
check(detail:find("LEG 1 / 3  Food\nDelta > Zeta", 1, true))
check(detail:find("LEG 2 / 3  Common metals\nZeta > Test Moon", 1, true))
check(detail:find("LEG 3 / 3  Electronics\nTest Moon > Delta", 1, true), "return leg remains explicit")
check(detail:find("Common metals", 1, true))
check(detail:find("Buy  1,000 units at 27.85 credits each", 1, true)
  and detail:find("Sell 1,000 units at 31.16 credits each", 1, true))
check(detail:find("Pay 14,970.00 credits at Delta", 1, true))
check(detail:find("Receive 31,160.00 credits at Test Moon", 1, true))
check(detail:find("Pay 26,000.00 credits at Test Moon", 1, true))
check(detail:find("Leg profit: +11,040.00 credits", 1, true))
check(detail:find("Listed taxes (not applied): origin 15.00%; destination 15.00%", 1, true))
check(detail:find("Oldest price: 2.0 min ago", 1, true))
local two = flat(Display.detail(duo, {now = 1020}))
check(two:find("Delta > Zeta > Delta", 1, true))
check(two:find("LEG 2 / 2  Food\nZeta > Delta", 1, true) and not two:find("LEG 3", 1, true))
check(two:find("Listed taxes (not applied): origin unknown; destination unknown", 1, true))
local one = flat(Display.detail(a, {units = 1, now = 1020}))
check(one:find("CARGO / ROUTE DETAILS", 1, true) and not one:find("LEG 2", 1, true))
check(one:find("ESTIMATED TRIP PROFIT\n+7.05 credits per unit", 1, true))
local unconfigured = flat(Display.summary({trio}, {units = 1000, capacitySet = false, width = 96}))
check(unconfigured:find("PROFIT/UNIT", 1, true) and unconfigured:find("PER DIST", 1, true))
check(unconfigured:find("+21.40", 1, true) and not unconfigured:find("+21.40k", 1, true))
check(unconfigured:find("0.485", 1, true) and not unconfigured:find("484.931", 1, true))
local singleCapacity = flat(Display.summary({trio}, {units = 1, capacitySet = true, width = 96}))
check(singleCapacity:find("Cargo capacity: 1 unit", 1, true)
  and not singleCapacity:find("PROFIT/UNIT", 1, true), "capacity of one is explicitly configured")
local singleCapacityDetail = flat(Display.detail(a, {units = 1, capacitySet = true, now = 1020}))
check(singleCapacityDetail:find("ESTIMATED TRIP PROFIT\n+7.05 credits\nBefore tax and fuel | 1 leg", 1, true))
check(singleCapacityDetail:find("Pay 14.97 credits at Delta", 1, true))
local forcedUnitDetail = flat(Display.detail(a, {units = 1000, capacitySet = false, now = 1020}))
check(forcedUnitDetail:find("Pay 14.97 credits at Delta", 1, true))
check(forcedUnitDetail:find("+7.05 credits per unit", 1, true))
local longName = string.rep("Really Long Planet Name ", 5) .. "<green>literal</green>"
local special = {origin = longName, destination = "<b>Destination</b>", resource = "<red>Mineral</red>",
  margin = 1, buyPrice = 2, sellPrice = 3}
local specialSummary, specialLines = flat(Display.summary({special}, {kind = "routes", width = 88}))
check(specialSummary:find("...", 1, true), "long summary names are clipped")
for _, line in ipairs(specialLines) do check(#line <= 88) end
local literal = flat(Display.detail(special, {}))
check(literal:gsub("\n", " "):find(longName, 1, true), "wrapped detail preserves the entire long name")
check(literal:find("<red>Mineral</red>", 1, true), "server markup remains literal text")
check(literal:find("Total distance: ?", 1, true)
  and literal:find("Listed taxes (not applied): origin unknown; destination unknown", 1, true))
local narrow, narrowLines = flat(Display.summary({trio}, {width = 60, units = 1000}))
check(narrow:find("Profit: +21.40k credits", 1, true))
for _, line in ipairs(narrowLines) do check(#line <= 60, "narrow summary wraps cleanly") end
local noRows = flat(Display.summary({}, {kind = "routes", width = 60}))
check(noRows:find("No matching routes yet", 1, true) and not noRows:find("cargoscan show", 1, true))
local countLines = Display.summary({trio, duo}, {count = 1})
local clickable = 0
for _, line in ipairs(countLines) do for _, part in ipairs(line) do if part.detail then clickable = clickable + 1 end end end
check(clickable == 1, "summary respects requested count")
for _, width in ipairs({40, 60, 75, 80, 88, 100}) do
  local _, sized = flat(Display.summary({trio, special}, {width = width, units = 100000000}))
  for _, line in ipairs(sized) do check(#line <= width, "summary overflows width " .. width) end
  local _, detailSized = flat(Display.detail(special, {width = width, units = 100000000}))
  for _, line in ipairs(detailSized) do check(#line <= width, "detail overflows width " .. width) end
end
local narrowFull = flat(Display.summary({special}, {kind = "routes", width = 40}))
check(narrowFull:gsub("%s+", " "):find(longName:gsub("%s+", " "), 1, true), "narrow summary retains the whole route")
local noDistance = flat(Display.detail({origin = "A", destination = "B", margin = 10, distance = 0}, {units = 100}))
check(noDistance:find("Profit per distance: ?", 1, true) and not noDistance:find("inf", 1, true))
special.resource = "literal\27[31m\t<red>"
local cleaned = flat(Display.detail(special, {}))
check(not cleaned:find("\27", 1, true) and not cleaned:find("\t", 1, true), "control bytes cannot inject output formatting")
check(cleaned:find("<red>", 1, true), "literal color tag is not parsed")
local function controls(output)
  local found = {}
  for _, line in ipairs(output) do
    for _, part in ipairs(line) do
      if part.command or part.fill then
        found[#found + 1] = part
        check(type(part.hint) == "string" and #part.hint > 0, "navigation has useful hover help")
        check(not (part.command and part.fill), "navigation either acts or prefills")
        check(not part.detail, "navigation is separate from route snapshots")
      end
    end
  end
  return found
end
local configuredControls = controls(Display.summary({trio}, config))
check(#configuredControls == 7 and configuredControls[5].command == "routes"
  and configuredControls[6].command == "settings" and configuredControls[7].command == "help", "summary navigation stays local")
check(configuredControls[1].command == "loops mixed" and configuredControls[1].color == "positive"
  and configuredControls[2].command == "loops 2" and configuredControls[3].command == "loops 3"
  and configuredControls[4].command == "loops 4", "all loop lengths are directly selectable")
local unsetControls = controls(Display.summary({trio}, {width = 40, capacitySet = false}))
check(unsetControls[5].fill == "cargoscan cargocapacity " and not unsetControls[5].command,
  "capacity shortcut opens input without changing the setting")
local emptyOutput = Display.summary({}, {width = 40, marketCount = 0})
local emptyText = flat(emptyOutput)
check(emptyText:find("Scan planet prices", 1, true), "empty market cache explains the next step")
local emptyControls = controls(emptyOutput)
check(emptyControls[5].command == "scan" and emptyControls[5].text == "[Scan prices]", "empty state has explicit scan action")
local customEmpty = flat(Display.summary({}, {width = 96, emptyReason = "Three fresh planets are needed."}))
check(customEmpty:find("Three fresh planets are needed.", 1, true), "adapter can explain the actual empty state")
local localOnly = controls(Display.detail(trio, config))
check(#localOnly == 2 and localOnly[1].command == "loops" and localOnly[2].command == "settings",
  "detail returns to its matching ranking without a scan")
local singleControls = controls(Display.detail(a, {capacitySet = false}))
check(singleControls[1].command == "routes" and singleControls[3].fill, "single-leg detail links to routes and capacity")
local counts = flat(Display.summary({trio, duo}, {width = 96, count = 1}))
check(counts:find("Showing 1 result |", 1, true), "result count reflects visible ranks")
local huge = {origin = "A", destination = "B", resource = "Food", margin = -1234567.89,
  buyPrice = 9999999.99, sellPrice = 8765432.10, distance = 123456.78}
local hugeDetails, hugeLines = flat(Display.detail(huge, {units = 1, capacitySet = true, width = 1000}))
check(hugeDetails:find("-1,234,567.89 credits", 1, true)
  and hugeDetails:find("9,999,999.99 credits each", 1, true)
  and hugeDetails:find("Total distance: 123,456.78", 1, true), "full amounts preserve signs, precision and grouping")
for _, line in ipairs(hugeLines) do check(#line <= 100, "detail stays readable on very wide consoles") end
local _, capped = flat(Display.summary({trio}, {width = 1000}))
for _, line in ipairs(capped) do check(#line <= 100, "summary stays readable on very wide consoles") end
local nan = flat(Display.detail({origin = "A", destination = "B", margin = 0/0, buyPrice = math.huge}, {}))
check(not nan:find("nan", 1, true) and not nan:find("inf", 1, true), "invalid amounts are shown as unknown")
local accented = {origin = "Planète", destination = "São José", resource = "Médicaments", margin = 2.5, buyPrice = 1, sellPrice = 3.5}
local accentedDetail = flat(Display.detail(accented, {width = 40}))
check(accentedDetail:find("Planète > São José", 1, true) and accentedDetail:find("Médicaments", 1, true),
  "ASCII control cleanup preserves accented UTF-8 text")
local utfSummary = flat(Display.summary({accented}, {kind = "routes", width = 80}))
check(utfSummary:find("Planète > São José", 1, true), "summary preserves accented UTF-8 text")
for _, label in ipairs({"2 planets", "3 planets", "4 planets"}) do
  local filters = controls(Display.summary({trio}, {stopsLabel = label, width = 40}))
  local active = 0
  for index = 1, 4 do
    if filters[index].color == "positive" then
      active = active + 1
      check(filters[index].text == "[" .. label .. "]", "the active loop filter matches the displayed scope")
    end
  end
  check(active == 1, "exactly one loop filter is active")
end
local routeControls = controls(Display.summary({a}, {kind = "routes", width = 40, capacitySet = true}))
check(#routeControls == 3 and routeControls[1].command == "loops", "single-leg routes do not show loop filters")
print("Display checks passed: " .. checks)
