-- The runner prepends the saved mission and warehouse literals, without rewriting them.
local playerGroups = 0
for _, country in pairs(mission.coalition.blue.country) do
    for _, category in ipairs({'plane','helicopter'}) do
        for _, group in pairs((country[category] or {}).group or {}) do
            for _, unit in pairs(group.units) do
                if unit.skill == 'Client' or unit.skill == 'Player' then playerGroups = playerGroups + 1 end
            end
            assert(not group.name:match('^BLUE_HORNET_') and not group.name:match('^BLUE_APACHE_'), 'Legacy player original remains')
        end
    end
end
assert(playerGroups == 0, 'BLUE fixed player aircraft must be removed')
local locations, entries = 0, 0
for _, entry in ipairs({{'airports',6},{'airports',16},{'airports',30},{'airports',44},{'warehouses',12}}) do
    local stock = assert(warehouses[entry[1]][entry[2]])
    assert(stock.coalition:lower() == 'blue' and stock.dynamicSpawn and not stock.allowHotStart)
    assert(not stock.unlimitedAircrafts and stock.unlimitedFuel and stock.unlimitedMunitions)
    local aircraft = 0
    for category, types in pairs(stock.aircrafts) do
        for kind, item in pairs(types) do
            local supported = kind == 'FA-18C_hornet' or (kind == 'AH-64D_BLK_II' and entry[1] == 'airports')
            if supported then
                assert(item.unlimited and item.initialAmount > 0 and #item.wsType == 4)
                assert(item.linkDynTempl == nil or item.linkDynTempl == 0, 'Dynamic aircraft must use DCS defaults')
                assert(category == (kind == 'AH-64D_BLK_II' and 'helicopters' or 'planes'))
                aircraft, entries = aircraft + 1, entries + 1
            else
                -- ME saves repopulate the standard warehouse catalogue. These
                -- finite stock rows are distinct from our nine unlimited entries.
                assert(not item.unlimited, 'Unexpected unlimited aircraft type: ' .. kind)
            end
        end
    end
    assert(aircraft == (entry[1] == 'airports' and 2 or 1))
    locations = locations + 1
end
assert(locations == 5 and entries == 9)
print('PASS: Dynamic Spawn at four BLUE airports and carrier; nine supported unlimited stock entries with no template links, cold start, no fixed BLUE player originals; ME standard stock rows permitted')
