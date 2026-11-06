-- Read identity in the host control environment, where dynamic slot properties are authoritative.
local PlayerDirectory = {}
function PlayerDirectory.Collect(control, network)
    assert(control.getUnitProperty and network.get_player_list and network.get_player_info, "Player identity APIs unavailable")
    local rows = {}
    for _, id in ipairs(assert(network.get_player_list())) do
        local p = assert(network.get_player_info(id))
        local slot = tostring(p.slot or "")
        local aircraft = slot:match("^(%d+)$") or slot:match("^(%d+)_[12]$")
        if p.side == 2 and aircraft and type(p.ucid) == "string" and p.ucid ~= "" then
            local unitID = tonumber(aircraft)
            local kind = control.getUnitProperty(unitID, control.UNIT_TYPE)
            if kind == "FA-18C_hornet" or kind == "AH-64D_BLK_II" then
                local name = control.getUnitProperty(unitID, control.UNIT_NAME)
                local group = control.getUnitProperty(unitID, control.UNIT_GROUPNAME)
                local objectID = tonumber(control.getUnitProperty(unitID, control.UNIT_RUNTIME_ID))
                assert(type(name) == "string" and name ~= "" and type(group) == "string" and group ~= ""
                    and objectID and objectID > 0 and objectID % 1 == 0, "Player runtime identity unavailable")
                rows[#rows + 1] = { playerID = id, ucid = p.ucid, name = p.name, slot = slot, side = 2,
                    unitName = name, groupName = group, objectID = objectID, aircraftType = kind }
            end
        end
    end
    return rows
end
return PlayerDirectory
