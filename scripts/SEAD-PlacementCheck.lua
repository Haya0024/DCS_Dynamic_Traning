-- Diagnostic controller; bundled only into the dedicated test mission.
local PlacementCheck = {}
function PlacementCheck.Start(config, sead, zones, clock, log)
    local checks, results = {}, { complete = false, checked = 0, passed = 0, errors = 0, rows = {} }
    local settings = config.sead
    local zoneNames, templates = settings.zones, settings.templates
    for _, name in ipairs(zoneNames) do
        for _, template in ipairs(templates) do
            local row = { zone = name, template = template.name, checked = 0, passed = 0, errors = 0,
                rejections = {}, firstSuccess = nil }
            results.rows[#results.rows + 1] = row
            local ok, job, zone = pcall(function()
                local circle = assert(zones.Find(name), "Zone missing: " .. name)
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
    log("START areas=" .. #zoneNames .. " templates=" .. #templates .. " samplesPerPair=50; no SAM spawn or scoring")
    local index = 1
    local function tick(_, time)
        -- Match normal planning's maximum two candidate checks per second.
        for _ = 1, 2 do
            local check = checks[index]
            if not check then
                results.complete = true
                log(string.format("COMPLETE pairs=%d checked=%d passed=%d errors=%d", #results.rows,
                    results.checked, results.passed, results.errors))
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
                index = index + 1
            end
        end
        return time + 1
    end
    clock.scheduleFunction(tick, nil, clock.getTime() + 1)
    return results
end
return PlacementCheck
