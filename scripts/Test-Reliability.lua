-- Failure-injection regressions discovered by the cross-module audit.
local scenario=dofile('scripts/Intercept-TestHarness.lua')
local count,failures=0,0
local function test(name,run)
    count=count+1; local ok,problem=pcall(run)
    print(string.format('%s: REL-%02d %s%s',ok and 'PASS' or 'FAIL',count,name,ok and '' or ': '..tostring(problem)))
    if not ok then failures=failures+1 end
end
local function module(s,wanted)
    for i=1,100 do local name,value=debug.getupvalue(s.timers[1].callback,i)
        if name==wanted then return value end; if not name then break end
    end; error('Missing module '..wanted)
end
local function sead(s,index)
    s.player.airborne=true; s.player.position={x=-80000,y=300,z=0}; s.zones={}
    for i,name in ipairs({'PALMYRA','SALAMIYAH','DUMAYR','TABQA'}) do
        local z={center={x=i*20000,y=0}}
        function z:GetVec2() return self.center end
        function z:GetRandomVec2() return self.center end
        function z:IsVec2InZone(p) return (p.x-self.center.x)^2+(p.y-self.center.y)^2<=3000^2 end
        s.zones['SEAD_ZONE_'..name]=z
    end
    s.randomValues={index or 1,1,1}; s:command('Task: SEAD'); s:tick(s.time+1)
    return s:mission()
end
local function cap(s)
    s:addCAPZones(); s:command('Task: CAP'); local r=assert(s:mission()); s.player.airborne=true
    s.player.position={x=r.capPlan.center.x,y=6000,z=r.capPlan.center.y}
    local start=s.time
    for t=start+1,start+31 do s:tick(t) end; assert(r.spawn); return r
end
local function completed(s,mp2)
    if mp2 then s:occupyWing(); s.wingman.airborne=true end
    s.player.airborne=true; s.generate(); s:complete()
    s:land(s:base(),10); if mp2 then s:land(s:base(),10,s.wingman) end
    return s:mission()
end

test('CAP keeps unconfirmed group deletion for a later retry',function()
    local s=scenario(); local r=cap(s); local g=r.spawn.group; g.cleanupNoEffect=1
    s:command('Abort Mission'); assert(not g.destroyed and module(s,'CAP').cleanup[g])
    s:tick(36); assert(g.destroyed)
end)
test('SEAD site remains tracked while deletion has no effect',function()
    local s=scenario(); local r=assert(sead(s)); local g,site=r.spawn.group,r.site; g.cleanupNoEffect=1
    s:command('Abort Mission'); assert(not g.destroyed and s:sites()[site.id]==site)
    s:tick(2); assert(g.destroyed and not s:sites()[site.id])
end)
test('SEAD setup failure retains a group when its first deletion fails',function()
    local s=scenario(); s.failRouteStop=true; s.spawnCleanupFailures=1; sead(s)
    assert(not s:mission() and #s.spawns==1 and not s.spawns[1].destroyed)
    s:tick(6); assert(s.spawns[1].destroyed)
end)
test('a different dead static identity cannot satisfy Strike',function()
    local s=scenario(); s.randomValues={2,1,2}; s:command('Task: Strike'); local r=assert(s:mission())
    local u=r.strikePlan.targets[1].unit; u.id=u.id+10000; u.alive=false
    s:tick(1); assert(r.state=='ACTIVE')
end)
test('a different dead radar identity cannot satisfy SEAD',function()
    local s=scenario(); local r=assert(sead(s,2)); local u=r.spawn.primaryUnits[1].unit
    u.id=u.id+10000; u.alive=false; s:tick(2); assert(r.state=='ACTIVE')
end)
test('a different dead vehicle identity cannot satisfy Immediate DEAD or erase its site',function()
    local s=scenario(); local r=assert(sead(s)); local u=r.spawn.primaryUnits[1].unit
    u.alive=false; s:event('Dead',u); s:command('Continue as DEAD')
    local targets=r.deadTargets
    targets[1].unit.id=targets[1].objectID+10000
    for _,t in ipairs(targets) do t.unit.alive=false end
    s:tick(2); assert(r.state=='DEAD_ACTIVE' and not targets[1].lost and r.site.observationUnavailable)
end)
test('recovery observation exceptions break the continuous ten-second hold',function()
    local s=scenario(); completed(s); for t=11,15 do s:tick(t) end
    local get=s.player.GetVelocityVec3; s.player.GetVelocityVec3=function() error('velocity unavailable') end
    for t=16,20 do s:tick(t) end
    s.player.GetVelocityVec3=get; s:tick(21); assert(s:mission())
    for t=22,31 do s:tick(t) end; s:score(150)
end)
test('one unavailable recovery observation does not block a healthy wingman',function()
    local s=scenario(); local r=completed(s,true)
    s.player.GetVelocityVec3=function() error('pilot velocity unavailable') end
    for t=11,21 do s:tick(t) end
    assert(not r.participants[1].done and r.participants[2].done); s:score(150,s.wingman); s:score(0)
end)
test('nonfinite recovery velocity cannot award a landing',function()
    local s=scenario(); completed(s); s.player.velocity.x=0/0
    for t=11,21 do s:tick(t) end
    assert(s:mission()); s:score(0)
end)
test('nonfinite recovery position cannot award a landing',function()
    local s=scenario(); completed(s); s.player.position.x=0/0
    for t=11,21 do s:tick(t) end
    assert(s:mission()); s:score(0)
end)
test('unknown airborne state cannot count as stopped on the ground',function()
    local s=scenario(); completed(s); s.player.InAir=function() return nil end
    for t=11,21 do s:tick(t) end
    assert(s:mission()); s:score(0)
end)
test('partial native creation failures in each group mission cannot leave live orphans',function()
    for _,category in ipairs({'Intercept','CAP','SEAD'}) do
        local s=scenario(); local new=s.env.SPAWN.NewWithAlias
        function s.env.SPAWN:NewWithAlias(template,alias)
            local spawner=new(self,template,alias); local create=spawner.SpawnFromVec3
            function spawner:SpawnFromVec3(position)
                local g=create(self,position); s.groups[g.name]=g
                g.raw.destroy=function() g:Destroy(false) end
                error('native group created before wrapper return')
            end
            return spawner
        end
        if category=='Intercept' then s.player.airborne=true; s.generate()
        elseif category=='CAP' then s:addCAPZones(); s:command('Task: CAP'); local r=s:mission()
            s.player.airborne=true; s.player.position={x=r.capPlan.center.x,y=6000,z=r.capPlan.center.y}
            for t=1,31 do s:tick(t) end
        else sead(s) end
        assert(not s:mission() and #s.spawns==1 and s.spawns[1].destroyed,category)
    end
end)

test('unknown airbase ownership breaks the hold without losing the landing context',function()
    local s=scenario(); completed(s); local p=s:mission().participants[1]
    local base=p.landing.base; for t=11,15 do s:tick(t) end
    base.side=nil; s:tick(16); assert(p.landing and not p.landing.stableSince)
    base.side=2; for t=17,27 do s:tick(t) end; s:score(150)
end)

test('nonfinite terrain height cannot approve a SEAD placement',function()
    for _,height in ipairs({0/0,math.huge,-math.huge}) do
        local s=scenario(); s.terrainHeight=function() return height end; sead(s)
        assert(not s:mission() and #s.spawns==0)
    end
end)

test('nonfinite obstacle positions or horizontal bounds cannot approve a SEAD placement',function()
    for _,kind in ipairs({'position','bounds'}) do
        local s=scenario(); s.scanObjects=function()
            return {{},{},{ {getPoint=function() return {x=kind=='position' and 0/0 or 1e6,y=0,z=0} end,
                getDesc=function() return {box={min={x=0,z=0},max={x=kind=='bounds' and 0/0 or 0,z=0}}} end} }}
        end
        sead(s); assert(not s:mission() and #s.spawns==0)
    end
end)

test('a skipped recovery monitor interval cannot satisfy continuous observation',function()
    local s=scenario(); completed(s); s:tick(11); s:tick(21)
    assert(s:mission()); s:score(0)
    for t=22,31 do s:tick(t) end; s:score(150)
end)

test('a skipped SEAD monitor interval cannot satisfy continuous radar suppression',function()
    local s=scenario(); local r=assert(sead(s)); local u=r.spawn.primaryUnits[1].unit
    u.life,u.radarEmitting=90,false; s:tick(2); s:tick(32)
    assert(r.state=='ACTIVE' and r.spawn.primaryUnits[1].offSince==32)
    for t=33,61 do s:tick(t) end; assert(r.state=='ACTIVE')
    s:tick(62); assert(r.primaryResult=='SUPPRESSED')
end)

test('partial creation without a MOOSE wrapper retries native cleanup after lock release',function()
    for _,category in ipairs({'Intercept','CAP','SEAD'}) do
        local s=scenario(); local new=s.env.SPAWN.NewWithAlias; s.spawnCleanupFailures=1
        function s.env.SPAWN:NewWithAlias(template,alias)
            local spawner=new(self,template,alias); local create=spawner.SpawnFromVec3
            function spawner:SpawnFromVec3(position)
                local g=create(self,position); s.groups[g.name]=g
                g.raw.destroy=function() g:Destroy(false) end
                -- Force the native fallback even though the native group exists.
                local find=s.env.GROUP.FindByName
                s.env.GROUP.FindByName=function(self,name) if name==g.name then return nil end; return find(self,name) end
                return nil
            end
            return spawner
        end
        if category=='Intercept' then s.player.airborne=true; s.generate()
        elseif category=='CAP' then s:addCAPZones(); s:command('Task: CAP'); local r=s:mission()
            s.player.airborne=true; s.player.position={x=r.capPlan.center.x,y=6000,z=r.capPlan.center.y}
            for t=1,31 do s:tick(t) end
        else sead(s) end
        assert(not s:mission() and #s.spawns==1 and not s.spawns[1].destroyed,category)
        s:tick(s.time+5); assert(s.spawns[1].destroyed,category)
    end
end)

test('repeated MP2 sorties release every mission/site/cleanup reference while preserving scores',function()
    local s=scenario(); s:occupyWing(); local expected=0
    for cycle=1,20 do
        for _,category in ipairs({'Intercept','CAP','SEAD','DEAD','Strike','Air Interdiction'}) do
            s.player.airborne,s.wingman.airborne=true,true; s.randomValues={}
            local r
            if category=='CAP' then r=cap(s)
            elseif category=='SEAD' or category=='DEAD' then
                r=assert(sead(s))
                if category=='DEAD' then
                    local radar=r.spawn.primaryUnits[1].unit; radar.alive=false; s:event('Dead',radar)
                    s:command('Continue as DEAD')
                end
            else
                if category=='Strike' then s.randomValues={cycle%2+1,1,cycle%3+1} end
                s:command('Task: '..category); r=assert(s:mission())
            end
            local targets=r.deadTargets or r.spawn.units
            for _,target in ipairs(targets) do target.unit.alive=false; s:event('Dead',target.unit) end
            local first=s.time+1
            for time=first,first+121 do
                if r.state=='RTB_PENDING' then break end
                s:tick(time)
            end
            assert(r.state=='RTB_PENDING',category)
            local home=s:base(); s:land(home,s.time+1); s:land(home,s.time,s.wingman)
            first=s.time+1
            for time=first,first+10 do s:tick(time) end
            assert(not s:mission(),category)
            local missions=module(s,'Missions')
            for _,name in ipairs({'wings','pilots','sites','strikeSites','interdictionSites'}) do
                assert(next(missions[name])==nil,category..' retained '..name)
            end
            assert(next(module(s,'CAP').cleanup)==nil and next(module(s,'CAP').cleaning)==nil)
            assert(next(module(s,'Intercept').pendingCleanup)==nil and next(module(s,'ObjectLifecycle').pending)==nil)
            expected=expected+(category=='DEAD' and 300 or 150)
            s:score(expected); s:score(expected,s.wingman)
        end
    end
    s:assertClean()
end)

assert(failures==0,string.format('%d reliability regressions failed',failures))
print(string.format('All %d reliability tests passed (failure-injected DCS/MOOSE).',count))
