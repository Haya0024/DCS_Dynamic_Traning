-- Test-ZoneCoverage.ps1 prepends the unchanged mission entry from the real .miz.
assert(mission and mission.theatre == "Syria", "Syria mission data required")
local config = dofile("src/config.lua")
local scenario = dofile("scripts/Intercept-TestHarness.lua")
assert(config.zoneDefinitions == nil, "ME must be the only training-zone geometry source")
local me, zoneIDs = {}, {}
for _, zone in ipairs(mission.triggers.zones) do
    assert(not me[zone.name] and not zoneIDs[zone.zoneId], "Duplicate ME zone name or ID")
    me[zone.name], zoneIDs[zone.zoneId] = zone, true
end
for _, category in ipairs({ "cap", "sead" }) do
    for _, name in ipairs(config[category].zones) do
        local zone = assert(me[name], "Configured zone must exist in ME: " .. name)
        assert(zone.type == 0 and zone.radius == 18288 and zone.hidden == false,
            "Visible 18,288 m circular ME zone required: " .. name)
    end
end
assert(#config.cap.zones == 9 and #config.sead.zones == 10)
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
        local z = me[name]
        assert(z, "Missing configured zone: " .. name)
        local center = { x = z.x, y = z.y }
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

local s = scenario()
local actual = {}
for name, z in pairs(me) do actual[name] = circle(name, { x = z.x, y = z.y }, z.radius) end
s.zones = actual
s.player.airborne = true
-- Missing migrated CAP zones must fail safely, rather than fabricate a Lua circle.
local missing = s.zones.CAP_ZONE_CYPRUS_WEST
s.zones.CAP_ZONE_CYPRUS_WEST = nil
s:command("Task: CAP")
assert(not s:mission() and #s.spawns == 0 and #s.errors == 1)
s.zones.CAP_ZONE_CYPRUS_WEST = missing
s:command("Task: CAP")
local record = assert(s:mission(), "Missing ME zone must not leave an acceptance lock")
assert(record.capPlan.zone == s.zones[record.capPlan.name], "CAP must use the existing ME object")
s:command("Abort Mission")
-- SEAD also needs an actual eligible ME zone; no runtime fallback may rescue it.
s.zones = {}
s:command("Task: SEAD")
assert(not s:mission() and #s.spawns == 0 and #s.errors == 2)
s.zones = actual
s:command("Task: SEAD")
record = assert(s:mission(), "Missing SEAD zones must not leave an acceptance lock")
s:tick(s.time + 1)
assert(record.state == "ACTIVE" and record.spawn.group.fromVec2 and #s.spawns == 1)
assert(s.zones[record.plan.zoneName]:IsVec2InZone(record.plan.actualSpawnPoint))
s:command("Abort Mission")
assert(not s:mission())
print("PASS: ME is the only zone source; missing zones fail safely and release locks for retry")
