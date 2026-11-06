-- The runner prepends the unmodified saved ME mission table.
local scenario=dofile('scripts/Intercept-TestHarness.lua')
local config=dofile('src/config.lua').airInterdiction
local templates,centers,unitNames,unitIDs,groupNames,groupIDs={},{},{},{},{},{}
local routeNames,convoyNames={},{}
for _,profile in ipairs({config,config.helicopter}) do
    for _,name in ipairs(profile.templates) do routeNames[name]=true end
    for _,name in ipairs(profile.convoyTemplates or config.convoyTemplates or {}) do convoyNames[name]=true end
end
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
            if routeNames[g.name] or convoyNames[g.name] then
                assert(side=='red' and country.name=='Russia' and category=='vehicle')
                assert(g.lateActivation==true and #g.units==3)
                g.CoalitionID,g.CategoryID=1,2 -- Metadata added by MOOSE database registration.
                templates[g.name]=g
            end
            if routeNames[g.name] then
                local types={}; for _,u in ipairs(g.units) do types[u.type]=(types[u.type] or 0)+1 end
                assert(types.Tigr_233036==1 and types['BTR-70']==1 and types['Ural-375']==1)
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
local n=0; for _ in pairs(centers) do n=n+1 end; assert(n==10)
for name in pairs(convoyNames) do assert(templates[name], 'Configured composition missing from ME: '..name) end
for _,name in ipairs(config.templates) do assert(templates[name],name) end
for _,name in ipairs(config.helicopter.templates) do assert(templates[name],name) end
print('PASS: actual .miz has ten RED three-vehicle road loops, late activation and unique names/IDs')
local hornetUsed = {}
for _,origin in ipairs(config.templates) do
    local p=centers[origin]; local center={x=p.x-40*1852,y=p.y}; local nearest={}
    for _,name in ipairs(config.templates) do local p=centers[name]
        local distance=(p.x-center.x)^2+(p.y-center.y)^2
        if distance >= (config.minDistanceNM*1852)^2 and distance <= (config.maxDistanceNM*1852)^2 then
            nearest[#nearest+1]={name=name,d=distance}
        end
    end
    table.sort(nearest,function(a,b) return a.d==b.d and a.name<b.name or a.d<b.d end)
    for draw=1,math.min(2,#nearest) do
        local s=scenario({interdictionTemplates=templates})
        s.player.position={x=center.x,y=300,z=center.y}; s.randomValues={draw}
        s:command('Task: Air Interdiction'); local r=assert(s:mission()); local name=nearest[draw].name; hornetUsed[name]=true
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
for _,name in ipairs(config.templates) do assert(hornetUsed[name], 'Hornet route untested: '..name) end
print('PASS: Hornet 20-100 NM choices cover all six routes and retain ME routes, spawn, completion and cleanup')

local profile = config.helicopter
local function candidates(position, selection)
    selection = selection or profile
    local found = {}
    for _, name in ipairs(selection.templates) do
        local p = centers[name]
        local nm = math.sqrt((p.x - position.x)^2 + (p.y - position.z)^2) / 1852
        if nm >= selection.minDistanceNM and nm <= selection.maxDistanceNM then
            found[#found + 1] = {name = name, d = nm}
        end
    end
    table.sort(found, function(a,b) return a.d == b.d and a.name < b.name or a.d < b.d end)
    return found
end
-- Historical parking samples provide regression coverage after deleting the ME player originals.
-- They do not assert where DCS will choose to spawn a new aircraft.
local departures = dofile('scripts/Departure-TestFixtures.lua')(mission, warehouses)
local hornetSamples, apacheSamples, apacheBases = 0, 0, {}
for _, sample in ipairs(departures) do
    local apache = sample.aircraftType == 'AH-64D_BLK_II'
    local origin = {x = sample.x, y = 0, z = sample.y}
    local selection = apache and profile or config
    local eligible = candidates(origin, selection)
    assert(#eligible > 0, sample.label .. ': no Air Interdiction route from regression reference')
    if apache then apacheSamples = apacheSamples + 1; apacheBases[sample.baseID] = true
    else hornetSamples = hornetSamples + 1 end
    for draw = 1, math.min(2, #eligible) do
        local s = scenario({aircraftType = sample.aircraftType, playerPosition = origin, interdictionTemplates = templates})
        s.randomValues = {draw}; s:command('Task: Air Interdiction'); local r = assert(s:mission())
        local selected = eligible[draw].name
        assert(r.interdictionPlan.site.name == selected)
        same(r.spawn.group.route, templates[selected].route)
        if apache then
            assert(r.interdictionPlan.location:match('^MGRS %d%d[A-Z] [A-Z][A-Z] %d%d%d%d %d%d%d%d$'))
            for _, target in ipairs(r.interdictionPlan.targets) do target.unit.alive = false; s:event('Dead', target.unit) end
            assert(r.state == 'RTB_PENDING')
        end
        s:command('Abort Mission'); assert(r.spawn.group.destroyed and not s:mission()); s:assertClean()
    end
    local labels = {}
    for _, item in ipairs(eligible) do labels[#labels + 1] = string.format('%s %.3f NM', item.name, item.d) end
    print('REFERENCE COVERAGE: ' .. sample.label .. ': ' .. table.concat(labels, ', '))
end
assert(hornetSamples == 15 and apacheSamples == 12)
local bases = 0; for _ in pairs(apacheBases) do bases = bases + 1 end; assert(bases == 4)
assert(dictionary[mission.sortie] == 'Persistent and Dynamic Training')
print('PASS: all fifteen Hornet reference samples have eligible 20-100 NM routes')
print('PASS: all twelve Apache reference samples at four BLUE airports have eligible 3-13 NM routes; mission title retained')

local used = {}
for _, name in ipairs(profile.templates) do
    local p = centers[name]; local origin = {x = p.x - 8 * 1852, y = 0, z = p.y}
    local eligible = candidates(origin)
    for draw = 1, math.min(2, #eligible) do
        local s = scenario({aircraftType = 'AH-64D_BLK_II', playerPosition = origin, interdictionTemplates = templates})
        s.randomValues = {draw}; s:command('Task: Air Interdiction'); local r = assert(s:mission())
        local selected = eligible[draw].name; used[selected] = true
        assert(r.interdictionPlan.location:match('^MGRS %d%d[A-Z] [A-Z][A-Z] %d%d%d%d %d%d%d%d$'))
        same(r.spawn.group.route, templates[selected].route)
        for _, target in ipairs(r.interdictionPlan.targets) do target.unit.alive = false; s:event('Dead', target.unit) end
        assert(r.state == 'RTB_PENDING'); s:command('Abort Mission'); assert(r.spawn.group.destroyed); s:assertClean()
    end
end
for _, name in ipairs(profile.templates) do assert(used[name], 'Apache route untested: ' .. name) end
print('PASS: Apache 3-13 NM selection, exact ME routes, three-target completion and cleanup cover all ten routes')
