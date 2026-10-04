-- SEAD emitter FSM. Site lifetime and pilot recovery are separate concerns.
local SEADObjective = {}
local terminal = { SUPPRESSED = true, DESTROYED = true }
local transitions = {
    ACTIVE = { ACTIVE = "ACTIVE", OFF = "SUPPRESSION_PENDING", HELD = "SUPPRESSED", DESTROYED = "DESTROYED" },
    SUPPRESSION_PENDING = { ACTIVE = "ACTIVE", OFF = "SUPPRESSION_PENDING", HELD = "SUPPRESSED", DESTROYED = "DESTROYED" }
}

local function Transition(spawn, observation, time)
    if terminal[spawn.emitterState] then return nil end
    local nextState = assert(transitions[spawn.emitterState][observation], "Invalid SEAD emitter transition.")
    if nextState ~= spawn.emitterState then
        env.info(string.format("[DynamicTraining] SEAD emitter %s -> %s (%s)",
            spawn.emitterState, nextState, spawn.group:GetName()))
        spawn.emitterState, spawn.emitterStateSince = nextState, time
    end
    if terminal[nextState] then
        spawn.primaryResult, spawn.completedAt = nextState, time
        return nextState
    end
end

local function Observe(record, time, hold)
    if record.lost then return "DESTROYED" end
    -- Use MOOSE's first radar return (emitting), not its optional tracking target.
    local ok, alive, life, radarOn = pcall(function()
        local alive = record.unit:IsAlive()
        if alive == false or alive == nil then return false end
        return alive, record.unit:GetLife(), record.unit:GetRadar()
    end)
    if ok and alive == false then
        record.lost, record.offSince = true, nil
        return "DESTROYED"
    end
    local valid = ok and alive == true and type(life) == "number" and life >= 0 and life < math.huge
        and type(radarOn) == "boolean"
    if not valid then
        if not record.observationUnavailable then
            env.info("[DynamicTraining] SEAD emitter observation unavailable; suppression timer reset")
        end
        record.observationUnavailable, record.offSince = true, nil
        return "ACTIVE"
    end
    record.observationUnavailable = nil
    if life >= record.initialLife or radarOn then
        record.offSince = nil
        return "ACTIVE"
    end
    -- Only damaged + observed OFF time counts; more damage does not restart it.
    record.offSince = record.offSince and math.min(record.offSince, time) or time
    return time - record.offSince >= hold and "HELD" or "OFF"
end

function SEADObjective.Update(spawn, time)
    if terminal[spawn.emitterState] then return nil end -- Never query wrappers after completion.
    local allDestroyed, allEligible, allHeld = true, true, true
    for _, record in ipairs(spawn.primaryUnits) do
        local observation = Observe(record, time, spawn.suppressionHoldSeconds)
        if observation ~= "DESTROYED" then
            allDestroyed = false
            if observation == "ACTIVE" then allEligible = false end
            if observation ~= "HELD" then allHeld = false end
        end
    end
    local observation = allDestroyed and "DESTROYED" or allHeld and "HELD" or allEligible and "OFF" or "ACTIVE"
    return Transition(spawn, observation, time)
end

function SEADObjective.RecordLoss(spawn, event)
    if terminal[spawn.emitterState] then return false end
    for _, record in ipairs(spawn.units) do
        if Player.EventMatches(record, event) then record.lost, record.offSince = true, nil end
    end
    -- Death events win immediately only when all primaries are confirmed lost.
    -- Other observations remain in polling, preserving pilot-loss event ordering.
    for _, record in ipairs(spawn.primaryUnits) do if not record.lost then return false end end
    return Transition(spawn, "DESTROYED", event.Time or event.time or timer.getTime()) ~= nil
end

function SEADObjective.Status(spawn, time)
    local text = "Emitter state: " .. spawn.emitterState:gsub("_", " ")
    if spawn.emitterState == "SUPPRESSION_PENDING" then
        for i, record in ipairs(spawn.primaryUnits) do
            if record.offSince then
                text = text .. string.format("\nRadar %d OFF: %g / %g seconds", i,
                    math.max(0, time - record.offSince), spawn.suppressionHoldSeconds)
            end
        end
    end
    return text
end

return SEADObjective
