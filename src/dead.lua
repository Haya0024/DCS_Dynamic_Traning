-- Immediate DEAD and Follow-on DEAD use existing SEAD sites only.
-- SAM creation and lifetime stay in SEAD/SEADSites.
local DEAD = {}

local function Point(site)
    if site.plan.actualSpawnPoint then return site.plan.actualSpawnPoint end
    local point = site.spawn.coordinate:GetVec3()
    return { x = point.x, y = point.z }
end

function DEAD.SelectSite(position, groupName)
    local nearest, minimum
    for _, site in pairs(Missions.sites) do
        if SEADSites.Available(site, groupName) then
            local point = Point(site)
            local distance = (point.x - position.x)^2 + (point.y - position.z)^2
            if not minimum or distance < minimum or (distance == minimum and site.id < nearest.id) then
                nearest, minimum = site, distance
            end
        end
    end
    return nearest
end

function DEAD.Snapshot(site)
    local targets = SEADSites.LivingTargets(site)
    assert(#targets > 0, "No remaining SAM site vehicles.")
    return targets
end

function DEAD.Remaining(record)
    local remaining = 0
    for _, target in ipairs(record.deadTargets) do
        if not target.lost then
            local ok, alive = pcall(function()
                local alive = target.unit:IsAlive()
                assert(type(alive) == "boolean", "DEAD target life observation unavailable.")
                if alive == false then return false end
                local id = assert(target.unit:GetID(), "DEAD target identity unavailable.")
                assert(id == target.objectID, "DEAD target identity changed.")
                return true
            end)
            if not ok then
                if not target.deadObservationUnavailable then
                    env.info("[DynamicTraining] DEAD target observation unavailable; site=" .. record.site.id ..
                        ": " .. tostring(alive))
                end
                target.deadObservationUnavailable = true
            else target.deadObservationUnavailable = nil end
            if ok and alive == false then target.lost = true
            else remaining = remaining + 1 end -- Unknown is never proof of destruction.
        end
    end
    return remaining
end

function DEAD.RecordLoss(record, event)
    local matched = false
    for _, target in ipairs(record.deadTargets) do
        if Player.EventMatches(target, event) then target.lost, matched = true, true end
    end
    if not matched then return false end
    for _, target in ipairs(record.deadTargets) do if not target.lost then return false end end
    return true
end

function DEAD.Briefing(site)
    local location = COORDINATE:NewFromVec2(Point(site)):ToStringLLDDM({ LL_Accuracy = 3 })
    local status = site.primaryResult == "DESTROYED" and "Primary radar destroyed" or "Previously suppressed"
    return "DEAD MISSION\nAREA: " .. site.plan.areaLabel .. "\nTARGET SITE: " .. site.plan.samType ..
        "\nSTATUS: " .. status .. "\nOBJECTIVE: Destroy all remaining SAM site vehicles.\n" ..
        "SITE LOCATION:\n" .. location
end

return DEAD
