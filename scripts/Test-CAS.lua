local scenario = dofile('scripts/Intercept-TestHarness.lua')
local count = 0
local function test(name, run) run(); count = count + 1; print(string.format('PASS: CAS-%02d %s', count, name)) end
local function module(s, wanted)
    local visited = {}
    local function find(fn)
        if visited[fn] then return end; visited[fn] = true
        for i = 1, 100 do
            local name, value = debug.getupvalue(fn, i); if not name then break end
            if name == wanted then return value end
            if type(value) == 'function' then local result = find(value); if result then return result end end
        end
    end
    return assert(find(s.timers[1].callback), wanted)
end
local function apache(options)
    options = options or {}; options.aircraftType = 'AH-64D_BLK_II'
    options.playerPosition = { x = 81000 - 8 * 1852, y = 0, z = 800 }
    return scenario(options)
end
local function accept(s, code, player)
    s:command('Laser ' .. (code or 1688), player); return assert(s:mission(player))
end
local function request(s, player) s:command('Request laser', player) end
local function kill(s, unit) unit.alive = false; unit.life = 0; s:event('Dead', unit) end
local function complete(s, r) for _, t in ipairs(r.casPlan.targets) do kill(s, t.unit) end end
local function recover(s, unit)
    unit = unit or s.player; s:land(s:base(), s.time + 1, unit); unit.position.y = 0
    local start = s.time + 1; for t = start, start + 10 do
        if s.rows then assert(s.env.DynamicTrainingPlayers.Update(s.rows)) end
        s:tick(t)
    end
end
local function clean(s)
    assert(next(module(s, 'Missions').casSites) == nil and next(module(s, 'Missions').jtacSlots) == nil)
    for _, g in ipairs(s.spawns) do if g.role then assert(g.destroyed) end end
end
local function fac(group)
    for _, t in ipairs(group.data.route.points[1].task.params.tasks) do if t.id == 'FAC_EngageGroup' then return t.params end end
end
local function addSites(s)
    local cas = module(s, 'CAS'); local cfg
    for i = 1, 30 do local name, value = debug.getupvalue(cas.Initialize, i); if name == 'Config' then cfg = value.cas end end
    local copy = s.env.UTILS.DeepCopy
    for i = 2, 3 do
        local entry = copy(cfg.sites[1]); entry.id = string.format('%02d', i)
        for _, role in ipairs({'enemy', 'friendly', 'jtac'}) do
            local old = entry[role]; local name = old:gsub('_01$', '_' .. entry.id); entry[role] = name
            local data = copy(s.casTemplates[old]); data.name = name; data.groupId = data.groupId + i * 10
            for _, u in ipairs(data.units) do u.x = u.x + (i - 1) * 1000 end
            data.route.points[1].x = data.route.points[1].x + (i - 1) * 1000
            if role == 'jtac' then data.route.points[1].task.params.tasks[1].params.groupId = 501 + i * 10 end
            s.casTemplates[name] = data; s.groups[name] = { GetTemplate = function() return copy(data) end }
        end
        cfg.sites[i] = entry
    end
    cas.sites = {}; cas.Initialize(); return cas
end

test('Apache has a code-selection submenu, Hornet cannot see or accept CAS', function()
    local s = apache(); assert(s.commands[s.player.group.name]['Laser 1688'])
    local found = false
    for _, page in ipairs(s.menuPages[s.player.group.name]) do if page.title == 'Task: CAS' then found = true end end
    assert(found and #module(s, 'CAS').sites == 1 and module(s, 'CAS').sites[1].valid and #s.spawns == 0)
    local old = s.commands[s.player.group.name]['Laser 1688']; s.player.kind = 'FA-18C_hornet'; old()
    assert(not s:mission() and #s.spawns == 0); s:lastMessageContains('not available')
    local h = scenario(); assert(not h.commands[h.player.group.name]['Laser 1688']); h:assertClean(); s:assertClean()
end)

test('ground acceptance immediately creates seven units and publishes MGRS briefing once', function()
    local s = apache(); local r = accept(s)
    assert(r.category == 'CAS' and r.state == 'ACTIVE' and #s.spawns == 3 and #r.casPlan.targets == 3)
    local m = s.messages[#s.messages]; assert(m.seconds == 60 and m.text:find('CAS MISSION\nFRIENDLY LOCATION: MGRS', 1, true))
    assert(m.text == 'CAS MISSION\nFRIENDLY LOCATION: ' .. r.casPlan.friendlyLocation ..
        '\nTARGETS: 2 BMP-2s and 1 truck.' ..
        '\nJTAC standing by. LASER 1688. F10 CAS JTAC > Request laser when ready.' ..
        '\nOBJECTIVE: Destroy all 3 designated enemy vehicles; then RTB.' ..
        '\nReward per pilot: 150 points.\nRegistered pilots: 1.')
    s:command('Mission Status'); assert(s.messages[#s.messages].text == m.text); s:assertClean()
end)

test('clones omit native FAC and AUTOLASE fixes the selected code without mutating templates', function()
    for _, code in ipairs({1688, 1687, 1686}) do
        local s = apache(); local r = accept(s, code); local engine = r.casPlan.autolase.engine
        assert(not fac(r.casPlan.instances.jtac.group))
        assert(engine:GetLaserCode(r.casPlan.jtac.unit:GetName()) == code and engine.maxlasing == 1)
        assert(s.messages[#s.messages].text:find('JTAC standing by. LASER '..code..'. F10 CAS JTAC > Request laser when ready.',1,true))
        assert(next(engine.RecceSet.Set) == r.casPlan.instances.jtac.group:GetName())
        assert(s.casTemplates.TPL_CAS_JTAC_01.route.points[1].task.params.tasks[1].params.groupId == 501)
        assert(s.casTemplates.TPL_CAS_JTAC_01.route.points[1].task.params.tasks[1].params.laserCode == 1688)
        for _, role in ipairs({'enemy', 'friendly', 'jtac'}) do
            local g = r.casPlan.instances[role].group; local original = s.casTemplates[g.data.name]
            for i, u in ipairs(g.data.units) do assert(u.x == original.units[i].x and u.y == original.units[i].y and u.heading == original.units[i].heading) end
        end
        s:assertClean()
    end
end)

test('three and thirteen NM are inclusive and out-of-range requests release all locks', function()
    for _, nm in ipairs({2.999, 3, 13, 13.001}) do
        local s = apache(); s.player.position.x = 81000 - nm * 1852; s.player.airborne = true
        s:command('Laser 1688'); assert((s:mission() ~= nil) == (nm >= 3 and nm <= 13))
        if not s:mission() then clean(s); assert(not module(s, 'Missions').pilots['ucid-a']); s:lastMessageContains('within 3-13 NM') end
        s:assertClean()
    end
end)

test('nearest two draw equally and never fall through to a third occupied site', function()
    for draw = 1, 2 do local s = apache(); addSites(s); s.randomValues = {draw}
        assert(accept(s).casPlan.site.id == string.format('%02d', draw)); assert(s.randomCalls[1].maximum == 2); s:assertClean()
    end
    local s = apache(); addSites(s); local missions = module(s, 'Missions')
    missions.casSites['01'], missions.casSites['02'] = {}, {}; s:command('Laser 1688')
    assert(not s:mission() and #s.spawns == 0); s:assertClean()
end)

test('parallel teams cannot share a code or site but can use independent resources', function()
    local s = apache(); addSites(s); local a = accept(s); local p = s:addPilot('Other', 'ucid-b', 20)
    p.kind = 'AH-64D_BLK_II'; p.position = s.env.UTILS.DeepCopy(s.player.position); s:tick(2)
    s:command('Laser 1688', p); assert(not s:mission(p) and #s.spawns == 3)
    s:lastMessageContains('radio slot is in use'); assert(not module(s, 'Missions').pilots['ucid-b'])
    local b = accept(s, 1687, p); assert(a.casPlan.site ~= b.casPlan.site and #s.spawns == 6)
    assert(not fac(b.casPlan.instances.jtac.group) and b.casPlan.autolase.engine:GetLaserCode(b.casPlan.jtac.unit:GetName())==1687)
    kill(s, a.casPlan.targets[1].unit); assert(module(s, 'CAS').Remaining(b.casPlan) == 3); s:assertClean()
end)

test('known invalid nearest sites cannot be bypassed for a third site', function()
    local s = apache(); local cas = addSites(s); cas.sites[1].valid, cas.sites[2].valid = false, false
    s:command('Laser 1688'); assert(not s:mission() and #s.spawns == 0); s:assertClean()
end)

test('all three designated deaths are needed and RTB awards CAS once', function()
    local s = apache(); local r = accept(s); kill(s, r.casPlan.targets[1].unit); kill(s, r.casPlan.targets[2].unit)
    s:tick(1); assert(r.state == 'ACTIVE'); kill(s, r.casPlan.targets[3].unit); assert(r.state == 'RTB_PENDING')
    recover(s); s:score(150); s:categoryScores({casScore = 150, airInterdictionScore = 0, missionCount = 1})
    clean(s); s:assertClean()
end)

test('post-objective loss awards ninety and duplicate aircraft events cannot settle twice', function()
    local s = apache(); local r = accept(s); complete(s, r); s:event('Ejection', s.player); s:event('Dead', s.player)
    s:score(90); s:categoryScores({casScore = 90, deathCount = 1, missionCount = 1}); clean(s); s:assertClean()
end)

test('pre-objective accident and abort are zero, unfinished landing stays active', function()
    for _, mode in ipairs({'accident', 'abort', 'landing'}) do
        local s = apache(); local r = accept(s)
        if mode == 'landing' then recover(s); assert(s:mission() == r and r.state == 'ACTIVE')
        elseif mode == 'abort' then s:command('Abort Mission'); clean(s)
        else s:event('Ejection', s.player); clean(s) end
        s:score(0); s:assertClean()
    end
end)

test('MP2 shares completion and retains support until the last participant settles', function()
    local s = apache(); s:occupyWing(); local r = accept(s); complete(s, r); recover(s)
    assert(s:mission() == r and not r.casPlan.instances.jtac.group.destroyed); s:score(150)
    s:event('Ejection', s.wingman); s:score(90, s.wingman); clean(s); s:assertClean()
end)

test('PLT and human CPG get distinct UCID rewards for the same Apache', function()
    local s = apache(); s.connections[10].slot = tostring(s.player.slotID) .. '_1'
    s:addCrew(s.player, 'CPG', 'ucid-cpg', 21); s:tick(2)
    local r = accept(s); assert(#r.participants == 2); complete(s, r); recover(s)
    assert(module(s, 'Scoring').Get('ucid-cpg').casScore == 150); s:score(150); clean(s); s:assertClean()
end)

test('mission teams receive one shared CAS and keep both group locks', function()
    local s = apache(); local p = s:addPilot('Other', 'ucid-b', 20)
    p.kind = 'AH-64D_BLK_II'; p.position = s.env.UTILS.DeepCopy(s.player.position); s:tick(2)
    s:command('Create Mission Team'); s:command('Join Mission Team 1: Pilot', p)
    local r = accept(s); assert(#r.participants == 2 and module(s, 'Missions').groupLocks[p.group.name] == r)
    s:command('Mission Status', p); s:lastMessageContains('CAS MISSION'); complete(s, r)
    recover(s); assert(not r.casPlan.instances.jtac.group.destroyed); s:event('Ejection', p)
    s:score(90, p); clean(s); s:assertClean()
end)

test('personal abort stays zero and late joiners do not receive retrospective credit', function()
    local s = apache(); s:occupyWing(); local r = accept(s); s:abortSortie(s.player)
    complete(s, r); recover(s, s.wingman); s:score(0); s:score(150, s.wingman); clean(s); s:assertClean()
    s = apache(); r = accept(s); s:occupyWing(); s:tick(2); assert(#r.participants == 1)
    complete(s, r); recover(s); s:score(0, s.wingman); clean(s); s:assertClean()
end)

test('nil, exception, identity changes and damage do not complete a target', function()
    for _, mode in ipairs({'nil', 'error', 'id', 'damage'}) do
        local s = apache(); local r = accept(s); local u = r.casPlan.targets[1].unit
        kill(s, r.casPlan.targets[2].unit); kill(s, r.casPlan.targets[3].unit)
        if mode == 'nil' then u.alive = nil elseif mode == 'error' then u.lifeError = true
        elseif mode == 'id' then u.id = u.id + 1; u.alive = false else u.life = 1 end
        s:tick(1); assert(r.state == 'ACTIVE'); s:assertClean()
    end
end)

test('fixed-ID native death polling works without a loss event', function()
    local s = apache(); local r = accept(s); for _, t in ipairs(r.casPlan.targets) do t.unit.alive = false end
    s:tick(1); assert(r.state == 'RTB_PENDING'); s:assertClean()
end)

test('friendly and JTAC losses notify once, permit self-designation and do not earn enemy kills', function()
    local s = apache(); local r = accept(s); kill(s, r.casPlan.jtac.unit); kill(s, r.casPlan.friendlies[1].unit)
    s:tick(1); assert(r.state == 'ACTIVE'); local n = #s.messages; s:tick(2); assert(#s.messages == n)
    assert(module(s, 'CAS').Remaining(r.casPlan) == 3)
    complete(s, r); recover(s); s:score(150); clean(s); s:assertClean()
end)

test('status recalls only public briefing, then only the completed result without coordinates', function()
    local s = apache(); local r = accept(s); local briefing = s.messages[#s.messages].text
    kill(s, r.casPlan.targets[1].unit); s:command('Mission Status'); assert(s.messages[#s.messages].text == briefing)
    complete(s, r); kill(s, r.casPlan.jtac.unit); s:tick(1); s:command('Mission Status')
    local text = s.messages[#s.messages].text
    assert(text:find('CAS Objective Complete', 1, true) and not text:find('LOCATION', 1, true) and not text:find('MGRS', 1, true))
    assert(s.messages[#s.messages].seconds == 20); s:assertClean()
end)

test('failures before, during and after each spawn clean every created group and release resources', function()
    for _, role in ipairs({'enemy', 'friendly', 'jtac'}) do
        for _, mode in ipairs({'casConstructorFailure', 'casBeforeFailure', 'casAfterFailure', 'casNilAfter', 'casInvalidCount', 'casInvalidType'}) do
            local s = apache(); s[mode] = role; s:command('Laser 1688')
            if s:mission() and s:mission().state == 'PREPARING' then s:tick(11) end
            assert(not s:mission() and not module(s, 'Missions').pilots['ucid-a']); clean(s)
            s:lastMessageContains('ERROR: CAS setup failed.')
        end
    end
end)

test('terrain LOS false or unobservable pauses designation and cannot cancel CAS setup', function()
    for _, mode in ipairs({'blocked', 'error'}) do local s = apache()
        if mode == 'blocked' then s.casLOS = false else s.casLOSError = true end
        local r=accept(s); assert(r.state=='ACTIVE' and #s.spawns==3)
        s:tick(1); assert(s:mission()==r and r.state=='ACTIVE')
        local log=table.concat(s.logs,'\n'); assert(log:find('CAS terrain visibility diagnostic',1,true))
        assert(log:find(mode=='blocked' and 'visible=false' or 'visible=UNKNOWN',1,true))
        complete(s,r); recover(s); s:score(150); clean(s); s:assertClean()
    end
end)

test('failed or unconfirmed deletion holds both site and code until retry', function()
    for _, mode in ipairs({'cleanupFailures', 'cleanupFalse', 'cleanupNoEffect'}) do
        local s = apache(); local r = accept(s); local g = r.casPlan.instances.jtac.group
        g[mode] = mode == 'cleanupFailures' and 1 or true; s:command('Abort Mission')
        assert(not s:mission() and not g.destroyed and module(s, 'Missions').jtacSlots[1688] == r.casPlan)
        assert(r.casPlan.instances.enemy.group.destroyed and r.casPlan.instances.friendly.group.destroyed)
        g[mode] = nil; s:tick(2); assert(not g.destroyed); s:tick(5); clean(s)
    end
end)

test('cleanup-generated death events cannot complete CAS or contaminate a later assignment', function()
    local s = apache(); s.cleanupEvents = true; local r = accept(s); s:command('Abort Mission'); clean(s); s:score(0)
    local b = accept(s); assert(b.assignmentID ~= r.assignmentID)
    s:event('Dead', r.casPlan.targets[1].unit); assert(b.state == 'ACTIVE' and module(s, 'CAS').Remaining(b.casPlan) == 3)
    for _, page in ipairs(s.menuPages[s.player.group.name]) do assert(page.entries <= 10) end
    s:assertClean()
end)

test('invalid TPL settings disable CAS only, preserving other Apache tasks', function()
    for _, mode in ipairs({'late', 'side', 'count', 'hold', 'disperse', 'fac', 'target', 'extraFAC'}) do
        local data = apache().casTemplates; local t = data.TPL_CAS_JTAC_01; local tasks = t.route.points[1].task.params.tasks
        if mode == 'late' then t.lateActivation = false elseif mode == 'side' then t.CoalitionID = 1
        elseif mode == 'count' then table.remove(t.units) elseif mode == 'hold' then tasks[2].params.action.params.value = 0
        elseif mode == 'disperse' then tasks[3].params.action.params.value = 600
        elseif mode == 'fac' then tasks[1].enabled = false elseif mode == 'target' then tasks[1].params.groupId = 999
        else tasks[#tasks + 1] = {id = 'FAC', enabled = true, params = {}} end
        local s = apache({casTemplates = data}); s:command('Laser 1688'); assert(not s:mission() and #s.spawns == 0 and #s.errors == 1)
        s:command('Task: Air Interdiction'); assert(s:mission().category == 'Air Interdiction')
    end
end)

test('coordinate conversion failure rolls back before any resource reservation', function()
    local s = apache(); s.env.COORDINATE.ToStringMGRS = function() error('conversion unavailable') end
    s:command('Laser 1688'); assert(not s:mission() and #s.spawns == 0); clean(s)
end)

test('partially created groups are recovered through the native fallback when MOOSE lookup fails', function()
    for _, mode in ipairs({'nil', 'error'}) do
        local s = apache(); local find = s.env.GROUP.FindByName
        s.env.GROUP.FindByName = function(self, name)
            if name:find('^DT_CAS_') then if mode == 'error' then error('wrapper unavailable') end; return nil end
            return find(self, name)
        end
        s.casAfterFailure = 'jtac'; s:command('Laser 1688'); assert(not s:mission()); clean(s)
    end
end)

test('setup failure holds resources while partial cleanup is pending and then permits retry', function()
    local s = apache(); local original = s.env.SPAWN.NewFromTemplate
    function s.env.SPAWN:NewFromTemplate(data, name, alias)
        local spawner = original(self, data, name, alias)
        local spawn = spawner.Spawn
        function spawner:Spawn()
            local g = spawn(self)
            if alias:find('_FRIENDLY$') then g.cleanupFalse = true end
            return g
        end
        return spawner
    end
    s.casBeforeFailure = 'jtac'; s:command('Laser 1688'); assert(not s:mission())
    local missions = module(s, 'Missions'); assert(missions.casSites['01'] and missions.jtacSlots[1688])
    for _, g in ipairs(s.spawns) do g.cleanupFalse = nil end
    s:tick(5); clean(s)
    s.casBeforeFailure = nil; s.env.SPAWN.NewFromTemplate = original; assert(accept(s).state == 'ACTIVE')
end)

test('dynamic Apache runtime identity and both seats retain individual CAS rewards', function()
    local s = apache(); local unit = s.player
    unit.slotID = 70000; s.connections[10].slot = '70000_1'; s:addCrew(unit, 'CPG', 'ucid-cpg', 21, '70000_2')
    function unit:GetTemplate() error('dynamic aircraft has no ME template') end
    s.rows = {}
    for _, id in ipairs({10,21}) do
        local p = s.connections[id]
        s.rows[#s.rows+1] = {playerID=id,ucid=p.ucid,name=p.name,side=2,slot=p.slot,
            unitName=unit:GetName(),groupName=unit.group:GetName(),objectID=unit:GetID(),aircraftType=unit.kind}
    end
    assert(s.env.DynamicTrainingPlayers.Update(s.rows)); s:tick(2)
    local r=accept(s); assert(#r.participants==2); complete(s,r); recover(s)
    s:score(150); assert(module(s,'Scoring').Get('ucid-cpg').casScore==150); clean(s); s:assertClean()
end)

test('unknown UCID stays explicitly unscored and does not borrow a player identity', function()
    local s=apache({unscored=true}); local r=accept(s); complete(s,r); recover(s)
    assert(r.participants[1].receipt.scored==false and next(module(s,'Scoring').players)==nil)
    clean(s); s:assertClean()
end)

test('MOOSE unit enumeration order may differ from the mixed-vehicle template', function()
    local s=apache(); s.casReverseUnits=true; local r=accept(s)
    assert(r.state=='ACTIVE' and r.casPlan.targets[1].unit:GetTypeName()=='Ural-375')
    complete(s,r); recover(s); s:score(150); clean(s); s:assertClean()
end)

test('inactive native units wait for activation before scoring and publishing coordinates', function()
    local s=apache(); s.casInactiveUntil=2; local r=accept(s)
    assert(r.state=='PREPARING' and #s.spawns==1 and not r.id)
    s:lastMessageContains('Preparing JTAC.'); s:command('Mission Status'); s:lastMessageContains('Preparing JTAC.')
    s:command('Laser 1688'); assert(s:mission()==r and #s.spawns==1); s:lastMessageContains('already armed')
    s:tick(1); assert(r.state=='PREPARING' and #s.spawns==1)
    s:tick(2); assert(r.state=='ACTIVE' and #s.spawns==3 and r.id)
    s:lastMessageContains('CAS MISSION'); complete(s,r); recover(s); s:score(150); clean(s); s:assertClean()
end)

test('delayed unit enumeration times out safely and retains useful activation diagnostics', function()
    local s=apache(); s.casUnitsUnavailableUntil=20; local r=accept(s)
    assert(r.state=='PREPARING'); s:tick(11); assert(not s:mission() and not r.id); clean(s)
    assert(table.concat(s.errors,'\n'):find('activation timed out: enemy: unit count=0/3',1,true))
end)

test('partial unit lists may become ready on the next frame without a false failure', function()
    local s=apache(); s.casUnitsUnavailableUntil=1; local r=accept(s)
    assert(r.state=='PREPARING'); s:tick(1); assert(r.state=='ACTIVE'); s:assertClean()
end)

test('preparation abort, aircraft change and personal abort release or retain the correct assignment', function()
    for _, mode in ipairs({'abort','changed','personal'}) do
        local s=apache(); s.casInactiveUntil=2
        if mode=='personal' then s:occupyWing() end
        local r=accept(s)
        if mode=='abort' then s:command('Abort Mission'); clean(s)
        elseif mode=='changed' then s.player.id=s.player.id+1; s:tick(1); assert(not s:mission()); clean(s)
        else
            s:abortSortie(s.player); assert(r.state=='PREPARING'); s:tick(2); assert(r.state=='ACTIVE')
            complete(s,r); recover(s,s.wingman); s:score(0); s:score(150,s.wingman); clean(s)
        end
        s:assertClean()
    end
end)

test('an already validated target lost before the rest activate cannot earn a setup-time success', function()
    local s=apache(); local original=s.env.SPAWN.NewFromTemplate
    function s.env.SPAWN:NewFromTemplate(data,name,alias)
        local spawner=original(self,data,name,alias); local spawn=spawner.Spawn
        function spawner:Spawn()
            local g=spawn(self)
            if alias:find('_FRIENDLY$') then
                function g:GetUnits() if s.time<1 then return {} end; return self.units end
            end
            return g
        end
        return spawner
    end
    local r=accept(s); assert(r.state=='PREPARING' and #r.casPlan.targets==3)
    r.casPlan.targets[1].unit.alive=false; s:tick(1)
    assert(not s:mission() and not r.id); clean(s)
end)

test('DCS decimal-string unit IDs activate CAS and keep target identity through RTB', function()
    local s=apache(); s.casStringUnitIDs=true; local r=accept(s)
    assert(r.state=='ACTIVE' and #s.spawns==3)
    for _,t in ipairs(r.casPlan.targets) do assert(type(t.objectID)=='string') end
    complete(s,r); recover(s); s:score(150); clean(s); s:assertClean()
end)

test('decimal-string group IDs retain CAS identity while native FAC remains absent', function()
    local s=apache(); s.casStringUnitIDs=true; s.casStringGroupID=true; local r=accept(s)
    assert(r.state=='ACTIVE')
    assert(not fac(r.casPlan.instances.jtac.group) and type(r.spawn.group:GetID())=='string')
    s:command('Abort Mission'); clean(s); s:assertClean()
end)

test('native ID validation accepts only exactly represented positive integers or decimal strings', function()
    local number=dofile('src/observations.lua').IDNumber
    for _,id in ipairs({1,1000003,'1000003','0001000003',9007199254740991,'9007199254740991'}) do
        assert(number(id)==tonumber(id))
    end
    for _,id in ipairs({false,true,{},0,-1,1.5,math.huge,0/0,'','0','-1','1.5','1e6',' 1',
        '1000003x','9007199254740992',9007199254740992}) do assert(number(id)==nil) end
    assert(number(nil)==nil)
end)

test('missing native objects remain pending with typed diagnostics, then release all resources', function()
    local s=apache(); local original=s.env.SPAWN.NewFromTemplate
    function s.env.SPAWN:NewFromTemplate(data,name,alias)
        local spawner=original(self,data,name,alias); local spawn=spawner.Spawn
        function spawner:Spawn()
            local g=spawn(self)
            if alias:find('_ENEMY$') then g.units[1].GetDCSObject=function() return nil end end
            return g
        end
        return spawner
    end
    local r=accept(s); assert(r.state=='PREPARING')
    s:tick(11); assert(not s:mission()); clean(s)
    local errors=table.concat(s.errors,'\n'); assert(errors:find('idType=number raw=false',1,true))
end)

test('mixed string and numeric duplicate IDs cannot describe two different generated vehicles', function()
    local s=apache(); local original=s.env.SPAWN.NewFromTemplate
    function s.env.SPAWN:NewFromTemplate(data,name,alias)
        local spawner=original(self,data,name,alias); local spawn=spawner.Spawn
        function spawner:Spawn()
            local g=spawn(self)
            if alias:find('_ENEMY$') then g.units[2].id=tostring(g.units[1].id) end
            return g
        end
        return spawner
    end
    s:command('Laser 1688'); assert(not s:mission()); clean(s)
    assert(table.concat(s.errors,'\n'):find('Invalid generated CAS vehicle',1,true))
end)

test('delayed visibility diagnostics include endpoints once and never replace the public briefing', function()
    local s=apache(); s.casLOS=false; s.terrainHeight=function() return 200 end
    local r=accept(s); local briefing=s.messages[#s.messages].text
    assert(not table.concat(s.logs,'\n'):find('CAS terrain visibility diagnostic',1,true))
    s:tick(1)
    local log=table.concat(s.logs,'\n')
    assert(log:find('visible=false; offsetMeters=2; from=',1,true) and log:find('ground=200.00,AGL=-200.00',1,true))
    for _,t in ipairs(r.casPlan.targets) do assert(log:find('targetID='..t.objectID,1,true)) end
    s:tick(2); assert(table.concat(s.logs,'\n')==log)
    s:command('Mission Status'); assert(s.messages[#s.messages].text==briefing)
    s:command('Abort Mission'); clean(s); s:assertClean()
end)

test('aborted preparation never schedules a later visibility diagnostic for removed groups', function()
    local s=apache(); accept(s); s:command('Abort Mission'); clean(s)
    s:tick(2); assert(not table.concat(s.logs,'\n'):find('CAS terrain visibility diagnostic',1,true))
    s:assertClean()
end)

local function activeLasers(s)
    local count=0
    for _,spot in ipairs(s.nativeSpots) do if spot.kind=='laser' and not spot.destroyed then count=count+1 end end
    return count
end

test('pinned AUTOLASE constructor has one Recce, fixed code and no autonomous pending jobs', function()
    for _,code in ipairs({1688,1687,1686}) do
        local s=apache(); local r=accept(s,code); local a=r.casPlan.autolase
        local n=0; for _,group in pairs(a.engine.RecceSet.Set) do n=n+1; assert(group==r.casPlan.instances.jtac.group) end
        assert(n==1 and a.engine.maxlasing==1 and a.engine.forcecooldown~=true)
        for _,task in ipairs(s.mooseTasks) do assert(task.cancelled) end
        assert(#s.nativeSpots==0); s:tick(1); assert(#s.nativeSpots==0); request(s)
        assert(activeLasers(s)==1 and a.spot.SpotLaser.code==code)
        s:command('Abort Mission'); assert(activeLasers(s)==0 and next(s.mooseSubscriptions)==nil); clean(s); s:assertClean()
    end
end)

test('actual MOOSE SPOT tracks the chosen unit at plus one metre and keeps that target', function()
    local s=apache(); local r=accept(s); request(s); s:tick(1); local a=r.casPlan.autolase
    local first=a.target; local laser=a.spot.SpotLaser
    assert(laser.point.x==first.unit.position.x and laser.point.y==first.unit.position.y+1)
    first.unit.position.x=first.unit.position.x+10
    r.casPlan.targets[3].unit.threat=10; s:tick(2)
    assert(a.target==first and a.spot.SpotLaser==laser and laser.updates>0)
    assert(laser.point.x==first.unit.position.x and activeLasers(s)==1)
    s:command('Abort Mission'); clean(s); s:assertClean()
end)

test('only designated visible RED targets may be selected and all blocked targets pause safely', function()
    local s=apache(); local r=accept(s); local p=r.casPlan
    p.targets[1].unit.los=false; p.targets[2].unit.los=false
    p.friendlies[1].unit.threat=100
    request(s); s:tick(1); assert(p.autolase.target==p.targets[3] and activeLasers(s)==1)
    kill(s,p.targets[3].unit); s:tick(2)
    assert(p.autolase.status=='WAITING' and activeLasers(s)==0 and r.state=='ACTIVE')
    p.targets[1].unit.los=true; s:tick(3); assert(p.autolase.target==p.targets[1])
    s:command('Abort Mission'); clean(s); s:assertClean()
end)

test('unknown, exceptions, invalid coordinates, side changes and reused IDs stop tracking without credit', function()
    for _,mode in ipairs({'nil','lifeError','id','position','side','losNil','losError'}) do
        local s=apache(); local r=accept(s); request(s); s:tick(1); local p=r.casPlan; local target=p.autolase.target
        for _,t in ipairs(p.targets) do if t~=target then t.unit.los=false end end
        local u=target.unit; local oldSpot=p.autolase.spot
        if mode=='nil' then u.alive=nil elseif mode=='lifeError' then u.lifeError=true
        elseif mode=='id' then u.id=u.id+100 elseif mode=='position' then u.position.x=0/0
        elseif mode=='side' then u.side=2 elseif mode=='losNil' then s.casLOSNil=true else s.casLOSError=true end
        s.time=2; s:runMoose(2)
        assert(not oldSpot.Lasing and activeLasers(s)==0)
        s:tick(2); assert(r.state=='ACTIVE' and not target.lost); s:score(0)
        s:command('Abort Mission'); clean(s); s:assertClean()
    end
end)

test('confirmed target death switches to another target while a JTAC loss stops all designation', function()
    local s=apache(); local r=accept(s); request(s); s:tick(1); local p=r.casPlan; local first=p.autolase.target
    kill(s,first.unit); assert(activeLasers(s)==0); s:tick(2)
    assert(p.autolase.target~=first and activeLasers(s)==1)
    kill(s,p.jtac.unit); assert(activeLasers(s)==0); s:tick(3)
    assert(r.state=='ACTIVE'); complete(s,r); recover(s); s:score(150); clean(s); s:assertClean()
end)

test('partial native spot creation is cleaned and cannot multiply lasers during a destroy failure', function()
    local s=apache(); local r=accept(s); s.spotCreateFailure='laser'; s.time=1; request(s)
    assert(#s.nativeSpots==1 and s.nativeSpots[1].destroyed and activeLasers(s)==0 and r.state=='ACTIVE')
    s.spotCreateFailure=nil; s:tick(2); assert(activeLasers(s)==1)
    local laser=r.casPlan.autolase.spot.SpotLaser; laser.destroyFalse=true; s.casLOS=false
    s:tick(3); local n=#s.nativeSpots; s.casLOS=true; s:tick(4)
    assert(#s.nativeSpots==n and r.casPlan.autolase.spot.SpotLaser==laser)
    laser.destroyFalse=nil; s:tick(5); assert(laser.destroyed and activeLasers(s)==1)
    s:command('Abort Mission'); clean(s); s:assertClean()
end)

test('IR creation failure leaves no spot and a later healthy scan recovers', function()
    local s=apache(); local r=accept(s); s.spotCreateFailure='ir'; s.time=1; request(s)
    assert(activeLasers(s)==0 and #s.nativeSpots==0 and r.state=='ACTIVE')
    s.spotCreateFailure=nil; s:tick(2); assert(activeLasers(s)==1)
    s:command('Abort Mission'); clean(s); s:assertClean()
end)

test('primary completion stops spots immediately and stale tracking cannot resume in a new CAS', function()
    local s=apache(); local r=accept(s); request(s); s:tick(1); local old=r.casPlan.autolase.spot
    complete(s,r); assert(r.state=='RTB_PENDING' and activeLasers(s)==0)
    assert(old:OnBeforeLasing()==false); recover(s); clean(s)
    s.player.position={x=81000-8*1852,y=0,z=800}
    local b=accept(s,1687); request(s); s:tick(s.time+1); local laser=b.casPlan.autolase.spot.SpotLaser
    old:__Lasing(0.1); s:runMoose(s.time+1)
    assert(not old.Lasing and not laser.destroyed and activeLasers(s)==1)
    s:command('Abort Mission'); clean(s); s:assertClean()
end)

test('spot cleanup failure after abort retains the code and site through the bounded retry', function()
    local s=apache(); local r=accept(s); request(s); s:tick(1); local spot=r.casPlan.autolase.spot.SpotLaser
    spot.destroyFailures=1; s:command('Abort Mission')
    assert(not s:mission() and module(s,'Missions').jtacSlots[1688]==r.casPlan)
    assert(not spot.destroyed and not r.casPlan.autolase.spot.Lasing)
    s:tick(6); assert(spot.destroyed); clean(s)
    for _,task in ipairs(s.mooseTasks) do assert(task.cancelled) end
    assert(next(s.mooseSubscriptions)==nil)
end)

test('spot cleanup also retries during RTB without changing its completed reward', function()
    local s=apache(); local r=accept(s); request(s); s:tick(1); local spot=r.casPlan.autolase.spot.SpotLaser
    spot.destroyFailures=2; complete(s,r); assert(r.state=='RTB_PENDING')
    s:tick(6); s:tick(11); assert(spot.destroyed and activeLasers(s)==0)
    recover(s); s:score(150); clean(s); s:assertClean()
end)

test('parallel designators keep distinct codes, targets and notification audiences', function()
    local s=apache(); addSites(s); local a=accept(s)
    local pilot=s:addPilot('Other','ucid-b',20); pilot.kind='AH-64D_BLK_II'
    pilot.position=s.env.UTILS.DeepCopy(s.player.position); request(s); s:tick(1)
    local b=accept(s,1687,pilot); request(s,pilot); s:tick(2)
    assert(a.casPlan.autolase.target~=b.casPlan.autolase.target and activeLasers(s)==2)
    assert(a.casPlan.autolase.spot.SpotLaser.code==1688 and b.casPlan.autolase.spot.SpotLaser.code==1687)
    for _,m in ipairs(s.messages) do if m.text:find('CAS JTAC: Lasing',1,true) then
        assert(m.text:find(m.group==s.player.group.name and '1688' or '1687',1,true))
    end end
    s:command('Abort Mission'); assert(activeLasers(s)==1)
    s:command('Abort Mission',pilot); assert(activeLasers(s)==0); clean(s); s:assertClean()
end)

test('designation notices preserve Mission Status and do not flood stable or blocked scans', function()
    for _,blocked in ipairs({false,true}) do
        local s=apache(); s.casLOS=not blocked; local r=accept(s); local briefing=s.messages[#s.messages].text
        request(s); s:tick(1); local n=#s.messages; s:tick(2); s:tick(3); assert(#s.messages==n)
        s:command('Mission Status'); assert(s.messages[#s.messages].text==briefing)
        s:command('Abort Mission'); clean(s); s:assertClean()
    end
end)

test('a missing AUTOLASE engine rolls back setup before reward activation', function()
    local s=apache(); s.env.AUTOLASE=nil; s:command('Laser 1688')
    assert(not s:mission()); clean(s); s:score(0)
    assert(table.concat(s.errors,'\n'):find('AUTOLASE/SPOT unavailable',1,true))
end)

test('the SPOT update guard enforces the configured designation deadline', function()
    local s=apache(); local r=accept(s); request(s); s:tick(1); local old=r.casPlan.autolase.spot
    s.time=301; s:runMoose(301); assert(not old.Lasing and activeLasers(s)==0)
    s:tick(301); assert(activeLasers(s)==1 and r.casPlan.autolase.spot~=old)
    s:command('Abort Mission'); clean(s); s:assertClean()
end)

test('ground and airborne acceptances remain on standby until an explicit request', function()
    for _,airborne in ipairs({false,true}) do
        local s=apache(); s.player.airborne=airborne; local r=accept(s)
        assert(s.messages[#s.messages].text:find('JTAC standing by. LASER 1688. F10 CAS JTAC > Request laser when ready.',1,true))
        for t=1,10 do s:tick(t) end
        assert(#s.nativeSpots==0 and not r.casPlan.autolase.requested and r.state=='ACTIVE')
        request(s); assert(activeLasers(s)==1 and #s.spawns==3)
        s:command('Abort Mission'); clean(s); s:assertClean()
    end
end)

test('stop is immediate, stays stopped, and re-request cannot revive stale tracking', function()
    local s=apache(); local r=accept(s); local briefing=s.messages[#s.messages].text
    request(s); local old=r.casPlan.autolase.spot; local n=#s.nativeSpots; local notices=#s.messages
    request(s); assert(#s.nativeSpots==n and #s.messages==notices)
    s:command('Stop laser'); assert(activeLasers(s)==0 and not old.Lasing)
    notices=#s.messages; s:command('Stop laser'); assert(#s.messages==notices)
    for t=1,10 do s:tick(t) end
    assert(#s.nativeSpots==n and not r.casPlan.autolase.requested)
    request(s); local current=r.casPlan.autolase.spot; assert(current~=old and activeLasers(s)==1)
    old:__Lasing(0.1); s:runMoose(11); assert(not old.Lasing and current.Lasing and activeLasers(s)==1)
    s:command('Mission Status'); assert(s.messages[#s.messages].text==briefing)
    assert(#s.spawns==3 and r.casPlan.radio.laserCode==1688); s:score(0)
    s:command('Abort Mission'); clean(s); s:assertClean()
end)

test('shutdown failure retries on standby without silently enabling designation', function()
    local s=apache(); local r=accept(s); request(s); local a=r.casPlan.autolase
    local old=a.spot; local native=old.SpotLaser; native.destroyFalse=true
    s:command('Stop laser'); assert(not a.requested and not old.Lasing and a.spot==old)
    s:lastMessageContains('shutdown pending'); local n=#s.nativeSpots
    s:tick(1); s:tick(2); assert(#s.nativeSpots==n and a.spot==old)
    native.destroyFalse=nil; s:tick(3); assert(not a.spot and native.destroyed and activeLasers(s)==0)
    s:tick(4); assert(#s.nativeSpots==n and a.status=='STANDBY')
    request(s); assert(activeLasers(s)==1)
    s:command('Abort Mission'); clean(s); s:assertClean()
end)

test('request during pending cleanup waits and old request generations remain invalid', function()
    local s=apache(); local r=accept(s); request(s); local a=r.casPlan.autolase
    local old=a.spot; old.SpotLaser.destroyFalse=true; s:command('Stop laser')
    local n=#s.nativeSpots; request(s); assert(#s.nativeSpots==n and a.spot==old)
    assert(old:OnBeforeLasing()==false)
    old.SpotLaser.destroyFalse=nil; s:tick(1); assert(a.spot~=old and activeLasers(s)==1)
    old:__Lasing(0.1); s:runMoose(2); assert(not old.Lasing and a.spot.Lasing)
    s:command('Abort Mission'); clean(s); s:assertClean()
end)

test('stale menu callbacks cannot request after completion, abort or replacement', function()
    local s=apache(); local r=accept(s); local oldRequest=s.commands[s.player.group.name]['Request laser']
    complete(s,r); oldRequest(); assert(#s.nativeSpots==0 and not r.casPlan.autolase.requested)
    s:command('Abort Mission'); oldRequest(); assert(#s.nativeSpots==0)
    local b=accept(s,1687); local oldStop=s.commands[s.player.group.name]['Stop laser']
    s:command('Abort Mission'); local c=accept(s,1686); request(s); local spot=c.casPlan.autolase.spot
    oldRequest(); oldStop(); assert(c.casPlan.autolase.spot==spot and activeLasers(s)==1)
    assert(b.casPlan.autolase.stopped)
    s:command('Abort Mission'); clean(s); s:assertClean()
end)

test('late joiners, changed aircraft and replaced groups cannot use captured laser controls', function()
    for _,mode in ipairs({'late','aircraft','group'}) do
        local s=apache(); local r=accept(s); local callback=s.commands[s.player.group.name]['Request laser']
        if mode=='late' then
            s:occupyWing(); s.player.name=nil; s.connections[10]=nil
        elseif mode=='aircraft' then s.player.id=s.player.id+1
        else s.player.group.id=s.player.group.id+1 end
        callback(); assert(#s.nativeSpots==0 and not r.casPlan.autolase.requested)
        s:lastMessageContains('no longer available'); s:assertClean()
    end
end)

test('registered team wings can control shared designation until their personal sortie closes', function()
    local s=apache(); local p=s:addPilot('Other','ucid-b',20); p.kind='AH-64D_BLK_II'
    p.position=s.env.UTILS.DeepCopy(s.player.position); s:tick(2)
    s:command('Create Mission Team'); s:command('Join Mission Team 1: Pilot',p)
    local r=accept(s); request(s,p); assert(activeLasers(s)==1)
    local callback=s.commands[p.group.name]['Request laser']; s:command('Stop laser',p)
    s:abortSortie(p,p); callback(); assert(activeLasers(s)==0)
    request(s); assert(activeLasers(s)==1 and r.state=='ACTIVE')
    for _,pages in pairs(s.menuPages) do for _,page in ipairs(pages) do assert(page.entries<=10) end end
    s:command('Abort Mission'); clean(s); s:assertClean()
end)

test('preparation exposes no laser controls and completion removes them on refresh', function()
    local s=apache(); s.casInactiveUntil=2; local r=accept(s)
    assert(r.state=='PREPARING' and not s.commands[s.player.group.name]['Request laser'])
    s:tick(1); assert(#s.nativeSpots==0)
    s:tick(2)
    assert(r.state=='ACTIVE' and #s.nativeSpots==0)
    complete(s,r); s:tick(4); assert(not s.commands[s.player.group.name]['Request laser'])
    s:command('Abort Mission'); clean(s); s:assertClean()
end)

print(string.format('All %d CAS tests passed (pinned MOOSE policy/SPOT; simulated engine boundaries).', count))
