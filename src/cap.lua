-- CAP planning, observed on-station time, enemy wave and cleanup ownership.
local CAP = { cleanup = {} }
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function integer(value) return finite(value) and value % 1 == 0 end
function CAP.Plan(playerPosition, time)
    local cfg = Config.cap
    assert(type(cfg.zones) == "table" and #cfg.zones > 0, "CAP zones are empty.")
    assert(type(playerPosition) == "table" and finite(playerPosition.x) and finite(playerPosition.z),
        "CAP acceptance position unavailable.")
    assert(finite(cfg.minDistanceNM) and finite(cfg.maxDistanceNM) and cfg.minDistanceNM >= 0
        and cfg.maxDistanceNM >= cfg.minDistanceNM, "Invalid CAP zone distance limits.")
    assert(finite(cfg.holdSeconds) and cfg.holdSeconds > 0 and integer(cfg.progressStepPercent)
        and cfg.progressStepPercent > 0 and 100 % cfg.progressStepPercent == 0, "Invalid CAP patrol timing.")
    assert(integer(cfg.enemySpawnMinSeconds) and integer(cfg.enemySpawnMaxSeconds)
        and cfg.enemySpawnMinSeconds >= 0 and cfg.enemySpawnMaxSeconds >= cfg.enemySpawnMinSeconds
        and cfg.enemySpawnMaxSeconds <= cfg.holdSeconds, "Invalid CAP enemy timing.")
    assert(finite(cfg.maxTickCreditSeconds) and cfg.maxTickCreditSeconds > 0
        and finite(cfg.cleanupRetrySeconds) and cfg.cleanupRetrySeconds > 0, "Invalid CAP monitor timing.")
    assert(finite(cfg.spawnOutsideMinNM) and cfg.spawnOutsideMinNM > 0
        and finite(cfg.spawnOutsideMaxNM) and cfg.spawnOutsideMaxNM >= cfg.spawnOutsideMinNM
        and integer(cfg.minAltitudeFt) and cfg.minAltitudeFt > 0 and integer(cfg.maxAltitudeFt)
        and cfg.maxAltitudeFt >= cfg.minAltitudeFt and finite(cfg.speedMps) and cfg.speedMps > 0,
        "Invalid CAP enemy geometry.")
    assert(integer(cfg.fullReward) and cfg.fullReward >= 0, "Invalid CAP reward.")
    local candidates, seen = {}, {}
    for _, name in ipairs(cfg.zones) do
        assert(type(name) == "string" and name ~= "" and not seen[name], "Invalid/duplicate CAP zone.")
        seen[name] = true
        local zone = assert(TrainingZones.Find(name), "CAP zone not found: " .. name)
        local center, radius = zone:GetVec2(), zone:GetRadius()
        assert(center and finite(center.x) and finite(center.y) and finite(radius) and radius > 0,
            "CAP requires a valid circular zone: " .. name)
        local distance = math.sqrt((center.x - playerPosition.x)^2 + (center.y - playerPosition.z)^2) / 1852
        if distance >= cfg.minDistanceNM and distance <= cfg.maxDistanceNM then
            candidates[#candidates + 1] = { zone = zone, name = name,
                center = { x = center.x, y = center.y }, radius = radius }
        end
    end
    if #candidates == 0 then return nil end
    local plan = candidates[math.random(1, #candidates)]
    local templates = Config.intercept.templates
    assert(type(templates) == "table" and #templates > 0, "CAP enemy templates are empty.")
    plan.template = templates[math.random(1, #templates)]
    assert(type(plan.template) == "string" and plan.template ~= "", "Invalid CAP enemy template.")
    plan.enemyAt = math.random(cfg.enemySpawnMinSeconds, cfg.enemySpawnMaxSeconds)
    plan.label = cfg.zoneLabels[plan.name] or plan.name
    plan.coordinate = COORDINATE:NewFromVec2(plan.center):ToStringLLDDM({ LL_Accuracy = 3 })
    plan.holdSeconds, plan.stepPercent, plan.maxCredit = cfg.holdSeconds, cfg.progressStepPercent, cfg.maxTickCreditSeconds
    plan.spawnMinNM, plan.spawnMaxNM = cfg.spawnOutsideMinNM, cfg.spawnOutsideMaxNM
    plan.minAltitudeFt, plan.maxAltitudeFt, plan.speedMps = cfg.minAltitudeFt, cfg.maxAltitudeFt, cfg.speedMps
    plan.elapsed, plan.nextPercent, plan.lastSample, plan.inside = 0, cfg.progressStepPercent, time, false
    plan.acceptancePosition = { x = playerPosition.x, y = playerPosition.z }
    return plan
end
function CAP.Briefing(plan)
    return string.format("CAP AREA: %s\n" ..
        "Objective: patrol inside for %g seconds AND destroy all hostiles.",
        plan.coordinate, plan.holdSeconds)
end
function CAP.Update(plan, participants, time)
    assert(finite(time), "CAP time unavailable.")
    local inside = false
    for _, p in ipairs(participants) do
        if not p.done then
            local ok, eligible = pcall(function()
                return Player.IsControlling(p.owner) and p.owner.unit:InAir() == true
                    and plan.zone:IsVec3InZone(p.owner.unit:GetVec3()) == true
            end)
            if ok and eligible then inside = true; break end
        end
    end
    local update = { progress = {} }
    if inside and plan.inside and time >= plan.lastSample then
        local delta = math.min(time - plan.lastSample, plan.maxCredit)
        plan.elapsed = math.min(plan.holdSeconds, plan.elapsed + delta)
    end
    if inside ~= plan.inside and plan.elapsed < plan.holdSeconds then
        if inside then update.transition = plan.started and "RESUMED" or "STARTED"; plan.started = true
        elseif plan.started then update.transition = "PAUSED" end
    end
    plan.inside, plan.lastSample = inside, time
    while plan.nextPercent <= 100 and plan.elapsed >= plan.holdSeconds * plan.nextPercent / 100 do
        update.progress[#update.progress + 1] = plan.nextPercent
        plan.nextPercent = plan.nextPercent + plan.stepPercent
    end
    update.spawnDue = plan.elapsed >= plan.enemyAt and not plan.spawnAttempted
    return update
end
function CAP.Spawn(plan, assignmentID)
    assert(assignmentID and not plan.spawnAttempted, "CAP wave already attempted or identity unavailable.")
    plan.spawnAttempted = true
    local offset = plan.spawnMinNM + math.random(0, 10000) / 10000 * (plan.spawnMaxNM - plan.spawnMinNM)
    local bearing, altitude = math.random(0, 359), math.random(plan.minAltitudeFt, plan.maxAltitudeFt)
    local center = COORDINATE:NewFromVec2(plan.center):SetAltitude(altitude * 0.3048, true)
    local position = center:Translate(plan.radius + offset * 1852, bearing, true):SetAltitude(altitude * 0.3048, true)
    local enemy = SPAWN:NewWithAlias(plan.template, "DT_CAP_" .. tostring(assignmentID))
        :InitHeading(position:HeadingTo(center)):SpawnFromVec3(position:GetVec3())
    assert(enemy, "CAP enemy spawn failed.")
    plan.enemy = enemy -- Retained even if route configuration fails.
    local engage = enemy:EnRouteTaskEngageTargets(nil, Config.intercept.targetTypes, 0)
    local orbit = enemy:TaskOrbit(center, altitude * 0.3048, plan.speedMps)
    enemy:OptionROEOpenFire()
    enemy:Route({
        position:WaypointAirTurningPoint(COORDINATE.WaypointAltType.BARO, plan.speedMps * 3.6, { engage }),
        center:WaypointAirTurningPoint(COORDINATE.WaypointAltType.BARO, plan.speedMps * 3.6, { engage, orbit })
    })
    return { group = enemy, units = AirTargets.Snapshot(enemy), template = plan.template, altitude = altitude }
end
function CAP.RecordLoss(spawn, event)
    return AirTargets.RecordLoss(spawn, event)
end
function CAP.Remaining(spawn)
    return AirTargets.Remaining(spawn)
end
function CAP.Complete(plan, spawn) return plan.elapsed >= plan.holdSeconds and CAP.Remaining(spawn) == 0 end
function CAP.Status(plan, spawn)
    local remaining = CAP.Remaining(spawn)
    return CAP.Briefing(plan) .. string.format("\nPatrol: %d%% (%d/%g seconds)\nClock: %s\nHostiles remaining: %s",
        math.floor(plan.elapsed / plan.holdSeconds * 100), math.floor(plan.elapsed), plan.holdSeconds,
        plan.elapsed >= plan.holdSeconds and "TIME COMPLETE" or (plan.inside and "RUNNING" or "WAITING / PAUSED"),
        remaining and tostring(remaining) or "NOT SPAWNED")
end
function CAP.Cleanup(group)
    if not group then return end
    local ok, result = pcall(function() return group:Destroy(false) end)
    -- Use the shared runtime's DCS mission clock rather than another scheduler.
    if ok and result ~= false then CAP.cleanup[group] = nil
    else CAP.cleanup[group] = timer.getTime() + Config.cap.cleanupRetrySeconds end
end
function CAP.Sweep(time)
    for group, due in pairs(CAP.cleanup) do if time >= due then CAP.Cleanup(group) end end
end
return CAP
