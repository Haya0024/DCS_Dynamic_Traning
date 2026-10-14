-- Diagnostic controller; bundled only into the dedicated test mission.
local PlacementCheck = {}
function PlacementCheck.Start(config, sead, zones, clock, log, options)
    local spawnCheck = options and options.spawnCheck == true
    local checks, results = {}, { complete = false, checked = 0, passed = 0, errors = 0,
        spawned = 0, spawnErrors = 0, cleanupErrors = 0, rows = {} }
    local settings = config.sead
    local zoneNames, templates = settings.zones, settings.templates
    for _, name in ipairs(zoneNames) do
        for _, template in ipairs(templates) do
            local row = { zone = name, template = template.name, checked = 0, passed = 0, errors = 0,
                rejections = {}, firstSuccess = nil }
            results.rows[#results.rows + 1] = row
            local ok, job, zone = pcall(function()
                local circle = assert(zones:FindByName(name), "Zone missing: " .. name)
                local center = circle:GetVec2()
                -- This isolated diagnostic config forces the requested pair.
                -- A virtual acceptance position 60 NM away passes normal filtering.
                settings.zones, settings.templates = { name }, { template }
                local plan = sead.Begin(#results.rows, "placement-check:" .. #results.rows,
                    { x = center.x - 60 * 1852, y = 0, z = center.y })
                return plan, circle
            end)
            settings.zones, settings.templates = zoneNames, templates
            if ok then checks[#checks + 1] = { row = row, job = job, zone = zone }
            else
                row.setupError = tostring(job)
                results.errors = results.errors + 1
                log("SETUP_ERROR zone=" .. name .. " template=" .. template.name .. " error=" .. row.setupError)
            end
        end
    end
    log("START areas=" .. #zoneNames .. " templates=" .. #templates .. " samplesPerPair=50; " ..
        (spawnCheck and "one SAM spawn/cleanup per suitable pair; no scoring" or "no SAM spawn or scoring"))
    local pendingCleanup
    local function verifySpawn(check, time)
        local row, spawn = check.row
        if not row.firstPoint then
            row.spawnSkipped = true
            log("SPAWN_SKIPPED zone=" .. row.zone .. " template=" .. row.template .. " reason=no valid placement")
            return
        end
        check.job.plan.actualSpawnPoint = row.firstPoint
        local ok, problem = pcall(function()
            local failure
            spawn, failure = sead.Spawn(check.job)
            assert(spawn, failure or "SAM spawn returned nil")
            assert(#spawn.units == #check.job.offsets and #spawn.primaryUnits == check.job.radarCount,
                "Spawned vehicle/radar count differs from template")
            for i, target in ipairs(spawn.units) do
                assert(target.unit:IsAlive() == true, "Spawned vehicle not active")
                local p, offset = target.unit:GetVec3(), check.job.offsets[i]
                local dx, dy = p.x - row.firstPoint.x - offset.x, p.z - row.firstPoint.y - offset.y
                assert(dx*dx + dy*dy <= 50^2, "Spawned vehicle differs from approved point/layout")
            end
        end)
        if spawn then
            local cleaned, cleanupError = pcall(function()
                assert(spawn.group:Destroy(false) ~= false, "Diagnostic cleanup rejected")
            end)
            if not cleaned then
                check.spawn = spawn -- Retain the failed group for diagnosis; stop further sampling.
                results.cleanupErrors, results.aborted = results.cleanupErrors + 1, true
                log("CLEANUP_ERROR zone=" .. row.zone .. " template=" .. row.template .. " error=" .. tostring(cleanupError))
            else
                check.spawn, check.cleanupRequestedAt, pendingCleanup = spawn, time, check
            end
        end
        if ok then
            row.spawned, results.spawned = true, results.spawned + 1
            log("SPAWN_RESULT zone=" .. row.zone .. " template=" .. row.template .. " success=true units=" ..
                #spawn.units .. " radars=" .. #spawn.primaryUnits)
        else
            row.spawnError, results.spawnErrors = tostring(problem), results.spawnErrors + 1
            log("SPAWN_RESULT zone=" .. row.zone .. " template=" .. row.template .. " success=false error=" .. row.spawnError)
        end
    end
    local index = 1
    local function tick(_, time)
        if pendingCleanup then
            -- DCS/MOOSE objects can remain observable during the removal frame.
            if time < pendingCleanup.cleanupRequestedAt + 3 then return time + 1 end
            local removed, reason = pcall(function()
                for _, target in ipairs(pendingCleanup.spawn.units) do
                    assert(target.unit:IsAlive() ~= true, "Diagnostic vehicle remains active after cleanup")
                end
            end)
            if not removed then
                if time < pendingCleanup.cleanupRequestedAt + 10 then return time + 1 end
                results.cleanupErrors, results.aborted = results.cleanupErrors + 1, true
                log("CLEANUP_ERROR zone=" .. pendingCleanup.row.zone .. " template=" .. pendingCleanup.row.template ..
                    " error=" .. tostring(reason))
                log("ABORTED reason=diagnostic cleanup failure")
                return nil
            end
            log("CLEANUP_RESULT zone=" .. pendingCleanup.row.zone .. " template=" .. pendingCleanup.row.template .. " success=true")
            pendingCleanup.spawn, pendingCleanup = nil, nil
        end
        -- Match normal planning's maximum two candidate checks per second.
        for _ = 1, 2 do
            local check = checks[index]
            if not check then
                results.complete = true
                log(string.format("COMPLETE pairs=%d checked=%d passed=%d errors=%d spawned=%d spawnErrors=%d cleanupErrors=%d", #results.rows,
                    results.checked, results.passed, results.errors, results.spawned, results.spawnErrors, results.cleanupErrors))
                return nil
            end
            local row = check.row
            row.checked, results.checked = row.checked + 1, results.checked + 1
            local point
            local ok, valid, reason = pcall(function()
                point = check.zone:GetRandomVec2()
                return sead.CheckPlacement(check.job, check.zone, point, {})
            end)
            if ok and valid == true then
                row.passed, results.passed = row.passed + 1, results.passed + 1
                row.firstSuccess = row.firstSuccess or row.checked
                row.firstPoint = row.firstPoint or { x = point.x, y = point.y }
                -- Diagnostic-only coordinates support evidence-based relocation.
                log(string.format("VALID_POINT zone=%s template=%s sample=%d x=%.3f y=%.3f",
                    row.zone, row.template, row.checked, point.x, point.y))
            else
                if not ok then
                    row.errors, results.errors = row.errors + 1, results.errors + 1
                    if row.errors == 1 then log("OBSERVATION_ERROR zone=" .. row.zone .. " template=" .. row.template .. " error=" .. tostring(valid)) end
                    reason = "observation error"
                end
                reason = reason or "invalid check result"
                row.rejections[reason] = (row.rejections[reason] or 0) + 1
            end
            if row.checked == 50 then
                local reasons = {}
                for reason, count in pairs(row.rejections) do reasons[#reasons + 1] = reason .. ":" .. count end
                table.sort(reasons)
                log(string.format("RESULT zone=%s template=%s checked=50 passed=%d firstSuccess=%s errors=%d rejected=%s",
                    row.zone, row.template, row.passed, tostring(row.firstSuccess or "NONE"), row.errors, table.concat(reasons, ";")))
                if spawnCheck then verifySpawn(check, time) end
                if results.aborted then log("ABORTED reason=diagnostic cleanup failure"); return nil end
                index = index + 1
                if pendingCleanup then return time + 1 end
            end
        end
        return time + 1
    end
    clock.scheduleFunction(tick, nil, clock.getTime() + 1)
    return results
end
return PlacementCheck
