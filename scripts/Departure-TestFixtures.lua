-- Test-only reference points captured from the last saved SOLO/MP2 parking layout on 2026-11-06.
-- These are regression samples, not runtime spawn positions or airport-center definitions.
-- Actual Dynamic Spawn parking is chosen by DCS and must be checked in game.
local samples = {
    { label = "BLUE_APACHE_AKROTIRI_MP2_01-1", aircraftType = "AH-64D_BLK_II", baseCategory = "airports", baseID = 44, x = -36541.75, y = -267715.15625 },
    { label = "BLUE_APACHE_AKROTIRI_MP2_01-2", aircraftType = "AH-64D_BLK_II", baseCategory = "airports", baseID = 44, x = -36591.25, y = -267694.90625 },
    { label = "BLUE_APACHE_AKROTIRI_SOLO_01-1", aircraftType = "AH-64D_BLK_II", baseCategory = "airports", baseID = 44, x = -36641.578125, y = -267672.15625 },
    { label = "BLUE_APACHE_BEIRUT_MP2_01-1", aircraftType = "AH-64D_BLK_II", baseCategory = "airports", baseID = 6, x = -131729.171875, y = -41638.6796875 },
    { label = "BLUE_APACHE_BEIRUT_MP2_01-2", aircraftType = "AH-64D_BLK_II", baseCategory = "airports", baseID = 6, x = -131769.21875, y = -41665.26953125 },
    { label = "BLUE_APACHE_BEIRUT_SOLO_01-1", aircraftType = "AH-64D_BLK_II", baseCategory = "airports", baseID = 6, x = -131676.96875, y = -41623.4765625 },
    { label = "BLUE_APACHE_INCIRLIK_MP2_01-1", aircraftType = "AH-64D_BLK_II", baseCategory = "airports", baseID = 16, x = 220896.90625, y = -36357.92578125 },
    { label = "BLUE_APACHE_INCIRLIK_MP2_01-2", aircraftType = "AH-64D_BLK_II", baseCategory = "airports", baseID = 16, x = 220917.125, y = -36237.390625 },
    { label = "BLUE_APACHE_INCIRLIK_SOLO_01-1", aircraftType = "AH-64D_BLK_II", baseCategory = "airports", baseID = 16, x = 220784.68139246, y = -36416.479406787 },
    { label = "BLUE_APACHE_RAMAT_MP2_01-1", aircraftType = "AH-64D_BLK_II", baseCategory = "airports", baseID = 30, x = -259803.140625, y = -74181.765625 },
    { label = "BLUE_APACHE_RAMAT_MP2_01-2", aircraftType = "AH-64D_BLK_II", baseCategory = "airports", baseID = 30, x = -259823.4375, y = -74189 },
    { label = "BLUE_APACHE_RAMAT_SOLO_01-1", aircraftType = "AH-64D_BLK_II", baseCategory = "airports", baseID = 30, x = -259782.125, y = -74177.9609375 },
    { label = "BLUE_HORNET_AKROTIRI_MP2_01-1", aircraftType = "FA-18C_hornet", baseCategory = "airports", baseID = 44, x = -36619.0546875, y = -267563.0625 },
    { label = "BLUE_HORNET_AKROTIRI_MP2_01-2", aircraftType = "FA-18C_hornet", baseCategory = "airports", baseID = 44, x = -36652.2578125, y = -267547.3125 },
    { label = "BLUE_HORNET_AKROTIRI_SOLO_01-1", aircraftType = "FA-18C_hornet", baseCategory = "airports", baseID = 44, x = -36585.44140625, y = -267579.1875 },
    { label = "BLUE_HORNET_BEIRUT_MP2_01-1", aircraftType = "FA-18C_hornet", baseCategory = "airports", baseID = 6, x = -131964.4375, y = -41914.17578125 },
    { label = "BLUE_HORNET_BEIRUT_MP2_01-2", aircraftType = "FA-18C_hornet", baseCategory = "airports", baseID = 6, x = -131951.234375, y = -41991.8515625 },
    { label = "BLUE_HORNET_BEIRUT_SOLO_01-1", aircraftType = "FA-18C_hornet", baseCategory = "airports", baseID = 6, x = -131979.609375, y = -41838.609375 },
    { label = "BLUE_HORNET_INCIRLIK_MP2_01-1", aircraftType = "FA-18C_hornet", baseCategory = "airports", baseID = 16, x = 220121.96875, y = -36102.75 },
    { label = "BLUE_HORNET_INCIRLIK_MP2_01-2", aircraftType = "FA-18C_hornet", baseCategory = "airports", baseID = 16, x = 220028.5, y = -36234.44921875 },
    { label = "BLUE_HORNET_INCIRLIK_SOLO_01-1", aircraftType = "FA-18C_hornet", baseCategory = "airports", baseID = 16, x = 220075.265625, y = -36168.0859375 },
    { label = "BLUE_HORNET_RAMAT_MP2_01-1", aircraftType = "FA-18C_hornet", baseCategory = "airports", baseID = 30, x = -259899.4375, y = -74221.8125 },
    { label = "BLUE_HORNET_RAMAT_MP2_01-2", aircraftType = "FA-18C_hornet", baseCategory = "airports", baseID = 30, x = -259878.6875, y = -74210.515625 },
    { label = "BLUE_HORNET_RAMAT_SOLO_01-1", aircraftType = "FA-18C_hornet", baseCategory = "airports", baseID = 30, x = -259919.375, y = -74234.3671875 },
    { label = "BLUE_HORNET_SC_MP2_01-1", aircraftType = "FA-18C_hornet", baseCategory = "warehouses", baseID = 12, x = -175789.9859487, y = -172127.61620219, offsetX = 48.12698500000988, offsetY = 40.03743036999367 },
    { label = "BLUE_HORNET_SC_MP2_01-2", aircraftType = "FA-18C_hornet", baseCategory = "warehouses", baseID = 12, x = -175864.621397, y = -172200.82927865, offsetX = -26.50846330000786, offsetY = -33.17564609000692 },
    { label = "BLUE_HORNET_SC_SOLO_01-1", aircraftType = "FA-18C_hornet", baseCategory = "warehouses", baseID = 12, x = -175789.9859487, y = -172127.61620219, offsetX = 48.12698500000988, offsetY = 40.03743036999367 },
}
return function(mission, warehouses)
    local ships, result = {}, {}
    for _, country in pairs(mission.coalition.blue.country) do
        for _, group in pairs((country.ship or {}).group or {}) do
            for _, unit in pairs(group.units) do ships[unit.unitId] = unit end
        end
    end
    for _, reference in ipairs(samples) do
        local stock = assert(warehouses[reference.baseCategory][reference.baseID], "Missing departure warehouse")
        assert(stock.coalition:upper() == "BLUE" and stock.dynamicSpawn, "Reference base is not a BLUE dynamic departure")
        local point = {}; for k,v in pairs(reference) do point[k] = v end
        if reference.baseCategory == "warehouses" then
            local ship = assert(ships[reference.baseID], "Missing current carrier")
            point.x, point.y = ship.x + reference.offsetX, ship.y + reference.offsetY
        end
        result[#result + 1] = point
    end
    return result
end
