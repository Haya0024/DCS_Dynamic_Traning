local Persistence = { attached = false, confirmed = false, savedRevision = 0, error = nil }
function Persistence.Initialize(payload)
    if not Config.persistence.enabled then return false end
    local data = ScoreData.Decode(payload)
    if Persistence.attached then return Persistence.session == data.session end
    assert(data.session > 0 and data.session == data.counter and data.revision == 0, "Invalid persistence bootstrap")
    -- Current counters are session deltas until attachment. Preserve them even
    -- if the hook first becomes available after a player has already settled.
    for ucid, current in pairs(Scoring.players) do
        local saved = data.players[ucid]
        local merged = { lastKnownName = current.lastKnownName }
        for _, field in ipairs(ScoreData.fields) do
            merged[field] = current[field] + (saved and saved[field] or 0)
        end
        data.players[ucid] = merged
    end
    ScoreData.Validate(data)
    Scoring.players, Scoring.sessionID = data.players, "run" .. string.format("%.0f", data.session)
    Persistence.session, Persistence.counter = data.session, data.counter
    Persistence.attached, Persistence.error = true, nil
    return true
end
function Persistence.ExportSnapshot()
    if not Persistence.attached or Scoring.revision <= Persistence.savedRevision then return "" end
    return ScoreData.Encode({ counter = Persistence.counter, session = Persistence.session,
        revision = Scoring.revision, players = Scoring.players })
end
function Persistence.Acknowledge(session, revision)
    if not Persistence.attached or session ~= Persistence.session or type(revision) ~= "number" or revision < 0
        or revision > Scoring.revision or revision ~= math.floor(revision) then return false end
    Persistence.savedRevision = math.max(Persistence.savedRevision, revision)
    Persistence.confirmed = true
    Persistence.error = nil
    return true
end
function Persistence.SetError(message)
    Persistence.error = message
end
function Persistence.Status()
    if not Config.persistence.enabled then return "Session only; persistence disabled." end
    if Persistence.error then return "Persistence unavailable; scores not confirmed saved." end
    if not Persistence.attached then return "Session only; persistence hook not connected." end
    if not Persistence.confirmed or Scoring.revision > Persistence.savedRevision then return "Persistence pending; not yet saved." end
    return "Persistent scores saved."
end
function Persistence.StartupStatus()
    if Config.persistence.enabled and not Persistence.attached and not Persistence.error then
        return "Persistence initialization pending."
    end
    return Persistence.Status()
end
function Persistence.Publish()
    if not Config.persistence.enabled then return end
    -- Explicit data-only endpoints; no file paths, arbitrary code or filesystem
    -- APIs are exposed in the mission environment.
    DynamicTrainingPersistence = { protocol = 1, Initialize = Persistence.Initialize,
        ExportSnapshot = Persistence.ExportSnapshot, Acknowledge = Persistence.Acknowledge,
        SetError = Persistence.SetError }
end
return Persistence
