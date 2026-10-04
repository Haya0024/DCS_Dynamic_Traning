local SEAD = {}

local function Log(text)
    env.info("[DynamicTraining] SEAD " .. text)
end

function SEAD.Begin(assignmentID, missionID, playerPosition)
    assert(assignmentID, "SEAD assignment identity unavailable.")
    local settings = Config.sead
    assert(type(settings.templates) == "table" and #settings.templates > 0, "SEAD templates are empty.")
    assert(type(settings.zones) == "table" and #settings.zones > 0, "SEAD zones are empty.")
    assert(missionID and playerPosition and playerPosition.x and playerPosition.z,
        "SEAD mission identity/acceptance position unavailable.")
    assert(type(settings.modes) == "table" and #settings.modes == 2
        and settings.modes[1] ~= settings.modes[2], "SEAD requires TOO and PB modes.")
    for _, mode in ipairs(settings.modes) do assert(mode == "TOO" or mode == "PB", "Invalid SEAD mode.") end
    assert(settings.minDistanceNM >= 0 and settings.maxDistanceNM >= settings.minDistanceNM,
        "Invalid SEAD zone distance limits.")
    assert(settings.pbEstimateErrorMinNM > 0 and settings.pbEstimateErrorMaxNM >= settings.pbEstimateErrorMinNM,
        "Invalid SEAD PB estimate error limits.")
    assert(settings.tooEstimateErrorMinNM > 0 and settings.tooEstimateErrorMaxNM >= settings.tooEstimateErrorMinNM,
        "Invalid SEAD TOO estimate error limits.")
    assert(type(settings.fullReward) == "number" and settings.fullReward >= 0 and settings.fullReward % 1 == 0,
        "Invalid SEAD full reward.")
    assert(type(settings.suppressionHoldSeconds) == "number" and settings.suppressionHoldSeconds > 0
        and settings.suppressionHoldSeconds < math.huge, "Invalid SEAD suppression hold time.")
    assert(settings.flatRadiusMeters > 0 and settings.sampleStepMeters > 0
        and settings.sampleStepMeters <= settings.flatRadiusMeters, "Invalid SEAD terrain sampling radius/step.")
    assert(settings.perimeterSamples >= 4 and settings.perimeterSamples % 1 == 0,
        "Invalid SEAD perimeter sample count.")
    assert(settings.attemptsPerZone >= 1 and settings.attemptsPerZone % 1 == 0
        and settings.attemptsPerTick >= 1 and settings.attemptsPerTick % 1 == 0, "Invalid SEAD retry limits.")
    assert(settings.maxHeightDifferenceMeters >= 0 and settings.buildingClearanceMeters > 0
        and settings.objectSearchPaddingMeters >= 0 and settings.unknownObjectRadiusMeters >= 0,
        "Invalid SEAD terrain/clearance limits.")
    local selected = settings.templates[math.random(1, #settings.templates)]
    local name = selected.name
    assert(type(selected.type) == "string" and type(selected.primaryUnitType) == "string"
        and type(selected.pbCode) == "number" and selected.pbCode >= 100 and selected.pbCode <= 999
        and selected.pbCode % 1 == 0, "Invalid SEAD template metadata.")
    local group = assert(GROUP:FindByName(name), "SEAD template not found: " .. tostring(name))
    local template = assert(group:GetTemplate(), "SEAD template data unavailable: " .. name)
    local origin = template.route and template.route.points and template.route.points[1]
    assert(origin and origin.x and origin.y and template.units and #template.units > 0,
        "SEAD template route/units unavailable: " .. name)
    local offsets, radius, radarCount = {}, settings.flatRadiusMeters, 0
    -- SpawnFromVec2 translates relative to route.points[1], not units[1].
    -- Keep the ME layout/heading and validate every vehicle in that layout.
    for _, unit in ipairs(template.units) do
        local offset = { x = unit.x - origin.x, y = unit.y - origin.y }
        offsets[#offsets + 1] = offset
        radius = math.max(radius, math.sqrt(offset.x ^ 2 + offset.y ^ 2))
        if unit.type == selected.primaryUnitType then radarCount = radarCount + 1 end
    end
    assert(radarCount > 0, "SEAD template has no configured primary radar: " .. name)
    local zones, seen = {}, {}
    for _, zone in ipairs(settings.zones) do
        assert(type(zone) == "string" and zone ~= "" and not seen[zone], "Invalid/duplicate SEAD zone.")
        seen[zone] = true
        local object = ZONE:FindByName(zone)
        if object then
            local center = assert(object:GetVec2(), "SEAD zone center unavailable: " .. zone)
            local dx, dy = center.x - playerPosition.x, center.y - playerPosition.z
            local distance = math.sqrt(dx * dx + dy * dy) / 1852
            if distance >= settings.minDistanceNM and distance <= settings.maxDistanceNM then
                zones[#zones + 1] = zone
            end
        else Log("zone missing; skipped " .. zone) end
    end
    assert(#zones > 0, "No SEAD zones within acceptance distance limits.")
    local mode = settings.modes[math.random(1, #settings.modes)]
    local zoneName = zones[math.random(1, #zones)]
    local plan = { missionType = "SEAD", id = missionID, attackMode = mode, template = name,
        samType = selected.type, pbCode = selected.pbCode, primaryUnitType = selected.primaryUnitType,
        zoneName = zoneName, areaLabel = (settings.zoneLabels or {})[zoneName] or zoneName,
        acceptancePosition = { x = playerPosition.x, y = playerPosition.z } }
    return { plan = plan, template = name, attempts = 0, totalAttempts = 0, rejections = {},
        offsets = offsets, radius = radius, radarCount = radarCount, settings = settings,
        spawner = SPAWN:NewWithAlias(name, "DT_SEAD_" .. tostring(assignmentID)) }
end

local function TerrainClear(job, zone, point)
    local settings, low, high = job.settings
    local function sample(x, y)
        local p = { x = x, y = y }
        if not zone:IsVec2InZone(p) then return false, "zone boundary" end
        local coordinate = COORDINATE:NewFromVec2(p)
        if not coordinate:IsSurfaceTypeLand() then return false, "non-LAND" end
        local height = coordinate:GetLandHeight()
        low, high = math.min(low or height, height), math.max(high or height, height)
        if high - low > settings.maxHeightDifferenceMeters then
            -- Range observed before early rejection, not the full site's range.
            job.maxRejectedHeightRangeMeters = math.max(job.maxRejectedHeightRangeMeters or 0, high - low)
            return false, "uneven terrain"
        end
        return true
    end
    local ok, reason = sample(point.x, point.y)
    if not ok then return false, reason end
    -- Interior grid plus perimeter catches slopes, interior bumps and shores.
    local step, radius = settings.sampleStepMeters, job.radius
    local extent = math.floor(radius / step)
    for ix = -extent, extent do
        for iy = -extent, extent do
            local x, y = ix * step, iy * step
            if x * x + y * y <= radius * radius then
                ok, reason = sample(point.x + x, point.y + y)
                if not ok then return false, reason end
            end
        end
    end
    for i = 1, settings.perimeterSamples do
        local angle = 2 * math.pi * i / settings.perimeterSamples
        ok, reason = sample(point.x + radius * math.cos(angle), point.y + radius * math.sin(angle))
        if not ok then return false, reason end
    end
    for _, offset in ipairs(job.offsets) do
        ok, reason = sample(point.x + offset.x, point.y + offset.y)
        if not ok then return false, reason end
    end
    return true
end

local function ObjectsClear(job, point)
    local settings = job.settings
    local searchRadius = job.radius + settings.buildingClearanceMeters + settings.objectSearchPaddingMeters
    local coordinate = COORDINATE:NewFromVec2({ x = point.x - searchRadius, y = point.y - searchRadius })
    -- ScanObjectsSquare uses a southwest corner and a cube. Center its vertical
    -- range on the candidate terrain, so differing corner elevation is irrelevant.
    coordinate:SetAltitude(COORDINATE:NewFromVec2(point):GetLandHeight(), true)
    local _, _, _, units, statics, scenery = coordinate:ScanObjectsSquare(searchRadius * 2, true, true, true)
    assert(type(units) == "table" and type(statics) == "table" and type(scenery) == "table",
        "SEAD object scan did not return valid lists.")
    local objects = {}
    for _, list in ipairs({ units, statics, scenery }) do
        for _, object in ipairs(list or {}) do objects[#objects + 1] = object end
    end
    for _, object in ipairs(objects) do
        -- MOOSE returns raw DCS objects from ScanObjectsSquare. Standard object
        -- bounds are needed to measure clearance from the structure, not its origin.
        local location = object:getPoint()
        local description = object.getDesc and object:getDesc()
        local box = description and description.box
        local objectRadius = settings.unknownObjectRadiusMeters
        if box and box.min and box.max then
            local x = math.max(math.abs(box.min.x), math.abs(box.max.x))
            local y = math.max(math.abs(box.min.z), math.abs(box.max.z))
            objectRadius = math.sqrt(x * x + y * y)
        end
        for _, offset in ipairs(job.offsets) do
            local dx, dy = point.x + offset.x - location.x, point.y + offset.y - location.z
            if dx * dx + dy * dy < (settings.buildingClearanceMeters + objectRadius) ^ 2 then
                return false, "near scenery/static/unit"
            end
        end
    end
    return true
end

function SEAD.Spawn(job)
    local plan = job.plan
    local point = assert(plan.actualSpawnPoint, "SEAD plan has no approved site.")
    local zone = assert(ZONE:FindByName(plan.zoneName), "Planned SEAD zone unavailable.")
    -- Conditions may change while awaiting departure. Recheck this exact site;
    -- an occupied/unsafe site fails rather than changing the accepted mission.
    local valid, reason = TerrainClear(job, zone, point)
    if valid then valid, reason = ObjectsClear(job, point) end
    if not valid then return nil, "Planned SEAD site no longer safe: " .. tostring(reason) end
    -- Omit airborne heights: DCS places each ground vehicle on local terrain.
    local enemy = job.spawner:SpawnFromVec2(point)
    if not enemy then return nil, "SEAD SpawnFromVec2 returned nil." end
    local ok, result = pcall(function()
        enemy:OptionAlarmStateRed()
        enemy:OptionROEOpenFire()
        enemy:RouteStop() -- Stationary training site; retain ME formation and weapons.
        local records, radars = {}, {}
        for _, unit in ipairs(enemy:GetUnits() or {}) do
            assert(unit:GetDCSObject() and unit:GetID(), "SEAD enemy identity unavailable.")
            local record = { unit = unit, dcsUnit = unit:GetDCSObject(), objectID = unit:GetID(), lost = false }
            records[#records + 1] = record
            if unit:GetTypeName() == plan.primaryUnitType then
                -- Snapshot actual life at mission start, not factory GetLife0.
                local life = unit:GetLife()
                assert(type(life) == "number" and life > 0 and life < math.huge,
                    "Initial SEAD emitter life unavailable.")
                record.initialLife = life
                radars[#radars + 1] = record
            end
        end
        assert(#records == #job.offsets, "SEAD spawned unit count differs from template.")
        assert(#radars > 0 and #radars == job.radarCount, "SEAD primary radars could not be tracked.")
        return { group = enemy, units = records, primaryUnits = radars, template = plan.template, zone = plan.zoneName,
            threatLabel = plan.samType, areaLabel = plan.areaLabel,
            coordinate = COORDINATE:NewFromVec2(point), attempts = job.totalAttempts,
            suppressionHoldSeconds = job.settings.suppressionHoldSeconds, emitterState = "ACTIVE" }
    end)
    if not ok then pcall(function() enemy:Destroy(false) end); return nil, tostring(result) end
    return result
end

function SEAD.Step(job, reservations)
    assert(not job.plan.actualSpawnPoint, "SEAD mission plan is already complete.")
    local zoneName = job.plan.zoneName
    local zone = assert(ZONE:FindByName(zoneName), "Planned SEAD zone unavailable: " .. zoneName)
    for _ = 1, job.settings.attemptsPerTick do
        job.attempts, job.totalAttempts = job.attempts + 1, job.totalAttempts + 1
        local point = zone:GetRandomVec2()
        local valid, reason = false, "no coordinate"
        if point then
            valid, reason = TerrainClear(job, zone, point)
            if valid then valid, reason = ObjectsClear(job, point) end
            if valid then
                -- Keep unspawned wing plans apart, too. Actual objects are
                -- still checked above and again when this plan is spawned.
                for _, other in ipairs(reservations or {}) do
                    local dx, dy = point.x - other.point.x, point.y - other.point.y
                    local clearance = job.radius + other.radius + job.settings.buildingClearanceMeters
                    if dx * dx + dy * dy < clearance * clearance then
                        valid, reason = false, "another reserved SEAD site"; break
                    end
                end
            end
        end
        if valid then
            job.plan.actualSpawnPoint = { x = point.x, y = point.y }
            local settings = job.settings
            local minimum = job.plan.attackMode == "PB" and settings.pbEstimateErrorMinNM or settings.tooEstimateErrorMinNM
            local maximum = job.plan.attackMode == "PB" and settings.pbEstimateErrorMaxNM or settings.tooEstimateErrorMaxNM
            local fraction = math.random(0, 1000000) / 1000000
            local distance = (minimum + fraction * (maximum - minimum)) * 1852
            local heading = math.rad(math.random(0, 359))
            job.plan.estimatedPoint = { x = point.x + distance * math.cos(heading),
                y = point.y + distance * math.sin(heading) }
            Log(string.format("planned %s in %s after %d attempts", job.template, zoneName, job.totalAttempts))
            return job.plan, "DONE"
        end
        job.rejections[reason] = (job.rejections[reason] or 0) + 1
        if job.attempts >= job.settings.attemptsPerZone then
            return nil, "FAILED", string.format("No suitable position in %s after %d attempts; last rejection=%s\n%s",
                zoneName, job.attempts, reason, SEAD.FailureSummary(job))
        end
    end
    return nil, "PENDING"
end

function SEAD.FailureSummary(job)
    -- Only area and rejection counts: even TOO failures must not reveal the
    -- selected SAM type, actual/estimated coordinates or the PB target code.
    local labels = {
        { "uneven terrain", string.format("Uneven terrain (height range > %g m)", job.settings.maxHeightDifferenceMeters) },
        { "non-LAND", "Not LAND" },
        { "zone boundary", "Outside area" },
        { "near scenery/static/unit", "Near obstacles" },
        { "another reserved SEAD site", "Near another reserved site" },
        { "no coordinate", "No location returned" }
    }
    local text = string.format("Area: %s\nNo safe site in %d attempts.", job.plan.areaLabel, job.totalAttempts)
    for _, entry in ipairs(labels) do
        local count = job.rejections[entry[1]] or 0
        if count > 0 then text = text .. string.format("\n%s: %d", entry[2], count) end
    end
    if job.maxRejectedHeightRangeMeters then
        text = text .. string.format("\nLargest height range sampled before rejection: %.1f m.",
            job.maxRejectedHeightRangeMeters)
    end
    return text
end

function SEAD.Briefing(plan)
    local location = plan.estimatedPoint and COORDINATE:NewFromVec2(plan.estimatedPoint):ToStringLLDMS()
        or "Planning in progress"
    local text = "SEAD MISSION\nMODE: " .. plan.attackMode
    if plan.attackMode == "TOO" then
        return text .. "\nTHREAT AREA: " .. location .. "\nTARGET TYPE: UNKNOWN\nINSTRUCTIONS:\n" ..
            "Search near the reported area and engage the hostile radar emitter using HARM TOO mode."
    end
    text = text .. "\nTHREAT AREA: " .. plan.areaLabel
    return text .. "\nTHREAT: " .. plan.samType .. "\nESTIMATED LOCATION: " .. location ..
        string.format("\nHARM PB CODE: %03d\nINSTRUCTIONS:\nEngage the emitter using HARM PB mode, then RTB.", plan.pbCode)
end

-- Objective transitions live in a dedicated module, independent of placement.
SEAD.UpdateObjective = SEADObjective.Update
SEAD.RecordLoss = SEADObjective.RecordLoss

return SEAD
