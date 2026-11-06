-- Native FAC owns radio procedures and lasing; Lua only binds it to our targets.
local JTAC = {}
local finite = Observations.Finite

function JTAC.Slot(code)
    local result
    for _, slot in ipairs(Config.cas.radioSlots) do
        assert(type(slot.laserCode) == "number" and tostring(slot.laserCode):match("^1[1-7][1-8][1-8]$"),
            "Invalid JTAC laser code.")
        assert(finite(slot.frequencyMHz) and slot.frequencyMHz > 0
            and (slot.modulation == 0 or slot.modulation == 1)
            and finite(slot.callname) and slot.callname > 0 and slot.callname % 1 == 0
            and finite(slot.number) and slot.number >= 1 and slot.number <= 9 and slot.number % 1 == 0
            and type(slot.label) == "string" and slot.label ~= "", "Invalid JTAC radio slot.")
        if slot.laserCode == code then assert(not result, "Duplicate JTAC laser code."); result = slot end
    end
    return result
end

function JTAC.Reserve(plan, code)
    local slot = assert(JTAC.Slot(code), "Unknown JTAC laser code.")
    if Missions.jtacSlots[code] then return false end
    -- Also protect the radio identity when configuration entries share a frequency.
    for _, other in pairs(Missions.jtacSlots) do
        if (other.radio.frequencyMHz == slot.frequencyMHz and other.radio.modulation == slot.modulation)
            or (other.radio.callname == slot.callname and other.radio.number == slot.number) then return false end
    end
    plan.radio = UTILS.DeepCopy(slot)
    Missions.jtacSlots[code] = plan
    return true
end

function JTAC.Release(plan)
    if plan.radio and Missions.jtacSlots[plan.radio.laserCode] == plan then
        Missions.jtacSlots[plan.radio.laserCode] = nil
    end
end

function JTAC.Extract(template, enemyID)
    local points = template.route.points
    local tasks = assert(points[1].task and points[1].task.params.tasks, "JTAC waypoint tasks unavailable.")
    local fac, index
    for i, task in ipairs(tasks) do
        if task.id == "FAC_EngageGroup" then
            assert(not fac and task.enabled == true and task.params and task.params.groupId == enemyID
                and task.params.designation == "Laser" and task.params.visible == true
                and finite(task.params.weaponType), "JTAC must have one enabled, visible Laser FAC for its site's enemy.")
            fac, index = UTILS.DeepCopy(task), i
        end
    end
    assert(fac, "JTAC FAC_EngageGroup task missing.")
    local function check(value)
        if type(value) ~= "table" then return end
        if type(value.id) == "string" and value.id:find("^FAC") then
            assert(value == tasks[index], "Additional or nested FAC task is not supported.")
        end
        for _, child in pairs(value) do check(child) end
    end
    check(template)
    local copy = UTILS.DeepCopy(template)
    table.remove(copy.route.points[1].task.params.tasks, index)
    return copy, fac, index
end

function JTAC.Bind(template, fac, index, groupID, radio)
    assert(finite(groupID) and groupID > 0 and groupID % 1 == 0, "Generated enemy group ID unavailable.")
    local copy, task = UTILS.DeepCopy(template), UTILS.DeepCopy(fac)
    -- MOOSE's FAC task builder omits ME's laserCode/visible fields. Preserve the
    -- native task data, replacing only the actual target ID and reserved radio.
    local p = task.params
    p.groupId, p.laserCode = groupID, radio.laserCode
    p.frequency, p.modulation = radio.frequencyMHz * 1000000, radio.modulation
    p.callname, p.number = radio.callname, radio.number
    local tasks = copy.route.points[1].task.params.tasks
    table.insert(tasks, index, task)
    for i, action in ipairs(tasks) do action.number = i end
    return copy
end

function JTAC.Contact(radio)
    return string.format("%s / %.3f MHz %s / LASER %d", radio.label, radio.frequencyMHz,
        radio.modulation == 0 and "AM" or "FM", radio.laserCode)
end
return JTAC
