-- Route views use literal text segments, not color markup.
local Display = {}

local function number(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge and n or nil
end
local function plain(s) return tostring(s or "?"):gsub("[%z\1-\31\127]", " ") end
local function length(s) return select(2, s:gsub("[^\128-\191]", "")) end
local function prefix(s, n)
  local at, seen = 1, 0
  while at <= #s and seen < n do
    at = at + 1
    while at <= #s and s:byte(at) >= 128 and s:byte(at) <= 191 do at = at + 1 end
    seen = seen + 1
  end
  return s:sub(1, at - 1)
end
local function clip(s, width)
  s = plain(s)
  if length(s) <= width then return s end
  return prefix(s, math.max(0, width - 3)) .. "..."
end
local function pad(s, width, right)
  s = clip(s, width)
  local spaces = string.rep(" ", math.max(0, width - length(s)))
  return right and (spaces .. s) or (s .. spaces)
end
local function segment(text, color, detail)
  return {text = plain(text), color = color or "text", detail = detail}
end
local function add(lines, text, color) lines[#lines + 1] = {segment(text, color)} end
local function compact(n, signed)
  if not number(n) then return "?" end
  local magnitude, suffix = math.abs(n), ""
  if magnitude >= 1000000000 then n, suffix = n / 1000000000, "b"
  elseif magnitude >= 1000000 then n, suffix = n / 1000000, "m"
  elseif magnitude >= 10000 then n, suffix = n / 1000, "k" end
  return string.format(signed and "%+.2f%s" or "%.2f%s", n, suffix)
end
local function exact(n, signed)
  if not number(n) then return "?" end
  local value = string.format(signed and "%+.2f" or "%.2f", n)
  local sign, whole, fraction = value:match("^([+-]?)(%d+)(%.%d+)$")
  return sign .. whole:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") .. fraction
end
local function integer(n)
  if not number(n) then return "?" end
  return string.format("%.0f", n):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end
local function legs(row)
  if type(row.legs) == "table" and #row.legs > 0 then return row.legs end
  if row.outbound and row.inbound then return {row.outbound, row.inbound} end
  return {row}
end
local function path(row)
  local route, parts = legs(row), {}
  parts[1] = plain(route[1].origin)
  for _, leg in ipairs(route) do parts[#parts + 1] = plain(leg.destination) end
  return table.concat(parts, " > ")
end
local function distance(row)
  if #legs(row) > 1 then return row.totalDistance end
  return row.distance
end
local function units(config, row)
  local n = number(config.units) or number(row and row.units) or 1
  return n > 0 and n or 1
end
local function capacity(config, row)
  local amount = units(config, row)
  local configured = config.capacitySet == true or (config.capacitySet == nil and amount > 1)
  return configured and amount or 1, configured
end
local function efficiency(row, amount)
  local routeDistance, margin = number(distance(row)), number(row.margin)
  if not routeDistance or routeDistance <= 0 or not margin then return "?" end
  local value = number(margin * amount / routeDistance)
  if not value then return "?" end
  return math.abs(value) >= 10000 and compact(value) or string.format("%.3f", value)
end
local function age(at, now)
  if not number(at) or at > now then return "unknown" end
  return string.format("%.1f min ago", (now - at) / 60)
end
local function wrapped(lines, text, width, color)
  local rest = plain(text)
  while length(rest) > width do
    local part = prefix(rest, width)
    local split = part:match("^.*() ")
    if not split or split < width / 2 then split = #part + 1 end
    add(lines, rest:sub(1, split - 1), color)
    rest = rest:sub(split):gsub("^ +", "")
  end
  add(lines, rest, color)
end
local function consoleWidth(config)
  return math.max(40, math.min(100, math.floor(number(config.width) or 96)))
end
local function blank(lines) lines[#lines + 1] = {} end
local function rule(lines, width) add(lines, string.rep("-", width), "muted") end
local function action(text, command, hint, fill)
  return {text = "[" .. text .. "]", color = "rank", command = command, fill = fill, hint = hint}
end
local function actions(lines, width, items)
  local line, used = {}, 0
  for _, item in ipairs(items) do
    local size = length(item.text)
    if #line > 0 and used + 2 + size > width then
      lines[#lines + 1], line, used = line, {}, 0
    end
    if #line > 0 then line[#line + 1] = segment("  "); used = used + 2 end
    line[#line + 1], used = item, used + size
  end
  if #line > 0 then lines[#lines + 1] = line end
end
local function navigation(lines, width, kind, configured)
  local items = {action(kind == "routes" and "Loops" or "Routes", kind == "routes" and "loops" or "routes",
    kind == "routes" and "Compare profitable round trips" or "Compare single cargo legs"),
    action("Settings", "settings", "View cargo capacity and ranking settings"),
    action("Help", "help", "Show all cargo scanner commands")}
  if not configured then
    table.insert(items, 1, action("Set capacity", nil, "Enter your ship's cargo capacity", "cargoscan cargocapacity "))
  end
  actions(lines, width, items)
end

function Display.summary(rows, config)
  config, rows = config or {}, rows or {}
  local width = consoleWidth(config)
  local limit = math.max(0, math.floor(number(config.count) or 10))
  local amount, configured = capacity(config)
  local lines = {}
  local kind = config.kind == "routes" and "ROUTES" or "LOOPS"
  add(lines, "CARGO / " .. kind, "title")
  local scope = kind == "LOOPS" and (plain(config.stopsLabel or "2-3 planets") .. " | ") or "Single cargo legs | "
  local markets = config.marketCount and (integer(config.marketCount) .. " fresh markets") or "Saved market prices"
  wrapped(lines, scope .. markets, width, "muted")
  if kind == "LOOPS" then
    local stops = config.stopsLabel or "2-3 planets"
    local filters = {
      action("Mixed", "loops mixed", "Compare 2- and 3-planet loops"),
      action("2 planets", "loops 2", "Compare 2-planet loops"),
      action("3 planets", "loops 3", "Compare 3-planet loops"),
      action("4 planets", "loops 4", "Compare 4-planet loops"),
    }
    local labels = {"2-3 planets", "2 planets", "3 planets", "4 planets"}
    for i, label in ipairs(labels) do if stops == label then filters[i].color = "positive" end end
    actions(lines, width, filters)
  end
  local capacityText = configured and ("Cargo capacity: " .. integer(amount) .. (amount == 1 and " unit" or " units"))
    or "Cargo capacity not set | showing profit per unit"
  wrapped(lines, capacityText, width, "text")
  if config.maxAgeMinutes then
    wrapped(lines, "Prices no older than " .. plain(config.maxAgeMinutes) .. " min", width, "muted")
  end
  local shown = math.min(limit, #rows)
  if shown > 0 then
    blank(lines)
    wrapped(lines, string.format("Showing %d %s | ", shown, shown == 1 and "result" or "results")
      .. (config.sort == "margin" and "Ranked by profit" or "Ranked by profit per distance"), width, "muted")
  end
  rule(lines, width)
  local narrow, valueTitle = width < 80, configured and "PROFIT" or "PROFIT/UNIT"
  local efficiencyTitle = "PER DIST"
  local pathWidth = width - 40
  if #rows > 0 and limit > 0 and narrow then
    add(lines, " #   " .. (kind == "LOOPS" and "CIRCUIT" or "ROUTE / CARGO"), "muted")
  elseif #rows > 0 and limit > 0 then
    add(lines, pad(" #", 3) .. "  " .. pad(kind == "LOOPS" and "CIRCUIT" or "ROUTE / CARGO", pathWidth)
      .. "  " .. pad(valueTitle, 12, true) .. "  " .. pad("DIST", 8, true)
      .. "  " .. pad(efficiencyTitle, 9, true), "muted")
  end
  for i = 1, math.min(limit, #rows) do
    local row = rows[i]
    local label = path(row)
    if kind == "ROUTES" then label = label .. " / " .. plain(row.resource) end
    local value = number(row.margin) and row.margin * amount or nil
    local rank = segment(pad(string.format("%02d", i), 3, true), "rank", row)
    if narrow then
      local labelLines = {}
      wrapped(labelLines, label, width - 5, "text")
      lines[#lines + 1] = {rank, segment("  " .. labelLines[1][1].text, "text")}
      for line = 2, #labelLines do add(lines, "     " .. labelLines[line][1].text, "text") end
      wrapped(lines, "     Profit: " .. compact(value, true) .. (configured and " credits" or " credits per unit"), width, "positive")
      wrapped(lines, "     Distance: " .. compact(distance(row)), width, "muted")
      wrapped(lines, "     Profit / distance: " .. efficiency(row, amount), width, "muted")
      if i < math.min(limit, #rows) then blank(lines) end
    else
      lines[#lines + 1] = {rank, segment("  " .. pad(label, pathWidth) .. "  "),
        segment(pad(compact(value, true), 12, true), "positive"),
        segment("  " .. pad(compact(distance(row)), 8, true) .. "  " .. pad(efficiency(row, amount), 9, true), "muted")}
    end
  end
  if #rows == 0 then
    blank(lines)
    wrapped(lines, "No matching " .. kind:lower() .. " yet", width, "title")
    wrapped(lines, config.emptyReason or (config.marketCount == 0 and "Scan planet prices to find cargo opportunities."
      or "No profitable routes match your current prices and settings."), width, "muted")
    blank(lines)
    actions(lines, width, {action("Scan prices", "scan", "Scan all planets for current resource prices")})
    blank(lines)
  end
  rule(lines, width)
  if #rows > 0 and limit > 0 then wrapped(lines, "Show the route details with cargoscan show <number>.", width, "rank") end
  wrapped(lines, "Profit is estimated from listed prices, before tax and fuel.", width, "muted")
  wrapped(lines, "Distance is the total route length on the galaxy map.", width, "muted")
  blank(lines)
  navigation(lines, width, kind:lower(), configured)
  return lines
end

function Display.detail(row, config)
  config = config or {}
  local lines, route = {}, legs(row)
  local amount, configured = capacity(config, row)
  local now = number(config.now) or os.time()
  local width = consoleWidth(config)
  add(lines, "CARGO / " .. (#route > 1 and "LOOP DETAILS" or "ROUTE DETAILS"), "title")
  wrapped(lines, path(row), width, "text")
  local trip = #route > 1 and "loop" or "trip"
  local total = exact(number(row.margin) and row.margin * amount, true)
  blank(lines)
  wrapped(lines, "ESTIMATED " .. trip:upper() .. " PROFIT", width, "muted")
  wrapped(lines, total .. " credits" .. (configured and "" or " per unit"), width, "positive")
  wrapped(lines, "Before tax and fuel | " .. #route .. (#route == 1 and " leg" or " legs"), width, "muted")
  wrapped(lines, configured and ("Cargo capacity: " .. integer(amount) .. (amount == 1 and " unit" or " units") .. " on each leg")
    or "Cargo capacity not set; showing one unit on each leg.", width, "text")
  wrapped(lines, "Total distance: " .. exact(distance(row)) .. " | Oldest price: " .. age(row.oldestAt, now), width, "muted")
  wrapped(lines, "Profit per distance: " .. efficiency(row, amount) .. " credits"
    .. (configured and "" or " per unit"), width, "muted")
  for i, leg in ipairs(route) do
    blank(lines)
    rule(lines, width)
    wrapped(lines, string.format("LEG %d / %d  ", i, #route) .. plain(leg.resource), width, "title")
    wrapped(lines, plain(leg.origin) .. " > " .. plain(leg.destination), width, "text")
    blank(lines)
    wrapped(lines, "Buy  " .. integer(amount) .. (amount == 1 and " unit" or " units") .. " at " .. exact(leg.buyPrice)
      .. " credits each", width, "text")
    wrapped(lines, "     Pay " .. exact(number(leg.buyPrice) and leg.buyPrice * amount) .. " credits at " .. plain(leg.origin), width, "muted")
    wrapped(lines, "Sell " .. integer(amount) .. (amount == 1 and " unit" or " units") .. " at " .. exact(leg.sellPrice)
      .. " credits each", width, "text")
    wrapped(lines, "     Receive " .. exact(number(leg.sellPrice) and leg.sellPrice * amount) .. " credits at " .. plain(leg.destination), width, "muted")
    wrapped(lines, "Leg profit: " .. exact(number(leg.margin) and leg.margin * amount, true)
      .. " credits" .. (configured and "" or " per unit"), width, "positive")
    local function tax(n) return number(n) and (exact(n) .. "%") or "unknown" end
    wrapped(lines, "Listed taxes (not applied): origin " .. tax(leg.originTaxRate)
      .. "; destination " .. tax(leg.destinationTaxRate), width, "muted")
    wrapped(lines, "Distance: " .. exact(leg.distance) .. " | Oldest price: " .. age(leg.oldestAt, now), width, "muted")
  end
  rule(lines, width)
  wrapped(lines, "Profit is estimated from listed prices, before tax and fuel.", width, "muted")
  wrapped(lines, "Distance is the total route length on the galaxy map.", width, "muted")
  blank(lines)
  local items = {action("Back to " .. (#route > 1 and "loops" or "routes"), #route > 1 and "loops" or "routes", "Show current ranked results"),
    action("Settings", "settings", "View cargo capacity and ranking settings")}
  if not configured then items[#items + 1] = action("Set capacity", nil, "Enter your ship's cargo capacity", "cargoscan cargocapacity ") end
  actions(lines, width, items)
  return lines
end

return Display
