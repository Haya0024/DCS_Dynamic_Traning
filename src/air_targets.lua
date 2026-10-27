-- Shared tracking of the aircraft actually spawned for Intercept and CAP.
-- Explicit loss events are authoritative; unknown observations remain pending.
local AirTargets = {}

function AirTargets.Snapshot(group)
    local targets = {}
    for _, unit in ipairs(group:GetUnits() or {}) do
        local object, id = unit:GetDCSObject(), unit:GetID()
        assert(object and id, "Air target identity unavailable.")
        targets[#targets + 1] = { unit = unit, dcsUnit = object, objectID = id, lost = false }
    end
    assert(#targets > 0, "Spawned air targets unavailable.")
    return targets
end

function AirTargets.RecordLoss(spawn, event)
    if not spawn then return false end
    for _, target in ipairs(spawn.units) do
        if Player.EventMatches(target, event) then target.lost = true end
    end
    for _, target in ipairs(spawn.units) do if not target.lost then return false end end
    return true
end

function AirTargets.Remaining(spawn)
    if not spawn then return nil end
    local remaining = 0
    for _, target in ipairs(spawn.units) do
        if not target.lost then
            local ok, alive = pcall(Observations.TargetAlive, target, false)
            if not ok or alive ~= false then remaining = remaining + 1 end
        end
    end
    return remaining
end

return AirTargets
