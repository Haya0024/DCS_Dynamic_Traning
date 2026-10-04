-- Build first; verify follow-on against the real runtime and existing boundary harness.
local scenario = dofile("scripts/Intercept-TestHarness.lua")
local count = 0
local function test(name, run) run(); count = count + 1; print("PASS: " .. name) end
local function module(s, wanted)
    for i = 1, 100 do
        local name, value = debug.getupvalue(s.timers[1].callback, i)
        if not name then break end
        if name == wanted then return value end
    end
    error("Test module unavailable: " .. wanted)
end
local function setup(options)
    local s = scenario(options)
    s.player.position.x, s.player.position.z = -80000, 0
    s.wingman.position.x, s.wingman.position.z = -80000, 0
    s.player.airborne, s.wingman.airborne = true, true
    s.zones = {}
    for i, name in ipairs({ "PALMYRA", "SALAMIYAH", "DUMAYR", "TABQA" }) do
        local z = { center = { x = i * 20000, y = 0 } }
        function z:GetVec2() return self.center end
        function z:GetRandomVec2() return self.center end
        function z:IsVec2InZone(p) return (p.x - self.center.x)^2 + (p.y - self.center.y)^2 <= 3000^2 end
        s.zones["SEAD_ZONE_" .. name] = z
    end
    return s
end
local function begin(s, index, zone, player)
    s.randomValues = { index or 1, 1, zone or 1 }
    s:command("Generate SEAD", player); s:tick(s.time + 1)
    return assert(s:mission(player))
end
local function destroy(s, unit, event)
    unit.alive = false; s:event(event or "Dead", unit)
end
local function primary(s, r, suppressed)
    local radar = r.spawn.primaryUnits[1].unit
    if suppressed then
        radar.life, radar.radarEmitting = 99, false
        s:tick(s.time + 1); s:tick(s.time + 60)
    else destroy(s, radar) end
    assert(r.state == "RTB_PENDING")
end
local function ready(index, suppressed, options)
    local s = setup(options); local r = begin(s, index); primary(s, r, suppressed)
    return s, r, r.site, r.spawn.group
end
local function recover(s, player, base)
    local time = s.time + 10
    s:land(base or s:base(), time, player)
    for t = time, time + 10 do s:tick(t) end
end
local function preserved(index, suppressed, options)
    local s, r, site, g = ready(index, suppressed, options)
    s:command("Preserve Site for DEAD"); recover(s)
    assert(not s:mission() and s:sites()[site.id] == site and not g.destroyed)
    return s, site, g, r
end
local function followOnDead(s, airborne, player)
    (player or s.player).airborne = airborne ~= false
    s:command("Generate DEAD", player)
    return assert(s:mission(player))
end
local function finish(s, r, event)
    for _, t in ipairs(r.deadTargets) do if not t.lost then destroy(s, t.unit, event) end end
    assert(r.state == "RTB_PENDING")
    s:lastMessageContains("DEAD Objective Complete\nSAM site destroyed.\nReturn to base.")
end
local function has(s, command, player) return s.commands[(player or s.player).group:GetName()][command] ~= nil end

test("SA6 suppression offers follow-on while the site defaults to CLEANUP and retains its source assignment", function()
    local s, r, site = ready(1, true)
    assert(site.state == "SUPPRESSED" and site.primaryResult == "SUPPRESSED" and site.followOnAvailable)
    assert(site.disposition == "CLEANUP" and site.sourceMissionID == r.id)
    assert(site.reservedByAssignmentID == r.assignmentID and has(s, "Continue as DEAD") and has(s, "Preserve Site for DEAD"))
    s:command("Mission Status"); s:lastMessageContains("Site disposition: CLEANUP")
    s:lastMessageContains("Follow-on DEAD available: YES"); s:assertClean()
end)

test("SA8 destruction never offers follow-on even if the wrapper still reports alive", function()
    local s = setup(); local r = begin(s, 2)
    s:event("Dead", r.spawn.group.units[1])
    assert(r.spawn.group.units[1].alive and r.site.state == "DESTROYED" and not r.site.followOnAvailable)
    assert(not has(s, "Continue as DEAD") and not has(s, "Preserve Site for DEAD"))
    recover(s); assert(r.site.cleaned); s:score(150); s:assertClean()
end)

test("SA8 alive and suppressed remains a valid one-vehicle DEAD site", function()
    local s, r, site = ready(2, true)
    s:command("Continue as DEAD"); assert(#r.deadTargets == 1 and site.disposition == "IN_USE")
    finish(s, r); recover(s); s:score(300); s:lastMessageContains("DEAD Score: 150"); s:assertClean()
end)

test("ordinary SEAD RTB without follow-on still cleans the site after 150 points", function()
    local s, r, site, g = ready(1, false)
    assert(site.state == "SUPPRESSED" and site.primaryResult == "DESTROYED")
    recover(s); assert(g.destroyed and site.cleaned and not s:sites()[site.id]); s:score(150); s:assertClean()
end)

test("Preserve is idempotent and retains the damaged original site after SEAD settlement", function()
    local s, r, site, g = ready(1, true)
    local callback = s.commands[s.player.group:GetName()]["Preserve Site for DEAD"]
    callback(); local retainedAt = site.retainedAt
    s:tick(s.time + 1); callback()
    assert(site.retainedAt == retainedAt and site.disposition == "RETAIN")
    assert(not has(s, "Preserve Site for DEAD") and has(s, "Continue as DEAD"))
    recover(s); assert(not s:mission() and site.reservedByAssignmentID == nil)
    assert(s:sites()[site.id] == site and site.followOnAvailable and g.units[1].life == 99)
    s:score(150); s:assertClean()
end)

test("CLEANUP and still-active SEAD sites are never Generate DEAD candidates", function()
    local s = setup(); local other = s:addPilot("Other", "ucid-other", 40); other.airborne = true
    s:tick(2); local r = begin(s)
    s:command("Generate DEAD", other); s:lastMessageContains("No preserved SAM sites")
    primary(s, r, true); s:command("Generate DEAD", other); s:lastMessageContains("No preserved SAM sites")
    assert(not s:mission(other) and r.site.disposition == "CLEANUP" and s:mission() == r); s:assertClean()
end)

test("a preserved site stays reserved until every original SEAD participant finishes", function()
    local s = setup(); s:occupyWing()
    local other = s:addPilot("Other", "ucid-other", 40); other.airborne = true; s:tick(2)
    local r = begin(s); primary(s, r, false); s:command("Preserve Site for DEAD")
    recover(s); s:command("Generate DEAD", other); s:lastMessageContains("No preserved SAM sites")
    assert(r.site.reservedByAssignmentID == r.assignmentID and not s:mission(other))
    s:event("Ejection", s.wingman); assert(r.site.reservedByAssignmentID == nil)
    local dead = followOnDead(s, true, other); assert(dead.site == r.site)
    s:score(150); s:score(90, s.wingman); s:assertClean()
end)

test("immediate DEAD uses the same record, ID, group, plan, life and radar without spawn or draws", function()
    local s, r, site, g = ready(1, true)
    local id, assignment, plan, draws = r.id, r.assignmentID, r.plan, #s.randomCalls
    s.env.SPAWN.NewWithAlias = function() error("DEAD must not spawn") end
    s.env.math.random = function() error("DEAD must not draw") end
    s:command("Continue as DEAD")
    assert(s:mission() == r and r.id == id and r.assignmentID == assignment and r.category == "SEAD")
    assert(r.spawn.group == g and r.plan == plan and site.spawn == r.spawn and #s.spawns == 1)
    assert(#s.randomCalls == draws and g.units[1].life == 99 and not g.units[1].radarEmitting)
    assert(r.primaryResult == "SUPPRESSED" and r.primaryCompletedAt and r.deadStartedAt)
    assert(r.state == "DEAD_ACTIVE" and not has(s, "Continue as DEAD") and not has(s, "Preserve Site for DEAD"))
    s:command("Mission Status"); s:lastMessageContains("SEAD: COMPLETE\nFollow-on: DEAD ACTIVE")
    s:lastMessageContains("Remaining targets: 4"); s:assertClean()
end)

test("immediate target snapshot excludes vehicles already destroyed during SEAD", function()
    local s, r, site, g = ready(1, false)
    destroy(s, g.units[2]); s:command("Continue as DEAD")
    assert(#r.deadTargets == 2 and r.deadTargets[1].unit == g.units[3] and r.deadTargets[2].unit == g.units[4])
    assert(site.disposition == "IN_USE" and not site.followOnAvailable)
    destroy(s, g.units[3]); assert(r.state == "DEAD_ACTIVE")
    finish(s, r); assert(r.deadCompletedAt and r.primaryResult == "DESTROYED")
    recover(s); s:score(300); s:lastMessageContains("DEAD Score: 150"); s:assertClean()
end)

test("immediate DEAD missing loss events are detected by polling and SEAD result stays fixed", function()
    local s, r, site = ready(1, true); s:command("Continue as DEAD")
    for _, t in ipairs(r.deadTargets) do t.unit.alive = false end
    s:tick(s.time + 1)
    assert(r.state == "RTB_PENDING" and site.state == "DESTROYED" and site.disposition == "CLEANUP")
    assert(r.primaryResult == "SUPPRESSED" and r.spawn.emitterState == "SUPPRESSED")
    recover(s); s:score(300); s:lastMessageContains("Settled Missions: 1"); s:assertClean()
end)

test("immediate DEAD accidents keep SEAD success and pay ninety once before cleaning IN_USE", function()
    for _, event in ipairs({ "Crash", "Dead", "PilotDead", "Ejection", "UnitLost" }) do
        local s, r, site, g = ready(1, false); s:command("Continue as DEAD")
        s.cleanupEvents = true; s:event(event, s.player); s:event("Dead", s.player)
        s:score(90); s:lastMessageContains("SEAD Score: 90"); s:lastMessageContains("DEAD Score: 0")
        assert(r.primaryResult == "DESTROYED" and not r.deadCompletedAt and site.cleaned and g.destroyed)
        assert(site.disposition == "CLEANUP" and site.reservedByAssignmentID == nil); s:assertClean()
    end
end)

test("immediate DEAD Abort settles both objectives at zero and cleans", function()
    local s, r, site = ready(1, false); s:command("Continue as DEAD"); s:command("Abort Mission")
    assert(site.cleaned and not s:mission()); s:score(0)
    assert(r.participants[1].deadReceipt.result == "ABORT" and r.participants[1].deadReceipt.points == 0)
    s:lastMessageContains("Primary Success: 1"); s:lastMessageContains("DEAD Score: 0"); s:assertClean()
end)

test("Preserve then Continue changes RETAIN to IN_USE and cleanup follows completion", function()
    local s, r, site = ready(1, false)
    s:command("Preserve Site for DEAD"); s:command("Continue as DEAD")
    assert(site.disposition == "IN_USE")
    finish(s, r); recover(s); assert(site.cleaned and not s:sites()[site.id]); s:assertClean()
end)

test("Generate DEAD safely rejects an empty pool and releases Wing and UCID locks", function()
    local s = setup(); s:command("Generate DEAD"); s:lastMessageContains("No preserved SAM sites available for DEAD.")
    assert(#s.spawns == 0 and #s.randomCalls == 0 and not next(s:sites()))
    assert(not s:mission()); s:generate(); assert(s:mission().category == "Intercept"); s:assertClean()
end)

test("Follow-on DEAD acquires the retained site without respawn and uses a new scoring category", function()
    local s, site, g, source = preserved(1, true)
    local draws = #s.randomCalls
    s.env.SPAWN.NewWithAlias = function() error("no respawn") end
    local r = followOnDead(s)
    assert(r.category == "DEAD" and r.id ~= source.id and r.assignmentID ~= source.assignmentID)
    assert(r.site == site and r.spawn.group == g and r.plan == source.plan and #s.spawns == 1)
    assert(#s.randomCalls == draws and g.units[1].life == 99 and not g.units[1].radarEmitting)
    assert(site.sourceMissionID == source.id and site.disposition == "IN_USE")
    assert(site.reservedByAssignmentID == r.assignmentID and #r.deadTargets == 4); s:assertClean()
end)

test("Follow-on DEAD briefing exposes existing site information without internal object names", function()
    local s, site, g = preserved(1, false); followOnDead(s)
    local text = s.messages[#s.messages].text
    for _, expected in ipairs({ "DEAD MISSION", "AREA: Palmyra", "TARGET SITE: SA-6", "Primary radar destroyed", "LL 20000 0" }) do
        assert(string.find(text, expected, 1, true), text)
    end
    assert(not string.find(text, g.name, 1, true) and not string.find(text, "objectID", 1, true))
    s:command("Mission Status"); s:lastMessageContains("DEAD: ACTIVE"); s:lastMessageContains("Remaining targets: 3")
    s:assertClean()
end)

test("ground Follow-on DEAD reserves immediately, snapshots at acceptance and starts at all-airborne without twenty seconds", function()
    local s, site, g = preserved(1, false); s:occupyWing(); s.wingman.airborne = false
    local r = followOnDead(s, false)
    assert(r.state == "ARMED" and site.reservedByAssignmentID == r.assignmentID and #r.deadTargets == 3)
    destroy(s, g.units[2]); assert(r.state == "ARMED" and not r.primaryCompletedAt)
    s.player.airborne = true; s:tick(s.time + 1); assert(r.state == "ARMED")
    s.wingman.airborne = true; s:tick(s.time + 2)
    assert(r.state == "ACTIVE" and r.deadStartedAt == s.time and not r.spawnAt and #s.spawns == 1)
    assert(#r.deadTargets == 3); s:assertClean()
end)

test("all targets lost while ARMED complete only after Follow-on DEAD activates", function()
    local s, site = preserved(1, false); local r = followOnDead(s, false)
    for _, t in ipairs(r.deadTargets) do destroy(s, t.unit) end
    assert(r.state == "ARMED" and not r.primaryCompletedAt)
    s.player.airborne = true; s:tick(s.time + 1); assert(r.state == "ACTIVE")
    s:tick(s.time + 1); assert(r.state == "RTB_PENDING"); recover(s)
    s:score(300); s:lastMessageContains("DEAD Score: 150"); s:assertClean()
end)

test("Follow-on DEAD whole target loss completes and RTB awards DEAD150 alongside SEAD150", function()
    local s, site = preserved(1, false); local r = followOnDead(s)
    destroy(s, r.deadTargets[1].unit); assert(r.state == "ACTIVE")
    finish(s, r); assert(site.state == "DESTROYED" and site.disposition == "CLEANUP" and not site.cleaned)
    s:command("Mission Status"); s:lastMessageContains("DEAD: RTB PENDING")
    recover(s); s:score(300); s:lastMessageContains("DEAD Score: 150"); s:lastMessageContains("SEAD Score: 150")
    s:lastMessageContains("Career Points: 300"); s:lastMessageContains("Settled Missions: 2")
    assert(site.cleaned and not s:sites()[site.id]); s:assertClean()
end)

test("Follow-on DEAD post-primary failure awards DEAD90 once for every supported failure event", function()
    for _, event in ipairs({ "Crash", "Dead", "PilotDead", "Ejection", "UnitLost" }) do
        local s, site = preserved(1, false); local r = followOnDead(s); finish(s, r)
        s:event(event, s.player); s:event("Dead", s.player)
        s:score(240); s:lastMessageContains("DEAD Score: 90"); assert(site.cleaned); s:assertClean()
    end
end)

test("Follow-on DEAD pre-primary accidents and Abort award zero DEAD points and clean the site", function()
    for _, event in ipairs({ "Crash", "Dead", "PilotDead", "Ejection", "UnitLost", "Abort" }) do
        local s, site = preserved(1, false); followOnDead(s)
        if event == "Abort" then s:command("Abort Mission") else s:event(event, s.player) end
        assert(site.cleaned and not s:mission()); s:score(150); s:lastMessageContains("DEAD Score: 0"); s:assertClean()
    end
end)

test("ground Follow-on DEAD abort or aircraft replacement closes its reservation with zero", function()
    for _, change in ipairs({ "Abort", "replacement" }) do
        local s, site = preserved(1, false); followOnDead(s, false)
        if change == "Abort" then s:command("Abort Mission")
        else s.player.id = 999; s:tick(s.time + 1) end
        assert(not s:mission() and site.cleaned and site.reservedByAssignmentID == nil)
        s:score(150); s:lastMessageContains("DEAD Score: 0"); s:assertClean()
    end
end)

test("Generate DEAD chooses the nearest retained site using the current flight-number leader", function()
    local s = setup(); local other = s:addPilot("Other", "ucid-other", 40)
    other.airborne, other.position.x, other.position.z = true, -80000, 0; s:tick(2)
    local a, b = begin(s, 1, 1), begin(s, 1, 4, other)
    primary(s, a, false); s:command("Preserve Site for DEAD"); recover(s)
    primary(s, b, false); s:command("Preserve Site for DEAD", other); recover(s, other)
    s:occupyWing(); s.player.airborne, s.wingman.airborne = true, true
    s.player.position.x, s.wingman.position.x = 79000, 19000
    s.player.group.units = { s.wingman, s.player }
    s:command("Generate DEAD", s.wingman)
    assert(s:mission().site == b.site and a.site.disposition == "RETAIN")
    s:assertClean()
end)

test("nearest selection falls back to spawn coordinate and equal distances resolve consistently", function()
    local s = setup(); local other = s:addPilot("Other", "ucid-other", 40)
    other.airborne, other.position.x, other.position.z = true, -80000, 0; s:tick(2)
    local a, b = begin(s, 1, 1), begin(s, 1, 2, other)
    primary(s, a, false); s:command("Preserve Site for DEAD"); recover(s)
    primary(s, b, false); s:command("Preserve Site for DEAD", other); recover(s, other)
    a.site.plan.actualSpawnPoint = nil
    s.player.position.x, s.player.position.z = 30000, 0
    local r = followOnDead(s); assert(r.site.id == (a.site.id < b.site.id and a.site.id or b.site.id))
    s:assertClean()
end)

test("one retained site cannot be acquired by two Wings even during ground departure wait", function()
    local s, site = preserved(1, false)
    local other = s:addPilot("Other", "ucid-other", 40); other.airborne = true; s:tick(s.time + 2)
    local r = followOnDead(s, false)
    s:command("Generate DEAD", other); s:lastMessageContains("No preserved SAM sites")
    assert(s:mission() == r and not s:mission(other) and site.reservedByAssignmentID == r.assignmentID)
    s:command("Generate Intercept", other); assert(s:mission(other).category == "Intercept"); s:assertClean()
end)

test("DEAD obeys the existing Wing and UCID blocker across all three categories", function()
    local s = setup(); local r = begin(s)
    s:command("Generate DEAD"); s:lastMessageContains("SEAD mission is already active")
    primary(s, r, false); s:command("Preserve Site for DEAD"); recover(s); r = followOnDead(s)
    for _, command in ipairs({ "Generate DEAD", "Generate SEAD", "Generate Intercept" }) do
        s:command(command); s:lastMessageContains("DEAD mission is already active")
    end
    s:occupyWing("SameAccount", "ucid-a")
    s:command("Generate Intercept"); assert(s:mission() == r); s:assertClean()
end)

test("Acquire failure never consumes a retained site", function()
    local s, site = preserved(1, false); local missions = module(s, "Missions")
    local acquire = missions.Acquire
    missions.Acquire = function() return false, "Injected Acquire rejection" end
    s:command("Generate DEAD"); s:lastMessageContains("Injected Acquire rejection")
    assert(site.disposition == "RETAIN" and not site.reservedByAssignmentID and not s:mission())
    missions.Acquire = acquire; assert(followOnDead(s).site == site); s:assertClean()
end)

test("snapshot failure after reservation rolls back the retained site and Wing/UCID locks", function()
    local s, site, g = preserved(1, false); local getUnits, calls = g.GetUnits, 0
    g.GetUnits = function(self)
        calls = calls + 1
        if calls == 3 then error("Injected snapshot failure") end
        return getUnits(self)
    end
    s:command("Generate DEAD"); s:lastMessageContains("reservation rolled back")
    assert(not s:mission() and site.disposition == "RETAIN" and site.followOnAvailable)
    assert(not site.reservedByAssignmentID and not site.cleanupRequested and #s.errors == 1)
    g.GetUnits = getUnits; assert(followOnDead(s).site == site)
end)

test("briefing or reward preparation failure rolls back without deleting the preserved group", function()
    for _, problem in ipairs({ "briefing", "reward" }) do
        local s, site, g = preserved(1, false)
        local coordinate, config = s.env.COORDINATE, module(s, "Config")
        local formatter = coordinate.ToStringLLDMS
        if problem == "briefing" then coordinate.ToStringLLDMS = function() error("Injected briefing failure") end
        else config.dead.fullReward = -1 end
        s:command("Generate DEAD"); s:lastMessageContains("reservation rolled back")
        assert(not s:mission() and site.disposition == "RETAIN" and not site.reservedByAssignmentID and not g.destroyed)
        assert(#s.errors == 1)
        coordinate.ToStringLLDMS, config.dead.fullReward = formatter, 150
        assert(followOnDead(s).site == site)
    end
end)

test("DEAD snapshots only live RED ground vehicles from the actual Group", function()
    local s, r, site, g = ready(1, false)
    g.units[2].side, g.units[3].ground = 2, false
    s:command("Continue as DEAD")
    assert(#r.deadTargets == 1 and r.deadTargets[1].unit == g.units[4])
    finish(s, r); recover(s); s:score(300); s:assertClean()
end)

test("late-added Group vehicles and previous-site events cannot change a fixed DEAD target snapshot", function()
    local s, r, site, g = ready(1, false); s:command("Continue as DEAD")
    local extra = { id = 9000, alive = true }
    local raw = { getID = function() return extra.id end }
    function extra:IsAlive() return self.alive end
    function extra:GetID() return self.id end
    function extra:GetCoalition() return 1 end
    function extra:IsGround() return true end
    function extra:GetDCSObject() return raw end
    g.units[#g.units + 1] = extra
    s:event("Dead", extra); assert(r.state == "DEAD_ACTIVE" and #r.deadTargets == 3)
    s:event("Dead", s.spawns[1].units[1]); assert(r.state == "DEAD_ACTIVE")
    finish(s, r); recover(s); s:score(300); s:assertClean()
end)

test("remaining-target API failures never imply destruction or erase the objective", function()
    local s, site = preserved(1, false); local r = followOnDead(s); local target = r.deadTargets[1].unit
    for i = 2, #r.deadTargets do destroy(s, r.deadTargets[i].unit) end
    local isAlive, getID = target.IsAlive, target.GetID
    target.IsAlive = function() error("Injected life observation failure") end
    s:tick(s.time + 1); assert(r.state == "ACTIVE")
    target.IsAlive = function() return "unknown" end
    s:tick(s.time + 1); assert(r.state == "ACTIVE")
    target.IsAlive = isAlive; target.GetID = function() return nil end
    s:tick(s.time + 1); assert(r.state == "ACTIVE")
    target.GetID = getID; destroy(s, target); assert(r.state == "RTB_PENDING"); s:assertClean()
end)

test("externally destroyed retained sites lose follow-on eligibility and are swept without respawn", function()
    local s, site, g = preserved(1, false)
    for _, u in ipairs(g.units) do u.alive = false end
    s:tick(s.time + 1); assert(site.state == "DESTROYED" and site.cleaned and not s:sites()[site.id])
    s:command("Generate DEAD"); s:lastMessageContains("No preserved SAM sites"); assert(#s.spawns == 1); s:assertClean()
end)

test("unknown retained-site observations block selection without deleting the site", function()
    local s, site, g = preserved(1, false); local getUnits = g.GetUnits
    g.GetUnits = function() error("Injected site observation failure") end
    s:tick(s.time + 1); s:command("Generate DEAD"); s:lastMessageContains("No preserved SAM sites")
    assert(site.disposition == "RETAIN" and not site.followOnAvailable and not g.destroyed and not s:mission())
    assert(site.remainingTargetCount == nil and site.state ~= "DESTROYED")
    g.GetUnits = getUnits; assert(followOnDead(s).site == site); s:assertClean()
end)

test("all remaining vehicles lost before choosing follow-on remove conditional commands", function()
    local s, r, site, g = ready(1, false)
    local callback = s.commands[s.player.group:GetName()]["Continue as DEAD"]
    for i = 2, #g.units do destroy(s, g.units[i]) end
    assert(not has(s, "Continue as DEAD") and not has(s, "Preserve Site for DEAD"))
    callback(); s:lastMessageContains("no longer available")
    assert(r.state == "RTB_PENDING" and site.disposition == "CLEANUP"); recover(s); s:score(150); s:assertClean()
end)

test("stale Continue and Preserve callbacks cannot modify a closed or later assignment", function()
    local s, r, site = ready(1, false)
    local commands = s.commands[s.player.group:GetName()]
    local continue, preserve = commands["Continue as DEAD"], commands["Preserve Site for DEAD"]
    recover(s); s.player.airborne = true; s:generate(); local current = s:mission()
    continue(); preserve()
    assert(s:mission() == current and current.category == "Intercept" and current.state == "ACTIVE")
    assert(site.cleaned and not s:sites()[site.id]); s:assertClean()
end)

test("only the source Wing's registered participants receive and may invoke immediate follow-on", function()
    local s = setup(); local other = s:addPilot("Other", "ucid-other", 40); other.airborne = true; s:tick(2)
    local r = begin(s); primary(s, r, false)
    assert(not has(s, "Continue as DEAD", other))
    local callback = s.commands[s.player.group:GetName()]["Continue as DEAD"]
    s.connections[10].ucid, s.player.name, s.connections[10].name = "new-ucid", "NewPilot", "NewPilot"
    callback(); assert(r.state == "RTB_PENDING" and not has(s, "Continue as DEAD")); s:assertClean()
end)

test("immediate MP2 continuation excludes settled pilots and keeps shared completion and cleanup", function()
    local s = setup(); s:occupyWing(); local r = begin(s); primary(s, r, false)
    recover(s); s:score(150)
    s:command("Continue as DEAD", s.wingman)
    assert(r.participants[1].done and r.participants[1].state == "RTB_SUCCESS" and r.state == "DEAD_ACTIVE")
    assert(not r.participants[1].deadScoring and r.participants[2].deadScoring)
    finish(s, r); recover(s, s.wingman); s:score(300, s.wingman); s:score(150)
    assert(r.site.cleaned); s:lastMessageContains("Settled Missions: 1"); s:assertClean()
end)

test("Follow-on DEAD MP2 shares DEAD objective and independently settles 150 and 90 before cleanup", function()
    local s, site = preserved(1, false); s:occupyWing(); local r = followOnDead(s)
    finish(s, r); recover(s); assert(not site.cleaned and site.reservedByAssignmentID == r.assignmentID)
    s:score(300); s:event("Ejection", s.wingman); s:score(90, s.wingman)
    s:lastMessageContains("DEAD Score: 90"); assert(site.cleaned); s:assertClean()
end)

test("cleanup failures after DEAD retry without retaining locks or awarding another result", function()
    local s, site, g = preserved(1, false); local r = followOnDead(s); finish(s, r)
    g.cleanupFailures, s.cleanupEvents = 2, true; s:event("Ejection", s.player)
    assert(not s:mission() and site.cleanupRequested and not site.cleaned and #s.errors == 1)
    assert(site.disposition == "CLEANUP" and not site.reservedByAssignmentID)
    s:tick(s.time + 1); assert(not site.cleaned)
    s:tick(s.time + 1); assert(site.cleaned and not s:sites()[site.id] and g.destroyCalls == 3)
    s:score(240); s:lastMessageContains("DEAD Score: 90"); assert(#s.errors == 1)
end)

test("Follow-on DEAD last-target and pilot-loss event order gives ninety versus zero without retrospective polling", function()
    for _, targetFirst in ipairs({ true, false }) do
        local s, site = preserved(1, false); local r = followOnDead(s)
        for i = 1, #r.deadTargets - 1 do destroy(s, r.deadTargets[i].unit) end
        local last = r.deadTargets[#r.deadTargets].unit
        if targetFirst then destroy(s, last); s:event("Crash", s.player)
        else last.alive = false; s:event("Crash", s.player); s:event("Dead", last) end
        s:tick(s.time + 1); s:score(targetFirst and 240 or 150)
        assert(site.cleaned); s:assertClean()
    end
end)

test("DEAD recovery reuses moving-carrier relative speed and ten-second confirmation", function()
    local s = setup(); local r = begin(s); primary(s, r, false)
    s:command("Preserve Site for DEAD"); recover(s); r = followOnDead(s); finish(s, r)
    local base, carrier = s:carrier(); s.player.velocity = carrier.velocity
    recover(s, nil, base); s:score(300); s:lastMessageContains("DEAD Score: 150"); s:assertClean()
end)

test("Follow-on DEAD unverified UCID stays unscored and still cleans after recovery", function()
    local s, site = preserved(1, false, { unscored = true }); local r = followOnDead(s); finish(s, r); recover(s)
    s:command("Player Statistics"); s:lastMessageContains("UCID unavailable; unscored.")
    assert(site.cleaned); s:assertClean()
end)

test("late joins do not enter Follow-on DEAD's frozen participants or affect its settlement", function()
    local s, site = preserved(1, false); local r = followOnDead(s)
    s:occupyWing(); s:event("Ejection", s.wingman)
    assert(#r.participants == 1 and r.state == "ACTIVE")
    finish(s, r); recover(s); s:score(300); s:score(0, s.wingman); s:assertClean()
end)

test("Immediate continuation clears an existing landing hold and permits recovery only after DEAD completion", function()
    local s, r = ready(1, false); s:land(s:base(), s.time + 1); s:tick(s.time)
    assert(r.participants[1].landing and r.participants[1].state == "LANDING_CHECK")
    s:command("Continue as DEAD"); assert(not r.participants[1].landing)
    s:land(s:base(), s.time + 1); s:tick(s.time + 20)
    assert(r.state == "DEAD_ACTIVE" and not r.participants[1].done)
    finish(s, r); recover(s); s:score(300); s:assertClean()
end)

test("parallel Follow-on DEAD assignments isolate losses, abort cleanup, scoring and source groups", function()
    local s = setup(); local other = s:addPilot("Other", "ucid-other", 40)
    other.airborne, other.position.x, other.position.z = true, -80000, 0; s:tick(2)
    local a, b = begin(s, 1, 1), begin(s, 1, 4, other)
    primary(s, a, false); s:command("Preserve Site for DEAD"); recover(s)
    primary(s, b, false); s:command("Preserve Site for DEAD", other); recover(s, other)
    s.player.position.x, s.player.position.z, other.position.x, other.position.z = 20000, 0, 80000, 0
    local da, db = followOnDead(s), followOnDead(s, true, other)
    assert(da.site == a.site and db.site == b.site and da.spawn.group ~= db.spawn.group and #s.spawns == 2)
    destroy(s, da.deadTargets[1].unit); assert(db.state == "ACTIVE" and not db.deadTargets[1].lost)
    s.cleanupEvents = true; s:command("Abort Mission")
    assert(a.site.cleaned and not b.site.cleaned and s:mission(other) == db)
    finish(s, db); recover(s, other); s:score(300, other); s:score(150)
    assert(b.site.cleaned); s:assertClean()
end)

test("an active DEAD assignment blocks the same UCID after moving to another Wing", function()
    local s, site = preserved(1, false); local r = followOnDead(s)
    local other = s:addPilot("MovedPilot", "ucid-a", 40); other.airborne = true; s:tick(s.time + 2)
    s:command("Generate Intercept", other); s:lastMessageContains("DEAD mission is already active")
    s:command("Generate DEAD", other); s:lastMessageContains("DEAD mission is already active")
    assert(not s:mission(other) and s:mission() == r and site.reservedByAssignmentID == r.assignmentID)
    s:assertClean()
end)

test("Follow-on DEAD MP2 pre-primary loss stays at zero while its survivor completes and recovers", function()
    local s, site = preserved(1, false); s:occupyWing(); local r = followOnDead(s)
    s:event("Crash", s.player); assert(r.state == "ACTIVE" and not site.cleaned)
    finish(s, r); recover(s, s.wingman)
    s:score(150); s:score(150, s.wingman); assert(site.cleaned); s:assertClean()
end)

test("Follow-on DEAD reward is fixed at acceptance and cannot change while waiting for takeoff", function()
    local s, site = preserved(1, false); local config = module(s, "Config")
    config.dead.fullReward = 175; local r = followOnDead(s, false); assert(r.fullReward == 175)
    config.dead.fullReward = 150; s.player.airborne = true; s:tick(s.time + 1)
    finish(s, r); recover(s); s:score(325); s:lastMessageContains("DEAD Score: 175"); s:assertClean()
end)

test("explicit Preserve survives a later voluntary SEAD abort without converting zero into a reward", function()
    local s, r, site = ready(1, false); s:command("Preserve Site for DEAD"); s:command("Abort Mission")
    assert(not s:mission() and site.disposition == "RETAIN" and not site.cleaned and not site.reservedByAssignmentID)
    s:score(0); local dead = followOnDead(s); finish(s, dead); recover(s)
    s:score(150); s:lastMessageContains("SEAD Score: 0"); s:lastMessageContains("DEAD Score: 150"); s:assertClean()
end)

test("participant readiness failure during acceptance rolls back both Site and assignment reservations", function()
    local s, site, g = preserved(1, false); local inAir = s.player.InAir
    s.player.InAir = function() error("Injected participant readiness failure") end
    s:command("Generate DEAD"); s:lastMessageContains("reservation rolled back")
    assert(not s:mission() and site.disposition == "RETAIN" and site.followOnAvailable)
    assert(not site.reservedByAssignmentID and not g.destroyed and #s.errors == 1)
    s.player.InAir = inAir; assert(followOnDead(s).site == site)
end)

test("prepared DEAD briefing is reused at activation without another coordinate API call", function()
    for _, airborne in ipairs({ true, false }) do
        local s, site = preserved(1, false); local coordinate = s.env.COORDINATE
        local formatter, calls = coordinate.ToStringLLDMS, 0
        coordinate.ToStringLLDMS = function(self)
            calls = calls + 1
            assert(calls == 1, "Briefing coordinate queried again after acceptance")
            return formatter(self)
        end
        local r = followOnDead(s, airborne)
        if not airborne then s.player.airborne = true; s:tick(s.time + 1) end
        assert(r.state == "ACTIVE" and calls == 1 and r.deadBriefing)
        s:lastMessageContains("DEAD TRAINING START"); s:assertClean()
    end
end)

test("preserved-site keeper logout cleans its group without changing settled SEAD points", function()
    local s, site, g = preserved(1, false)
    assert(site.retainedBy.ucid == "ucid-a" and site.retainedBy.playerID == 10)
    s.connections[10] = nil; s:tick(s.time + 1)
    assert(site.cleaned and g.destroyed and not s:sites()[site.id] and site.cleanupReason == "PRESERVER_DISCONNECTED")
    s.connections[10] = { id = 10, name = s.player.name, ucid = "ucid-a", side = 2, slot = "10" }
    s:score(150); s:command("Generate DEAD"); s:lastMessageContains("No preserved SAM sites available for DEAD.")
    assert(not s:mission() and #s.spawns == 1); s:assertClean()
end)

test("UCID connectivity preserves sites across spectators, slot changes, names and network-ID changes", function()
    local s, site, g = preserved(1, false)
    s.connections[10] = nil
    s.connections[77] = { id = 77, name = "RenamedKeeper", ucid = "ucid-a", side = 0, slot = "" }
    s:tick(s.time + 1); assert(not site.cleaned and site.disposition == "RETAIN")
    s.connections[77].side, s.connections[77].slot = 1, "different-slot"
    s:tick(s.time + 1); assert(not site.cleaned and not g.destroyed)
    s.connections[77] = nil
    s.connections[88] = { id = 88, name = s.player.name, ucid = "different-ucid", side = 2, slot = "10" }
    s:tick(s.time + 1); assert(site.cleaned); s:assertClean()
end)

test("MP2 Preserve from the wingman menu assigns the current registered leader and keeps identity fixed", function()
    local s = setup({ reversePlayers = true }); s:occupyWing()
    local r = begin(s); primary(s, r, false); local site, g = r.site, r.spawn.group
    local callback = s.commands[s.player.group:GetName()]["Preserve Site for DEAD"]
    s:command("Preserve Site for DEAD", s.wingman); local keeper = site.retainedBy
    assert(keeper.ucid == "ucid-a")
    recover(s); callback(); assert(site.retainedBy == keeper and keeper.ucid == "ucid-a")
    s.connections[s.wingman.slotID] = nil; s:tick(s.time + 1)
    assert(not site.cleaned and site.disposition == "RETAIN")
    s.connections[10] = nil; s:tick(s.time + 1)
    assert(site.cleaned and g.destroyed and s:mission() == r and r.primaryCompletedAt)
    assert(r.participants[1].done and not r.participants[2].done); s:assertClean()
end)

test("Preserve uses the surviving registered leader when the original leader was lost", function()
    local s = setup(); s:occupyWing(); local r = begin(s); primary(s, r, false)
    s:event("Crash", s.player); s:command("Preserve Site for DEAD", s.wingman)
    assert(r.site.retainedBy.ucid == "ucid-wing")
    s.connections[10] = nil; s:tick(s.time + 1); assert(not r.site.cleaned)
    s.connections[s.wingman.slotID] = nil; s:tick(s.time + 1); assert(r.site.cleaned); s:assertClean()
end)

test("logout before original SEAD settlement detaches the site while preserving wing recovery and locks", function()
    local s, r, site, g = ready(1, false); s:command("Preserve Site for DEAD")
    s.connections[10] = nil; s:tick(s.time + 1)
    assert(site.cleaned and not site.reservedByAssignmentID and g.destroyed)
    assert(s:mission() == r and r.state == "RTB_PENDING" and not r.participants[1].done)
    s.connections[10] = { id = 10, name = s.player.name, ucid = "ucid-a", side = 2, slot = "10" }
    s:command("Generate DEAD"); s:lastMessageContains("SEAD mission is already active")
    recover(s); s:score(150); assert(not s:mission()); s:assertClean()
end)

test("keeper logout cannot destroy sites already handed to Immediate or Follow-on DEAD", function()
    for _, immediate in ipairs({ true, false }) do
        local s, r, site = ready(1, false); s:command("Preserve Site for DEAD")
        if immediate then s:command("Continue as DEAD") else
            recover(s)
            local other = s:addPilot("Other", "ucid-other", 40); other.airborne = true; s:tick(s.time + 2)
            r = followOnDead(s, true, other)
        end
        s.connections[10] = nil; s:tick(s.time + 1)
        assert(site.disposition == "IN_USE" and not site.cleaned and not r.spawn.group.destroyed)
        assert(r.state == (immediate and "DEAD_ACTIVE" or "ACTIVE")); s:assertClean()
    end
end)

test("network exceptions and incomplete snapshots never imply retained-site keeper logout", function()
    local s, site = preserved(1, false); local network = s.env.net
    local getList, getInfo = network.get_player_list, network.get_player_info
    local keeper = site.retainedBy
    s.connections[10] = nil
    for _, problem in ipairs({ "error", "nil-list", "bad-list", "sparse-list", "error-info", "nil-info", "bad-info", "empty-ucid", "no-api", "no-identity" }) do
        network.get_player_list, network.get_player_info = getList, getInfo
        site.retainedBy = keeper
        if problem == "error" then network.get_player_list = function() error("unavailable") end
        elseif problem == "nil-list" then network.get_player_list = function() return nil end
        elseif problem == "bad-list" then network.get_player_list = function() return { invalid = 10 } end
        elseif problem == "sparse-list" then network.get_player_list = function() return { [2] = 10 } end
        elseif problem == "no-api" then network.get_player_list = nil
        elseif problem == "no-identity" then site.retainedBy = {}
        else
            network.get_player_list = function() return { 70 } end
            network.get_player_info = function()
                if problem == "error-info" then error("unavailable player info") end
                if problem == "bad-info" then return "unknown" end
                if problem == "empty-ucid" then return { ucid = "" } end
            end
        end
        s:tick(s.time + 1); assert(site.disposition == "RETAIN" and not site.cleaned)
    end
    network.get_player_list, network.get_player_info = getList, getInfo
    site.retainedBy = keeper
    s:tick(s.time + 1); assert(site.cleaned); s:assertClean()
end)

test("logout cleanup ignores a server entry without UCID and retries failed Destroy without restoring retention", function()
    local s, site, g = preserved(1, false)
    s.env.net.get_server_id = function() return 1 end; s.connections[1] = { id = 1, name = "Server" }
    s.connections[10] = nil; g.cleanupFailures, s.cleanupEvents = 2, true
    s:tick(s.time + 1); assert(not site.cleaned and site.cleanupRequested and site.disposition == "CLEANUP")
    assert(not site.reservedByAssignmentID and #s.errors == 1)
    s.connections[10] = { id = 10, name = s.player.name, ucid = "ucid-a", side = 2, slot = "10" }
    s:tick(s.time + 1); assert(not site.cleaned and site.disposition == "CLEANUP")
    s:tick(s.time + 1); assert(site.cleaned and g.destroyCalls == 3 and #s.errors == 1)
    s:score(150)
end)

test("logout candidates are rejected before the next periodic Sweep and only the keeper's sites are cleaned", function()
    local s = setup(); local other = s:addPilot("Other", "ucid-other", 40)
    other.airborne, other.position.x, other.position.z = true, -80000, 0; s:tick(2)
    local a, b = begin(s, 1, 1), begin(s, 1, 4, other)
    primary(s, a, false); s:command("Preserve Site for DEAD"); recover(s)
    primary(s, b, false); s:command("Preserve Site for DEAD", other); recover(s, other)
    s.connections[10] = nil; local r = followOnDead(s, true, other)
    assert(r.site == b.site and a.site.cleanupRequested and not a.site.followOnAvailable)
    s:tick(s.time + 1); assert(a.site.cleaned and not b.site.cleaned); s:assertClean()
end)

test("unscored preserved sites use their verified network player ID for logout cleanup", function()
    local s, site, g = preserved(1, false, { unscored = true })
    assert(not site.retainedBy.ucid and site.retainedBy.playerID == 10)
    s.connections[10].side, s.connections[10].slot = 0, ""
    s:tick(s.time + 1); assert(not site.cleaned)
    s.connections[10] = nil; s:tick(s.time + 1); assert(site.cleaned and g.destroyed); s:assertClean()
end)

test("SA6 destroyed radar with one or three live launchers supports both DEAD paths independently of primary result", function()
    for _, remaining in ipairs({ 1, 3 }) do
        for _, immediate in ipairs({ true, false }) do
            local s = setup(); local source = begin(s); local g, site = source.spawn.group, source.site
            for i = remaining + 2, #g.units do destroy(s, g.units[i]) end
            primary(s, source, false)
            assert(source.primaryResult == "DESTROYED" and site.primaryResult == "DESTROYED")
            assert(site.seadCompleted and site.state == "SUPPRESSED" and site.remainingTargetCount == remaining)
            assert(site.followOnAvailable and has(s, "Continue as DEAD") and has(s, "Preserve Site for DEAD"))
            s:command("Mission Status"); s:lastMessageContains("SEAD Primary result: DESTROYED")
            s:lastMessageContains("Site state: SUPPRESSED"); s:lastMessageContains("Site remaining vehicles: " .. remaining)
            s.env.SPAWN.NewWithAlias = function() error("DEAD must not spawn") end
            local dead = source
            if immediate then s:command("Continue as DEAD") else
                s:command("Preserve Site for DEAD"); recover(s); dead = followOnDead(s)
                s:lastMessageContains("STATUS: Primary radar destroyed")
            end
            assert(dead.spawn.group == g and #dead.deadTargets == remaining and #s.spawns == 1)
            for _, target in ipairs(dead.deadTargets) do assert(target.unit.kind == "Kub 2P25 ln") end
            finish(s, dead)
            assert(source.primaryResult == "DESTROYED" and site.state == "DESTROYED" and site.remainingTargetCount == 0)
            recover(s); s:score(300); s:lastMessageContains("DEAD Score: 150"); s:assertClean()
        end
    end
end)

test("SA6 suppression snapshots its surviving radar and launchers in Immediate and Follow-on DEAD", function()
    for _, immediate in ipairs({ true, false }) do
        local s, source, site, g = ready(1, true)
        assert(source.primaryResult == "SUPPRESSED" and site.remainingTargetCount == 4 and site.followOnAvailable)
        local dead = source
        if immediate then s:command("Continue as DEAD") else
            s:command("Preserve Site for DEAD"); recover(s); dead = followOnDead(s)
            s:lastMessageContains("STATUS: Previously suppressed")
        end
        assert(#dead.deadTargets == 4 and dead.deadTargets[1].unit == g.units[1])
        assert(g.units[1].alive and g.units[1].life == 99 and not g.units[1].radarEmitting)
        for i = 2, #dead.deadTargets do destroy(s, dead.deadTargets[i].unit) end
        assert(dead.state == (immediate and "DEAD_ACTIVE" or "ACTIVE") and site.remainingTargetCount == 1)
        destroy(s, g.units[1]); assert(dead.state == "RTB_PENDING" and site.remainingTargetCount == 0)
        assert(source.primaryResult == "SUPPRESSED" and site.primaryResult == "SUPPRESSED")
        recover(s); s:score(300); s:lastMessageContains("DEAD Score: 150"); s:assertClean()
    end
end)

test("all SA6 or SA8 site vehicles lost means no DEAD even while wrappers report alive", function()
    for _, template in ipairs({ 1, 2 }) do
        local s = setup(); local r = begin(s, template); local g, site = r.spawn.group, r.site
        for i = 2, #g.units do s:event("Dead", g.units[i]) end
        s:event("Dead", g.units[1])
        assert(r.primaryResult == "DESTROYED" and site.seadCompleted)
        assert(site.state == "DESTROYED" and site.remainingTargetCount == 0 and not site.followOnAvailable)
        for _, unit in ipairs(g.units) do assert(unit.alive) end
        assert(not has(s, "Continue as DEAD") and not has(s, "Preserve Site for DEAD"))
        recover(s); s:command("Generate DEAD"); s:lastMessageContains("No preserved SAM sites available for DEAD.")
        s:score(150); s:assertClean()
    end
end)

test("live site targets alone do not allow DEAD before SEAD primary completion", function()
    local s = setup(); local r = begin(s); local site = r.site
    s:command("Mission Status")
    assert(site.remainingTargetCount == 4 and site.state == "ACTIVE" and not site.seadCompleted)
    assert(not site.followOnAvailable and not has(s, "Continue as DEAD") and not has(s, "Preserve Site for DEAD"))
    local radar = r.spawn.primaryUnits[1].unit; radar.life, radar.radarEmitting = 99, false
    s:tick(s.time + 1); s:tick(s.time + 59)
    assert(r.state == "ACTIVE" and site.remainingTargetCount == 4 and not site.followOnAvailable)
    s:tick(s.time + 1); assert(site.seadCompleted and site.remainingTargetCount == 4 and site.followOnAvailable)
    s:assertClean()
end)

test("Immediate DEAD completed accidents award SEAD90 and DEAD90 once without duplicating statistics", function()
    for _, event in ipairs({ "Crash", "Dead", "PilotDead", "Ejection", "UnitLost" }) do
        local s, r, site = ready(1, true); s:command("Continue as DEAD"); finish(s, r)
        s:event(event, s.player); s:event("Dead", s.player); s:tick(s.time + 1)
        s:score(180); s:lastMessageContains("SEAD Score: 90"); s:lastMessageContains("DEAD Score: 90")
        s:lastMessageContains("Settled Missions: 1"); s:lastMessageContains("Primary Success: 1")
        s:lastMessageContains("Recovery Failure: 1")
        assert(r.participants[1].deadReceipt.result == "RTB_FAILURE" and site.cleaned); s:assertClean()
    end
end)

test("Immediate DEAD fixes a separate reward and ledger at Continue while retaining one assignment", function()
    for _, reward in ipairs({ 175, 0 }) do
        local s, r = ready(1, false); local config = module(s, "Config")
        local callback = s.commands[s.player.group:GetName()]["Continue as DEAD"]
        config.dead.fullReward = reward; callback()
        local scoreID, primaryAt = r.deadScoringID, r.primaryCompletedAt
        config.dead.fullReward = 50; callback()
        assert(r.deadScoringID == scoreID and scoreID ~= r.id and r.deadFullReward == reward)
        assert(s:mission() == r and r.category == "SEAD" and r.participants[1].deadScoring.scoreOnly)
        finish(s, r); recover(s); s:score(150 + reward)
        s:lastMessageContains("DEAD Score: " .. reward); s:lastMessageContains("Settled Missions: 1")
        assert(r.primaryCompletedAt == primaryAt and r.participants[1].deadReceipt.missionID == scoreID)
        s:assertClean()
    end
end)

test("Immediate DEAD MP2 separately awards combined 300 and 180 and retains the site until both settle", function()
    local s = setup(); s:occupyWing(); local r = begin(s); primary(s, r, false)
    s:command("Continue as DEAD"); finish(s, r); recover(s)
    assert(not r.site.cleaned and s:mission() == r); s:score(300)
    s:event("Ejection", s.wingman); s:event("Dead", s.wingman)
    s:score(180, s.wingman); s:lastMessageContains("DEAD Score: 90")
    s:lastMessageContains("Settled Missions: 1"); assert(r.site.cleaned); s:assertClean()
end)

test("Immediate DEAD participant lost before its objective cannot retroactively earn the survivor's DEAD points", function()
    local s = setup(); s:occupyWing(); local r = begin(s); primary(s, r, false)
    s:command("Continue as DEAD"); s:event("Crash", s.player)
    local p = r.participants[1]; assert(p.deadReceipt.points == 0 and p.deadReceipt.result == "FAILED")
    assert(not p.deadScoring.primaryCompletedAt and not r.site.cleaned)
    finish(s, r); recover(s, s.wingman)
    assert(not p.deadScoring.primaryCompletedAt and p.primaryCompletedAt)
    s:score(90); s:score(300, s.wingman); assert(r.site.cleaned); s:assertClean()
end)

test("Immediate DEAD last target versus pilot loss preserves event order for its additional award", function()
    for _, targetFirst in ipairs({ true, false }) do
        local s, r = ready(1, false); s:command("Continue as DEAD")
        for i = 1, #r.deadTargets - 1 do destroy(s, r.deadTargets[i].unit) end
        local last = r.deadTargets[#r.deadTargets].unit
        if targetFirst then destroy(s, last); s:event("Crash", s.player)
        else last.alive = false; s:event("Crash", s.player); s:event("Dead", last) end
        s:tick(s.time + 1); s:score(targetFirst and 180 or 90); s:assertClean()
    end
end)

test("Immediate DEAD delayed pre-completion accident pays only the earlier SEAD success", function()
    local s, r = ready(1, false); s:command("Continue as DEAD")
    local crashAt = s.time + 1; s:tick(s.time + 2); finish(s, r)
    assert(r.deadCompletedAt > crashAt and r.primaryCompletedAt < crashAt)
    s:event("Crash", s.player, nil, crashAt); s:score(90)
    assert(r.participants[1].deadReceipt.result == "FAILED" and not r.participants[1].deadScoring.primaryCompletedAt)
    s:lastMessageContains("DEAD Score: 0"); s:assertClean()
end)

test("Immediate DEAD unverified UCID settles both objectives unscored and still cleans", function()
    local s, r, site = ready(1, true, { unscored = true })
    s:command("Continue as DEAD"); finish(s, r); recover(s)
    local p = r.participants[1]
    assert(p.receipt.points == 0 and not p.receipt.scored and p.deadReceipt.points == 0 and not p.deadReceipt.scored)
    s:command("Player Statistics"); s:lastMessageContains("UCID unavailable; unscored.")
    assert(site.cleaned); s:assertClean()
end)

test("Immediate DEAD voluntary Abort after both objectives pays neither and counts only one abort", function()
    local s, r = ready(1, false); s:command("Continue as DEAD"); finish(s, r); s:command("Abort Mission")
    s:score(0); s:lastMessageContains("Settled Missions: 1")
    assert(r.participants[1].receipt.result == "ABORT" and r.participants[1].deadReceipt.result == "ABORT")
    assert(r.site.cleaned); s:assertClean()
end)

test("invalid Immediate DEAD reward leaves SEAD recovery and site disposition intact", function()
    for _, reward in ipairs({ -1, math.huge, 0/0, 1.5, "150" }) do
        local s, r, site = ready(1, false); local config = module(s, "Config")
        config.dead.fullReward = reward; s:command("Continue as DEAD")
        assert(r.state == "RTB_PENDING" and not r.deadScoringID and not r.deadStartedAt)
        assert(not r.participants[1].deadScoring and site.disposition == "CLEANUP" and #s.errors == 1)
        recover(s); s:score(150); s:lastMessageContains("DEAD Score: 0"); assert(site.cleaned)
    end
end)

test("additional DEAD ledger retries cannot duplicate points or mission statistics", function()
    local env = setmetatable({ Config = { recoveryFailurePercent = 60 } }, { __index = _G })
    local chunk = assert(loadfile("src/scoring.lua")); setfenv(chunk, env); local scoring = chunk()
    local owner = { ucid = "ucid-a", name = "Pilot" }
    local sead = { id = scoring.NextID("SEAD"), category = "SEAD", owner = owner, fullReward = 150, primaryCompletedAt = 1 }
    local dead = { id = scoring.NextID("DEAD"), category = "DEAD", owner = owner, fullReward = 101,
        primaryCompletedAt = 2, scoreOnly = true }
    scoring.Settle(sead, "RTB_FAILURE", "Crash")
    local receipt = scoring.Settle(dead, "RTB_FAILURE", "Crash")
    assert(receipt.points == 60 and scoring.Settle(dead, "RTB_SUCCESS", "Land") == receipt)
    local p = scoring.Get(owner.ucid)
    assert(p.totalScore == 150 and p.careerPoints == 150 and p.seadScore == 90 and p.deadScore == 60)
    assert(p.missionCount == 1 and p.primarySuccessCount == 1 and p.recoveryFailureCount == 1)
    assert(p.rtbSuccessCount == 0 and p.failedCount == 0 and p.abortCount == 0)
    scoring.Settle({ id = "abort", category = "DEAD", owner = owner, fullReward = 150, scoreOnly = true }, "ABORT", "Abort")
    assert(p.totalScore == 150 and p.missionCount == 1 and p.abortCount == 0)
end)

print(string.format("All %d DEAD tests passed (simulated DCS/MOOSE).", count))
