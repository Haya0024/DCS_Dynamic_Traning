local Scoring = { players = {}, settlements = {}, sequence = 0, revision = 0 }
local scoreFields = { Intercept = "interceptScore", SEAD = "seadScore", DEAD = "deadScore" }

function Scoring.NextID(category)
    -- The hook assigns a durably allocated namespace after storage attachment.
    category = category or "Intercept"
    assert(scoreFields[category], "Unsupported scoring category: " .. tostring(category))
    Scoring.sequence = Scoring.sequence + 1
    return (Scoring.sessionID and (Scoring.sessionID .. ":") or "") .. category .. ":" .. tostring(Scoring.sequence)
end

function Scoring.Get(ucid, name)
    if not ucid then return nil end
    local p = Scoring.players[ucid]
    if not p then
        p = { totalScore = 0, careerPoints = 0, interceptScore = 0, seadScore = 0, deadScore = 0,
            missionCount = 0, primarySuccessCount = 0, rtbSuccessCount = 0,
            recoveryFailureCount = 0, failedCount = 0, abortCount = 0, deathCount = 0 }
        Scoring.players[ucid] = p
    end
    p.lastKnownName = name or p.lastKnownName
    return p
end

function Scoring.Settle(mission, result, reason)
    local category = mission.category or "Intercept"
    local scoreField = assert(scoreFields[category], "Unsupported scoring category: " .. tostring(category))
    -- A wing shares the mission ID, but each registered UCID settles once.
    -- Unknown identities have a session-only aircraft key and never a score.
    local key = mission.owner.ucid and ("ucid:" .. mission.owner.ucid)
        or ("aircraft:" .. tostring(mission.owner.objectID))
    local ledger = Scoring.settlements[mission.id] or {}
    local existing = ledger[key]
    if existing then return existing end
    local points = 0
    if result == "RTB_SUCCESS" then
        points = mission.fullReward
    elseif result == "RTB_FAILURE" and mission.primaryCompletedAt then
        points = math.floor(mission.fullReward * Config.recoveryFailurePercent / 100)
    end
    local p = Scoring.Get(mission.owner.ucid, mission.owner.name)
    if p then
        p.totalScore = p.totalScore + points
        p.careerPoints = p.careerPoints + points
        p[scoreField] = p[scoreField] + points
        -- Immediate DEAD is an extra objective in the same wing assignment.
        -- Its separate ledger awards points without counting another mission.
        if not mission.scoreOnly then
            p.missionCount = p.missionCount + 1
            if mission.primaryCompletedAt then p.primarySuccessCount = p.primarySuccessCount + 1 end
            if result == "RTB_SUCCESS" then p.rtbSuccessCount = p.rtbSuccessCount + 1 end
            if result == "RTB_FAILURE" then p.recoveryFailureCount = p.recoveryFailureCount + 1 end
            if result == "FAILED" then p.failedCount = p.failedCount + 1 end
            if result == "ABORT" then p.abortCount = p.abortCount + 1 end
            if mission.failureEvent then p.deathCount = p.deathCount + 1 end
        end
    end
    local receipt = { missionID = mission.id, category = category, ownerUCID = mission.owner.ucid,
        fullReward = mission.fullReward, result = result, reason = reason, scored = p ~= nil,
        points = p and points or 0, total = p and p.totalScore or 0 }
    ledger[key] = receipt
    Scoring.settlements[mission.id] = ledger
    if p then Scoring.revision = Scoring.revision + 1 end
    return receipt
end

return Scoring
