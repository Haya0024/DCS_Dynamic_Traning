trigger.action.outText("DynamicTraining.lua loaded", 10)

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------

local NM_TO_M = 1852
local FT_TO_M = 0.3048

local BVR_MIN_DISTANCE_NM = 60
local BVR_MAX_DISTANCE_NM = 80
local BVR_MAX_BEARING_OFFSET_DEG = 60
local BVR_THROUGH_DISTANCE_NM = 20
local BVR_TAKEOFF_DELAY_SECONDS = 20
local BVR_TAKEOFF_CHECK_INTERVAL_SECONDS = 2

local BVR_MIN_ALT_FT = 15000
local BVR_MAX_ALT_FT = 30000

local BVR_ROUTE_SPEED_MPS = 230
local BVR_ENGAGE_TARGET_TYPES = { "Fighters", "Multirole fighters" }

------------------------------------------------------------
-- STATE
------------------------------------------------------------

local bvrPending = false
local bvrPendingPlayer = nil
local bvrSpawnAt = nil
local bvrActive = false
local currentEnemyGroup = nil

local function ClearBVRPending()
    bvrPending = false
    bvrPendingPlayer = nil
    bvrSpawnAt = nil
end

------------------------------------------------------------
-- GET CURRENT BLUE PLAYER
------------------------------------------------------------

local function GetBluePlayer()

    local players = coalition.getPlayers(coalition.side.BLUE)

    if not players or #players == 0 then
        return nil
    end

    local dcsUnit = players[1]

    if not dcsUnit or not dcsUnit:isExist() then
        return nil
    end

    return UNIT:FindByName(dcsUnit:getName())
end

------------------------------------------------------------
-- BVR ROUTE / ENGAGEMENT
------------------------------------------------------------

local function ConfigureBVRRoute(enemyGroup, spawnVec3, destinationVec3)

    -- En-route engagement uses normal AI detection. No route-leg distance
    -- limit is imposed; this argument is not a weapon launch range.
    local engageTask = enemyGroup:EnRouteTaskEngageTargets(
        nil,
        BVR_ENGAGE_TARGET_TYPES,
        0
    )

    -- MOOSE waypoint builders accept km/h, unlike RouteToVec3's m/s.
    local speedKmh = BVR_ROUTE_SPEED_MPS * 3.6
    local altitudeType = COORDINATE.WaypointAltType.BARO
    local route = {
        COORDINATE:NewFromVec3(spawnVec3):WaypointAirTurningPoint(
            altitudeType,
            speedKmh,
            { engageTask }
        ),
        COORDINATE:NewFromVec3(destinationVec3):WaypointAirFlyOverPoint(
            altitudeType,
            speedKmh
        )
    }

    -- Only designated target types may be engaged, so the BLUE AWACS is
    -- excluded. Weapons Free would permit attacks outside this task filter.
    enemyGroup:OptionROEOpenFire()

    -- Submit the movement and engagement task together. RouteToVec3 builds
    -- bare waypoints and would discard the template's CAP engagement task.
    enemyGroup:Route(route)
end

------------------------------------------------------------
-- SPAWN BVR
------------------------------------------------------------

local function SpawnBVR(playerUnit)

    if bvrActive then
        MESSAGE:New(
            "A BVR mission is already active.",
            10
        ):ToBlue()
        return
    end

    if not playerUnit or not playerUnit:IsAlive() then
        MESSAGE:New(
            "Player aircraft not found.",
            10
        ):ToBlue()
        return
    end

    --------------------------------------------------------
    -- Player position / heading
    --------------------------------------------------------

    local playerVec3 = playerUnit:GetVec3()
    local playerHeading = playerUnit:GetHeading()

    --------------------------------------------------------
    -- Random distance
    --------------------------------------------------------

    local distanceNM =
        math.random(
            BVR_MIN_DISTANCE_NM,
            BVR_MAX_DISTANCE_NM
        )

    local distanceM = distanceNM * NM_TO_M

    --------------------------------------------------------
    -- Enemy altitude
    --------------------------------------------------------

    local altitudeFT =
        math.random(
            BVR_MIN_ALT_FT,
            BVR_MAX_ALT_FT
        )

    local altitudeM = altitudeFT * FT_TO_M

    --------------------------------------------------------
    -- Randomize bearing within the forward sector
    --------------------------------------------------------

    local bearingOffset = math.random(
        -BVR_MAX_BEARING_OFFSET_DEG,
        BVR_MAX_BEARING_OFFSET_DEG
    )
    local spawnBearing = (playerHeading + bearingOffset) % 360

    -- MOOSE Translate uses the same x/z heading convention as GetHeading.
    local playerCoordinate = COORDINATE:NewFromVec3(playerVec3)
    local spawnCoordinate = playerCoordinate:Translate(
        distanceM,
        spawnBearing,
        true
    )
    -- SetAltitude's second argument selects ASL rather than its default AGL.
    spawnCoordinate:SetAltitude(altitudeM, true)
    local spawnVec3 = spawnCoordinate:GetVec3()

    --------------------------------------------------------
    -- Enemy faces player
    --------------------------------------------------------

    -- HOT is relative to the actual spawn-to-player line, not player heading.
    local enemyHeading = spawnCoordinate:HeadingTo(playerCoordinate)

    --------------------------------------------------------
    -- Spawn
    --------------------------------------------------------

    local spawner =
        SPAWN:New("TPL_BVR_MIG29_2")
        :InitHeading(enemyHeading)

    currentEnemyGroup =
        spawner:SpawnFromVec3(spawnVec3)

    if not currentEnemyGroup then
        MESSAGE:New(
            "ERROR: BVR enemy spawn failed.",
            15
        ):ToBlue()

        return
    end

    bvrActive = true

    --------------------------------------------------------
    -- Route THROUGH player's position
    --------------------------------------------------------

    -- Extend the randomized approach line through the player's reference
    -- position. Using playerHeading here would make the route miss the player.
    local destinationCoordinate = playerCoordinate:Translate(
        BVR_THROUGH_DISTANCE_NM * NM_TO_M,
        (spawnBearing + 180) % 360,
        true
    )
    destinationCoordinate:SetAltitude(altitudeM, true)
    local destinationVec3 = destinationCoordinate:GetVec3()

    ConfigureBVRRoute(currentEnemyGroup, spawnVec3, destinationVec3)

    --------------------------------------------------------
    -- Message
    --------------------------------------------------------

    MESSAGE:New(
        string.format(
            "BVR MISSION START\n\n" ..
            "Hostiles: 2 x MiG-29A\n" ..
            "Range: %d NM\n" ..
            "Altitude: %d ft\n" ..
            "Aspect: HOT",
            distanceNM,
            altitudeFT
        ),
        15
    ):ToBlue()
end

------------------------------------------------------------
-- GENERATE BVR COMMAND
------------------------------------------------------------

local function GenerateBVR()

    if bvrActive then
        MESSAGE:New(
            "A BVR mission is already active.",
            10
        ):ToBlue()
        return
    end

    if bvrPending then
        MESSAGE:New(
            "BVR mission is already armed.",
            10
        ):ToBlue()
        return
    end

    local playerUnit = GetBluePlayer()

    local playerName = playerUnit and playerUnit:GetPlayerName()
    if not playerUnit or not playerUnit:IsAlive() or not playerName or playerName == "" then
        MESSAGE:New(
            "Player aircraft not found.",
            10
        ):ToBlue()
        return
    end

    --------------------------------------------------------
    -- Already airborne
    --------------------------------------------------------

    if playerUnit:InAir() then

        SpawnBVR(playerUnit)

    --------------------------------------------------------
    -- Still on ground
    --------------------------------------------------------

    else

        bvrPending = true
        -- Bind the reservation to this human-controlled aircraft. AI wingmen
        -- and other BLUE players must not trigger its takeoff countdown.
        bvrPendingPlayer = {
            unit = playerUnit,
            id = playerUnit:GetID(),
            name = playerName
        }
        bvrSpawnAt = nil

        MESSAGE:New(
            "BVR mission armed.\n" ..
            string.format(
                "Hostiles will spawn %d seconds after takeoff detection.",
                BVR_TAKEOFF_DELAY_SECONDS
            ),
            10
        ):ToBlue()

    end
end

------------------------------------------------------------
-- TAKEOFF MONITOR
------------------------------------------------------------

local function CheckTakeoff(arg, time)

    if bvrPending then

        local playerUnit = bvrPendingPlayer.unit

        if not playerUnit:IsAlive()
            or playerUnit:GetID() ~= bvrPendingPlayer.id
            or playerUnit:GetPlayerName() ~= bvrPendingPlayer.name then

            ClearBVRPending()
            MESSAGE:New(
                "BVR reservation cancelled. Player aircraft changed or unavailable.",
                10
            ):ToBlue()

        elseif not playerUnit:InAir() then

            -- A touchdown before spawning restarts the wait for takeoff.
            if bvrSpawnAt then
                bvrSpawnAt = nil
                MESSAGE:New(
                    "BVR countdown reset. Waiting for takeoff.",
                    10
                ):ToBlue()
            end

        elseif not bvrSpawnAt then

            bvrSpawnAt = time + BVR_TAKEOFF_DELAY_SECONDS
            MESSAGE:New(
                string.format(
                    "Takeoff detected. Hostiles will spawn in %d seconds.",
                    BVR_TAKEOFF_DELAY_SECONDS
                ),
                10
            ):ToBlue()

        elseif time >= bvrSpawnAt then

            ClearBVRPending()
            -- Read position and heading now, after the countdown has elapsed.
            SpawnBVR(playerUnit)
        end
    end

    return time + BVR_TAKEOFF_CHECK_INTERVAL_SECONDS
end

timer.scheduleFunction(
    CheckTakeoff,
    nil,
    timer.getTime() + BVR_TAKEOFF_CHECK_INTERVAL_SECONDS
)

------------------------------------------------------------
-- BVR COMPLETION MONITOR
------------------------------------------------------------

local function CheckBVRMission(arg, time)

    if bvrActive and currentEnemyGroup then

        if not currentEnemyGroup:IsAlive() then

            bvrActive = false
            currentEnemyGroup = nil

            MESSAGE:New(
                "BVR MISSION COMPLETE\nAll hostile aircraft destroyed.",
                15
            ):ToBlue()

        end
    end

    return time + 2
end

timer.scheduleFunction(
    CheckBVRMission,
    nil,
    timer.getTime() + 2
)

------------------------------------------------------------
-- F10 MENU
------------------------------------------------------------

local TrainingMenu =
    MENU_COALITION:New(
        coalition.side.BLUE,
        "Dynamic Training"
    )

MENU_COALITION_COMMAND:New(
    coalition.side.BLUE,
    "Generate BVR",
    TrainingMenu,
    GenerateBVR
)

MESSAGE:New(
    "Dynamic Training ready.",
    10
):ToBlue()
