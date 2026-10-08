-- Resolve ME zones and additional configured circles without editing mission data.
local TrainingZones = { circles = {} }
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
function TrainingZones.Find(name)
    local zone = ZONE:FindByName(name)
    if zone then return zone end
    if TrainingZones.circles[name] then return TrainingZones.circles[name] end
    local definition = (Config.zoneDefinitions or {})[name]
    if not definition then return nil end
    local center, radius = definition.center, definition.radiusMeters
    assert(type(center) == "table" and finite(center.x) and finite(center.y)
        and finite(radius) and radius > 0, "Invalid training zone definition: " .. name)
    -- DoNotRegisterZone keeps these circles out of the ME/global zone database.
    zone = assert(ZONE_RADIUS:New(name, { x = center.x, y = center.y }, radius, true),
        "Training zone construction failed: " .. name)
    TrainingZones.circles[name] = zone
    return zone
end
return TrainingZones
