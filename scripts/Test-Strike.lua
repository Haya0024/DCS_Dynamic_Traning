local scenario = dofile("scripts/Intercept-TestHarness.lua")
local count = 0
local function test(name, run) run(); count = count + 1; print("PASS: " .. name) end
local function module(s, wanted)
    for i = 1, 100 do
        local name, value = debug.getupvalue(s.timers[1].callback, i)
        if name == wanted then return value end
        if not name then break end
    end
    error("Missing module: " .. wanted)
end
local function accept(s, base, kind, player)
    s.randomValues = { 1, base or 1, kind or 3 }
    s:command("Task: Strike", player)
    return assert(s:mission(player))
end
local function destroy(s, object, event)
    object.alive, object.life = false, 0
    s:event("Dead", object, nil, nil, nil)
end
local function complete(s, r)
    for _, target in ipairs(r.strikePlan.targets) do destroy(s, target.unit) end
    assert(r.state == "RTB_PENDING")
end
local function recover(s, pilot)
    s:land(s:base(), s.time + 1, pilot)
    pilot = pilot or s.player
    pilot.position.y = 0
    s:tick(s.time + 1); s:tick(s.time + 10)
end

test("initialization caches and silently removes every ME original", function()
    local s = scenario(); local n = 0
    for name, static in pairs(s.statics) do
        assert(name:find("TPL_", 1, true) == 1 and not static.alive and static.destroyCalls == 1); n=n+1
    end
    assert(n == 54 and #s.staticSpawns == 0 and #s.randomCalls == 0); s:assertClean()
end)
test("ground acceptance spawns the complete selected site with one search coordinate", function()
    local s = scenario(); local r = accept(s, 1, 3)
    assert(r.category == "Strike" and r.state == "ACTIVE" and #s.staticSpawns == 7)
    assert(r.strikePlan.site.id == "SITE01" and r.strikePlan.target.kind.label == "Trucks")
    assert(#s.randomCalls == 3 and s.randomCalls[1].maximum == 2 and s.randomCalls[2].maximum == 2 and s.randomCalls[3].maximum == 3)
    local text = s.messages[#s.messages].text
    assert(text == "STRIKE MISSION (TOO)\nTARGET AREA: LL DDM 100000.000 300.000\n" ..
        "OBJECTIVE: Destroy both trucks; then RTB.\nReward per pilot: 150 points.\nRegistered pilots: 1.")
    assert(s.messages[#s.messages].seconds == 60); s:assertClean()
end)
test("either nearest site and all three target classes are selectable", function()
    for base=1,2 do for kind=1,3 do
        local s=scenario(); local r=accept(s,base,kind)
        assert(r.strikePlan.site.id == string.format("SITE%02d",base))
        assert(#s.staticSpawns == 7 and #r.strikePlan.targets == (kind==1 and 4 or kind==2 and 1 or 2)); s:assertClean()
        local plan = r.strikePlan
        assert(s.messages[#s.messages].text == "STRIKE MISSION (TOO)\nTARGET AREA: " ..
            plan.location .. "\nOBJECTIVE: " ..
            plan.target.kind.objective .. "; then RTB.\nReward per pilot: 150 points.\nRegistered pilots: 1.")
    end end
end)
test("nearest means acceptance location, including airborne players", function()
    local s=scenario(); s.player.airborne=true; s.player.position.x=499900
    local r=accept(s,2,2); assert(r.strikePlan.site.id=="SITE04")
    s.player.position.x=100; s:tick(2)
    assert(r.strikePlan.site.id=="SITE04" and #s.randomCalls==3); s:assertClean()
end)
test("wing leader is the occupied participant with the lowest flight number", function()
    local s=scenario(); s:occupyWing(); s.player.number=2; s.wingman.number=1
    s.wingman.position.x=499900; local r=accept(s)
    assert(r.owner.unit==s.wingman and r.strikePlan.site.id=="SITE05"); s:assertClean()
end)
test("site distance ties are deterministic before the equal random draw", function()
    local s=scenario(); s.player.position.x=150000
    local r=accept(s,1); assert(r.strikePlan.site.id=="SITE01"); s:assertClean()
end)
test("site selection is independent of airport ownership and runtime AIRBASE", function()
    local s=scenario(); s.env.AIRBASE={FindByName=function() error('no airport lookup') end}
    local r=accept(s); assert(r.strikePlan.site.id=="SITE01"); s:assertClean()
end)

test("non-RED facility members invalidate their site without creating targets", function()
    local templates=scenario().staticTemplates
    for _,g in pairs(templates) do g.coalition=2 end
    local s=scenario({strikeTemplates=templates})
    s:command("Task: Strike"); assert(not s:mission() and #s.staticSpawns==0)
    s:lastMessageContains("No available Strike targets"); s.generate(); assert(s:mission())
end)

test("site reservation keeps parallel wings on distinct nearest sites", function()
    local s=scenario(); local a=accept(s)
    local other=s:addPilot("Other","ucid-b",20); s:tick(2)
    local b=accept(s,1,2,other)
    assert(a.strikePlan.site.id=="SITE01" and b.strikePlan.site.id=="SITE02")
    assert(s.randomCalls[5].maximum==1); s:assertClean()
end)
test("both nearest sites busy rejects instead of silently choosing a third", function()
    local s=scenario(); accept(s)
    local other=s:addPilot("Other","ucid-b",20); s:tick(2); accept(s,1,2,other)
    local third=s:addPilot("Third","ucid-c",30); s:tick(4)
    s:command("Task: Strike",third); assert(not s:mission(third) and #s.staticSpawns==14)
    s:lastMessageContains("No available Strike targets"); s:assertClean()
end)
test("existing wing and UCID locks prevent spawning or redrawing", function()
    local s=scenario(); local r=accept(s); local draws=#s.randomCalls
    s:command("Task: Strike"); s.generate()
    assert(s:mission()==r and #s.randomCalls==draws and #s.staticSpawns==7); s:assertClean()
end)
test("TOO briefing uses the facility reference and explicit three-place DDM without elevation", function()
    local s=scenario(); s.terrainHeight=function() return 304.8 end
    local r=accept(s)
    assert(r.strikePlan.point.x==100000 and r.strikePlan.point.y==300)
    s:lastMessageContains("TARGET AREA: LL DDM 100000.000 300.000\n")
    assert(not s.messages[#s.messages].text:find('ft MSL',1,true)); s:assertClean()
    local file=assert(io.open('vendor/MOOSE/Moose.lua','rb'))
    local source=file:read('*a'):gsub('\r\n','\n'); file:close()
    local real=scenario()
    local scope=setmetatable({UTILS={}, COORDINATE=real.env.COORDINATE,
        _SETTINGS={LL_Accuracy=5}, coord={LOtoLL=function()
            return 33 + 23.4/60, 36 + 30.3/60
        end}}, {__index=_G})
    for _,pattern in ipairs({'function UTILS%.Round.-\nend', 'UTILS%.tostringLL = function.-\nend',
        'function COORDINATE:ToStringLLDDM.-\n  end'}) do
        setfenv(assert(loadstring(assert(source:match(pattern)))),scope)()
    end
    real.env.COORDINATE.ToStringLLDMS=function() error('Strike must use DDM') end
    accept(real)
    local degree=string.char(194,176)
    real:lastMessageContains('TARGET AREA: LL DDM 033'..degree.." 23.400'N   036"..degree.." 30.300'E\n")
    real:assertClean()
end)

test("all seven members preserve ME position heading type and receive fresh IDs", function()
    local s=scenario(); local r=accept(s)
    assert(#s.staticSpawns==7 and #r.strikePlan.objects==7 and #r.strikePlan.targets==2)
    for i,o in ipairs(s.staticSpawns) do
        assert(o.position.x==100000+(i-1)*10 and o.position.z==300+(i-1)*10 and o.heading==0.8)
        assert(o.id>10000 and o.unitName=="DT_STRIKE_"..r.assignmentID.."_"..i)
        assert(o.kind==dofile('src/config.lua').strike.members[i].type)
    end
    s:assertClean()
end)

test("both trucks must be destroyed; damage and unrelated component losses are insufficient", function()
    local s=scenario(); local r=accept(s); local targets=r.strikePlan.targets
    targets[1].unit.life=1; s:tick(1); assert(r.state=="ACTIVE")
    destroy(s,s.staticSpawns[1]); destroy(s,s.staticSpawns[2]); s:tick(2); assert(r.state=="ACTIVE")
    destroy(s,targets[1].unit); assert(r.state=="ACTIVE")
    destroy(s,targets[2].unit); assert(r.state=="RTB_PENDING"); s:assertClean()
end)

test("polling detects zero life without a delivered death event", function()
    local s=scenario(); local r=accept(s,1,2); r.strikePlan.targets[1].unit.life=0
    s:tick(1); assert(r.state=="RTB_PENDING"); s:assertClean()
end)
test("unknown, failed and mismatched identities never prove destruction", function()
    for _,mode in ipairs({'nil','error','id','life'}) do
        local s=scenario(); local r=accept(s,1,2); local o=r.strikePlan.targets[1].unit
        if mode=='nil' then o.IsAlive=function() return nil end
        elseif mode=='error' then o.IsAlive=function() error('unknown') end
        elseif mode=='id' then o.id=o.id+1; o.life=0
        else o.life=nil end
        s:tick(1); s:tick(2); assert(r.state=='ACTIVE'); s:assertClean()
    end
end)
test("static death events use IniDCSStatic and cannot match unrelated objects", function()
    local s=scenario(); local r=accept(s,1,2); local strike=module(s,'Strike')
    assert(not strike.RecordLoss(r.strikePlan,{initiator=s.player.raw}))
    local o=r.strikePlan.targets[1].unit
    local event={IniDCSStatic=o.raw}
    assert(strike.RecordLoss(r.strikePlan,event)); s:tick(1); assert(r.state=='RTB_PENDING'); s:assertClean()
end)
test("status recalls exact published coordinates then completion only for twenty seconds", function()
    local s=scenario(); local r=accept(s); local brief=s.messages[#s.messages].text
    destroy(s,r.strikePlan.targets[1].unit)
    s.env.COORDINATE.NewFromVec2=function() error('must not regenerate') end
    s:command('Mission Status'); assert(s.messages[#s.messages].text==brief)
    complete(s,r); local done=s.messages[#s.messages].text
    s:command('Mission Status'); assert(s.messages[#s.messages].text==done and s.messages[#s.messages].seconds==20)
    assert(not done:find('TARGET AREA:',1,true)); s:assertClean()
end)
test("completed recovery awards Strike150 once and preserves statistics", function()
    local s=scenario(); local r=accept(s,1,2); complete(s,r); recover(s)
    s:score(150); s:categoryScores({strikeScore=150,missionCount=1,rtbSuccessCount=1})
    s:event('Dead',s.player); s:score(150); assert(not s:mission()); s:assertClean()
end)
test("completed accidents award ninety and unfinished accidents award zero", function()
    for _,completed in ipairs({false,true}) do
        local s=scenario(); local r=accept(s,1,3); if completed then complete(s,r) end
        s:event('Crash',s.player); s:score(completed and 90 or 0)
        assert(not s:mission()); s:assertClean()
    end
end)
test("abort always awards zero, removes statics and permits another sortie", function()
    local s=scenario(); local r=accept(s); complete(s,r); s:command('Abort Mission')
    s:score(0); for _,o in ipairs(s.staticSpawns) do assert(not o.alive) end
    local next=accept(s); assert(next.strikePlan.site.id=='SITE01'); s:assertClean()
end)
test("RTB before completion keeps the active facility and lock", function()
    local s=scenario(); local r=accept(s); recover(s)
    assert(s:mission()==r and r.state=='ACTIVE' and #s.staticSpawns==7); s:score(0); s:assertClean()
end)
test("MP2 pre-clear loss stays at zero while its wingmate completes and recovers", function()
    local s=scenario(); s:occupyWing(); local r=accept(s)
    s:event('Ejection',s.player); complete(s,r); recover(s,s.wingman)
    s:score(0); s:score(150,s.wingman); assert(not s:mission()); s:assertClean()
end)
test("partial static spawn failure cleans created targets and releases locks", function()
    local s=scenario(); s.failStaticAt=2; s:command('Task: Strike')
    assert(not s:mission() and #s.staticSpawns==1 and not s.staticSpawns[1].alive and #s.errors==1)
    s.failStaticAt=nil; assert(accept(s).strikePlan.site.id=='SITE01')
end)
test("a throw after native creation still retains and cleans the object", function()
    local s=scenario(); s.throwStaticAt=2; s:command('Task: Strike')
    assert(not s:mission() and #s.staticSpawns==2)
    for _,o in ipairs(s.staticSpawns) do assert(not o.alive) end
    assert(#s.errors==1)
end)
test("cleanup failure retains the site reservation until successful retry", function()
    local s=scenario(); local r=accept(s); local old=r.strikePlan.targets[1].unit
    old.cleanupFailures=1; s:command('Abort Mission'); assert(old.alive and not s:mission())
    local next=accept(s); assert(next.strikePlan.site.id=='SITE02')
    s:tick(5); assert(not old.alive); s:command('Abort Mission')
    assert(accept(s).strikePlan.site.id=='SITE01'); s:assertClean()
end)
test("native statics created before MOOSE registration are cleaned by the rollback fallback", function()
    local s=scenario(); s.throwStaticAt=1
    s.env.STATIC.FindByName=function() return nil end
    s:command('Task: Strike')
    assert(not s:mission() and #s.staticSpawns==1 and not s.staticSpawns[1].alive and #s.errors==1)
    assert(not next(module(s,'Missions').strikeSites))
end)
test("no-effect deletion cannot release a site even when Destroy returns nil", function()
    local s=scenario(); local r=accept(s); local old=r.strikePlan.targets[1].unit
    old.cleanupNoEffect=true; s:command('Abort Mission'); s:tick(10)
    assert(old.alive and accept(s).strikePlan.site.id=='SITE02'); s:assertClean()
end)
test("new sorties use fresh static identities and stale death events do not complete them", function()
    local s=scenario(); local first=accept(s,1,2); local old=first.strikePlan.targets[1].unit
    s:command('Abort Mission'); local r=accept(s,1,2)
    s:event('Dead',old); assert(r.state=='ACTIVE')
    assert(r.strikePlan.targets[1].objectID~=old.id); s:assertClean()
end)
test("missing templates fail only that site without stopping other mission categories", function()
    local s=scenario({strikeTemplates={}})
    s:command('Task: Strike'); assert(not s:mission())
    s.player.airborne=true; s.generate(); assert(s:mission().category=='Intercept' and #s.errors==54)
end)
test("coordinate formatting failure rolls back before any static spawn", function()
    local s=scenario(); s.env.COORDINATE.ToStringLLDDM=function() error('coordinate unavailable') end
    s:command('Task: Strike'); assert(not s:mission() and #s.staticSpawns==0 and #s.errors==1)
end)

test("a site stays unavailable until every ME original has actually been removed", function()
    local s=scenario({strikeOriginalCleanupFailures=1})
    local original=s.statics['TPL_CMD_SITE01_01-1']; assert(original.alive)
    local r=accept(s); assert(r.strikePlan.site.id=='SITE02')
    s:tick(1); assert(not original.alive)
    s:command('Abort Mission'); assert(accept(s).strikePlan.site.id=='SITE01'); s:assertClean()
end)

test("optional smoke marks each selected facility fifty meters north at ground height", function()
    for kind=1,3 do
        local s=scenario(); assert(not s.commands[s.player.group.name]['Mark Strike Target'])
        s.terrainHeight=function() return 123 end
        local r=accept(s,1,kind); assert(#s.smokes==0)
        local draws=#s.randomCalls; s:command('Mark Strike Target')
        local mark=assert(s.smokes[1]); assert(mark.color==1)
        assert(mark.point.x==r.strikePlan.point.x+50 and mark.point.z==r.strikePlan.point.y and mark.point.y==123)
        assert(#s.randomCalls==draws and #s.smokes==1 and r.state=='ACTIVE')
        assert(s.messages[#s.messages].text=='Strike target marked with RED smoke.\nSmoke is 50 m north of the target; lasts 120 seconds.')
        assert(s.messages[#s.messages].seconds==10); s:assertClean()
    end
end)
test("smoke requests cannot stack or replace the coordinate briefing and can be renewed after expiry", function()
    local s=scenario(); accept(s); local brief=s.messages[#s.messages].text
    s:command('Mark Strike Target'); local old=s.smokes[1].name
    s:command('Mark Strike Target'); assert(#s.smokes==1)
    s:lastMessageContains('Strike target already marked. Try again later.')
    s:command('Mission Status'); assert(s.messages[#s.messages].text==brief)
    s:tick(119); assert(s.activeSmokes[old]); s:tick(120); assert(not s.activeSmokes[old])
    s:command('Mark Strike Target'); assert(#s.smokes==2 and s.smokes[2].name~=old); s:assertClean()
end)
test("completion stops smoke removes its menu and invalidates a saved callback", function()
    local s=scenario(); local r=accept(s); local callback=s.commands[s.player.group.name]['Mark Strike Target']
    s:command('Mark Strike Target'); complete(s,r)
    assert(not next(s.activeSmokes) and not s.commands[s.player.group.name]['Mark Strike Target'])
    callback(); s:lastMessageContains('Strike target marking is no longer available.')
    assert(#s.smokes==1); s:assertClean()
end)
test("aborted assignment callbacks cannot mark a replacement Strike sortie", function()
    local s=scenario(); accept(s); local callback=s.commands[s.player.group.name]['Mark Strike Target']
    s:command('Mark Strike Target'); s:command('Abort Mission'); assert(not next(s.activeSmokes))
    accept(s,1,3); callback(); assert(#s.smokes==1)
    s:lastMessageContains('Strike target marking is no longer available.'); s:assertClean()
end)
test("MP2 smoke remains available for the surviving participant after individual abort", function()
    local s=scenario(); s:occupyWing(); local r=accept(s)
    s:abortSortie(s.player); assert(s:mission()==r)
    s:command('Mark Strike Target',s.wingman); assert(#s.smokes==1)
    s:abortSortie(s.wingman); assert(not next(s.activeSmokes) and not s:mission()); s:assertClean()
end)
test("parallel Strike wings mark only their own facilities with unique effect names", function()
    local s=scenario(); local a=accept(s)
    local other=s:addPilot('Other','ucid-b',20); s:tick(2); local b=accept(s,1,2,other)
    s:command('Mark Strike Target'); s:command('Mark Strike Target',other)
    assert(#s.smokes==2 and s.smokes[1].name~=s.smokes[2].name)
    assert(s.smokes[1].point.x==a.strikePlan.point.x+50 and s.smokes[2].point.x==b.strikePlan.point.x+50)
    s:command('Abort Mission'); assert(not s.activeSmokes[s.smokes[1].name] and s.activeSmokes[s.smokes[2].name])
    s:assertClean()
end)
test("smoke API failure preserves assignment score and briefing and allows a retry", function()
    local s=scenario(); local r=accept(s); local brief=s.messages[#s.messages].text
    s.failSmokeBefore=true; s:command('Mark Strike Target')
    assert(s:mission()==r and r.state=='ACTIVE' and #s.errors==1 and not next(s.activeSmokes))
    s:lastMessageContains('ERROR: Strike target smoke failed. See DCS log; retry later.')
    s:command('Mission Status'); assert(s.messages[#s.messages].text==brief)
    s:score(0); s.failSmokeBefore=nil; s:command('Mark Strike Target'); assert(#s.smokes==1)
end)
test("post-emission error retains the effect for a failed stop retry without aborting the sortie", function()
    local s=scenario(); local r=accept(s); s.failSmokeAfter=true; s.smokeStopFailures=1
    s:command('Mark Strike Target'); local name=s.smokes[1].name
    assert(s.activeSmokes[name] and s:mission()==r and #s.errors==1)
    s.failSmokeAfter=nil; s:command('Mark Strike Target'); assert(#s.smokes==1)
    s:tick(5); assert(not s.activeSmokes[name]); s:command('Mark Strike Target'); assert(#s.smokes==2)
end)
test("failed smoke stop retries independently and cannot stop a later sortie's effect", function()
    local s=scenario(); accept(s); s:command('Mark Strike Target'); local old=s.smokes[1].name
    s.smokeStopFailures=1; s:command('Abort Mission')
    assert(s.activeSmokes[old]); local r=accept(s); assert(r.strikePlan.site.id=='SITE01')
    s:command('Mark Strike Target'); local current=s.smokes[2].name
    s:tick(5); assert(not s.activeSmokes[old] and s.activeSmokes[current]); s:assertClean()
end)
test("a late occupant without controlling registered participants cannot use a stale marker callback", function()
    local s=scenario(); local r=accept(s); local callback=s.commands[s.player.group.name]['Mark Strike Target']
    s.player.name=nil; s:occupyWing('Late','ucid-late'); s:tick(2)
    assert(not s.commands[s.player.group.name]['Mark Strike Target'])
    callback(); assert(#s.smokes==0 and s:mission()==r)
    s:lastMessageContains('Strike target marking is no longer available.'); s:assertClean()
end)

test("MP2 Strike menus keep smoke and both personal aborts reachable within ten entries per page", function()
    local s=scenario(); s:occupyWing(); accept(s)
    for _,page in ipairs(s.menuPages[s.player.group.name]) do assert(page.entries<=10) end
    assert(#s.menuPages[s.player.group.name]==2)
    assert(s.commands[s.player.group.name]['Mark Strike Target'])
    s:command('Mark Strike Target'); s:abortSortie(s.player); s:abortSortie(s.wingman)
    assert(not s:mission()); s:assertClean()
end)

test("the sixth site can be selected from the current leader position", function()
    local s=scenario(); s.player.position.x=600000
    assert(accept(s).strikePlan.site.id=='SITE06'); s:assertClean()
end)

test("command objective ignores all six scenery objects and completion leaves surviving scenery", function()
    local s=scenario(); local r=accept(s,1,2)
    assert(#r.strikePlan.targets==1 and r.strikePlan.targets[1].member==1)
    complete(s,r)
    for i=2,7 do assert(s.staticSpawns[i].alive) end
    s:command('Abort Mission')
    for _,o in ipairs(s.staticSpawns) do assert(not o.alive) end
    s:assertClean()
end)

test("failed scenery cleanup holds the site reservation just like failed target cleanup", function()
    local s=scenario(); local r=accept(s,1,2); local scenery=s.staticSpawns[7]
    scenery.cleanupFailures=1; s:command('Abort Mission')
    assert(scenery.alive and module(s,'Missions').strikeSites.SITE01==r.strikePlan)
    assert(accept(s).strikePlan.site.id=='SITE02')
    s:tick(5); assert(not scenery.alive and not module(s,'Missions').strikeSites.SITE01)
    s:assertClean()
end)

test("a missing non-reference member invalidates only its site and removes the other originals", function()
    local templates=scenario().staticTemplates; templates['TPL_CONT_SITE01_03-1']=nil
    local s=scenario({strikeTemplates=templates}); local r=accept(s)
    assert(r.strikePlan.site.id=='SITE02' and #s.errors==1)
    for name,o in pairs(s.statics) do if name:find('SITE01',1,true) then assert(not o.alive) end end
end)

test("mixed actual unit names resolve through their stable ME group names", function()
    local s=scenario()
    assert(s.staticTemplates['TPL_CMD_SITE01_01-1'] and s.staticTemplates['TPL_CONT_SITE01_02'])
    local r=accept(s,1,2); assert(#r.strikePlan.objects==7); s:assertClean()
end)

test("any two of four containers complete the objective for all six pairs without another random draw", function()
    for a=1,3 do for b=a+1,4 do
        local s=scenario(); local r=accept(s,1,1); local targets=r.strikePlan.targets
        assert(#targets==4 and r.strikePlan.requiredCount==2 and #s.randomCalls==3)
        s:lastMessageContains('OBJECTIVE: Destroy any 2 of the 4 storage containers; then RTB.')
        destroy(s,targets[a].unit); assert(r.state=='ACTIVE')
        destroy(s,targets[a].unit); assert(r.state=='ACTIVE')
        destroy(s,targets[b].unit); assert(r.state=='RTB_PENDING')
        local alive=0; for _,t in ipairs(targets) do if t.unit.alive then alive=alive+1 end end
        assert(alive==2 and s.staticSpawns[1].alive and s.staticSpawns[6].alive)
        recover(s); s:score(150); for _,o in ipairs(s.staticSpawns) do assert(not o.alive) end
        s:assertClean()
    end end
end)

test("container polling needs two confirmed losses and unknown or damaged members cannot fill the quota", function()
    local s=scenario(); local r=accept(s,1,1); local targets=r.strikePlan.targets
    targets[1].unit.life=0; targets[2].unit.life=1
    targets[3].unit.IsAlive=function() return nil end
    targets[4].unit.GetLife=function() error('unavailable') end
    s:tick(1); assert(r.state=='ACTIVE')
    targets[2].unit.life=0; s:tick(2); assert(r.state=='RTB_PENDING'); s:assertClean()
end)

local function acceptPB(s, kind, player, base)
    s.randomValues={2,base or 1,kind or 1}; s:command('Task: Strike',player)
    return assert(s:mission(player))
end

test('PB draws command fuel or ammunition equally after mode and nearest-site draws',function()
    for kind,index in ipairs({1,8,9}) do
        local s=scenario(); local p=acceptPB(s,kind).strikePlan
        assert(p.attackMode=='PB' and #p.targets==1 and p.targets[1].member==index and p.requiredCount==1)
        assert(#s.randomCalls==3 and s.randomCalls[1].maximum==2 and s.randomCalls[2].maximum==2 and s.randomCalls[3].maximum==3)
        assert(#s.staticSpawns==9 and #p.objects==9); s:assertClean()
    end
end)
test('PB publishes the exact five-line DMS and elevation briefing for each target',function()
    local objectives={'Destroy the command center','Destroy the fuel tank','Destroy the ammunition depot'}
    for kind,index in ipairs({1,8,9}) do
        local s=scenario(); s.terrainHeight=function() return 304.8 end
        local p=acceptPB(s,kind).strikePlan; local x,y=100000+(index-1)*10,300+(index-1)*10
        assert(p.point.x==x and p.point.y==y and p.elevationFt==1000)
        assert(s.messages[#s.messages-1].text=='Strike mission accepted.' and s.messages[#s.messages-1].seconds==10)
        assert(s.messages[#s.messages].text==string.format('STRIKE MISSION (PB)\nTARGET AREA: LL DMS %.2f %.2f, 1000 ft MSL\nOBJECTIVE: %s; then RTB.\nReward per pilot: 150 points.\nRegistered pilots: 1.',x,y,objectives[kind]))
        assert(s.messages[#s.messages].seconds==60); s:assertClean()
    end
end)
test('PB DMS hundredths are independent of global precision using bundled MOOSE',function()
    local s=scenario(); s.terrainHeight=function() return 304.8 end
    local file=assert(io.open('vendor/MOOSE/Moose.lua','rb')); local source=file:read('*a'):gsub('\r\n','\n'); file:close()
    local scope=setmetatable({UTILS={},COORDINATE=s.env.COORDINATE,_SETTINGS={LL_Accuracy=5},
        coord={LOtoLL=function(v) assert(v.x==100070 and v.z==370)
            return 33+12/60+34.56/3600,36+45/60+12.34/3600 end}},{__index=_G})
    for _,pattern in ipairs({'function UTILS%.Round.-\nend','UTILS%.tostringLL = function.-\nend',
        'function COORDINATE:ToStringLLDMS.-\n  end'}) do setfenv(assert(loadstring(assert(source:match(pattern)))),scope)() end
    s.env.COORDINATE.ToStringLLDDM=function() error('PB must use DMS') end
    acceptPB(s,2); local degree=string.char(194,176)
    s:lastMessageContains('TARGET AREA: LL DMS 033'..degree..'12\'34.56"N 036'..degree..'45\'12.34"E, 1000 ft MSL')
    s:assertClean()
end)
test('PB elevation uses the selected object ground location rather than facility reference or roof',function()
    for kind,index in ipairs({1,8,9}) do
        local s=scenario(); s.terrainHeight=function(p) return p.x==100000+(index-1)*10 and 123.45 or 900 end
        local r=acceptPB(s,kind)
        assert(r.strikePlan.elevationFt==405 and r.strikePlan.targets[1].unit.position.y==0); s:assertClean()
    end
end)
test('PB status freezes mode target and coordinates through movement scenery losses and smoke',function()
    local s=scenario(); local r=acceptPB(s,2); local text=s.messages[#s.messages].text; local draws=#s.randomCalls
    destroy(s,s.staticSpawns[1]); s.player.position.x=600000; s:command('Mark Strike Target')
    s.env.COORDINATE.ToStringLLDMS=function() error('must not regenerate') end
    s:command('Mission Status'); assert(s.messages[#s.messages].text==text and #s.randomCalls==draws)
    complete(s,r); local done=s.messages[#s.messages].text
    s:command('Mission Status'); assert(s.messages[#s.messages].text==done and s.messages[#s.messages].seconds==20)
    assert(not done:find('TARGET AREA:',1,true) and not done:find('ft MSL',1,true)); s:assertClean()
end)
test('PB counts only the selected building even if all eight other objects are destroyed',function()
    for kind,index in ipairs({1,8,9}) do
        local s=scenario(); local r=acceptPB(s,kind)
        for i,o in ipairs(s.staticSpawns) do if i~=index then destroy(s,o) end end
        assert(r.state=='ACTIVE'); destroy(s,s.staticSpawns[index]); assert(r.state=='RTB_PENDING'); s:assertClean()
    end
end)
test('PB fuel and ammunition reject damage unknown life and replaced identities',function()
    for kind=2,3 do for _,mode in ipairs({'damage','unknown','identity'}) do
        local s=scenario(); local r=acceptPB(s,kind); local o=r.strikePlan.targets[1].unit
        if mode=='damage' then o.life=1 elseif mode=='unknown' then o.life=nil else o.id=o.id+1; o.life=0 end
        s:tick(2); assert(r.state=='ACTIVE'); if mode=='identity' then o.id=o.id-1 end
        o.life=0; s:tick(4); assert(r.state=='RTB_PENDING'); s:assertClean()
    end end
end)
test('each PB target awards Strike150 after recovery and removes all nine objects',function()
    for kind=1,3 do local s=scenario(); local r=acceptPB(s,kind); complete(s,r); recover(s)
        s:score(150); s:categoryScores({strikeScore=150,missionCount=1,rtbSuccessCount=1})
        assert(not s:mission()); for _,o in ipairs(s.staticSpawns) do assert(not o.alive) end; s:assertClean()
    end
end)
test('PB awards ninety after completion accident and zero for pre-clear accident or abort',function()
    for _,mode in ipairs({'completed','unfinished','abort'}) do
        local s=scenario(); local r=acceptPB(s,3); if mode~='unfinished' then complete(s,r) end
        if mode=='abort' then s:command('Abort Mission') else s:event('Ejection',s.player) end
        s:score(mode=='completed' and 90 or 0); assert(not s:mission()); s:assertClean()
    end
end)
test('PB and TOO share site reservations while keeping their own objectives and creation counts',function()
    local s=scenario(); local a=acceptPB(s,2); local other=s:addPilot('Other','ucid-b',20); s:tick(2)
    local b=accept(s,1,1,other)
    assert(a.strikePlan.site.id=='SITE01' and b.strikePlan.site.id=='SITE02' and #s.staticSpawns==16)
    complete(s,a); assert(b.state=='ACTIVE'); s:assertClean()
end)
test('missing PB-only templates do not disable the existing TOO facility',function()
    local data=scenario().staticTemplates
    for name,group in pairs(data) do if group.name=='TPL_TANK_SITE01_01' then data[name]=nil end end
    local s=scenario({strikeTemplates=data}); local r=accept(s)
    assert(r.strikePlan.site.id=='SITE01' and #s.staticSpawns==7 and #s.errors==1)
    s:command('Abort Mission'); assert(acceptPB(s,2).strikePlan.site.id=='SITE02')
end)
test('invalid PB nearest sites never switch mode or fall back to the third site',function()
    local data=scenario().staticTemplates
    for _,g in pairs(data) do if g.name=='TPL_AMMO_SITE01_01' or g.name=='TPL_AMMO_SITE02_01' then g.units[1].type='Wrong type' end end
    local s=scenario({strikeTemplates=data}); s.randomValues={2}; s:command('Task: Strike')
    assert(not s:mission() and #s.staticSpawns==0 and #s.randomCalls==1)
    s:lastMessageContains('No available Strike targets'); assert(accept(s).strikePlan.site.id=='SITE01')
end)
test('PB coordinate and terrain failures release locks before any spawn',function()
    for _,fault in ipairs({'format','height','nan'}) do
        local s=scenario()
        if fault=='format' then s.env.COORDINATE.ToStringLLDMS=function() error('coordinate unavailable') end
        elseif fault=='height' then s.env.COORDINATE.GetLandHeight=function() return nil end
        else s.env.COORDINATE.GetLandHeight=function() return 0/0 end end
        s.randomValues={2,1,2}; s:command('Task: Strike')
        assert(not s:mission() and #s.staticSpawns==0 and not next(module(s,'Missions').strikeSites))
        s:lastMessageContains('ERROR: Strike setup failed.')
    end
end)
test('PB spawn failures at added tank or depot remove every partially created object',function()
    for _,fault in ipairs({'failStaticAt','throwStaticAt'}) do for i=8,9 do
        local s=scenario(); s[fault]=i; s.randomValues={2,1,3}; s:command('Task: Strike')
        assert(not s:mission() and not next(module(s,'Missions').strikeSites))
        for _,o in ipairs(s.staticSpawns) do assert(not o.alive) end
    end end
end)
test('PB scenery depot deletion failure keeps the site reserved until confirmed cleanup',function()
    local s=scenario(); local r=acceptPB(s,1); local o=s.staticSpawns[9]; o.cleanupFailures=1
    s:command('Abort Mission'); assert(o.alive and module(s,'Missions').strikeSites.SITE01==r.strikePlan)
    assert(accept(s).strikePlan.site.id=='SITE02'); s:tick(5)
    assert(not o.alive and not module(s,'Missions').strikeSites.SITE01); s:assertClean()
end)
test('PB smoke uses fifty meters north of the same precise target point',function()
    local s=scenario(); local r=acceptPB(s,2); s:command('Mark Strike Target')
    local p=r.strikePlan.point; assert(p.x==100070 and s.smokes[1].point.x==p.x+50 and s.smokes[1].point.z==p.y)
    complete(s,r); assert(not next(s.activeSmokes)); s:assertClean()
end)
test('PB MP2 keeps early personal abort zero while its surviving pilot completes and recovers',function()
    local s=scenario(); s:occupyWing(); local r=acceptPB(s,3)
    assert(s.messages[#s.messages].text:find('Registered pilots: 2.',1,true))
    s:abortSortie(s.player); complete(s,r); recover(s,s.wingman)
    s:score(0); s:score(150,s.wingman); assert(not s:mission()); s:assertClean()
end)
print(string.format("All %d Strike tests passed (simulated DCS/MOOSE).",count))
