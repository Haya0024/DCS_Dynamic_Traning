-- Build first: powershell -File scripts/Build-Mission.ps1
local scenario = dofile("scripts/Intercept-TestHarness.lua")
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.00001, string.format("expected %.8f, got %.8f", expected, actual))
end
local function nearHeading(actual, expected)
    near((actual - expected + 180) % 360 - 180, 0)
end
local count = 0
local function test(name, callback)
    callback(); count = count + 1; print("PASS: " .. name)
end

test("takeoff delay, latest position/heading, duplicate requests", function()
    local s = scenario()
    s.generate(); s:tick(2); assert(#s.spawns == 0)
    s.player.airborne = true; s:tick(4)
    s.generate(); s:lastMessageContains("already armed")
    for t = 6, 22, 2 do s:tick(t); assert(#s.spawns == 0) end
    s.player.position = { x = 5000, y = 1000, z = 8000 }; s.player.heading = 90
    s.randomValues = { 80, 30000, 60 }; s:tick(24)
    assert(#s.spawns == 1)
    local g = s.spawns[1]
    near(g.position.x, 5000 + math.cos(math.rad(150)) * 80 * 1852)
    near(g.position.z, 8000 + math.sin(math.rad(150)) * 80 * 1852)
    near(g.position.y, 30000 * 0.3048); nearHeading(g.heading, 330)
    assert(g.openFire and g.route[1].tasks[1].id == "EngageTargets")
    near(g.route[1].speed, 828); assert(g.route[1].altitudeType == "BARO")
    near(g.route[2].position.x, 5000 - math.cos(math.rad(150)) * 20 * 1852)
    near(g.route[2].position.z, 8000 - math.sin(math.rad(150)) * 20 * 1852)
    s.generate(); s:tick(26); assert(#s.spawns == 1)
    s:lastMessageContains("already active"); s:assertClean()
end)

test("touchdown resets countdown until next takeoff", function()
    local s = scenario()
    s.generate(); s.player.airborne = true; s:tick(2)
    s.player.airborne = false; s:tick(10); s:lastMessageContains("countdown reset")
    s.player.airborne = true; s:tick(12)
    s:tick(22); s:tick(30); assert(#s.spawns == 0)
    s:tick(32); assert(#s.spawns == 1); s:assertClean()
end)

test("death, departure, replacement and occupant change cancel reservation", function()
    for _, change in ipairs({
        function(p) p.alive = false end, function(p) p.name = nil end,
        function(p) p.id = 20 end, function(p) p.name = "OtherPilot" end
    }) do
        local s = scenario()
        s.generate(); s.player.airborne = true; s:tick(2)
        change(s.player); s:tick(4); s:lastMessageContains("reservation cancelled")
        s.player.alive = true; s.player.id = 10; s.player.name = "Pilot"
        s:tick(22); assert(#s.spawns == 0); s:tick(24)
        s.generate(); assert(#s.spawns == 1); s:assertClean()
    end
end)

test("player ordering and AI wingman takeoff never replace reservation owner", function()
    local s = scenario()
    local other = s:addPilot("Other", "ucid-b", 20)
    s.generate(); other.airborne = true; s.wingman.airborne = true
    s.players = { other.raw, s.player.raw }; s:tick(2); s:tick(24)
    assert(#s.spawns == 0)
    s.player.airborne = true; s:tick(26); s:tick(46)
    assert(#s.spawns == 1); s:assertClean()
end)

test("airborne request is immediate; RTB phase blocks next request", function()
    local s = scenario()
    s.player.airborne = true; s.generate(); assert(#s.spawns == 1)
    s:complete(); s:lastMessageContains("PRIMARY OBJECTIVE COMPLETE")
    s.generate(); assert(#s.spawns == 1)
    s:command("Abort Mission"); s.generate(); assert(#s.spawns == 2); s:assertClean()
end)

test("spawn, formation and route failures clean up and permit retry", function()
    for _, failure in ipairs({ "failSpawn", "failFormation", "failRoute" }) do
        local s = scenario()
        s.generate(); s.player.airborne = true; s:tick(2)
        s[failure] = true; s:tick(22); s:lastMessageContains("spawn failed")
        if failure ~= "failSpawn" then assert(s.spawns[1].destroyed) end
        s[failure] = false; s.generate()
        assert(s.spawns[#s.spawns].route)
        s:score(0)
    end
end)

test("empty group cannot arm; occupied MP2 is registered as one wing", function()
    local s = scenario()
    s.player.name = nil; s.generate(); s:lastMessageContains("At least one")
    s.player.name = "Pilot"; s:occupyWing()
    s.generate(); s:lastMessageContains("Registered pilots: 2"); assert(#s.spawns == 0)
    s:assertClean()
end)

test("range, forward sector, HOT and through route across boundaries", function()
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
                s:assertClean()
            end
        end
    end
end)

test("all five formation draws set the controller and delayed route consistently", function()
    local choices = {
        { "WEDGE", 196610 }, { "LINE_ABREAST", 65538 }, { "TRAIL", 131074 },
        { "ECHELON_LEFT", 327682 }, { "ECHELON_RIGHT", 262146 }
    }
    for index, choice in ipairs(choices) do
        local s = scenario(); s.player.airborne = true
        s.randomValues = { 60, 15000, 0, index }; s.generate()
        local g = assert(s.spawns[1])
        assert(g.formation == choice[2])
        local task = g.route[1].tasks[2]
        assert(task.id == "WrappedAction" and task.enabled and task.number == 2)
        local action = task.params.action
        assert(action.id == "Option" and action.params.name == s.env.AI.Option.Air.id.FORMATION)
        assert(action.params.value == choice[2])
        assert(g.route[1].tasks[1].id == "EngageTargets" and g.openFire)
        assert(string.find(s.logs[#s.logs], "formation=" .. choice[1] .. "/Open", 1, true))
        s.randomValues = { 80, 30000, 60, 5 }; s.generate()
        assert(#s.spawns == 1 and g.formation == choice[2] and #s.randomValues == 4)
        s:assertClean()
    end
end)

test("concurrent wing formations are selected independently", function()
    local s = scenario(); s.player.airborne = true
    local other = s:addPilot("Other", "ucid-other", 20); other.airborne = true; s:tick(2)
    s.randomValues = { 60, 15000, 0, 2 }; s.generate()
    s.randomValues = { 80, 30000, 60, 5 }; s:command("Generate Intercept", other)
    assert(#s.spawns == 2)
    assert(s.spawns[1].formation == 65538 and s.spawns[2].formation == 262146)
    assert(s.spawns[1].name ~= s.spawns[2].name)
    s:assertClean()
end)

test("three template draws preserve ME composition and display the actual enemy", function()
    local choices = {
        { "TPL_INT_MIG29A_2", "MiG-29A", 2 },
        { "TPL_INT_SU27_1", "Su-27", 1 },
        { "TPL_INT_MIG29A_1", "MiG-29A", 1 }
    }
    for index, choice in ipairs(choices) do
        for formation = 1, 5 do
            local s = scenario(); s.player.airborne = true
            s.randomValues = { 70, 20000, -30, formation, index }; s.generate()
            local g = assert(s.spawns[1])
            assert(g.template == choice[1] and #g.units == choice[3])
            for _, unit in ipairs(g.units) do assert(unit:GetTypeName() == choice[2]) end
            s:lastMessageContains("Hostiles: " .. choice[3] .. " x " .. choice[2])
            assert(string.find(s.logs[#s.logs], "template=" .. choice[1], 1, true))
            assert(g.route and g.formation and g.openFire and #s.randomValues == 0)
            s.randomValues = { 80, 30000, 60, 5, 3 }; s.generate()
            assert(#s.spawns == 1 and #s.randomValues == 5 and g.template == choice[1])
            s:assertClean()
        end
    end
end)

test("single-aircraft objectives complete by event or polling and retain RTB scoring", function()
    for _, index in ipairs({ 2, 3 }) do
        for _, byEvent in ipairs({ true, false }) do
            local s = scenario(); s.player.airborne = true
            s.randomValues = { 60, 15000, 0, 1, index }; s.generate()
            local enemy = s.spawns[1].units[1]
            enemy.alive = false
            if byEvent then s:event("Dead", enemy) else s:tick(1) end
            s:lastMessageContains("PRIMARY OBJECTIVE COMPLETE"); s:score(0)
            s:land(s:base(), 2)
            for time = 2, 12 do s:tick(time) end
            s:score(150)
            s:event("Dead", enemy); s:event("Crash", s.player); s:score(150)
            s:assertClean()
        end
    end
end)

test("two-aircraft template cannot complete while its second enemy is alive", function()
    local s = scenario(); s.player.airborne = true
    s.randomValues = { 60, 15000, 0, 1, 1 }; s.generate()
    local g = s.spawns[1]
    g.units[1].alive = false; s:event("Dead", g.units[1]); s:tick(1)
    s:command("Mission Status"); s:lastMessageContains("Intercept: ACTIVE")
    s:complete(g); s:lastMessageContains("PRIMARY OBJECTIVE COMPLETE")
    s:event("Crash", s.player); s:score(90); s:assertClean()
end)

test("missing selected template releases the reservation and permits a fresh draw", function()
    for index, template in ipairs({ "TPL_INT_MIG29A_2", "TPL_INT_SU27_1", "TPL_INT_MIG29A_1" }) do
        local s = scenario(); s.player.airborne = true; s.missingTemplate = template
        s.randomValues = { 60, 15000, 0, 1, index }; s.generate()
        s:lastMessageContains("spawn failed"); assert(#s.spawns == 0 and #s.errors == 1)
        assert(string.find(s.errors[1], template, 1, true))
        s.missingTemplate = nil
        s.randomValues = { 60, 15000, 0, 1, index }; s.generate()
        assert(#s.spawns == 1 and s.spawns[1].template == template)
    end
end)

test("new assignments redraw templates and concurrent wings remain independent", function()
    for _, otherIndex in ipairs({ 1, 2, 3 }) do
        local s = scenario(); s.player.airborne = true
        local other = s:addPilot("Other", "ucid-other", 20); other.airborne = true; s:tick(2)
        s.randomValues = { 60, 15000, 0, 1, 1 }; s.generate()
        s.randomValues = { 60, 15000, 0, 1, otherIndex }; s:command("Generate Intercept", other)
        local a, b = s.spawns[1], s.spawns[2]
        assert(a.name ~= b.name)
        s:complete(b)
        s:command("Mission Status", other); s:lastMessageContains("Intercept: RTB_PENDING")
        s:command("Mission Status"); s:lastMessageContains("Intercept: ACTIVE")
        s:command("Abort Mission")
        assert(a.destroyed and not b.destroyed)
        s.randomValues = { 60, 15000, 0, 1, 3 }; s.generate()
        assert(#s.spawns == 3 and s.spawns[3].template == "TPL_INT_MIG29A_1")
        assert(s.spawns[3].name ~= a.name and s.spawns[3].name ~= b.name)
        s:assertClean()
    end
end)

print(string.format("All %d Intercept tests passed (simulated DCS/MOOSE).", count))
