local Player = {}

function Player.ForUnit(unit, group)
    if not unit or not unit:IsAlive() or not unit:GetPlayerName() or unit:GetPlayerName() == "" then
        return nil, "Human pilot unavailable."
    end
    if unit:GetCoalition() ~= coalition.side.BLUE or unit:GetTypeName() ~= Config.playerType then
        return nil, "A BLUE F/A-18C player aircraft is required."
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
    local template = unit:GetTemplate()
    local slotID = template and template.unitId
    if not slotID or not net or not net.get_player_list or not net.get_player_info then
        return owner, "Server UCID API unavailable; this sortie is unscored."
    end
    local ok, info = pcall(function()
        local matches = {}
        for _, id in ipairs(net.get_player_list() or {}) do
            local p = net.get_player_info(id)
            if p and p.side == coalition.side.BLUE and p.name == owner.name
                and tostring(p.slot) == tostring(slotID) then
                matches[#matches + 1] = p
            end
        end
        if #matches == 1 then return matches[1] end
    end)
    if ok and info and type(info.ucid) == "string" and info.ucid ~= "" then
        owner.ucid = info.ucid
        owner.playerID = info.id
        return owner
    end
    return owner, "UCID could not be verified; this sortie is unscored."
end

function Player.ForGroup(groupName)
    local group = GROUP:FindByName(groupName)
    if not group then return nil, "Player group unavailable." end
    local humans, warnings, ucids = {}, {}, {}
    for _, unit in ipairs(group:GetUnits() or {}) do
        local name = unit:GetPlayerName()
        if unit:IsAlive() and name and name ~= "" then
            local owner, problem = Player.ForUnit(unit, group)
            if not owner then return nil, problem end
            if owner.ucid and ucids[owner.ucid] then
                return nil, "The same UCID cannot occupy two participating aircraft."
            end
            if owner.ucid then ucids[owner.ucid] = true end
            humans[#humans + 1] = owner
            if problem then warnings[#warnings + 1] = owner.name .. ": " .. problem end
        end
    end
    if #humans == 0 then return nil, "At least one human pilot is required." end
    -- GROUP:GetUnits uses pairs internally; explicitly preserve flight order.
    table.sort(humans, function(a, b)
        if a.number ~= b.number then return a.number < b.number end
        return a.unitName < b.unitName
    end)
    return humans, #warnings > 0 and table.concat(warnings, "\n") or nil
end

function Player.SameAircraft(owner)
    return owner.unit:IsAlive() and owner.unit:GetID() == owner.objectID
end

function Player.IsControlling(owner)
    if not Player.SameAircraft(owner) then return false end
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
