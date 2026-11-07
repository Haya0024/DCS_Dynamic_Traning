-- Scoped integration of pinned MOOSE AUTOLASE policy and SPOT tracking.
-- CAS owns targets, scheduling, messages and teardown; no world-wide INTEL scan.
local CASAutolase = {}
local finite = Observations.Finite

local function owned(plan, state)
    return plan.autolase == state and not state.stopped and not plan.closing
        and Missions.casSites[plan.site.id] == plan
end

local function change(plan, state, key, message)
    if state.status == key then return end
    state.status = key
    env.info("[DynamicTraining] [DEBUG] CAS AUTOLASE; assignment=" .. plan.assignmentID .. "; " .. key)
    if message then state.messages[#state.messages + 1] = message end
end

local function observed(target, side)
    if target.lost then return false end
    local alive = Observations.TargetAlive(target, true)
    if not alive then return false end
    assert(target.unit:GetCoalition() == side and target.unit:IsGround() == true, "Designation identity/side changed.")
    assert(Observations.Vec3(target.unit:GetVec3()), "Designation position unavailable.")
    return true
end

local function allowed(plan, state, target)
    if not owned(plan, state) then return false, "STOPPED" end
    if not state.requested then return false, "STANDBY" end
    local ok, visible = pcall(function()
        if not observed(plan.jtac, coalition.side.BLUE) then return false end
        if not observed(target, coalition.side.RED) then return false end
        return state.engine:CanLase(plan.jtac.unit, target.unit)
    end)
    if not ok or type(visible) ~= "boolean" then return false, "OBSERVATION_UNAVAILABLE" end
    return visible, visible and "VISIBLE" or "NOT_VISIBLE"
end

local function clearScheduler(scheduler)
    if not scheduler then return true end
    local ok, result = pcall(scheduler.Clear, scheduler)
    return ok and result ~= false
end

local function releaseSpot(state)
    local spot = state.spot
    if not spot then return true end
    -- Disable tracking before attempting any external operation, including on
    -- partial creation. Keep each native handle until its destroy call succeeds.
    spot.Lasing = false
    local clean = clearScheduler(spot.CallScheduler)
    clean = clearScheduler(spot.LaseScheduler) and clean
    local ok, result = pcall(spot.UnHandleEvent, spot, EVENTS.Dead)
    clean = ok and result ~= false and clean
    for _, field in ipairs({ "SpotIR", "SpotLaser" }) do
        local native = spot[field]
        if native then
            ok, result = pcall(native.destroy, native)
            if ok and result ~= false then spot[field] = nil else clean = false end
        end
    end
    if clean then
        spot.Target, state.spot, state.target = nil, nil, nil
    end
    return clean
end

function CASAutolase.Start(plan)
    assert(not plan.autolase, "CAS designator already initialized.")
    local cfg = Config.cas.autolase
    for _, name in ipairs({ "maxDistanceNM", "scanSeconds", "laseSeconds", "notificationSeconds" }) do
        assert(cfg and finite(cfg[name]) and cfg[name] > 0, "Invalid CAS AUTOLASE setting: " .. name)
    end
    assert(AUTOLASE and SPOT and SET_GROUP, "MOOSE AUTOLASE/SPOT unavailable.")
    local state = { messages = {}, nextScan = timer.getTime(), requested = false, generation = 0, status = "STANDBY" }
    plan.autolase = state -- Rollback handle before constructing external objects.
    local name = plan.jtac.unit:GetName()
    local groupName = plan.instances.jtac.group:GetName()
    -- INTEL's constructor calls FilterOnce. Constrain that set before New;
    -- passing an unfiltered AddGroup set would also discover other BLUE groups.
    local prefix = "^" .. groupName:gsub("([^%w])", "%%%1") .. "$"
    state.recceSet = SET_GROUP:New():FilterPrefixes(prefix)
    state.engine = AUTOLASE:New(state.recceSet, coalition.side.BLUE, "DT_CAS_" .. plan.assignmentID)
    local engine = state.engine
    assert(clearScheduler(engine.CallScheduler), "Cannot cancel AUTOLASE's default polling.")
    engine.NoMenus, engine.notifypilots, engine.debug, engine.useSRS = true, false, false, false
    engine:SetMaxLasingTargets(1)
    engine:SetLaserCoolDown(false)
    engine:SetLasingParameters(cfg.maxDistanceNM * 1852, cfg.laseSeconds)
    engine:SetLaserCodes({ plan.radio.laserCode })
    engine:SetRecceLaserCode(name, plan.radio.laserCode)
    engine.RecceUnits[name] = { name = name, unit = plan.jtac.unit, cooldown = false }
end

-- A pilot's stop is reversible; mission teardown uses Stop's permanent tombstone.
function CASAutolase.SetRequested(plan, requested, time)
    local state = plan and plan.autolase
    assert(state and owned(plan, state), "CAS designation is no longer available.")
    assert(type(requested) == "boolean" and finite(time), "Invalid designation request.")
    if state.requested == requested then return false end
    state.requested, state.generation = requested, state.generation + 1
    state.messages, state.nextScan = {}, time
    if requested then
        change(plan, state, "REQUESTED")
    elseif releaseSpot(state) then
        state.nextScan = time + Config.cas.autolase.scanSeconds
        change(plan, state, "STANDBY", "CAS JTAC: Laser stopped. Request laser when ready.")
    else
        state.nextScan = time + Config.cas.autolase.scanSeconds
        change(plan, state, "CLEANUP_PENDING", "CAS JTAC: Laser shutdown pending. Retry cleanup in progress.")
    end
    return true
end

function CASAutolase.Stop(plan)
    local state = plan and plan.autolase
    if not state then return true end
    state.stopped, state.requested, state.messages = true, false, {}
    local clean = releaseSpot(state)
    if state.engine then clean = clearScheduler(state.engine.CallScheduler) and clean end
    if state.recceSet then clean = clearScheduler(state.recceSet.CallScheduler) and clean end
    return clean
end

function CASAutolase.Interrupt(plan)
    local state = plan.autolase
    if state and (plan.jtac.lost or (state.target and state.target.lost)) then releaseSpot(state) end
end

local function beginSpot(plan, state, target, time)
    -- Register ownership BEFORE LaseOn: createInfraRed may succeed while
    -- createLaser fails, and MOOSE's FSM catches exceptions internally.
    local spot = SPOT:New(plan.jtac.unit)
    local generation = state.generation
    state.spot, state.target, state.startedAt = spot, target, time
    local function guard()
        if state.spot ~= spot or not owned(plan, state) or not state.requested
            or state.generation ~= generation then return false end
        local canLase, reason = allowed(plan, state, target)
        local now = timer.getTime()
        if now < state.startedAt or now - state.startedAt >= Config.cas.autolase.laseSeconds then
            canLase, reason = false, "TIMEOUT"
        end
        if not canLase then
            releaseSpot(state)
            change(plan, state, reason, "CAS JTAC: Designation paused. Searching for a visible target.")
            return false
        end
        return true
    end
    spot.OnBeforeLaseOn, spot.OnBeforeLasing = guard, guard
    -- Use CAS's conservative life/ID observations, not SPOT's name-only death
    -- handler or its nil-as-dead branch. Every tracking update is guarded above.
    spot.OnEventDead = function() end
    spot:LaseOn(target.unit, state.engine:GetLaserCode(plan.jtac.unit:GetName()))
    assert(spot.Lasing and spot.SpotLaser and spot.SpotIR, "MOOSE SPOT creation incomplete.")
    local point = target.unit:GetVec3()
    env.info(string.format("[DynamicTraining] [DEBUG] CAS AUTOLASE requested spot; assignment=%s; targetID=%s; code=%d; x=%.2f;yMSL=%.2f;z=%.2f; sourceOffsetMeters=2; targetOffsetMeters=1",
        tostring(plan.assignmentID), tostring(target.objectID), plan.radio.laserCode, point.x, point.y + 1, point.z))
    change(plan, state, "LASING:" .. tostring(target.objectID),
        "CAS JTAC: Lasing " .. target.unit:GetTypeName() .. ". LASER " .. plan.radio.laserCode .. ".")
end

local function step(plan, state, time)
    if not state.requested then
        if releaseSpot(state) then
            change(plan, state, "STANDBY", "CAS JTAC: Laser stopped. Request laser when ready.")
        else
            change(plan, state, "CLEANUP_PENDING", "CAS JTAC: Laser shutdown pending. Retry cleanup in progress.")
        end
        return
    end
    if state.spot then
        local canLase, reason = allowed(plan, state, state.target)
        if canLase and time >= state.startedAt and time - state.startedAt < Config.cas.autolase.laseSeconds
            and state.spot.Lasing and state.spot.SpotLaser and state.spot.SpotIR then return end
        if not releaseSpot(state) then
            change(plan, state, "CLEANUP_PENDING", "CAS JTAC: Designation unavailable. Continue using your own sensors and designation.")
            return
        end
        if reason == "OBSERVATION_UNAVAILABLE" then
            change(plan, state, reason, "CAS JTAC: Designation paused. Searching for a visible target.")
        end
    end
    local candidates, unknown = {}, false
    for _, target in ipairs(plan.targets) do
        local canLase, reason = allowed(plan, state, target)
        unknown = unknown or reason == "OBSERVATION_UNAVAILABLE"
        if canLase then
            local ok, threat = pcall(target.unit.GetThreatLevel, target.unit)
            candidates[#candidates + 1] = { target = target, threat = ok and finite(threat) and threat or 0 }
        end
    end
    table.sort(candidates, function(a, b)
        return a.threat > b.threat or (a.threat == b.threat
            and Observations.IDNumber(a.target.objectID) < Observations.IDNumber(b.target.objectID))
    end)
    if candidates[1] then beginSpot(plan, state, candidates[1].target, time)
    else change(plan, state, unknown and "OBSERVATION_UNAVAILABLE" or "WAITING",
        "CAS JTAC: No designated targets available for lasing. Use your own sensors and designation.") end
end

function CASAutolase.Tick(plan, time)
    local state = plan.autolase
    if not state or not owned(plan, state) then return {} end
    if time >= state.nextScan then
        state.nextScan = time + Config.cas.autolase.scanSeconds
        local ok, problem = pcall(step, plan, state, time)
        if not ok then
            releaseSpot(state)
            if state.status ~= "ERROR" then
                env.info("[DynamicTraining] CAS AUTOLASE observation/spot failure: " .. tostring(problem))
            end
            change(plan, state, "ERROR", "CAS JTAC: Designation unavailable. Continue using your own sensors and designation.")
        end
    end
    local messages = state.messages
    state.messages = {}
    return messages
end

return CASAutolase
