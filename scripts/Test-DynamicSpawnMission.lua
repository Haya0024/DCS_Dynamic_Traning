-- The runner prepends the saved mission and warehouse literals, without rewriting them.
local groups, templateCount = {}, 0
for _, country in pairs(mission.coalition.blue.country) do
    for _, category in ipairs({'plane','helicopter'}) do
        for _, group in pairs((country[category] or {}).group or {}) do
            groups[group.groupId] = group
            if group.name:match('^BLUE_HORNET_') or group.name:match('^BLUE_APACHE_') then
                assert(group.dynSpawnTemplate == true and type(group.password) == 'string' and #group.password > 0)
                templateCount = templateCount + 1
            end
        end
    end
end
assert(templateCount == 18, 'All former player groups must be template-only')
local locations, links = 0, 0
for _, entry in ipairs({{'airports',6},{'airports',16},{'airports',30},{'airports',44},{'warehouses',12}}) do
    local stock = assert(warehouses[entry[1]][entry[2]])
    assert(stock.coalition:lower() == 'blue' and stock.dynamicSpawn and not stock.allowHotStart)
    assert(not stock.unlimitedAircrafts and stock.unlimitedFuel and stock.unlimitedMunitions)
    local aircraft = 0
    for category, types in pairs(stock.aircrafts) do
        for kind, item in pairs(types) do
            assert(kind == 'FA-18C_hornet' or kind == 'AH-64D_BLK_II')
            assert(item.unlimited and item.initialAmount > 0 and #item.wsType == 4)
            local source = assert(groups[item.linkDynTempl], 'Missing linked ME template')
            assert(source.dynSpawnTemplate and #source.units == 1 and source.units[1].type == kind)
            assert(source.name:match('_SOLO_01$'))
            local start = source.route.points[1]
            assert(entry[1] == 'airports' and start.airdromeId == entry[2] or start.linkUnit == entry[2])
            if kind == 'AH-64D_BLK_II' then assert(entry[1] == 'airports' and category == 'helicopters')
            else assert(category == 'planes') end
            aircraft, links = aircraft + 1, links + 1
        end
    end
    assert(aircraft == (entry[1] == 'airports' and 2 or 1))
    locations = locations + 1
end
assert(locations == 5 and links == 9)
print('PASS: Dynamic Spawn at four BLUE airports and carrier; nine SOLO template links, selected types unlimited, cold start, eighteen hidden originals')
