-- Runtime entry. Build-Mission.ps1 prepends the local gameplay modules.
if DynamicTrainingRuntime then
    trigger.action.outText("Dynamic Training is already loaded.", 10)
    return
end
if not BASE or not SPAWN or not MENU_GROUP then
    trigger.action.outText("ERROR: Load MOOSE before DynamicTraining.", 15)
    return
end
DynamicTrainingRuntime = { version = "SEAD-emitter-FSM-trial-5" }

local menus = {}
local nextPlayerScan = 0
local ScanPlayers

local function Message(group, text, seconds)
    if group then pcall(function() MESSAGE:New(text, seconds or 10):ToGroup(group) end) end
end

local function Log(text)
    env.info("[DynamicTraining] " .. text)
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

local function Close(record)
    -- Release before cleanup: generated destroy events cannot award a win.
    if not Missions.Release(record) then return end
    if record.category == "SEAD" then
        SEADSites.Release(record.site)
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

local function SettleParticipant(record, p, result, reason)
    if p.done then return end
    local receipt
    if p.id then receipt = Scoring.Settle(p, result, reason) end
    p.done, p.state, p.receipt, p.landing = true, result, receipt, nil
    local text = string.format("%s %s: %s\n%s", record.category or "Intercept", result, p.owner.name, reason)
    if receipt then
        if receipt.scored then
            text = text .. string.format("\nPoints: +%d\nTotal Score: %d\nSession only; not saved.",
                receipt.points, receipt.total)
        else text = text .. "\nUnscored sortie (UCID unavailable)." end
        Log(string.format("%s %s points=%d scored=%s", record.id, result,
            receipt.points, tostring(receipt.scored)))
    end
    Message(record.group, text, 20)
    if HasPending(record) then SelectLeader(record) else Close(record) end
end

local function PrimaryComplete(record, time, result)
    if not Missions.IsActive(record) or record.state ~= "ACTIVE" then return end
    record.primaryCompletedAt, record.state = time, "RTB_PENDING"
    if record.category == "SEAD" then record.primaryResult = result or "DESTROYED" end
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
    end
    Message(record.group, title .. "\n" ..
        objective .. "\nEach pilot: return to a BLUE airfield or carrier.\n" ..
        string.format("Reward per pilot: %d points; recovery failure: %d points.",
            record.fullReward, math.floor(record.fullReward * Config.recoveryFailurePercent / 100)), 20)
    Log(record.id .. " primary objective complete" .. (record.primaryResult and (" (" .. record.primaryResult .. ")") or "") ..
        "; awaiting individual RTB")
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
        Close(record)
        Message(record.group, record.category .. " reservation cancelled. Player aircraft changed or unavailable.")
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
        Message(record.group, "SEAD TRAINING START\n" .. SEAD.Briefing(record.plan) ..
            string.format("\nObjective: destroy primary emitter, or damage it and keep radar OFF for %g seconds; then RTB.\nPilots: %s",
                spawn.suppressionHoldSeconds, table.concat(pilots, ", ")), 25)
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
    Message(record.group, string.format(
        "Intercept MISSION START\nHostiles: %s\nRange: %d NM\nAltitude: %d ft\nAspect: HOT\nPilots: %s",
        spawn.composition, spawn.distance, spawn.altitude, table.concat(pilots, ", ")), 15)
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
        Message(group, SEAD.Briefing(record.plan) .. "\nMission planning in progress.", 20)
        return
    end
    local _, airborne = Ready(record)
    if airborne then Start(record) else
        record.owner = roster[1]
        Message(group, string.format(
            "Intercept mission armed. Registered pilots: %d.\nHostiles will spawn %d seconds after ALL registered pilots take off.",
            #roster, Config.takeoffDelaySeconds))
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
                "PLAYER STATISTICS: %s [%s]\nTotal Score: %d\nCareer Points: %d\nIntercept Score: %d\nSEAD Score: %d\n" ..
                "Settled Missions: %d\nPrimary Success: %d\nRTB Success: %d\nRecovery Failure: %d",
                owner.name, owner.unitName, p.totalScore, p.careerPoints, p.interceptScore, p.seadScore,
                p.missionCount, p.primarySuccessCount, p.rtbSuccessCount, p.recoveryFailureCount)
        else texts[#texts + 1] = "PLAYER STATISTICS: " .. owner.name .. "\nUCID unavailable; unscored." end
    end
    Message(group, table.concat(texts, "\n\n") .. "\nSession only; not saved.", 25)
end

local function Status(groupName)
    local group = GROUP:FindByName(groupName)
    local roster = Player.ForGroup(groupName)
    local records = Missions.ForGroup(groupName, roster)
    if #records == 0 then Message(group, "Intercept: Idle.\nSEAD: Idle."); return end
    local texts = {}
    for _, record in ipairs(records) do
        local text = (record.category or "Intercept") .. ": " .. record.state .. "\nWing: " .. record.groupName ..
            "\nLead reference: " .. record.owner.name
        if record.category == "SEAD" then
            text = text .. "\n" .. SEAD.Briefing(record.plan)
            if record.primaryResult then text = text .. "\nPrimary result: " .. record.primaryResult end
            if record.spawn then text = text .. "\n" .. SEADObjective.Status(record.spawn, timer.getTime()) end
            if record.state == "PLANNING" then
                text = text .. "\nSite checks: " .. record.selection.totalAttempts
            end
        end
        if record.spawnAt then
            text = text .. string.format("\nSpawn in %d seconds.", math.max(0, math.ceil(record.spawnAt - timer.getTime())))
        end
        for _, p in ipairs(record.participants) do
            text = text .. "\n" .. p.owner.name .. " [" .. p.owner.unitName .. "]: " .. p.state
            if p.receipt then text = text .. " (+" .. p.receipt.points .. ")" end
        end
        texts[#texts + 1] = text
    end
    Message(group, table.concat(texts, "\n\n"), 20)
end

local function CanManage(groupName, target)
    local roster = Player.ForGroup(groupName)
    if not roster then return false end
    for _, current in ipairs(roster) do
        if Player.CanManage(target.owner, current) then return true end
    end
    return false
end

local function Abort(groupName, target, assignment)
    local group = GROUP:FindByName(groupName)
    local record = assignment
    if target then
        if not Missions.IsActive(record) then Message(group, "This sortie is already closed."); return end
    else
        local records = Missions.ForGroup(groupName, Player.ForGroup(groupName))
        if #records == 0 then Message(group, "Intercept: Idle.\nSEAD: Idle."); return end
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
            signature = signature .. ":" .. owner.unitName .. ":" .. owner.objectID .. ":" .. owner.name
        end
        local targets = {}
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
                { "Generate SEAD", function(groupName) Generate(groupName, "SEAD") end }, { "Mission Status", Status },
                { "Abort Mission", Abort }, { "Player Statistics", Statistics }
            }) do
                local label, action = command[1], command[2]
                MENU_GROUP_COMMAND:New(group, label, root, function()
                    Safe(label, group, function() action(name); ScanPlayers() end)
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
            Message(record.group, SEAD.Briefing(record.plan) .. string.format(
                "\nReward per pilot: %d points.\nRegistered pilots: %d.\nGround acceptance: SAM spawns %d seconds after ALL registered pilots take off.",
                Config.sead.fullReward, #record.participants, Config.takeoffDelaySeconds), 30)
            local _, airborne = Ready(record)
            if record.airborneAtAcceptance and airborne then Start(record) end
        end
    elseif record.state == "ARMED" or record.state == "TAKEOFF_DELAY" then
        if time < record.nextTakeoffCheck then return end
        record.nextTakeoffCheck = time + Config.takeoffCheckSeconds
        local controlling, airborne = Ready(record)
        if not controlling then
            Close(record)
            Message(record.group, record.category .. " reservation cancelled. Player aircraft changed or unavailable.")
        elseif not airborne then
            if record.spawnAt then
                record.spawnAt, record.state = nil, "ARMED"
                Message(record.group, record.category .. " countdown reset. Waiting for all registered pilots to take off.")
            end
        elseif not record.spawnAt then
            record.spawnAt, record.state = time + Config.takeoffDelaySeconds, "TAKEOFF_DELAY"
            Message(record.group, string.format("All registered pilots airborne. Hostiles will spawn in %d seconds.",
                Config.takeoffDelaySeconds))
        elseif time >= record.spawnAt then
            record.spawnAt = nil
            Start(record)
        end
    elseif record.state == "ACTIVE" then
        -- No retrospective polling win when every original aircraft has gone.
        if SelectLeader(record) then
            if record.category == "SEAD" then
                local result = SEAD.UpdateObjective(record.spawn, time)
                if result then PrimaryComplete(record, time, result) end
            elseif Intercept.AllGone(record.spawn) then PrimaryComplete(record, time) end
        end
    elseif record.state == "RTB_PENDING" then
        for _, p in ipairs(record.participants) do
            if not p.done and p.state == "LANDING_CHECK" then
                if Recovery.Update(p, time) == "SUCCESS" then
                    SettleParticipant(record, p, "RTB_SUCCESS", "Safe recovery confirmed (100%).")
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
                if p.primaryCompletedAt and time >= p.primaryCompletedAt then
                    SettleParticipant(record, p, "RTB_FAILURE", reason .. " before safe recovery (60%).")
                else
                    p.primaryCompletedAt = nil
                    SettleParticipant(record, p, "FAILED", reason .. " before primary completion (0 points).")
                end
                return
            end
        end
        if record.state == "ACTIVE" and
            (event.id == EVENTS.Crash or event.id == EVENTS.Dead or event.id == EVENTS.UnitLost) then
            local module = record.category == "SEAD" and SEAD or Intercept
            if module.RecordLoss(record.spawn, event) then PrimaryComplete(record, time) end
        end
    elseif event.id == EVENTS.RunwayTouch or event.id == EVENTS.Land then
        if record.state == "RTB_PENDING" then
            for _, p in ipairs(record.participants) do
                if not p.done then Recovery.Start(p, event) end
            end
        end
    elseif event.id == EVENTS.Takeoff or event.id == EVENTS.RunwayTakeoff then
        for _, p in ipairs(record.participants) do
            if not p.done and Player.EventMatches(p.owner, event) and p.landing then
                p.landing, p.state = nil, "RTB_PENDING"
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
        for _, record in ipairs(Missions.Snapshot()) do
            Safe("Mission event", record.group, function() HandleEvent(record, event) end)
        end
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

Safe("Initial player menu scan", nil, ScanPlayers)
timer.scheduleFunction(Tick, nil, timer.getTime() + Config.pollSeconds)
trigger.action.outText("Dynamic Training ready. Wing UCID scoring trial; session scores are not saved.", 10)
