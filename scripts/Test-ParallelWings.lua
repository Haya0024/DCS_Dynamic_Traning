-- Build first; verify independent wing assignments against the actual bundle.
local scenario = dofile("scripts/Intercept-TestHarness.lua")
local count = 0
local function test(name, callback)
    callback(); count = count + 1; print("PASS: " .. name)
end
local function hold(s, first, last)
    for t = first, last do s:tick(t) end
end
local function parallel(crew)
    local s = scenario()
    local other, mate = s:addPilot("Other", "ucid-other", 40)
    if crew then
        s:occupyWing()
        s:occupyWing("OtherMate", "ucid-other-mate", mate)
        s.wingman.airborne, mate.airborne = true, true
    end
    s.player.airborne, other.airborne = true, true
    s:tick(2); s.generate(); s:command("Generate Intercept", other)
    assert(#s.spawns == 2)
    return s, other, mate, s.spawns[1], s.spawns[2]
end
local function status(s, player, state)
    s:command("Mission Status", player)
    s:lastMessageContains("Intercept: " .. state)
    if state ~= "Idle" then s:lastMessageContains("Wing: " .. player.group:GetName()) end
end

test("an airborne wing can start while another wing is still awaiting takeoff", function()
    local s = scenario(); s.generate()
    local other = s:addPilot("Other", "ucid-other", 40)
    other.airborne = true; other.position.x = 50000; s:tick(2)
    s:command("Generate Intercept", other); assert(#s.spawns == 1)
    status(s, s.player, "ARMED"); status(s, other, "ACTIVE")
    s.player.airborne = true; s:tick(4); s:tick(24)
    assert(#s.spawns == 2 and s.spawns[1].name ~= s.spawns[2].name)
    status(s, s.player, "ACTIVE"); status(s, other, "ACTIVE"); s:assertClean()
end)

test("two MP2 ground reservations keep separate twenty-second countdowns", function()
    local s = scenario(); s:occupyWing()
    local other, mate = s:addPilot("Other", "ucid-other", 40)
    s:occupyWing("OtherMate", "ucid-other-mate", mate)
    s:tick(2); s.generate(); s:command("Generate Intercept", other)
    s.player.airborne, s.wingman.airborne = true, true
    other.airborne = true; s:tick(4)
    status(s, s.player, "TAKEOFF_DELAY"); status(s, other, "ARMED")
    s:tick(24); assert(#s.spawns == 1)
    mate.airborne = true; s:tick(26); s:tick(44); assert(#s.spawns == 1)
    s:tick(46); assert(#s.spawns == 2); s:assertClean()
end)

test("a touchdown resets only that wing's countdown, not the other wing's deadline", function()
    local s = scenario()
    local other = s:addPilot("Other", "ucid-other", 40); s:tick(2)
    s.generate(); s:command("Generate Intercept", other)
    s.player.airborne, other.airborne = true, true; s:tick(4)
    s.player.airborne = false; s:tick(10)
    status(s, s.player, "ARMED"); status(s, other, "TAKEOFF_DELAY")
    s:tick(24); assert(#s.spawns == 1)
    status(s, other, "ACTIVE"); status(s, s.player, "ARMED"); s:assertClean()
end)

test("enemy losses and cross-wing assistance complete only the assigned objective", function()
    local s, other, _, a, b = parallel()
    a.units[1].alive = false; s:event("Dead", a.units[1])
    b.units[1].alive = false; s:event("Dead", b.units[1])
    status(s, s.player, "ACTIVE"); status(s, other, "ACTIVE")
    s:complete(a)
    status(s, s.player, "RTB_PENDING"); status(s, other, "ACTIVE")
    assert(b.units[2].alive)
    s:event("Crash", s.player); s:score(90); s:score(0, other)
    status(s, s.player, "Idle"); status(s, other, "ACTIVE")
    s:complete(b); s:event("Crash", other); s:score(90, other); s:assertClean()
end)

test("one wing returning and settling does not stop another wing's active combat", function()
    local s, other, _, a, b = parallel(true)
    s:complete(a); s:event("Crash", s.wingman)
    s:land(s:base(), 10); hold(s, 11, 21)
    s:score(150); s:score(90, s.wingman); s:score(0, other)
    status(s, s.player, "Idle"); status(s, other, "ACTIVE")
    assert(not b.destroyed and b.units[1].alive and b.units[2].alive)
    s:command("Generate Intercept", other); s:lastMessageContains("Wing assignment blocked")
    s.player.airborne = true; s.generate(); assert(#s.spawns == 3)
    status(s, other, "ACTIVE"); s:assertClean()
end)

test("four pilots from two wings can all complete their landing holds on one tick", function()
    local s, other, mate, a, b = parallel(true)
    s:complete(a); s:complete(b)
    local base = s:base()
    for _, pilot in ipairs({ s.player, s.wingman, other, mate }) do s:land(base, 10, pilot) end
    hold(s, 11, 21)
    for _, pilot in ipairs({ s.player, s.wingman, other, mate }) do s:score(150, pilot) end
    status(s, s.player, "Idle"); status(s, other, "Idle"); s:assertClean()
end)

test("wing abort and its cleanup death events cannot abort or complete a different wing", function()
    local s, other, _, a, b = parallel(true)
    s.cleanupEvents = true; s:command("Abort Mission")
    assert(a.destroyed and not b.destroyed)
    s:score(0); s:score(0, other)
    status(s, s.player, "Idle"); status(s, other, "ACTIVE")
    s:complete(b); s:event("Ejection", other); s:event("Crash", other.group.units[2])
    s:score(90, other); s:assertClean()
end)

test("player loss in one wing never settles another wing's participants", function()
    local s, other, _, a, b = parallel()
    s:complete(b); s:event("Ejection", s.player)
    s:score(0); s:score(0, other)
    status(s, s.player, "Idle"); status(s, other, "RTB_PENDING")
    s:land(s:base(), 10, other); hold(s, 11, 21)
    s:score(150, other); s:assertClean()
end)

test("route failure releases only the failing wing and retries use a fresh spawn alias", function()
    local s = scenario(); s.player.airborne = true; s.generate()
    local a = s.spawns[1]
    local other = s:addPilot("Other", "ucid-other", 40); other.airborne = true; s:tick(2)
    s.cleanupEvents, s.failRoute = true, true
    s:command("Generate Intercept", other); s:lastMessageContains("spawn failed")
    assert(s.spawns[2].destroyed and not a.destroyed)
    status(s, other, "Idle"); status(s, s.player, "ACTIVE")
    s.failRoute = false; s:command("Generate Intercept", other)
    assert(#s.spawns == 3 and s.spawns[2].name ~= s.spawns[3].name)
    status(s, s.player, "ACTIVE"); status(s, other, "ACTIVE")
    -- The intentional spawn failure produces the expected diagnostic.
    assert(#s.errors == 1 and string.find(s.errors[1], "route failure", 1, true))
end)

test("cancelling a ground reservation does not release an active wing's blocker", function()
    local s = scenario(); s.generate()
    local other = s:addPilot("Other", "ucid-other", 40); other.airborne = true; s:tick(2)
    s:command("Generate Intercept", other); local b = s.spawns[1]
    s.player.name = nil; s:tick(4)
    status(s, other, "ACTIVE")
    s:command("Generate Intercept", other); s:lastMessageContains("Wing assignment blocked")
    assert(#s.spawns == 1 and not b.destroyed)
    s.player.name = "Pilot"; s.player.airborne = true; s.generate()
    assert(#s.spawns == 2); s:assertClean()
end)

test("idle wing menus never display or abort someone else's active mission", function()
    local s, other = parallel()
    local idle = s:addPilot("Idle", "ucid-idle", 60); s:tick(4)
    status(s, idle, "Idle"); s:command("Abort Mission", idle); s:lastMessageContains("Idle")
    status(s, s.player, "ACTIVE"); status(s, other, "ACTIVE")
    for label in pairs(s.commands[idle.group:GetName()]) do
        assert(not string.find(label, "Abort Sortie:", 1, true))
    end
    s:assertClean()
end)

test("moving UCID still blocks a new mission and shows only that pilot's earlier wing", function()
    local s, other, _, a, b = parallel(true)
    local moved = s:addPilot("Moved", "ucid-a", 60); moved.airborne = true; s:tick(4)
    s:command("Generate Intercept", moved); s:lastMessageContains("Wing assignment blocked")
    s:command("Mission Status", moved); s:lastMessageContains("Wing: " .. s.player.group:GetName())
    assert(not string.find(s.messages[#s.messages].text, other.group:GetName(), 1, true))
    s:abortSortie(s.player, moved)
    assert(not a.destroyed and not b.destroyed)
    status(s, s.wingman, "ACTIVE"); status(s, other, "ACTIVE")
    s:event("Crash", s.wingman)
    s:command("Generate Intercept", moved); assert(#s.spawns == 3); s:assertClean()
end)

test("a shared group can manage two earlier sorties without ambiguously aborting a wing", function()
    local s, other, _, a, b = parallel()
    local moved, mate = s:addPilot("MovedA", "ucid-a", 60)
    s:occupyWing("MovedB", "ucid-other", mate); s:tick(4)
    s:command("Abort Mission", moved); s:lastMessageContains("Multiple earlier wing missions")
    assert(not a.destroyed and not b.destroyed)
    s:abortSortie(s.player, moved)
    assert(a.destroyed and not b.destroyed)
    s:command("Mission Status", moved); s:lastMessageContains("Wing: " .. other.group:GetName())
    s:abortSortie(other, moved); assert(b.destroyed); s:assertClean()
end)

test("own wing abort is scoped to that wing when a newcomer carries an earlier assignment", function()
    local s, other, mate, a, b = parallel()
    s:occupyWing("MovedA", "ucid-a", mate); s:tick(4)
    s:command("Abort Mission", other)
    assert(b.destroyed and not a.destroyed)
    status(s, s.player, "ACTIVE")
    s:command("Mission Status", other); s:lastMessageContains("Wing: " .. s.player.group:GetName())
    s:abortSortie(s.player, other); assert(a.destroyed); s:assertClean()
end)

test("a stale abort callback cannot target either a new assignment or a concurrent wing", function()
    local s, other, _, a, b = parallel()
    local stale = s.commands[s.player.group:GetName()]["Abort Sortie: Pilot [Player10]"]
    s:command("Abort Mission"); s.generate(); local c = s.spawns[3]
    stale(); s:lastMessageContains("already closed")
    assert(a.destroyed and not b.destroyed and not c.destroyed)
    status(s, s.player, "ACTIVE"); status(s, other, "ACTIVE"); s:assertClean()
end)

test("an exception in one wing's monitor does not interrupt another wing's safe recovery", function()
    local s, other, _, a, b = parallel()
    s:complete(a); s:complete(b)
    s:land(s:base(), 10); s:land(s:base(), 10, other)
    local velocity = s.player.GetVelocityVec3
    s.player.GetVelocityVec3 = function() error("simulated wing monitor exception") end
    hold(s, 11, 21)
    s:score(150, other); status(s, other, "Idle")
    assert(#s.errors > 0 and string.find(s.errors[1], "wing monitor exception", 1, true))
    s.player.GetVelocityVec3 = velocity
    hold(s, 22, 32); s:score(150); status(s, s.player, "Idle")
end)

print(string.format("All %d parallel wing tests passed (simulated DCS/MOOSE).", count))
