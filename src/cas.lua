-- A CAS site owns three ME groups; geometry is never re-randomized.
local CAS = { sites = {} }
local finite = Observations.Finite
local roles = { "enemy", "friendly", "jtac" }
local counts = { enemy = 3, friendly = 3, jtac = 1 }

local function templateFor(name, side, count, site)
    local group = assert(GROUP:FindByName(name), "Missing CAS template: " .. name)
    local data = assert(group:GetTemplate(), "CAS template data unavailable.")
    local first = data.units and data.units[1]
    if site and first and finite(first.x) and finite(first.y) then site.point = { x = first.x, y = first.y } end
    assert(data.CoalitionID == side and data.CategoryID == 2 and data.lateActivation == true,
        "CAS template must be a late-activated ground group on the correct side.")
    assert(#data.units == count, "Unexpected CAS vehicle count.")
    local points = assert(data.route and data.route.points, "CAS route unavailable.")
    assert(#points == 1 and points[1].speed == 0 and finite(points[1].x) and finite(points[1].y),
        "CAS template must have a single stationary waypoint.")
    local hold, disperse = false, false
    for _, task in ipairs(points[1].task and points[1].task.params.tasks or {}) do
        local action = task.params and task.params.action
        if action and action.id == "Option" and task.enabled ~= false then
            -- ME serializes unchecked Disperse as name=8 with a nil value.
            if action.params.name == 0 then hold = action.params.value == 4 end
            if action.params.name == 8 then disperse = action.params.value == nil or action.params.value == 0 end
        end
    end
    assert(hold and disperse, "CAS needs Weapon Hold and Disperse under fire OFF.")
    for _, unit in ipairs(data.units) do
        assert(type(unit.type) == "string" and unit.type ~= "" and finite(unit.x) and finite(unit.y),
            "CAS vehicle type or position unavailable.")
    end
    return UTILS.DeepCopy(data)
end

function CAS.Initialize()
    local names, ids = {}, {}
    for _, cfg in ipairs(Config.cas.sites) do
        local site = { id = cfg.id, config = cfg, templates = {} }
        CAS.sites[#CAS.sites + 1] = site
        local ok, problem = pcall(function()
            assert(type(cfg.id) == "string" and cfg.id ~= "" and not ids[cfg.id], "Duplicate or missing CAS site ID.")
            ids[cfg.id] = true
            for _, role in ipairs(roles) do
                local name = cfg[role]
                assert(type(name) == "string" and not names[name], "Duplicate or missing CAS template name.")
                names[name] = true
                site.templates[role] = templateFor(name, role == "enemy" and coalition.side.RED or coalition.side.BLUE,
                    counts[role], role == "enemy" and site or nil)
            end
            assert(type(cfg.friendlyDescription) == "string" and cfg.friendlyDescription ~= ""
                and type(cfg.enemyDescription) == "string" and cfg.enemyDescription ~= "", "CAS identification text missing.")
            site.jtacTemplate, site.fac, site.facIndex = JTAC.Extract(site.templates.jtac, site.templates.enemy.groupId)
            local function rejectFAC(value)
                if type(value) ~= "table" then return end
                assert(type(value.id) ~= "string" or not value.id:find("^FAC"), "FAC task in a non-JTAC template.")
                for _, child in pairs(value) do rejectFAC(child) end
            end
            rejectFAC(site.templates.enemy); rejectFAC(site.templates.friendly)
        end)
        site.valid = ok
        if not ok then env.error("[DynamicTraining] CAS site " .. tostring(cfg.id) .. ": " .. tostring(problem)) end
    end
end

local function coordinate(point)
    local c = COORDINATE:NewFromVec2(point)
    local text
    if Config.cas.coordinateFormat == "MGRS" then
        text = c:ToStringMGRS({ MGRS_Accuracy = Config.cas.mgrsAccuracy })
    else text = c:ToStringLLDDM({ LL_Accuracy = 3 }) end
    assert(type(text) == "string" and text ~= "", "CAS coordinate unavailable.")
    return text
end

function CAS.Plan(position, assignmentID, code)
    assert(Observations.Vec3(position), "CAS acceptance position unavailable.")
    local cfg, nearest = Config.cas, {}
    for _, site in ipairs(CAS.sites) do
        if site.point then
            local distance = (site.point.x - position.x)^2 + (site.point.y - position.z)^2
            if distance >= (cfg.minDistanceNM * 1852)^2 and distance <= (cfg.maxDistanceNM * 1852)^2 then
                nearest[#nearest + 1] = { site = site, distance = distance }
            end
        end
    end
    table.sort(nearest, function(a, b)
        return a.distance < b.distance or (a.distance == b.distance and a.site.id < b.site.id)
    end)
    local available = {}
    for i = 1, math.min(2, #nearest) do
        local site = nearest[i].site
        if site.valid and not Missions.casSites[site.id] then available[#available + 1] = site end
    end
    if #available == 0 then return nil, "SITE" end
    assert(finite(cfg.fullReward) and cfg.fullReward >= 0 and cfg.fullReward % 1 == 0, "Invalid CAS reward.")
    local site = available[math.random(1, #available)]
    local plan = { site = site, assignmentID = assignmentID, fullReward = cfg.fullReward,
        targets = {}, friendlies = {}, instances = {}, unitIDs = {}, targetLocation = coordinate(site.point),
        friendlyLocation = coordinate(site.templates.friendly.units[1]) }
    for _, role in ipairs(roles) do
        plan.instances[role] = { alias = "DT_CAS_" .. assignmentID .. "_" .. role:upper() }
    end
    if not JTAC.Reserve(plan, code) then return nil, "RADIO" end
    -- Return the rollback handle before starting any external creation.
    Missions.casSites[site.id] = plan
    return plan
end

local function spawnRole(plan, role, template)
    local instance = plan.instances[role]
    instance.attempted, instance.template = true, template
    local ok, group = pcall(function()
        return SPAWN:NewFromTemplate(template, plan.site.config[role], instance.alias):Spawn()
    end)
    instance.group = ok and group or nil
    if not instance.group then
        instance.group = ObjectLifecycle.GroupReference(instance.alias .. "#001")
        error("CAS " .. role .. " spawn failed: " .. tostring(group))
    end
    assert(group:GetName() == instance.alias .. "#001", "Unexpected CAS group alias.")
end

local function validateRole(plan, role)
    local instance = plan.instances[role]
    local ok, units = pcall(function() return instance.group:GetUnits() end)
    if not ok or type(units) ~= "table" then return nil, "unit list unavailable" end
    assert(#units <= counts[role], "Too many generated CAS vehicles: " .. role)
    if #units < counts[role] then return nil, "unit count=" .. #units .. "/" .. counts[role] end
    local expected, targets, ids = {}, {}, {}
    for _, u in ipairs(instance.template.units) do expected[u.type] = (expected[u.type] or 0) + 1 end
    for _, unit in ipairs(units) do
        local readable, values = pcall(function()
            return { id = unit:GetID(), raw = unit:GetDCSObject(), alive = unit:IsAlive(),
                ground = unit:IsGround(), side = unit:GetCoalition(), kind = unit:GetTypeName() }
        end)
        if not readable then return nil, "unit observation unavailable: " .. tostring(values) end
        local v = values
        local id = Observations.IDNumber(v.id)
        local detail = string.format("role=%s id=%s idType=%s raw=%s alive=%s ground=%s side=%s type=%s", role,
            tostring(v.id), type(v.id), tostring(v.raw ~= nil and v.raw ~= false),
            tostring(v.alive), tostring(v.ground), tostring(v.side), tostring(v.kind))
        -- DCS may return wrappers before the spawned units become active. Keep
        -- the complete rollback handle and wait on the mission timer, bounded.
        if not id or not v.raw or v.alive ~= true
            or v.ground == nil or v.side == nil or v.kind == nil then return nil, detail end
        assert(not plan.unitIDs[id] and not ids[id] and v.ground == true
            and v.side == instance.template.CoalitionID and (expected[v.kind] or 0) > 0,
            "Invalid generated CAS vehicle: " .. detail)
        -- GROUP:GetUnits uses pairs; validate the composition, not array order.
        expected[v.kind] = expected[v.kind] - 1
        ids[id] = true
        targets[#targets + 1] = { unit = unit, objectID = v.id, dcsUnit = v.raw }
    end
    if role == "enemy" then
        local readable, id = pcall(function() return instance.group:GetID() end)
        local number = readable and Observations.IDNumber(id)
        if not number then return nil, "enemy Group ID unavailable: id=" .. tostring(id) .. " idType=" .. type(id) end
        assert(number ~= plan.site.templates.enemy.groupId, "CAS enemy still has the source template's Group ID.")
        plan.enemyGroupID = number
    end
    for id in pairs(ids) do plan.unitIDs[id] = true end
    return targets
end

function CAS.Step(plan, time)
    assert(Missions.casSites[plan.site.id] == plan and plan.spawnAttempted and not plan.closing,
        "Invalid CAS preparation.")
    assert(time >= plan.setupStartedAt and time - plan.setupStartedAt <= Config.cas.setupTimeoutSeconds,
        "CAS activation timed out: " .. tostring(plan.waitReason))
    for _, role in ipairs(roles) do
        local instance = plan.instances[role]
        if not instance.attempted then
            local template = role == "jtac" and JTAC.Bind(plan.site.jtacTemplate, plan.site.fac,
                plan.site.facIndex, plan.enemyGroupID, plan.radio) or UTILS.DeepCopy(plan.site.templates[role])
            spawnRole(plan, role, template)
        end
        if not instance.targets then
            local targets, reason = validateRole(plan, role)
            if not targets then
                plan.waitReason = role .. ": " .. reason
                if instance.waitReason ~= reason then
                    env.info("[DynamicTraining] CAS awaiting activation: " .. plan.waitReason)
                    instance.waitReason = reason
                end
                return nil
            end
            instance.targets = targets
            if role == "enemy" then plan.targets = targets
            elseif role == "friendly" then plan.friendlies = targets
            else plan.jtac = targets[1] end
        end
    end
    for _, role in ipairs(roles) do
        for _, target in ipairs(plan.instances[role].targets) do
            assert(Observations.TargetAlive(target, true) == true, "CAS vehicle lost during preparation: " .. role)
        end
    end
    for _, target in ipairs(plan.targets) do
        assert(plan.jtac.unit:IsLOS(target.unit) == true, "CAS JTAC terrain line of sight unavailable or blocked.")
    end
    return { group = plan.instances.enemy.group, units = plan.targets }
end

function CAS.Spawn(plan)
    assert(Missions.casSites[plan.site.id] == plan and not plan.spawnAttempted, "Invalid CAS reservation.")
    plan.spawnAttempted, plan.setupStartedAt = true, timer.getTime()
    return CAS.Step(plan, plan.setupStartedAt)
end

function CAS.Briefing(plan)
    return "CAS MISSION\nFRIENDLY LOCATION: " .. plan.friendlyLocation .. "\nTARGET AREA: " .. plan.targetLocation ..
        "\nFRIENDLIES: " .. plan.site.config.friendlyDescription .. "\nTARGETS: " .. plan.site.config.enemyDescription ..
        "\nJTAC: " .. JTAC.Contact(plan.radio) .. "\nOBJECTIVE: Destroy all 3 designated enemy vehicles; then RTB."
end

local function observe(target)
    if target.lost then return false end
    local ok, alive = pcall(Observations.TargetAlive, target, true)
    if ok and alive == false then target.lost = true; return false end
    if not ok and not target.observationUnavailable then
        env.info("[DynamicTraining] CAS observation unavailable: " .. tostring(target.objectID))
    end
    target.observationUnavailable = not ok or nil
    return true
end

function CAS.Remaining(plan)
    local remaining = 0
    for _, target in ipairs(plan.targets) do if observe(target) then remaining = remaining + 1 end end
    return remaining
end

function CAS.SupportMessages(plan)
    local messages = {}
    local function report(target, message)
        if target and not observe(target) and not target.notified then
            target.notified = true; messages[#messages + 1] = message
        end
    end
    report(plan.jtac, "CAS JTAC lost. Continue the mission using your own sensors and designation.")
    for _, target in ipairs(plan.friendlies) do report(target, "CAS friendly vehicle lost. Confirm target identification before firing.") end
    return messages
end

function CAS.RecordLoss(plan, event)
    if plan.closing or plan.cleaning then return false end
    local matched = false
    for _, target in ipairs(plan.targets) do
        if Player.EventMatches(target, event) then target.lost, matched = true, true end
    end
    for _, target in ipairs(plan.friendlies) do if Player.EventMatches(target, event) then target.lost = true end end
    if plan.jtac and Player.EventMatches(plan.jtac, event) then plan.jtac.lost = true end
    if not matched then return false end
    for _, target in ipairs(plan.targets) do if not target.lost then return false end end
    return true
end

function CAS.Close(plan)
    if not plan or Missions.casSites[plan.site.id] ~= plan then return end
    plan.closing, plan.retryAt = true, timer.getTime()
    CAS.Sweep(timer.getTime())
end

function CAS.Sweep(time)
    local closing = {}
    for _, plan in pairs(Missions.casSites) do
        if plan.closing and not plan.cleaning and time >= plan.retryAt then closing[#closing + 1] = plan end
    end
    for _, plan in ipairs(closing) do
        plan.cleaning = true
        local allRemoved, problem = true, nil
        -- Stop the designator first; attempt every group even if one removal fails.
        for _, role in ipairs({ "jtac", "friendly", "enemy" }) do
            local instance = plan.instances[role]
            if instance.attempted and not instance.removed then
                local ok, reason = ObjectLifecycle.Remove(instance.group)
                if ok then instance.removed = true else allRemoved, problem = false, reason end
            end
        end
        plan.cleaning = nil
        if allRemoved then
            Missions.casSites[plan.site.id] = nil
            JTAC.Release(plan)
        else
            plan.retryAt = time + Config.cas.cleanupRetrySeconds
            if not plan.cleanupReported then
                plan.cleanupReported = true
                env.error("[DynamicTraining] CAS cleanup pending: " .. plan.site.id .. ": " .. tostring(problem))
            end
        end
    end
end
return CAS
