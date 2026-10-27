local Recovery = {}
-- The supplied record is one pilot's sortie; a wing has independent holds.

local function distance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.z - b.z)^2)
end

function Recovery.Start(mission, event, resumeState)
    if not mission.primaryCompletedAt or not Player.EventMatches(mission.owner, event)
        or not Player.IsControlling(mission.owner) then return false end
    local base = event.Place
    if not base or base:GetCoalition() ~= coalition.side.BLUE then return false end
    local category = base:GetAirbaseCategory()
    local carrier
    if category == 2 then -- DCS Airbase.Category.SHIP
        carrier = UNIT:FindByName(base:GetName())
        if not carrier or not Config.carrierTypes[carrier:GetTypeName()] then return false end
    elseif category ~= 0 then -- DCS Airbase.Category.AIRDROME (exclude FARPs).
        return false
    end
    local point = mission.owner.unit:GetVec3()
    local basePoint = base:GetVec3()
    if not Observations.Vec3(point) or not Observations.Vec3(basePoint) then return false end
    local carrierID = carrier and carrier:GetID()
    if carrier and not Observations.Finite(carrierID) then return false end
    local radius = carrier and Config.carrierRadiusMeters or Config.airfieldRadiusMeters
    if distance(point, basePoint) > radius then return false end
    -- Duplicate Land/RunwayTouch events must not restart a valid hold timer.
    if mission.landing and mission.landing.base:GetName() == base:GetName() then return true end
    mission.landing = { base = base, carrier = carrier,
        carrierObjectID = carrierID,
        height = point.y - basePoint.y, stableSince = nil,
        resumeState = resumeState or "RTB_PENDING" }
    mission.state = "LANDING_CHECK"
    return true
end

local function Update(mission, time)
    local landing = mission.landing
    if not landing then return nil end
    assert(Observations.Finite(time), "Recovery time unavailable.")
    if not Player.IsControlling(mission.owner) then
        landing.stableSince = nil
        return nil -- Hold until the original pilot returns; no automatic loss.
    end
    local unit = mission.owner.unit
    local point, basePoint = unit:GetVec3(), landing.base:GetVec3()
    local airborne = unit:InAir()
    local side = landing.base:GetCoalition()
    assert(type(airborne) == "boolean" and Observations.Vec3(point) and Observations.Vec3(basePoint),
        "Recovery position/airborne observation unavailable.")
    assert(type(side) == "number" and (side == coalition.side.BLUE or side == coalition.side.RED
        or side == (coalition.side.NEUTRAL or 0)),
        "Recovery airbase ownership unavailable.")
    local radius = landing.carrier and Config.carrierRadiusMeters or Config.airfieldRadiusMeters
    if airborne or side ~= coalition.side.BLUE
        or distance(point, basePoint) > radius
        or (landing.carrier and math.abs(point.y - basePoint.y - landing.height)
            > Config.carrierHeightToleranceMeters) then
        mission.landing = nil
        mission.state = landing.resumeState
        return "RESET"
    end
    local v = unit:GetVelocityVec3()
    local deck = { x = 0, y = 0, z = 0 }
    if landing.carrier then
        assert(landing.carrier:IsAlive() == true and landing.carrier:GetID() == landing.carrierObjectID,
            "Recovery carrier observation unavailable.")
        deck = landing.carrier:GetVelocityVec3()
    end
    assert(Observations.Vec3(v) and Observations.Vec3(deck), "Recovery velocity unavailable.")
    local speed = math.sqrt((v.x - deck.x)^2 + (v.y - deck.y)^2 + (v.z - deck.z)^2)
    if speed > Config.landingSpeedKnots * 1852 / 3600 then
        landing.stableSince = nil
        return nil
    end
    landing.stableSince = Observations.HoldStart(landing.stableSince, landing.lastObservedAt, time)
    landing.lastObservedAt = time
    if time - landing.stableSince >= Config.landingHoldSeconds then return "SUCCESS" end
end

function Recovery.Update(mission, time)
    -- Contain failures per pilot. An unavailable API must break the continuous
    -- hold without preventing healthy wingmates from being evaluated.
    local ok, result = pcall(Update, mission, time)
    local landing = mission.landing
    if not ok then
        if landing then
            landing.stableSince = nil
            if not landing.observationUnavailable then
                env.info("[DynamicTraining] Recovery observation unavailable; hold reset: " .. tostring(result))
            end
            landing.observationUnavailable = true
        end
        return nil
    end
    if landing then landing.observationUnavailable = nil end
    return result
end

return Recovery
