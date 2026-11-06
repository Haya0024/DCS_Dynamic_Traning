local scenario = dofile('scripts/Intercept-TestHarness.lua')
local count = 0
local function test(label, run) run(); count=count+1; print('PASS: DYNAMIC-'..count..' '..label) end
local function module(s, wanted)
    local visited = {}
    local function find(fn)
        if visited[fn] then return end; visited[fn]=true
        for i=1,100 do
            local key,value=debug.getupvalue(fn,i); if not key then break end
            if key==wanted then return value end
            if type(value)=='function' then local result=find(value); if result then return result end end
        end
    end
    return assert(find(s.timers[1].callback),wanted)
end
local function dynamic(s, unit, id)
    unit=unit or s.player; id=id or unit.slotID
    unit.slotID=70000+id; s.connections[id].slot=tostring(unit.slotID)
    function unit:GetTemplate() error('No ME template for a dynamic player') end
    return { playerID=id,ucid=s.connections[id].ucid,name=s.connections[id].name,side=2,
        slot=s.connections[id].slot,unitName=unit.unitName,groupName=unit.group.name,
        objectID=unit.id,aircraftType=unit.kind }
end
local function recover(s,p)
    s:land(s:base(),s.time+1,p); p.position.y=0
    local start=s.time+1; for time=start,start+10 do
        -- Live host refreshes identities once per second during recovery.
        if s.rows then assert(s.env.DynamicTrainingPlayers.Update(s.rows)) end
        s:tick(time)
    end
end
local function team(s,p)
    s:tick(s.time+2); s:command('Create Mission Team')
    s:command('Join Mission Team 1: Pilot',p)
end
test('dynamic Hornet has no ME template yet binds its runtime aircraft and UCID',function()
    local s=scenario(); s.rows={dynamic(s)}; assert(s.env.DynamicTrainingPlayers.Update(s.rows))
    local people=assert(module(s,'Player').ForGroup(s.player.group.name))
    assert(#people==1 and people[1].ucid=='ucid-a' and people[1].objectID==s.player.id)
    s:command('Task: Air Interdiction'); assert(s:mission().participants[1].owner.ucid=='ucid-a'); s:assertClean()
end)
test('dynamic Apache binds pilot and CPG separately, including CPG-only occupancy',function()
    for _,only in ipairs({false,true}) do
        local s=scenario({aircraftType='AH-64D_BLK_II'}); local a=dynamic(s)
        s.connections[10].slot=a.slot..'_1'; a.slot=s.connections[10].slot
        s:addCrew(s.player,'CPG','ucid-cpg',21,tostring(s.player.slotID)..'_2')
        local b=s.env.UTILS.DeepCopy(a); b.playerID,b.ucid,b.name,b.slot=21,'ucid-cpg','CPG',s.connections[21].slot
        local rows={a,b}; if only then s.connections[10]=nil; s.player.name=nil; rows={b} end
        assert(s.env.DynamicTrainingPlayers.Update(rows))
        local people=assert(module(s,'Player').ForGroup(s.player.group.name))
        assert(#people==(only and 1 or 2)); for _,owner in ipairs(people) do assert(owner.ucid) end
    end
end)
test('stale directory and changed network slots cannot attribute old accounts',function()
    for _,fault in ipairs({'expired','slot','object','group','type','ucid'}) do
        local s=scenario(); local row=dynamic(s); assert(s.env.DynamicTrainingPlayers.Update({row}))
        if fault=='expired' then s.time=4 elseif fault=='slot' then s.connections[10].slot='123456'
        elseif fault=='object' then s.player.id=s.player.id+1 elseif fault=='group' then s.player.group.name='Different'
        elseif fault=='type' then s.player.kind='AH-64D_BLK_II'
        else s.connections[10].ucid='replacement-ucid' end
        local owner=module(s,'Player').ForUnit(s.player,s.player.group)
        assert(not owner or not owner.ucid)
    end
end)
test('malformed snapshots and duplicate people fail atomically',function()
    local s=scenario(); local row=dynamic(s); assert(s.env.DynamicTrainingPlayers.Update({row}))
    for _,fault in ipairs({'ucid','object','side','duplicate','sparse'}) do
        local r=s.env.UTILS.DeepCopy(row); local rows={r}
        if fault=='ucid' then r.ucid='' elseif fault=='object' then r.objectID=0 elseif fault=='side' then r.side=1
        elseif fault=='duplicate' then rows[2]=s.env.UTILS.DeepCopy(r) else rows[3]=r end
        assert(not s.env.DynamicTrainingPlayers.Update(rows))
        assert(module(s,'Player').ForUnit(s.player,s.player.group).ucid=='ucid-a')
    end
    assert(s.env.DynamicTrainingPlayers.Update({}))
    assert(not module(s,'Player').ForUnit(s.player,s.player.group).ucid)
end)
test('dynamic SOLO completion and return retain the existing 150-point receipt',function()
    local s=scenario(); s.rows={dynamic(s)}; assert(s.env.DynamicTrainingPlayers.Update(s.rows))
    s:command('Task: Air Interdiction'); local r=assert(s:mission()); s:complete(r.spawn.group)
    recover(s,s.player); s:score(150); assert(not s:mission()); s:assertClean()
end)
test('host collector resolves dynamic slot IDs to names, runtime IDs and both crew seats',function()
    local collect=dofile('server/player_directory.lua'); local s=scenario({aircraftType='AH-64D_BLK_II'})
    local row=dynamic(s); s.connections[10].slot=row.slot..'_1'
    s:addCrew(s.player,'CPG','ucid-cpg',21,row.slot..'_2')
    local control={UNIT_TYPE='type',UNIT_NAME='name',UNIT_GROUPNAME='group',UNIT_RUNTIME_ID='runtime'}
    function control.getUnitProperty(id,key)
        assert(id==s.player.slotID)
        return ({type=s.player.kind,name=s.player.unitName,group=s.player.group.name,runtime=s.player.id})[key]
    end
    local rows=collect.Collect(control,s.env.net); assert(#rows==2)
    assert(s.env.DynamicTrainingPlayers.Update(rows))
    assert(#module(s,'Player').ForAircraft(s.player,s.player.group)==2)
end)
test('host identity bridge quotes names as data rather than executable code',function()
    local s=scenario(); local row=dynamic(s)
    s.connections[10].name='Pilot "\nreturn bad() --'; row.name=s.connections[10].name
    local chunk=assert(loadfile('server/mission_bridge.lua')); local Bridge=chunk()
    local network={dostring_in=function(_,code)
        local env=setmetatable({a_do_script=function(source)
            local fn=assert(loadstring(source)); setfenv(fn,s.env); return fn()
        end},{__index=_G})
        local fn=assert(loadstring(code)); setfenv(fn,env); return fn(),true
    end}
    assert(Bridge.New(network).UpdatePlayers({row}))
    assert(module(s,'Player').ForUnit(s.player,s.player.group).name==row.name)
end)
test('two independent native groups form a wing and only its leader accepts',function()
    local s=scenario(); local p=s:addPilot('Second','ucid-b',20); s:tick(2)
    local staleAI=s.commands[p.group.name]['Task: Air Interdiction']
    local staleIntercept=s.commands[p.group.name]['Task: Intercept']; team(s,p)
    assert(not s.commands[p.group.name]['Task: Air Interdiction'])
    staleAI(); assert(not s:mission())
    s:command('Task: Air Interdiction'); local r=assert(s:mission())
    assert(#r.participants==2 and module(s,'Missions').groupLocks[p.group.name]==r and #s.spawns==1)
    staleIntercept(); assert(#s.spawns==1)
end)
test('shared briefing, completion and manual status reach every registered native group',function()
    local s=scenario(); local p=s:addPilot('Second','ucid-b',20); team(s,p)
    s:command('Task: Air Interdiction'); local r=assert(s:mission()); local groups={}
    for _,m in ipairs(s.messages) do if m.text:find('TARGET AREA:',1,true) then groups[m.group]=true end end
    assert(groups[s.player.group.name] and groups[p.group.name])
    s:complete(r.spawn.group); s:command('Mission Status',p); s:lastMessageContains('Objective Complete')
    assert(not s.messages[#s.messages].text:find('TARGET AREA:',1,true)); s:assertClean()
end)
test('shared objective settles each native group independently and retains locks until everyone finishes',function()
    local s=scenario(); local p=s:addPilot('Second','ucid-b',20); team(s,p)
    s:command('Task: Air Interdiction'); local r=assert(s:mission()); s:complete(r.spawn.group)
    recover(s,s.player); s:score(150); assert(s:mission()==r and module(s,'Missions').groupLocks[p.group.name]==r)
    s:event('Crash',p); s:score(90,p)
    assert(not s:mission() and next(module(s,'Missions').groupLocks)==nil); s:assertClean()
end)
test('one member pre-clear loss remains zero while the surviving aircraft finishes',function()
    local s=scenario(); local p=s:addPilot('Second','ucid-b',20); team(s,p)
    s:command('Task: Air Interdiction'); local r=assert(s:mission()); s:event('Crash',s.player)
    s:score(0); s:complete(r.spawn.group); recover(s,p); s:score(150,p); s:assertClean()
end)
test('shared Intercept waits for all groups to take off and then twenty seconds',function()
    local s=scenario(); local p=s:addPilot('Second','ucid-b',20); team(s,p)
    s:command('Task: Intercept'); local r=assert(s:mission()); s.player.airborne=true; s:tick(4)
    assert(r.state=='ARMED' and #s.spawns==0); p.airborne=true; s:tick(6)
    assert(r.state=='TAKEOFF_DELAY'); s:tick(26); assert(r.state=='ACTIVE' and #s.spawns==1); s:assertClean()
end)
test('joining, leaving and replacing crew cannot change a frozen assignment',function()
    local s=scenario(); local p=s:addPilot('Second','ucid-b',20); team(s,p)
    s:command('Task: Air Interdiction'); local r=assert(s:mission()); local w=module(s,'TrainingWings')
    assert(not pcall(w.Leave,p.group.name)); local late=s:addPilot('Late','ucid-c',30); s:tick(4)
    assert(not pcall(w.Join,late.group.name,1)); assert(#r.participants==2)
    local separate=assert(w.Create(late.group.name)); assert(separate.id==2 and #r.participants==2)
end)
test('mixed aircraft and unverified identities cannot join a mission team',function()
    local s=scenario(); local p=s:addPilot('Second','ucid-b',20); p.kind='AH-64D_BLK_II'; s:tick(2)
    local w=module(s,'TrainingWings'); w.Create(s.player.group.name)
    assert(not pcall(w.Join,p.group.name,1)); p.kind='FA-18C_hornet'; s.connections[20].ucid=''
    assert(not pcall(w.Join,p.group.name,1))
end)
test('idle wings dissolve on aircraft/crew change and stale join callbacks cannot reuse them',function()
    local s=scenario(); local p=s:addPilot('Second','ucid-b',20); team(s,p)
    local w=module(s,'TrainingWings'); s.connections[20].ucid='other'; s:tick(4)
    assert(not w.members[s.player.group.name] and not w.members[p.group.name])
    assert(not pcall(w.Join,p.group.name,1)); s:assertClean()
end)
test('leader abort releases every group, target and UCID lock',function()
    local s=scenario(); local p=s:addPilot('Second','ucid-b',20); team(s,p)
    s:command('Task: Air Interdiction'); s:command('Abort Mission')
    local m=module(s,'Missions'); assert(not s:mission() and next(m.groupLocks)==nil and next(m.pilots)==nil)
    assert(s.spawns[1].destroyed); s:assertClean()
end)
test('native dynamic group registration happens before looking up its UNIT wrapper',function()
    local s=scenario(); local player=module(s,'Player'); local findGroup=s.env.GROUP.FindByName
    local findUnit=s.env.UNIT.FindByName; local registered=false
    function s.player.raw:getGroup() return {getName=function() return s.player.group.name end} end
    s.env.GROUP.FindByName=function(self,name) if name==s.player.group.name then registered=true end; return findGroup(self,name) end
    s.env.UNIT.FindByName=function(self,name) assert(registered,'UNIT lookup preceded registration'); return findUnit(self,name) end
    assert(player.Groups()[s.player.group.name]); s:assertClean()
end)
test('Apache seat exchange within the same dynamic aircraft remains valid between host polls',function()
    local s=scenario({aircraftType='AH-64D_BLK_II'}); local a=dynamic(s)
    s.connections[10].slot=a.slot..'_1'; a.slot=s.connections[10].slot
    s:addCrew(s.player,'CPG','ucid-cpg',21,tostring(s.player.slotID)..'_2')
    local b=s.env.UTILS.DeepCopy(a); b.playerID,b.ucid,b.name,b.slot=21,'ucid-cpg','CPG',s.connections[21].slot
    assert(s.env.DynamicTrainingPlayers.Update({a,b})); local people=module(s,'Player').ForAircraft(s.player,s.player.group)
    s.connections[10].slot,s.connections[21].slot=s.connections[21].slot,s.connections[10].slot
    for _,owner in ipairs(people) do assert(module(s,'Player').IsControlling(owner)) end
end)
test('stale leave callback cannot dissolve a replacement wing in the same group',function()
    local s=scenario(); s:command('Create Mission Team')
    local old=s.commands[s.player.group.name]['Mission Team: 1 / Leave']
    s:command('Mission Team: 1 / Leave'); s:command('Create Mission Team'); old()
    assert(module(s,'TrainingWings').members[s.player.group.name].id==2); s:assertClean()
end)
local function seadArea(s,p)
    s.player.position.x,s.player.position.z=-80000,0
    p.position.x,p.position.z=-80000,0; s.zones={}
    for i,name in ipairs({'PALMYRA','SALAMIYAH','DUMAYR','TABQA'}) do
        local z={center={x=i*20000,y=0}}
        function z:GetVec2() return self.center end
        function z:GetRandomVec2() return self.center end
        function z:IsVec2InZone(point) return (point.x-self.center.x)^2+(point.y-self.center.y)^2<=3000^2 end
        s.zones['SEAD_ZONE_'..name]=z
    end
end
test('all five new-objective categories acquire one shared roster and release both native groups',function()
    for _,category in ipairs({'Intercept','CAP','SEAD','Strike','Air Interdiction'}) do
        local s=scenario(); local p=s:addPilot('Second','ucid-b',20)
        if category=='CAP' then s:addCAPZones() elseif category=='SEAD' then seadArea(s,p) end
        s.player.airborne,p.airborne=true,true; team(s,p)
        s.randomValues=category=='SEAD' and {1,1,1} or {}; s:command('Task: '..category); if category=='SEAD' then s:tick(s.time+1) end
        local r=assert(s:mission(),category); assert(#r.participants==2 and r.category==category)
        assert(module(s,'Missions').groupLocks[p.group.name]==r)
        s:command('Abort Mission'); assert(not s:mission() and next(module(s,'Missions').groupLocks)==nil); s:assertClean()
    end
end)
test('shared SEAD supports Immediate DEAD and preserved Follow-on DEAD with the same frozen roster',function()
    for _,mode in ipairs({'immediate','follow'}) do
        local s=scenario(); local p=s:addPilot('Second','ucid-b',20); seadArea(s,p)
        s.player.airborne,p.airborne=true,true; team(s,p); s.randomValues={1,1,1}
        s:command('Task: SEAD'); s:tick(s.time+1); local r=assert(s:mission())
        local radar=r.spawn.primaryUnits[1].unit; radar.alive=false; s:event('Dead',radar)
        assert(r.state=='RTB_PENDING')
        if mode=='immediate' then
            s:command('Continue as DEAD'); assert(r.state=='DEAD_ACTIVE' and #r.participants==2)
            for _,t in ipairs(r.deadTargets) do t.unit.alive=false; s:event('Dead',t.unit) end
            recover(s,s.player); recover(s,p); s:score(300); s:score(300,p)
        else
            s:command('Preserve Site for DEAD'); recover(s,s.player); recover(s,p)
            assert(not s:mission()); s.player.airborne,p.airborne=true,true
            s:command('Task: DEAD'); r=assert(s:mission()); assert(r.category=='DEAD' and #r.participants==2)
            for _,t in ipairs(r.deadTargets) do t.unit.alive=false; s:event('Dead',t.unit) end
            recover(s,s.player); recover(s,p); s:score(300); s:score(300,p)
        end
        s:assertClean()
    end
end)
test('identity publishing survives score-storage failure and stops after simulation stop',function()
    local callbacks, updates, logs = nil,0,{}
    local control={getUnitProperty=function() end,isServer=function() return true end,getRealTime=function() return 1 end,
        setUserCallbacks=function(c) callbacks=c end}
    local env=setmetatable({Sim=control,net={},lfs={writedir=function() return 'fixture/' end},
        log={INFO=1,WARNING=2,ERROR=3,write=function(_,_,message) logs[#logs+1]=message end},
        MissionBridge={description='fixture',New=function() return {UpdatePlayers=function() updates=updates+1; return true end,SetError=function() end} end},
        PlayerDirectory={Collect=function() return {} end}, PersistenceFS={New=function() return {} end},
        PersistenceService={New=function() return {phase='LOAD',Reset=function() end,Poll=function() error('disk denied') end} end}
    },{__index=_G})
    local chunk=assert(loadfile('server/DynamicTrainingPersistenceHook.lua')); setfenv(chunk,env); chunk()
    callbacks.onMissionLoadEnd(); callbacks.onSimulationFrame(); assert(updates==1)
    callbacks.onSimulationStop(); callbacks.onSimulationFrame(); assert(updates==1)
end)
test('two dynamic Apaches with four humans share a mission and retain four independent receipts',function()
    local s=scenario({aircraftType='AH-64D_BLK_II',playerPosition={x=81000-8*1852,y=0,z=800}})
    local p=s:addPilot('Second','ucid-b',20); p.kind='AH-64D_BLK_II'; p.position=s.env.UTILS.DeepCopy(s.player.position)
    local rows={dynamic(s),dynamic(s,p,20)}
    for i,unit in ipairs({s.player,p}) do
        local id=30+i; s:addCrew(unit,'CPG'..i,'ucid-cpg'..i,id,tostring(unit.slotID)..'_2')
        local row=s.env.UTILS.DeepCopy(rows[i]); row.playerID,row.ucid,row.name,row.slot=id,'ucid-cpg'..i,'CPG'..i,s.connections[id].slot
        rows[#rows+1]=row
    end
    s.rows=rows; assert(s.env.DynamicTrainingPlayers.Update(rows)); team(s,p)
    s:command('Task: Air Interdiction'); local r=assert(s:mission()); assert(#r.participants==4)
    s:complete(r.spawn.group); recover(s,s.player); recover(s,p)
    for _,ucid in ipairs({'ucid-a','ucid-b','ucid-cpg1','ucid-cpg2'}) do assert(module(s,'Scoring').players[ucid].totalScore==150) end
    assert(not s:mission()); s:assertClean()
end)
test('member personal abort is isolated and leader-only mission abort cannot erase the other aircraft',function()
    local s=scenario(); local p=s:addPilot('Second','ucid-b',20); team(s,p)
    s:command('Task: Air Interdiction'); local r=assert(s:mission())
    s:command('Abort Mission',p); assert(s:mission()==r)
    s:abortSortie(p); assert(s:mission()==r); s:complete(r.spawn.group); recover(s,s.player)
    s:score(150); s:score(0,p); s:assertClean()
end)
print(string.format('All %d dynamic player and mission team tests passed (simulated DCS/MOOSE/host APIs).',count))
