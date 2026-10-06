-- Build first; terrain and DCS/MOOSE boundaries are simulated.
local scenario = dofile("scripts/Intercept-TestHarness.lua")
local names = { "SEAD_ZONE_PALMYRA", "SEAD_ZONE_SALAMIYAH", "SEAD_ZONE_DUMAYR", "SEAD_ZONE_TABQA" }
local count = 0
local function test(name, callback)
    callback(); count = count + 1; print("PASS: " .. name)
end
local function setup(templateIndex, options)
    local s = scenario(options)
    s.player.position.x, s.wingman.position.x = -80000, -80000
    s.player.airborne, s.wingman.airborne = true, true
    s.zones = {}
    for i, name in ipairs(names) do
        local zone = { name = name, center = { x = i * 20000, y = 0 }, calls = 0, points = {} }
        function zone:GetRandomVec2()
            self.calls = self.calls + 1
            return self.points[self.calls] or self.center
        end
        function zone:GetVec2() return self.center end
        function zone:IsVec2InZone(p)
            return (p.x - self.center.x) ^ 2 + (p.y - self.center.y) ^ 2 <= 3000 ^ 2
        end
        s.zones[name] = zone
    end
    s.randomValues = { templateIndex or 1, 2, 1 } -- Template, PB mode, first eligible zone.
    return s, s.zones[names[1]]
end
local function generate(s)
    s:command("Generate SEAD")
    s:lastMessageContains("SEAD mission accepted.")
end
local function status(s, expected, pilot)
    s:command("Mission Status", pilot); s:lastMessageContains("SEAD: " .. expected)
end
local function object(x, y, radius)
    return { getPoint = function() return { x = x, y = 0, z = y } end,
        getDesc = function()
            if radius then return { box = { min = { x = -radius, z = 0 }, max = { x = radius, z = 0 } } } end
            return {}
        end }
end

test("SA6 and SA8 airborne acceptance plans then ground-spawns with ME layouts, active radars and abort", function()
    for index, name in ipairs({ "TPL_SEAD_SA6", "TPL_SEAD_SA8" }) do
        local s, zone = setup(index)
        s.terrainHeight = function() return 175 end
        generate(s); assert(#s.spawns == 0); status(s, "PLANNING")
        s:tick(1)
        local g = assert(s.spawns[1])
        assert(g.template == name and g.fromVec2 and g.position.y == 175)
        assert(#g.units == (index == 1 and 4 or 1))
        assert(g.alarmRed and g.openFire and g.stopped and zone.calls == 1)
        for _, u in ipairs(g.units) do assert(u.position.y == 175) end
        s:lastMessageContains("SEAD TRAINING START")
        status(s, "ACTIVE"); s:lastMessageContains("THREAT: " .. (index == 1 and "SA-6" or "SA-8"))
        s:command("Abort Mission"); assert(g.destroyed); status(s, "Idle")
        s:score(0); s:assertClean()
    end
end)

test("a whole dry flat footprint is required; failed candidates redraw", function()
    local s, zone = setup()
    zone.points = { { x = 9000, y = 0 }, zone.center } -- Outside the selected zone.
    generate(s); s:tick(1)
    assert(zone.calls == 2 and #s.spawns == 1); s:assertClean()

    for _, bad in ipairs({ "center", "perimeter", "vehicle" }) do
        s, zone = setup()
        zone.points = { { x = 21000, y = 0 }, zone.center }
        s.surfaceLand = function(p)
            if bad == "center" then return p.x ~= 21000 or p.y ~= 0 end
            if bad == "vehicle" then return math.abs(p.x - 21140) > 0.01 or math.abs(p.y) > 0.01 end
            local edgeX, edgeY = 21000 + 200 * math.cos(math.pi / 8), 200 * math.sin(math.pi / 8)
            return math.abs(p.x - edgeX) > 0.01 or math.abs(p.y - edgeY) > 0.01
        end
        generate(s); s:tick(1)
        assert(zone.calls == 2 and #s.spawns == 1 and s.spawns[1].position.x == 20000)
        s:assertClean()
    end
end)

test("height range accepts 20 m and rejects larger interior, perimeter and exact vehicle-position bumps", function()
  for _, height in ipairs({ 20, 20.01 }) do
    for _, bad in ipairs({ "interior", "perimeter", "vehicle" }) do
        local s, zone = setup()
        zone.points = { { x = 21000, y = 0 }, zone.center }
        local x, y = 21050, 50
        if bad == "perimeter" then x, y = 21000 + 200 * math.cos(math.pi / 8), 200 * math.sin(math.pi / 8) end
        if bad == "vehicle" then x, y = 21140, 0 end
        s.terrainHeight = function(p)
            return math.abs(p.x - x) < 0.01 and math.abs(p.y - y) < 0.01 and height or 0
        end
        generate(s); s:tick(1)
        assert(zone.calls == (height == 20 and 1 or 2) and #s.spawns == 1
            and s.spawns[1].position.x == (height == 20 and 21000 or 20000))
        s:assertClean()
    end
  end
end)

test("scenery, statics and units must clear every vehicle including building bounds", function()
    for category = 1, 3 do
        local s, zone = setup()
        zone.points = { { x = 21000, y = 0 }, zone.center }
        s.scanObjects = function()
            local lists = { {}, {}, {} }
            -- 330 m from anchor, but only 190 m from the eastern SA6 launcher.
            lists[category] = { object(21330, 0, 0) }
            return lists
        end
        generate(s); s:tick(1)
        assert(zone.calls == 2 and #s.spawns == 1 and s.spawns[1].position.x == 20000)
        s:assertClean()
    end
    local s, zone = setup(2)
    zone.points = { { x = 21000, y = 0 }, zone.center }
    s.scanObjects = function() return { {}, {}, { object(21220, 0, 30) } } end
    generate(s); s:tick(1)
    assert(zone.calls == 2 and s.spawns[1].position.x == 20000)
    s:assertClean()
end)

test("objects without bounds use a conservative radius; exact 200 m clearance is allowed", function()
    local s, zone = setup(2)
    zone.points = { { x = 21000, y = 0 }, zone.center }
    s.scanObjects = function() return { {}, {}, { object(21225, 0) } } end
    generate(s); s:tick(1)
    assert(zone.calls == 2 and s.spawns[1].position.x == 20000)
    s, zone = setup(2)
    s.scanObjects = function() return { {}, {}, { object(20230, 0, 30) } } end
    generate(s); s:tick(1)
    assert(zone.calls == 1 and #s.spawns == 1); s:assertClean()
end)

test("50 failures release the selected zone without switching; at most two checks per tick", function()
    local s, zone = setup()
    s.surfaceLand = function(p) return p.x > 30000 end
    generate(s)
    for t = 1, 25 do
        s:tick(t); assert(zone.calls == t * 2 and #s.spawns == 0)
    end
    s:lastMessageContains("placement failed")
    assert(zone.calls == 50 and s.zones[names[2]].calls == 0 and #s.errors == 1)
    assert(not s:mission())
end)

test("unsafe selected zone terminates after 50 tries even when other zones exist", function()
    local s = setup(); s.surfaceLand = function() return false end
    generate(s)
    for t = 1, 25 do s:tick(t) end
    s:lastMessageContains("placement failed"); assert(#s.spawns == 0 and #s.errors == 1)
    assert(s.zones[names[1]].calls == 50)
    for i = 2, #names do assert(s.zones[names[i]].calls == 0) end
    s.surfaceLand = nil
    s:command("Generate SEAD"); s:tick(61); assert(#s.spawns == 1)
end)

test("missing zones are skipped; all missing zones fail and permit retry", function()
    local s = setup(); s.zones[names[1]] = nil
    generate(s); s:tick(1)
    assert(#s.spawns == 1 and s.zones[names[2]].calls == 1); s:assertClean()
    s = setup(); local zones = s.zones; s.zones = {}
    s:command("Generate SEAD")
    s:lastMessageContains("setup failed"); assert(#s.errors == 1)
    s.zones = zones; s:command("Generate SEAD"); s:tick(3); assert(#s.spawns == 1)
end)

test("template, terrain, scan and spawn failures release locks and clean spawned enemies", function()
    for _, failure in ipairs({ "missingTemplate", "terrain", "scan", "failSpawn", "failAlarm", "failRouteStop" }) do
        local s = setup()
        if failure == "missingTemplate" then s.missingTemplate = "TPL_SEAD_SA6"
        elseif failure == "terrain" then s.terrainHeight = function() error("terrain API unavailable") end
        elseif failure == "scan" then s.scanObjects = function() error("scenery API unavailable") end
        else s[failure] = true end
        s:command("Generate SEAD"); s:tick(1)
        assert(#s.errors == 1)
        for _, g in ipairs(s.spawns) do assert(g.destroyed) end
        s.missingTemplate, s.terrainHeight, s.scanObjects = nil, nil, nil
        s.failSpawn, s.failAlarm, s.failRouteStop = false, false, false
        s:command("Generate SEAD"); s:tick(2)
        assert(s.spawns[#s.spawns].fromVec2 and not s.spawns[#s.spawns].destroyed)
    end
end)

test("Intercept and SEAD cross-block both while selecting and while active", function()
    local s, zone = setup()
    generate(s)
    s:command("Generate Intercept"); s:lastMessageContains("SEAD mission is already armed")
    assert(zone.calls == 0 and #s.randomValues == 0)
    s:command("Generate SEAD"); assert(zone.calls == 0)
    s:tick(1)
    s:command("Generate Intercept"); s:lastMessageContains("SEAD mission is already active")
    assert(#s.spawns == 1)
    s:command("Abort Mission")
    s.player.airborne = true; s.generate()
    s:command("Generate SEAD"); s:lastMessageContains("Intercept mission is already active")
    assert(#s.spawns == 2); s:assertClean()
end)

test("aborting selection or losing a reserved pilot cannot create a delayed SAM", function()
    for _, cancel in ipairs({ "abort", "replacement", "death" }) do
        local s, zone = setup(); generate(s)
        if cancel == "abort" then s:command("Abort Mission")
        elseif cancel == "replacement" then s.player.id = 999
        else s.player.alive = false end
        s:tick(1); s:tick(20)
        assert(zone.calls == 0 and #s.spawns == 0); s:assertClean()
    end
end)

test("MP2 individual withdrawal during selection leaves the partner's job active", function()
    local s = setup(); s:occupyWing(); generate(s)
    s:abortSortie(s.player)
    status(s, "PLANNING"); s:tick(1)
    assert(#s.spawns == 1); status(s, "ACTIVE")
    s:lastMessageContains("Pilot [Player10]: ABORT")
    s:event("Crash", s.wingman); assert(s.spawns[1].destroyed)
    s:score(0); s:score(0, s.wingman); s:assertClean()
end)

test("distinct wings can select SEAD and Intercept independently", function()
    local s = setup()
    local other = s:addPilot("Other", "ucid-other", 40); other.airborne = true; s:tick(2)
    generate(s); s.randomValues = {}; s:command("Generate Intercept", other)
    s:tick(3); assert(#s.spawns == 2)
    local aircraft, sam = s.spawns[1], s.spawns[2]
    assert(aircraft.name ~= sam.name and sam.fromVec2)
    s:command("Abort Mission"); assert(sam.destroyed and not aircraft.destroyed)
    s:complete(aircraft); s:event("Crash", other); s:score(90, other)
    s:score(0); s:assertClean()
end)

test("two SEAD wings avoid an occupied site and receive different aliases", function()
    local s, zone = setup()
    local other = s:addPilot("Other", "ucid-other", 40)
    other.airborne = true; other.position.x = -80000; s:tick(2)
    generate(s); s:tick(3)
    zone.points[2], zone.points[3] = zone.center, { x = zone.center.x + 1000, y = 0 }
    s.scanObjects = function()
        local units = {}
        for _, g in ipairs(s.spawns) do
            if g.fromVec2 and not g.destroyed then
                for _, u in ipairs(g.units) do units[#units + 1] = object(u.position.x, u.position.z, 10) end
            end
        end
        return { units, {}, {} }
    end
    s.randomValues = { 1, 2, 1 }; s:command("Generate SEAD", other); s:tick(4)
    assert(#s.spawns == 2 and zone.calls == 3)
    assert(s.spawns[1].position.x == 20000 and s.spawns[2].position.x == 21000)
    assert(s.spawns[1].name ~= s.spawns[2].name); s:assertClean()
end)

test("SA6 launcher losses cannot clear while the primary radar is alive", function()
    local s = setup(); generate(s); s:tick(1)
    local g = s.spawns[1]
    for i = 2, #g.units do g.units[i].alive = false; s:event("Dead", g.units[i]) end
    s:tick(2)
    status(s, "ACTIVE")
    g.units[1].alive = false; s:event("Dead", g.units[1])
    s:lastMessageContains("Enemy radar destroyed."); status(s, "RTB_PENDING"); s:score(0)
    s:event("Crash", s.player); s:score(90)
    s:lastMessageContains("SEAD Score: 90"); s:lastMessageContains("Intercept Score: 0")
    s:assertClean()
end)

test("vehicle offsets follow route origin even when the first vehicle is offset", function()
    local s = setup(2)
    s.groundTemplates.TPL_SEAD_SA8.units[1].x = 1015
    generate(s); s:tick(1)
    assert(s.spawns[1].units[1].position.x == 20015); s:assertClean()
end)

test("zone draw chooses one eligible zone without changing the configured pool", function()
    for _, second in ipairs({ true, false }) do
        local s = setup(2)
        s.randomValues = { 2, 2, second and 2 or 1 }
        generate(s); s:tick(1)
        local expected = second and names[2] or names[1]
        assert(s.zones[expected].calls == 1)
        status(s, "ACTIVE")
        s:lastMessageContains("THREAT AREA: " .. (second and "Salamiyah" or "Palmyra"))
        s:assertClean()
    end
end)

local function started(index, options)
    local s = setup(index, options); generate(s); s:tick(1)
    return s, s.spawns[1]
end
local function destroyRadar(s, g, event)
    g.units[1].alive = false
    s:event(event or "Dead", g.units[1])
end
local function recover(s, pilot, time)
    time = time or 10
    s:land(s:base(), time, pilot)
    for t = time, time + 10 do s:tick(t) end
end

test("SA6 radar alone clears with launchers alive; the site and blocker persist until RTB", function()
    local s, g = started()
    destroyRadar(s, g)
    s:lastMessageContains("Enemy radar destroyed.")
    assert(g.units[2].alive and g.units[3].alive and g.units[4].alive and not g.destroyed)
    s:score(0); status(s, "RTB_PENDING")
    s:command("Generate Intercept"); s:lastMessageContains("SEAD mission is already active")
    recover(s); s:score(150)
    s:lastMessageContains("SEAD Score: 150"); s:lastMessageContains("Intercept Score: 0")
    assert(g.destroyed); status(s, "Idle"); s:assertClean()
end)

test("SA8 radar vehicle clears by Dead, Crash or UnitLost even before the wrapper updates", function()
    for _, event in ipairs({ "Dead", "Crash", "UnitLost" }) do
        local s, g = started(2)
        -- The event's recorded identity is sufficient while IsAlive still says true.
        s:event(event, g.units[1])
        s:lastMessageContains("Enemy radar destroyed."); status(s, "RTB_PENDING")
        recover(s); s:score(150); s:assertClean()
    end
end)

test("polling catches missed radar loss but radar shutdown or damage alone cannot clear", function()
    for _, index in ipairs({ 1, 2 }) do
        local s, g = started(index)
        g.units[1].radarEmitting, g.units[1].life = false, 10
        s:tick(2); status(s, "ACTIVE")
        g.units[1].alive = false; s:tick(3)
        s:lastMessageContains("Enemy radar destroyed."); s:score(0)
        recover(s); s:score(150); s:assertClean()
    end
end)

test("SEAD post-clear failures award exactly 90 once; pre-clear failures and abort award zero", function()
    for _, index in ipairs({ 1, 2 }) do
        for _, event in ipairs({ "Crash", "Dead", "PilotDead", "Ejection", "UnitLost" }) do
            local s, g = started(index)
            destroyRadar(s, g); s.cleanupEvents = true
            s:event(event, s.player); s:event("Dead", s.player); s:score(90)
            s:lastMessageContains("SEAD Score: 90"); s:lastMessageContains("Intercept Score: 0")
            s:lastMessageContains("Settled Missions: 1"); s:assertClean()
            s, g = started(index); s.cleanupEvents = true
            s:event(event, s.player); s:complete(g); s:score(0)
            s:lastMessageContains("Primary Success: 0"); s:assertClean()
        end
        local s, g = started(index); destroyRadar(s, g)
        s:command("Abort Mission"); s:score(0); s:assertClean()
    end
end)

test("SEAD safe landing needs ten seconds; later crashes and repeated radar events cannot change 150", function()
    local s, g = started(); destroyRadar(s, g)
    s:land(s:base(), 10)
    for t = 10, 19 do s:tick(t) end
    s:score(0); s:tick(20); s:score(150)
    s:event("Dead", g.units[1]); s:event("Crash", s.player); s:score(150)
    s:lastMessageContains("Settled Missions: 1"); s:assertClean()
end)

test("SEAD radar and pilot-loss event order determines 90 versus zero without retrospective polling", function()
    for _, radarFirst in ipairs({ true, false }) do
        local s, g = started()
        if radarFirst then destroyRadar(s, g); s:event("Crash", s.player)
        else
            g.units[1].alive = false
            s:event("Crash", s.player); s:event("Dead", g.units[1])
        end
        s:tick(2); s:score(radarFirst and 90 or 0); s:assertClean()
    end
end)

test("MP2 shares the radar objective but settles 150 and 90 individually", function()
    local s = setup(); s:occupyWing(); generate(s); s:tick(1)
    local g = s.spawns[1]; destroyRadar(s, g)
    recover(s, s.player)
    s:score(150); s:score(0, s.wingman)
    assert(not g.destroyed)
    s:command("Generate SEAD"); s:lastMessageContains("already active")
    s:event("Ejection", s.wingman)
    s:score(150); s:score(90, s.wingman); assert(g.destroyed); s:assertClean()
end)

test("a pre-clear MP2 loss stays at zero while the survivor clears and recovers for 150", function()
    local s = setup(); s:occupyWing(); generate(s); s:tick(1)
    local g = s.spawns[1]
    s:event("Dead", s.player); destroyRadar(s, g)
    recover(s, s.wingman)
    s:score(150, s.wingman); s:score(0)
    s:lastMessageContains("Primary Success: 0"); s:assertClean()
end)

test("SEAD and Intercept scores accumulate separately for the same UCID", function()
    local s, g = started(); destroyRadar(s, g); recover(s)
    s:score(150); s.player.airborne = true; s.generate()
    s:complete(); s:event("Crash", s.player); s:score(240)
    s:lastMessageContains("Career Points: 240")
    s:lastMessageContains("SEAD Score: 150"); s:lastMessageContains("Intercept Score: 90")
    s:lastMessageContains("Settled Missions: 2"); s:assertClean()
end)

test("another wing's radar events and previous assignments cannot clear the current site", function()
    local s, old = started(); s:command("Abort Mission")
    s.randomValues = { 1, 2, 1 }; generate(s); s:tick(2)
    local current = s.spawns[2]
    s:event("Dead", old.units[1]); status(s, "ACTIVE")
    local other = s:addPilot("Other", "ucid-other", 40)
    other.airborne, other.position.x = true, -80000; s:tick(3)
    s.randomValues = { 1, 2, 2 }; s:command("Generate SEAD", other); s:tick(4)
    local otherGroup = s.spawns[3]
    destroyRadar(s, otherGroup)
    status(s, "RTB_PENDING", other); status(s, "ACTIVE")
    assert(current.units[1].alive)
    destroyRadar(s, current); status(s, "RTB_PENDING"); s:assertClean()
end)

test("major radar selection uses unit type rather than vehicle ordering; every major radar is required", function()
    local s = setup()
    s.groundTemplates.TPL_SEAD_SA6.units[1].type = "Kub 2P25 ln"
    s.groundTemplates.TPL_SEAD_SA6.units[4].type = "Kub 1S91 str"
    generate(s); s:tick(1)
    local g = s.spawns[1]; destroyRadar(s, g); status(s, "ACTIVE")
    g.units[4].alive = false; s:event("Dead", g.units[4]); status(s, "RTB_PENDING")
    s:assertClean()
    s = setup(); s.groundTemplates.TPL_SEAD_SA6.units[2].type = "Kub 1S91 str"
    generate(s); s:tick(1); g = s.spawns[1]
    destroyRadar(s, g); status(s, "ACTIVE")
    g.units[2].alive = false; s:event("Dead", g.units[2]); status(s, "RTB_PENDING")
    s:assertClean()
end)

test("missing or untrackable primary radars fail safely and allow a fresh request", function()
    local s = setup(); s.groundTemplates.TPL_SEAD_SA6.units[1].type = "Kub 2P25 ln"
    s:command("Generate SEAD"); s:lastMessageContains("setup failed")
    assert(#s.spawns == 0 and #s.errors == 1)
    s.groundTemplates.TPL_SEAD_SA6.units[1].type = "Kub 1S91 str"
    s.randomValues = { 1, 2, 1 }
    generate(s); s:tick(1); assert(#s.spawns == 1)
    s = setup(); s.enemyTypeOverride = "Unknown"
    generate(s); s:tick(1)
    s:lastMessageContains("spawn failed"); assert(s.spawns[1].destroyed and #s.errors == 1)
    s.enemyTypeOverride = nil
    generate(s); s:tick(2); assert(not s.spawns[2].destroyed)
end)

test("missing UCID remains unscored after SEAD clearance and recovery", function()
    local s, g = started(2, { unscored = true })
    local unscored = false
    for _, text in ipairs(s.logs) do
        if string.find(text, "[DEBUG]", 1, true) and string.find(text, "(unscored)", 1, true) then unscored = true end
    end
    assert(unscored); destroyRadar(s, g)
    recover(s)
    s:lastMessageContains("Unscored sortie (UCID unavailable).")
    s:command("Player Statistics"); s:lastMessageContains("UCID unavailable; unscored.")
    s:assertClean()
end)

local function fingerprint(plan)
    local fields = { plan.id, plan.missionType, plan.attackMode, plan.template, plan.samType,
        plan.pbCode, plan.primaryUnitType, plan.zoneName, plan.areaLabel,
        plan.acceptancePosition.x, plan.acceptancePosition.y, plan.actualSpawnPoint.x, plan.actualSpawnPoint.y }
    if plan.estimatedPoint then
        fields[#fields + 1], fields[#fields + 2] = plan.estimatedPoint.x, plan.estimatedPoint.y
    end
    for i, value in ipairs(fields) do fields[i] = tostring(value) end
    return table.concat(fields, "|")
end

test("TOO/PB use equal-size random draws and both SAM metadata/code mappings are saved at acceptance", function()
    for template = 1, 2 do
        for mode = 1, 2 do
            local s = setup(template); s.randomValues = { template, mode, 1 }
            generate(s)
            local r = assert(s:mission()); local plan = r.plan
            assert(plan.id == r.id and plan.missionType == "SEAD" and not r.spawn)
            assert(plan.attackMode == (mode == 1 and "TOO" or "PB"))
            assert(plan.template == (template == 1 and "TPL_SEAD_SA6" or "TPL_SEAD_SA8"))
            assert(plan.samType == (template == 1 and "SA-6" or "SA-8"))
            assert(plan.pbCode == (template == 1 and 108 or 117))
            assert(s.randomCalls[2].minimum == 1 and s.randomCalls[2].maximum == 2)
            s:tick(1)
            assert(plan.estimatedPoint ~= nil)
            assert(r.spawn.primaryUnits[1].unit:GetTypeName() == plan.primaryUnitType)
            s:assertClean()
        end
    end
end)

test("TOO displays its fixed search coordinate but hides type, exact location and PB code throughout the sortie", function()
    local s = setup(); s.player.airborne = false; s.randomValues = { 1, 1, 1 }
    generate(s); status(s, "PLANNING"); s:tick(1); status(s, "ARMED")
    local r = s:mission(); local saved = fingerprint(r.plan); local draws = #s.randomCalls
    local location = s.env.COORDINATE:NewFromVec2(r.plan.estimatedPoint):ToStringLLDDM({ LL_Accuracy = 3 })
    local actual = s.env.COORDINATE:NewFromVec2(r.plan.actualSpawnPoint):ToStringLLDDM({ LL_Accuracy = 3 })
    s:lastMessageContains("THREAT AREA: " .. location)
    s.randomValues = { 9999 } -- No estimate redraw during departure/spawn.
    s.player.airborne = true; s:tick(2)
    for t = 4, 22, 2 do s:tick(t) end
    status(s, "ACTIVE")
    assert(fingerprint(r.plan) == saved and #s.randomCalls == draws)
    for _, m in ipairs(s.messages) do
        for _, forbidden in ipairs({ "SA-6", "SA-8", "Kub", "Osa", "TPL_SEAD", actual, "PB CODE", "108", "117", "ESTIMATED LOCATION" }) do
            assert(not string.find(m.text, forbidden, 1, true), m.text)
        end
    end
    s:lastMessageContains("TARGET TYPE: UNKNOWN"); s:lastMessageContains("THREAT AREA: " .. location)
    assert(not string.find(s.messages[#s.messages].text, "THREAT AREA: Palmyra", 1, true))
    s:assertClean()
end)

test("TOO three-to-five NM and PB one-to-three NM estimates match actual spawns across distance and bearing boundaries", function()
  for mode = 1, 2 do
    for _, fraction in ipairs({ 0, 500000, 1000000 }) do
        for _, heading in ipairs({ 0, 90, 180, 359 }) do
            local s = setup(2); s.randomValues = { 2, mode, 1, fraction, heading }
            s.env.COORDINATE.ToStringLLDMS = function() error("SEAD must display DDM coordinates") end
            generate(s); s:tick(1)
            local p = s:mission().plan
            local dx, dy = p.estimatedPoint.x - p.actualSpawnPoint.x, p.estimatedPoint.y - p.actualSpawnPoint.y
            local nm = math.sqrt(dx * dx + dy * dy) / 1852
            assert(math.abs(nm - ((mode == 1 and 3 or 1) + 2 * fraction / 1000000)) < 1e-9)
            local g = s.spawns[1]
            assert(g.position.x == p.actualSpawnPoint.x and g.position.z == p.actualSpawnPoint.y)
            s:command("Mission Status")
            local label = mode == 1 and "THREAT AREA: " or "ESTIMATED LOCATION: "
            local location = s.env.COORDINATE:NewFromVec2(p.estimatedPoint):ToStringLLDDM({ LL_Accuracy = 3 })
            s:lastMessageContains(label .. location)
            assert(not string.find(s.messages[#s.messages].text, "LL DMS", 1, true))
            for _, message in ipairs(s.messages) do
                if string.find(message.text, "SEAD MISSION", 1, true)
                    and not string.find(message.text, "Planning in progress", 1, true) then
                    assert(string.find(message.text, label .. location, 1, true), message.text)
                end
            end
            if mode == 2 then s:lastMessageContains("HARM PB CODE: 117")
            else
                assert(not string.find(s.messages[#s.messages].text, "HARM PB CODE", 1, true))
            end
            assert(not string.find(s.messages[#s.messages].text, "Target:", 1, true))
            s:assertClean()
        end
    end
  end
end)

test("ground acceptance fixes the plan before departure and never redraws after movement or spawning", function()
    local s = setup(); s.player.airborne = false
    generate(s); local r = s:mission(); local id = r.id
    s:tick(1); assert(r.state == "ARMED" and #s.spawns == 0)
    local saved, calls, plan = fingerprint(r.plan), #s.randomCalls, r.plan
    s.player.position = { x = -300000, y = 10000, z = 200000 }
    s:tick(100); assert(#s.spawns == 0 and r.state == "ARMED")
    s.randomValues = { 9999 } -- Any spawn-time random draw would fail.
    s.player.airborne = true; s:tick(102)
    assert(r.state == "TAKEOFF_DELAY" and r.spawnAt == 122)
    for t = 104, 120, 2 do s:tick(t); assert(#s.spawns == 0) end
    s:tick(122); assert(#s.spawns == 1 and r.state == "ACTIVE")
    assert(r.id == id and r.plan == plan and fingerprint(plan) == saved and #s.randomCalls == calls)
    assert(r.participants[1].id == id)
    destroyRadar(s, r.spawn.group); recover(s, nil, 130); s:score(150); s:assertClean()
end)

test("MP2 SEAD waits for all registered humans and resets the full twenty seconds after touchdown", function()
    local s = setup(); local wing = s:occupyWing()
    s.player.airborne, wing.airborne = false, false
    generate(s); s:tick(1); local saved = fingerprint(s:mission().plan)
    s.player.airborne = true
    for t = 2, 10, 2 do s:tick(t); assert(#s.spawns == 0 and s:mission().state == "ARMED") end
    wing.airborne = true; s:tick(12); assert(s:mission().spawnAt == 32)
    wing.airborne = false; s:tick(20); assert(s:mission().state == "ARMED")
    wing.airborne = true; s:tick(22); assert(s:mission().spawnAt == 42)
    for t = 24, 40, 2 do s:tick(t); assert(#s.spawns == 0) end
    s:tick(42); assert(#s.spawns == 1 and fingerprint(s:mission().plan) == saved)
    s:assertClean()
end)

test("SEAD individual withdrawal during departure delay preserves the partner's accepted plan", function()
    local s = setup(); s:occupyWing(); s.player.airborne = false
    generate(s); s:tick(1); local saved = fingerprint(s:mission().plan)
    s.player.airborne = true; s:tick(2); s:abortSortie(s.player)
    assert(s:mission().state == "ARMED")
    s:tick(4); assert(s:mission().spawnAt == 24)
    for t = 6, 24, 2 do s:tick(t) end
    assert(#s.spawns == 1 and fingerprint(s:mission().plan) == saved)
    destroyRadar(s, s.spawns[1]); s:event("Ejection", s.wingman)
    s:score(0); s:score(90, s.wingman); s:assertClean()
end)

test("SEAD reservation cancellation and late joining cannot bypass departure or create a stale SAM", function()
    for _, cancel in ipairs({ "abort", "death", "replacement", "disconnect" }) do
        local s = setup(); s.player.airborne = false; generate(s); s:tick(1)
        if cancel == "abort" then s:command("Abort Mission")
        elseif cancel == "death" then s.player.alive = false
        elseif cancel == "replacement" then s.player.id = 999
        else s.connections[10] = nil; s.player.name = nil end
        s:tick(2); s.player.airborne = true; s:tick(30)
        assert(#s.spawns == 0 and not s:mission()); s:assertClean()
    end
    local s = setup(); s.player.airborne = false; generate(s); s:tick(1)
    local late = s:occupyWing(); late.airborne = false
    s.player.airborne = true; s:tick(2)
    for t = 4, 22, 2 do s:tick(t) end
    assert(#s.spawns == 1 and #s:mission().participants == 1)
    s:assertClean()
end)

test("zone-center distance filtering uses the accepted leader position with inclusive 40/130 NM limits", function()
    for draw = 1, 2 do
        local s = setup(2)
        for i, nm in ipairs({ 39.9, 40, 130, 130.1 }) do
            s.zones[names[i]].center = { x = s.player.position.x + nm * 1852, y = s.player.position.z }
        end
        s.randomValues = { 2, 1, draw }; generate(s)
        local plan = s:mission().plan
        assert(plan.zoneName == names[draw + 1])
        assert(s.randomCalls[3].maximum == 2)
        s.player.position.x = s.player.position.x - 200000
        s:tick(1); assert(s:mission().plan.zoneName == names[draw + 1] and #s.spawns == 1)
        s:assertClean()
    end
end)

test("zone selection uses flight-number leader rather than player enumeration or the requesting menu", function()
    local s = setup(); local wing = s:occupyWing()
    wing.position.x = 1000000
    s.player.group.units = { wing, s.player }
    s:command("Generate SEAD", wing); s:tick(1)
    assert(s:mission().plan.acceptancePosition.x == -80000 and #s.spawns == 1)
    s:assertClean()
end)

test("no zones in range or a missing selected zone safely fail without changing zone", function()
    local s = setup(); s.player.position.x = 1000000
    s:command("Generate SEAD"); s:lastMessageContains("setup failed")
    assert(#s.errors == 1 and not s:mission())
    s.player.position.x = -80000; s.randomValues = { 1, 1, 1 }
    generate(s); s:tick(1); assert(#s.spawns == 1)
    s = setup(); generate(s); s.zones[names[1]] = nil; s:tick(1)
    s:lastMessageContains("placement failed")
    assert(not s:mission() and #s.spawns == 0 and s.zones[names[2]].calls == 0)
end)

test("an unsafe fixed site at departure fails without redrawing or spawning and releases its lock", function()
    for _, change in ipairs({ "terrain", "object", "zone" }) do
        local s, zone = setup(); s.player.airborne = false; generate(s); s:tick(1)
        local r = s:mission(); local saved = fingerprint(r.plan); local draws = #s.randomCalls
        if change == "terrain" then s.surfaceLand = function() return false end
        elseif change == "object" then s.scanObjects = function() return { { object(zone.center.x, zone.center.y, 10) }, {}, {} } end
        else s.zones[names[1]] = nil end
        s.player.airborne = true; s:tick(2)
        for t = 4, 22, 2 do s:tick(t) end
        s:lastMessageContains("spawn failed")
        assert(not s:mission() and #s.spawns == 0 and zone.calls == 1)
        assert(fingerprint(r.plan) == saved and #s.randomCalls == draws and #s.errors == 1)
        s.surfaceLand, s.scanObjects, s.zones[names[1]] = nil, nil, zone
        s.randomValues = { 1, 1, 1 }; generate(s); s:tick(23)
        assert(#s.spawns == 1)
    end
end)

test("two grounded wings reserve different actual sites before any SAM exists", function()
    local s, zone = setup(); s.player.airborne = false
    local other = s:addPilot("Other", "ucid-other", 40); other.position.x = -80000; s:tick(2)
    generate(s); s:tick(3); assert(#s.spawns == 0)
    zone.points[2], zone.points[3] = zone.center, { x = zone.center.x + 1000, y = 0 }
    s.randomValues = { 2, 1, 1 }; s:command("Generate SEAD", other); s:tick(4)
    assert(#s.spawns == 0 and zone.calls == 3)
    local a, b = s:mission(), s:mission(other)
    assert(a.plan.actualSpawnPoint.x == 20000 and b.plan.actualSpawnPoint.x == 21000 and a.id ~= b.id)
    s:command("Abort Mission", other); assert(s:mission() == a and not s:mission(other))
    s.player.airborne = true; s:tick(6)
    for t = 8, 26, 2 do s:tick(t) end
    assert(#s.spawns == 1 and s.spawns[1].position.x == 20000); s:assertClean()
end)

test("the expanded retry limit can find a safe site after the old thirty-attempt limit", function()
    local s, zone = setup()
    for i = 1, 30 do zone.points[i] = { x = 21000, y = 0 } end
    s.surfaceLand = function(p) return p.x ~= 21000 or p.y ~= 0 end
    generate(s)
    for t = 1, 15 do s:tick(t); assert(#s.spawns == 0) end
    assert(s:mission().state == "PLANNING")
    s:tick(16)
    assert(zone.calls == 31 and #s.spawns == 1 and s.spawns[1].position.x == 20000)
    assert(s.zones[names[2]].calls == 0); s:assertClean()
end)

test("placement failure counts every rejection reason without revealing TOO target information", function()
    local s, zone = setup(); s.randomValues = { 1, 1, 1 }
    zone.points = { { x = 9000, y = 0 }, { x = 21000, y = 0 }, zone.center, { x = 22000, y = 0 } }
    s.surfaceLand = function(p) return p.x ~= 21000 or p.y ~= 0 end
    s.terrainHeight = function(p) return p.x == 20050 and p.y == 50 and 21 or 0 end
    s.scanObjects = function() return { {}, {}, { object(22330, 0, 0) } } end
    generate(s); local job = s:mission().selection
    for t = 1, 25 do s:tick(t) end
    assert(not s:mission() and #s.spawns == 0 and #s.errors == 1)
    assert(job.rejections["uneven terrain"] == 47 and job.rejections["non-LAND"] == 1
        and job.rejections["zone boundary"] == 1 and job.rejections["near scenery/static/unit"] == 1)
    for _, text in ipairs({ s.messages[#s.messages].text, s.errors[1] }) do
        for _, fragment in ipairs({ "No safe site in 50 attempts.", "Uneven terrain (height range > 20 m): 47",
            "Not LAND: 1", "Outside area: 1", "Near obstacles: 1", "before rejection: 21.0 m." }) do
            assert(string.find(text, fragment, 1, true), text)
        end
    end
    local message = s.messages[#s.messages].text
    for _, hidden in ipairs({ "SA-6", "Kub", "TPL_SEAD", "LL ", "108", "HARM PB CODE" }) do
        assert(not string.find(message, hidden, 1, true), message)
    end
end)

test("damaged live emitters need sixty full OFF seconds in both modes and both SAM types before RTB scoring", function()
    for template = 1, 2 do
        for mode = 1, 2 do
            local s = setup(template); s.randomValues = { template, mode, 1 }; generate(s); s:tick(1)
            local r = s:mission(); local g = r.spawn.group; local radar = g.units[1]
            assert(r.spawn.primaryUnits[1].initialLife == 100)
            radar.life, radar.radarEmitting = 99, false
            s:tick(2)
            for t = 3, 61 do s:tick(t); assert(r.state == "ACTIVE") end
            s:tick(62); s:lastMessageContains("Enemy radar suppressed.")
            assert(r.state == "RTB_PENDING" and r.primaryResult == "SUPPRESSED" and radar.alive and not g.destroyed)
            status(s, "RTB_PENDING"); s:lastMessageContains("Primary result: SUPPRESSED")
            s:score(0); s:command("Generate SEAD"); s:lastMessageContains("already active")
            radar.radarEmitting = true; s:tick(63); assert(r.primaryResult == "SUPPRESSED")
            recover(s, nil, 70); s:score(150)
            s:lastMessageContains("SEAD Score: 150"); s:lastMessageContains("Primary Success: 1")
            assert(g.destroyed and not s:mission()); s:assertClean()
        end
    end
end)

test("radar OFF without mission-start damage and damage with radar ON cannot complete", function()
    for _, life in ipairs({ 100, 120, 1, 0 }) do
        local s, g = started(); local radar = g.units[1]
        radar.life, radar.radarEmitting = life, life < 100
        radar.radarTarget = nil -- No tracked target still does not mean OFF.
        for t = 2, 100 do s:tick(t) end
        assert(s:mission().state == "ACTIVE" and s:mission().spawn.primaryUnits[1].offSince == nil)
        s:score(0); s:assertClean()
    end
end)

test("undamaged OFF time is excluded; counting starts when damage and OFF are both observed", function()
    local s, g = started(); local radar = g.units[1]; radar.radarEmitting = false
    for t = 2, 100 do s:tick(t) end
    assert(s:mission().state == "ACTIVE")
    radar.life = 99; s:tick(101)
    assert(s:mission().spawn.primaryUnits[1].offSince == 101)
    for t = 102, 160 do s:tick(t) end
    assert(s:mission().state == "ACTIVE")
    s:tick(161); s:lastMessageContains("Enemy radar suppressed."); s:assertClean()
end)

test("radar restart resets OFF continuity and requires a new complete sixty-second interval", function()
    local s, g = started(); local radar = g.units[1]
    radar.life, radar.radarEmitting = 90, false
    for t = 2, 60 do s:tick(t) end
    radar.radarEmitting = true; s:tick(61)
    assert(s:mission().spawn.primaryUnits[1].offSince == nil and s:mission().state == "ACTIVE")
    radar.radarEmitting = false; s:tick(62)
    for t = 63, 121 do s:tick(t) end
    assert(s:mission().state == "ACTIVE")
    s:tick(122); s:lastMessageContains("Enemy radar suppressed."); s:assertClean()
end)

test("invalid alive/life/radar observations and API exceptions break continuity without implying OFF or destruction", function()
    for _, problem in ipairs({ "aliveNil", "aliveNumber", "aliveError", "radarNil", "radarNumber", "radarError", "lifeNil", "lifeNegative", "lifeNaN", "lifeInfinity", "lifeError" }) do
        local s, g = started(); local radar = g.units[1]
        local isAlive = radar.IsAlive
        radar.life, radar.radarEmitting = 95, false
        for t = 2, 60 do s:tick(t) end
        if problem == "aliveNil" then radar.IsAlive = function() return nil end
        elseif problem == "aliveNumber" then radar.IsAlive = function() return 0 end
        elseif problem == "aliveError" then radar.IsAlive = function() error("Injected emitter life observation failure") end
        elseif problem == "radarNil" then radar.radarEmitting = nil
        elseif problem == "radarNumber" then radar.radarEmitting = 0
        elseif problem == "lifeNil" then radar.life = nil
        elseif problem == "lifeNegative" then radar.life = -1
        elseif problem == "lifeNaN" then radar.life = 0 / 0
        elseif problem == "lifeInfinity" then radar.life = math.huge
        else radar[problem] = true end
        s:tick(61); s:tick(62)
        assert(s:mission().spawn.primaryUnits[1].offSince == nil and s:mission().state == "ACTIVE")
        assert(not s:mission().spawn.primaryUnits[1].lost and not s:mission().primaryResult)
        if string.sub(problem, 1, 5) == "alive" then
            s:command("Mission Status")
            assert(s:mission().site.state == "ACTIVE" and s:mission().site.observationUnavailable)
            assert(s:mission().site.remainingTargetCount == nil)
        end
        radar.IsAlive = isAlive
        radar.life, radar.radarEmitting, radar.lifeError, radar.radarError = 95, false, nil, nil
        s:tick(63)
        for t = 64, 122 do s:tick(t) end
        assert(s:mission().state == "ACTIVE")
        s:tick(123); s:lastMessageContains("Enemy radar suppressed."); s:assertClean()
    end
end)

test("damage comparison uses the mission-start snapshot rather than factory life or a later lower reading", function()
    local s = setup(); s.enemyInitialLife = 50; generate(s); s:tick(1)
    local radar = s.spawns[1].units[1]; local record = s:mission().spawn.primaryUnits[1]
    radar.life, radar.radarEmitting = 60, false
    for t = 2, 100 do s:tick(t) end
    assert(record.initialLife == 50 and not record.offSince and s:mission().state == "ACTIVE")
    radar.life = 49; s:tick(101)
    radar.life = 48; s:tick(120) -- Further damage does not restart the OFF timer.
    assert(record.initialLife == 50 and record.offSince == 101)
    for t = 121, 160 do s:tick(t) end
    assert(s:mission().state == "ACTIVE")
    s:tick(161); s:lastMessageContains("Enemy radar suppressed."); s:assertClean()
end)

test("life returning to its initial value resets suppression eligibility", function()
    local s, g = started(); local radar = g.units[1]
    radar.life, radar.radarEmitting = 99, false
    for t = 2, 60 do s:tick(t) end
    radar.life = 100; s:tick(61)
    assert(s:mission().spawn.primaryUnits[1].offSince == nil)
    radar.life = 99; s:tick(62)
    for t = 63, 121 do s:tick(t) end
    assert(s:mission().state == "ACTIVE")
    s:tick(122); s:lastMessageContains("Enemy radar suppressed."); s:assertClean()
end)

test("destruction completes immediately while suppression is pending and does not depend on life/radar readings", function()
    for _, event in ipairs({ "Dead", "poll" }) do
        local s, g = started(); local radar = g.units[1]
        radar.life, radar.radarEmitting = 99, false
        s:tick(2); radar.lifeError, radar.radarError = true, true
        if event == "poll" then radar.alive = false; s:tick(3)
        else s:event(event, radar) end
        s:lastMessageContains("Enemy radar destroyed.")
        assert(s:mission().primaryResult == "DESTROYED")
        s:event("Crash", s.player); s:score(90); s:assertClean()
    end
end)

test("missing mission-start life fails safely rather than substituting a damage baseline", function()
    for _, life in ipairs({ 0, -1, "unknown", math.huge }) do
        local s = setup(); s.enemyInitialLife = life; generate(s); s:tick(1)
        s:lastMessageContains("spawn failed")
        assert(s.spawns[1].destroyed and not s:mission() and #s.errors == 1)
        s.enemyInitialLife = 100; s.randomValues = { 1, 1, 1 }
        generate(s); s:tick(2); assert(not s.spawns[2].destroyed)
    end
end)

test("multiple primary emitters require each to be destroyed or currently suppressed with independent timers", function()
    local s = setup(); s.groundTemplates.TPL_SEAD_SA6.units[2].type = "Kub 1S91 str"
    generate(s); s:tick(1); local g = s.spawns[1]
    g.units[1].life, g.units[1].radarEmitting = 99, false
    for t = 2, 62 do s:tick(t) end
    assert(s:mission().state == "ACTIVE") -- First qualifies, second still active.
    g.units[2].life, g.units[2].radarEmitting = 99, false; s:tick(63)
    g.units[1].radarEmitting = true; s:tick(64)
    for t = 65, 123 do s:tick(t) end
    assert(s:mission().state == "ACTIVE") -- First no longer qualifies.
    g.units[1].alive = false; s:event("Dead", g.units[1]); s:tick(124)
    s:lastMessageContains("Enemy radar suppressed.")
    assert(g.units[2].alive and s:mission().primaryResult == "SUPPRESSED")
    s:assertClean()
end)

test("suppression timers are scoped to their own wing and cannot complete another assignment", function()
    local s, g = started(); local other = s:addPilot("Other", "ucid-other", 40)
    other.airborne, other.position.x = true, -80000; s:tick(3)
    s.randomValues = { 2, 1, 2 }; s:command("Generate SEAD", other); s:tick(4)
    local b = s.spawns[2]
    g.units[1].life, g.units[1].radarEmitting = 99, false
    for t = 5, 65 do s:tick(t) end
    assert(s:mission().primaryResult == "SUPPRESSED" and s:mission(other).state == "ACTIVE")
    b.units[1].life, b.units[1].radarEmitting = 99, false
    for t = 66, 125 do s:tick(t) end
    assert(s:mission(other).state == "ACTIVE")
    s:tick(126); assert(s:mission(other).primaryResult == "SUPPRESSED")
    s:event("Ejection", other); s:score(90, other)
    assert(s:mission().state == "RTB_PENDING" and not g.destroyed)
    recover(s, nil, 130); s:score(150); s:assertClean()
end)

test("MP2 suppression shares the objective and settles 150/90 once while later radar changes preserve success", function()
    local s, g = started(1); s:command("Abort Mission")
    s:occupyWing(); s.randomValues = { 1, 1, 1 }; generate(s); s:tick(2); g = s.spawns[2]
    g.units[1].life, g.units[1].radarEmitting = 99, false
    for t = 3, 63 do s:tick(t) end
    assert(s:mission().primaryResult == "SUPPRESSED")
    g.units[1].radarEmitting = true; s:tick(64)
    recover(s, nil, 70); s:score(150)
    assert(not g.destroyed and s:mission().state == "RTB_PENDING")
    s:event("Ejection", s.wingman); s:event("Dead", s.wingman); s:score(90, s.wingman)
    assert(g.destroyed and not s:mission()); s:score(150); s:assertClean()
end)

test("pilot loss before suppression confirmation gives zero and cleanup cannot retrospectively complete", function()
    local s, g = started(); g.units[1].life, g.units[1].radarEmitting = 99, false
    for t = 2, 61 do s:tick(t) end
    s.cleanupEvents = true; s:event("Crash", s.player, nil, 62)
    s:tick(62); s:score(0); s:lastMessageContains("Primary Success: 0")
    assert(g.destroyed and not s:mission()); s:assertClean()
end)

test("emitter FSM exposes ACTIVE, PENDING, reset and SUPPRESSED independently of wing recovery state", function()
    local s, g = started(); local r = s:mission(); local radar = g.units[1]
    assert(r.spawn.emitterState == "ACTIVE" and r.site.spawn == r.spawn and r.site.plan == r.plan)
    status(s, "ACTIVE"); s:lastMessageContains("Emitter state: ACTIVE")
    radar.radarEmitting = false; s:tick(2)
    assert(r.spawn.emitterState == "ACTIVE") -- OFF alone is not a transition.
    radar.life = 99; s:tick(3)
    assert(r.spawn.emitterState == "SUPPRESSION_PENDING" and r.state == "ACTIVE")
    status(s, "ACTIVE"); s:lastMessageContains("Emitter state: SUPPRESSION PENDING")
    s:lastMessageContains("Radar 1 OFF: 0 / 60 seconds")
    s:tick(62); assert(r.spawn.emitterState == "SUPPRESSION_PENDING")
    radar.radarEmitting = true; s:tick(63)
    assert(r.spawn.emitterState == "ACTIVE" and not r.spawn.primaryUnits[1].offSince)
    radar.radarEmitting = false; s:tick(64); s:tick(124)
    assert(r.spawn.emitterState == "SUPPRESSED" and r.state == "RTB_PENDING")
    s:lastMessageContains("SEAD Objective Complete\nEnemy radar suppressed.")
    status(s, "RTB_PENDING"); s:lastMessageContains("Emitter state: SUPPRESSED")
    local lifeCalls, radarCalls = radar.lifeCalls, radar.radarCalls
    radar.lifeError, radar.radarError, radar.radarEmitting = true, true, true
    s:tick(125); s:event("Dead", radar); s:tick(126)
    assert(radar.lifeCalls == lifeCalls and radar.radarCalls == radarCalls)
    assert(r.spawn.emitterState == "SUPPRESSED" and r.primaryResult == "SUPPRESSED" and not g.destroyed)
    s:score(0); s:assertClean()
end)

test("DESTROYED is terminal from ACTIVE or PENDING and site cleanup preserves the completed result", function()
    for _, pending in ipairs({ false, true }) do
        local s, g = started(); local r = s:mission(); local radar = g.units[1]
        if pending then
            radar.life, radar.radarEmitting = 99, false; s:tick(2)
            assert(r.spawn.emitterState == "SUPPRESSION_PENDING")
        end
        s:event("Dead", radar)
        s:lastMessageContains("SEAD Objective Complete\nEnemy radar destroyed.")
        assert(r.spawn.emitterState == "DESTROYED" and r.primaryResult == "DESTROYED")
        status(s, "RTB_PENDING"); s:lastMessageContains("Emitter state: DESTROYED")
        local calls = radar.lifeCalls
        s:tick(3); assert(radar.lifeCalls == calls and not g.destroyed)
        for i = 2, #g.units do s:event("Dead", g.units[i]) end
        s:score(0); assert(r.primaryResult == "DESTROYED")
        recover(s, nil, 10); s:score(150)
        assert(g.destroyed and r.site.cleaned and r.site.spawn.group == g and r.site.plan == r.plan)
        assert(r.spawn.emitterState == "DESTROYED" and s:sites()[r.id] == nil)
        s:assertClean()
    end
end)

test("SAM lifecycle waits for every participant and is independent of released wing locks", function()
    local s = setup(); s:occupyWing(); generate(s); s:tick(1)
    local r, g = s:mission(), s.spawns[1]
    g.units[1].life, g.units[1].radarEmitting = 99, false; s:tick(2); s:tick(62)
    assert(s:sites()[r.id] == r.site and not r.site.cleanupRequested and not g.destroyCalls)
    recover(s, nil, 70); s:score(150)
    assert(s:sites()[r.id] == r.site and not g.destroyCalls and s:mission() == r)
    g.cleanupFailures = 2; s:event("Ejection", s.wingman)
    s:score(90, s.wingman)
    assert(not s:mission() and s:sites()[r.id] == r.site and r.site.cleanupRequested)
    assert(not g.destroyed and r.spawn.emitterState == "SUPPRESSED" and #s.errors == 1)
    assert(string.find(s.errors[1], "site cleanup pending", 1, true))
    -- Released UCIDs can accept Intercept while cleanup retries retain the SAM reference.
    s:generate(); s:lastMessageContains("Intercept mission armed")
    s:tick(82); assert(s:sites()[r.id] == r.site and not g.destroyed and #s.errors == 1)
    s.cleanupEvents = true; s:tick(83)
    assert(g.destroyed and g.destroyCalls == 3 and r.site.cleaned and s:sites()[r.id] == nil)
    assert(r.spawn.emitterState == "SUPPRESSED" and s:mission().category == "Intercept")
    s:score(150); s:score(90, s.wingman)
end)

test("abort cleanup is independent of success and releases only its own site", function()
    local s, g = started(); local first = s:mission()
    local other = s:addPilot("Other", "ucid-other", 40)
    other.airborne, other.position.x = true, -80000; s:tick(3)
    s.randomValues = { 2, 1, 2 }; s:command("Generate SEAD", other); s:tick(4)
    local second = s:mission(other)
    assert(s:sites()[first.id] and s:sites()[second.id])
    s:command("Abort Mission")
    assert(g.destroyed and not s:mission() and s:sites()[first.id] == nil)
    assert(first.spawn.emitterState == "ACTIVE" and not first.primaryResult)
    assert(s:sites()[second.id] == second.site and not second.spawn.group.destroyed)
    s:tick(5); assert(second.state == "ACTIVE")
    s:score(0); s:assertClean()
end)

test("TOO and PB automatically brief coordinates once; spawn and countdown resets do not repeat them", function()
  for mode = 1, 2 do
    for _, airborne in ipairs({ false, true }) do
        local s, zone = setup()
        s.player.airborne = airborne
        s.randomValues = { 1, mode, 1 }
        local duration = airborne and 90 or 60
        local configured = false
        for i = 1, 100 do
            local name, value = debug.getupvalue(s.timers[1].callback, i)
            if name == "Config" then
                assert(value.coordinateBriefingSeconds == 60)
                value.coordinateBriefingSeconds, configured = duration, true
                break
            end
        end
        assert(configured)
        -- Two rejected candidates keep planning open for a second tick.
        zone.points = { { x = 9000, y = 0 }, { x = 9000, y = 0 }, zone.center }
        local function briefings()
            local n = 0
            for _, message in ipairs(s.messages) do
                if string.find(message.text, "SEAD MISSION\n", 1, true) then n = n + 1 end
            end
            return n
        end
        generate(s)
        s:lastMessageContains("SEAD mission accepted.")
        assert(not string.find(s.messages[#s.messages].text, "MODE:", 1, true))
        assert(string.find(s.logs[#s.logs - 1], "MODE: " .. (mode == 1 and "TOO" or "PB"), 1, true))
        assert(briefings() == 0)
        s:tick(1); assert(s:mission().state == "PLANNING" and briefings() == 0)
        s:tick(2); assert(briefings() == 1)
        local r = s:mission()
        local location = s.env.COORDINATE:NewFromVec2(r.plan.estimatedPoint):ToStringLLDDM({ LL_Accuracy = 3 })
        local label = mode == 1 and "THREAT AREA: " or "ESTIMATED LOCATION: "
        local briefing
        for _, message in ipairs(s.messages) do
            if string.find(message.text, "SEAD MISSION\n", 1, true) then
                briefing = message.text
                assert(message.seconds == duration)
            end
        end
        assert(string.find(briefing, label .. location, 1, true))
        assert(not string.find(briefing, "INSTRUCTIONS", 1, true))
        assert(not string.find(briefing, "Ground acceptance:", 1, true))
        local instruction = mode == 1 and "Search near the reported area" or "Engage the emitter using HARM PB mode"
        local foundDebug = false
        for _, text in ipairs(s.logs) do
            if string.find(text, "[DEBUG]", 1, true) and string.find(text, instruction, 1, true)
                and string.find(text, label .. location, 1, true)
                and string.find(text, "Ground acceptance: SAM spawns 20 seconds", 1, true) then foundDebug = true end
        end
        assert(foundDebug)
        if mode == 1 then
            assert(not string.find(briefing, "HARM PB CODE", 1, true))
            assert(not string.find(briefing, "SA-6", 1, true))
        else assert(string.find(briefing, "HARM PB CODE: 108", 1, true)) end
        if not airborne then
            assert(#s.spawns == 0)
            s:tick(3); s:tick(5); assert(briefings() == 1)
            s.player.airborne = true; s:tick(7)
            assert(string.find(s.logs[#s.logs], "Hostiles will spawn in 20 seconds.", 1, true))
            s.player.airborne = false; s:tick(9)
            assert(string.find(s.logs[#s.logs], "SEAD countdown reset", 1, true))
            s.player.airborne = true; s:tick(11); s:tick(31)
        end
        s:lastMessageContains("SEAD TRAINING START")
        assert(not string.find(s.messages[#s.messages].text, "Pilots:", 1, true))
        local debugPilots = false
        for _, text in ipairs(s.logs) do
            if string.find(text, "[DEBUG]", 1, true) and string.find(text, "SEAD TRAINING START", 1, true)
                and string.find(text, "Pilots:", 1, true) then debugPilots = true end
        end
        assert(debugPilots)
        assert(not string.find(s.messages[#s.messages].text, location, 1, true))
        assert(not string.find(s.messages[#s.messages].text, "HARM PB CODE", 1, true))
        assert(#s.spawns == 1 and briefings() == 1)
        for time = 32, 35 do s:tick(time) end
        assert(briefings() == 1 and r.state == "ACTIVE")
        for n = 1, 2 do
            status(s, "ACTIVE"); s:lastMessageContains(label .. location)
            assert(not string.find(s.messages[#s.messages].text, "INSTRUCTIONS", 1, true))
            assert(s.messages[#s.messages].seconds == duration)
            assert(briefings() == 1 + n)
        end
        s:tick(36); assert(briefings() == 3)
        for _, message in ipairs(s.messages) do
            assert(not string.find(message.text, "Hostiles will spawn", 1, true))
            assert(not string.find(message.text, "countdown reset", 1, true))
            assert(not string.find(message.text, instruction, 1, true))
        end
        s:assertClean()
    end
  end
end)

print(string.format("All %d SEAD tests passed (simulated DCS/MOOSE).", count))
