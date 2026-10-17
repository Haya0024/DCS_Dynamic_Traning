-- Moving ground convoys retain ME routes, including the final loop task.
local AirInterdiction = { sites = {} }
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end

function AirInterdiction.Initialize()
    for _, name in ipairs(Config.airInterdiction.templates) do
        local site = { name = name }
        AirInterdiction.sites[#AirInterdiction.sites + 1] = site
        local ok, problem = pcall(function()
            local group = assert(GROUP:FindByName(name), "Missing convoy template: " .. name)
            local template = assert(group:GetTemplate(), "Missing convoy template data.")
            local points = assert(template.route and template.route.points, "Missing convoy route.")
            assert(#points >= 3, "Convoy needs a loop route.")
            local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
            for _, p in ipairs(points) do
                assert(finite(p.x) and finite(p.y), "Invalid convoy waypoint.")
                minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
                minY, maxY = math.min(minY, p.y), math.max(maxY, p.y)
            end
            site.point = { x = (minX + maxX) / 2, y = (minY + maxY) / 2 }
            assert(template.CoalitionID == coalition.side.RED and template.CategoryID == 2
                and template.lateActivation == true, "Convoy must be RED, ground and late activated.") -- DCS GROUND=2.
            assert(#template.units == 3, "Convoy must contain exactly three vehicles.")
            for _, p in ipairs(points) do
                assert(p.action == "On Road" and finite(p.speed) and p.speed > 0, "Invalid convoy road/speed.")
            end
            local loop = false
            for _, task in ipairs(points[#points].task and points[#points].task.params.tasks or {}) do
                if task.id == "GoToWaypoint" and task.enabled ~= false and task.params
                    and task.params.fromWaypointIndex == #points
                    and (task.params.nWaypointIndx or task.params.goToWaypointIndex) == 1 then loop = true end
            end
            assert(loop, "Convoy route must return from its last waypoint to WP0.")
        end)
        site.valid = ok
        if not ok then env.error("[DynamicTraining] Air Interdiction template " .. name .. ": " .. tostring(problem)) end
    end
end

function AirInterdiction.Plan(position, assignmentID)
    assert(position and finite(position.x) and finite(position.z), "Convoy acceptance position unavailable.")
    local nearest = {}
    for _, site in ipairs(AirInterdiction.sites) do
        if site.point then nearest[#nearest + 1] = { site = site,
            distance = (site.point.x - position.x)^2 + (site.point.y - position.z)^2 } end
    end
    table.sort(nearest, function(a, b)
        if a.distance == b.distance then return a.site.name < b.site.name end
        return a.distance < b.distance
    end)
    local available = {}
    for i = 1, math.min(2, #nearest) do
        local site = nearest[i].site
        if site.valid and not Missions.interdictionSites[site.name] then available[#available + 1] = site end
    end
    if #available == 0 then return nil end
    local site = available[math.random(1, #available)]
    local location = COORDINATE:NewFromVec2(site.point):ToStringLLDDM({ LL_Accuracy = 3 })
    assert(type(location) == "string" and location ~= "", "Convoy coordinate unavailable.")
    local reward = Config.airInterdiction.fullReward
    assert(finite(reward) and reward >= 0 and reward % 1 == 0, "Invalid convoy reward.")
    local plan = { site = site, location = location, assignmentID = assignmentID, fullReward = reward,
        alias = "DT_INTERDICTION_" .. assignmentID, targets = {} }
    Missions.interdictionSites[site.name] = plan
    return plan
end

local function rollbackReference(name)
    local ok, group = pcall(function() return GROUP:FindByName(name) end)
    if ok and group then return group end
    -- A native group can exist before MOOSE registers its wrapper. This
    -- rollback alone uses DCS directly to confirm absence of our unique alias.
    return {
        Destroy = function() local raw = Group.getByName(name); if raw then raw:destroy() end end,
        GetDCSObject = function() return Group.getByName(name) end
    }
end

function AirInterdiction.Spawn(plan)
    assert(Missions.interdictionSites[plan.site.name] == plan and not plan.spawnAttempted, "Invalid convoy reservation.")
    local spawner = SPAWN:NewWithAlias(plan.site.name, plan.alias)
    plan.spawnAttempted = true
    local ok, group = pcall(function() return spawner:Spawn() end)
    if not ok or not group then
        plan.group = rollbackReference(plan.alias .. "#001")
        error("Convoy spawn failed.")
    end
    plan.group = group -- Retain before any post-spawn validation can fail.
    assert(group:GetName() == plan.alias .. "#001", "Unexpected convoy group.")
    local units = assert(group:GetUnits(), "Convoy units unavailable.")
    assert(#units == 3, "Spawned convoy must contain three vehicles.")
    for _, unit in ipairs(units) do
        local object, id = unit:GetDCSObject(), unit:GetID()
        assert(object and id and unit:IsAlive() == true and unit:GetCoalition() == coalition.side.RED
            and unit:IsGround() == true, "Invalid spawned convoy vehicle.")
        plan.targets[#plan.targets + 1] = { unit = unit, dcsUnit = object, objectID = id }
    end
    return { group = group, units = plan.targets }
end

function AirInterdiction.Briefing(plan)
    return "AIR INTERDICTION MISSION\nTARGET AREA: " .. plan.location ..
        "\nOBJECTIVE: Destroy all 3 convoy vehicles; then RTB."
end

function AirInterdiction.Remaining(plan)
    local remaining = 0
    for _, target in ipairs(plan.targets) do
        if not target.lost then
            local ok, alive = pcall(function()
                local alive, id = target.unit:IsAlive(), target.unit:GetID()
                assert(type(alive) == "boolean" and (id == target.objectID or (alive == false and id == nil)),
                    "Convoy observation unavailable or identity changed.")
                if alive == false then return false end
                local life = target.unit:GetLife()
                assert(finite(life), "Convoy life unavailable.")
                return life > 0
            end)
            if ok and alive == false then target.lost = true
            else
                remaining = remaining + 1
                if not ok and not target.observationUnavailable then
                    env.info("[DynamicTraining] Air Interdiction observation unavailable: " .. tostring(target.objectID))
                end
                target.observationUnavailable = not ok or nil
            end
        end
    end
    return remaining
end

function AirInterdiction.RecordLoss(plan, event)
    local matched = false
    for _, target in ipairs(plan.targets) do
        if Player.EventMatches(target, event) then target.lost, matched = true, true end
    end
    if not matched then return false end
    for _, target in ipairs(plan.targets) do if not target.lost then return false end end
    return true
end

function AirInterdiction.Close(plan)
    if not plan or Missions.interdictionSites[plan.site.name] ~= plan then return end
    plan.closing, plan.retryAt = true, timer.getTime()
    AirInterdiction.Sweep(timer.getTime())
end

function AirInterdiction.Sweep(time)
    local closing = {}
    for _, plan in pairs(Missions.interdictionSites) do
        if plan.closing and not plan.cleaning and time >= plan.retryAt then closing[#closing + 1] = plan end
    end
    for _, plan in ipairs(closing) do
        plan.cleaning = true -- Deletion may synchronously emit loss events.
        local ok, problem = pcall(function()
            if plan.group then
                assert(plan.group:Destroy(false) ~= false, "Convoy deletion refused.")
                local raw = plan.group:GetDCSObject()
                assert(raw == nil or raw:isExist() == false, "Convoy deletion unconfirmed.")
            else assert(not plan.spawnAttempted, "Convoy cleanup reference unavailable.") end
        end)
        plan.cleaning = nil
        if ok then Missions.interdictionSites[plan.site.name] = nil
        else
            plan.retryAt = time + Config.airInterdiction.cleanupRetrySeconds
            if not plan.cleanupReported then
                plan.cleanupReported = true
                env.error("[DynamicTraining] Air Interdiction cleanup pending: " .. plan.site.name .. ": " .. tostring(problem))
            end
        end
    end
end
return AirInterdiction
