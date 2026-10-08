-- Test-ZoneCoverage.ps1 prepends the unchanged mission entry from the real .miz.
assert(mission and mission.theatre == "Syria", "Syria mission data required")
local config = dofile("src/config.lua")
local scenario = dofile("scripts/Intercept-TestHarness.lua")
local me = {}
for _, zone in ipairs(mission.triggers.zones) do me[zone.name] = zone end
local function circle(name, point, radius)
    local zone = { name = name, center = point, radius = radius }
    function zone:GetVec2() return self.center end
    function zone:GetRadius() return self.radius end
    function zone:GetRandomVec2() return self.center end
    function zone:IsVec2InZone(p)
        return (p.x - self.center.x)^2 + (p.y - self.center.y)^2 <= self.radius^2
    end
    function zone:IsVec3InZone(p) return self:IsVec2InZone({ x = p.x, y = p.z }) end
    return zone
end
local function eligible(category, origin)
    local found, cfg = {}, config[category]
    for _, name in ipairs(cfg.zones) do
        local z = me[name] or config.zoneDefinitions[name]
        assert(z, "Missing configured zone: " .. name)
        local center = z.center or { x = z.x, y = z.y }
        local distance = math.sqrt((center.x - origin.x)^2 + (center.y - origin.y)^2) / 1852
        if distance >= cfg.minDistanceNM and distance <= cfg.maxDistanceNM then found[#found + 1] = name end
    end
    return found
end
local origins, slots = {}, 0
for _, country in pairs(mission.coalition.blue.country) do
    for _, group in pairs((country.plane or {}).group or {}) do
        local start = group.route and group.route.points and group.route.points[1]
        for _, unit in pairs(group.units) do
            if unit.type == config.playerType and (unit.skill == "Client" or unit.skill == "Player")
                and start and (start.airdromeId or start.linkUnit) then
                local origin = { x = unit.x, y = unit.y }
                local key = start.airdromeId and "airfield:" .. start.airdromeId or "carrier:" .. start.linkUnit
                origins[key] = origins[key] or origin
                for _, category in ipairs({ "cap", "sead" }) do
                    local n = #eligible(category, origin)
                    assert(n >= 2 and n <= 3, unit.name .. ": " .. category .. " candidates=" .. n)
                end
                slots = slots + 1
            end
        end
    end
end
local bases = 0
for key, origin in pairs(origins) do
    bases = bases + 1
    local s = scenario()
    s.zones = {}
    for name, z in pairs(me) do
        assert(z.type == 0, "Circular ME zone required: " .. name)
        s.zones[name] = circle(name, { x = z.x, y = z.y }, z.radius)
    end
    for _, category in ipairs({ "cap", "sead" }) do
        local candidates = eligible(category, origin)
        for index, name in ipairs(candidates) do
            s.player.position = { x = origin.x, y = 0, z = origin.y }
            s.player.airborne = category == "sead"
            s.randomValues = category == "cap" and { index, 1, 30 } or { 2, 2, index }
            s:command(category == "cap" and "Task: CAP" or "Task: SEAD")
            local record = assert(s:mission(), key .. " cannot accept " .. name)
            if category == "cap" then
                assert(record.capPlan.name == name and record.state == "ACTIVE")
            else
                assert(record.plan.zoneName == name)
                s:tick(s.time + 1)
                assert(record.state == "ACTIVE" and record.spawn.group.fromVec2)
                assert(record.spawn.group.position.x == record.plan.actualSpawnPoint.x)
            end
            s:command("Abort Mission")
            assert(not s:mission() and #s.errors == 0)
        end
    end
    print("Coverage " .. key .. ": CAP=" .. #eligible("cap", origin) .. ", SEAD=" .. #eligible("sead", origin))
end
assert(bases == 5 and slots >= 5, "All four airfields and carrier slots must be covered")
print("PASS: actual .miz departure slots have 2-3 CAP/SEAD areas; every candidate accepts and spawns in simulation")

local constructors = 0
local cfg = { zoneDefinitions = { Extra = { center = { x = 1, y = 2 }, radiusMeters = 100 } } }
local existing = circle("ME", { x = 9, y = 8 }, 100)
local env = setmetatable({ Config = cfg,
    ZONE = { FindByName = function(_, name) return name == "ME" and existing or nil end },
    ZONE_RADIUS = { New = function(_, name, center, radius, unregistered)
        assert(unregistered == true); constructors = constructors + 1
        return circle(name, center, radius)
    end } }, { __index = _G })
local chunk = assert(loadfile("src/training_zones.lua")); setfenv(chunk, env)
local zones = chunk()
local extra = zones.Find("Extra")
assert(zones.Find("Extra") == extra and constructors == 1 and not zones.Find("Missing"))
cfg.zoneDefinitions.Extra.center.x = 999
assert(extra:GetVec2().x == 1, "Runtime center must be a detached copy")
cfg.zoneDefinitions.ME = { center = { x = 0, y = 0 }, radiusMeters = 10 }
assert(zones.Find("ME") == existing and existing:GetVec2().x == 9 and constructors == 1)
for _, invalid in ipairs({ { center = {}, radiusMeters = 1 },
    { center = { x = math.huge, y = 0 }, radiusMeters = 1 },
    { center = { x = 0, y = 0 }, radiusMeters = 0 },
    { center = { x = 0, y = 0 }, radiusMeters = 0/0 } }) do
    cfg.zoneDefinitions.Invalid = invalid
    assert(not pcall(zones.Find, "Invalid"))
end
print("PASS: additional MOOSE circles are cached, unregistered and validated; ME circles stay unchanged")
