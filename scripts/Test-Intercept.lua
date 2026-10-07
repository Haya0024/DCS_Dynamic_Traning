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
    s.player.airborne = false; s:tick(10)
    assert(string.find(s.logs[#s.logs], "countdown reset", 1, true))
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
    s.randomValues = { 80, 30000, 60, 5 }; s:command("Task: Intercept", other)
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
            s:lastMessageContains("Intercept MISSION START")
            assert(not string.find(s.messages[#s.messages].text, "Hostiles:", 1, true))
            local found = false
            for _, text in ipairs(s.logs) do
                if string.find(text, "Hostiles: " .. choice[3] .. " x " .. choice[2], 1, true) then found = true end
            end
            assert(found)
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
        s.randomValues = { 60, 15000, 0, 1, otherIndex }; s:command("Task: Intercept", other)
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

test("solo and MP2 show one range altitude aspect start; hostiles countdown and pilots stay debug-only", function()
  for _, mp2 in ipairs({ false, true }) do
    for _, airborne in ipairs({ false, true }) do
        local s = scenario()
        if mp2 then s:occupyWing() end
        s.player.airborne, s.wingman.airborne = airborne, airborne
        local function messages(fragment)
            local n = 0
            for _, message in ipairs(s.messages) do
                if string.find(message.text, fragment, 1, true) then n = n + 1 end
            end
            return n
        end
        local function logs(fragment)
            local n = 0
            for _, text in ipairs(s.logs) do if string.find(text, fragment, 1, true) then n = n + 1 end end
            return n
        end
        s.generate()
        assert(logs("MESSAGE [ALL]\nDynamic Training ready. Wing UCID scoring.") == 1)
        if not airborne then
            s:lastMessageContains("Waiting for ALL registered pilots to take off.")
            assert(messages("Hostiles will spawn") == 0)
            s.generate()
            if mp2 then s:command("Task: Intercept", s.wingman) end
            s.player.airborne, s.wingman.airborne = true, true
            s:event("Takeoff", s.player); s:tick(2); s:tick(4)
            assert(messages("Hostiles will spawn") == 0 and logs("Hostiles will spawn") == 1)
            s.player.airborne = false; s:tick(6)
            assert(messages("countdown reset") == 0 and logs("countdown reset") == 1)
            s.player.airborne = true; s:tick(8)
            assert(messages("Hostiles will spawn") == 0 and logs("Hostiles will spawn") == 2)
            for time = 10, 26, 2 do s:tick(time) end
            assert(messages("Intercept MISSION START") == 0)
            s:tick(28)
        else assert(messages("Hostiles will spawn") == 0) end
        s:lastMessageContains("Intercept MISSION START")
        local text, spawn = s.messages[#s.messages].text, s:mission().spawn
        assert(not string.find(text, "Hostiles:", 1, true))
        assert(string.find(text, "Range: " .. spawn.distance .. " NM", 1, true))
        assert(string.find(text, "Altitude: " .. spawn.altitude .. " ft", 1, true))
        assert(string.find(text, "Aspect: HOT", 1, true) and not string.find(text, "Pilots:", 1, true))
        assert(s.messages[#s.messages].seconds == 15)
        s.generate()
        if mp2 then s:command("Task: Intercept", s.wingman) end
        s:event("Takeoff", s.player)
        s:tick(32); s:tick(34)
        assert(#s.spawns == 1 and messages("Intercept MISSION START") == 1)
        assert(logs("[DEBUG] " .. s:mission().id .. "\nIntercept MISSION START") == 1)
        assert(logs("MESSAGE [" .. s.player.group:GetName() .. "]\n" .. text) == 1)
        assert(logs("Pilots:") == 1)
        s:command("Mission Status"); s:lastMessageContains("Intercept: ACTIVE")
        assert(s.messages[#s.messages].seconds == 20)
        assert(messages("Intercept MISSION START") == 1 and logs("Intercept MISSION START") == 2)
        s:assertClean()
    end
  end
end)

test("unknown life or changed identity cannot complete Intercept by polling", function()
    for _, observation in ipairs({ "nil", "invalid", "error", "newAliveID", "newDeadID" }) do
        local s = scenario(); s.player.airborne = true; s.generate()
        local record = s:mission()
        for _, target in ipairs(record.spawn.units) do
            local unit = target.unit
            if observation == "nil" then unit.IsAlive = function() return nil end
            elseif observation == "invalid" then unit.IsAlive = function() return "dead" end
            elseif observation == "error" then unit.IsAlive = function() error("unavailable") end
            else
                unit.alive = observation == "newAliveID"
                unit.GetID = function() return 999999 end
            end
        end
        s:tick(1); s:tick(2)
        assert(record.state == "ACTIVE" and not record.primaryCompletedAt)
        -- The original targets become observable again, including destroyed
        -- wrappers whose DCS IDs no longer exist.
        for _, target in ipairs(record.spawn.units) do
            target.unit.IsAlive = function() return false end
            target.unit.GetID = function() return nil end
        end
        s:tick(3); assert(record.state == "RTB_PENDING")
        s:score(0); s:assertClean()
    end
end)

test("confirmed loss events complete Intercept even when life queries stay unavailable", function()
    local s = scenario(); s.player.airborne = true; s.generate()
    local record = s:mission()
    for i, target in ipairs(record.spawn.units) do
        target.unit.IsAlive = function() return nil end
        target.unit.GetID = function() return nil end
        s:event("Dead", target.unit)
        assert(record.state == (i == #record.spawn.units and "RTB_PENDING" or "ACTIVE"))
    end
    s:tick(1); assert(record.state == "RTB_PENDING")
    s:score(0); s:assertClean()
end)

local function pendingCleanup(s)
    for i = 1, 100 do
        local name, module = debug.getupvalue(s.timers[1].callback, i)
        if name == "Intercept" then return module.pendingCleanup end
    end
    error("Missing Intercept cleanup module")
end

test("abort cleanup retries at five seconds while new and parallel wings continue independently", function()
    local s = scenario(); s.player.airborne = true; s.generate()
    local old = s.spawns[1]; old.cleanupFailures = 2
    s:command("Abort Mission")
    assert(not s:mission() and not old.destroyed and pendingCleanup(s)[old])
    s:lastMessageContains("ERROR: Enemy cleanup. See DCS log.")
    assert(s.messages[#s.messages].seconds == 15)
    s.generate(); local current = s:mission()
    local other = s:addPilot("Other", "ucid-other", 40); other.airborne = true; s:tick(1)
    s:command("Task: Intercept", other); local parallel = s:mission(other)
    s.cleanupEvents = true
    s:tick(4); assert(old.destroyCalls == 1)
    s:tick(5); assert(old.destroyCalls == 2 and not old.destroyed)
    s:tick(9); assert(old.destroyCalls == 2)
    s:tick(10); assert(old.destroyed and old.destroyCalls == 3 and not pendingCleanup(s)[old])
    s:tick(15); assert(old.destroyCalls == 3)
    assert(current.state == "ACTIVE" and parallel.state == "ACTIVE")
    assert(not current.spawn.group.destroyed and not parallel.spawn.group.destroyed)
    s:score(0); s:score(0, other)
    s:lastMessageContains("Primary Success: 0")
    assert(#s.errors == 1 and s.errors[1]:find("Intercept enemy cleanup pending", 1, true))
    local recovered = 0
    for _, log in ipairs(s.logs) do if log:find("Intercept enemy cleaned: " .. old.name, 1, true) then recovered = recovered + 1 end end
    assert(recovered == 1)
end)

test("formation and route setup failure keep untracked enemies queued for cleanup after lock release", function()
    for _, fault in ipairs({ "failFormation", "failRoute" }) do
        local s = scenario(); s.player.airborne = true
        s[fault], s.spawnCleanupFailures = true, 1; s.generate()
        local old = s.spawns[1]
        assert(not s:mission() and not old.destroyed and pendingCleanup(s)[old])
        s:lastMessageContains("Intercept enemy spawn failed")
        s[fault], s.spawnCleanupFailures, s.cleanupEvents = false, nil, true
        s.generate(); local current = s:mission()
        assert(current and current.spawn.group ~= old)
        s:tick(4); assert(old.destroyCalls == 1)
        s:tick(5); assert(old.destroyed and not pendingCleanup(s)[old])
        assert(current.state == "ACTIVE" and not current.spawn.group.destroyed)
        s:score(0); s:lastMessageContains("Primary Success: 0")
        assert(#s.errors == 2) -- Cleanup diagnostic plus the original setup failure.
    end
end)

test("false no-effect and unobservable Destroy results never discard pending cleanup", function()
    for _, fault in ipairs({ "false", "noEffect", "queryError", "queryFalse" }) do
        local s = scenario(); s.player.airborne = true; s.generate()
        local group = s.spawns[1]; local lookup = group.GetDCSObject
        if fault == "false" then group.cleanupFalse = 1
        elseif fault == "noEffect" then group.cleanupNoEffect = 1
        elseif fault == "queryError" then group.GetDCSObject = function() error("lookup unavailable") end
        else group.GetDCSObject = function() return false end end
        s:command("Abort Mission")
        assert(not s:mission() and pendingCleanup(s)[group] and group.destroyCalls == 1)
        group.GetDCSObject = lookup
        s:tick(4); assert(group.destroyCalls == 1)
        s:tick(5); assert(group.destroyed and not pendingCleanup(s)[group] and group.destroyCalls == 2)
        s:tick(10); assert(group.destroyCalls == 2)
        s:score(0); assert(#s.errors == 1)
    end
end)

test("cleanup retries after success or accident never resettle the closed sortie", function()
    for _, result in ipairs({ "RTB_SUCCESS", "RTB_FAILURE", "FAILED" }) do
        local s = scenario(); s.player.airborne = true; s.generate()
        local record = s:mission(); local group = record.spawn.group
        group.cleanupFailures, s.cleanupEvents = 1, true
        local points, closedAt = 0, 0
        if result ~= "FAILED" then s:complete() end
        if result == "RTB_SUCCESS" then
            s:land(s:base(), 10)
            for time = 11, 21 do s:tick(time) end
            points, closedAt = 150, 21
        else
            s:event("Ejection", s.player)
            points = result == "RTB_FAILURE" and 90 or 0
        end
        local receipt = record.participants[1].receipt
        assert(receipt.result == result and not s:mission() and pendingCleanup(s)[group])
        s:score(points); s:lastMessageContains("Settled Missions: 1")
        s:tick(closedAt + 4); assert(group.destroyCalls == 1)
        s:tick(closedAt + 5); assert(group.destroyed and not pendingCleanup(s)[group])
        s:tick(closedAt + 10); assert(group.destroyCalls == 2 and record.participants[1].receipt == receipt)
        s:score(points); s:lastMessageContains("Settled Missions: 1")
        assert(#s.errors == 1)
    end
end)

print(string.format("All %d Intercept tests passed (simulated DCS/MOOSE).", count))
