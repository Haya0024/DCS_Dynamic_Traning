-- Cosmetic overlay boundary tests; existing gameplay suites remain unchanged.
local count = 0
local function test(name, callback)
    callback(); count = count + 1; print("PASS: " .. name)
end
local function read(path)
    local file = assert(io.open(path, "rb")); local text = file:read("*a"); file:close(); return text
end
-- Exercise the allocator actually shipped in MOOSE, not a second implementation.
local allocator = assert(read("vendor/MOOSE/Moose.lua"):match("function UTILS.GetMarkID%(%)%s*(.-)\nend"))
local function base(name, side, category)
    local b = { name = name, side = side or 2, category = category or 0,
        center = { x = 1000, y = 2000 } }
    function b:GetName() return self.name end
    function b:GetCoalition() if self.fail then error("observation failed") end; return self.side end
    function b:GetAirbaseCategory() return self.category end
    function b:GetVec2() return self.center end
    function b:GetVec3() error("Raw DCS runway threshold must not be used") end
    return b
end
local function fixture(bases)
    local s = { bases = bases or {}, active = {}, calls = {}, removed = {}, logs = {} }
    local e = setmetatable({}, { __index = _G })
    s.env = e
    e.Config = dofile("src/config.lua")
    e.coalition = { side = { BLUE = 2, RED = 1, NEUTRAL = 0 } }
    e.Airbase = { Category = { AIRDROME = 0, HELIPAD = 1, SHIP = 2 } }
    e.AIRBASE = { GetAllAirbases = function()
        if s.enumerationFailure then error("enumeration failed") end
        return s.bases
    end }
    e.UTILS = { _MarkID = 1 }
    e.UTILS.GetMarkID = setfenv(assert(loadstring(allocator)), e)
    e.COORDINATE = { NewFromVec2 = function(_, v)
        return { GetVec3 = function() return { x = v.x, y = 125, z = v.y } end }
    end }
    e.env = { info = function(text) s.logs[#s.logs + 1] = text end }
    local function draw(kind, ...)
        local args = { ... }
        assert(args[1] == 2, "Drawing must be BLUE only")
        assert(not s.active[args[2]], "Drawing ID collision")
        s.calls[#s.calls + 1] = { kind = kind, args = args }
        s.active[args[2]] = s.calls[#s.calls]
        -- Simulate partial creation followed by API failure as well as success.
        if s.failDraw == kind then error(kind .. " failed after creation") end
    end
    e.trigger = { action = {
        circleToAll = function(...) draw("circle", ...) end,
        textToAll = function(...) draw("text", ...) end,
        removeMark = function(id)
            if s.failRemove == id then error("cleanup failed") end
            s.removed[#s.removed + 1] = id; s.active[id] = nil
        end
    } }
    function s:load()
        self.overlay = setfenv(assert(loadfile("src/map_overlay.lua")), e)()
    end
    function s:refresh() return self.overlay.RefreshFriendlyAirbases() end
    function s:size() local n = 0; for _ in pairs(self.active) do n = n + 1 end; return n end
    function s:text(name)
        for _, d in pairs(self.active) do
            if d.kind == "text" and d.args[8] == "BLUE AIRBASE\n" .. name and
                d.args[4] == e.Config.mapOverlay.textColor then return d end
        end
    end
    s:load(); return s
end

test("BLUE land base: centered Circle, Text south offset, signatures, colors and read-only", function()
    local s = fixture({ base("Any runtime airbase") }); assert(s:refresh()); assert(s:size() == 2)
    local circle, text = s.calls[1].args, s.calls[2].args
    assert(circle[3].x == 1000 and circle[3].z == 2000 and circle[3].y == 125)
    assert(circle[4] == 2500 and circle[7] == 1 and circle[8] == true and circle[9] == "")
    assert(circle[5][3] > circle[5][1] and circle[6][4] == 0.04)
    assert(text[3].x == circle[3].x - 1000 and text[3].y == circle[3].y and text[3].z == circle[3].z)
    assert(text[6] == 16 and text[7] == true)
    assert(text[5][4] == 0 and s:text("Any runtime airbase"))
    assert(text[4][1] == 0.35 and text[4][2] == 0.7 and text[4][3] == 1 and text[4][4] == 1)
end)
test("RED airbase excluded", function()
    local s = fixture({ base("Red", 1) }); assert(s:refresh()); assert(s:size() == 0)
end)
test("Neutral airbase excluded", function()
    local s = fixture({ base("Neutral", 0) }); assert(s:refresh()); assert(s:size() == 0)
end)
test("Carrier and other ship excluded by category regardless of name", function()
    local s = fixture({ base("Incirlik", 2, 2), base("Non-carrier ship", 2, 2) })
    assert(s:refresh()); assert(s:size() == 0)
end)
test("FARP, helipad and MOOSE-corrected heliport excluded", function()
    local flagged = base("Looks like land", 2, 0); flagged.isHelipad = true
    local ship = base("Flagged ship", 2, 0); ship.isShip = true
    local s = fixture({ base("FARP", 2, 1), base("Helipad", 2, 1), flagged, ship })
    assert(s:refresh()); assert(s:size() == 0)
end)
test("Multiple bases have unique IDs shared with existing/future MOOSE marks", function()
    local s = fixture({ base("One"), base("Two"), base("Three") })
    s.env.UTILS._MarkID = 1100000
    local before = s.env.UTILS.GetMarkID(); s.active[before] = { kind = "foreign" }
    assert(s:refresh()); assert(s:size() == 7)
    for _, d in ipairs(s.calls) do assert(d.args[2] > before) end
    local after = s.env.UTILS.GetMarkID(); assert(not s.active[after])
    assert(s:text("One") and s:text("Two") and s:text("Three"))
end)
test("Refresh removes only owned drawings without duplication or ID reuse", function()
    local s = fixture({ base("One"), base("One") }); s.active[42] = { kind = "foreign" }
    assert(s:refresh()); local last = s.env.UTILS._MarkID
    assert(s:refresh()); assert(s:size() == 3 and s.active[42] and #s.removed == 2)
    assert(s.calls[3].args[2] > last)
end)
test("Module reinitialization keeps ownership and safely refreshes", function()
    local s = fixture({ base("One") }); assert(s:refresh()); s:load(); assert(s:refresh())
    assert(s:size() == 2 and #s.removed == 2)
end)
test("Explicit refresh reflects coalition changes including newly BLUE Tiyas", function()
    local old, tiyas = base("Old"), base("Tiyas", 1)
    local s = fixture({ old, tiyas }); assert(s:refresh()); assert(not s:text("Tiyas"))
    old.side, tiyas.side = 1, 2; assert(s:refresh())
    assert(s:size() == 2 and not s:text("Old") and s:text("Tiyas"))
end)
test("Empty BLUE list removes previous overlay", function()
    local s = fixture({ base("One") }); assert(s:refresh()); s.bases = {}
    assert(s:refresh()); assert(s:size() == 0)
end)
test("Enumeration failure preserves current drawings without stopping gameplay", function()
    local s = fixture({ base("One") }); assert(s:refresh()); s.enumerationFailure = true
    assert(s:refresh() == false and s:size() == 2 and #s.removed == 0)
end)
test("Bad airbase observation is isolated from other bases", function()
    local bad = base("Bad"); bad.fail = true
    local invalid = base("Invalid"); invalid.center = nil
    local s = fixture({ bad, invalid, base("Good") }); assert(s:refresh())
    assert(s:size() == 2 and s:text("Good"))
end)
test("Partial Text failure rolls back both owned drawings", function()
    local s = fixture({ base("One") }); s.failDraw = "text"
    assert(s:refresh() == false and s:size() == 0 and #s.removed == 2)
    s.failDraw = nil; assert(s:refresh()); assert(s:size() == 2)
end)
test("Partial Circle failure rolls back the allocated ID", function()
    local s = fixture({ base("One") }); s.failDraw = "circle"
    assert(s:refresh() == false and s:size() == 0 and #s.removed == 1)
end)
test("Cleanup failure retains ownership and blocks duplicate creation until retry", function()
    local s = fixture({ base("One") }); assert(s:refresh()); s.failRemove = s.calls[1].args[2]
    assert(s:refresh() == false and #s.calls == 2 and s:size() == 1)
    s.failRemove = nil; assert(s:refresh()); assert(s:size() == 2)
end)
test("Missing drawing API safely skips overlay", function()
    local s = fixture({ base("One") }); s.env.trigger.action.textToAll = nil
    assert(s:refresh() == false and #s.calls == 0)
end)
test("Failed rollback is retained and cleaned during next refresh", function()
    local s = fixture({ base("One") }); s.failDraw = "text"
    s.failRemove = s.env.Config.mapOverlay.minimumDrawingID
    assert(s:refresh() == false and s:size() == 1)
    s.failDraw, s.failRemove = nil, nil
    assert(s:refresh()); assert(s:size() == 2)
end)
test("Bundled startup initializes once; regular mission ticks do not redraw", function()
    local scenario = dofile("scripts/Intercept-TestHarness.lua")
    local s = scenario()
    local f = fixture({ base("Startup") })
    f.env.trigger.action.outText = s.env.trigger.action.outText
    for _, key in ipairs({ "AIRBASE", "Airbase", "UTILS", "COORDINATE", "trigger" }) do s.env[key] = f.env[key] end
    s.env.DynamicTrainingMapOverlayState = nil
    s.env.DynamicTrainingRuntime = nil -- Start with Drawing APIs installed in the harness.
    s.reload(); assert(#f.calls == 2, table.concat(s.logs, "\n"))
    s:tick(2); s:tick(20); assert(#f.calls == 2)
    s.reload(); assert(#f.calls == 2 and f:size() == 2 and #f.removed == 0)
    s:assertClean()
end)
print(string.format("All %d MapOverlay tests passed.", count))
