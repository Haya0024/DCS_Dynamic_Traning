-- Read actual saved ME groups; only the DCS/MOOSE runtime boundary is simulated.
local scenario = dofile('scripts/Intercept-TestHarness.lua')
local config = dofile('src/config.lua').cas
local templates, wanted = {}, {}
for _, site in ipairs(config.sites) do for _, role in ipairs({'enemy','friendly','jtac'}) do wanted[site[role]] = role end end
for side, co in pairs(mission.coalition) do for _, country in pairs(co.country or {}) do
    for _, group in pairs((country.vehicle or {}).group or {}) do
        local role = wanted[group.name]
        if role then
            assert(not templates[group.name] and group.lateActivation == true, 'CAS TPL missing Late Activation or duplicated')
            assert(side == (role == 'enemy' and 'red' or 'blue') and country.name == (role == 'enemy' and 'Russia' or 'USA'))
            group.CoalitionID, group.CategoryID, group.CountryID = role == 'enemy' and 1 or 2, 2, country.id
            templates[group.name] = group
        end
    end
end end
for name in pairs(wanted) do assert(templates[name], 'CAS template absent in actual .miz: ' .. name) end
print('PASS: CASME-1 actual CAS templates, sides and Late Activation are present')

for _, site in ipairs(config.sites) do
    local enemy = templates[site.enemy].units[1]
    for _, slot in ipairs(config.radioSlots) do
        local s = scenario({aircraftType='AH-64D_BLK_II',casTemplates=templates,
            playerPosition={x=enemy.x-8*1852,y=200,z=enemy.y}})
        s:command('Laser '..slot.laserCode); local r = assert(s:mission(), table.concat(s.errors, '\n'))
        assert(r.state == 'ACTIVE' and #r.casPlan.targets == 3 and #s.spawns == 3)
        local jtac = r.casPlan.instances.jtac.group; local fac
        for _, task in ipairs(jtac.data.route.points[1].task.params.tasks) do if task.id=='FAC_EngageGroup' then fac=task.params end end
        assert(not fac, 'Native FAC must be absent from the AUTOLASE clone')
        assert(r.casPlan.autolase.engine:GetLaserCode(r.casPlan.jtac.unit:GetName())==slot.laserCode)
        s:tick(1); assert(not r.casPlan.autolase.spot, 'Acceptance must remain on standby')
        s:command('Request laser')
        assert(r.casPlan.autolase.spot.SpotLaser.code==slot.laserCode)
        for _, role in ipairs({'enemy','friendly','jtac'}) do
            local generated = r.casPlan.instances[role].group.data
            for i, u in ipairs(generated.units) do
                local original = templates[site[role]].units[i]
                assert(u.x==original.x and u.y==original.y and u.heading==original.heading and u.type==original.type)
            end
        end
        for _, target in ipairs(r.casPlan.targets) do target.unit.alive=false; s:event('Dead',target.unit) end
        assert(r.state=='RTB_PENDING'); s:command('Abort Mission')
        for _, group in ipairs(s.spawns) do assert(group.destroyed) end
        s:assertClean()
    end
end
print('PASS: CASME-2 actual templates retain geometry, omit native FAC, lase with each selected code and complete/clean up')

local samples = dofile('scripts/Departure-TestFixtures.lua')(mission, warehouses)
local nearby = 0
for _, sample in ipairs(samples) do
    if sample.aircraftType=='AH-64D_BLK_II' and sample.baseID==30 then
        local found=false
        for _, site in ipairs(config.sites) do
            local p=templates[site.enemy].units[1]; local nm=math.sqrt((p.x-sample.x)^2+(p.y-sample.y)^2)/1852
            if nm>=config.minDistanceNM and nm<=config.maxDistanceNM then found=true; nearby=nearby+1 end
        end
        assert(found, 'No CAS site in range of historical Ramat parking reference')
    end
end
assert(nearby==3)
print('PASS: CASME-3 Ramat historical parking samples have CAS within 3-13 NM; actual Dynamic Spawn and LOS remain DCS checks')

local audited=dofile('scripts/CAS-MOOSE-TestBoundary.lua')(templates,config)
assert(audited==#config.sites*#config.radioSlots)
print('PASS: CASME-4 pinned MOOSE Spawn/Prepare/DATABASE preserve geometry and omit native FAC at the addGroup boundary')
