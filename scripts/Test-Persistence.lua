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
local function hook(s, fs)
    local h = { time = 0, errors = {}, server = true }
    local env = setmetatable({}, { __index = _G })
    env.Sim = { isServer = function() return h.server end, getRealTime = function() return h.time end,
        setUserCallbacks = function(callbacks) h.callbacks = callbacks end }
    env.log = { ERROR = 1, WARNING = 2, write = function(_, _, message) h.errors[#h.errors + 1] = message end }
    env.a_do_script = function(code)
        local chunk = assert(loadstring(code)); setfenv(chunk, s.env); return chunk()
    end
    env.lfs = { writedir = function() return "saved/" end,
        mkdir = function() fs.directory = true; return true end,
        attributes = function(name, field)
            local mode = name == "saved/DynamicTraining" and fs.directory and "directory"
                or fs.files[name] ~= nil and "file" or nil
            if field then return mode end
            return mode and { mode = mode } or nil
        end }
    env.io = { open = function(name, mode)
        if mode == "rb" then
            local text, problem = fs.read(name)
            if not text then return nil, problem, problem == "missing" and 2 or 13 end
            return { read = function(_, n) return text:sub(1, n) end, close = function() return true end }
        end
        if fs.failWrite then return nil, "denied", 13 end
        return { write = function(_, text) return fs.write(name, text) end,
            flush = function() return not fs.failFlush end, close = function() return not fs.failClose end }
    end }
    env.os = { rename = fs.rename, remove = fs.remove }
    local chunk = assert(loadfile("build/DynamicTrainingPersistenceHook.lua")); setfenv(chunk, env); chunk()
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
    local fs = filesystem(); local h = hook(s, fs); h.env.a_do_script = nil; h:frame(0)
    assert(not fs.files[path] and #h.errors == 1); statistics(s, "Session only")
    s = scenario(); module(s, "Config").persistence.enabled = false
    -- Runtime already published the endpoint; Initialize still rejects disabled config.
    h = hook(s, fs); h:frame(0); assert(not module(s, "Scoring").sessionID)
    earn(s, false); statistics(s, "Session only; persistence disabled.")
end)

test("non-server hook does not access mission or write scores", function()
    local fs = filesystem(); local s = scenario(); local h = hook(s, fs)
    h.server = false; h.env.a_do_script = function() error("client must not invoke bridge") end
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
    local bridge = h.env.a_do_script
    h.env.a_do_script = function() error("temporary bridge failure") end
    h:frame(2)
    s.env.DynamicTrainingPersistence.SetError("temporary bridge failure")
    statistics(s, "Persistence unavailable")
    h.env.a_do_script = bridge; h:frame(3)
    statistics(s, "Persistent scores saved.")
    assert(Data.Decode(fs.files[path]).players["ucid-a"].totalScore == 90)
end)

print(string.format("All %d persistence tests passed (simulated filesystem/DCS hooks).", count))
