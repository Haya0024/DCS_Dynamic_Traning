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
    s.randomValues = { base or 1, kind or 1 }
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
        assert(name:find("TPL_STRIKE_", 1, true) == 1 and not static.alive and static.destroyCalls == 1); n=n+1
    end
    assert(n == 25 and #s.staticSpawns == 0 and #s.randomCalls == 0); s:assertClean()
end)
test("ground acceptance spawns only the selected facility with one exact coordinate", function()
    local s = scenario(); local r = accept(s, 1, 3)
    assert(r.category == "Strike" and r.state == "ACTIVE" and #s.staticSpawns == 1)
    assert(r.strikePlan.site.id == "SITE01" and r.strikePlan.target.kind.type == "Warehouse")
    assert(#s.randomCalls == 2 and s.randomCalls[1].maximum == 2 and s.randomCalls[2].maximum == 3)
    local text = s.messages[#s.messages].text
    assert(text == "STRIKE MISSION\nTARGET LOCATION: LL DMS 100300.00 310.00, 0 ft MSL\n" ..
        "OBJECTIVE: Destroy the warehouse; then RTB.\nReward per pilot: 150 points.\nRegistered pilots: 1.")
    assert(s.messages[#s.messages].seconds == 60); s:assertClean()
end)
test("either nearest base and all three target classes are selectable", function()
    for base=1,2 do for kind=1,3 do
        local s=scenario(); local r=accept(s,base,kind)
        assert(r.strikePlan.site.id == string.format("SITE%02d",base))
        assert(#s.staticSpawns == (kind==1 and 3 or 1)); s:assertClean()
        local plan = r.strikePlan
        assert(s.messages[#s.messages].text == "STRIKE MISSION\nTARGET LOCATION: " ..
            plan.location .. ", " .. plan.elevation .. " ft MSL\nOBJECTIVE: " ..
            plan.target.kind.objective .. "; then RTB.\nReward per pilot: 150 points.\nRegistered pilots: 1.")
    end end
end)
test("nearest means acceptance location, including airborne players", function()
    local s=scenario(); s.player.airborne=true; s.player.position.x=499900
    local r=accept(s,2,2); assert(r.strikePlan.site.id=="SITE04")
    s.player.position.x=100; s:tick(2)
    assert(r.strikePlan.site.id=="SITE04" and #s.randomCalls==2); s:assertClean()
end)
test("wing leader is the occupied participant with the lowest flight number", function()
    local s=scenario(); s:occupyWing(); s.player.number=2; s.wingman.number=1
    s.wingman.position.x=499900; local r=accept(s)
    assert(r.owner.unit==s.wingman and r.strikePlan.site.id=="SITE05"); s:assertClean()
end)
test("base distance ties are deterministic before the equal random draw", function()
    local s=scenario(); s.player.position.x=150000
    local r=accept(s,1); assert(r.strikePlan.site.id=="SITE01"); s:assertClean()
end)
test("non-RED bases are excluded and a single RED candidate still works", function()
    local s=scenario()
    for name,b in pairs(s.airbases) do if name~="Hama" then b.side=2 end end
    local r=accept(s); assert(r.strikePlan.site.id=="SITE04" and s.randomCalls[1].maximum==1)
    s:assertClean()
end)
test("no RED base rejects without scoring or retaining wing locks", function()
    local s=scenario(); for _,b in pairs(s.airbases) do b.side=2 end
    s:command("Task: Strike"); assert(not s:mission() and #s.staticSpawns==0)
    s:lastMessageContains("No available Strike targets"); s.generate(); assert(s:mission()); s:assertClean()
end)
test("base reservation keeps parallel wings on distinct nearest bases", function()
    local s=scenario(); local a=accept(s)
    local other=s:addPilot("Other","ucid-b",20); s:tick(2)
    local b=accept(s,1,2,other)
    assert(a.strikePlan.site.id=="SITE01" and b.strikePlan.site.id=="SITE02")
    assert(s.randomCalls[3].maximum==1); s:assertClean()
end)
test("both nearest bases busy rejects instead of silently choosing a third", function()
    local s=scenario(); accept(s)
    local other=s:addPilot("Other","ucid-b",20); s:tick(2); accept(s,1,2,other)
    local third=s:addPilot("Third","ucid-c",30); s:tick(4)
    s:command("Task: Strike",third); assert(not s:mission(third) and #s.staticSpawns==4)
    s:lastMessageContains("No available Strike targets"); s:assertClean()
end)
test("existing wing and UCID locks prevent spawning or redrawing", function()
    local s=scenario(); local r=accept(s); local draws=#s.randomCalls
    s:command("Task: Strike"); s.generate()
    assert(s:mission()==r and #s.randomCalls==draws and #s.staticSpawns==3); s:assertClean()
end)
test("fuel briefing uses the three-tank center and terrain elevation", function()
    local s=scenario(); s.terrainHeight=function() return 304.8 end
    local r=accept(s)
    assert(r.strikePlan.point.x==100100 and r.strikePlan.point.y==320)
    s:lastMessageContains("TARGET LOCATION: LL DMS 100100.00 320.00, 1000 ft MSL\n")
    s:assertClean()
    -- Exercise the bundled MOOSE formatter itself, beyond the boundary mock.
    local file=assert(io.open('vendor/MOOSE/Moose.lua','rb'))
    local source=file:read('*a'):gsub('\r\n','\n'); file:close()
    local real=scenario(); real.terrainHeight=function() return 304.8 end
    local scope=setmetatable({UTILS={}, COORDINATE=real.env.COORDINATE,
        _SETTINGS={LL_Accuracy=5}, coord={LOtoLL=function()
            return 33 + 23.4/60, 36 + 30.3/60
        end}}, {__index=_G})
    for _,pattern in ipairs({'function UTILS%.Round.-\nend', 'UTILS%.tostringLL = function.-\nend',
        'function COORDINATE:ToStringLLDMS.-\n  end'}) do
        setfenv(assert(loadstring(assert(source:match(pattern)))),scope)()
    end
    real.env.COORDINATE.ToStringLLDDM=function() error('Strike must use DMS') end
    accept(real)
    local degree=string.char(194,176) -- UTF-8; native PowerShell pipes can replace non-ASCII literals.
    real:lastMessageContains('TARGET LOCATION: LL DMS 033'..degree..'23\'24.00"N 036'..degree..'30\'18.00"E, 1000 ft MSL\n')
    real:command('Abort Mission')
    scope.coord.LOtoLL=function() return 33 + 23/60 + 4.5/3600, 36 + 30/60 + 7.89/3600 end
    accept(real)
    real:lastMessageContains('TARGET LOCATION: LL DMS 033'..degree..'23\'04.50"N 036'..degree..'30\'07.89"E, 1000 ft MSL\n')
    real:assertClean()
end)
test("spawn preserves each ME position heading type and clears original IDs", function()
    local s=scenario(); local r=accept(s)
    for i,o in ipairs(s.staticSpawns) do
        assert(o.position.x==100100 and o.position.z==300+i*10 and o.heading==0.8)
        assert(o.id~=s.staticTemplates["TPL_STRIKE_SITE01_TANK_0"..i.."-1"].units[1].unitId)
        assert(o.unitName=="DT_STRIKE_"..r.assignmentID.."_"..i)
    end
    s:assertClean()
end)
test("fuel requires all three tanks; partial damage and two losses are insufficient", function()
    local s=scenario(); local r=accept(s); local targets=r.strikePlan.targets
    targets[1].unit.life=1; s:tick(1); assert(r.state=="ACTIVE")
    destroy(s,targets[1].unit); destroy(s,targets[2].unit); s:tick(2); assert(r.state=="ACTIVE")
    destroy(s,targets[3].unit); assert(r.state=="RTB_PENDING"); s:assertClean()
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
    assert(not done:find('TARGET LOCATION:',1,true)); s:assertClean()
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
    assert(s:mission()==r and r.state=='ACTIVE' and #s.staticSpawns==3); s:score(0); s:assertClean()
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
test("cleanup failure retains the base reservation until successful retry", function()
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
    assert(not next(module(s,'Missions').strikeBases))
end)
test("no-effect deletion cannot release a base even when Destroy returns nil", function()
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
test("missing templates fail only that base without stopping other mission categories", function()
    local s=scenario({strikeTemplates={}})
    s:command('Task: Strike'); assert(not s:mission())
    s.player.airborne=true; s.generate(); assert(s:mission().category=='Intercept' and #s.errors==5)
end)
test("coordinate formatting failure rolls back before any static spawn", function()
    local s=scenario(); s.env.COORDINATE.ToStringLLDMS=function() error('coordinate unavailable') end
    s:command('Task: Strike'); assert(not s:mission() and #s.staticSpawns==0 and #s.errors==1)
end)

test("a base stays unavailable until every ME original has actually been removed", function()
    local s=scenario({strikeOriginalCleanupFailures=1})
    local original=s.statics['TPL_STRIKE_SITE01_TANK_01-1']; assert(original.alive)
    local r=accept(s); assert(r.strikePlan.site.id=='SITE02')
    s:tick(1); assert(not original.alive)
    s:command('Abort Mission'); assert(accept(s).strikePlan.site.id=='SITE01'); s:assertClean()
end)

print(string.format("All %d Strike tests passed (simulated DCS/MOOSE).",count))
