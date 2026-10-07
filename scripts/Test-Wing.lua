-- Build first; run from the repository root with Lua 5.1.
local scenario = dofile("scripts/Intercept-TestHarness.lua")
local count = 0
local function test(name, callback)
    callback(); count = count + 1; print("PASS: " .. name)
end
local function wing(airborne)
    local s = scenario()
    s:occupyWing()
    s.player.airborne, s.wingman.airborne = airborne or false, airborne or false
    return s
end
local function hold(s, first, last)
    for t = first, last do s:tick(t) end
end

test("MP2 waits for both pilots then twenty seconds; either menu cannot duplicate acceptance", function()
    local s = wing()
    s.generate(); s:command("Task: Intercept", s.wingman)
    s:lastMessageContains("already armed")
    s.player.airborne = true; s:tick(2); s:tick(24); assert(#s.spawns == 0)
    s.wingman.airborne = true; s:tick(26); s:tick(44); assert(#s.spawns == 0)
    s:tick(46); assert(#s.spawns == 1)
    s:command("Task: Intercept", s.wingman); s:lastMessageContains("Wing assignment blocked")
    assert(#s.spawns == 1); s:assertClean()
end)

test("either pilot touching down during countdown resets the whole wing countdown", function()
    local s = wing()
    s.generate(); s.player.airborne = true; s.wingman.airborne = true; s:tick(2)
    s.wingman.airborne = false; s:tick(10)
    assert(string.find(s.logs[#s.logs], "countdown reset", 1, true))
    s.wingman.airborne = true; s:tick(12); s:tick(30); assert(#s.spawns == 0)
    s:tick(32); assert(#s.spawns == 1); s:assertClean()
end)

test("leader reference follows flight number even if unit and player lists are reversed", function()
    local s = wing(true)
    s.player.group.units = { s.wingman, s.player }
    s.players = { s.wingman.raw, s.player.raw }
    s.player.position = { x = 1000, y = 100, z = 2000 }
    s.wingman.position = { x = 90000, y = 500, z = 80000 }
    s:command("Task: Intercept", s.wingman)
    assert(#s.spawns == 1)
    assert(math.abs(s.spawns[1].position.x - (1000 + 60 * 1852 * math.cos(math.rad(-60)))) < 0.001)
    s:assertClean()
end)

test("staggered returns at different bases award each 150; first return keeps wing locked", function()
    local s = wing(true); s.generate(); s:complete()
    s:land(s:base(), 10); hold(s, 11, 21)
    s:score(150); s:score(0, s.wingman)
    s:command("Mission Status"); s:lastMessageContains("WingPilot [Wing10]: RTB_PENDING")
    s.generate(); s:lastMessageContains("Wing assignment blocked"); assert(#s.spawns == 1)
    local otherBase = s:base(2, 0, "OtherBase"); otherBase.position.x = 20000
    s:land(otherBase, 30, s.wingman); hold(s, 31, 41)
    s:score(150); s:score(150, s.wingman)
    s:command("Mission Status"); s:lastMessageContains("Idle")
    s.player.airborne, s.wingman.airborne = true, true
    s.generate(); assert(#s.spawns == 2); s:assertClean()
end)

test("both can finish on the same monitor tick without lost or duplicate receipts", function()
    local s = wing(true); s.generate(); s:complete()
    local base = s:base()
    s:land(base, 10); s:land(base, 10, s.wingman); hold(s, 11, 21)
    s:score(150); s:score(150, s.wingman)
    s:event("Crash", s.player); s:event("Ejection", s.wingman)
    s:score(150); s:score(150, s.wingman); s:assertClean()
end)

test("one safe return and one post-clear failure give 150 and 90 independently", function()
    for _, failure in ipairs({ "Crash", "Dead", "PilotDead", "Ejection", "UnitLost" }) do
        local s = wing(true); s.generate(); s:complete()
        s:land(s:base(), 10); hold(s, 11, 21)
        s:event(failure, s.wingman); s:event("Dead", s.wingman)
        s:score(150); s:score(90, s.wingman)
        s:lastMessageContains("Recovery Failure: 1"); s:assertClean()
    end
end)

test("two post-clear losses award each 90 and close only after the second loss", function()
    local s = wing(true); s.generate(); s:complete()
    s:event("Crash", s.player); s:score(90); s:score(0, s.wingman)
    s.generate(); s:lastMessageContains("Wing assignment blocked")
    s:event("Ejection", s.wingman); s:score(90); s:score(90, s.wingman)
    s:command("Mission Status"); s:lastMessageContains("Idle"); s:assertClean()
end)

test("leader lost before clear remains at zero; surviving wingman can clear and recover", function()
    local s = wing(true); s.generate()
    s:event("Dead", s.player); s:event("Crash", s.player)
    assert(not s.spawns[1].destroyed)
    s:command("Mission Status"); s:lastMessageContains("Lead reference: WingPilot")
    s:complete(); s:land(s:base(), 10, s.wingman); hold(s, 11, 21)
    s:score(0); s:score(150, s.wingman)
    s:lastMessageContains("WingPilot [Wing10]\nTotal Score: 150")
    s:assertClean()
end)

test("all losses before clear close at zero; cleanup deaths never clear the objective", function()
    local s = wing(true); s.generate(); s.cleanupEvents = true
    s:event("Crash", s.player); s:event("Dead", s.wingman)
    assert(s.spawns[1].destroyed)
    s:score(0); s:score(0, s.wingman)
    s:lastMessageContains("Primary Success: 0")
    s:command("Mission Status"); s:lastMessageContains("Idle"); s:assertClean()
end)

test("individual abort leaves partner active and blocked until partner finishes", function()
    local s = wing(true); s.generate()
    s:abortSortie(s.player)
    assert(not s.spawns[1].destroyed)
    s:command("Task: Intercept", s.wingman); s:lastMessageContains("Wing assignment blocked")
    s:complete(); s:land(s:base(), 10, s.wingman); hold(s, 11, 21)
    s:score(0); s:score(150, s.wingman); s:assertClean()
end)

test("abort after personal settlement preserves that score and aborts only pending sorties", function()
    local s = wing(true); s.generate(); s:complete()
    s:land(s:base(), 10); hold(s, 11, 21)
    s:command("Abort Mission", s.wingman)
    s:score(150); s:score(0, s.wingman)
    s:command("Mission Status"); s:lastMessageContains("Idle"); s:assertClean()
end)

test("reservation individual withdrawal excludes only that pilot from departure readiness", function()
    local s = wing(); s.generate()
    s:abortSortie(s.player)
    s.wingman.airborne = true; s:tick(2); s:tick(22)
    assert(#s.spawns == 1)
    s:complete(); s:event("Crash", s.wingman)
    s:score(0); s:score(90, s.wingman); s:assertClean()
end)

test("UCID blocker survives personal settlement and moving to another wing", function()
    local s = wing(true); s.generate(); s:complete(); s:event("Crash", s.player)
    local replacement = s:addPilot("NewSlot", "ucid-a", 40)
    replacement.airborne = true; s:tick(2)
    s:command("Task: Intercept", replacement); s:lastMessageContains("Wing assignment blocked")
    assert(#s.spawns == 1)
    s:event("Crash", s.wingman); s:score(90, replacement)
    s:command("Task: Intercept", replacement); assert(#s.spawns == 2); s:assertClean()
end)

test("from another wing a registered UCID can withdraw its own pending sortie", function()
    local s = wing(true); s.generate(); s:complete()
    local replacement = s:addPilot("NewSlot", "ucid-a", 40); s:tick(2)
    s:command("Abort Mission", replacement); s:lastMessageContains("Use Abort Sortie")
    s:abortSortie(s.player, replacement)
    s:score(0, replacement)
    assert(not s.spawns[1].destroyed)
    s:event("Crash", s.wingman); s:score(90, s.wingman); s:assertClean()
end)

test("late join cannot earn this mission or erase the shared objective with its own accident", function()
    local s = scenario(); s.player.airborne = true; s.generate()
    local late = s:occupyWing(); late.airborne = true
    s:tick(2); s:complete()
    s:land(s:base(), 10, late); s:event("Crash", late); hold(s, 11, 25)
    s:score(0, late); s:score(0)
    s:land(s:base(), 30); hold(s, 31, 41); s:score(150); s:score(0, late)
    s:assertClean()
end)

test("same wing remains blocked even after every original occupant is replaced", function()
    local s = wing(true); s.generate()
    s.player.name, s.wingman.name = "NewLead", "NewWing"
    s.connections[10].name, s.connections[10].ucid = "NewLead", "new-lead"
    s.connections[110].name, s.connections[110].ucid = "NewWing", "new-wing"
    s.generate(); s:lastMessageContains("Wing assignment blocked"); assert(#s.spawns == 1)
    s:command("Abort Mission"); s:lastMessageContains("Only registered mission participants")
    s:assertClean()
end)

test("replacement wingman aircraft cannot recover the original participant's sortie", function()
    local s = wing(true); s.generate(); s:complete()
    local old = s.wingman.raw
    s.wingman.id = 60000; s.wingman:newDCSObject()
    s.players = { s.player.raw, s.wingman.raw }
    s:land(s:base(), 10, s.wingman); hold(s, 11, 25); s:score(0, s.wingman)
    s:event("Crash", s.wingman, nil, 26, old); s:score(90, s.wingman)
    s:event("Crash", s.player); s:score(90); s:assertClean()
end)

test("unverified wingman remains unscored while verified pilot still earns full reward", function()
    local s = wing(true); s.connections[110].ucid = ""
    s.generate(); s:complete()
    s:land(s:base(), 10); hold(s, 11, 21); s:score(150)
    s:event("Crash", s.wingman); s:lastMessageContains("Unscored sortie")
    s:command("Mission Status"); s:lastMessageContains("Idle"); s:assertClean()
end)

test("loss of a reserved crew member cancels reservation and releases its wing blocker", function()
    local s = wing()
    s.generate(); s.wingman.name = nil; s:tick(2)
    s:lastMessageContains("reservation cancelled")
    s.player.airborne = true; s.generate(); assert(#s.spawns == 1); s:assertClean()
end)

test("different wings can start together while each wing blocks a second acceptance", function()
    local s = wing(true); s.generate()
    local other = s:addPilot("Other", "ucid-other", 40); other.airborne = true; s:tick(2)
    s:command("Task: Intercept", other); assert(#s.spawns == 2)
    s:command("Task: Intercept", other); s:lastMessageContains("Wing assignment blocked")
    s.generate(); s:lastMessageContains("Wing assignment blocked")
    assert(s.spawns[1].name ~= s.spawns[2].name)
    assert(#s.spawns == 2); s:assertClean()
end)

test("duplicate UCID in two occupied slots is rejected before acquiring any blocker", function()
    local s = wing(true); s.connections[110].ucid = "ucid-a"
    s.generate(); s:lastMessageContains("same UCID"); assert(#s.spawns == 0)
    s.connections[110].ucid = "ucid-wing"; s.generate(); assert(#s.spawns == 1); s:assertClean()
end)

test("shared mission ledger isolates receipts for two UCIDs and two unscored aircraft", function()
    local env = setmetatable({}, { __index = _G })
    local c = assert(loadfile("src/config.lua")); setfenv(c, env); env.Config = c()
    local chunk = assert(loadfile("src/scoring.lua")); setfenv(chunk, env); local scoring = chunk()
    local a = { id = "shared", owner = { ucid = "a", name = "SameName", objectID = 1 },
        fullReward = 150, primaryCompletedAt = 0 }
    local b = { id = "shared", owner = { ucid = "b", name = "SameName", objectID = 2 },
        fullReward = 150, primaryCompletedAt = 0 }
    local ra, rb = scoring.Settle(a, "RTB_SUCCESS"), scoring.Settle(b, "RTB_FAILURE")
    assert(ra.points == 150 and rb.points == 90 and ra ~= rb)
    assert(scoring.Settle(b, "RTB_SUCCESS") == rb and scoring.Settle(a, "FAILED") == ra)
    a.owner.ucid, b.owner.ucid = nil, nil
    local ua, ub = scoring.Settle(a, "RTB_SUCCESS"), scoring.Settle(b, "RTB_SUCCESS")
    assert(not ua.scored and not ub.scored and ua ~= ub)
    assert(scoring.Get("a").totalScore == 150 and scoring.Get("b").totalScore == 90)
end)

test("two successive cooperative missions accumulate separately for both pilots", function()
    local s = wing(true)
    for n = 1, 2 do
        s.generate(); s:complete()
        s:event("Crash", s.player); s:event("Ejection", s.wingman)
        s:score(90 * n); s:score(90 * n, s.wingman)
    end
    assert(#s.spawns == 2); s:assertClean()
end)

test("immediate reacceptance after cancelled reservation rebuilds pilot abort callbacks", function()
    local s = wing(); s.generate()
    s.wingman.name = nil; s:tick(2)
    s.wingman.name = "WingPilot"; s.generate()
    s:abortSortie(s.player)
    s:lastMessageContains("Individual sortie aborted")
    s.wingman.airborne = true; s:tick(4); s:tick(24)
    assert(#s.spawns == 1); s:assertClean()
end)

test("a stale individual abort callback cannot withdraw a pilot from a later mission", function()
    local s = wing(true); s.generate()
    local label = "Abort Sortie: Pilot [Player10]"
    local stale = s.commands[s.player.group:GetName()][label]
    s:command("Abort Mission"); s.generate()
    stale(); s:lastMessageContains("already closed")
    s:complete(); s:event("Crash", s.player); s:event("Crash", s.wingman)
    s:score(90); s:score(90, s.wingman); s:assertClean()
end)

test("delayed pre-clear loss stays failed with zero primary-success count", function()
    local s = wing(true); s.generate(); s.time = 10; s:complete()
    s:event("Dead", s.player, nil, 5)
    s:score(0)
    local text = s.messages[#s.messages].text
    local first = assert(string.find(text, "PLAYER STATISTICS: WingPilot", 1, true))
    assert(string.find(string.sub(text, 1, first - 1), "Primary Success: 0", 1, true))
    s:land(s:base(), 20, s.wingman); hold(s, 21, 31)
    s:score(150, s.wingman); s:score(0); s:assertClean()
end)

test("two humans with the same display name are still scored and targeted separately", function()
    local s = scenario(); s:occupyWing("Pilot", "ucid-wing")
    s.player.airborne, s.wingman.airborne = true, true
    s.generate(); s:complete()
    s:land(s:base(), 10); hold(s, 11, 21); s:event("Crash", s.wingman)
    s:score(150); s:score(90, s.wingman); s:assertClean()
end)

print(string.format("All %d wing mission tests passed (simulated DCS/MOOSE).", count))
