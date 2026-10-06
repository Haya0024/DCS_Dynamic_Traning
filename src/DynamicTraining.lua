-- Runtime entry. Build-Mission.ps1 prepends the local gameplay modules.
local function GlobalMessage(text, seconds)
    env.info("[DynamicTraining] MESSAGE [ALL]\n" .. text)
    trigger.action.outText(text, seconds)
end
if DynamicTrainingRuntime then
    GlobalMessage("Dynamic Training is already loaded.", 10)
    return
end
if not BASE or not SPAWN or not MENU_GROUP then
    GlobalMessage("ERROR: Load MOOSE before DynamicTraining.", 15)
    return
end
DynamicTrainingRuntime = { version = "SEAD-DEAD-follow-on-trial-7" }
Persistence.Publish()

local menus = {}
local nextPlayerScan = 0
local ScanPlayers

local function Message(group, text, seconds)
    if group then pcall(function()
        env.info("[DynamicTraining] MESSAGE [" .. group:GetName() .. "]\n" .. text)
        MESSAGE:New(text, seconds or 10):ToGroup(group)
    end) end
end

local function Log(text)
    env.info("[DynamicTraining] " .. text)
end

local function DebugLog(record, text)
    local id = record.id or (record.category .. " assignment " .. record.assignmentID)
    Log("[DEBUG] " .. id .. "\n" .. text)
end

local function Safe(label, group, callback)
    local ok, result = pcall(callback)
    if not ok then
        env.error("[DynamicTraining] " .. label .. ": " .. tostring(result))
        Message(group, "ERROR: " .. label .. ". See DCS log.", 15)
    end
    return ok, result
end

local function HasPending(record)
    for _, p in ipairs(record.participants) do if not p.done then return true end end
    return false
end

local function CanRecover(record)
    return record.state == "RTB_PENDING" or
        (record.category == "SEAD" and record.state == "DEAD_ACTIVE" and record.primaryCompletedAt ~= nil)
end

local function Close(record)
    -- Release before cleanup: generated destroy events cannot award a win.
    if not Missions.Release(record) then return end
    if record.site then
        SEADSites.CloseAssignment(record.site, record.assignmentID)
    elseif record.spawn then
        Safe("Enemy cleanup", record.group, function() record.spawn.group:Destroy(false) end)
    end
    Log((record.id or ((record.category or "Intercept") .. " reservation")) .. " closed; wing assignment released")
end

local function SelectLeader(record)
    for _, p in ipairs(record.participants) do
        if not p.done and Player.SameAircraft(p.owner) then
            record.owner = p.owner
            return p.owner
        end
    end
end

local function SettleParticipant(record, p, result, reason, time)
    if p.done then return end
    local receipt
    if p.id then receipt = Scoring.Settle(p, result, reason) end
    if p.deadScoring then
        local dead = p.deadScoring
        local completed = dead.primaryCompletedAt and (time or timer.getTime()) >= dead.primaryCompletedAt
        local deadResult = result
        if result ~= "ABORT" and not completed then
            deadResult = "FAILED"
            dead.primaryCompletedAt = nil
        end
        p.deadReceipt = Scoring.Settle(dead, deadResult, reason)
    end
    p.done, p.state, p.receipt, p.landing = true, result, receipt, nil
    local text = string.format("%s %s: %s\n%s", record.category or "Intercept", result, p.owner.name, reason)
    if receipt then
        if receipt.scored then
            local points, total = receipt.points, receipt.total
            if p.deadReceipt then
                points, total = points + p.deadReceipt.points, p.deadReceipt.total
                text = text .. string.format("\nSEAD Points: +%d\nDEAD Points: +%d", receipt.points, p.deadReceipt.points)
            end
            text = text .. string.format("\nPoints: +%d\nTotal Score: %d\n%s",
                points, total, Persistence.Status())
        else text = text .. "\nUnscored sortie (UCID unavailable)." end
        Log(string.format("%s %s points=%d scored=%s", record.id, result,
            receipt.points, tostring(receipt.scored)))
        if p.deadReceipt then
            Log(string.format("%s %s points=%d scored=%s", p.deadReceipt.missionID, p.deadReceipt.result,
                p.deadReceipt.points, tostring(p.deadReceipt.scored)))
        end
    end
    Message(record.group, text, 20)
    if HasPending(record) then SelectLeader(record) else Close(record) end
end

local function PrimaryComplete(record, time, result)
    if not Missions.IsActive(record) or record.state ~= "ACTIVE" then return end
    record.primaryCompletedAt, record.state = time, "RTB_PENDING"
    if record.category == "SEAD" then
        record.primaryResult = result or "DESTROYED"
        SEADSites.PrimaryComplete(record.site, record.primaryResult)
    end
    for _, p in ipairs(record.participants) do
        -- A pre-clear death/abort stays at zero even if the wing later wins.
        if not p.done then
            p.primaryCompletedAt, p.state, p.primaryResult = time, "RTB_PENDING", record.primaryResult
        end
    end
    local title = "Intercept PRIMARY OBJECTIVE COMPLETE"
    local objective = "All hostile aircraft destroyed."
    if record.category == "SEAD" then
        title = "SEAD Objective Complete"
        objective = record.primaryResult == "DESTROYED" and "Enemy radar destroyed." or "Enemy radar suppressed."
    elseif record.category == "DEAD" then
        title, objective = "DEAD Objective Complete", "SAM site destroyed.\nReturn to base."
    end
    Message(record.group, title .. "\n" ..
        objective .. "\nEach pilot: return to a BLUE airfield or carrier.\n" ..
        string.format("Reward per pilot: %d points; recovery failure: %d points.",
            record.fullReward, math.floor(record.fullReward * Config.recoveryFailurePercent / 100)), 20)
    Log(record.id .. " primary objective complete" .. (record.primaryResult and (" (" .. record.primaryResult .. ")") or "") ..
        "; awaiting individual RTB")
    ScanPlayers()
end

local function DeadComplete(record, time)
    local active = record.state == "DEAD_ACTIVE" or (record.category == "DEAD" and record.state == "ACTIVE")
    if not Missions.IsActive(record) or record.deadCompletedAt or not active then return end
    record.deadCompletedAt = time
    record.site.state, record.site.followOnAvailable, record.site.disposition = "DESTROYED", false, "CLEANUP"
    if record.category == "DEAD" then PrimaryComplete(record, time); return end
    record.state = "RTB_PENDING"
    for _, p in ipairs(record.participants) do
        if not p.done then
            if p.landing then
                -- An already valid SEAD recovery hold survives DEAD completion.
                p.landing.resumeState = "RTB_PENDING"
            else
                p.state = "RTB_PENDING"
            end
            p.deadScoring.primaryCompletedAt = time
        end
    end
    Message(record.group, "DEAD Objective Complete\nSAM site destroyed.\nReturn to base.\n" ..
        string.format("DEAD reward per pilot: %d points; recovery failure: %d points.\nSEAD reward also retained.",
            record.deadFullReward, math.floor(record.deadFullReward * Config.recoveryFailurePercent / 100)), 20)
    Log(record.id .. " immediate DEAD complete; awaiting SEAD and DEAD recovery settlement")
    ScanPlayers()
end

local function Ready(record)
    local airborne = true
    for _, p in ipairs(record.participants) do
        if not p.done then
            if not Player.IsControlling(p.owner) then return false, false end
            if not p.owner.unit:InAir() then airborne = false end
        end
    end
    return true, airborne
end

local function BeginScoring(record, fullReward)
    record.id, record.fullReward = record.id or Scoring.NextID(record.category), fullReward
    local pilots = {}
    for _, p in ipairs(record.participants) do
        if not p.done then
            p.id, p.fullReward, p.state, p.category = record.id, record.fullReward, "ACTIVE", record.category
            pilots[#pilots + 1] = p.owner.name ..
                (p.owner.ucid and (" (reward: " .. record.fullReward .. ")") or " (unscored)")
        end
    end
    return pilots
end

local function Start(record)
    local controlling, airborne = Ready(record)
    local leader = SelectLeader(record)
    if not controlling or not airborne or not leader then
        if record.category == "DEAD" then
            for _, p in ipairs(record.participants) do
                SettleParticipant(record, p, "FAILED", "DEAD reservation cancelled. No reward.")
            end
        else Close(record) end
        Message(record.group, record.category .. " reservation cancelled. Player aircraft changed or unavailable.")
        return
    end
    if record.category == "DEAD" then
        record.state, record.deadStartedAt = "ACTIVE", timer.getTime()
        for _, p in ipairs(record.participants) do if not p.done then p.state = "ACTIVE" end end
        local text = "DEAD TRAINING START\nObjective: destroy all remaining SAM site vehicles; then RTB."
        DebugLog(record, record.deadBriefing .. "\n" .. text .. "\nRemaining targets: " .. DEAD.Remaining(record))
        Message(record.group, text, 25)
        Log(record.id .. " started using retained site " .. record.site.id)
        return
    end
    if record.category == "SEAD" then
        local ok, spawn, problem = pcall(SEAD.Spawn, record.selection)
        if not ok or not spawn then
            Close(record)
            env.error("[DynamicTraining] SEAD spawn: " .. tostring(ok and problem or spawn))
            Message(record.group, "ERROR: SEAD spawn failed. Generate SEAD to retry; see DCS log.", 20)
            return
        end
        record.spawn, record.state = spawn, "ACTIVE"
        record.site = SEADSites.Register(record)
        local pilots = BeginScoring(record, Config.sead.fullReward)
        -- The full briefing was shown when planning completed; status can recall it.
        local text = "SEAD TRAINING START" .. string.format(
            "\nObjective: destroy primary emitter, or damage it and keep radar OFF for %g seconds; then RTB.",
            spawn.suppressionHoldSeconds)
        DebugLog(record, text .. "\nPilots: " .. table.concat(pilots, ", "))
        Message(record.group, text, 25)
        Log(record.id .. " started; mode=" .. record.plan.attackMode .. " template=" .. spawn.template .. " zone=" .. spawn.zone)
        return
    end
    local ok, spawn, problem = pcall(Intercept.Spawn, leader.unit, record.assignmentID)
    if not ok or not spawn then
        Close(record)
        env.error("[DynamicTraining] Spawn: " .. tostring(ok and problem or spawn))
        Message(record.group, "ERROR: Intercept enemy spawn failed. Select Generate Intercept to retry.", 15)
        return
    end
    record.spawn, record.state = spawn, "ACTIVE"
    local pilots = BeginScoring(record, Config.fullReward)
    local details = string.format(
        "Range: %d NM\nAltitude: %d ft\nAspect: HOT",
        spawn.distance, spawn.altitude)
    DebugLog(record, "Intercept MISSION START\nHostiles: " .. spawn.composition .. "\n" .. details ..
        "\nPilots: " .. table.concat(pilots, ", "))
    Message(record.group, "Intercept MISSION START\n" .. details, 15)
    Log(record.id .. " started; registered pilots=" .. tostring(#pilots) ..
        " template=" .. spawn.template ..
        " formation=" .. spawn.formation .. "/" .. spawn.formationSpacing)
end

local function Generate(groupName, category)
    category = category or "Intercept"
    local group = GROUP:FindByName(groupName)
    local roster, problem = Player.ForGroup(groupName)
    if not roster then Message(group, problem); return end
    local blocker = Missions.Blocker(groupName, roster)
    if blocker then Message(group, blocker); return end
    local record = { group = group, groupName = groupName, category = category, participants = {},
        state = "ARMED", nextTakeoffCheck = timer.getTime() }
    -- Freeze membership at acceptance, including those still on the ground.
    for _, owner in ipairs(roster) do
        record.participants[#record.participants + 1] = { owner = owner, state = "ARMED" }
    end
    local acquired, blocked = Missions.Acquire(record)
    if not acquired then Message(group, blocked); return end
    if problem then Message(group, problem, 15) end
    if category == "DEAD" then
        -- Follow-on DEAD accepts a preserved SEAD site; never create a new SAM.
        record.owner = roster[1]
        local site, previous, airborne
        local ok, failure = pcall(function()
            site = DEAD.SelectSite(record.owner.unit:GetVec3(), record.groupName)
            if not site then return end
            previous = assert(SEADSites.Reserve(site, record.assignmentID, record.groupName))
            local reward = Config.dead.fullReward
            assert(type(reward) == "number" and reward >= 0 and reward < math.huge and reward % 1 == 0,
                "Invalid DEAD full reward.")
            record.deadTargets = DEAD.Snapshot(site)
            record.deadBriefing = DEAD.Briefing(site)
            record.site, record.spawn, record.plan = site, site.spawn, site.plan
            local controlling
            controlling, airborne = Ready(record)
            assert(controlling, "DEAD participant aircraft changed during acceptance.")
            BeginScoring(record, reward)
        end)
        if not ok or not site then
            Missions.Release(record)
            SEADSites.Rollback(site, record.assignmentID, previous)
            if not ok then
                env.error("[DynamicTraining] DEAD setup: " .. tostring(failure))
                Message(group, "ERROR: DEAD setup failed. Site reservation rolled back; see DCS log.", 20)
            else Message(group, "No preserved SAM sites available for DEAD.", 15) end
            return
        end
        Message(group, "DEAD mission accepted.", 10)
        local briefing = record.deadBriefing .. string.format("\nReward per pilot: %d points.\nRegistered pilots: %d.",
            record.fullReward, #record.participants)
        DebugLog(record, briefing .. "\nRemaining targets: " .. #record.deadTargets ..
            (airborne and "" or "\nSite reserved. Waiting for ALL registered pilots to take off."))
        Message(group, briefing, Config.coordinateBriefingSeconds)
        if airborne then Start(record) else
            record.state = "ARMED"
            for _, p in ipairs(record.participants) do p.state = "ARMED" end
        end
        return
    end
    if category == "SEAD" then
        record.owner = roster[1]
        record.id = Scoring.NextID(category)
        local _, airborne = Ready(record)
        record.airborneAtAcceptance = airborne
        local ok, job = pcall(function()
            return SEAD.Begin(record.assignmentID, record.id, record.owner.unit:GetVec3())
        end)
        if not ok then
            Close(record)
            env.error("[DynamicTraining] SEAD setup: " .. tostring(job))
            Message(group, "ERROR: SEAD setup failed. See DCS log; Generate SEAD to retry.", 15)
            return
        end
        record.selection, record.plan, record.state = job, job.plan, "PLANNING"
        for _, p in ipairs(record.participants) do p.state = "PLANNING" end
        DebugLog(record, "SEAD mission accepted.\nMODE: " .. record.plan.attackMode .. "\nMission planning in progress.")
        Message(group, "SEAD mission accepted.\nMission planning in progress.", 10)
        return
    end
    local _, airborne = Ready(record)
    if airborne then Start(record) else
        record.owner = roster[1]
        Message(group, string.format(
            "Intercept mission armed. Registered pilots: %d.\nWaiting for ALL registered pilots to take off.",
            #roster))
    end
end

local function Statistics(groupName)
    local group = GROUP:FindByName(groupName)
    local roster, problem = Player.ForGroup(groupName)
    if not roster then Message(group, problem); return end
    local texts = {}
    for _, owner in ipairs(roster) do
        local p = Scoring.Get(owner.ucid, owner.name)
        if p then
            texts[#texts + 1] = string.format(
                "PLAYER STATISTICS: %s [%s]\nTotal Score: %d\nCareer Points: %d\nIntercept Score: %d\nSEAD Score: %d\nDEAD Score: %d\n" ..
                "Settled Missions: %d\nPrimary Success: %d\nRTB Success: %d\nRecovery Failure: %d\nDeath Count: %d",
                owner.name, owner.unitName, p.totalScore, p.careerPoints, p.interceptScore, p.seadScore, p.deadScore,
                p.missionCount, p.primarySuccessCount, p.rtbSuccessCount, p.recoveryFailureCount, p.deathCount)
        else texts[#texts + 1] = "PLAYER STATISTICS: " .. owner.name .. "\nUCID unavailable; unscored." end
    end
    Message(group, table.concat(texts, "\n\n") .. "\n" .. Persistence.Status(), 25)
end

local function Status(groupName)
    local group = GROUP:FindByName(groupName)
    local roster = Player.ForGroup(groupName)
    local records = Missions.ForGroup(groupName, roster)
    if #records == 0 then Message(group, "Intercept: Idle.\nSEAD: Idle.\nDEAD: Idle."); return end
    local texts, displaySeconds = {}, 20
    for _, record in ipairs(records) do
        if record.category == "DEAD" or (record.category == "SEAD" and record.plan.estimatedPoint) then
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
            if record.spawn then text = text .. "\n" .. SEADObjective.Status(record.spawn, timer.getTime()) end
            if record.state == "PLANNING" then
                text = text .. "\nSite checks: " .. record.selection.totalAttempts
            end
        end
        if record.site then
            SEADSites.Refresh(record.site)
            text = text .. "\nSite state: " .. record.site.state
            if record.site.seadCompleted then
                text = text .. "\nSite remaining vehicles: " .. (record.site.remainingTargetCount or "UNKNOWN")
            end
            text = text .. "\nSite disposition: " .. record.site.disposition:gsub("_", " ") ..
                "\nFollow-on DEAD available: " .. (record.site.followOnAvailable and "YES" or "NO")
        end
        if record.spawnAt then
            text = text .. string.format("\nSpawn in %d seconds.", math.max(0, math.ceil(record.spawnAt - timer.getTime())))
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
    Message(group, table.concat(texts, "\n\n"), displaySeconds)
end

local function CanManage(groupName, target)
    local roster = Player.ForGroup(groupName)
    if not roster then return false end
    for _, current in ipairs(roster) do
        if Player.CanManage(target.owner, current) then return true end
    end
    return false
end

local function FollowOnAvailable(groupName, record)
    if not Missions.IsActive(record) or record.groupName ~= groupName or record.category ~= "SEAD"
        or record.state ~= "RTB_PENDING" or record.deadStartedAt or not record.primaryCompletedAt then return false end
    local site = record.site
    local targets = site and SEADSites.Refresh(site)
    if not targets or #targets == 0 or not site.followOnAvailable or site.cleanupRequested or site.cleaned
        or site.reservedByAssignmentID ~= record.assignmentID then return false end
    for _, p in ipairs(record.participants) do
        if not p.done and CanManage(groupName, p) then return true end
    end
    return false
end

local function FollowOn(groupName, record, preserve)
    local group = GROUP:FindByName(groupName)
    if not FollowOnAvailable(groupName, record) then
        Message(group, "Follow-on DEAD is no longer available for this SEAD mission."); return
    end
    local site, time = record.site, timer.getTime()
    if preserve then
        local keeper
        for _, p in ipairs(record.participants) do
            if not p.done and Player.IsControlling(p.owner) then keeper = p.owner; break end
        end
        if keeper and SEADSites.Preserve(site, record.assignmentID, time, keeper) then
            Message(group, "SAM site preserved for follow-on DEAD.\nKeeper: " .. site.retainedBy.name ..
                "\nSite remains reserved for your wing after SEAD settlement.\nReturn to base and rearm." ..
                "\nSite will be cleaned when the keeper disconnects.", 20)
        end
        return
    end
    -- Snapshot before changing phase: an API failure leaves SEAD recovery intact.
    local targets = DEAD.Snapshot(site)
    local reward = Config.dead.fullReward
    assert(type(reward) == "number" and reward >= 0 and reward < math.huge and reward == math.floor(reward),
        "Invalid DEAD reward")
    record.deadScoringID, record.deadFullReward = Scoring.NextID("DEAD"), reward
    site.disposition, site.followOnAvailable = "IN_USE", false
    site.unreservedSince = nil
    record.deadTargets, record.deadStartedAt, record.state = targets, time, "DEAD_ACTIVE"
    for _, p in ipairs(record.participants) do
        if not p.done then
            p.state, p.landing = "DEAD_ACTIVE", nil
            p.deadScoring = { id = record.deadScoringID, category = "DEAD", owner = p.owner,
                fullReward = reward, scoreOnly = true }
        end
    end
    Message(group, "Immediate DEAD started.\nDestroy all remaining SAM site vehicles.\nRemaining targets: " ..
        #targets .. string.format("\nAdditional DEAD reward per pilot: %d points.\nSEAD reward also retained.", reward), 20)
    Log(record.id .. " continued as DEAD using original site")
end

local function Abort(groupName, target, assignment)
    local group = GROUP:FindByName(groupName)
    local record = assignment
    if target then
        if not Missions.IsActive(record) then Message(group, "This sortie is already closed."); return end
    else
        local records = Missions.ForGroup(groupName, Player.ForGroup(groupName))
        if #records == 0 then Message(group, "Intercept: Idle.\nSEAD: Idle.\nDEAD: Idle."); return end
        record = records[1]
        if not Missions.wings[groupName] and #records > 1 then
            Message(group, "Multiple earlier wing missions found. Use the named Abort Sortie command."); return
        end
    end
    local authorized = false
    for _, p in ipairs(record.participants) do
        if CanManage(groupName, p) then authorized = true; break end
    end
    if not authorized then Message(group, "Only registered mission participants may abort this mission."); return end
    if target then
        local registered = false
        for _, p in ipairs(record.participants) do if p == target then registered = true end end
        if not registered or target.done then Message(group, "This sortie is already closed."); return end
        -- Group F10 has no caller identity: registered wing members may select
        -- a named sortie; from another group, only their own UCID is permitted.
        if groupName ~= record.groupName and not CanManage(groupName, target) then
            Message(group, "Only your own sortie may be aborted from another wing."); return
        end
        SettleParticipant(record, target, "ABORT", "Individual sortie aborted. No reward.")
        if not record.spawn and record.state ~= "PLANNING" and Missions.IsActive(record) then
            record.spawnAt, record.state = nil, "ARMED"
        end
    else
        if groupName ~= record.groupName and #record.participants > 1 then
            Message(group, "Use Abort Sortie for your own pilot; wing abort is available in the original wing."); return
        end
        for _, p in ipairs(record.participants) do
            SettleParticipant(record, p, "ABORT", "Wing mission aborted. No reward.")
        end
        if not record.spawn then Message(group, (record.category or "Intercept") .. " reservation cancelled.") end
    end
end

ScanPlayers = function()
    local present = {}
    -- Standard API lists human BLUE units; MOOSE supplies wrappers and menus.
    -- Neither airfield names nor Client group names are fixed.
    for _, dcsUnit in ipairs(coalition.getPlayers(coalition.side.BLUE) or {}) do
        if dcsUnit:isExist() then
            local unit = UNIT:FindByName(dcsUnit:getName())
            if unit and unit:GetTypeName() == Config.playerType then
                local group = unit:GetGroup()
                present[group:GetName()] = group
            end
        end
    end
    for name, group in pairs(present) do
        local roster = Player.ForGroup(name) or {}
        local records = Missions.ForGroup(name, roster)
        local signature = tostring(group:GetID())
        for _, owner in ipairs(roster) do
            signature = signature .. ":" .. owner.unitName .. ":" .. owner.objectID .. ":" .. owner.name .. ":" .. tostring(owner.ucid)
        end
        local targets = {}
        local followOn = Missions.wings[name]
        local canContinue = FollowOnAvailable(name, followOn)
        local canPreserve = canContinue and followOn.site.disposition == "CLEANUP"
        signature = signature .. ":follow:" .. tostring(canContinue) .. ":preserve:" .. tostring(canPreserve)
        local reservations = {}
        for _, site in pairs(Missions.sites) do
            if SEADSites.CanReleaseReservation(site, name) then reservations[#reservations + 1] = site end
        end
        table.sort(reservations, function(a, b) return a.id < b.id end)
        for _, site in ipairs(reservations) do signature = signature .. ":release:" .. site.id end
        for _, record in ipairs(records) do
            signature = signature .. ":assignment:" .. record.assignmentID
            for _, p in ipairs(record.participants) do
                local own = false
                for _, current in ipairs(roster) do
                    if Player.CanManage(p.owner, current) then own = true end
                end
                if not p.done and (name == record.groupName or own) then
                    targets[#targets + 1] = { participant = p, record = record }
                    signature = signature .. ":abort:" .. p.owner.unitName
                end
            end
        end
        if not menus[name] or menus[name].signature ~= signature then
            if menus[name] then menus[name].root:Remove() end
            local root = MENU_GROUP:New(group, "Dynamic Training")
            menus[name] = { root = root, signature = signature }
            for _, command in ipairs({
                { "Generate Intercept", Generate },
                { "Generate SEAD", function(groupName) Generate(groupName, "SEAD") end },
                { "Generate DEAD", function(groupName) Generate(groupName, "DEAD") end }, { "Mission Status", Status },
                { "Abort Mission", Abort }, { "Player Statistics", Statistics }
            }) do
                local label, action = command[1], command[2]
                MENU_GROUP_COMMAND:New(group, label, root, function()
                    Safe(label, group, function() action(name); ScanPlayers() end)
                end)
            end
            if canContinue then
                local record = followOn
                for _, choice in ipairs({ { "Continue as DEAD", false }, { "Preserve Site for DEAD", true } }) do
                    local label, preserve = choice[1], choice[2]
                    if not preserve or canPreserve then
                        MENU_GROUP_COMMAND:New(group, label, root, function()
                            Safe(label, group, function() FollowOn(name, record, preserve); ScanPlayers() end)
                        end)
                    end
                end
            end
            for index, reservedSite in ipairs(reservations) do
                local site, groupID, owners = reservedSite, group:GetID(), roster
                local label = "Release Site Reservation"
                if #reservations > 1 then
                    label = label .. ": " .. (site.plan.areaLabel or "SAM site") .. " (" .. index .. ")"
                end
                MENU_GROUP_COMMAND:New(group, label, root, function()
                    Safe(label, group, function()
                        local currentGroup, authorized = GROUP:FindByName(name), false
                        if currentGroup and currentGroup:GetID() == groupID then
                            for _, current in ipairs(Player.ForGroup(name) or {}) do
                                for _, owner in ipairs(owners) do
                                    if Player.CanManage(owner, current) then authorized = true end
                                end
                            end
                        end
                        if authorized and SEADSites.ReleaseReservation(site, name) then
                            local waiting = site.reservedByAssignmentID ~= nil
                            Message(currentGroup, "SAM site reservation released.\n" ..
                                (waiting and "Available to other wings after SEAD settlement.\n" or "Available to all wings for Generate DEAD.\n") ..
                                string.format("Cleanup after %g minutes without a reservation.",
                                    Config.dead.unreservedSiteCleanupSeconds / 60), 20)
                        else
                            Message(currentGroup or group, "This site reservation is no longer available to release.")
                        end
                        ScanPlayers()
                    end)
                end)
            end
            for _, entry in ipairs(targets) do
                local target, record = entry.participant, entry.record
                local p = target
                local label = "Abort Sortie: " .. p.owner.name .. " [" .. p.owner.unitName .. "]"
                MENU_GROUP_COMMAND:New(group, label, root, function()
                    Safe("Individual abort", group, function() Abort(name, target, record); ScanPlayers() end)
                end)
            end
        end
    end
    for name, menu in pairs(menus) do
        if not present[name] then menu.root:Remove(); menus[name] = nil end
    end
end

local function TickMission(record, time)
    if not Missions.IsActive(record) then return end
    if record.state == "PLANNING" then
        -- Spread bounded terrain/scenery checks across ticks to avoid a long frame.
        local controlling = Ready(record)
        if not controlling then
            Close(record); Message(record.group, "SEAD selection cancelled. Player aircraft changed or unavailable.")
            return
        end
        local reservations = {}
        for _, other in ipairs(Missions.Snapshot()) do
            if other ~= record and other.category == "SEAD" and other.plan.actualSpawnPoint then
                reservations[#reservations + 1] = { point = other.plan.actualSpawnPoint, radius = other.selection.radius }
            end
        end
        local ok, plan, state, problem = pcall(SEAD.Step, record.selection, reservations)
        if not ok or state == "FAILED" then
            Close(record)
            env.error("[DynamicTraining] SEAD selection: " .. tostring(ok and problem or plan))
            local detail = ok and SEAD.FailureSummary(record.selection) or "Site check error. See DCS log."
            Message(record.group, "ERROR: SEAD placement failed.\n" .. detail .. "\nGenerate SEAD to retry.", 25)
        elseif plan then
            -- Plan is complete before any physical spawn. Only the accepted
            -- plan supplies briefing data, including after departure/spawn.
            record.state = "ARMED"
            for _, p in ipairs(record.participants) do if not p.done then p.state = "ARMED" end end
            local briefing = SEAD.Briefing(record.plan) .. string.format(
                "\nReward per pilot: %d points.\nRegistered pilots: %d.",
                Config.sead.fullReward, #record.participants)
            DebugLog(record, briefing .. string.format(
                "\nGround acceptance: SAM spawns %d seconds after ALL registered pilots take off.\n",
                Config.takeoffDelaySeconds) .. SEAD.Instructions(record.plan))
            Message(record.group, briefing, Config.coordinateBriefingSeconds)
            local _, airborne = Ready(record)
            if record.airborneAtAcceptance and airborne then Start(record) end
        end
    elseif record.state == "ARMED" or record.state == "TAKEOFF_DELAY" then
        if time < record.nextTakeoffCheck then return end
        record.nextTakeoffCheck = time + Config.takeoffCheckSeconds
        local controlling, airborne = Ready(record)
        if not controlling then
            if record.category == "DEAD" then
                for _, p in ipairs(record.participants) do
                    SettleParticipant(record, p, "FAILED", "DEAD reservation cancelled. No reward.")
                end
            else Close(record) end
            Message(record.group, record.category .. " reservation cancelled. Player aircraft changed or unavailable.")
        elseif not airborne then
            if record.spawnAt then
                record.spawnAt, record.state = nil, "ARMED"
                DebugLog(record, record.category .. " countdown reset. Waiting for all registered pilots to take off.")
            end
        elseif record.category == "DEAD" then
            Start(record) -- Existing SAM is already present; no spawn delay.
        elseif not record.spawnAt then
            record.spawnAt, record.state = time + Config.takeoffDelaySeconds, "TAKEOFF_DELAY"
            DebugLog(record, string.format("All registered pilots airborne. Hostiles will spawn in %d seconds.",
                Config.takeoffDelaySeconds))
        elseif time >= record.spawnAt then
            record.spawnAt = nil
            Start(record)
        end
    elseif record.state == "ACTIVE" or record.state == "DEAD_ACTIVE" then
        -- No retrospective polling win when every original aircraft has gone.
        if SelectLeader(record) then
            if record.deadTargets then
                if DEAD.Remaining(record) == 0 then DeadComplete(record, time) end
            elseif record.category == "SEAD" then
                local result = SEAD.UpdateObjective(record.spawn, time)
                if result then PrimaryComplete(record, time, result) end
            elseif Intercept.AllGone(record.spawn) then PrimaryComplete(record, time) end
        end
    end
    -- Immediate DEAD cannot block settlement of the achieved SEAD objective.
    -- Poll targets first so completion before confirmed RTB is counted.
    if Missions.IsActive(record) and CanRecover(record) then
        for _, p in ipairs(record.participants) do
            if not p.done and p.state == "LANDING_CHECK" then
                if Recovery.Update(p, time) == "SUCCESS" then
                    SettleParticipant(record, p, "RTB_SUCCESS", "Safe recovery confirmed (100%).", time)
                end
            end
        end
    end
end

local eventHandler = BASE:New()
local failureEvents = {}
for _, name in ipairs({ "Crash", "Dead", "PilotDead", "Ejection", "UnitLost" }) do
    if EVENTS[name] and EVENTS[name] >= 0 then failureEvents[EVENTS[name]] = name end
end

local function HandleEvent(record, event)
    if not Missions.IsActive(record) or not record.spawn then return end
    local time = event.Time or event.time or timer.getTime()
    local reason = failureEvents[event.id]
    if reason then
        for _, p in ipairs(record.participants) do
            if Player.EventMatches(p.owner, event) then
                if p.done then return end
                p.failureEvent = reason
                if p.primaryCompletedAt and time >= p.primaryCompletedAt then
                    SettleParticipant(record, p, "RTB_FAILURE", reason .. " before safe recovery (60%).", time)
                else
                    p.primaryCompletedAt = nil
                    SettleParticipant(record, p, "FAILED", reason .. " before primary completion (0 points).", time)
                end
                return
            end
        end
        if (record.state == "ACTIVE" or record.state == "DEAD_ACTIVE") and
            (event.id == EVENTS.Crash or event.id == EVENTS.Dead or event.id == EVENTS.UnitLost) then
            if record.deadTargets then
                if DEAD.RecordLoss(record, event) then DeadComplete(record, time) end
            else
                local module = record.category == "SEAD" and SEAD or Intercept
                if module.RecordLoss(record.spawn, event) then PrimaryComplete(record, time) end
            end
        end
    elseif event.id == EVENTS.RunwayTouch or event.id == EVENTS.Land then
        if CanRecover(record) then
            for _, p in ipairs(record.participants) do
                if not p.done then Recovery.Start(p, event, record.state) end
            end
        end
    elseif event.id == EVENTS.Takeoff or event.id == EVENTS.RunwayTakeoff then
        for _, p in ipairs(record.participants) do
            if not p.done and Player.EventMatches(p.owner, event) and p.landing then
                p.state = p.landing.resumeState
                p.landing = nil
            end
        end
    end
end

local subscriptions = {}
for id in pairs(failureEvents) do subscriptions[id] = true end
for _, name in ipairs({ "RunwayTouch", "Land", "Takeoff", "RunwayTakeoff" }) do
    if EVENTS[name] and EVENTS[name] >= 0 then subscriptions[EVENTS[name]] = true end
end
for id in pairs(subscriptions) do
    eventHandler:HandleEvent(id, function(_, event)
        if event.id == EVENTS.Crash or event.id == EVENTS.Dead or event.id == EVENTS.UnitLost then
            Safe("SAM site loss", nil, function() SEADSites.RecordLoss(event) end)
        end
        for _, record in ipairs(Missions.Snapshot()) do
            Safe("Mission event", record.group, function() HandleEvent(record, event) end)
        end
        Safe("Player menu scan", nil, ScanPlayers)
    end)
end

local function Tick(_, time)
    if time >= nextPlayerScan then
        Safe("Player menu scan", nil, ScanPlayers)
        nextPlayerScan = time + Config.playerScanSeconds
    end
    for _, record in ipairs(Missions.Snapshot()) do
        Safe("Mission monitor", record.group, function() TickMission(record, time) end)
    end
    Safe("SEAD site cleanup", nil, SEADSites.Sweep)
    return time + Config.pollSeconds
end

MapOverlay.RefreshFriendlyAirbases()
Safe("Initial player menu scan", nil, ScanPlayers)
timer.scheduleFunction(Tick, nil, timer.getTime() + Config.pollSeconds)
GlobalMessage("Dynamic Training ready. Wing UCID scoring.\n" .. Persistence.Status(), 10)
