-- Manual F10 reports. Runtime selects the group; this module builds the body.
-- Category observers may refresh target/site counts, but no scoring occurs here.
local MissionReport = {}

function MissionReport.Idle()
    return "Intercept: Idle.\nSEAD: Idle.\nDEAD: Idle.\nCAP: Idle."
end

function MissionReport.Statistics(roster)
    local texts = {}
    for _, owner in ipairs(roster) do
        local p = Scoring.Get(owner.ucid, owner.name)
        if p then
            texts[#texts + 1] = string.format(
                "PLAYER STATISTICS: %s [%s]\nTotal Score: %d\nCareer Points: %d\n" ..
                "Settled Missions: %d\nPrimary Success: %d\nRTB Success: %d\nRecovery Failure: %d\nDeath Count: %d",
                owner.name, owner.unitName, p.totalScore, p.careerPoints,
                p.missionCount, p.primarySuccessCount, p.rtbSuccessCount, p.recoveryFailureCount, p.deathCount)
        else texts[#texts + 1] = "PLAYER STATISTICS: " .. owner.name .. "\nUCID unavailable; unscored." end
    end
    return table.concat(texts, "\n\n") .. "\n" .. Persistence.Status(), 25
end

function MissionReport.Status(records, time)
    if #records == 0 then return MissionReport.Idle(), 10 end
    local texts, displaySeconds = {}, 20
    for _, record in ipairs(records) do
        if record.category == "CAP" or record.category == "DEAD" or (record.category == "SEAD" and record.plan.estimatedPoint) then
            displaySeconds = Config.coordinateBriefingSeconds
        end
        local text = (record.category or "Intercept") .. ": " .. record.state .. "\nWing: " .. record.groupName ..
            "\nLead reference: " .. record.owner.name
        if record.state == "DEAD_ACTIVE" then
            text = "SEAD: COMPLETE\nFollow-on: DEAD ACTIVE\nRemaining targets: " .. DEAD.Remaining(record) ..
                "\nWing: " .. record.groupName
        elseif record.category == "DEAD" then
            text = "DEAD: " .. record.state:gsub("_", " ") .. "\nArea: " .. record.plan.areaLabel ..
                "\nRemaining targets: " .. DEAD.Remaining(record) .. "\n" .. DEAD.Briefing(record.site)
        end
        if record.category == "SEAD" then
            text = text .. "\n" .. SEAD.Briefing(record.plan)
            if record.primaryResult then text = text .. "\nSEAD Primary result: " .. record.primaryResult end
            if record.spawn then text = text .. "\n" .. SEADObjective.Status(record.spawn, time) end
            if record.state == "PLANNING" then
                text = text .. "\nSite checks: " .. record.selection.totalAttempts
            end
        end
        if record.category == "CAP" then text = text .. "\n" .. CAP.Status(record.capPlan, record.spawn) end
        if record.site then
            SEADSites.Refresh(record.site)
            text = text .. "\nSite state: " .. record.site.state
            if record.site.seadCompleted then
                text = text .. "\nSite remaining vehicles: " .. (record.site.remainingTargetCount or "UNKNOWN")
            end
            text = text .. "\nSite disposition: " .. record.site.disposition:gsub("_", " ") ..
                "\nFollow-on DEAD available: " .. (record.site.followOnAvailable and "YES" or "NO")
        end
        if record.category == "Intercept" and record.spawnAt then
            text = text .. string.format("\nSpawn in %d seconds.", math.max(0, math.ceil(record.spawnAt - time)))
        end
        for _, p in ipairs(record.participants) do
            text = text .. "\n" .. p.owner.name .. " [" .. p.owner.unitName .. "]: " .. p.state
            if p.receipt then text = text .. " (+" .. p.receipt.points .. ")" end
            if p.deadScoring then
                text = text .. "\nDEAD objective: " .. (p.deadScoring.primaryCompletedAt and "COMPLETE" or "INCOMPLETE")
                if p.deadReceipt then text = text .. " (+" .. p.deadReceipt.points .. ")" end
            end
        end
        texts[#texts + 1] = text
    end
    return table.concat(texts, "\n\n"), displaySeconds
end

return MissionReport
