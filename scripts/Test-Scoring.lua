-- Build first; run from the repository root with Lua 5.1.
local scenario = dofile("scripts/Intercept-TestHarness.lua")
local count = 0
local function test(name, callback)
    callback(); count = count + 1; print("PASS: " .. name)
end
local function started(options)
    local s = scenario(options)
    s.player.airborne = true; s.generate()
    assert(#s.spawns == 1)
    return s
end
local function hold(s, first, last)
    for t = first, last do s:tick(t) end
end

test("airfield recovery awards 150 only after ten continuous stopped seconds", function()
    local s = started()
    s:complete(); s:score(0)
    s:land(s:base(), 10)
    hold(s, 11, 20); s:score(0)
    s:tick(21); s:score(150)
    s:lastMessageContains("Career Points: 150")
    s:lastMessageContains("RTB Success: 1")
    s:command("Mission Status"); s:lastMessageContains("Idle")
    s:assertClean()
end)

test("each post-clear failure type awards exactly 90 despite duplicate events", function()
    for _, event in ipairs({ "Crash", "Dead", "PilotDead", "Ejection", "UnitLost" }) do
        local s = started()
        s:complete(); s:event(event, s.player)
        s:lastMessageContains("Points: +90")
        s.player.name = nil -- Subsequent failure need not contain player data.
        s:event("Dead", s.player); s:event("Crash", s.player); s:event("Ejection", s.player)
        s.player.name = "Pilot"; s:score(90)
        s:lastMessageContains("Recovery Failure: 1")
        s:lastMessageContains("Settled Missions: 1"); s:assertClean()
    end
end)

test("failure before clear gives zero even when cleanup emits enemy death", function()
    local s = started(); s.cleanupEvents = true
    s:event("Ejection", s.player); s:lastMessageContains("Points: +0")
    s:score(0); s:lastMessageContains("Primary Success: 0")
    s:command("Mission Status"); s:lastMessageContains("Idle"); s:assertClean()
end)

test("crash during landing hold gives 90; crash after confirmation cannot reduce 150", function()
    local s = started(); s:complete(); s:land(s:base(), 10); hold(s, 11, 15)
    s:event("Crash", s.player); s:score(90)
    s = started(); s:complete(); s:land(s:base(), 10); hold(s, 11, 21)
    s:event("Crash", s.player); s:event("Dead", s.player); s:score(150); s:assertClean()
end)

test("bolter and takeoff event reset landing hold; a new touchdown is required", function()
    local s = started(); s:complete(); local base = s:base()
    s:land(base, 10); hold(s, 11, 15)
    s:event("RunwayTakeoff", s.player); s.player.airborne = true
    hold(s, 16, 25); s:score(0)
    s:land(base, 26); hold(s, 27, 37); s:score(150); s:assertClean()
end)

test("airborne bounce and excessive speed reset continuous hold", function()
    local s = started(); s:complete(); local base = s:base()
    s:land(base, 10); hold(s, 11, 15)
    s.player.airborne = true; s:tick(16); s.player.airborne = false
    hold(s, 17, 30); s:score(0)
    s:land(base, 31); hold(s, 32, 35)
    s.player.velocity = { x = 5, y = 0, z = 0 }; s:tick(36)
    s.player.velocity.x = 0; hold(s, 37, 46); s:score(0)
    s:tick(47); s:score(150); s:assertClean()
end)

test("duplicate Land and RunwayTouch events do not restart hold or award twice", function()
    local s = started(); s:complete(); local base = s:base()
    s:land(base, 10); hold(s, 11, 15)
    s:event("Land", s.player, base); hold(s, 16, 21); s:score(150)
    s:event("Land", s.player, base); s:event("RunwayTouch", s.player, base)
    hold(s, 22, 35); s:score(150); s:assertClean()
end)

test("moving carrier uses deck-relative speed", function()
    local s = started(); s:complete(); local base, carrier = s:carrier()
    s.player.velocity = { x = 12, y = 0, z = 0 }
    s:land(base, 10)
    for t = 11, 21 do
        base.position.x = base.position.x + 12
        carrier.position.x = base.position.x
        s.player.position.x = base.position.x
        s:tick(t)
    end
    s:score(150); s:assertClean()
end)

test("RED, neutral, FARP, unknown place and unsupported ship do not pay", function()
    for _, kind in ipairs({ "red", "neutral", "farp", "unknown", "ship" }) do
        local s = started(); s:complete()
        local base = s:base(kind == "red" and 1 or 2)
        if kind == "neutral" then base.side = 0 end
        if kind == "farp" then base.category = 1 end
        if kind == "ship" then base.category = 2 end
        if kind == "unknown" then base = nil end
        s.player.airborne = false; s:event("Land", s.player, base)
        hold(s, 1, 20); s:score(0); s:assertClean()
    end
end)

test("leaving the airfield or losing BLUE ownership cancels landing confirmation", function()
    for _, change in ipairs({
        function(s, base) s.player.position.x = 50000 end,
        function(s, base) base.side = 1 end
    }) do
        local s = started(); s:complete(); local base = s:base()
        s:land(base, 10); hold(s, 11, 15); change(s, base)
        hold(s, 16, 30); s:score(0); s:assertClean()
    end
end)

test("wingman and another player cannot settle the owner's sortie", function()
    local s = started(); local other = s:addPilot("Other", "ucid-b", 20)
    s:tick(2); s:complete(); local base = s:base()
    s:land(base, 10, s.wingman); s:event("Crash", s.wingman)
    s:land(base, 10, other); s:event("Dead", other)
    hold(s, 11, 25); s:score(0); s:score(0, other)
    s:land(base, 26); hold(s, 27, 37); s:score(150); s:score(0, other); s:assertClean()
end)

test("menu owner wins even when another BLUE player is first", function()
    local s = scenario(); local other = s:addPilot("Other", "ucid-b", 20)
    s.players = { other.raw, s.player.raw }; s:tick(2)
    other.airborne = true; other.position = { x = 9000, y = 1000, z = 10000 }
    other.heading = 180; s:command("Generate Intercept", other)
    assert(#s.spawns == 1)
    assert(math.abs(s.spawns[1].position.x - s.player.position.x) > 1000)
    s:complete(); s:event("Ejection", other)
    s:score(90, other); s:score(0); s:assertClean()
end)

test("same display name with different slots and UCIDs stays separate", function()
    local s = started(); local other = s:addPilot("Pilot", "ucid-b", 20)
    s:tick(2); s:complete(); s:event("Crash", s.player)
    s:score(90); s:score(0, other); s:assertClean()
end)

test("same UCID retains score across pilot name and slot change", function()
    local s = started(); s:complete(); s:event("Crash", s.player)
    s.player.name = "Renamed"; s.connections[10].name = "Renamed"; s:score(90)
    local other = s:addPilot("NewSlot", "ucid-a", 20); s:tick(2)
    s:score(90, other); s:assertClean()
end)

test("runtime respawn ID is distinct from static network slot", function()
    local s = scenario()
    s.player.id = 50000; s.player:newDCSObject(); s.players = { s.player.raw }
    s.player.airborne = true; s.generate(); s:complete(); s:event("Crash", s.player)
    s:score(90); s:assertClean()
end)

test("replacement aircraft cannot collect original sortie's full reward", function()
    local s = started(); s:complete(); local original = s.player.raw
    s.player.id = 50000; s.player:newDCSObject(); s.players = { s.player.raw }
    s:land(s:base(), 10); hold(s, 11, 25); s:score(0)
    s:event("Crash", s.player, nil, 26, original); s:score(90); s:assertClean()
end)

test("disconnect pauses hold; original pilot may return to the same aircraft", function()
    local s = started(); s:complete(); local base = s:base()
    s:land(base, 10); hold(s, 11, 15)
    s.connections[10] = nil; hold(s, 16, 30)
    s.connections[10] = { id = 10, name = "Pilot", ucid = "ucid-a", side = 2, slot = "10" }
    hold(s, 31, 40); s:score(0); s:tick(41); s:score(150); s:assertClean()
end)

test("UCID missing, ambiguous slot and unavailable net API run unscored", function()
    for _, kind in ipairs({ "missing", "ambiguous", "offline", "error" }) do
        local s = scenario({ unscored = kind == "missing" })
        if kind == "ambiguous" then
            s.connections[99] = { id = 99, name = "Pilot", ucid = "other", side = 2, slot = "10" }
        elseif kind == "offline" then s.env.net = nil
        elseif kind == "error" then s.netFailure = true end
        s.player.airborne = true; s.generate(); assert(#s.spawns == 1)
        s:complete(); s:event("Crash", s.player); s:lastMessageContains("Unscored sortie")
        s:assertClean()
    end
end)

test("slot mismatch never gives credit to a matching display name", function()
    local s = scenario(); s.connections[10].slot = "999"
    s.player.airborne = true; s.generate(); s:complete(); s:event("Crash", s.player)
    s:lastMessageContains("Unscored sortie"); s:assertClean()
end)

test("later UCID availability never retroactively scores an unscored sortie", function()
    local s = started({ unscored = true })
    s.connections[10].ucid = "ucid-a"
    s:complete(); s:land(s:base(), 10); hold(s, 11, 21)
    s:lastMessageContains("Unscored sortie")
    s:score(0); s:assertClean()
end)

test("only owner may abort; voluntary abort gives zero and cleanup cannot win", function()
    local s = started(); local other = s:addPilot("Other", "ucid-b", 20)
    s:tick(2); s:command("Abort Mission", other); s:lastMessageContains("Idle")
    s:complete(); s.cleanupEvents = true; s:command("Abort Mission")
    s:score(0); s:lastMessageContains("Primary Success: 1")
    s:command("Mission Status"); s:lastMessageContains("Idle"); s:assertClean()
end)

test("event-ordered last hostile loss before player death pays 60%; reverse pays zero", function()
    local s = started(); s.time = 1; s:complete(); s:event("Dead", s.player); s:score(90)
    s = started(); s.time = 1; s:event("Dead", s.player); s:complete(); s:score(0); s:assertClean()
end)

test("polling cannot retroactively win after player loss", function()
    local s = started()
    for _, u in ipairs(s.spawns[1].units) do u.alive = false end
    s.player.alive = false; s:event("Dead", s.player); s:tick(2)
    s.player.alive = true; s:tick(4); s:score(0); s:assertClean()
end)

test("second sortie accumulates; stale old-aircraft event cannot pay the new sortie", function()
    local s = started(); s:complete(); local old = s.player.raw
    s:event("Crash", s.player); s:score(90)
    s.player.id = 50000; s.player:newDCSObject(); s.players = { s.player.raw }
    s.generate(); s:complete(); s:event("Crash", s.player, nil, nil, old)
    s:score(90)
    s:land(s:base(), 10); hold(s, 11, 21); s:score(240); s:assertClean()
end)

test("reloading bundle does not duplicate timers, subscriptions or reset points", function()
    local s = started(); s:complete(); s:event("Crash", s.player)
    local timers = #s.timers; s.reload(); assert(#s.timers == timers)
    s:score(90); s:assertClean()
end)

-- Exercise the pure settlement module independently, including non-integer
-- percentage results and duplicate calls with conflicting outcomes.
test("settlement ledger is idempotent and floors 60% to an integer", function()
    local env = setmetatable({}, { __index = _G })
    local c = assert(loadfile("src/config.lua")); setfenv(c, env); env.Config = c()
    local chunk = assert(loadfile("src/scoring.lua")); setfenv(chunk, env); local scoring = chunk()
    local m = { id = "test", owner = { ucid = "ucid-a", name = "Pilot" }, fullReward = 101, primaryCompletedAt = 0 }
    local receipt = scoring.Settle(m, "RTB_FAILURE", "Crash")
    assert(receipt.points == 60 and receipt.total == 60)
    assert(scoring.Settle(m, "RTB_SUCCESS", "Land") == receipt)
    assert(scoring.Get("ucid-a").totalScore == 60)
end)

print(string.format("All %d scoring tests passed (simulated DCS/MOOSE).", count))
