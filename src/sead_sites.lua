-- Owns SAM lifetime independently of wing assignment and objective evaluation.
-- A future follow-on can take this site (including plan and spawn references)
-- before Release, without changing recovery/scoring or the emitter FSM.
local SEADSites = {}

function SEADSites.Register(record)
    local site = { id = record.id, spawn = record.spawn, plan = record.plan, cleanupRequested = false }
    Missions.sites[site.id] = site
    return site
end

function SEADSites.Sweep()
    local sites = {}
    for _, site in pairs(Missions.sites) do sites[#sites + 1] = site end
    for _, site in ipairs(sites) do
        if site.cleanupRequested and not site.cleaning then
            site.cleaning = true -- Destroy can synchronously emit events.
            local ok, result = pcall(function() return site.spawn.group:Destroy(false) end)
            site.cleaning = nil
            if ok and result ~= false then
                site.cleaned = true
                Missions.sites[site.id] = nil
                env.info("[DynamicTraining] SEAD site cleaned: " .. site.id)
            elseif not site.cleanupError then
                site.cleanupError = tostring(result)
                env.error("[DynamicTraining] SEAD site cleanup pending: " .. site.id .. ": " .. tostring(result))
            end
        end
    end
end

function SEADSites.Release(site)
    if not site or site.cleaned then return end
    site.cleanupRequested = true
    SEADSites.Sweep() -- Settlement does not wait for cleanup; failed deletion retries on tick.
end

return SEADSites
