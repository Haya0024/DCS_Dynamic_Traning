-- PB/TOO facilities: ME geometry, nearest-site selection, objectives and cleanup.
local Strike = { sites = {}, templates = {}, marks = {} }
local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
local function point(p) return type(p) == "table" and finite(p.x) and finite(p.y) end
local function cleanupReference(name)
    local ok, object = pcall(function() return STATIC:FindByName(name, false) end)
    if ok and object then return object end
    -- MOOSE can throw after native creation but before wrapper registration.
    -- Only this rollback path uses DCS directly, so an unregistered object is
    -- still deleted and a missing lookup API never frees a site prematurely.
    return {
        GetDCSObject = function() return StaticObject.getByName(name) end,
        Destroy = function()
            local raw = StaticObject.getByName(name)
            if raw then raw:destroy() end
        end
    }
end
local function remove(object)
    -- STATIC:Destroy returns nil for an already absent object. Verify absence;
    -- never free a site merely because a deletion call did not throw.
    local ok, gone = pcall(function()
        if object:GetDCSObject() == nil then return true end
        assert(object:Destroy(false) ~= false, "Static deletion refused.")
        return object:GetDCSObject() == nil
    end)
    return ok and gone == true
end

function Strike.Initialize()
    -- ME group names are stable; the actual unit names may or may not end in
    -- '-1'. Resolve through MOOSE's registered templates without renaming ME.
    local groups = {}
    for name, registered in pairs(_DATABASE.Templates.Statics) do
        local groupName = registered.StaticName
        if groups[groupName] then groups[groupName] = false
        elseif groups[groupName] == nil then groups[groupName] = name end
    end
    for _, cfg in ipairs(Config.strike.sites) do
        local site = { id = cfg.id, members = {}, originals = {}, valid = true, pbValid = true }
        Strike.sites[#Strike.sites + 1] = site
        for index, member in ipairs(Config.strike.members) do
            local ok, problem = pcall(function()
                local groupName = member.prefix .. "_" .. cfg.id .. "_" .. member.suffix
                local name = assert(groups[groupName], "Missing or duplicate Strike group: " .. groupName)
                local group, side = _DATABASE:GetStaticGroupTemplate(name)
                local unit = assert(group and group.units and group.units[1], "Empty static template: " .. name)
                -- Capture geometry and cleanup references even if another
                -- member is invalid, so a partial set never remains live.
                local original = assert(STATIC:FindByName(name, false), name)
                site.originals[#site.originals + 1] = original
                Strike.templates[original] = site
                if index == 1 and finite(unit.x) and finite(unit.y) then
                    site.point = { x = unit.x, y = unit.y }
                end
                assert(group and side == coalition.side.RED and group.dead ~= true,
                    "Missing, dead or non-RED Strike template: " .. name)
                assert(#group.units == 1 and unit.name == name and finite(unit.x) and finite(unit.y)
                    and finite(unit.heading) and unit.type == member.type, "Invalid Strike static: " .. name)
                local spawner = SPAWNSTATIC:NewFromStatic(name)
                -- Native IDs must be fresh on every sortie; names alone do
                -- not protect delayed death events after a template is reused.
                spawner.TemplateStaticUnit.unitId = nil
                site.members[index] = { spawner = spawner, x = unit.x, y = unit.y, pbOnly = member.pbOnly }
            end)
            if not ok then
                site.pbValid = false
                if not member.pbOnly then site.valid = false end
                env.error("[DynamicTraining] Strike templates " .. cfg.id .. ": " .. tostring(problem))
            end
        end
    end
    Strike.Sweep(timer.getTime())
end

function Strike.Plan(position, assignmentID)
    assert(position and finite(position.x) and finite(position.z), "Strike acceptance position unavailable.")
    local cfg, nearest = Config.strike, {}
    assert(finite(cfg.fullReward) and cfg.fullReward >= 0 and cfg.fullReward % 1 == 0, "Invalid Strike reward.")
    local mode = cfg.modes[math.random(1, #cfg.modes)]
    assert(mode == "TOO" or mode == "PB", "Invalid Strike attack mode.")
    for _, site in ipairs(Strike.sites) do
        if site.point then
            local p = site.point
            nearest[#nearest + 1] = { site = site,
                distance = (p.x - position.x)^2 + (p.y - position.z)^2 }
        end
    end
    table.sort(nearest, function(a, b)
        if a.distance == b.distance then return a.site.id < b.site.id end
        return a.distance < b.distance
    end)
    local available = {}
    for i = 1, math.min(2, #nearest) do
        local site, clean = nearest[i].site, true
        for _, object in ipairs(site.originals) do if Strike.templates[object] then clean = false end end
        if site.valid and (mode ~= "PB" or site.pbValid) and clean and not Missions.strikeSites[site.id] then
            available[#available + 1] = site
        end
    end
    if #available == 0 then return nil end
    local site = available[math.random(1, #available)]
    local kinds = mode == "PB" and cfg.pbTargets or cfg.targets
    local kind = kinds[math.random(1, #kinds)]
    local selected = {}
    for _, index in ipairs(kind.members) do selected[index] = true end
    local requiredCount = kind.requiredCount or #kind.members
    assert(finite(requiredCount) and requiredCount % 1 == 0 and requiredCount > 0
        and requiredCount <= #kind.members, "Invalid Strike target count.")
    local aimPoint = site.point
    if mode == "PB" then
        assert(#kind.members == 1 and requiredCount == 1, "PB requires one target.")
        local member = assert(site.members[kind.members[1]], "PB target template unavailable.")
        aimPoint = { x = member.x, y = member.y }
    end
    local coordinate = COORDINATE:NewFromVec2(aimPoint)
    local location, elevation
    if mode == "PB" then
        local height = coordinate:GetLandHeight()
        assert(finite(height), "PB target elevation unavailable.")
        elevation = math.floor(height / 0.3048 + 0.5)
        location = coordinate:ToStringLLDMS({ LL_Accuracy = 2 })
    else location = coordinate:ToStringLLDDM({ LL_Accuracy = 3 }) end
    assert(type(location) == "string" and location ~= "", "Strike briefing unavailable.")
    if mode == "PB" then location = location .. string.format(", %d ft MSL", elevation) end
    local plan = { site = site, attackMode = mode, target = { kind = kind, selected = selected }, point = aimPoint,
        location = location, elevationFt = elevation,
        assignmentID = assignmentID,
        objects = {}, targets = {}, requiredCount = requiredCount, fullReward = cfg.fullReward }
    assert(not Missions.strikeSites[site.id], "Strike site already reserved.")
    Missions.strikeSites[site.id] = plan
    return plan
end

function Strike.Spawn(plan)
    assert(Missions.strikeSites[plan.site.id] == plan and not plan.spawnAttempted, "Invalid Strike reservation.")
    plan.spawnAttempted = true
    for i, template in ipairs(plan.site.members) do
        if plan.attackMode == "PB" or not template.pbOnly then
            local name = "DT_STRIKE_" .. plan.assignmentID .. "_" .. i
            template.spawner.TemplateStaticUnit.unitId = nil
            local ok, object = pcall(function() return template.spawner:Spawn(nil, name) end)
            if not ok or not object then
                -- A MOOSE post-spawn failure can leave the native static alive.
                -- Recover it by its unique name before rolling the assignment back.
                object = cleanupReference(name)
                plan.objects[#plan.objects + 1] = object
                error("Strike static spawn failed: " .. name)
            end
            -- Retain the native result even if validation of its identity fails.
            if object then plan.objects[#plan.objects + 1] = object end
            assert(object and object:IsAlive() == true, "Strike static spawn failed.")
            local id = assert(object:GetID(), "Strike static identity unavailable.")
            assert(object:GetName() == name and object:GetCoalition() == coalition.side.RED, "Unexpected Strike object.")
            local p = object:GetVec2()
            assert(point(p) and math.abs(p.x - template.x) < 0.1 and math.abs(p.y - template.y) < 0.1,
                "Strike static moved from its ME position.")
            if plan.target.selected[i] then
                plan.targets[#plan.targets + 1] = { unit = object, objectID = id, unitName = name, member = i }
            end
        end
    end
    return { units = plan.targets }
end

function Strike.Briefing(plan)
    return string.format("STRIKE MISSION (%s)\nTARGET AREA: %s\nOBJECTIVE: %s; then RTB.",
        plan.attackMode, plan.location, plan.target.kind.objective)
end

local function stopMark(mark, time)
    local ok, result = pcall(function() return mark.coordinate:StopSmoke(mark.name) end)
    if ok and result ~= false then Strike.marks[mark] = nil
    else mark.retryAt = time + Config.strike.cleanupRetrySeconds end
end

function Strike.StopMark(plan)
    local mark = plan and plan.smoke
    if mark and Strike.marks[mark] then
        mark.stopping = true
        stopMark(mark, timer.getTime())
    end
end

function Strike.Mark(plan, time)
    assert(plan and not plan.closing and Missions.strikeSites[plan.site.id] == plan,
        "Strike smoke reservation unavailable.")
    if plan.smoke and Strike.marks[plan.smoke] then return false end
    local cfg = Config.strike.smoke
    local color = SMOKECOLOR[cfg.color]
    assert(type(color) == "number" and finite(cfg.northOffsetMeters) and cfg.northOffsetMeters >= 0
        and finite(cfg.durationSeconds) and cfg.durationSeconds > 0 and cfg.durationSeconds <= 300,
        "Invalid Strike smoke settings.")
    local coordinate = COORDINATE:NewFromVec2({ x = plan.point.x + cfg.northOffsetMeters, y = plan.point.y })
    plan.smokeSequence = (plan.smokeSequence or 0) + 1
    local mark = { coordinate = coordinate, name = "DT_STRIKE_MARK_" .. plan.assignmentID .. "_" .. plan.smokeSequence,
        expiresAt = time + cfg.durationSeconds, retryAt = time }
    -- Retain the name before calling MOOSE: a native effect can exist even if
    -- its wrapper throws after emission. Lifetime is independent of the site.
    plan.smoke, Strike.marks[mark] = mark, true
    local ok, result = pcall(function()
        -- Zero direction/distance also prevent global MOOSE smoke offsets.
        return coordinate:Smoke(color, nil, nil, mark.name, false, 0, 0)
    end)
    if not ok or result == false then
        mark.stopping = true
        stopMark(mark, time)
        error("Strike smoke emission failed.")
    end
    return true
end

function Strike.Remaining(plan)
    local remaining = 0
    for _, target in ipairs(plan.targets) do
        if not target.lost then
            local ok, alive = pcall(function()
                local alive = target.unit:IsAlive()
                assert(type(alive) == "boolean", "Strike observation unavailable.")
                if alive == false then return false end
                assert(target.unit:GetID() == target.objectID, "Strike object identity changed.")
                local life = target.unit:GetLife()
                assert(finite(life), "Strike life observation unavailable.")
                return life > 0
            end)
            if ok and alive == false then target.lost = true
            else
                remaining = remaining + 1
                if not ok and not target.observationUnavailable then
                    env.info("[DynamicTraining] Strike observation unavailable: " .. target.unitName)
                end
                target.observationUnavailable = not ok or nil
            end
        end
    end
    -- Every member of the selected class is eligible, but storage needs only
    -- two confirmed losses out of four. Unknown observations stay remaining.
    return math.max(0, plan.requiredCount - (#plan.targets - remaining))
end

function Strike.RecordLoss(plan, event)
    -- MOOSE exposes statics as IniDCSStatic; aircraft use IniDCSUnit. Keep
    -- matching local to the facility and require the captured identity.
    local raw = event.IniDCSStatic or event.IniDCSUnit or event.initiator
    if not raw then return false end
    local ok, id, name = pcall(function() return raw:getID(), raw:getName() end)
    if not ok then return false end
    local matched = false
    for _, target in ipairs(plan.targets) do
        if id == target.objectID and name == target.unitName then target.lost, matched = true, true end
    end
    if not matched then return false end
    local destroyed = 0
    for _, target in ipairs(plan.targets) do if target.lost then destroyed = destroyed + 1 end end
    return destroyed >= plan.requiredCount
end

function Strike.Close(plan)
    Strike.StopMark(plan)
    if not plan or Missions.strikeSites[plan.site.id] ~= plan then return end
    plan.closing, plan.retryAt = true, timer.getTime()
    Strike.Sweep(timer.getTime())
end

function Strike.Sweep(time)
    for mark in pairs(Strike.marks) do
        if (mark.stopping or time >= mark.expiresAt) and time >= mark.retryAt then stopMark(mark, time) end
    end
    for object in pairs(Strike.templates) do if remove(object) then Strike.templates[object] = nil end end
    for id, plan in pairs(Missions.strikeSites) do
        if plan.closing and time >= plan.retryAt then
            local pending = {}
            for _, object in ipairs(plan.objects) do if not remove(object) then pending[#pending + 1] = object end end
            plan.objects = pending
            if #pending == 0 then Missions.strikeSites[id] = nil
            else plan.retryAt = time + Config.strike.cleanupRetrySeconds end
        end
    end
end

return Strike
