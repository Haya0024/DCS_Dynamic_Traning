-- Build both mission and hook bundles before running with Lua 5.1.
local scenario = dofile("scripts/Intercept-TestHarness.lua")
local Data = dofile("src/score_data.lua")
local storeChunk = assert(loadfile("server/score_store.lua"))
setfenv(storeChunk, setmetatable({ ScoreData = Data }, { __index = _G }))
local Store = storeChunk()
local count = 0
local function test(name, run) run(); count = count + 1; print("PASS: " .. name) end
local function rejected(run) assert(not pcall(run), "Expected rejection") end
local function account(points)
    local p = { lastKnownName = "訓練 Pilot\n\"name\"" }
    for _, field in ipairs(Data.fields) do p[field] = 0 end
    p.totalScore, p.careerPoints, p.interceptScore = points or 0, points or 0, points or 0
    return p
end
local function data(points, revision)
    return { counter = 1, session = 1, revision = revision or 1, players = { ["ucid-a"] = account(points) } }
end
local function filesystem()
    local fs = { files = {}, directory = false }
    function fs.read(path)
        if fs.failRead == path then return nil, "denied" end
        if fs.files[path] == nil then return nil, "missing" end
        return fs.files[path]
    end
    function fs.write(path, text)
        if fs.failWrite then return false end
        fs.files[path] = fs.tamper and text:sub(1, -3) or text
        return true
    end
    function fs.rename(from, to)
        if fs.failPromotion and from:sub(-4) == ".tmp" and to:sub(-4) == ".dat" then return false end
        if not fs.files[from] or fs.files[to] then return false end
        fs.files[to], fs.files[from] = fs.files[from], nil
        return true
    end
    function fs.remove(path) fs.files[path] = nil; return true end
    return fs
end
local path = "saved/DynamicTraining/scores.dat"
local function hook(s, fs, startLoaded)
    local h = { time = 0, errors = {}, messages = {}, diagnostics = {}, commits = {}, server = true, calls = 0 }
    local env = setmetatable({}, { __index = _G })
    env.Sim = { isServer = function() return h.server end, getRealTime = function() return h.time end,
        setUserCallbacks = function(callbacks) h.callbacks = callbacks end }
    env.log = { ERROR = 1, WARNING = 2, INFO = 3, write = function(source, level, message)
        local messages = source == "DynamicTrainingPersistenceDiagnostic" and h.diagnostics or
            (level == 1 and h.errors or (message:match("^[A-Z]+_COMMITTED:") and h.commits or h.messages))
        messages[#messages + 1] = message
    end }
    -- Neither Hook nor mission manager sees the real SSE globals directly.
    -- DCS 2.9.18 regression: one nil slot is prepended and the last value lost.
    -- A single returned value therefore disappears; 2 values preserve it in #2.
    local manager = setmetatable({ a_do_script = function(inner)
        local run = assert(loadstring(inner)); setfenv(run, s.env)
        local first, second = run()
        if h.dispatchMode == "fixed" then return first, second end
        if h.dispatchMode == "lost" then return nil end
        return nil, first
    end }, { __index = _G })
    h.manager = manager
    env.net = { dostring_in = function(state, code)
        h.calls = h.calls + 1
        assert(manager.DynamicTrainingPersistence == nil)
        local chunk = assert(loadstring(code))
        if state == "mission" then
            setfenv(chunk, manager); local reply = chunk()
            assert(reply == nil or type(reply) == "string", "Manager must return only a scalar string")
            return reply or "", true
        end
        assert(state == "scripting"); return nil, nil -- Observed in DCS 2.9.30.
    end }
    env.lfs = { writedir = function() return "saved/" end,
        mkdir = function() fs.directory = true; return true end,
        dir = function(parent)
            if fs.failListing then error("listing denied") end
            local entries = { ".", ".." }
            for name in pairs(fs.files) do
                if name:sub(1, #parent + 1) == parent .. "/" then entries[#entries + 1] = name:sub(#parent + 2) end
            end
            local index = 0
            return function()
                index = index + 1
                if fs.failIteration and index == 2 then error("iteration failed") end
                return entries[index]
            end
        end,
        attributes = function(name, field)
            if fs.hiddenAttributes and name ~= "saved/DynamicTraining" then return nil end
            local mode = name == "saved/DynamicTraining" and fs.directory and "directory"
                or fs.files[name] ~= nil and "file" or nil
            if field then return mode end
            return mode and { mode = mode } or nil
        end }
    env.io = { open = function(name, mode)
        if mode == "rb" then
            local text, problem = fs.read(name)
            if not text then
                if fs.noErrno then return nil, problem end
                return nil, problem, problem == "missing" and 2 or 13
            end
            return { read = function(_, n) return text:sub(1, n) end,
                close = function() if not fs.noMethodResult then return true end end }
        end
        if fs.failWrite then return nil, "denied", 13 end
        return { write = function(_, text)
                local written = fs.write(name, text)
                if not written or not fs.noMethodResult then return written end
            end,
            flush = not fs.noFlushMethod and function()
                if fs.failFlush then return false end
                if not fs.noMethodResult then return true end
            end or nil,
            close = function()
                if fs.failClose then return false end
                if not fs.noMethodResult then return true end
            end }
    end }
    env.os = {
        rename = function(from, to)
            local moved = fs.rename(from, to)
            if not moved or not fs.noMethodResult then return moved end
        end,
        remove = function(name)
            local removed = fs.remove(name)
            if not removed or not fs.noMethodResult then return removed end
        end }
    local chunk = assert(loadfile("build/DynamicTrainingPersistenceHook.lua")); setfenv(chunk, env); chunk()
    if startLoaded ~= false then h.callbacks.onMissionLoadEnd() end
    function h:frame(time) self.time = time; self.callbacks.onSimulationFrame() end
    h.env = env
    return h
end
local function module(s, wanted)
    local callback = wanted == "Scoring" and s.env.DynamicTrainingPersistence.Initialize or s.timers[1].callback
    for i = 1, 100 do
        local name, value = debug.getupvalue(callback, i)
        if name == wanted then return value end
    end
    error("Missing module: " .. wanted)
end
local function start(s) s.player.airborne = true; s.generate() end
local function earn(s, safe)
    start(s); s:complete()
    if safe then s:land(s:base(), 10); for time = 11, 21 do s:tick(time) end
    else s:event("Ejection", s.player) end
end
local function statistics(s, fragment) s:command("Player Statistics"); s:lastMessageContains(fragment) end

test("schema round trips unicode names and rejects invalid, executable and truncated data", function()
    local original = data(150)
    local text = Data.Encode(original)
    assert(Data.Encode(Data.Decode(text)) == text)
    assert(Data.Decode(text).players["ucid-a"].lastKnownName == original.players["ucid-a"].lastKnownName)
    for _, bad in ipairs({ "return os.execute('bad')", text:sub(1, -2), text:gsub("150", "151", 1), "" }) do
        rejected(function() Data.Decode(bad) end)
    end
    original.players["ucid-a"].deathCount = -1; rejected(function() Data.Encode(original) end)
    original.players["ucid-a"].deathCount = 0.5; rejected(function() Data.Encode(original) end)
end)

test("storage writes verified primary and previous-good backup and reloads on restart", function()
    local fs = filesystem(); local store = Store.New(path, fs)
    local empty, source = store.Load(); assert(source == "new" and empty.counter == 0)
    store.Save(data(150)); store.Save(data(240, 2))
    assert(Store.New(path, fs).Load().players["ucid-a"].totalScore == 240)
    assert(Data.Decode(fs.files[path .. ".bak"]).players["ucid-a"].totalScore == 150)
end)

test("corrupt and missing primary recover backup; dual corruption cannot create empty scores", function()
    for _, missing in ipairs({ false, true }) do
        local fs = filesystem(); fs.files[path .. ".bak"] = Data.Encode(data(150))
        if not missing then fs.files[path] = "corrupt" end
        local restored, source = Store.New(path, fs).Load()
        assert(source == "backup" and restored.players["ucid-a"].totalScore == 150)
        fs.files[path .. ".bak"] = "corrupt too"
        rejected(function() Store.New(path, fs).Load() end)
        assert(fs.files[path .. ".bak"] == "corrupt too")
    end
end)

test("write failure, verification failure and Windows replacement failure retain old scores", function()
    for _, failure in ipairs({ "failWrite", "tamper", "failPromotion" }) do
        local fs = filesystem(); local store = Store.New(path, fs); store.Save(data(150))
        fs[failure] = true; rejected(function() store.Save(data(240, 2)) end)
        assert(store.Load().players["ucid-a"].totalScore == 150)
        fs[failure] = false; store.Save(data(240, 2))
        assert(store.Load().players["ucid-a"].totalScore == 240)
    end
end)

test("permission errors never masquerade as an empty new database", function()
    local fs = filesystem(); fs.failRead = path
    rejected(function() Store.New(path, fs).Load() end)
    assert(not fs.files[path])
end)

test("hook restores 150 across mission restart and keeps later 90 and death statistics", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs); h:frame(0)
    earn(s, true); statistics(s, "Persistence pending")
    h:frame(1); statistics(s, "Persistent scores saved.")
    s = scenario(); h = hook(s, fs); h:frame(0); s:score(150)
    assert(s.env.DynamicTrainingPersistence.Initialize(Data.Encode({ counter = 2, session = 2,
        revision = 0, players = { ["ucid-a"] = account(150) } })))
    s:score(150) -- Duplicate initialization does not re-add the baseline.
    earn(s, false); h:frame(1); s:score(240); statistics(s, "Death Count: 1")
    local saved = Data.Decode(fs.files[path])
    assert(saved.counter == 2 and saved.players["ucid-a"].missionCount == 2)
    assert(saved.players["ucid-a"].rtbSuccessCount == 1 and saved.players["ucid-a"].recoveryFailureCount == 1)
end)

test("hook first connecting after settlement merges the local delta once", function()
    local fs = filesystem(); fs.files[path] = Data.Encode(data(150))
    local s = scenario(); earn(s, false); s:score(90)
    local h = hook(s, fs); h:frame(0); s:score(240)
    h:frame(1); h:frame(2); s:score(240)
    assert(Data.Decode(fs.files[path]).players["ucid-a"].totalScore == 240)
end)

test("duplicate loss and snapshot retry cannot duplicate score or death count", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs); h:frame(0)
    earn(s, false); local payload = s.env.DynamicTrainingPersistence.ExportSnapshot()
    s:event("Dead", s.player); s:event("Crash", s.player)
    assert(s.env.DynamicTrainingPersistence.ExportSnapshot() == payload)
    h:frame(1); h:frame(2)
    local saved = Data.Decode(fs.files[path]).players["ucid-a"]
    assert(saved.totalScore == 90 and saved.missionCount == 1 and saved.deathCount == 1)
end)

test("stale acknowledgements cannot mark a newer settlement or another run saved", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs); h:frame(0)
    earn(s, false); h:frame(1)
    local old = Data.Decode(fs.files[path])
    s.generate(); s:complete(); s:event("Ejection", s.player)
    assert(s.env.DynamicTrainingPersistence.Acknowledge(old.session, old.revision))
    statistics(s, "Persistence pending")
    assert(not s.env.DynamicTrainingPersistence.Acknowledge(old.session + 1, old.revision + 1))
    assert(not s.env.DynamicTrainingPersistence.Acknowledge(old.session, old.revision + 99))
    h:frame(2); s:score(180); statistics(s, "Persistent scores saved.")
end)

test("flush and close errors leave scores unconfirmed until a successful retry", function()
    for _, flag in ipairs({ "failFlush", "failClose" }) do
        local fs = filesystem(); local s = scenario(); local h = hook(s, fs); h:frame(0)
        earn(s, false); fs[flag] = true; h:frame(1)
        statistics(s, "Persistence unavailable")
        assert(Data.Decode(fs.files[path]).players["ucid-a"] == nil)
        fs[flag] = false; h:frame(2); s:score(90); statistics(s, "Persistent scores saved.")
    end
end)

test("hook missing, bridge unavailable and disabled persistence remain session only", function()
    local s = scenario(); earn(s, false); statistics(s, "Session only")
    local fs = filesystem(); local h = hook(s, fs); h.env.net.dostring_in = nil; h:frame(0)
    assert(not fs.files[path] and #h.errors == 1); statistics(s, "Session only")
    s = scenario(); module(s, "Config").persistence.enabled = false
    -- Runtime already published the endpoint; Initialize still rejects disabled config.
    h = hook(s, fs); h:frame(0); assert(not module(s, "Scoring").sessionID)
    earn(s, false); statistics(s, "Session only; persistence disabled.")
end)

test("non-server hook does not access mission or write scores", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs)
    h.server = false; h.env.net.dostring_in = function() error("client must not invoke bridge") end
    h:frame(0); h.callbacks.onSimulationStop()
    assert(not fs.files[path] and #h.errors == 0)
end)

test("normal simulation stop flushes a settlement without waiting for the next frame", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs); h:frame(0)
    earn(s, false); h.callbacks.onSimulationStop()
    assert(Data.Decode(fs.files[path]).players["ucid-a"].totalScore == 90)
    statistics(s, "Persistent scores saved.")
end)

test("UCID-unknown sorties never add a synthetic saved account", function()
    local fs = filesystem(); local s = scenario(); s.netFailure = true
    local h = hook(s, fs); h:frame(0); earn(s, false); h:frame(1)
    assert(next(Data.Decode(fs.files[path]).players) == nil)
    statistics(s, "UCID unavailable; unscored.")
end)

test("all failure events increment loss statistic once; abort never increments it", function()
    for _, event in ipairs({ "Crash", "Dead", "PilotDead", "Ejection", "UnitLost" }) do
        local s = scenario(); start(s); s:event(event, s.player); s:event(event, s.player)
        statistics(s, "Death Count: 1"); statistics(s, "Settled Missions: 1")
    end
    local s = scenario(); start(s); s:command("Abort Mission"); statistics(s, "Death Count: 0")
end)

test("Immediate DEAD extra settlement persists score without duplicate mission or death statistics", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs); h:frame(0)
    local scoring = module(s, "Scoring")
    local owner = { ucid = "ucid-a", name = "Pilot", objectID = 10 }
    local main = { id = scoring.NextID("SEAD"), category = "SEAD", fullReward = 150,
        owner = owner, primaryCompletedAt = 1, failureEvent = "Ejection" }
    local extra = { id = scoring.NextID("DEAD"), category = "DEAD", fullReward = 150,
        owner = owner, primaryCompletedAt = 2, failureEvent = "Ejection", scoreOnly = true }
    scoring.Settle(main, "RTB_FAILURE", "Ejection"); scoring.Settle(extra, "RTB_FAILURE", "Ejection")
    h:frame(1)
    local p = Data.Decode(fs.files[path]).players["ucid-a"]
    assert(p.totalScore == 180 and p.seadScore == 90 and p.deadScore == 90)
    assert(p.missionCount == 1 and p.deathCount == 1)
end)

test("new mission namespaces differ and an old snapshot is rejected", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs); h:frame(0)
    start(s); local firstID = s:mission().id; s:event("Ejection", s.player); h:frame(1)
    local old = fs.files[path]
    s = scenario(); h = hook(s, fs); h:frame(0); start(s)
    assert(s:mission().id ~= firstID)
    s.env.DynamicTrainingPersistence.ExportSnapshot = function() return old end
    h:frame(1); assert(#h.errors == 1)
    assert(Data.Decode(fs.files[path]).session == 2)
end)

test("corrupt storage blocks persistence without overwriting or stopping gameplay", function()
    local fs = filesystem(); fs.files[path], fs.files[path .. ".bak"] = "broken", "also broken"
    local s = scenario(); local h = hook(s, fs); h:frame(0); h:frame(1)
    assert(fs.files[path] == "broken" and fs.files[path .. ".bak"] == "also broken" and #h.errors == 1)
    earn(s, false); s:score(90); statistics(s, "Persistence unavailable")
end)

test("failed hydration is transactional and retry does not partially add counters", function()
    local s = scenario(); earn(s, false)
    local baseline = data(9007199254740991, 0)
    rejected(function() s.env.DynamicTrainingPersistence.Initialize(Data.Encode(baseline)) end)
    s:score(90)
    baseline.players["ucid-a"] = account(150)
    assert(s.env.DynamicTrainingPersistence.Initialize(Data.Encode(baseline)))
    s:score(240)
end)

test("an idle healthy poll clears a transient bridge error without another settlement", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs); h:frame(0)
    earn(s, false); h:frame(1)
    local bridge = h.env.net.dostring_in
    h.env.net.dostring_in = function() error("temporary bridge failure") end
    h:frame(2)
    s.env.DynamicTrainingPersistence.SetError("temporary bridge failure")
    statistics(s, "Persistence unavailable")
    h.env.net.dostring_in = bridge; h:frame(3)
    statistics(s, "Persistent scores saved.")
    assert(Data.Decode(fs.files[path]).players["ucid-a"].totalScore == 90)
end)

test("separate hook, manager and SSE states connect through scalar slots without hook a_do_script", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs)
    assert(h.env.a_do_script == nil and h.env.DynamicTrainingPersistence == nil)
    assert(h.manager.DynamicTrainingPersistence == nil and type(h.manager.a_do_script) == "function")
    local bridge = h.env.net.dostring_in
    h.env.net.dostring_in = function(state, code)
        local reply = bridge(state, code)
        assert(type(reply) == "string")
        return reply, nil -- Older DCS string-only transport.
    end
    h:frame(0); assert(h.calls >= 4 and #h.messages == 1)
    earn(s, false); h:frame(1); h:frame(2)
    statistics(s, "Persistent scores saved.")
    assert(Data.Decode(fs.files[path]).players["ucid-a"].totalScore == 90)
    assert(#h.errors == 0 and #h.messages == 1)
end)

test("API denial logs once, creates no storage and reconnects after permission recovery", function()
    for _, mode in ipairs({ "denied", "exception", "falseStatus" }) do
        local fs = filesystem(); local s = scenario(); earn(s, false)
        local h = hook(s, fs); local bridge = h.env.net.dostring_in
        h.env.net.dostring_in = function()
            if mode == "exception" then error("not allowed") end
            if mode == "falseStatus" then return "DTBR1:D1", false end
            return nil, "mission state not allowed"
        end
        h:frame(0); h:frame(1)
        assert(#h.errors == 1 and not fs.files[path]); statistics(s, "Session only")
        h.env.net.dostring_in = bridge; h:frame(2); h:frame(3)
        statistics(s, "Persistent scores saved.")
        assert(Data.Decode(fs.files[path]).players["ucid-a"].totalScore == 90)
    end
end)

test("empty, untagged and malformed typed replies never become a successful connection", function()
    for _, reply in ipairs({ "", "true", "1", "return os.execute('bad')", "DTBR1:Nextra",
        "DTBR1:Btrue", "DTBR1:Dnan", "DTBR1:Dinf", "DTBR1:D1junk", "DTBR1:X", false }) do
        local fs = filesystem(); local s = scenario(); local h = hook(s, fs)
        h.env.net.dostring_in = function() return reply end
        h:frame(0); assert(#h.errors == 1 and not fs.files[path])
        if reply == "" then
            assert(h.errors[1]:find("replyType=string; replyBytes=0; status=nil", 1, true))
        end
        statistics(s, "Session only")
    end
end)

test("mission-side exceptions and unsupported replies are rejected and initialization safely retries", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs)
    local initialize = s.env.DynamicTrainingPersistence.Initialize
    s.env.DynamicTrainingPersistence.Initialize = function() error("hydration failed") end
    h:frame(0); assert(#h.errors == 1 and h.errors[1]:find("hydration failed", 1, true))
    s.env.DynamicTrainingPersistence.Initialize = initialize
    assert(not module(s, "Scoring").sessionID)
    h:frame(1)
    assert(Data.Decode(fs.files[path]).counter == 1)
    earn(s, false)
    local snapshot = s.env.DynamicTrainingPersistence.ExportSnapshot
    s.env.DynamicTrainingPersistence.ExportSnapshot = function() return {} end
    h:frame(2); statistics(s, "Persistence unavailable")
    assert(Data.Decode(fs.files[path]).players["ucid-a"] == nil)
    s.env.DynamicTrainingPersistence.ExportSnapshot = snapshot; h:frame(3)
    statistics(s, "Persistent scores saved.")
    assert(Data.Decode(fs.files[path]).players["ucid-a"].totalScore == 90)
end)

test("false acknowledgements cannot confirm a saved revision and recover without adding points", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs); h:frame(0)
    earn(s, false)
    local acknowledge = s.env.DynamicTrainingPersistence.Acknowledge
    s.env.DynamicTrainingPersistence.Acknowledge = function() return false end
    h:frame(1); statistics(s, "Persistence unavailable")
    assert(Data.Decode(fs.files[path]).players["ucid-a"].totalScore == 90)
    s.env.DynamicTrainingPersistence.Acknowledge = acknowledge; h:frame(2)
    statistics(s, "Persistent scores saved.")
    assert(Data.Decode(fs.files[path]).players["ucid-a"].totalScore == 90)
end)

test("missing endpoint diagnostics are deduplicated, data-free and recover without creating early storage", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs)
    local endpoint = s.env.DynamicTrainingPersistence
    s.env.DynamicTrainingPersistence = nil
    assert(#h.diagnostics == 2 and h.diagnostics[1]:find("HOOK_REGISTERED", 1, true))
    h:frame(0); h:frame(1)
    assert(#h.diagnostics == 4 and #h.errors == 0 and not fs.files[path])
    assert(h.diagnostics[3]:find("FIRST_SIMULATION_FRAME", 1, true))
    assert(h.diagnostics[4]:find("WAITING_ENDPOINT: protocol=nil", 1, true))
    assert(h.diagnostics[4]:find("endpoint=nil", 1, true) and h.diagnostics[4]:find("a_do_script=nil", 1, true))
    for _, message in ipairs(h.diagnostics) do assert(not message:find("ucid-a", 1, true)) end
    assert(h.env.a_do_script == nil)
    s.env.DynamicTrainingPersistence = endpoint
    h:frame(2); h:frame(3)
    assert(#h.diagnostics == 5 and h.diagnostics[5]:find("CONNECTED", 1, true))
    statistics(s, "Persistent scores saved."); assert(fs.files[path])
end)

test("diagnostics distinguish non-host and restart callback lifecycle without changing persistence", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs)
    h.server = false; h:frame(0); h:frame(1)
    assert(#h.diagnostics == 4 and h.diagnostics[4]:find("NOT_SERVER", 1, true))
    assert(h.calls == 0 and not fs.files[path] and #h.errors == 0)
    h.callbacks.onMissionLoadBegin(); h:frame(2)
    assert(#h.diagnostics == 5 and h.diagnostics[5]:find("MISSION_LOAD_BEGIN", 1, true))
    h.callbacks.onMissionLoadEnd(); h:frame(2)
    assert(#h.diagnostics == 8 and h.diagnostics[7]:find("FIRST_SIMULATION_FRAME", 1, true))
    h.server = true; h:frame(3)
    assert(#h.diagnostics == 9 and h.diagnostics[9]:find("CONNECTED", 1, true))
    statistics(s, "Persistent scores saved."); assert(Data.Decode(fs.files[path]).counter == 1)
end)

test("missing mission dispatcher cannot initialize storage and reconnects after recovery", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs)
    local dispatch = h.manager.a_do_script; h.manager.a_do_script = nil
    h:frame(0); h:frame(1)
    assert(#h.errors == 1 and h.errors[1]:find("a_do_script", 1, true))
    assert(not fs.files[path] and not module(s, "Scoring").sessionID)
    statistics(s, "Session only")
    h.manager.a_do_script = dispatch; h:frame(2)
    statistics(s, "Persistent scores saved.")
    assert(Data.Decode(fs.files[path]).counter == 1 and #h.messages == 1)
end)

test("shifted native slots discard a single result; trailing scalar preserves confirmation and snapshots", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs)
    local inner = 'bridgeProbe = true; return "DTBR1:D1"'
    local reply, accepted = h.env.net.dostring_in("mission", "return a_do_script(" .. string.format("%q", inner) .. ")")
    assert(accepted == true and reply == "" and s.env.bridgeProbe == true)
    assert(h.manager.bridgeProbe == nil and not fs.files[path])
    h:frame(0); earn(s, false); h:frame(1); h:frame(2)
    statistics(s, "Persistent scores saved.")
    assert(Data.Decode(fs.files[path]).players["ucid-a"].totalScore == 90)
    assert(#h.errors == 0 and #h.messages == 1)
end)

test("fixed and shifted dispatchers preserve all typed values; fully lost replies cannot initialize storage", function()
    for _, mode in ipairs({ "fixed", "shifted", "lost" }) do
        local fs = filesystem(); local s = scenario(); local h = hook(s, fs)
        h.dispatchMode = mode
        h:frame(0)
        if mode == "lost" then
            assert(#h.errors == 1 and not fs.files[path] and not module(s, "Scoring").sessionID)
            assert(h.errors[1]:find("DTBRIDGE_INVALID:first=nil;second=nil", 1, true))
            statistics(s, "Persistence unavailable")
            h.dispatchMode = "shifted"; h:frame(1)
        end
        local other = account(150)
        module(s, "Scoring").players["ucid-other"] = other
        earn(s, false); h:frame(2); h:frame(3)
        statistics(s, "Persistent scores saved.")
        local saved = Data.Decode(fs.files[path]); assert(saved.counter == 1)
        assert(saved.players["ucid-a"].totalScore == 90)
        assert(saved.players["ucid-other"].totalScore == 150 and
            saved.players["ucid-other"].lastKnownName == other.lastKnownName)
        assert(#h.messages == 1)
    end
end)

test("missing files with no numeric errno bootstrap safely and later restore without resetting scores", function()
    local fs = filesystem(); fs.noErrno = true
    local s = scenario(); local h = hook(s, fs); h:frame(0)
    assert(#h.errors == 0 and Data.Decode(fs.files[path]).counter == 1)
    earn(s, false); h:frame(1)
    s = scenario(); h = hook(s, fs); h:frame(0); s:score(90)
    assert(Data.Decode(fs.files[path]).counter == 2 and #h.errors == 0)
end)

test("unreadable existing primary cannot fall back to a backup or be mistaken for a missing file", function()
    for _, hidden in ipairs({ false, true }) do
        local fs = filesystem(); fs.noErrno, fs.hiddenAttributes = true, hidden
        local primary, backup = Data.Encode(data(240, 2)), Data.Encode(data(150))
        fs.files[path], fs.files[path .. ".bak"], fs.failRead = primary, backup, path
        local s = scenario(); local h = hook(s, fs); h:frame(0); h:frame(1)
        assert(#h.errors == 1 and h.errors[1]:find("phase=LOAD", 1, true))
        assert(not h.errors[1]:find("ucid-a", 1, true) and not h.errors[1]:find("DT_SCORE", 1, true))
        assert(fs.files[path] == primary and fs.files[path .. ".bak"] == backup)
        assert(not module(s, "Scoring").sessionID)
        fs.failRead = nil; h:frame(2); s:score(240)
    end
end)

test("failed or incomplete directory inspection blocks bootstrap and safely retries", function()
    for _, fault in ipairs({ "failListing", "failIteration" }) do
        local fs = filesystem(); fs.noErrno = true; fs[fault] = true
        local s = scenario(); local h = hook(s, fs); h:frame(0); h:frame(1)
        assert(#h.errors == 1 and h.errors[1]:find("directory inspection failed", 1, true))
        assert(not fs.files[path] and not module(s, "Scoring").sessionID)
        fs[fault] = false; h:frame(2)
        assert(Data.Decode(fs.files[path]).counter == 1)
    end
end)

test("native file operation exceptions close handles and never confirm partial writes", function()
    local Adapter = dofile("server/persistence_fs.lua")
    for _, fault in ipairs({ "read", "write", "flush", "lookup" }) do
        local closed = 0
        local file = { close = function() closed = closed + 1; return true end }
        for _, operation in ipairs({ "read", "write", "flush" }) do
            file[operation] = function()
                if operation == fault then error("native operation failed") end
                return operation == "read" and "contents" or true
            end
        end
        if fault == "lookup" then
            file.flush = nil
            setmetatable(file, { __index = function() error("native method lookup failed") end })
        end
        local fs = Adapter.New({ open = function() return file end },
            { attributes = function() return { mode = "file" } end }, {})
        if fault == "read" then rejected(function() fs.read(path) end)
        else assert(fs.write(path, "contents") == false) end
        assert(closed == 1)
    end
end)

test("unloaded and stopped frames do not access DCS or storage; teardown is a final-flush limitation", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs, false)
    h:frame(0); h:frame(1)
    assert(h.calls == 0 and #h.errors == 0 and not fs.files[path])
    h.callbacks.onMissionLoadBegin(); h:frame(2)
    assert(h.calls == 0)
    h.callbacks.onMissionLoadEnd(); h:frame(3)
    earn(s, false); h:frame(4)
    local saved = fs.files[path]
    s.env.DynamicTrainingPersistence = nil
    h.callbacks.onSimulationStop()
    local calls = h.calls
    h:frame(5); h:frame(6); h.callbacks.onSimulationStop()
    assert(h.calls == calls and fs.files[path] == saved and #h.errors == 0)
    assert(h.diagnostics[#h.diagnostics]:find("STOP_FLUSH_UNAVAILABLE", 1, true))
end)

test("restoration alone does not report saved and acknowledgement requires an attached matching run", function()
    local s = scenario(); local endpoint = s.env.DynamicTrainingPersistence
    assert(not endpoint.Acknowledge(nil, 0))
    local baseline = data(150, 0)
    baseline.counter = 2
    rejected(function() endpoint.Initialize(Data.Encode(baseline)) end)
    baseline.counter = 1
    assert(endpoint.Initialize(Data.Encode(baseline)))
    statistics(s, "Persistence pending")
    assert(not endpoint.Acknowledge(2, 0))
    assert(endpoint.Acknowledge(1, 0)); statistics(s, "Persistent scores saved.")
end)

test("lost initialize response retries the same committed run without remerging local settlements", function()
    local fs = filesystem(); fs.files[path] = Data.Encode(data(150))
    local s = scenario(); earn(s, false)
    local h = hook(s, fs); local bridge = h.env.net.dostring_in
    h.env.net.dostring_in = function(state, code)
        local reply, status = bridge(state, code)
        if code:find(".Initialize(", 1, true) then return "", true end
        return reply, status
    end
    h:frame(0); s:score(240)
    assert(#h.errors == 1 and h.errors[1]:find("phase=ATTACH", 1, true))
    h.env.net.dostring_in = bridge; h:frame(1); h:frame(2)
    s:score(240); statistics(s, "Persistent scores saved.")
    local saved = Data.Decode(fs.files[path]); assert(saved.counter == 2 and saved.players["ucid-a"].totalScore == 240)
end)

test("persistence initializes with no selected slot or player statistics command", function()
    local fs = filesystem(); fs.noErrno = true
    local s = scenario(); s.connections = {}; s.player.name = nil
    assert(table.concat(s.logs, "\n"):find("Persistence initialization pending.", 1, true))
    local h = hook(s, fs); h:frame(0)
    local saved = Data.Decode(fs.files[path]); assert(saved.counter == 1 and next(saved.players) == nil)
    assert(#h.errors == 0 and h.diagnostics[#h.diagnostics]:find("CONNECTED", 1, true))
end)

test("host file methods with no return or optional flush still require verified save and restore", function()
    for _, noFlush in ipairs({ false, true }) do
        local fs = filesystem(); fs.noErrno, fs.noMethodResult, fs.noFlushMethod = true, true, noFlush
        local s = scenario(); local h = hook(s, fs); h:frame(0)
        earn(s, false); h:frame(1); statistics(s, "Persistent scores saved.")
        assert(Data.Decode(fs.files[path]).players["ucid-a"].totalScore == 90)
        local compat = 0
        for _, message in ipairs(h.diagnostics) do if message:find("IO_COMPATIBILITY", 1, true) then compat = compat + 1 end end
        assert(compat == 1)
        s = scenario(); h = hook(s, fs); h:frame(0); s:score(90)
        assert(#h.errors == 0 and Data.Decode(fs.files[path]).counter == 2)
    end
end)

test("void-return writes that drop bytes or report explicit errors cannot become committed saves", function()
    for _, fault in ipairs({ "tamper", "failFlush", "failClose" }) do
        local fs = filesystem(); fs.noMethodResult, fs.noErrno = true, true
        local s = scenario(); local h = hook(s, fs); h:frame(0)
        local baseline = fs.files[path]; earn(s, false); fs[fault] = true; h:frame(1)
        assert(#h.errors == 1 and fs.files[path] == baseline)
        statistics(s, "Persistence unavailable")
        fs[fault] = false; h:frame(2)
        assert(Data.Decode(fs.files[path]).players["ucid-a"].totalScore == 90)
    end
end)

test("rename and remove require observed postconditions even with nil or misleading success replies", function()
    local Adapter = dofile("server/persistence_fs.lua")
    for _, mode in ipairs({ "void", "noMutation", "exception" }) do
        local contents = { [path .. ".tmp"] = "verified bytes" }
        local rawFiles = { open = function(name)
            if not contents[name] then return nil, "missing", 2 end
            return { read = function() return contents[name] end, close = function() end }
        end }
        local system = {
            rename = function(from, to)
                if mode == "exception" then error("rename denied") end
                if mode == "noMutation" then return true end
                contents[to], contents[from] = contents[from], nil
            end,
            remove = function(name)
                if mode == "exception" then error("remove denied") end
                if mode == "noMutation" then return true end
                contents[name] = nil
            end }
        local fs = Adapter.New(rawFiles, { attributes = function(name)
            return contents[name] and { mode = "file" } or nil
        end }, system)
        assert(fs.rename(path .. ".tmp", path) == (mode == "void"))
        local target = mode == "void" and path or path .. ".tmp"
        assert(fs.remove(target) == (mode == "void"))
        assert((contents[target] == nil) == (mode == "void"))
    end
end)

local function legacyFile()
    -- Independent version-1 fixture: the original 12 columns, no CAP field.
    local body = "DT_SCORE\t1\t7\t7\t3\nP\t756369642d61\t50696c6f74\t300\t300\t150\t150\t0\t2\t2\t2\t0\t0\t0\t0\n"
    local checksum = 0
    for i = 1, #body do checksum = (checksum * 31 + body:byte(i)) % 2147483647 end
    return body .. "END\t1\t" .. string.format("%.0f", checksum) .. "\n"
end
test("version one accounts migrate CAP to zero while preserving all original counters and canonical validation", function()
    local original = legacyFile(); local saved = Data.Decode(original)
    local p = saved.players["ucid-a"]
    assert(saved.counter == 7 and saved.revision == 3 and p.capScore == 0)
    assert(p.totalScore == 300 and p.interceptScore == 150 and p.seadScore == 150 and p.missionCount == 2)
    local updated = Data.Encode(saved); assert(updated:find("DT_SCORE\t2\t", 1, true) == 1)
    assert(Data.Decode(updated).players["ucid-a"].capScore == 0)
    rejected(function() Data.Decode(original:sub(1, -2)) end)
    rejected(function() Data.Decode(original:gsub("300", "301", 1)) end)
end)
test("CAP settlement persists separately after legacy restoration and survives a fresh hook session", function()
    local fs = filesystem(); fs.files[path] = legacyFile()
    local s = scenario(); s:addCAPZones(); local h = hook(s, fs); h:frame(0); s:score(300)
    s:command("Generate CAP"); local record = s:mission()
    s.player.airborne = true
    s.player.position = { x = record.capPlan.center.x, y = 6000, z = record.capPlan.center.y }
    for time = 1, 121 do s:tick(time) end
    s:complete(record.spawn.group); s:event("Ejection", s.player); h:frame(122)
    local data = Data.Decode(fs.files[path]); local p = data.players["ucid-a"]
    assert(data.counter == 8 and p.totalScore == 390 and p.capScore == 90 and p.interceptScore == 150 and p.seadScore == 150)
    s = scenario(); h = hook(s, fs); h:frame(0); s:score(390)
    statistics(s, "CAP Score: 90"); statistics(s, "Persistent scores saved.")
    assert(Data.Decode(fs.files[path]).counter == 9)
end)

test("unsupported future primary schemas cannot be overwritten or rolled back to an older backup", function()
    local body = Data.Encode(data(450)):match("^(.*\n)END\t%d+\t%d+\n$"):gsub("^DT_SCORE\t2\t", "DT_SCORE\t3\t")
    local checksum = 0
    for i = 1, #body do checksum = (checksum * 31 + body:byte(i)) % 2147483647 end
    local future = body .. "END\t1\t" .. string.format("%.0f", checksum) .. "\n"
    local fs = filesystem(); fs.files[path], fs.files[path .. ".bak"] = future, legacyFile()
    local store = Store.New(path, fs)
    rejected(store.Load); rejected(function() store.Save(data(150)) end)
    assert(fs.files[path] == future and fs.files[path .. ".bak"] == legacyFile())
end)

print(string.format("All %d persistence tests passed (simulated filesystem/DCS hooks).", count))
