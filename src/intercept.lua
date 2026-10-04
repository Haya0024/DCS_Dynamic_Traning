local Intercept = {}
local formationTypes = {
    WEDGE = "Wedge", LINE_ABREAST = "LineAbreast", TRAIL = "Trail",
    ECHELON_LEFT = "EchelonLeft", ECHELON_RIGHT = "EchelonRight"
}

function Intercept.Spawn(playerUnit, assignmentID)
    assert(assignmentID, "Intercept assignment identity unavailable.")
    local settings = Config.intercept
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
        local records, types, counts = {}, {}, {}
        for _, unit in ipairs(enemy:GetUnits() or {}) do
            assert(unit:GetDCSObject() and unit:GetID(), "Enemy identity unavailable.")
            records[#records + 1] = { unit = unit, dcsUnit = unit:GetDCSObject(),
                objectID = unit:GetID(), lost = false }
            -- Derive the briefing from the actual ME composition, not the template name.
            local kind = unit:GetTypeName() or "Unknown"
            if not counts[kind] then types[#types + 1] = kind; counts[kind] = 0 end
            counts[kind] = counts[kind] + 1
        end
        assert(#records > 0, "Spawned enemy units could not be tracked.")
        local composition = {}
        for _, kind in ipairs(types) do
            composition[#composition + 1] = string.format("%d x %s", counts[kind], kind)
        end
        return { group = enemy, units = records, distance = distance, altitude = altitude,
            template = template, composition = table.concat(composition, ", "),
            formation = formationName, formationSpacing = settings.formationSpacing }
    end)
    if not ok then
        pcall(function() enemy:Destroy(false) end)
        return nil, tostring(result)
    end
    return result
end

function Intercept.RecordLoss(spawn, event)
    for _, unit in ipairs(spawn.units) do
        if Player.EventMatches(unit, event) then unit.lost = true end
    end
    for _, unit in ipairs(spawn.units) do
        if not unit.lost then return false end
    end
    return true
end

function Intercept.AllGone(spawn)
    for _, record in ipairs(spawn.units) do
        if not record.lost and record.unit:IsAlive() then return false end
    end
    return true
end

return Intercept
