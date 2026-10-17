-- The runner prepends the unmodified saved ME mission table.
local scenario=dofile('scripts/Intercept-TestHarness.lua')
local config=dofile('src/config.lua').airInterdiction
local templates,centers,unitNames,unitIDs,groupNames,groupIDs={},{},{},{},{},{}
local function same(a,b)
    assert(type(a)==type(b))
    if type(a)~='table' then assert(a==b); return end
    for k,v in pairs(a) do same(v,b[k]) end
    for k in pairs(b) do assert(a[k]~=nil) end
end
for side,co in pairs(mission.coalition) do for _,country in pairs(co.country or {}) do
    for _,category in ipairs({'plane','helicopter','vehicle','ship','static'}) do
        for _,g in pairs((country[category] or {}).group or {}) do
            assert(not groupNames[g.name] and not groupIDs[g.groupId], 'Duplicate ME group name/ID')
            groupNames[g.name],groupIDs[g.groupId]=true,true
            for _,u in pairs(g.units or {}) do
                assert(not unitNames[u.name] and not unitIDs[u.unitId], 'Duplicate ME unit name/ID')
                unitNames[u.name],unitIDs[u.unitId]=true,true
            end
            if g.name:find('^TPL_AI_') then
                assert(side=='red' and country.name=='Russia' and category=='vehicle')
                assert(g.lateActivation==true and #g.units==3)
                local types={}; for _,u in ipairs(g.units) do types[u.type]=(types[u.type] or 0)+1 end
                assert(types.Tigr_233036==1 and types['BTR-70']==1 and types['Ural-375']==1)
                g.CoalitionID,g.CategoryID=1,2 -- Metadata added by MOOSE database registration.
                templates[g.name]=g
                local minX,maxX,minY,maxY=math.huge,-math.huge,math.huge,-math.huge
                for _,p in ipairs(g.route.points) do
                    assert(p.action=='On Road' and p.speed>0)
                    minX,maxX=math.min(minX,p.x),math.max(maxX,p.x)
                    minY,maxY=math.min(minY,p.y),math.max(maxY,p.y)
                end
                local points=g.route.points; local loop=false
                for _,task in pairs(points[#points].task.params.tasks) do
                    if task.id=='GoToWaypoint' and task.enabled==true and task.params.fromWaypointIndex==#points
                        and task.params.nWaypointIndx==1 then loop=true end
                end
                assert(loop,'Last WP must loop to ME WP0')
                centers[g.name]={x=(minX+maxX)/2,y=(minY+maxY)/2}
            end
        end
    end
end end
local n=0; for _ in pairs(templates) do n=n+1 end; assert(n==6)
for _,name in ipairs(config.templates) do assert(templates[name],name) end
print('PASS: actual .miz has six RED three-vehicle road loops, late activation and unique names/IDs')
for _,origin in ipairs(config.templates) do
    local center=centers[origin]; local nearest={}
    for name,p in pairs(centers) do nearest[#nearest+1]={name=name,d=(p.x-center.x)^2+(p.y-center.y)^2} end
    table.sort(nearest,function(a,b) return a.d==b.d and a.name<b.name or a.d<b.d end)
    for draw=1,2 do
        local s=scenario({interdictionTemplates=templates})
        s.player.position={x=center.x,y=300,z=center.y}; s.randomValues={draw}
        s:command('Task: Air Interdiction'); local r=assert(s:mission()); local name=nearest[draw].name
        assert(r.category=='Air Interdiction' and r.state=='ACTIVE' and r.interdictionPlan.site.name==name)
        local p=centers[name]; assert(r.interdictionPlan.site.point.x==p.x and r.interdictionPlan.site.point.y==p.y)
        assert(r.interdictionPlan.location==string.format('LL DDM %.3f %.3f',p.x,p.y))
        same(r.spawn.group.route,templates[name].route)
        for i,u in ipairs(r.spawn.group.units) do
            assert(u.position.x==templates[name].units[i].x and u.position.z==templates[name].units[i].y)
            u.alive=false; s:event('Dead',u); assert(r.state==(i<3 and 'ACTIVE' or 'RTB_PENDING'))
        end
        s:command('Abort Mission'); assert(r.spawn.group.destroyed and not s:mission()); s:assertClean()
    end
end
print('PASS: both nearest choices at all six centers retain exact ME routes, spawn three vehicles and complete/clean up')
