-- Integration fixture invoked by Test-PersistenceInstall.ps1 in fresh Lua processes.
local root = assert(os.getenv("DCS_TRAINING_TEST_ROOT")):gsub("\\", "/") .. "/"
local phase = assert(os.getenv("DCS_TRAINING_TEST_PHASE"))
local scenario = dofile("scripts/Intercept-TestHarness.lua")
local Data = dofile("src/score_data.lua")
local path = root .. "DynamicTraining/scores.dat"
if phase == "recover" then
    local file = assert(io.open(path, "wb")); assert(file:write("corrupt fixture")); assert(file:close())
end
local s = scenario()
local h = { time = 0 }
local env = setmetatable({}, { __index = _G })
env.Sim = { isServer = function() return true end, getRealTime = function() return h.time end,
    setUserCallbacks = function(callbacks) h.callbacks = callbacks end }
env.lfs = { writedir = function() return root end,
    attributes = function(name, field)
        if name == root .. "DynamicTraining" then return field and "directory" or { mode = "directory" } end
        local file = io.open(name, "rb")
        if file then file:close(); return field and "file" or { mode = "file" } end
    end,
    mkdir = function() error("Fixture directory must already exist") end }
env.log = { ERROR = 1, WARNING = 2, INFO = 3, write = function(_, level, message)
    if level == 1 then error(message) end
end }
env.net = { dostring_in = function(state, code)
    assert(state == "server")
    local chunk = assert(loadstring(code)); setfenv(chunk, s.env); return chunk()
end }
local chunk = assert(loadfile("build/DynamicTrainingPersistenceHook.lua")); setfenv(chunk, env); chunk()
h.callbacks.onSimulationFrame()
if phase == "write" or phase == "restore" then
    if phase == "restore" then s:score(90) end
    s.player.airborne = true; s.generate(); s:complete(); s:event("Ejection", s.player)
    h.time = 1; h.callbacks.onSimulationFrame()
    s:score(phase == "write" and 90 or 180)
else
    assert(phase == "recover"); s:score(90)
end
local file = assert(io.open(path, "rb")); local text = assert(file:read("*a")); assert(file:close())
local data = Data.Decode(text)
assert(data.players["ucid-a"].totalScore == (phase == "restore" and 180 or 90))
s:command("Player Statistics"); s:lastMessageContains("Persistent scores saved.")
print("PASS: real disk " .. phase .. " in a fresh Lua process")
