-- Trial values; all speeds presented to players use knots.
return {
    playerType = "FA-18C_hornet",
    pollSeconds = 1,
    playerScanSeconds = 2,
    takeoffCheckSeconds = 2,
    takeoffDelaySeconds = 20,
    coordinateBriefingSeconds = 60, -- Coordinate briefings and status recall (SEAD / DEAD / CAP).
    persistence = { enabled = true }, -- Requires the server-side Saved Games hook.
    mapOverlay = {
        radiusMeters = 2500,
        textOffsetSouthMeters = 1000, -- Below the base label when the F10 map is north-up.
        outlineColor = { 0.2, 0.55, 1, 0.65 },
        fillColor = { 0.2, 0.55, 1, 0.04 },
        textColor = { 0.35, 0.7, 1, 1 },
        textFillColor = { 0, 0, 0, 0 },
        fontSize = 16,
        minimumDrawingID = 1000000 -- Shared MOOSE allocator continues above this floor.
    },
    recoveryFailurePercent = 60,
    landingHoldSeconds = 10,
    landingSpeedKnots = 5,
    airfieldRadiusMeters = 2500,
    carrierRadiusMeters = 350,
    carrierHeightToleranceMeters = 5,
    carrierTypes = {
        Stennis = true, CVN_71 = true, CVN_72 = true, CVN_73 = true,
        CVN_74 = true, CVN_75 = true, Forrestal = true
    },
    sead = {
        fullReward = 150,
        suppressionHoldSeconds = 30,
        modes = { "TOO", "PB" },
        templates = {
            { name = "TPL_SEAD_SA6", type = "SA-6", pbCode = 108, primaryUnitType = "Kub 1S91 str", planningRangeNM = 15 },
            { name = "TPL_SEAD_SA8", type = "SA-8", pbCode = 117, primaryUnitType = "Osa 9A33 ln", planningRangeNM = 8 }
        },
        zones = { "SEAD_ZONE_PALMYRA", "SEAD_ZONE_SALAMIYAH", "SEAD_ZONE_DUMAYR", "SEAD_ZONE_TABQA",
            "SEAD_ZONE_TURKOGLU", "SEAD_ZONE_HASSA", "SEAD_ZONE_KILIS",
            "SEAD_ZONE_MORPHOU_NORTH", "SEAD_ZONE_GECITKALE_EAST", "SEAD_ZONE_AKKAR" },
        zoneLabels = { SEAD_ZONE_PALMYRA = "Palmyra", SEAD_ZONE_SALAMIYAH = "Salamiyah",
            SEAD_ZONE_DUMAYR = "Dumayr", SEAD_ZONE_TABQA = "Tabqa",
            SEAD_ZONE_TURKOGLU = "Turkoglu", SEAD_ZONE_HASSA = "Hassa", SEAD_ZONE_KILIS = "Kilis",
            SEAD_ZONE_MORPHOU_NORTH = "Morphou North", SEAD_ZONE_GECITKALE_EAST = "Gecitkale East", SEAD_ZONE_AKKAR = "Akkar" },
        minDistanceNM = 40,
        maxDistanceNM = 130,
        pbEstimateErrorMinNM = 1,
        pbEstimateErrorMaxNM = 3,
        tooEstimateErrorMinNM = 3,
        tooEstimateErrorMaxNM = 5,
        flatRadiusMeters = 200,
        sampleStepMeters = 50,
        perimeterSamples = 16,
        maxHeightDifferenceMeters = 20,
        buildingClearanceMeters = 200,
        objectSearchPaddingMeters = 300,
        unknownObjectRadiusMeters = 50,
        attemptsPerZone = 50,
        attemptsPerTick = 2
    },
    dead = { fullReward = 150, unreservedSiteCleanupSeconds = 1800 },
    cap = {
        zones = { "CAP_ZONE_CENTRAL_COAST", "CAP_ZONE_GOLAN", "CAP_ZONE_NORTH_COAST", "CAP_ZONE_LATAKIA_SOUTH",
            "CAP_ZONE_CYPRUS_WEST", "CAP_ZONE_CYPRUS_EAST", "CAP_ZONE_LEVANT_SOUTH",
            "CAP_ZONE_HATAY_SOUTH", "CAP_ZONE_MERSIN_SOUTH" },
        zoneLabels = { CAP_ZONE_CENTRAL_COAST = "Central Coast", CAP_ZONE_GOLAN = "Golan",
            CAP_ZONE_NORTH_COAST = "North Coast", CAP_ZONE_LATAKIA_SOUTH = "Latakia South",
            CAP_ZONE_CYPRUS_WEST = "Cyprus West", CAP_ZONE_CYPRUS_EAST = "Cyprus East",
            CAP_ZONE_LEVANT_SOUTH = "Levant South", CAP_ZONE_HATAY_SOUTH = "Hatay South", CAP_ZONE_MERSIN_SOUTH = "Mersin South" },
        minDistanceNM = 40, maxDistanceNM = 100,
        samSafetyBufferNM = 5, -- Static ME coverage validation; not a limit on AI engagement.
        holdSeconds = 120, progressStepPercent = 20,
        enemySpawnMinSeconds = 30, enemySpawnMaxSeconds = 120,
        spawnOutsideMinNM = 15, spawnOutsideMaxNM = 25,
        minAltitudeFt = 15000, maxAltitudeFt = 30000, speedMps = 230,
        maxTickCreditSeconds = 2, cleanupRetrySeconds = 5, fullReward = 150
    },
    intercept = {
        fullReward = 150,
        cleanupRetrySeconds = 5,
        templates = { "TPL_INT_MIG29A_2", "TPL_INT_SU27_1", "TPL_INT_MIG29A_1" },
        minDistanceNM = 90,
        maxDistanceNM = 110,
        maxBearingOffsetDeg = 60,
        throughDistanceNM = 20,
        minAltitudeFt = 15000,
        maxAltitudeFt = 30000,
        speedMps = 230,
        targetTypes = { "Fighters", "Multirole fighters" },
        formations = { "WEDGE", "LINE_ABREAST", "TRAIL", "ECHELON_LEFT", "ECHELON_RIGHT" },
        formationSpacing = "Open" -- MOOSE fixed-wing spacing: Close / Open / Group.
    }
}
