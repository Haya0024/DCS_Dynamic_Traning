-- Shared contracts for runtime observations; callers own logging and state.
local Observations = {}
function Observations.Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
function Observations.Vec3(value)
    return type(value) == "table" and Observations.Finite(value.x)
        and Observations.Finite(value.y) and Observations.Finite(value.z)
end
function Observations.HoldStart(since, previous, time)
    assert(Observations.Finite(time), "Observation time unavailable.")
    -- SSE mission time pauses with the simulation. A long gap therefore
    -- means monitoring was skipped, rather than ten/thirty observed seconds.
    if not previous or time < previous or time - previous > Config.pollSeconds * 2 then return time end
    return since or time
end
function Observations.TargetAlive(target, checkLife)
    local alive, id = target.unit:IsAlive(), target.unit:GetID()
    assert(type(alive) == "boolean", "Target life observation unavailable.")
    -- Only an explicitly dead wrapper may have lost its ID. Another ID is
    -- always unknown, even when that replacement object is already dead.
    assert(id == target.objectID or (alive == false and id == nil), "Target identity changed or unavailable.")
    if not alive then return false end
    if checkLife then
        local life = target.unit:GetLife()
        assert(Observations.Finite(life), "Target life value unavailable.")
        return life > 0
    end
    return true
end
return Observations
