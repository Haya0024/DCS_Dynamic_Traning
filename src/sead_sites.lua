-- Owns SAM lifetime independently of wing assignment and objective evaluation.
-- Disposition controls cleanup; ending an assignment does not imply deletion.
local SEADSites = {}

function SEADSites.Register(record)
    local site = { id = record.id, sourceMissionID = record.id, sourceGroupName = record.groupName,
        spawn = record.spawn, plan = record.plan,
        state = "ACTIVE", seadCompleted = false, disposition = "CLEANUP", followOnAvailable = false,
        reservedByAssignmentID = record.assignmentID, cleanupRequested = false, cleaned = false, unitRecords = {} }
    for _, unit in ipairs(record.spawn.units) do site.unitRecords[unit.objectID] = unit end
    Missions.sites[site.id] = site
    return site
end

function SEADSites.LivingTargets(site)
    local targets, byUnit, seen = {}, {}, {}
    for _, target in pairs(site.unitRecords) do byUnit[target.unit] = target end
    local units = site.spawn.group:GetUnits()
    assert(units == nil or type(units) == "table", "SAM site unit list unavailable.")
    local function observe(unit, listed)
        seen[unit] = true
        local target = byUnit[unit]
        -- Explicit loss remains authoritative even when the wrapper returns nil.
        if target and target.lost then return end
        local alive = unit:IsAlive()
        assert(type(alive) == "boolean", "SAM site life observation unavailable.")
        if alive == false then
            if target then target.lost = true end
        else
            assert(listed, "SAM site live target missing from group list.")
            local id = assert(unit:GetID(), "SAM site unit identity unavailable.")
            assert(not target or id == target.objectID, "SAM site target identity changed.")
            target = site.unitRecords[id]
            -- A loss event is authoritative while the wrapper is still updating.
            if not target or not target.lost then
                local side, ground = unit:GetCoalition(), unit:IsGround()
                assert(type(side) == "number" and type(ground) == "boolean", "SAM site category unavailable.")
                if side == coalition.side.RED and ground then
                    if not target then
                        target = { unit = unit, dcsUnit = assert(unit:GetDCSObject()), objectID = id, lost = false }
                        site.unitRecords[id] = target
                    end
                    targets[#targets + 1] = target
                end
            end
        end
    end
    for _, unit in ipairs(units or {}) do observe(unit, true) end
    -- A missing/nil group list alone is not evidence of target destruction.
    for _, target in pairs(site.unitRecords) do
        if not seen[target.unit] and not target.lost then observe(target.unit, false) end
    end
    return targets
end

function SEADSites.CountAliveSiteTargets(site)
    local targets = SEADSites.LivingTargets(site)
    return #targets, targets
end

local function CheckRetention(site)
    if site.disposition == "RETAIN" and Player.ConnectionStatus(site.retainedBy) == false then
        site.disposition, site.followOnAvailable, site.cleanupRequested = "CLEANUP", false, true
        -- Detach only the site. Original SEAD recovery/UCID locks stay intact.
        site.reservedByAssignmentID, site.cleanupReason = nil, "PRESERVER_DISCONNECTED"
        env.info("[DynamicTraining] Preserved SAM site cleanup: keeper disconnected; site=" .. site.id)
    end
end

local function CleanupTimeout()
    local seconds = Config.dead.unreservedSiteCleanupSeconds
    assert(type(seconds) == "number" and seconds > 0 and seconds < math.huge, "Invalid unreserved site cleanup timeout.")
    return seconds
end

local function CheckAvailability(site)
    CheckRetention(site)
    if site.disposition ~= "AVAILABLE" or site.cleanupRequested or site.cleaned then return end
    if site.reservedByAssignmentID then return end
    local time = timer.getTime()
    site.unreservedSince = site.unreservedSince or time
    if time - site.unreservedSince >= CleanupTimeout() then
        site.disposition, site.followOnAvailable, site.cleanupRequested = "CLEANUP", false, true
        site.cleanupReason = "UNRESERVED_TIMEOUT"
        env.info("[DynamicTraining] SAM site cleanup: unreserved timeout; site=" .. site.id)
    end
end

function SEADSites.Refresh(site)
    CheckAvailability(site)
    local ok, remaining, targets = pcall(SEADSites.CountAliveSiteTargets, site)
    if not ok then
        if not site.observationUnavailable then
            env.info("[DynamicTraining] SAM site observation unavailable: " .. site.id .. ": " .. tostring(remaining))
        end
        site.observationUnavailable, site.followOnAvailable = true, false
        site.remainingTargetCount = nil
        return nil
    end
    site.observationUnavailable = nil
    -- Primary result is emitter history. Site destruction depends on live vehicles.
    site.remainingTargetCount = remaining
    site.state = remaining == 0 and "DESTROYED" or site.seadCompleted and "SUPPRESSED" or "ACTIVE"
    site.followOnAvailable = site.seadCompleted and remaining > 0 and site.disposition ~= "IN_USE"
        and not site.cleanupRequested and not site.cleaned
    return targets
end

function SEADSites.PrimaryComplete(site, result)
    site.primaryResult, site.seadCompleted = result, true
    SEADSites.Refresh(site)
end

function SEADSites.Preserve(site, assignmentID, time, keeper)
    local targets = SEADSites.Refresh(site)
    if site.reservedByAssignmentID ~= assignmentID or not site.followOnAvailable or not targets
        or #targets == 0 or site.cleanupRequested or site.cleaned or site.disposition == "AVAILABLE"
        or type(site.sourceGroupName) ~= "string" or site.sourceGroupName == "" then return false end
    site.disposition, site.retainedAt = "RETAIN", site.retainedAt or time
    site.retainedWingName = site.retainedWingName or site.sourceGroupName
    if not site.retainedBy and keeper then
        site.retainedBy = { ucid = keeper.ucid, playerID = keeper.playerID, name = keeper.name }
    end
    return true
end

function SEADSites.CanReleaseReservation(site, groupName)
    if not site or Missions.sites[site.id] ~= site then return false end
    CheckRetention(site)
    return site.disposition == "RETAIN" and site.seadCompleted and not site.cleanupRequested and not site.cleaned
        and type(groupName) == "string" and groupName ~= "" and site.retainedWingName == groupName
end

function SEADSites.ReleaseReservation(site, groupName)
    if not SEADSites.CanReleaseReservation(site, groupName) then return false end
    CleanupTimeout() -- Validate before changing ownership/lifetime.
    site.disposition, site.retainedWingName = "AVAILABLE", nil
    site.releasedAt, site.releasedByWingName = timer.getTime(), groupName
    -- Source SEAD recovery still owns its assignment use lock.
    site.unreservedSince = site.reservedByAssignmentID == nil and timer.getTime() or nil
    SEADSites.Refresh(site)
    return true
end

function SEADSites.Available(site, groupName)
    CheckAvailability(site)
    if (site.disposition ~= "RETAIN" and site.disposition ~= "AVAILABLE")
        or site.reservedByAssignmentID or site.cleanupRequested or site.cleaned then
        return false
    end
    if type(groupName) ~= "string" or groupName == "" then return false end
    if site.disposition == "RETAIN" and site.retainedWingName ~= groupName then return false end
    local targets = SEADSites.Refresh(site)
    return targets ~= nil and #targets > 0 and site.followOnAvailable
end

function SEADSites.Reserve(site, assignmentID, groupName)
    if not SEADSites.Available(site, groupName) then return nil, "SAM site is no longer available for this wing." end
    local previous = { disposition = site.disposition, followOnAvailable = site.followOnAvailable,
        unreservedSince = site.unreservedSince }
    site.reservedByAssignmentID, site.disposition, site.followOnAvailable = assignmentID, "IN_USE", false
    site.unreservedSince = nil
    return previous
end

function SEADSites.Rollback(site, assignmentID, previous)
    if site and previous and site.reservedByAssignmentID == assignmentID then
        site.reservedByAssignmentID, site.disposition, site.followOnAvailable = nil,
            previous.disposition, previous.followOnAvailable
        site.unreservedSince = previous.unreservedSince
    end
end

function SEADSites.RecordLoss(event)
    for _, site in pairs(Missions.sites) do
        local changed = false
        for _, target in pairs(site.unitRecords) do
            if not target.lost and Player.EventMatches(target, event) then target.lost, changed = true, true end
        end
        if changed then SEADSites.Refresh(site) end
    end
end

function SEADSites.Sweep()
    local sites = {}
    for _, site in pairs(Missions.sites) do sites[#sites + 1] = site end
    for _, site in ipairs(sites) do
        CheckAvailability(site)
        if not site.cleanupRequested and site.seadCompleted then
            SEADSites.Refresh(site)
            if (site.disposition == "RETAIN" or site.disposition == "AVAILABLE")
                and not site.reservedByAssignmentID and site.state == "DESTROYED"
                and not site.observationUnavailable then
                site.disposition, site.cleanupRequested = "CLEANUP", true
            end
        end
        if site.cleanupRequested and site.disposition == "CLEANUP" and not site.reservedByAssignmentID
            and not site.cleaning then
            site.cleaning = true -- Destroy can synchronously emit events.
            local ok, result = pcall(function() return site.spawn.group:Destroy(false) end)
            site.cleaning = nil
            if ok and result ~= false then
                site.cleaned = true
                Missions.sites[site.id] = nil
                env.info("[DynamicTraining] SEAD site cleaned: " .. site.id)
            elseif not site.cleanupError then
                site.cleanupError = tostring(result)
                env.error("[DynamicTraining] SEAD site cleanup pending: " .. site.id .. ": " .. tostring(result))
            end
        end
    end
end

function SEADSites.Release(site)
    if not site or site.cleaned or site.disposition ~= "CLEANUP" or site.reservedByAssignmentID then return end
    site.cleanupRequested = true
    SEADSites.Sweep() -- Settlement does not wait for cleanup; failed deletion retries on tick.
end

function SEADSites.CloseAssignment(site, assignmentID)
    if not site or site.reservedByAssignmentID ~= assignmentID then return end
    site.reservedByAssignmentID = nil
    -- The old assignment ends; retainedWingName still reserves the site for
    -- its wing across RTB/rearm until the next DEAD assignment or cleanup.
    local targets = SEADSites.Refresh(site)
    if (site.disposition == "RETAIN" or site.disposition == "AVAILABLE") and site.seadCompleted
        and not site.cleanupRequested and (not targets or #targets > 0) then return end
    -- IN_USE on failure/abort must not leave an orphaned reservation/site.
    site.disposition, site.followOnAvailable = "CLEANUP", false
    SEADSites.Release(site)
end

return SEADSites
