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
    if not point or not basePoint then return false end
    local radius = carrier and Config.carrierRadiusMeters or Config.airfieldRadiusMeters
    if distance(point, basePoint) > radius then return false end
    -- Duplicate Land/RunwayTouch events must not restart a valid hold timer.
    if mission.landing and mission.landing.base:GetName() == base:GetName() then return true end
    mission.landing = { base = base, carrier = carrier,
        carrierObjectID = carrier and carrier:GetID(),
        height = point.y - basePoint.y, stableSince = nil,
        resumeState = resumeState or "RTB_PENDING" }
    mission.state = "LANDING_CHECK"
    return true
end

function Recovery.Update(mission, time)
    local landing = mission.landing
    if not landing then return nil end
    if not Player.IsControlling(mission.owner) then
        landing.stableSince = nil
        return nil -- Hold until the original pilot returns; no automatic loss.
    end
    local unit = mission.owner.unit
    local point, basePoint = unit:GetVec3(), landing.base:GetVec3()
    local radius = landing.carrier and Config.carrierRadiusMeters or Config.airfieldRadiusMeters
    if unit:InAir() or landing.base:GetCoalition() ~= coalition.side.BLUE
        or not point or not basePoint or distance(point, basePoint) > radius
        or (landing.carrier and math.abs(point.y - basePoint.y - landing.height)
            > Config.carrierHeightToleranceMeters) then
        mission.landing = nil
        mission.state = landing.resumeState
        return "RESET"
    end
    local v = unit:GetVelocityVec3()
    local deck = { x = 0, y = 0, z = 0 }
    if landing.carrier then
        if not landing.carrier:IsAlive() or landing.carrier:GetID() ~= landing.carrierObjectID then
            landing.stableSince = nil
            return nil
        end
        deck = landing.carrier:GetVelocityVec3()
    end
    if not v or not deck then landing.stableSince = nil; return nil end
    local speed = math.sqrt((v.x - deck.x)^2 + (v.y - deck.y)^2 + (v.z - deck.z)^2)
    if speed > Config.landingSpeedKnots * 1852 / 3600 then
        landing.stableSince = nil
        return nil
    end
    landing.stableSince = landing.stableSince or time
    if time - landing.stableSince >= Config.landingHoldSeconds then return "SUCCESS" end
end

return Recovery
