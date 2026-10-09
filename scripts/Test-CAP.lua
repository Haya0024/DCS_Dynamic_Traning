local scenario = dofile("scripts/Intercept-TestHarness.lua")
local count = 0
local function test(name, run) run(); count = count + 1; print("PASS: " .. name) end
local function new(options)
    local s = scenario(options); s:addCAPZones(); return s
end
local function accept(s, player, choices)
    s.randomValues = choices or { 1, 1, 30 }
    s:command("Task: CAP", player)
    return assert(s:mission(player))
end
local function enter(s, record, player)
    local p = player or s.player
    p.airborne = true
    p.position = { x = record.capPlan.center.x, y = 6000, z = record.capPlan.center.y }
end
local function advance(s, seconds)
    for _ = 1, seconds do s:tick(s.time + 1) end
end
local function progress(s, percent)
    local found = 0
    for _, message in ipairs(s.messages) do
        if message.text:find("CAP patrol progress: " .. percent .. "%", 1, true) then found = found + 1 end
    end
    return found
end
local function completed(s, record)
    enter(s, record); advance(s, 121)
    s:complete(record.spawn.group)
    assert(record.state == "RTB_PENDING")
end

test("all four configured areas are selectable with runtime center/radius and acceptance DDM", function()
    for index = 1, 4 do
        local s = new(); local record = accept(s, nil, { index, 1, 30 })
        assert(record.capPlan.center.x == 100100 and record.capPlan.center.y == index * 10000 + 300
            and record.capPlan.radius == 18288)
        local message = s.messages[#s.messages]
        assert(message.seconds == 60 and message.text:find("CAP AREA: LL DDM", 1, true))
        assert(not message.text:find("PATROL CENTER", 1, true) and not message.text:find("Radius:", 1, true))
        assert(message.text:find("120 seconds AND destroy", 1, true))
        assert(#s.spawns == 0 and record.category == "CAP")
    end
end)
test("ground acceptance and transit do not start the patrol or spawn hostiles", function()
    local s = new(); local r = accept(s); advance(s, 130)
    assert(r.capPlan.elapsed == 0 and #s.spawns == 0 and r.state == "ACTIVE")
    s.player.airborne = true; advance(s, 130)
    assert(r.capPlan.elapsed == 0 and #s.spawns == 0)
end)
test("entry starts the clock and 20 percent notifications occur once at 24 second boundaries", function()
    local s = new(); local r = accept(s); enter(s, r); advance(s, 1)
    assert(r.capPlan.elapsed == 0)
    assert(s.messages[#s.messages].text == "CAP on station.")
    for percent = 20, 100, 20 do
        advance(s, 23); assert(progress(s, percent) == 0)
        advance(s, 1); assert(progress(s, percent) == 1)
    end
    advance(s, 30)
    for percent = 20, 100, 20 do assert(progress(s, percent) == 1) end
end)
test("outside patrol time and enemy appearance clock pause and resume without reselecting", function()
    local s = new(); local r = accept(s); enter(s, r); advance(s, 21)
    local plan = r.capPlan
    assert(plan.elapsed == 20)
    s.player.position.x = plan.center.x + plan.radius + 1; advance(s, 90)
    assert(plan.elapsed == 20 and #s.spawns == 0)
    enter(s, r); advance(s, 10); assert(plan.elapsed == 29 and #s.spawns == 0)
    advance(s, 1); assert(plan.elapsed == 30 and #s.spawns == 1 and r.capPlan == plan)
end)
test("30 and 120 second spawn boundaries create exactly one wave", function()
    for _, deadline in ipairs({ 30, 120 }) do
        local s = new(); local r = accept(s, nil, { 1, 1, deadline }); enter(s, r)
        advance(s, deadline); assert(#s.spawns == 0)
        advance(s, 1); assert(#s.spawns == 1)
        s.player.position.x = r.capPlan.center.x + r.capPlan.radius + 1; advance(s, 20)
        enter(s, r); advance(s, 140); assert(#s.spawns == 1)
    end
end)
test("enemy templates use each intercept candidate and an independent alias and orbit route", function()
    local expected = { "TPL_INT_MIG29A_2", "TPL_INT_SU27_1", "TPL_INT_MIG29A_1" }
    for index = 1, 3 do
        local s = new(); local r = accept(s, nil, { 1, index, 30 }); enter(s, r); advance(s, 31)
        local g, plan = r.spawn.group, r.capPlan
        assert(g.template == expected[index] and g.name:find("DT_CAP_", 1, true) == 1 and g.openFire)
        local dx, dz = g.position.x - plan.center.x, g.position.z - plan.center.y
        assert(math.abs(math.sqrt(dx*dx + dz*dz) - (plan.radius + 15*1852)) < 0.01)
        assert(g.position.y == 15000 * 0.3048 and g.route[1].speed == 230 * 3.6)
        assert(g.route[2].position.x == plan.center.x and g.route[2].tasks[2].id == "Orbit")
    end
end)
test("maximum enemy geometry honors distance altitude and hot approach toward area", function()
    local s = new(); local r = accept(s); enter(s, r)
    advance(s, 30); s.randomValues = { 10000, 359, 30000 }; advance(s, 1)
    local g, p = r.spawn.group, r.capPlan
    local dx, dz = g.position.x - p.center.x, g.position.z - p.center.y
    assert(math.abs(math.sqrt(dx*dx + dz*dz) - (p.radius + 25*1852)) < 0.01)
    assert(math.abs(g.heading - 179) < 0.01 and g.position.y == 30000 * 0.3048)
end)
test("time complete with living enemies remains active and completion follows their destruction", function()
    local s = new(); local r = accept(s); enter(s, r); advance(s, 121)
    assert(r.capPlan.elapsed == 120 and r.state == "ACTIVE" and not r.primaryCompletedAt)
    s:complete(); assert(r.state == "RTB_PENDING" and r.primaryCompletedAt)
end)
test("enemy elimination before time completion is not an early win", function()
    local s = new(); local r = accept(s); enter(s, r); advance(s, 31); s:complete()
    assert(r.state == "ACTIVE" and not r.primaryCompletedAt)
    advance(s, 89); assert(r.state == "ACTIVE")
    advance(s, 1); assert(r.state == "RTB_PENDING")
end)
test("one surviving aircraft and nil or failed observations cannot complete CAP", function()
    for _, observation in ipairs({ "alive", "nil", "error", "identity" }) do
        local s = new(); local r = accept(s); enter(s, r); advance(s, 121)
        local targets = r.spawn.group.units; targets[1].alive = false
        local u = targets[2]
        if observation == "nil" then u.IsAlive = function() return nil end
        elseif observation == "error" then u.IsAlive = function() error("unobserved") end
        elseif observation == "identity" then u.id = u.id + 1; u.alive = false end
        advance(s, 1); assert(r.state == "ACTIVE")
    end
end)
test("MP2 clock uses any original pilot and freezes when all are outside", function()
    local s = new(); s:occupyWing(); local r = accept(s)
    enter(s, r, s.wingman); advance(s, 25); assert(r.capPlan.elapsed == 24)
    s.wingman.position.x = 0; advance(s, 20); assert(r.capPlan.elapsed == 24)
    enter(s, r, s.player); advance(s, 25); assert(r.capPlan.elapsed == 48)
end)
test("AI and late joining humans inside cannot advance the frozen roster clock", function()
    local s = new(); local r = accept(s)
    enter(s, r, s.wingman); advance(s, 20); assert(r.capPlan.elapsed == 0)
    s:occupyWing(); advance(s, 20)
    assert(#r.participants == 1 and r.capPlan.elapsed == 0)
end)
test("zone observation failure pauses the clock without adding missing time", function()
    local s = new(); local r = accept(s); enter(s, r); advance(s, 11)
    r.capPlan.zone.failObservation = true; advance(s, 40); assert(r.capPlan.elapsed == 10)
    r.capPlan.zone.failObservation = false; advance(s, 1); assert(r.capPlan.elapsed == 10)
    advance(s, 1); assert(r.capPlan.elapsed == 11)
end)
test("large tick gaps cannot grant unobserved minutes and repeated ticks cannot duplicate progress", function()
    local s = new(); local r = accept(s); enter(s, r); advance(s, 1)
    s:tick(200); assert(r.capPlan.elapsed == 2)
    s:tick(200); assert(r.capPlan.elapsed == 2 and #s.spawns == 0)
end)
test("death before enemy spawn releases the assignment with zero reward", function()
    local s = new(); local r = accept(s); s:event("Ejection", s.player)
    assert(not s:mission() and #s.spawns == 0); s:score(0)
end)
test("leader loss keeps a registered surviving wingmate counting and preserves the lost pilot zero", function()
    local s = new(); s:occupyWing(); local r = accept(s); enter(s, r, s.wingman)
    advance(s, 11); s.player.alive = false; s:event("Ejection", s.player)
    advance(s, 110); s:complete(); assert(r.state == "RTB_PENDING")
    assert(r.participants[1].receipt.points == 0)
    s:event("Ejection", s.wingman); s:score(90, s.wingman)
    assert(not s:mission(s.wingman))
end)
test("safe recovery awards CAP 150 independently of other categories", function()
    local s = new(); local r = accept(s); completed(s, r)
    local t = s.time; s:land(s:base(), t); advance(s, 11)
    assert(not s:mission() and r.spawn.group.destroyed); s:score(150)
    s:categoryScores({ capScore = 150, interceptScore = 0 })
end)
test("completed CAP accident awards 90 once and abort awards zero", function()
    for _, abort in ipairs({ false, true }) do
        local s = new(); local r = accept(s); completed(s, r)
        if abort then s:command("Abort Mission") else s:event("Ejection", s.player); s:event("Dead", s.player) end
        assert(not s:mission()); s:score(abort and 0 or 90)
    end
end)
test("MP2 recovery settles individually at full reward and keeps the shared lock until both finish", function()
    local s = new(); s:occupyWing(); local r = accept(s); enter(s, r, s.wingman); advance(s, 121); s:complete()
    s:land(s:base(), s.time, s.player); advance(s, 11); s:score(150, s.player)
    assert(s:mission() == r and not r.spawn.group.destroyed)
    s:command("Task: Intercept"); s:lastMessageContains("already active")
    s:event("Ejection", s.wingman); s:score(90, s.wingman); assert(not s:mission())
end)
test("CAP and Intercept in separate wings keep aliases objectives and locks separate", function()
    local s = new(); local other = s:addPilot("Other", "ucid-other", 30); other.airborne = true
    local r = accept(s); s:tick(2); s:command("Task: Intercept", other); local intercept = s:mission(other)
    enter(s, r); advance(s, 31); assert(r.spawn.group.name ~= intercept.spawn.group.name)
    s:complete(r.spawn.group); assert(intercept.state == "ACTIVE" and r.state == "ACTIVE")
    s:complete(intercept.spawn.group); assert(intercept.state == "RTB_PENDING" and r.state == "ACTIVE")
end)
test("parallel CAP wings count and spawn independently without alias collisions", function()
    local s = new(); local other = s:addPilot("Other", "ucid-other", 30); s:tick(2)
    local a = accept(s, nil, { 1, 1, 30 }); local b = accept(s, other, { 2, 2, 120 })
    enter(s, a); advance(s, 31)
    assert(#s.spawns == 1 and a.capPlan.elapsed == 30 and b.capPlan.elapsed == 0)
    enter(s, b, other); advance(s, 121)
    assert(#s.spawns == 2 and a.spawn.group.name ~= b.spawn.group.name)
end)
test("spawn and route failures release the lock and remove partially configured enemies", function()
    for _, fault in ipairs({ "failSpawn", "failRoute" }) do
        local s = new(); local r = accept(s); s[fault] = true; enter(s, r); advance(s, 31)
        assert(not s:mission()); s:score(0)
        if fault == "failRoute" then assert(r.capPlan.enemy.destroyed) end
    end
end)
test("failed CAP cleanup retains the enemy reference and retries without affecting other wings", function()
    local s = new(); local r = accept(s); enter(s, r); advance(s, 31)
    local g = r.spawn.group; g.cleanupFailures = 1
    s:command("Abort Mission"); assert(not s:mission() and not g.destroyed)
    advance(s, 4); assert(not g.destroyed)
    advance(s, 1); assert(g.destroyed and g.destroyCalls == 2)
end)
test("missing or malformed CAP zones fail acceptance without leaving a wing lock", function()
    for _, broken in ipairs({ "missing", "radius" }) do
        local s = new()
        if broken == "missing" then s.zones.CAP_ZONE_GOLAN = nil else s.zones.CAP_ZONE_GOLAN.radius = 0 end
        s:command("Task: CAP"); assert(not s:mission() and #s.spawns == 0)
        s.player.airborne = true; s.generate(); assert(s:mission().category == "Intercept")
    end
end)
test("status recalls the same briefing without rerolling or advancing patrol time", function()
    local s = new(); local r = accept(s); local calls = #s.randomCalls
    s:command("Mission Status")
    assert(s.messages[#s.messages].seconds == 60)
    s:lastMessageContains("CAP AREA: LL DDM"); s:lastMessageContains("Patrol: 0%")
    local text = s.messages[#s.messages].text
    assert(not text:find("PATROL CENTER", 1, true) and not text:find("Radius:", 1, true))
    assert(#s.randomCalls == calls and r.capPlan.elapsed == 0)
end)
test("time-complete CAP may finish combat outside without losing patrol progress", function()
    local s = new(); local r = accept(s); enter(s, r); advance(s, 121)
    s.player.position.x = 0; advance(s, 30); s:complete()
    assert(r.capPlan.elapsed == 120 and r.state == "RTB_PENDING")
end)
test("explicitly destroyed wrappers with no remaining DCS ID still finish the tracked enemy objective", function()
    local s = new(); local r = accept(s); enter(s, r); advance(s, 121)
    for _, target in ipairs(r.spawn.group.units) do
        target.alive = false; target.GetID = function() return nil end
        target.GetDCSObject = function() return nil end
    end
    advance(s, 1); assert(r.state == "RTB_PENDING")
end)
test("duplicate and cross-category acceptance plus the same UCID in another wing cannot reroll CAP", function()
    local s = new(); local r = accept(s); local calls = #s.randomCalls
    s:command("Task: CAP"); s:lastMessageContains("CAP mission is already active")
    s:command("Task: SEAD"); s:lastMessageContains("CAP mission is already active")
    local other = s:addPilot("Other", "ucid-a", 30); s:tick(2)
    s:command("Task: CAP", other); s:lastMessageContains("CAP mission is already active")
    assert(s:mission() == r and not s:mission(other) and #s.randomCalls == calls)
end)
test("circular boundary is included while one meter beyond it pauses patrol time", function()
    local s = new(); local r = accept(s); enter(s, r)
    s.player.position.x = r.capPlan.center.x + r.capPlan.radius
    advance(s, 25); assert(r.capPlan.elapsed == 24)
    s.player.position.x = s.player.position.x + 1; advance(s, 20)
    assert(r.capPlan.elapsed == 24)
end)
test("personally aborted pilots inside cannot keep counting while their surviving wingmate is outside", function()
    local s = new(); s:occupyWing(); local r = accept(s); enter(s, r); advance(s, 11)
    s:abortSortie(s.player); advance(s, 40)
    assert(r.participants[1].done and r.capPlan.elapsed == 10 and s:mission() == r)
    enter(s, r, s.wingman); advance(s, 111); s:complete()
    assert(r.state == "RTB_PENDING" and r.participants[1].receipt.points == 0)
end)
test("MOOSE weak subscribers survive garbage collection after Intercept and respawn for CAP", function()
    local s = new({ weakEventHandlers = true })
    s.player.airborne = true; s.generate(); s:complete(); s:event("Ejection", s.player)
    s:score(90); assert(not s:mission())
    s.player.id = 50000; s.player:newDCSObject(); s.players = { s.player.raw }; advance(s, 2)
    local r = accept(s, nil, { 3, 1, 97 }); enter(s, r); advance(s, 121)
    assert(r.state == "ACTIVE" and r.capPlan.elapsed == 120 and #r.spawn.units == 2)
    collectgarbage("collect")
    s.reload(); collectgarbage("collect") -- The existing subscriber must remain retained.
    local subscribers = 0
    for _ in pairs(s.eventSubscribers[s.env.EVENTS.Ejection]) do subscribers = subscribers + 1 end
    assert(subscribers == 1, "MOOSE weak subscriber was collected or duplicated")
    local unmatchedAt = #s.logs
    local unrelated = { getName = function() return s.player.unitName end, getID = function() return 999999 end }
    s:event("Ejection", s.player, nil, nil, unrelated)
    assert(s:mission() == r and r.state == "ACTIVE")
    for i = unmatchedAt + 1, #s.logs do assert(not s.logs[i]:find("Failure event matched:", 1, true)) end
    s.player.raw.getID = function() error("destroyed object ID unavailable") end
    s.player.alive = false; s:event("Ejection", s.player); s:event("Crash", s.player)
    assert(not s:mission() and r.spawn.group.destroyed)
    local p = r.participants[1]
    assert(p.done and p.receipt.result == "FAILED" and p.receipt.points == 0)
    local registered, received, matched, initialized = false, false, false, 0
    for _, log in ipairs(s.logs) do
        assert(not log:find("ucid-a", 1, true))
        if log:find("Registered aircraft: Player10 (objectID=50000)", 1, true) then registered = true end
        if log:find("Failure event received: event=Ejection", 1, true) and
            log:find("objectID=UNAVAILABLE; subscriberRetained=true", 1, true) then received = true end
        if log:find(r.id, 1, true) and log:find("Failure event matched: event=Ejection", 1, true) and
            log:find("objectID=50000; state=ACTIVE; done=false", 1, true) then matched = true end
        if log:find("Runtime initialized; version=training-7;", 1, true) then initialized = initialized + 1 end
    end
    assert(registered and received and matched and initialized == 1)
    s.player.alive = true; s.player.id = 50001; s.player:newDCSObject()
    s.players = { s.player.raw }; advance(s, 2)
    s:score(90); s:lastMessageContains("Settled Missions: 2"); s:lastMessageContains("Death Count: 2")
    s:categoryScores({ interceptScore = 90, capScore = 0 })
    local next = accept(s); enter(s, next); advance(s, 121)
    collectgarbage("collect"); s:complete(next.spawn.group)
    assert(next.state == "RTB_PENDING")
    collectgarbage("collect"); s:land(s:base(), s.time); advance(s, 11)
    assert(not s:mission()); s:score(240)
    s:lastMessageContains("Settled Missions: 3"); s:lastMessageContains("Death Count: 2")
    s:categoryScores({ interceptScore = 90, capScore = 150 }); s:assertClean()
end)

test("acceptance distance includes forty and one hundred NM and excludes both outside edges", function()
    for draw = 1, 2 do
        local s = new()
        s.player.position = { x = -1000000, y = 0, z = 0 }
        for i, name in ipairs({ "CAP_ZONE_CENTRAL_COAST", "CAP_ZONE_GOLAN", "CAP_ZONE_NORTH_COAST", "CAP_ZONE_HOMS_WEST" }) do
            local nm = ({ 39.999, 40, 100, 100.001 })[i]
            s.zones[name].center = { x = s.player.position.x + nm * 1852, y = 0 }
        end
        local r = accept(s, nil, { draw, 1, 30 })
        assert(r.capPlan.name == (draw == 1 and "CAP_ZONE_GOLAN" or "CAP_ZONE_NORTH_COAST"))
        assert(s.randomCalls[1].minimum == 1 and s.randomCalls[1].maximum == 2)
        assert(r.capPlan.acceptancePosition.x == -1000000)
        local plan = r.capPlan
        s.player.position.x = 1000000; advance(s, 20)
        s:command("Mission Status")
        assert(r.capPlan == plan and #s.randomCalls == 3 and plan.elapsed == 0)
    end
end)

test("no in-range CAP area refuses without scoring or locking and permits a fresh request", function()
    local s = new(); s.player.position.x = 1000000
    s:command("Task: CAP")
    assert(not s:mission() and #s.spawns == 0 and #s.randomCalls == 0 and #s.errors == 0)
    s:lastMessageContains("No CAP areas within 40-100 NM.")
    s.player.position.x = 100
    assert(accept(s).category == "CAP")
end)

test("CAP filters from the lowest flight-number accepted pilot and releases a failed position probe", function()
    local s = new(); s:occupyWing()
    s.player.number, s.wingman.number = 2, 1
    s.player.position.x, s.wingman.position.x = 1000000, 100
    local r = accept(s)
    assert(r.owner.unit == s.wingman and r.capPlan.acceptancePosition.x == 100)
    s:command("Abort Mission")
    local original = s.wingman.GetVec3
    s.wingman.GetVec3 = function() error("position unavailable") end
    s:command("Task: CAP")
    assert(not s:mission() and #s.errors == 1)
    s.wingman.GetVec3 = original
    assert(accept(s).owner.unit == s.wingman)
end)

print(string.format("All %d CAP tests passed (simulated DCS/MOOSE).", count))
