local Intercept = { pendingCleanup = {} }
local formationTypes = {
    WEDGE = "Wedge", LINE_ABREAST = "LineAbreast", TRAIL = "Trail",
    ECHELON_LEFT = "EchelonLeft", ECHELON_RIGHT = "EchelonRight"
}

function Intercept.Cleanup(group)
    if not group then return true end
    local pending = Intercept.pendingCleanup[group]
    if not pending then
        local retry = Config.intercept.cleanupRetrySeconds
        assert(type(retry) == "number" and retry > 0 and retry < math.huge, "Invalid Intercept cleanup interval.")
        local ok, name = pcall(function() return group:GetName() end)
        pending = { name = ok and tostring(name) or "UNKNOWN", retrySeconds = retry }
        Intercept.pendingCleanup[group] = pending
    end
    if pending.cleaning then return false end -- Destroy may emit synchronous events.
    pending.cleaning = true
    local ok, problem = pcall(function()
        assert(group:Destroy(false) ~= false, "Destroy returned false.")
        -- Bundled MOOSE returns nil on success. GetDCSObject performs a fresh
        -- lookup; Group:IsAlive only checks the first unit and cannot prove
        -- deletion. The raw DCS existence check confirms any remaining object.
        local object = group:GetDCSObject()
        if object ~= nil then
            assert(object:isExist() == false, "Enemy group disappearance unconfirmed.")
        end
    end)
    pending.cleaning = nil
    if ok then
        Intercept.pendingCleanup[group] = nil
        if pending.reported then
            env.info("[DynamicTraining] Intercept enemy cleaned: " .. pending.name)
        end
    else
        pending.nextAttempt = timer.getTime() + pending.retrySeconds
        if not pending.reported then
            pending.reported = true
            env.error("[DynamicTraining] Intercept enemy cleanup pending: " .. pending.name .. ": " .. tostring(problem))
        end
    end
    return ok
end

function Intercept.Sweep(time)
    -- Snapshot first: Destroy can synchronously trigger callbacks.
    local groups = {}
    for group, pending in pairs(Intercept.pendingCleanup) do
        if not pending.cleaning and time >= pending.nextAttempt then groups[#groups + 1] = group end
    end
    for _, group in ipairs(groups) do
        if Intercept.pendingCleanup[group] then Intercept.Cleanup(group) end
    end
end

function Intercept.Spawn(playerUnit, assignmentID)
    assert(assignmentID, "Intercept assignment identity unavailable.")
    local settings = Config.intercept
    assert(type(settings.cleanupRetrySeconds) == "number" and settings.cleanupRetrySeconds > 0
        and settings.cleanupRetrySeconds < math.huge, "Invalid Intercept cleanup interval.")
    local distance = math.random(settings.minDistanceNM, settings.maxDistanceNM)
    local altitude = math.random(settings.minAltitudeFt, settings.maxAltitudeFt)
    local bearing = (playerUnit:GetHeading()
        + math.random(-settings.maxBearingOffsetDeg, settings.maxBearingOffsetDeg)) % 360
    assert(type(settings.formations) == "table" and #settings.formations > 0, "Intercept formation candidates are empty.")
    local formationName = settings.formations[math.random(1, #settings.formations)]
    local formationType = formationTypes[formationName]
    local fixedWing = ENUMS and ENUMS.Formation and ENUMS.Formation.FixedWing
    local options = fixedWing and formationType and fixedWing[formationType]
    local formation = options and options[settings.formationSpacing]
    assert(type(formation) == "number", "Unsupported Intercept formation or spacing: " ..
        tostring(formationName) .. " / " .. tostring(settings.formationSpacing))
    assert(type(settings.templates) == "table" and #settings.templates > 0, "Intercept template candidates are empty.")
    local template = settings.templates[math.random(1, #settings.templates)]
    assert(type(template) == "string" and template ~= "", "Invalid Intercept template name.")
    local reference = COORDINATE:NewFromVec3(playerUnit:GetVec3())
    local spawn = reference:Translate(distance * 1852, bearing, true)
    spawn:SetAltitude(altitude * 0.3048, true)
    -- A new SPAWN instance starts at #001. Unique aliases prevent concurrent
    -- assignments (and retries) from reusing DCS group/unit names.
    local enemy = SPAWN:NewWithAlias(template, "DT_INTERCEPT_" .. tostring(assignmentID))
        :InitHeading(spawn:HeadingTo(reference))
        :SpawnFromVec3(spawn:GetVec3())
    if not enemy then return nil, "Intercept enemy spawn failed." end
    local ok, result = pcall(function()
        local destination = reference:Translate(settings.throughDistanceNM * 1852, (bearing + 180) % 360, true)
        destination:SetAltitude(altitude * 0.3048, true)
        local engage = enemy:EnRouteTaskEngageTargets(nil, settings.targetTypes, 0)
        -- MOOSE sets the initial controller option. Wrap the standard DCS
        -- option with MOOSE too, so the delayed route explicitly reapplies it.
        local formationTask = enemy:TaskWrappedAction({ id = "Option",
            params = { name = AI.Option.Air.id.FORMATION, value = formation } }, 2)
        -- MOOSE waypoint builders accept km/h. BARO/ASL and the randomized
        -- approach line must be preserved in both waypoints.
        local route = {
            spawn:WaypointAirTurningPoint(COORDINATE.WaypointAltType.BARO, settings.speedMps * 3.6, { engage, formationTask }),
            destination:WaypointAirFlyOverPoint(COORDINATE.WaypointAltType.BARO, settings.speedMps * 3.6)
        }
        enemy:OptionROEOpenFire() -- Fighter task only; excludes BLUE AWACS.
        enemy:SetFormation(formation)
        enemy:Route(route)
        local records, types, counts = AirTargets.Snapshot(enemy), {}, {}
        for _, record in ipairs(records) do
            local unit = record.unit
            -- Derive the briefing from the actual ME composition, not the template name.
            local kind = unit:GetTypeName() or "Unknown"
            if not counts[kind] then types[#types + 1] = kind; counts[kind] = 0 end
            counts[kind] = counts[kind] + 1
        end
        local composition = {}
        for _, kind in ipairs(types) do
            composition[#composition + 1] = string.format("%d x %s", counts[kind], kind)
        end
        return { group = enemy, units = records, distance = distance, altitude = altitude,
            template = template, composition = table.concat(composition, ", "),
            formation = formationName, formationSpacing = settings.formationSpacing }
    end)
    if not ok then
        Intercept.Cleanup(enemy)
        return nil, tostring(result)
    end
    return result
end

function Intercept.RecordLoss(spawn, event)
    return AirTargets.RecordLoss(spawn, event)
end

function Intercept.AllGone(spawn)
    return AirTargets.Remaining(spawn) == 0
end

return Intercept
