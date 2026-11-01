local scenario = dofile('scripts/Intercept-TestHarness.lua')
local count = 0
local function test(name, run)
    run(); count = count + 1; print(string.format('PASS: APACHE-%02d %s', count, name))
end
local function module(s, wanted)
    local visited = {}
    local function find(callback)
        if visited[callback] then return end
        visited[callback] = true
        local callbacks = {}
        for i = 1, 100 do
            local name, value = debug.getupvalue(callback, i)
            if name == wanted then return value end
            if not name then break end
            if type(value) == 'function' then callbacks[#callbacks + 1] = value end
        end
        for _, nextCallback in ipairs(callbacks) do
            local value = find(nextCallback); if value then return value end
        end
    end
    return assert(find(s.timers[1].callback), 'Missing module: ' .. wanted)
end
local function apache()
    return scenario({ aircraftType = 'AH-64D_BLK_II', playerPosition = { x = 81000 - 8 * 1852, y = 0, z = 800 } })
end
local function accept(s)
    s:command('Task: Air Interdiction'); return assert(s:mission())
end
local function complete(s, r)
    for _, target in ipairs(r.interdictionPlan.targets) do
        target.unit.alive = false; s:event('Dead', target.unit)
    end
end
local function recover(s, unit)
    s:land(s:base(), s.time + 1, unit or s.player)
    local start = s.time + 1
    for time = start, start + 10 do s:tick(time) end
end
local function points(s, ucid)
    local value = module(s, 'Scoring').Get(ucid)
    return value and value.totalScore or 0
end

test('Apache exposes Air Interdiction and shared controls without fixed group names', function()
    local s = apache(); local commands = s.commands[s.player.group.name]
    for _, title in ipairs({'Task: Air Interdiction', 'Mission Status', 'Abort Mission', 'Player Statistics'}) do
        assert(commands[title])
    end
    for _, title in ipairs({'Task: Intercept', 'Task: CAP', 'Task: SEAD', 'Task: DEAD', 'Task: Strike'}) do
        assert(not commands[title])
    end
    local r = accept(s)
    assert(r.state == 'ACTIVE' and #r.participants == 1 and r.interdictionPlan.site.name == 'TPL_AI_01')
    assert(r.participants[1].owner.ucid == 'ucid-a'); s:assertClean()
end)

test('SOLO earns 150 only after all three assigned vehicles and safe BLUE airport recovery', function()
    local s = apache(); local r = accept(s); complete(s, r)
    assert(r.state == 'RTB_PENDING' and points(s, 'ucid-a') == 0)
    recover(s); assert(points(s, 'ucid-a') == 150 and not s:mission())
    assert(module(s, 'Scoring').Get('ucid-a').airInterdictionScore == 150); s:assertClean()
end)

test('post-objective aircraft loss awards 90 once and pre-objective loss awards zero', function()
    for _, done in ipairs({false, true}) do
        local s = apache(); local r = accept(s); if done then complete(s, r) end
        s:event('Crash', s.player); s:event('Dead', s.player); s:event('UnitLost', s.player)
        assert(points(s, 'ucid-a') == (done and 90 or 0) and not s:mission())
        assert(module(s, 'Scoring').Get('ucid-a').missionCount == 1); s:assertClean()
    end
end)

test('MP2 shares three targets but recovers and settles each aircraft independently', function()
    local s = apache(); s.wingman.position = {x = s.player.position.x, y = 0, z = 800}
    s:occupyWing(); s:tick(2); local r = accept(s); assert(#r.participants == 2)
    complete(s, r); recover(s)
    assert(points(s, 'ucid-a') == 150 and points(s, 'ucid-wing') == 0 and s:mission())
    recover(s, s.wingman)
    assert(points(s, 'ucid-wing') == 150 and not s:mission()); s:assertClean()
end)

test('human PLT and CPG on one aircraft both join and earn their own 150-point receipt', function()
    local s = apache(); s:addCrew(s.player, 'Gunner', 'ucid-cpg', 90); s:tick(2)
    local r = accept(s); assert(#r.participants == 2)
    assert(r.participants[1].owner.objectID == r.participants[2].owner.objectID)
    complete(s, r); recover(s)
    assert(points(s, 'ucid-a') == 150 and points(s, 'ucid-cpg') == 150 and not s:mission())
    s:event('Dead', s.player)
    assert(module(s, 'Scoring').Get('ucid-cpg').missionCount == 1); s:assertClean()
end)

test('MP2 with four human crew shares one mission and settles all four accounts', function()
    local s = apache(); s:occupyWing(); s:addCrew(s.player, 'CPG1', 'cpg1', 90)
    s:addCrew(s.wingman, 'CPG2', 'cpg2', 91); s:tick(2)
    local r = accept(s); assert(#r.participants == 4)
    complete(s, r); recover(s); assert(points(s, 'cpg1') == 150 and points(s, 'cpg2') == 0)
    recover(s, s.wingman)
    for _, id in ipairs({'ucid-a', 'ucid-wing', 'cpg1', 'cpg2'}) do assert(points(s, id) == 150) end
    assert(not s:mission()); s:assertClean()
end)

test('CPG-only aircraft is found even when getPlayers and GetPlayerName omit it', function()
    local s = apache(); s.player.name = nil; s.connections[10] = nil; s.players = {}
    s:addCrew(s.player, 'Gunner', 'ucid-cpg', 90)
    s.env.coalition.getGroups = function(side, category)
        assert(side == 2 and category == 1)
        return {{getUnits = function() return {s.player.raw} end}}
    end
    s:tick(2); local r = accept(s)
    assert(#r.participants == 1 and r.participants[1].owner.ucid == 'ucid-cpg')
    complete(s, r); recover(s); assert(points(s, 'ucid-cpg') == 150); s:assertClean()
end)

test('slot suffixes 1 and 2 are matched using ME unitId rather than runtime object ID', function()
    for _, seat in ipairs({'1', '2'}) do
        local s = apache(); s.player.slotID = 700; s.connections[10].slot = '700_' .. seat
        local r = accept(s); assert(r.participants[1].owner.ucid == 'ucid-a')
        complete(s, r); recover(s); assert(points(s, 'ucid-a') == 150); s:assertClean()
    end
end)

test('crew can exchange seats within the original aircraft without changing membership', function()
    local s = apache(); s:addCrew(s.player, 'Gunner', 'ucid-cpg', 90); s:tick(2)
    local r = accept(s); s.connections[10].slot, s.connections[90].slot = '10_2', '10'
    s.player.name = 'Gunner'; complete(s, r); recover(s)
    assert(points(s, 'ucid-a') == 150 and points(s, 'ucid-cpg') == 150); s:assertClean()
end)

test('late CPG joins do not gain participation or retrospective points', function()
    local s = apache(); local r = accept(s); s:addCrew(s.player, 'Late', 'late', 90); s:tick(2)
    assert(#r.participants == 1); complete(s, r); recover(s)
    assert(points(s, 'ucid-a') == 150 and points(s, 'late') == 0); s:assertClean()
end)

test('one aircraft loss settles both crew once without terminating the other MP2 aircraft', function()
    local s = apache(); s:occupyWing(); s:addCrew(s.player, 'Gunner', 'cpg', 90); s:tick(2)
    local r = accept(s); complete(s, r); s:event('Crash', s.player); s:event('UnitLost', s.player)
    assert(points(s, 'ucid-a') == 90 and points(s, 'cpg') == 90 and s:mission())
    recover(s, s.wingman); assert(points(s, 'ucid-wing') == 150 and not s:mission()); s:assertClean()
end)

test('an aborted pilot cannot mask loss settlement for their still-registered CPG', function()
    local s = apache(); s:addCrew(s.player, 'Gunner', 'cpg', 90); s:tick(2)
    local r = accept(s); s:command('Abort Sortie: Pilot [Player10]')
    complete(s, r); s:event('Crash', s.player)
    assert(points(s, 'ucid-a') == 0 and points(s, 'cpg') == 90 and not s:mission()); s:assertClean()
end)

test('crew UCID blockers survive moving to another Apache group', function()
    local s = apache(); s:addCrew(s.player, 'Gunner', 'cpg', 90); s:tick(2); local r = accept(s)
    local p = s:addPilot('Moved', 'cpg', 40); p.kind = 'AH-64D_BLK_II'; p.position = s.player.position
    s.connections[90] = nil; s:tick(4); s:command('Task: Air Interdiction', p)
    assert(not s:mission(p) and s:mission() == r and #s.spawns == 1)
    s:lastMessageContains('Wing assignment blocked'); s:assertClean()
end)

test('duplicate UCIDs across crew seats reject acceptance before reservation or spawn', function()
    local s = apache(); s:addCrew(s.player, 'Gunner', 'ucid-a', 90); s:tick(2)
    -- The existing group callback is revalidated even after invalid membership removes its menu.
    local roster, problem = module(s, 'Player').ForGroup(s.player.group.name)
    assert(not roster and problem:find('same UCID', 1, true))
    assert(not s:mission() and #s.spawns == 0); s:assertClean()
end)

test('missing crew UCID never borrows the pilot account or gains points after identification', function()
    local s = apache(); s:addCrew(s.player, 'Gunner', '', 90); s:tick(2)
    local r = accept(s); assert(#r.participants == 2 and not r.participants[2].owner.ucid)
    s.connections[90].ucid = 'late-identity'; complete(s, r); recover(s)
    assert(points(s, 'ucid-a') == 150 and points(s, 'late-identity') == 0); s:assertClean()
end)

test('network failure leaves a named Apache player explicitly unscored', function()
    local s = apache(); s.netFailure = true; local r = accept(s)
    assert(#r.participants == 1 and not r.participants[1].owner.ucid)
    complete(s, r); s.netFailure = false; recover(s)
    assert(points(s, 'ucid-a') == 0); s:assertClean()
end)

test('ambiguous network seat does not award either purported crew UCID', function()
    local s = apache(); s:addCrew(s.player, 'Other', 'other', 90, '10')
    local owners = module(s, 'Player').ForAircraft(s.player, s.player.group)
    for _, owner in ipairs(owners) do assert(not owner.ucid) end
    assert(points(s, 'ucid-a') == 0 and points(s, 'other') == 0); s:assertClean()
end)

test('unsupported seat suffixes and wrong aircraft slots do not join the roster', function()
    local s = apache(); s:addCrew(s.player, 'WrongSeat', 'wrong-seat', 90, '10_3')
    s:addCrew(s.player, 'OtherAircraft', 'wrong-unit', 91, '999_2'); s:tick(2)
    assert(#accept(s).participants == 1); s:assertClean()
end)

test('Apache accepts the inclusive 3 and 13 NM boundaries and rejects positions beyond them', function()
    for _, nm in ipairs({2.999, 3, 13, 13.001}) do
        local s = apache(); s.player.position.x = 81000 - nm * 1852
        s:command('Task: Air Interdiction')
        assert((s:mission() ~= nil) == (nm >= 3 and nm <= 13))
        if not s:mission() then
            assert(#s.spawns == 0 and not module(s, 'Missions').pilots['ucid-a'])
            s:lastMessageContains('within 3-13 NM')
        end
        s:assertClean()
    end
end)

test('out-of-range nearer routes are filtered before selecting the nearest two eligible routes', function()
    local s = apache(); local ai = module(s, 'AirInterdiction')
    for _, site in ipairs(ai.sites) do
        if site.name == 'TPL_AI_07' then site.point = {x = s.player.position.x + 2 * 1852, y = 800}
        elseif site.name == 'TPL_AI_08' then site.point = {x = s.player.position.x + 10 * 1852, y = 800} end
    end
    s.randomValues = {2}; assert(accept(s).interdictionPlan.site.name == 'TPL_AI_08')
    assert(s.randomCalls[1].maximum == 2); s:assertClean()
end)

test('both eligible nearest routes busy never falls back to a third', function()
    local s = apache(); local ai, missions = module(s, 'AirInterdiction'), module(s, 'Missions')
    for _, site in ipairs(ai.sites) do
        if site.name == 'TPL_AI_07' then site.point = {x = s.player.position.x + 9 * 1852, y = 800}
        elseif site.name == 'TPL_AI_08' then site.point = {x = s.player.position.x + 10 * 1852, y = 800} end
    end
    missions.interdictionSites.TPL_AI_01 = {}; missions.interdictionSites.TPL_AI_07 = {}
    s:command('Task: Air Interdiction'); assert(not s:mission() and #s.spawns == 0); s:assertClean()
end)

test('Hornet retains six legacy candidates with its separate 20-100 NM limits', function()
    local s = scenario(); local ai = module(s, 'AirInterdiction')
    for _, site in ipairs(ai.sites) do
        if site.name == 'TPL_AI_07' then site.point = {x = 100, y = 300} end
    end
    assert(accept(s).interdictionPlan.site.name == 'TPL_AI_01'); s:assertClean()
end)

test('a stale Hornet task callback rechecks Apache eligibility before acquiring a lock', function()
    local s = scenario(); local callback = s.commands[s.player.group.name]['Task: Intercept']
    s.player.kind = 'AH-64D_BLK_II'; callback()
    assert(not s:mission() and #s.spawns == 0); s:lastMessageContains('not available'); s:assertClean()
end)

test('Mission Status recalls only the published Apache briefing, then the coordinate-free result', function()
    local s = apache(); local r = accept(s); local text = s.messages[#s.messages].text
    assert(text:find('TARGET AREA: MGRS 37S BV 8100 0080', 1, true))
    assert(not text:find('LL DDM', 1, true) and #s.mgrsCalls == 1)
    assert(s.mgrsCalls[1].x == r.interdictionPlan.site.point.x and s.mgrsCalls[1].z == r.interdictionPlan.site.point.y)
    s.env.COORDINATE.ToStringMGRS = function() error('Status must use the published coordinate') end
    s:command('Mission Status'); assert(s.messages[#s.messages].text == text)
    complete(s, r); s:command('Mission Status')
    assert(not s.messages[#s.messages].text:find('TARGET AREA', 1, true)); s:assertClean()
end)

test('unverified seats have independent non-scoring receipts on the same aircraft', function()
    local s = apache(); s.connections[10].ucid = ''; s:addCrew(s.player, 'Gunner', '', 90); s:tick(2)
    local r = accept(s); complete(s, r)
    s:command('Abort Sortie: Pilot [Player10]'); recover(s)
    assert(r.participants[1].receipt.result == 'ABORT' and r.participants[2].receipt.result == 'RTB_SUCCESS')
    assert(not r.participants[1].receipt.scored and not r.participants[2].receipt.scored); s:assertClean()
end)

test('bundled MOOSE MGRS formatting keeps zone, square, leading zeroes and truncates each axis to four digits', function()
    local file = assert(io.open('vendor/MOOSE/Moose.lua', 'rb')); local source = file:read('*a'); file:close()
    source = source:gsub('\r\n', '\n')
    local formatter = assert(source:match('(UTILS%.tostringMGRS = function.-)\nend')) .. '\nend'
    local converter = assert(source:match('(function COORDINATE:ToStringMGRS.-)\n  end')) .. '\n  end'
    local grid
    local env = setmetatable({UTILS = {}, COORDINATE = {}, _SETTINGS = {MGRS_Accuracy = 5}, coord = {
        LOtoLL = function(p) assert(p.x == 123 and p.z == 456); return 34, 36 end,
        LLtoMGRS = function(lat, lon) assert(lat == 34 and lon == 36); return grid end
    }}, {__index = _G})
    setfenv(assert(loadstring(formatter .. '\n' .. converter)), env)()
    local object = {GetVec3 = function() return {x = 123, y = 0, z = 456} end}
    for _, case in ipairs({{123, 5432, '0012 0543'}, {12349, 56789, '1234 5678'}, {99999, 0, '9999 0000'}}) do
        grid = {UTMZone = '37S', MGRSDigraph = 'BV', Easting = case[1], Northing = case[2]}
        assert(env.COORDINATE.ToStringMGRS(object, {MGRS_Accuracy = 4}) == 'MGRS 37S BV ' .. case[3])
    end
end)

test('Apache coordinate conversion failure releases the Wing and route before spawning', function()
    local s = apache(); s.env.COORDINATE.ToStringMGRS = function() error('conversion unavailable') end
    s:command('Task: Air Interdiction')
    assert(not s:mission() and #s.spawns == 0 and next(module(s, 'Missions').interdictionSites) == nil)
    assert(not module(s, 'Missions').pilots['ucid-a']); s:lastMessageContains('ERROR: Air Interdiction setup failed.')
end)

print(string.format('All %d Apache tests passed (simulated DCS/MOOSE).', count))
