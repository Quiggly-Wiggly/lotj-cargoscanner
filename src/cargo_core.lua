-- Market parsing and route calculations; independent of Mudlet.
local Core = {}

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function finite(value)
  local n = tonumber(value)
  if n and n == n and n ~= math.huge and n ~= -math.huge then return n end
end

local function key(value)
  return type(value) == "string" and trim(value):lower() or nil
end

local function validName(value)
  return type(value) == "string" and trim(value) ~= ""
    and not value:find("[%c]")
end

local Parser = {}
Parser.__index = Parser

-- feed(line) returns "continue"; "complete", record; or "error", message.
-- A nil expectedName uses the response's Planet field (for cache replay).
function Core.newParser(expectedName, now)
  assert(expectedName == nil or validName(expectedName), "expected planet name must be nonempty text or nil")
  return setmetatable({
    expectedName = expectedName and trim(expectedName) or nil, status = "continue", started = false,
    seen = {}, resourceKeys = {},
    record = { observedAt = finite(now) or os.time(), resources = {},
      resourceLines = {}, rawLines = {}, freeport = false },
  }, Parser)
end

function Parser:fail(message)
  self.status, self.result = "error", message
  return self.status, self.result
end

function Parser:field(name, value)
  if self.seen[name] then return self:fail("duplicate " .. name .. " field") end
  self.seen[name], self.record[name] = true, value
  return "continue"
end

local footer = "Use 'SHOWPLANET <planet> RESOURCES <resource>' for price history."

function Parser:feed(raw)
  if self.status ~= "continue" then return self.status, self.result end
  if type(raw) ~= "string" then return self:fail("response line is not text") end
  local line = trim(raw:gsub("\27%[[%d;]*m", ""))
  local header = line:match("^%-%-Planet Data:%s*%-+$")
  if not self.started then
    if not header then return "continue" end
    self.started = true
    self.record.rawLines[#self.record.rawLines + 1] = raw
    return "continue"
  end
  self.record.rawLines[#self.record.rawLines + 1] = raw
  if header then return self:fail("another planet response interrupted the market") end
  if line == "" then return "continue" end
  if line == footer then
    for _, name in ipairs({ "name", "system", "government", "taxRate" }) do
      if not self.seen[name] then return self:fail("missing " .. name .. " field") end
    end
    if not next(self.record.resources) then return self:fail("market has no resource quotes") end
    self.status, self.result = "complete", self.record
    return self.status, self.result
  end
  local value = line:match("^Planet:%s*(.+)$")
  if value then
    if self.expectedName and key(value) ~= key(self.expectedName) then
      return self:fail("expected " .. self.expectedName .. ", received " .. value)
    end
    self.expectedName = self.expectedName or trim(value)
    return self:field("name", trim(value))
  end
  value = line:match("^Starsystem:%s*(.+)$")
  if value then return self:field("system", trim(value)) end
  value = line:match("^Governed By:%s*(.+)$")
  if value then return self:field("government", trim(value)) end
  value = line:match("^Tax Rate:%s*(.-)$")
  if value then
    local tax = value:match("^%d+%.?%d*$") and finite(value)
    if not tax or tax < 0 or tax > 100 then return self:fail("invalid tax rate") end
    return self:field("taxRate", tax)
  end
  value = line:match("^(.-) is a freeport%.$")
  if value then
    if key(value) ~= key(self.expectedName or self.record.name) then return self:fail("freeport name does not match planet") end
    return self:field("freeport", true)
  end
  local resource, priceText = line:match("^(.-)%s+%(%s*Price per unit:%s*(.-)%)$")
  if resource then
    resource = trim(resource)
    -- The server pads short prices inside the parentheses, e.g. "6.16 ".
    priceText = trim(priceText)
    local price = priceText:match("^%d+%.?%d*$") and finite(priceText)
    if not validName(resource) or not price or price < 0 then return self:fail("invalid resource quote") end
    if self.resourceKeys[key(resource)] then return self:fail("duplicate resource " .. resource) end
    self.resourceKeys[key(resource)] = true
    self.record.resources[resource] = price
    self.record.resourceLines[#self.record.resourceLines + 1] = raw
    return "continue"
  end
  return self:fail("unexpected market line: " .. line)
end

-- Galaxy.Systems: system-name -> {x, y, planet-name = {...}}.
-- The LotJ UI adds planet/planets helpers to these same system tables.
function Core.planetsFromGMCP(systems)
  local planets = {}
  if type(systems) ~= "table" then return planets end
  for systemName, system in pairs(systems) do
    if validName(systemName) and type(system) == "table" then
      local function addPlanet(planetName, planet)
        if planetName ~= "planet" and planetName ~= "planets"
          and validName(planetName) and type(planet) == "table"
          and (planet.government ~= nil or planet.x ~= nil or planet.y ~= nil or planet.z ~= nil) then
          planets[key(planetName)] = {
            name = trim(planetName), system = trim(systemName),
            galaxyX = finite(system.x), galaxyY = finite(system.y),
            systemX = finite(planet.x), systemY = finite(planet.y), systemZ = finite(planet.z),
            government = type(planet.government) == "string" and planet.government or nil,
          }
          return true
        end
      end
      local foundNamedPlanet = false
      for planetName, planet in pairs(system) do
        if addPlanet(planetName, planet) then foundNamedPlanet = true end
      end
      -- Prefer original keyed records: repeated UI redraws can change the
      -- name inside a shared planet and copy that helper alias into the list.
      if not foundNamedPlanet and type(system.planets) == "table" then
        for _, planet in ipairs(system.planets) do
          if type(planet) == "table" then addPlanet(planet.name, planet) end
        end
      end
    end
  end
  return planets
end

local function settings(options)
  options = options or {}
  local units = finite(options.units or 1)
  local age = finite(options.maxAgeSeconds or 3600)
  local now = finite(options.now or os.time())
  local sort = options.sort or "distance"
  assert(units and units > 0, "units must be positive")
  assert(age and age >= 0, "maxAgeSeconds must be nonnegative")
  assert(now, "now must be a finite epoch timestamp")
  assert(sort == "distance" or sort == "margin", "sort must be distance or margin")
  assert(options.taxMode == nil or options.taxMode == "unknown", "tax semantics are not verified; use taxMode=unknown")
  return { units = units, maxAgeSeconds = age, now = now, sort = sort }
end

local function catalogByName(records)
  local result = {}
  for fallback, record in pairs(type(records) == "table" and records or {}) do
    if type(record) == "table" then
      local name = record.name or fallback
      if validName(name) then result[key(name)] = record end
    end
  end
  return result
end

local function freshMarkets(markets, options)
  local result = {}
  for name, market in pairs(catalogByName(markets)) do
    local at = finite(market.observedAt)
    if at and at <= options.now and options.now - at <= options.maxAgeSeconds then
      local quotes = {}
      for resource, value in pairs(type(market.resources) == "table" and market.resources or {}) do
        local price = finite(value)
        if validName(resource) and price and price >= 0 then
          quotes[key(resource)] = { name = resource, price = price }
        end
      end
      result[name] = { name = market.name or name, system = market.system,
        observedAt = at, quotes = quotes, taxRate = finite(market.taxRate),
        freeport = market.freeport == true }
    end
  end
  return result
end

local function distanceBetween(a, b, planets)
  local pa, pb = planets[key(a.name)], planets[key(b.name)]
  if not pa or not pb then return nil end
  -- A changed system assignment means the old market and new catalog disagree.
  if a.system and key(a.system) ~= key(pa.system) then return nil end
  if b.system and key(b.system) ~= key(pb.system) then return nil end
  local ax, ay, bx, by = finite(pa.galaxyX), finite(pa.galaxyY), finite(pb.galaxyX), finite(pb.galaxyY)
  if not ax or not ay or not bx or not by then return nil end
  local distance = math.sqrt((bx - ax)^2 + (by - ay)^2)
  return finite(distance)
end

local function route(a, b, resource, quote, other, distance, options)
  local margin = other.price - quote.price
  if margin <= 0 then return nil end
  return { origin = a.name, destination = b.name, resource = quote.name,
    buyPrice = quote.price, sellPrice = other.price, margin = margin,
    units = options.units, loadMargin = margin * options.units,
    distance = distance, score = distance and distance > 0 and margin / distance or nil,
    oldestAt = math.min(a.observedAt, b.observedAt),
    originTaxRate = a.taxRate, destinationTaxRate = b.taxRate,
    originFreeport = a.freeport, destinationFreeport = b.freeport,
    taxMode = "unknown", quoteOnly = true }
end

local function sortRows(rows, sort)
  table.sort(rows, function(a, b)
    if sort == "distance" then
      if a.score ~= nil and b.score == nil then return true end
      if a.score == nil and b.score ~= nil then return false end
      if a.score ~= nil and a.score ~= b.score then return a.score > b.score end
    end
    if a.margin ~= b.margin then return a.margin > b.margin end
    if a.origin ~= b.origin then return a.origin < b.origin end
    if a.destination ~= b.destination then return a.destination < b.destination end
    if a.path and b.path then return table.concat(a.path, "\0") < table.concat(b.path, "\0") end
    return (a.resource or "") < (b.resource or "")
  end)
  return rows
end

-- Distance ranking places unknown or zero distances after scored routes.
function Core.routes(markets, planets, options)
  local opts, result = settings(options), {}
  local live, catalog = freshMarkets(markets, opts), catalogByName(planets)
  for aKey, a in pairs(live) do
    for bKey, b in pairs(live) do
      if aKey ~= bKey then
        local distance = distanceBetween(a, b, catalog)
        for resource, quote in pairs(a.quotes) do
          if b.quotes[resource] then
            local row = route(a, b, resource, quote, b.quotes[resource], distance, opts)
            if row then result[#result + 1] = row end
          end
        end
      end
    end
  end
  return sortRows(result, opts.sort)
end

local function bestLegs(markets, planets, options)
  local graph = {}
  for _, row in ipairs(Core.routes(markets, planets, options)) do
    local origin, destination = key(row.origin), key(row.destination)
    graph[origin] = graph[origin] or {}
    local old = graph[origin][destination]
    if not old or row.margin > old.margin
      or (row.margin == old.margin and row.resource < old.resource) then
      graph[origin][destination] = row
    end
  end
  return graph
end

-- Legacy pair API: distance is one-way; totalDistance covers both legs.
function Core.roundTrips(markets, planets, options)
  local opts, result, pairsByOrigin = settings(options), {}, bestLegs(markets, planets, options)
  for origin, destinations in pairs(pairsByOrigin) do
    for destination, outbound in pairs(destinations) do
      local inbound = pairsByOrigin[destination] and pairsByOrigin[destination][origin]
      if origin < destination and inbound then
        local margin = outbound.margin + inbound.margin
        local totalDistance = outbound.distance and 2 * outbound.distance or nil
        result[#result + 1] = {
          origin = outbound.origin, destination = outbound.destination,
          outbound = outbound, inbound = inbound,
          margin = margin, loadMargin = margin * opts.units, units = opts.units,
          distance = outbound.distance, totalDistance = totalDistance,
          score = totalDistance and totalDistance > 0 and margin / totalDistance or nil,
          oldestAt = math.min(outbound.oldestAt, inbound.oldestAt),
          taxMode = "unknown", quoteOnly = true,
        }
      end
    end
  end
  return sortRows(result, opts.sort)
end

local function sortedKeys(values)
  local result = {}
  for name in pairs(values) do result[#result + 1] = name end
  table.sort(result)
  return result
end

-- Every leg must have a positive spread, including the return to the start.
-- Defaults to 2-3 planets; the returned path repeats the starting planet at the end.
function Core.loops(markets, planets, options)
  options = options or {}
  local opts = settings(options)
  local minimum, maximum = 2, 3
  if options.minStops ~= nil then minimum = finite(options.minStops) end
  if options.maxStops ~= nil then maximum = finite(options.maxStops) end
  if options.stops ~= nil then minimum, maximum = finite(options.stops), finite(options.stops) end
  assert(minimum and maximum and minimum % 1 == 0 and maximum % 1 == 0
    and minimum >= 2 and maximum <= 4 and minimum <= maximum,
    "loop stops must be an inclusive range of integers from 2 to 4")
  assert(options.start == nil or validName(options.start), "start must be a planet name")
  local start = key(options.start)
  local limit = options.limit ~= nil and finite(options.limit) or nil
  assert(options.limit == nil or (limit and limit >= 0 and limit % 1 == 0),
    "limit must be a nonnegative integer")
  if limit == 0 then return {} end
  local graph, result = bestLegs(markets, planets, options), {}
  local origins = start and { start } or sortedKeys(graph)
  local neighbors = {}
  for origin, destinations in pairs(graph) do neighbors[origin] = sortedKeys(destinations) end

  local function emit(openLegs, closingLeg)
    local legs, path, margin, totalDistance, oldestAt = {}, {}, 0, 0, math.huge
    for i = 1, #openLegs + 1 do
      local leg = openLegs[i] or closingLeg
      legs[i], path[i] = leg, leg.origin
      margin, oldestAt = margin + leg.margin, math.min(oldestAt, leg.oldestAt)
      if leg.distance == nil then totalDistance = nil
      elseif totalDistance ~= nil then totalDistance = totalDistance + leg.distance end
    end
    path[#path + 1] = closingLeg.destination
    result[#result + 1] = {
      origin = path[1], destination = path[2], legs = legs, path = path, stops = #legs,
      margin = margin, loadMargin = margin * opts.units, units = opts.units,
      totalDistance = totalDistance,
      score = totalDistance and totalDistance > 0 and margin / totalDistance or nil,
      oldestAt = oldestAt, taxMode = "unknown", quoteOnly = true,
    }
  end

  for _, origin in ipairs(origins) do
    local visited, openLegs = { [origin] = true }, {}
    local function visit(current, depth)
      if not graph[current] then return end
      if depth >= minimum and graph[current][origin] then emit(openLegs, graph[current][origin]) end
      if depth >= maximum then return end
      for _, destination in ipairs(neighbors[current]) do
        -- Canonical starting point removes rotations without removing reversals.
        if not visited[destination] and (start or destination > origin) then
          visited[destination] = true
          openLegs[#openLegs + 1] = graph[current][destination]
          visit(destination, depth + 1)
          openLegs[#openLegs], visited[destination] = nil, nil
        end
      end
    end
    visit(origin, 1)
  end
  sortRows(result, opts.sort)
  if limit then while #result > limit do result[#result] = nil end end
  return result
end

return Core
