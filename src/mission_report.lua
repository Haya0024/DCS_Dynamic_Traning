-- Manual F10 reports. Status replays published text, never hidden live state.
local MissionReport = {}

function MissionReport.Idle()
    return "Intercept: Idle.\nSEAD: Idle.\nDEAD: Idle.\nCAP: Idle.\nStrike: Idle."
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

function MissionReport.Remember(record, kind, text, seconds)
    local message = { text = text, seconds = seconds or 10 }
    if kind == "briefing" then
        -- A new coordinate briefing replaces the previous stage and its notice.
        record.publicReport = { briefing = message }
    elseif kind == "complete" then
        -- Completed objectives only need the published result and RTB instructions.
        record.publicReport = { notice = message }
    else
        record.publicReport = record.publicReport or {}
        record.publicReport.notice = message
    end
end

function MissionReport.Status(records)
    if #records == 0 then return MissionReport.Idle(), 10 end
    local texts, displaySeconds = {}, 10
    for _, record in ipairs(records) do
        local published, parts = record.publicReport or {}, {}
        for _, kind in ipairs({ "briefing", "notice" }) do
            local message = published[kind]
            if message then
                parts[#parts + 1] = message.text
                displaySeconds = math.max(displaySeconds, message.seconds)
            end
        end
        texts[#texts + 1] = #parts > 0 and table.concat(parts, "\n\n") or "Mission briefing unavailable."
    end
    return table.concat(texts, "\n\n"), displaySeconds
end

return MissionReport
