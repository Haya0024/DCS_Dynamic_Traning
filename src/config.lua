-- Trial values; all speeds presented to players use knots.
return {
    playerType = "FA-18C_hornet",
    pollSeconds = 1,
    playerScanSeconds = 2,
    takeoffCheckSeconds = 2,
    takeoffDelaySeconds = 20,
    coordinateBriefingSeconds = 60, -- Coordinate briefings and status recall (SEAD / DEAD).
    persistence = { enabled = true }, -- Requires the server-side Saved Games hook.
    fullReward = 150,
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
        suppressionHoldSeconds = 60,
        modes = { "TOO", "PB" },
        templates = {
            { name = "TPL_SEAD_SA6", type = "SA-6", pbCode = 108, primaryUnitType = "Kub 1S91 str" },
            { name = "TPL_SEAD_SA8", type = "SA-8", pbCode = 117, primaryUnitType = "Osa 9A33 ln" }
        },
        zones = { "SEAD_ZONE_PALMYRA", "SEAD_ZONE_SALAMIYAH", "SEAD_ZONE_DUMAYR", "SEAD_ZONE_TABQA" },
        zoneLabels = { SEAD_ZONE_PALMYRA = "Palmyra", SEAD_ZONE_SALAMIYAH = "Salamiyah",
            SEAD_ZONE_DUMAYR = "Dumayr", SEAD_ZONE_TABQA = "Tabqa" },
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
    dead = { fullReward = 150 }, -- Immediate additional reward and Follow-on DEAD reward.
    intercept = {
        templates = { "TPL_INT_MIG29A_2", "TPL_INT_SU27_1", "TPL_INT_MIG29A_1" },
        minDistanceNM = 60,
        maxDistanceNM = 80,
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
