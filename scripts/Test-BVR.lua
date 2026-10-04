-- Run from the repository root with Lua 5.1 (DCS bin/luae.exe also works).
-- Exercises the real mission script with simulated DCS/MOOSE boundaries.
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.00001,
        string.format("expected %.8f, got %.8f", expected, actual))
end

local function nearHeading(actual, expected)
    -- Floating-point rounding can represent a north heading as either 0 or 360.
    near((actual - expected + 180) % 360 - 180, 0)
end

local function scenario()
    local s = { time = 0, timers = {}, messages = {}, spawns = {}, randomValues = {} }
    local p = { alive = true, airborne = false, id = 1, name = "Pilot",
        position = { x = 100, y = 200, z = 300 }, heading = 0 }
    function p:IsAlive() return self.alive end
    function p:InAir() return self.airborne end
    function p:GetID() return self.id end
    function p:GetPlayerName() return self.name end
    function p:GetVec3() return self.position end
    function p:GetHeading() return self.heading end
    local dcsPlayer = {}
    function dcsPlayer:isExist() return p.alive end
    function dcsPlayer:getName() return "PlayerUnit" end
    s.player = p
    s.players = { dcsPlayer }

    local coordinate = { WaypointAltType = { BARO = "BARO" } }
    coordinate.__index = coordinate
    function coordinate:NewFromVec3(v)
        return setmetatable({ x = v.x, y = v.y, z = v.z }, coordinate)
    end
    function coordinate:Translate(distance, heading, keepAltitude)
        assert(keepAltitude == true)
        local radians = math.rad(heading)
        return self:NewFromVec3({ x = self.x + distance * math.cos(radians),
            y = self.y, z = self.z + distance * math.sin(radians) })
    end
    function coordinate:SetAltitude(altitude, asl)
        assert(asl == true)
        self.y = altitude
    end
    function coordinate:GetVec3() return { x = self.x, y = self.y, z = self.z } end
    function coordinate:HeadingTo(other)
        return math.deg(math.atan2(other.z - self.z, other.x - self.x)) % 360
    end
    function coordinate:WaypointAirTurningPoint(altitudeType, speed, tasks)
        return { position = self:GetVec3(), altitudeType = altitudeType,
            speed = speed, tasks = tasks }
    end
    coordinate.WaypointAirFlyOverPoint = coordinate.WaypointAirTurningPoint

    local spawn = {}
    function spawn:New(template)
        assert(template == "TPL_BVR_MIG29_2")
        return setmetatable({}, { __index = spawn })
    end
    function spawn:InitHeading(heading) self.heading = heading; return self end
    function spawn:SpawnFromVec3(position)
        if s.failSpawn then return nil end
        local g = { position = position, heading = self.heading, alive = true }
        function g:EnRouteTaskEngageTargets(distance, types, priority)
            assert(distance == nil and priority == 0)
            assert(#types == 2 and types[1] == "Fighters" and types[2] == "Multirole fighters")
            return { id = "EngageTargets", types = types }
        end
        function g:OptionROEOpenFire() self.openFire = true end
        function g:Route(route) self.route = route end
        function g:IsAlive() return self.alive end
        table.insert(s.spawns, g)
        return g
    end

    local env = setmetatable({ COORDINATE = coordinate, SPAWN = spawn }, { __index = _G })
    env.math = setmetatable({}, { __index = math })
    function env.math.random(minimum, maximum)
        local value = table.remove(s.randomValues, 1) or minimum
        assert(value >= minimum and value <= maximum, "random bounds changed")
        return value
    end
    env.trigger = { action = { outText = function() end } }
    env.coalition = { side = { BLUE = 2 }, getPlayers = function() return s.players end }
    env.UNIT = { FindByName = function(_, name)
        assert(name == "PlayerUnit"); return p
    end }
    env.MESSAGE = { New = function(_, message)
        table.insert(s.messages, message)
        return { ToBlue = function() end }
    end }
    env.timer = {
        getTime = function() return s.time end,
        scheduleFunction = function(callback, arg, due)
            table.insert(s.timers, { callback = callback, arg = arg, due = due })
        end
    }
    env.MENU_COALITION = { New = function() return {} end }
    env.MENU_COALITION_COMMAND = { New = function(_, side, title, menu, callback)
        s.generate = callback
    end }
    local mission = assert(loadfile("src/DynamicTraining.lua"))
    setfenv(mission, env)()
    function s:tick(time)
        self.time = time
        for _, scheduled in ipairs(self.timers) do
            if scheduled.due <= time then
                scheduled.due = scheduled.callback(scheduled.arg, time)
            end
        end
    end
    function s:lastMessageContains(fragment)
        assert(string.find(self.messages[#self.messages], fragment, 1, true))
    end
    return s
end

local count = 0
local function test(name, callback)
    callback()
    count = count + 1
    print("PASS: " .. name)
end

test("takeoff delay, latest position/heading, duplicate requests", function()
    local s = scenario()
    s.generate()
    s:tick(2)
    assert(#s.spawns == 0)
    s.player.airborne = true
    s:tick(4) -- detected at 4, due at 24
    s.generate()
    s:lastMessageContains("already armed")
    for t = 6, 22, 2 do s:tick(t); assert(#s.spawns == 0) end
    s.player.position = { x = 5000, y = 1000, z = 8000 }
    s.player.heading = 90
    s.randomValues = { 80, 30000, 60 }
    s:tick(24)
    assert(#s.spawns == 1)
    local g = s.spawns[1]
    near(g.position.x, 5000 + math.cos(math.rad(150)) * 80 * 1852)
    near(g.position.z, 8000 + math.sin(math.rad(150)) * 80 * 1852)
    near(g.position.y, 30000 * 0.3048)
    near(g.heading, 330)
    assert(g.openFire and g.route[1].tasks[1].id == "EngageTargets")
    near(g.route[1].speed, 828)
    assert(g.route[1].altitudeType == "BARO")
    near(g.route[2].position.x, 5000 - math.cos(math.rad(150)) * 20 * 1852)
    near(g.route[2].position.z, 8000 - math.sin(math.rad(150)) * 20 * 1852)
    s.generate(); s:tick(26)
    assert(#s.spawns == 1)
    s:lastMessageContains("already active")
end)

test("touchdown resets countdown until next takeoff", function()
    local s = scenario()
    s.generate(); s.player.airborne = true; s:tick(2)
    s.player.airborne = false; s:tick(10)
    s:lastMessageContains("countdown reset")
    s.player.airborne = true; s:tick(12)
    s:tick(22); s:tick(30); assert(#s.spawns == 0)
    s:tick(32); assert(#s.spawns == 1)
end)

test("death, departure, aircraft replacement and occupant change cancel", function()
    for _, change in ipairs({
        function(p) p.alive = false end,
        function(p) p.name = nil end,
        function(p) p.id = 2 end,
        function(p) p.name = "OtherPilot" end
    }) do
        local s = scenario()
        s.generate(); s.player.airborne = true; s:tick(2)
        change(s.player); s:tick(4)
        s:lastMessageContains("reservation cancelled")
        s.player.alive = true; s.player.id = 1; s.player.name = "Pilot"
        s:tick(22); assert(#s.spawns == 0)
        s.generate(); assert(#s.spawns == 1)
    end
end)

test("reservation keeps selected aircraft when BLUE player order changes", function()
    local s = scenario()
    s.generate()
    s.players = { { isExist = function() error("must not reselect player") end } }
    s:tick(2); assert(#s.spawns == 0)
    s.player.airborne = true; s:tick(4); s:tick(24)
    assert(#s.spawns == 1)
end)

test("airborne request is immediate; completion allows next request", function()
    local s = scenario()
    s.player.airborne = true; s.generate(); assert(#s.spawns == 1)
    s.spawns[1].alive = false; s:tick(2)
    s:lastMessageContains("BVR MISSION COMPLETE")
    s.generate(); assert(#s.spawns == 2)
end)

test("spawn failure clears reservation and permits retry", function()
    local s = scenario()
    s.generate(); s.player.airborne = true; s:tick(2)
    s.failSpawn = true; s:tick(22)
    s:lastMessageContains("spawn failed")
    s.failSpawn = false; s.generate(); assert(#s.spawns == 1)
end)

test("no player or AI-only aircraft does not arm", function()
    local s = scenario()
    s.players = {}; s.generate(); s:lastMessageContains("not found")
    s = scenario()
    s.player.name = nil; s.generate(); s:lastMessageContains("not found")
    s.player.name = "Pilot"; s.player.airborne = true
    s:tick(22); assert(#s.spawns == 0)
    s.generate(); assert(#s.spawns == 1)
end)

test("range, sector, HOT and through route across boundary bearings", function()
    for _, heading in ipairs({ 0, 45, 90, 180, 270, 359 }) do
        for _, offset in ipairs({ -60, 0, 60 }) do
            for _, distance in ipairs({ 60, 70, 80 }) do
                local s = scenario()
                s.player.airborne = true; s.player.heading = heading
                s.randomValues = { distance, 15000, offset }; s.generate()
                local g, p = s.spawns[1], s.player.position
                local dx, dz = g.position.x - p.x, g.position.z - p.z
                near(math.sqrt(dx * dx + dz * dz), distance * 1852)
                local bearing = (heading + offset) % 360
                near(dx, math.cos(math.rad(bearing)) * distance * 1852)
                near(dz, math.sin(math.rad(bearing)) * distance * 1852)
                nearHeading(g.heading, (bearing + 180) % 360)
                near(g.route[2].position.x - p.x, -dx * 20 / distance)
                near(g.route[2].position.z - p.z, -dz * 20 / distance)
            end
        end
    end
end)

print(string.format("All %d BVR tests passed (simulated DCS/MOOSE).", count))
