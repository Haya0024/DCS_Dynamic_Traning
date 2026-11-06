-- Explicit pre-mission teams across native DCS groups. Assignment membership is frozen separately.
local TrainingWings = { wings = {}, members = {}, sequence = 0 }
local function roster(name)
    local people, warning = Player.ForGroup(name)
    assert(people and #people > 0, warning or "Mission team aircraft unavailable.")
    local signature, kind = {}, people[1].unit:GetTypeName()
    for _, owner in ipairs(people) do
        assert(owner.ucid, "Verified UCID required to join a mission team. Check the server hook.")
        assert(owner.unit:GetTypeName() == kind, "Use the same aircraft type within a mission team.")
        signature[#signature + 1] = owner.ucid .. ":" .. owner.objectID .. ":" .. owner.group:GetID()
    end
    table.sort(signature)
    return people, table.concat(signature, "|"), kind
end
local function busy(wing)
    for name in pairs(wing.groups) do if Missions.groupLocks[name] or Missions.wings[name] then return true end end
    return false
end
local function remove(wing)
    for name in pairs(wing.groups) do if TrainingWings.members[name] == wing then TrainingWings.members[name] = nil end end
    TrainingWings.wings[wing.id] = nil
end
function TrainingWings.Create(name)
    assert(not TrainingWings.members[name], "Already in a mission team.")
    local people, signature, kind = roster(name)
    assert(not Missions.Blocker(name, people), "Finish the current assignment before creating a mission team.")
    TrainingWings.sequence = TrainingWings.sequence + 1
    local wing = { id = TrainingWings.sequence, leader = name, kind = kind,
        label = people[1].name, groups = { [name] = signature } }
    TrainingWings.wings[wing.id], TrainingWings.members[name] = wing, wing
    return wing
end
function TrainingWings.Join(name, id)
    local wing = assert(TrainingWings.wings[id], "This mission team is no longer available.")
    assert(not TrainingWings.members[name] and not busy(wing), "Team membership is locked during an assignment.")
    local people, signature, kind = roster(name)
    assert(kind == wing.kind, "Use the same aircraft type within a mission team.")
    assert(not Missions.Blocker(name, people), "Finish the current assignment before joining a mission team.")
    -- Recheck every original aircraft/crew, not just the callback's old menu label.
    local ucids = {}
    for member, expected in pairs(wing.groups) do
        local registered, current = roster(member); assert(current == expected, "Team membership changed. Recreate the team.")
        for _, owner in ipairs(registered) do ucids[owner.ucid] = true end
    end
    for _, owner in ipairs(people) do assert(not ucids[owner.ucid], "The same UCID cannot join a mission team twice.") end
    wing.groups[name], TrainingWings.members[name] = signature, wing
    return wing
end
function TrainingWings.Leave(name, expectedID)
    local wing = assert(TrainingWings.members[name], "Not in a mission team.")
    assert(not expectedID or wing.id == expectedID, "This mission team is no longer current.")
    assert(not busy(wing), "Finish or abort the assignment before leaving the mission team.")
    if wing.leader == name then remove(wing)
    else wing.groups[name], TrainingWings.members[name] = nil, nil end
end
function TrainingWings.Roster(name)
    local wing = TrainingWings.members[name]
    if not wing then return Player.ForGroup(name) end
    assert(wing.leader == name, "Only the mission team leader may accept a mission.")
    local names, result, ucids = { name }, {}, {}
    for member in pairs(wing.groups) do if member ~= name then names[#names + 1] = member end end
    table.sort(names, function(a,b)
        if a == b then return false elseif a == name then return true elseif b == name then return false else return a < b end
    end)
    for _, member in ipairs(names) do
        local people, current = roster(member)
        assert(current == wing.groups[member], "Team aircraft or crew changed. Recreate the team before accepting.")
        for _, owner in ipairs(people) do
            assert(not ucids[owner.ucid], "The same UCID cannot join a mission team twice.")
            ucids[owner.ucid] = true; result[#result + 1] = owner
        end
    end
    return result, nil, wing
end
function TrainingWings.Sweep()
    local stale = {}
    for _, wing in pairs(TrainingWings.wings) do
        if not busy(wing) then
            for name, expected in pairs(wing.groups) do
                local ok, _, signature = pcall(roster, name)
                if not ok or signature ~= expected then stale[#stale + 1] = wing; break end
            end
        end
    end
    for _, wing in ipairs(stale) do remove(wing) end
end
function TrainingWings.List(name)
    local result, wing = {}, TrainingWings.members[name]
    if wing then return result, wing end
    local ok, _, _, kind = pcall(roster, name)
    if not ok then return result end
    for _, candidate in pairs(TrainingWings.wings) do
        if candidate.kind == kind and not busy(candidate) then result[#result + 1] = candidate end
    end
    table.sort(result, function(a,b) return a.id < b.id end)
    return result
end
return TrainingWings
