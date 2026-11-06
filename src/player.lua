local Player = {}

function Player.Profile(unit)
    return unit and unit:GetCoalition() == coalition.side.BLUE and Config.playerTypes[unit:GetTypeName()] or nil
end

function Player.CanTask(roster, category)
    if not roster or #roster == 0 then return false end
    for _, owner in ipairs(roster) do
        local supported = false
        local profile = Player.Profile(owner.unit)
        for _, task in ipairs(profile and profile.tasks or {}) do
            if task == category then supported = true; break end
        end
        if not supported then return false end
    end
    return true
end

-- DCS multislot.lua identifies crew seats as <ME unitId>_<seat>.
-- Native object IDs are deliberately not used as network slot IDs.
local function aircraftSlot(slot, multicrew)
    local text = tostring(slot)
    if text:match("^%d+$") then return text end
    if multicrew then
        local unitID, seat = text:match("^(%d+)_(%d+)$")
        if unitID and (seat == "1" or seat == "2") then return unitID end
    end
end

-- Host-verified runtime identities for dynamic slots; never infer slots from object IDs.
Player.directory, Player.directoryAt = {}, nil
function Player.UpdateDirectory(rows)
    if type(rows) ~= "table" or #rows > 256 then return false end
    local pending, ids, ucids = {}, {}, {}
    for index, row in pairs(rows) do
        if type(index) ~= "number" or index < 1 or index > #rows or index % 1 ~= 0 or type(row) ~= "table" then return false end
        for _, field in ipairs({ "ucid", "name", "unitName", "groupName", "aircraftType", "slot" }) do
            if type(row[field]) ~= "string" or row[field] == "" or #row[field] > 512 then return false end
        end
        if type(row.playerID) ~= "number" or row.playerID < 1 or row.playerID % 1 ~= 0
            or type(row.objectID) ~= "number" or row.objectID < 1 or row.objectID % 1 ~= 0
            or row.side ~= coalition.side.BLUE or not Config.playerTypes[row.aircraftType]
            or ids[row.playerID] or ucids[row.ucid] then return false end
        if not row.slot:match("^%d+$") and not (Config.playerTypes[row.aircraftType].multicrew
            and row.slot:match("^%d+_[12]$")) then return false end
        ids[row.playerID], ucids[row.ucid] = true, true
        local copy = {}; for k, v in pairs(row) do copy[k] = v end
        pending[#pending + 1] = copy
    end
    if #pending ~= #rows then return false end
    Player.directory, Player.directoryAt = pending, timer.getTime()
    return true
end

local function directoryCrew(unit, group)
    if not Player.directoryAt or timer.getTime() < Player.directoryAt or timer.getTime() - Player.directoryAt > 3 then return end
    local owners, seen = {}, {}
    for _, row in ipairs(Player.directory) do
        if row.unitName == unit:GetName() and row.groupName == group:GetName()
            and row.objectID == unit:GetID() and row.aircraftType == unit:GetTypeName() then
            local ok, current = pcall(function() return net.get_player_info(row.playerID) end)
            if not ok or not current or current.ucid ~= row.ucid or current.side ~= row.side then return end
            local currentSlot = tostring(current.slot)
            local sameSeat = currentSlot == row.slot
            if not sameSeat and Config.playerTypes[row.aircraftType].multicrew then
                local oldAircraft = row.slot:match("^(%d+)_[12]$") or row.slot:match("^(%d+)$")
                local newAircraft = currentSlot:match("^(%d+)_[12]$") or currentSlot:match("^(%d+)$")
                sameSeat = oldAircraft and newAircraft and oldAircraft == newAircraft
            end
            if not sameSeat or seen[currentSlot] then return end
            seen[currentSlot] = true
            owners[#owners + 1] = { unit = unit, dcsUnit = unit:GetDCSObject(), unitName = row.unitName,
                objectID = row.objectID, name = row.name, group = group, groupName = row.groupName,
                number = unit:GetNumber() or math.huge, playerID = row.playerID, seat = currentSlot, ucid = row.ucid }
        end
    end
    if #owners > 0 then return owners end
end

local function templateSlot(unit)
    local ok, template = pcall(function() return unit:GetTemplate() end)
    return ok and template and template.unitId or nil
end

function Player.ForUnit(unit, group)
    if unit and unit:IsAlive() and Player.Profile(unit) then
        local crew = directoryCrew(unit, group)
        if crew and #crew == 1 then return crew[1] end
    end
    if not unit or not unit:IsAlive() or not unit:GetPlayerName() or unit:GetPlayerName() == "" then
        return nil, "Human pilot unavailable."
    end
    local profile = Player.Profile(unit)
    if not profile then
        return nil, "A supported BLUE player aircraft is required."
    end
    local owner = {
        unit = unit, dcsUnit = unit:GetDCSObject(), unitName = unit:GetName(),
        objectID = unit:GetID(), name = unit:GetPlayerName(), group = group,
        groupName = group:GetName(), number = unit:GetNumber() or math.huge, ucid = nil
    }
    if not owner.dcsUnit or not owner.objectID then
        return nil, "Player aircraft identity unavailable."
    end
    -- MOOSE's GetUCID searches by display name. Enumerate the standard DCS
    -- network API instead to also verify coalition and the static client slot.
    -- Template unitId is the network slot; runtime object IDs may change.
    local slotID = templateSlot(unit)
    if not slotID or not net or not net.get_player_list or not net.get_player_info then
        return owner, "Server UCID API unavailable; this sortie is unscored."
    end
    local ok, info = pcall(function()
        local matches = {}
        for _, id in ipairs(net.get_player_list() or {}) do
            local p = net.get_player_info(id)
            if p and p.side == coalition.side.BLUE and p.name == owner.name
                and aircraftSlot(p.slot, profile.multicrew) == tostring(slotID) then
                matches[#matches + 1] = p
            end
        end
        if #matches == 1 then return matches[1] end
    end)
    if ok and info then owner.playerID = info.id end
    if ok and info and type(info.ucid) == "string" and info.ucid ~= "" then
        owner.ucid = info.ucid
        owner.playerID = info.id
        return owner
    end
    return owner, "UCID could not be verified; this sortie is unscored."
end

-- Return every occupied Apache seat, including a CPG with an AI pilot.
-- Crew are people sharing one aircraft; their UCID locks and receipts remain separate.
function Player.ForAircraft(unit, group)
    local profile = Player.Profile(unit)
    if not profile or not profile.multicrew then
        local owner, problem = Player.ForUnit(unit, group)
        return owner and { owner } or {}, problem
    end
    if unit and unit:IsAlive() then
        local verified = directoryCrew(unit, group)
        if verified then return verified end
    end
    local slotID = templateSlot(unit)
    local ok, crew = pcall(function()
        assert(slotID and net and net.get_player_list and net.get_player_info, "Crew API unavailable.")
        local owners, occupied = {}, {}
        local ids = net.get_player_list()
        assert(type(ids) == "table", "Crew list unavailable.")
        local count = 0
        for index, id in pairs(ids) do
            assert(type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #ids
                and type(id) == "number" and id > 0 and id % 1 == 0, "Invalid crew list.")
            count = count + 1
        end
        assert(count == #ids, "Incomplete crew list.")
        for _, id in ipairs(ids) do
            local p = net.get_player_info(id)
            assert(type(p) == "table", "Incomplete crew list.")
            if p.side == coalition.side.BLUE and aircraftSlot(p.slot, true) == tostring(slotID) then
                assert(type(p.name) == "string" and p.name ~= "", "Crew name unavailable.")
                local seat = tostring(p.slot)
                assert(not occupied[seat], "Ambiguous crew seat.")
                occupied[seat] = true
                owners[#owners + 1] = {
                    unit = unit, dcsUnit = unit:GetDCSObject(), unitName = unit:GetName(),
                    objectID = unit:GetID(), name = p.name, group = group, groupName = group:GetName(),
                    number = unit:GetNumber() or math.huge, playerID = p.id or id, seat = seat,
                    ucid = type(p.ucid) == "string" and p.ucid ~= "" and p.ucid or nil
                }
                assert(owners[#owners].dcsUnit and owners[#owners].objectID, "Crew aircraft identity unavailable.")
            end
        end
        return owners
    end)
    if ok then
        local warning
        for _, owner in ipairs(crew) do
            if not owner.ucid then warning = "UCID could not be verified; unverified crew sorties are unscored." end
        end
        return crew, warning
    end
    -- A failed/partial network lookup must never attribute another crew member's UCID.
    local owner = Player.ForUnit(unit, group)
    if owner then owner.ucid = nil end
    return owner and { owner } or {}, "Crew could not be verified; this sortie is unscored."
end

function Player.Groups()
    local groups = {}
    local function add(raw, requireCrew)
        if raw:isExist() then
            -- Dynamic slots have no ME database entry until their native group is registered.
            local nativeGroup = raw.getGroup and raw:getGroup()
            if nativeGroup then GROUP:FindByName(nativeGroup:getName()) end
            local unit = UNIT:FindByName(raw:getName())
            if Player.Profile(unit) then
                local group = unit:GetGroup()
                if not requireCrew or Player.ForGroup(group:GetName()) then groups[group:GetName()] = group end
            end
        end
    end
    for _, raw in ipairs(coalition.getPlayers(coalition.side.BLUE) or {}) do add(raw) end
    -- getPlayers/GetPlayerName may omit aircraft occupied only by a human CPG.
    -- Standard helicopter-group enumeration supplies wrappers; ForGroup verifies occupants.
    if coalition.getGroups then
        for _, group in ipairs(coalition.getGroups(coalition.side.BLUE, 1) or {}) do -- DCS HELICOPTER=1.
            for _, raw in ipairs(group:getUnits() or {}) do add(raw, true) end
        end
    end
    return groups
end

-- MOOSE's player lookup uses names/aircraft. Use network membership instead:
-- spectators and pilots changing slots remain connected. nil means unknown.
function Player.ConnectionStatus(identity)
    if not identity or (not identity.ucid and not identity.playerID) then return nil end
    if not net or not net.get_player_list or not net.get_player_info then return nil end
    local ok, connected = pcall(function()
        local ids = net.get_player_list()
        assert(type(ids) == "table", "Connection list unavailable.")
        local count = 0
        for index, id in pairs(ids) do
            assert(type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #ids
                and type(id) == "number" and id > 0 and id % 1 == 0, "Invalid connection list.")
            count = count + 1
        end
        assert(count == #ids, "Incomplete connection list.")
        local serverID = net.get_server_id and net.get_server_id()
        local complete = true
        for _, id in ipairs(ids) do
            if not identity.ucid and id == identity.playerID then return true end
            if identity.ucid then
                local info = net.get_player_info(id)
                if type(info) == "table" and type(info.ucid) == "string" and info.ucid ~= "" then
                    if info.ucid == identity.ucid then return true end
                elseif id ~= serverID then complete = false end
            end
        end
        if complete then return false end
    end)
    if ok then return connected end -- false is confirmed logout; errors remain nil.
end

function Player.ForGroup(groupName)
    local group = GROUP:FindByName(groupName)
    if not group then return nil, "Player group unavailable." end
    local humans, warnings, ucids = {}, {}, {}
    for _, unit in ipairs(group:GetUnits() or {}) do
        local name = unit:GetPlayerName()
        local profile = Player.Profile(unit)
        if unit:IsAlive() and ((name and name ~= "") or (profile and profile.multicrew)) then
            if not profile then return nil, "A supported BLUE player aircraft is required." end
            local crew, problem = Player.ForAircraft(unit, group)
            for _, owner in ipairs(crew) do
                if owner.ucid and ucids[owner.ucid] then
                    return nil, "The same UCID cannot occupy two participating seats."
                end
                if owner.ucid then ucids[owner.ucid] = true end
                humans[#humans + 1] = owner
            end
            if problem then warnings[#warnings + 1] = unit:GetName() .. ": " .. problem end
        end
    end
    if #humans == 0 then return nil, "At least one human pilot is required." end
    -- GROUP:GetUnits uses pairs internally; explicitly preserve flight order.
    table.sort(humans, function(a, b)
        if a.number ~= b.number then return a.number < b.number end
        if a.unitName ~= b.unitName then return a.unitName < b.unitName end
        return tostring(a.seat or "") < tostring(b.seat or "")
    end)
    return humans, #warnings > 0 and table.concat(warnings, "\n") or nil
end

function Player.SameAircraft(owner)
    return owner.unit:IsAlive() and owner.unit:GetID() == owner.objectID
end

function Player.IsControlling(owner)
    if not Player.SameAircraft(owner) then return false end
    local profile = Player.Profile(owner.unit)
    if profile and profile.multicrew then
        for _, current in ipairs(Player.ForAircraft(owner.unit, owner.group)) do
            if owner.ucid and current.ucid == owner.ucid then return true end
            if not owner.ucid and current.name == owner.name then return true end
        end
        return false
    end
    local current = Player.ForUnit(owner.unit, owner.group)
    if not current or current.objectID ~= owner.objectID then return false end
    if owner.ucid then return current.ucid == owner.ucid end
    -- Names are used only for an explicitly unscored sortie, never an account.
    return current.name == owner.name
end

function Player.EventMatches(record, event)
    local dcsUnit = event.IniDCSUnit or event.initiator
    if not dcsUnit then return false end
    if dcsUnit == record.dcsUnit then return true end
    local ok, id = pcall(function() return dcsUnit:getID() end)
    return ok and id ~= nil and record.objectID ~= nil and id == record.objectID
end

function Player.CanManage(owner, current)
    if not current then return false end
    if owner.ucid then return current.ucid == owner.ucid end
    return current.groupName == owner.groupName and current.name == owner.name
end

return Player
