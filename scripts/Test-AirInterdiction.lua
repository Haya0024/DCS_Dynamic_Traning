local scenario=dofile('scripts/Intercept-TestHarness.lua')
local count=0
local function test(name,run) run(); count=count+1; print(string.format('PASS: AI-%02d %s',count,name)) end
local function module(s,wanted)
    for i=1,100 do local name,value=debug.getupvalue(s.timers[1].callback,i)
        if name==wanted then return value end; if not name then break end
    end; error('Missing module: '..wanted)
end
local function accept(s,draw,player)
    s.randomValues={draw or 1}; s:command('Task: Air Interdiction',player); return assert(s:mission(player))
end
local function kill(s,u) u.alive=false; u.life=0; s:event('Dead',u) end
local function complete(s,r) for _,t in ipairs(r.interdictionPlan.targets) do kill(s,t.unit) end end
local function recover(s,p)
    p=p or s.player; s:land(s:base(),s.time+1,p); p.position.y=0
    s:tick(s.time+1); s:tick(s.time+10)
end

test('six dormant templates are cached without spawning or drawing',function()
    local s=scenario(); local sites=module(s,'AirInterdiction').sites
    assert(#sites==6 and #s.spawns==0 and #s.randomCalls==0)
    for _,site in ipairs(sites) do assert(site.valid and site.point) end; s:assertClean()
end)
test('ground acceptance starts immediately with the five-line DDM briefing',function()
    local s=scenario(); local r=accept(s)
    assert(r.category=='Air Interdiction' and r.state=='ACTIVE' and #s.spawns==1)
    assert(s.messages[#s.messages-1].text=='Air Interdiction mission accepted.' and s.messages[#s.messages-1].seconds==10)
    assert(s.messages[#s.messages].text=='AIR INTERDICTION MISSION\nTARGET AREA: LL DDM 101000.000 800.000\n'..
        'OBJECTIVE: Destroy all 3 convoy vehicles; then RTB.\nReward per pilot: 150 points.\nRegistered pilots: 1.')
    assert(s.messages[#s.messages].seconds==60); s:assertClean()
end)
test('either nearest route can be selected by one equal draw',function()
    for draw=1,2 do local s=scenario(); local r=accept(s,draw)
        assert(r.interdictionPlan.site.name==string.format('TPL_AI_%02d',draw))
        assert(#s.randomCalls==1 and s.randomCalls[1].minimum==1 and s.randomCalls[1].maximum==2); s:assertClean()
    end
end)
test('all six routes are available from a nearby acceptance position',function()
    for i=1,6 do local s=scenario(); s.player.position.x=i*100000+1000
        assert(accept(s).interdictionPlan.site.name==string.format('TPL_AI_%02d',i)); s:assertClean()
    end
end)
test('route center uses geographic extents rather than waypoint density',function()
    local data=scenario().interdictionTemplates; local points=data.TPL_AI_01.route.points
    -- An extra point near the start must not bias the displayed center.
    table.insert(points,2,{x=100010,y=310,action='On Road',speed=9.25})
    points[#points].task.params.tasks[1].params.fromWaypointIndex=#points
    local s=scenario({interdictionTemplates=data}); local r=accept(s)
    assert(r.interdictionPlan.location=='LL DDM 101000.000 800.000'); s:assertClean()
end)
test('acceptance uses the occupied participant with the lowest aircraft number',function()
    local s=scenario(); s:occupyWing(); s.player.number=2; s.wingman.number=1
    s.wingman.position.x=501000; local r=accept(s)
    assert(r.owner.unit==s.wingman and r.interdictionPlan.site.name=='TPL_AI_05'); s:assertClean()
end)
test('equal distance ties have deterministic ordering before the random draw',function()
    local s=scenario(); s.player.position.x=151000; s.player.position.z=800
    assert(accept(s).interdictionPlan.site.name=='TPL_AI_01'); s:assertClean()
end)
test('airborne selection needs no airport or minimum range',function()
    local s=scenario(); s.player.airborne=true; s.player.position.x=101000
    s.env.AIRBASE={FindByName=function() error('airport lookup forbidden') end}
    assert(accept(s).state=='ACTIVE'); s:assertClean()
end)
test('parallel wings reserve distinct nearest routes and distinct aliases',function()
    local s=scenario(); local a=accept(s); local p=s:addPilot('Other','ucid-b',20); s:tick(2)
    local b=accept(s,1,p)
    assert(a.interdictionPlan.site.name=='TPL_AI_01' and b.interdictionPlan.site.name=='TPL_AI_02')
    assert(a.spawn.group.name~=b.spawn.group.name and s.randomCalls[2].maximum==1); s:assertClean()
end)
test('both nearest routes busy does not fall back to the third route',function()
    local s=scenario(); accept(s); local p=s:addPilot('Other','ucid-b',20); s:tick(2); accept(s,1,p)
    p=s:addPilot('Third','ucid-c',30); s:tick(4); s:command('Task: Air Interdiction',p)
    assert(not s:mission(p) and #s.spawns==2); s:lastMessageContains('No available Air Interdiction routes')
    s:command('Task: Intercept',p); assert(s:mission(p)); s:assertClean()
end)
test('shared wing and UCID blockers also cover the new category',function()
    local s=scenario(); local r=accept(s); s:command('Task: Strike'); assert(s:mission()==r and #s.staticSpawns==0)
    local p=s:addPilot('Moved','ucid-a',20); s:tick(2); s:command('Task: Air Interdiction',p)
    assert(not s:mission(p) and #s.spawns==1); s:assertClean()
end)
test('moving vehicles and players do not move or redraw the briefing coordinate',function()
    local s=scenario(); local r=accept(s); local text=s.messages[#s.messages].text
    s.player.position.x=601000; for _,u in ipairs(r.spawn.group.units) do u.position.x=500000 end
    s:tick(2); s:command('Mission Status'); assert(s.messages[#s.messages].text==text and #s.randomCalls==1); s:assertClean()
end)
test('spawn keeps ME route, road speed, column interval and final loop',function()
    local s=scenario(); local r=accept(s); local route=r.spawn.group.route
    local original=s.interdictionTemplates.TPL_AI_01.route
    assert(#route.points==#original.points)
    for i,p in ipairs(route.points) do local me=original.points[i]
        assert(p.x==me.x and p.y==me.y and p.action==me.action and p.speed==me.speed)
    end
    assert(route.points[1].task.params.tasks[1].params.action.params.value==60.96)
    assert(route.points[4].task.params.tasks[1].params.nWaypointIndx==1); s:assertClean()
end)
test('three assigned loss events are required and duplicate events do not count twice',function()
    local s=scenario(); local r=accept(s); local units=r.spawn.group.units
    kill(s,units[1]); kill(s,units[1]); kill(s,units[2]); assert(r.state=='ACTIVE')
    kill(s,units[3]); assert(r.state=='RTB_PENDING'); s:assertClean()
end)
test('polling observes destruction even when loss events are missing',function()
    local s=scenario(); local r=accept(s); for _,u in ipairs(r.spawn.group.units) do u.alive=false end
    s:tick(2); assert(r.state=='RTB_PENDING'); s:assertClean()
end)
test('damaged living vehicles do not satisfy destruction',function()
    local s=scenario(); local r=accept(s); for _,u in ipairs(r.spawn.group.units) do u.life=1 end
    s:tick(2); assert(r.state=='ACTIVE'); s:assertClean()
end)
test('nil, exception and invalid life observations cannot count as destroyed',function()
    for _,mode in ipairs({'nil','exception','nan'}) do
        local s=scenario(); local r=accept(s); kill(s,r.spawn.group.units[1]); kill(s,r.spawn.group.units[2])
        local u=r.spawn.group.units[3]
        if mode=='nil' then function u:IsAlive() return nil end
        elseif mode=='exception' then u.lifeError=true else u.life=0/0 end
        s:tick(2); s:tick(4); assert(r.state=='ACTIVE')
        local n=0; for _,line in ipairs(s.logs) do if line:find('Air Interdiction observation unavailable',1,true) then n=n+1 end end
        assert(n==1); s:assertClean()
    end
end)
test('changed object identity is not a destruction observation',function()
    local s=scenario(); local r=accept(s); local u=r.spawn.group.units[3]
    kill(s,r.spawn.group.units[1]); kill(s,r.spawn.group.units[2]); u.id=u.id+10000; u.life=0
    s:tick(2); assert(r.state=='ACTIVE'); s:assertClean()
end)
test('loss of a different wing convoy never completes this wing',function()
    local s=scenario(); local a=accept(s); local p=s:addPilot('Other','ucid-b',20); s:tick(2)
    local b=accept(s,1,p); complete(s,b); assert(b.state=='RTB_PENDING' and a.state=='ACTIVE'); s:assertClean()
end)
test('retained raw object identity handles unavailable IDs on confirmed loss',function()
    local s=scenario(); local r=accept(s)
    for _,u in ipairs(r.spawn.group.units) do u.id=nil; u.raw.getID=function() return nil end; kill(s,u) end
    assert(r.state=='RTB_PENDING'); s:assertClean()
end)
test('completed status replays the result and RTB instructions without coordinates',function()
    local s=scenario(); local r=accept(s); complete(s,r)
    local text=s.messages[#s.messages].text
    assert(text:find('Air Interdiction Objective Complete',1,true) and text:find('All 3 convoy vehicles destroyed.',1,true))
    assert(not text:find('TARGET AREA',1,true)); s:command('Mission Status')
    assert(s.messages[#s.messages].text==text and s.messages[#s.messages].seconds==20); s:assertClean()
end)
test('safe RTB awards 150 in the new score category and closes the route',function()
    local s=scenario(); local r=accept(s); complete(s,r); recover(s)
    s:score(150); s:categoryScores({airInterdictionScore=150,strikeScore=0,interceptScore=0})
    assert(not s:mission() and r.spawn.group.destroyed); s:assertClean()
end)
test('post-objective ejection awards 90 only once',function()
    local s=scenario(); local r=accept(s); complete(s,r); s:event('Ejection',s.player); s:event('Dead',s.player)
    s:score(90); s:categoryScores({airInterdictionScore=90}); assert(not s:mission()); s:assertClean()
end)
test('pre-objective accident and voluntary abort award zero',function()
    for _,mode in ipairs({'accident','abort'}) do local s=scenario(); local r=accept(s)
        kill(s,r.spawn.group.units[1]); if mode=='accident' then s:event('Ejection',s.player) else s:command('Abort Mission') end
        s:score(0); assert(not s:mission() and r.spawn.group.destroyed); s:assertClean()
    end
end)
test('landing without completing the objective keeps the mission active',function()
    local s=scenario(); local r=accept(s); recover(s)
    assert(s:mission()==r and r.state=='ACTIVE'); s:score(0); s:assertClean()
end)
test('MP2 shares completion but settles each pilot individually before cleanup',function()
    local s=scenario(); s:occupyWing(); local r=accept(s); assert(#r.participants==2)
    complete(s,r); recover(s); assert(s:mission()==r and not r.spawn.group.destroyed); s:score(150)
    s:event('Ejection',s.wingman); s:score(90,s.wingman)
    assert(not s:mission() and r.spawn.group.destroyed); s:assertClean()
end)
test('early personal abort remains zero while the surviving wingman can finish',function()
    local s=scenario(); s:occupyWing(); local r=accept(s); s:abortSortie(s.player)
    complete(s,r); recover(s,s.wingman); s:score(0); s:score(150,s.wingman); s:assertClean()
end)
test('missing template affects its site without breaking other missions',function()
    local data=scenario().interdictionTemplates; data.TPL_AI_01=nil
    local s=scenario({interdictionTemplates=data}); local r=accept(s)
    assert(#s.errors==1 and r.interdictionPlan.site.name=='TPL_AI_02')
end)
test('invalid nearest road, side, count or loop is rejected without a third fallback',function()
    for _,mode in ipairs({'road','side','count','loop'}) do
        local data=scenario().interdictionTemplates
        for i=1,2 do local t=data[string.format('TPL_AI_%02d',i)]
            if mode=='road' then t.route.points[1].action='Off Road'
            elseif mode=='side' then t.CoalitionID=2 elseif mode=='count' then table.remove(t.units)
            else t.route.points[4].task.params.tasks={} end
        end
        local s=scenario({interdictionTemplates=data}); s:command('Task: Air Interdiction')
        assert(not s:mission() and #s.spawns==0 and #s.errors==2); s:lastMessageContains('No available Air Interdiction routes')
    end
end)
test('spawn constructor failure rolls back the reservation and wing lock',function()
    local s=scenario(); s.missingInterdictionTemplate='TPL_AI_01'; s:command('Task: Air Interdiction')
    assert(not s:mission() and next(module(s,'Missions').interdictionSites)==nil)
    s.missingInterdictionTemplate=nil; assert(accept(s).interdictionPlan.site.name=='TPL_AI_01')
end)
test('nil or exception after creation removes partially spawned convoys',function()
    for _,fault in ipairs({'failInterdictionSpawnBefore','failInterdictionSpawnAfter','nilInterdictionSpawnAfter','interdictionInvalidCount'}) do
        local s=scenario(); s[fault]=true; s:command('Task: Air Interdiction')
        assert(not s:mission() and next(module(s,'Missions').interdictionSites)==nil)
        for _,g in ipairs(s.spawns) do assert(g.destroyed) end
        s:lastMessageContains('ERROR: Air Interdiction setup failed.')
    end
end)
test('failed or unconfirmed cleanup holds its route and retries after five seconds',function()
    for _,mode in ipairs({'cleanupFailures','cleanupFalse','cleanupNoEffect'}) do
        local s=scenario(); local r=accept(s); local g=r.spawn.group; g[mode]=mode=='cleanupFailures' and 1 or true
        s:command('Abort Mission'); assert(not s:mission() and not g.destroyed)
        assert(module(s,'Missions').interdictionSites.TPL_AI_01==r.interdictionPlan)
        g[mode]=nil; s:tick(2); assert(not g.destroyed); s:tick(5)
        assert(g.destroyed and next(module(s,'Missions').interdictionSites)==nil)
    end
end)
test('cleanup-generated death events cannot award a completion',function()
    local s=scenario(); s.cleanupEvents=true; local r=accept(s); s:command('Abort Mission')
    assert(r.spawn.group.destroyed); for _,m in ipairs(s.messages) do assert(not m.text:find('Objective Complete',1,true)) end
    s:score(0); s:assertClean()
end)
test('a completed and cleaned route can be requested again with a new alias',function()
    local s=scenario(); local a=accept(s); s:command('Abort Mission'); local b=accept(s)
    assert(a.interdictionPlan.site==b.interdictionPlan.site and a.spawn.group.name~=b.spawn.group.name); s:assertClean()
end)
test('late human joiners and AI do not become registered participants',function()
    local s=scenario(); local r=accept(s); s:occupyWing(); s:tick(2)
    assert(#r.participants==1); complete(s,r); recover(s)
    assert(not s:mission()); s:score(150); s:score(0,s.wingman); s:assertClean()
end)
test('same-mission reload is guarded and initialization is announced once',function()
    local s=scenario(); local r=accept(s); s.reload()
    assert(s:mission()==r and #s.spawns==1); s:assertClean()
end)
test('native rollback removes a partially spawned group before its MOOSE wrapper is available',function()
    for _,fault in ipairs({'missing','exception'}) do
        local s=scenario(); local find=s.env.GROUP.FindByName
        s.env.GROUP.FindByName=function(self,name)
            if name:find('^DT_INTERDICTION_') then if fault=='exception' then error('wrapper unavailable') end; return nil end
            return find(self,name)
        end
        s.failInterdictionSpawnAfter=true; s:command('Task: Air Interdiction')
        assert(not s:mission() and s.spawns[1].destroyed and next(module(s,'Missions').interdictionSites)==nil)
    end
end)
test('coordinate formatting failure releases acceptance without spawning or reserving a route',function()
    local s=scenario(); s.env.COORDINATE.ToStringLLDDM=function() error('coordinate unavailable') end
    s:command('Task: Air Interdiction'); assert(not s:mission() and #s.spawns==0)
    assert(next(module(s,'Missions').interdictionSites)==nil); s:lastMessageContains('ERROR: Air Interdiction setup failed.')
end)
test('Life zero polling requires all three original vehicles',function()
    local s=scenario(); local r=accept(s); local units=r.spawn.group.units
    units[1].life=0; units[2].life=0; s:tick(2); assert(r.state=='ACTIVE')
    units[3].life=0; s:tick(4); assert(r.state=='RTB_PENDING'); s:assertClean()
end)
print(string.format('All %d Air Interdiction tests passed (simulated DCS/MOOSE).',count))
