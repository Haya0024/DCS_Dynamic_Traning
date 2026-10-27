-- Test-StrikeMission.ps1 prepends unchanged tables from the actual .miz.
local scenario = dofile('scripts/Intercept-TestHarness.lua')
local config = dofile('src/config.lua').strike
local templates, units, ids, groups, groupIDs = {}, {}, {}, {}, {}
for side, co in pairs(mission.coalition) do for _, country in pairs(co.country or {}) do
    for _, group in pairs((country.static or {}).group or {}) do
        assert(not group.name:find('^TPL_STRIKE_'), 'Obsolete airport Strike template remains')
        if group.name:find('^TPL_CMD_') or group.name:find('^TPL_CONT_') or group.name:find('^TPL_TRUCK_')
            or group.name:find('^TPL_TANK_') or group.name:find('^TPL_AMMO_') then
            assert(side=='red' and country.name=='Russia' and group.dead==false and #group.units==1)
            assert(not groups[group.name] and not groupIDs[group.groupId])
            groups[group.name]=group; groupIDs[group.groupId]=true
            local u=group.units[1]
            assert(not units[u.name] and not ids[u.unitId]); units[u.name]=true; ids[u.unitId]=true
            templates[u.name]=group
        end
    end
end end
local total=0; for _ in pairs(templates) do total=total+1 end; assert(total==54)
local centers={}
for _,site in ipairs(config.sites) do
    for i,member in ipairs(config.members) do
        local name=member.prefix..'_'..site.id..'_'..member.suffix
        local group=assert(groups[name],name); local u=group.units[1]
        assert(u.type==member.type and (u.name==name or u.name==name..'-1'))
        if i==1 then centers[site.id]={x=u.x,y=u.y} end
    end
end
print('PASS: actual .miz has six complete RED nine-member facilities including six tanks and six ammunition depots')
for _,site in ipairs(config.sites) do for mode=1,2 do for kind=1,3 do
    local s=scenario({strikeTemplates=templates})
    local p=centers[site.id]
    s.player.position={x=p.x,y=300,z=p.y}; s.randomValues={mode,1,kind}
    s:command('Task: Strike'); local r=assert(s:mission())
    assert(r.strikePlan.site.id==site.id and #s.staticSpawns==(mode==1 and 7 or 9))
    assert(r.strikePlan.attackMode==config.modes[mode])
    assert(#r.strikePlan.targets==(mode==2 and 1 or kind==1 and 4 or kind==2 and 1 or 2))
    local text=s.messages[#s.messages].text
    assert(text:find('STRIKE MISSION ('..config.modes[mode]..')',1,true))
    assert(text:find(mode==1 and 'TARGET AREA: LL DDM ' or 'TARGET AREA: LL DMS ',1,true))
    if mode==2 then
        local member=config.members[({1,8,9})[kind]]
        local me=groups[member.prefix..'_'..site.id..'_'..member.suffix].units[1]
        assert(r.strikePlan.point.x==me.x and r.strikePlan.point.y==me.y)
        assert(text:find(string.format('LL DMS %.2f %.2f, 0 ft MSL',me.x,me.y),1,true))
    else assert(not text:find('ft MSL',1,true)) end
    for i,o in ipairs(s.staticSpawns) do
        local member=config.members[i]
        local me=groups[member.prefix..'_'..site.id..'_'..member.suffix].units[1]
        assert(o.position.x==me.x and o.position.z==me.y and o.heading==me.heading and o.kind==me.type)
    end
    -- Scenery losses cannot complete a selected objective. Target losses can.
    for i,o in ipairs(s.staticSpawns) do
        if not r.strikePlan.target.selected[i] then o.alive=false; s:event('Dead',o) end
    end
    assert(r.state=='ACTIVE')
    for i=1,r.strikePlan.requiredCount do
        local t=r.strikePlan.targets[i]; t.unit.alive=false; s:event('Dead',t.unit)
        assert(r.state==(i<r.strikePlan.requiredCount and 'ACTIVE' or 'RTB_PENDING'))
    end
    assert(r.state=='RTB_PENDING')
    s:command('Abort Mission'); for _,o in ipairs(s.staticSpawns) do assert(not o.alive) end
    assert(not s:mission()); s:assertClean()
end end end
print('PASS: all 36 actual Strike choices retain TOO seven-object DDM and PB nine-object precise target DMS, objectives and cleanup')
