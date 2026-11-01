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
local n=0; for _ in pairs(templates) do n=n+1 end; assert(n==10)
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
local hornetSlots = 0
for _,country in pairs(mission.coalition.blue.country) do
    for _,g in pairs((country.plane or {}).group or {}) do
        for _,u in ipairs(g.units) do
            if u.type=='FA-18C_hornet' and u.skill=='Client' then
                hornetSlots=hornetSlots+1
                local origin={x=u.x,y=0,z=u.y}; local eligible=candidates(origin,config)
                assert(#eligible>0,u.name..': no Hornet route within 20-100 NM')
                for draw=1,math.min(2,#eligible) do
                    local s=scenario({playerPosition=origin,interdictionTemplates=templates})
                    s.randomValues={draw}; s:command('Task: Air Interdiction'); local r=assert(s:mission())
                    assert(r.interdictionPlan.site.name==eligible[draw].name)
                    same(r.spawn.group.route,templates[eligible[draw].name].route)
                    s:command('Abort Mission'); assert(r.spawn.group.destroyed); s:assertClean()
                end
                local labels={}
                for _,item in ipairs(eligible) do labels[#labels+1]=string.format('%s %.3f NM',item.name,item.d) end
                print('HORNET COVERAGE: '..u.name..': '..table.concat(labels,', '))
            end
        end
    end
end
assert(hornetSlots==15)
print('PASS: all fifteen Hornet parking positions have available 20-100 NM routes and use the nearest eligible choices')

local airports, groups, slots, parking = {}, 0, 0, {}
for _, country in pairs(mission.coalition.blue.country) do
    for _, g in pairs((country.helicopter or {}).group or {}) do
        if g.name:find('^BLUE_APACHE_') then
            assert(country.name == 'USA' and not g.lateActivation and not g.uncontrolled)
            local start = assert(g.route.points[1]); local base = assert(start.airdromeId)
            assert(start.type == 'TakeOffParking' and start.action == 'From Parking Area' and not start.linkUnit)
            local airport = assert(warehouses.airports[base] or warehouses.airports[tostring(base)])
            assert(airport.coalition == 'BLUE', 'Apache start airport is not BLUE')
            local kind = g.name:match('_(SOLO)_01$') or g.name:match('_(MP2)_01$')
            assert(kind and #g.units == (kind == 'SOLO' and 1 or 2))
            airports[base] = airports[base] or {}; assert(not airports[base][kind])
            airports[base][kind] = true; groups = groups + 1
            for _, u in ipairs(g.units) do
                assert(u.type == 'AH-64D_BLK_II' and u.skill == 'Client')
                assert(u.parking and u.parking_id)
                local key = tostring(base) .. ':' .. tostring(u.parking)
                assert(not parking[key], 'Duplicate Apache parking'); parking[key] = true
                slots = slots + 1
                local origin = {x = u.x, y = 0, z = u.y}; local eligible = candidates(origin)
                assert(#eligible > 0, u.name .. ": no Apache route within 3-13 NM")
                for draw = 1, math.max(1, math.min(2, #eligible)) do
                    local s = scenario({aircraftType = u.type, playerPosition = origin, interdictionTemplates = templates})
                    s.randomValues = {draw}; s:command('Task: Air Interdiction'); local r = s:mission()
                    if #eligible == 0 then
                        assert(not r and #s.spawns == 0)
                        s:lastMessageContains('within 3-13 NM')
                    else
                        assert(r and r.interdictionPlan.site.name == eligible[draw].name)
                        assert(r.interdictionPlan.location:match('^MGRS %d%d[A-Z] [A-Z][A-Z] %d%d%d%d %d%d%d%d$'))
                        same(r.spawn.group.route, templates[eligible[draw].name].route)
                        for _, target in ipairs(r.interdictionPlan.targets) do
                            target.unit.alive = false; s:event('Dead', target.unit)
                        end
                        assert(r.state == 'RTB_PENDING'); s:command('Abort Mission')
                        assert(r.spawn.group.destroyed and not s:mission())
                    end
                    s:assertClean()
                end
                local labels = {}
                for _, item in ipairs(eligible) do labels[#labels + 1] = string.format('%s %.3f NM', item.name, item.d) end
                print('COVERAGE: ' .. u.name .. ': ' .. (#labels > 0 and table.concat(labels, ', ') or 'NONE within 3-13 NM'))
            end
        end
    end
end
local bases = 0
for _, modes in pairs(airports) do assert(modes.SOLO and modes.MP2); bases = bases + 1 end
assert(bases == 4 and groups == 8 and slots == 12)
assert(dictionary[mission.sortie] == 'Persistent and Dynamic Training')
print('PASS: actual .miz has four BLUE Apache airports, eight SOLO/MP2 groups, twelve Client aircraft and the requested title')

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
