-- Runtime entry. Build-Mission.ps1 prepends the local gameplay modules.
if DynamicTrainingRuntime then
    trigger.action.outText("Dynamic Training is already loaded.", 10)
    return
end
if not BASE or not SPAWN or not MENU_GROUP then
    trigger.action.outText("ERROR: Load MOOSE before DynamicTraining.", 15)
    return
end
DynamicTrainingRuntime = { version = "UCID-parallel-wing-scoring-trial-3" }

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
    if record.spawn then Safe("Enemy cleanup", record.group, function() record.spawn.group:Destroy(false) end) end
    Log((record.id or "Intercept reservation") .. " closed; wing assignment released")
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
    local text = string.format("Intercept %s: %s\n%s", result, p.owner.name, reason)
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

local function PrimaryComplete(record, time)
    if not Missions.IsActive(record) or record.state ~= "ACTIVE" then return end
    record.primaryCompletedAt, record.state = time, "RTB_PENDING"
    for _, p in ipairs(record.participants) do
        -- A pre-clear death/abort stays at zero even if the wing later wins.
        if not p.done then p.primaryCompletedAt, p.state = time, "RTB_PENDING" end
    end
    Message(record.group, "Intercept PRIMARY OBJECTIVE COMPLETE\n" ..
        "All hostile aircraft destroyed.\nEach pilot: return to a BLUE airfield or carrier.\n" ..
        string.format("Reward per pilot: %d points; recovery failure: %d points.",
            record.fullReward, math.floor(record.fullReward * Config.recoveryFailurePercent / 100)), 20)
    Log(record.id .. " primary objective complete; awaiting individual RTB")
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

local function Start(record)
    local controlling, airborne = Ready(record)
    local leader = SelectLeader(record)
    if not controlling or not airborne or not leader then
        Close(record)
        Message(record.group, "Intercept reservation cancelled. Player aircraft changed or unavailable.")
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
    record.id, record.fullReward = Scoring.NextID(), Config.fullReward
    local pilots = {}
    for _, p in ipairs(record.participants) do
        if not p.done then
            p.id, p.fullReward, p.state = record.id, record.fullReward, "ACTIVE"
            pilots[#pilots + 1] = p.owner.name ..
                (p.owner.ucid and (" (reward: " .. record.fullReward .. ")") or " (unscored)")
        end
    end
    Message(record.group, string.format(
        "Intercept MISSION START\nHostiles: %s\nRange: %d NM\nAltitude: %d ft\nAspect: HOT\nPilots: %s",
        spawn.composition, spawn.distance, spawn.altitude, table.concat(pilots, ", ")), 15)
    Log(record.id .. " started; registered pilots=" .. tostring(#pilots) ..
        " template=" .. spawn.template ..
        " formation=" .. spawn.formation .. "/" .. spawn.formationSpacing)
end

local function Generate(groupName)
    local group = GROUP:FindByName(groupName)
    local roster, problem = Player.ForGroup(groupName)
    if not roster then Message(group, problem); return end
    local blocker = Missions.Blocker(groupName, roster)
    if blocker then Message(group, blocker); return end
    local record = { group = group, groupName = groupName, participants = {},
        state = "ARMED", nextTakeoffCheck = timer.getTime() }
    -- Freeze membership at acceptance, including those still on the ground.
    for _, owner in ipairs(roster) do
        record.participants[#record.participants + 1] = { owner = owner, state = "ARMED" }
    end
    local acquired, blocked = Missions.Acquire(record)
    if not acquired then Message(group, blocked); return end
    if problem then Message(group, problem, 15) end
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
                "PLAYER STATISTICS: %s [%s]\nTotal Score: %d\nCareer Points: %d\nIntercept Score: %d\n" ..
                "Settled Missions: %d\nPrimary Success: %d\nRTB Success: %d\nRecovery Failure: %d",
                owner.name, owner.unitName, p.totalScore, p.careerPoints, p.interceptScore,
                p.missionCount, p.primarySuccessCount, p.rtbSuccessCount, p.recoveryFailureCount)
        else texts[#texts + 1] = "PLAYER STATISTICS: " .. owner.name .. "\nUCID unavailable; unscored." end
    end
    Message(group, table.concat(texts, "\n\n") .. "\nSession only; not saved.", 25)
end

local function Status(groupName)
    local group = GROUP:FindByName(groupName)
    local roster = Player.ForGroup(groupName)
    local records = Missions.ForGroup(groupName, roster)
    if #records == 0 then Message(group, "Intercept: Idle."); return end
    local texts = {}
    for _, record in ipairs(records) do
        local text = "Intercept: " .. record.state .. "\nWing: " .. record.groupName ..
            "\nLead reference: " .. record.owner.name
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
        if #records == 0 then Message(group, "Intercept: Idle."); return end
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
        if not record.spawn and Missions.IsActive(record) then
            record.spawnAt, record.state = nil, "ARMED"
        end
    else
        if groupName ~= record.groupName and #record.participants > 1 then
            Message(group, "Use Abort Sortie for your own pilot; wing abort is available in the original wing."); return
        end
        for _, p in ipairs(record.participants) do
            SettleParticipant(record, p, "ABORT", "Wing mission aborted. No reward.")
        end
        if not record.spawn then Message(group, "Intercept reservation cancelled.") end
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
                { "Generate Intercept", Generate }, { "Mission Status", Status },
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
    if record.state == "ARMED" or record.state == "TAKEOFF_DELAY" then
        if time < record.nextTakeoffCheck then return end
        record.nextTakeoffCheck = time + Config.takeoffCheckSeconds
        local controlling, airborne = Ready(record)
        if not controlling then
            Close(record)
            Message(record.group, "Intercept reservation cancelled. Player aircraft changed or unavailable.")
        elseif not airborne then
            if record.spawnAt then
                record.spawnAt, record.state = nil, "ARMED"
                Message(record.group, "Intercept countdown reset. Waiting for all registered pilots to take off.")
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
        if SelectLeader(record) and Intercept.AllGone(record.spawn) then PrimaryComplete(record, time) end
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
            if Intercept.RecordLoss(record.spawn, event) then PrimaryComplete(record, time) end
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
    return time + Config.pollSeconds
end

Safe("Initial player menu scan", nil, ScanPlayers)
timer.scheduleFunction(Tick, nil, timer.getTime() + Config.pollSeconds)
trigger.action.outText("Dynamic Training ready. Wing UCID scoring trial; session scores are not saved.", 10)
