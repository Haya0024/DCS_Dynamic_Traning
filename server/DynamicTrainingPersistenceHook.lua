-- Build-PersistenceHook.ps1 prepends data, adapters and transaction service.
local control, hooks = Sim or DCS, {}
local loaded, nextPoll, lastError, diagnosticState, frameSeen = false, 0, nil, nil, false
local function diagnostic(message)
    log.write("DynamicTrainingPersistenceDiagnostic", log.INFO, message)
end
local function transition(state, detail)
    if state ~= diagnosticState then diagnostic(state .. ": " .. detail); diagnosticState = state end
end
local bridge = MissionBridge.New(net)
local fs = PersistenceFS.New(io, lfs, os, diagnostic)
local service = PersistenceService.New(bridge, fs, lfs.writedir() .. "DynamicTraining", {
    transition = transition,
    info = function(message) log.write("DynamicTrainingPersistence", log.INFO, message) end,
    warning = function(message) log.write("DynamicTrainingPersistence", log.WARNING, message) end
})
local function safePoll()
    local ok, result = pcall(service.Poll)
    if ok then
        if result then lastError = nil end
        return
    end
    local message = "phase=" .. service.phase .. "; " .. tostring(result)
    if message ~= lastError then
        log.write("DynamicTrainingPersistence", log.ERROR, message)
        lastError = message
    end
    pcall(bridge.SetError)
end
function hooks.onMissionLoadBegin()
    loaded, nextPoll, lastError, diagnosticState, frameSeen = false, 0, nil, nil, false
    service.Reset()
    diagnostic("MISSION_LOAD_BEGIN: Persistence connection state reset.")
end
function hooks.onMissionLoadEnd()
    loaded = true
    diagnostic("MISSION_LOAD_END: Persistence polling enabled.")
end
function hooks.onSimulationFrame()
    if not loaded then return end
    if not frameSeen then diagnostic("FIRST_SIMULATION_FRAME: Persistence callback received."); frameSeen = true end
    if not control.isServer() then transition("NOT_SERVER", "Persistence only runs on the host."); return end
    local time = control.getRealTime()
    if time >= nextPoll then nextPoll = time + 1; safePoll() end
end
function hooks.onSimulationStop()
    if not loaded then return end
    loaded = false -- Stop/menu frames cannot contact the destroyed SSE or start a run.
    if not control.isServer() then diagnostic("STOPPED: Host unavailable; prior saves preserved."); return end
    if not service.attached then diagnostic("STOPPED: No attached session to flush."); return end
    local ok, result = pcall(service.Poll)
    if not ok or not result then
        -- DCS can destroy SSE before Stop. This is a final-flush limitation,
        -- not a new permission failure; previously committed saves remain.
        diagnostic("STOP_FLUSH_UNAVAILABLE: phase=" .. service.phase .. "; lastCommittedRevision=" ..
            string.format("%.0f", service.committed))
    else diagnostic("STOPPED: Final snapshot and acknowledgement confirmed.") end
end
control.setUserCallbacks(hooks)
diagnostic("HOOK_REGISTERED: control=" .. (Sim and "Sim" or "DCS") ..
    "; net.dostring_in=" .. type(net and net.dostring_in) .. "; transport=" .. MissionBridge.description)
