-- Trial values; all speeds presented to players use knots.
return {
    playerType = "FA-18C_hornet",
    pollSeconds = 1,
    playerScanSeconds = 2,
    takeoffCheckSeconds = 2,
    takeoffDelaySeconds = 20,
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
    intercept = {
        templates = { "TPL_BVR_MIG29A_2", "TPL_BVR_SU27_1", "TPL_BVR_MIG29A_1" },
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
