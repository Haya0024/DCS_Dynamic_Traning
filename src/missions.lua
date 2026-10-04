-- Shared assignment state. Every mission category must acquire this blocker
-- before reserving or spawning; locks survive individual participant settlement.
local Missions = { wings = {}, pilots = {}, sites = {}, sequence = 0 }

function Missions.Blocker(groupName, roster)
    local record = Missions.wings[groupName]
    if not record then
        for _, owner in ipairs(roster or {}) do
            if owner.ucid and Missions.pilots[owner.ucid] then
                record = Missions.pilots[owner.ucid]
                break
            end
        end
    end
    if record then
        local category = record.category or "Intercept"
        local pending = record.state == "ARMED" or record.state == "TAKEOFF_DELAY" or record.state == "PLANNING"
        return pending and (category .. " mission is already armed. Wing assignment blocked.")
            or (category .. " mission is already active (including return to base). Wing assignment blocked.")
    end
end

function Missions.IsActive(record)
    return record and Missions.wings[record.groupName] == record
end

function Missions.Snapshot()
    -- Callbacks can release assignments while iterating: use a stable copy.
    local records = {}
    for _, record in pairs(Missions.wings) do records[#records + 1] = record end
    table.sort(records, function(a, b) return a.assignmentID < b.assignmentID end)
    return records
end

function Missions.ForGroup(groupName, roster)
    local records, found = {}, {}
    local function add(record)
        if Missions.IsActive(record) and not found[record] then
            found[record] = true
            records[#records + 1] = record
        end
    end
    -- Own wing first; pilots can also manage their earlier sortie after moving.
    add(Missions.wings[groupName])
    for _, owner in ipairs(roster or {}) do
        if owner.ucid then add(Missions.pilots[owner.ucid]) end
    end
    return records
end

function Missions.Acquire(record)
    local roster = {}
    for _, participant in ipairs(record.participants) do roster[#roster + 1] = participant.owner end
    local problem = Missions.Blocker(record.groupName, roster)
    if problem then return false, problem end
    Missions.sequence = Missions.sequence + 1
    record.assignmentID = Missions.sequence
    Missions.wings[record.groupName] = record
    for _, owner in ipairs(roster) do
        if owner.ucid then Missions.pilots[owner.ucid] = record end
    end
    return true
end

function Missions.Release(record)
    if not Missions.IsActive(record) then return false end
    Missions.wings[record.groupName] = nil
    for _, participant in ipairs(record.participants) do
        local ucid = participant.owner.ucid
        if ucid and Missions.pilots[ucid] == record then Missions.pilots[ucid] = nil end
    end
    return true
end

return Missions
