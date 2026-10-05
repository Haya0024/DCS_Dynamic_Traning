-- Build-PersistenceHook.ps1 prepends ScoreData and ScoreStore.
local control = Sim or DCS
local hooks = {}
local store, bootstrap, session, committed = nil, nil, nil, 0
local nextPoll, lastError, attached = 0, nil, false
local function report(message)
    if message ~= lastError then
        log.write("DynamicTrainingPersistence", log.ERROR, message)
        lastError = message
    end
end
local function mission(code)
    assert(net and type(net.dostring_in) == "function",
        "DCS net.dostring_in unavailable; configure Config/autoexec.cfg: userhooks -> server, then restart DCS")
    -- The hook and mission have different Lua states. DCS's older bridge only
    -- returns strings, so use a tagged scalar reply on both old and new APIs.
    -- Never loadstring the reply or expose filesystem APIs to mission scripts.
    local wrapped = [[local ok, value = pcall(function()
]] .. code .. "\n" .. [[end)
if not ok then return "DTBR1:E" .. tostring(value) end
local kind = type(value)
if kind == "nil" then return "DTBR1:N" end
if kind == "boolean" then return value and "DTBR1:B1" or "DTBR1:B0" end
if kind == "number" then return "DTBR1:D" .. tostring(value) end
if kind == "string" then return "DTBR1:S" .. value end
return "DTBR1:EUnsupported bridge result type: " .. kind]]
    local reply, problem = net.dostring_in("server", wrapped)
    assert(type(reply) == "string" and reply:sub(1, 6) == "DTBR1:",
        "DCS mission bridge rejected/invalid reply; check autoexec.cfg userhooks -> server: " .. tostring(problem))
    local tag, value = reply:sub(7, 7), reply:sub(8)
    if tag == "N" and value == "" then return nil end
    if tag == "B" and (value == "1" or value == "0") then return value == "1" end
    if tag == "D" then
        local number = tonumber(value)
        assert(number and number == number and number ~= math.huge and number ~= -math.huge,
            "Invalid numeric bridge reply")
        return number
    end
    if tag == "S" then return value end
    if tag == "E" then error("Mission persistence bridge: " .. value) end
    error("Invalid typed mission bridge reply")
end
local fs = {}
function fs.read(path)
    if not lfs.attributes(path) then
        -- attributes can also fail on permissions. io's error code distinguishes
        -- a genuinely absent file from an inaccessible existing one.
        local file, problem, code = io.open(path, "rb")
        if not file then return nil, code == 2 and "missing" or problem end
        file:close()
    end
    local file, problem = io.open(path, "rb")
    if not file then return nil, problem end
    local text, readError = file:read(4 * 1024 * 1024 + 1)
    local closed = file:close()
    assert(closed and not readError, "Score read/close failed")
    return text or ""
end
function fs.write(path, text)
    local file = io.open(path, "wb")
    if not file then return false end
    local ok = file:write(text)
    local flushed = ok and file:flush()
    local closed = file:close()
    return ok and flushed and closed and true or false
end
fs.rename, fs.remove = os.rename, os.remove
local function poll()
    if not control.isServer() then return end
    if mission("return DynamicTrainingPersistence and DynamicTrainingPersistence.protocol") ~= 1 then return end
    if not store then
        local directory = lfs.writedir() .. "DynamicTraining"
        assert(lfs.attributes(directory, "mode") == "directory" or lfs.mkdir(directory), "Cannot create score directory")
        store = ScoreStore.New(directory .. "/scores.dat", fs)
    end
    if not bootstrap then
        local data, source = store.Load()
        assert(data.counter < 9007199254740991, "Score run counter exhausted")
        data.counter = data.counter + 1
        data.session, data.revision = data.counter, 0
        store.Save(data) -- Commit the unique namespace before publishing it.
        bootstrap, session, committed = ScoreData.Encode(data), data.session, 0
        if source == "backup" then log.write("DynamicTrainingPersistence", log.WARNING, "Recovered score backup") end
    end
    if not attached then
        local initialized = mission("return DynamicTrainingPersistence.Initialize(" .. string.format("%q", bootstrap) .. ")")
        assert(initialized == true, "Persistence initialization rejected")
        attached = true
        log.write("DynamicTrainingPersistence", log.INFO, "Connected via net.dostring_in(server)")
    end
    local payload = mission("return DynamicTrainingPersistence.ExportSnapshot()")
    assert(type(payload) == "string", "Persistence snapshot unavailable")
    if payload ~= "" then
        local data = ScoreData.Decode(payload)
        assert(data.session == session and data.counter == session, "Stale score session rejected")
        if data.revision > committed then
            store.Save(data)
            committed = data.revision
        end
    end
    -- Healthy idle polls also clear a transient bridge error. Only the last
    -- committed revision is acknowledged, never a pending/newer snapshot.
    assert(mission(string.format("return DynamicTrainingPersistence.Acknowledge(%.0f, %.0f)",
        session, committed)) == true, "Persistence acknowledgement rejected")
    lastError = nil
end
local function safePoll()
    local ok, problem = pcall(poll)
    if not ok then
        report(tostring(problem))
        pcall(mission, 'if DynamicTrainingPersistence then DynamicTrainingPersistence.SetError("Storage unavailable") end')
    end
end
function hooks.onMissionLoadBegin()
    -- The stop callback normally flushes first. Do not carry one mission's
    -- namespace or acknowledgement into the next mission environment.
    store, bootstrap, session, committed, nextPoll, lastError, attached = nil, nil, nil, 0, 0, nil, false
end
function hooks.onSimulationFrame()
    local time = control.getRealTime()
    if time >= nextPoll then nextPoll = time + 1; safePoll() end
end
function hooks.onSimulationStop() safePoll() end
control.setUserCallbacks(hooks)
