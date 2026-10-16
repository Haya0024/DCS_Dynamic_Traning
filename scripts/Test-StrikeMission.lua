-- Test-StrikeMission.ps1 prepends unchanged tables from the actual .miz.
local scenario = dofile('scripts/Intercept-TestHarness.lua')
local config = dofile('src/config.lua').strike
local templates, units, ids, groups = {}, {}, {}, {}
for side, co in pairs(mission.coalition) do for _, country in pairs(co.country or {}) do
    for _, group in pairs((country.static or {}).group or {}) do
        if group.name:find('^TPL_STRIKE_') then
            assert(side=='red' and country.name=='Russia' and group.dead==false and #group.units==1)
            assert(not groups[group.name]); groups[group.name]=true
            local u=group.units[1]
            assert(not units[u.name] and not ids[u.unitId]); units[u.name]=true; ids[u.unitId]=true
            templates[u.name]=group
        end
    end
end end
local total=0; for _ in pairs(templates) do total=total+1 end; assert(total==25)
-- Airports paired with the five ME sites. Fixture base points are the ME
-- facility centroid; production obtains runway centers from MOOSE AIRBASE.
local airportIDs={7,39,21,14,50}
local bases={}
for index,site in ipairs(config.sites) do
    assert(warehouses.airports[airportIDs[index]].coalition=='RED')
    local center={x=0,y=0}; local n=0
    for _,kind in ipairs(config.targets) do for _,suffix in ipairs(kind.suffixes) do
        local name='TPL_STRIKE_'..site.id..'_'..suffix..'-1'
        local group=assert(templates[name],name); local u=group.units[1]
        assert(group.name=='TPL_STRIKE_'..site.id..'_'..suffix and u.type==kind.type)
        center.x,center.y,n=center.x+u.x,center.y+u.y,n+1
    end end
    center.x,center.y=center.x/n,center.y/n
    local base={point=center,side=1}
    function base:GetVec2() return self.point end
    function base:GetCoalition() return self.side end
    bases[site.airbase]=base
end
print('PASS: actual .miz has five RED bases and 25 uniquely named Strike templates')
for _,site in ipairs(config.sites) do for kind=1,3 do
    local s=scenario({strikeTemplates=templates,strikeAirbases=bases})
    local p=bases[site.airbase].point
    s.player.position={x=p.x,y=300,z=p.y}; s.randomValues={1,kind}
    s:command('Task: Strike'); local r=assert(s:mission())
    assert(r.strikePlan.site.id==site.id and #s.staticSpawns==(kind==1 and 3 or 1))
    for i,t in ipairs(r.strikePlan.targets) do
        local me=r.strikePlan.target.templates[i]
        assert(t.unit.position.x==me.x and t.unit.position.z==me.y)
    end
    s:command('Abort Mission'); for _,o in ipairs(s.staticSpawns) do assert(not o.alive) end
    assert(not s:mission()); s:assertClean()
end end
print('PASS: all 15 actual Strike facilities spawn at their ME positions and clean up in simulation')
