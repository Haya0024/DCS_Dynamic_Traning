-- Boundary simulation shared by geometry and scoring tests. The generated
-- bundle contains exactly the code embedded into the mission by Sync-Mission.
local function scenario(options)
    options = options or {}
    local s = { time = 0, timers = {}, messages = {}, spawns = {}, randomValues = {},
        errors = {}, logs = {}, units = {}, groups = {}, commands = {}, connections = {}, handlers = {},
        eventSubscribers = {}, randomCalls = {} }
    local function newUnit(name, id, pilot, group, side, kind)
        local u = { alive = true, airborne = false, id = id, slotID = id, name = pilot,
            unitName = name, position = { x = 100, y = 200, z = 300 }, heading = 0,
            velocity = { x = 0, y = 0, z = 0 }, group = group, side = side or 2,
            kind = kind or "FA-18C_hornet", life = side == 1 and s.enemyInitialLife or 100, radarEmitting = true }
        function u:newDCSObject()
            local capturedID = self.id
            local raw = {}
            function raw:getID() return capturedID end
            function raw:getName() return name end
            function raw:isExist() return u.alive and u.raw == self end
            u.raw = raw
        end
        u:newDCSObject()
        function u:IsAlive() return self.alive end
        function u:InAir() return self.airborne end
        function u:GetID() return self.id end
        function u:GetPlayerName() return self.name end
        function u:GetVec3() return self.position end
        function u:GetHeading() return self.heading end
        function u:GetGroup() return self.group end
        function u:GetName() return self.unitName end
        function u:GetDCSObject() return self.raw end
        function u:GetCoalition() return self.side end
        function u:IsGround() return self.ground ~= false and (self.kind == "Kub 1S91 str"
            or self.kind == "Kub 2P25 ln" or self.kind == "Osa 9A33 ln") end
        function u:GetTypeName() return self.side == 1 and s.enemyTypeOverride or self.kind end
        function u:GetLife()
            self.lifeCalls = (self.lifeCalls or 0) + 1
            if self.lifeError then error("simulated life API failure") end
            return self.life
        end
        function u:GetRadar()
            self.radarCalls = (self.radarCalls or 0) + 1
            if self.radarError then error("simulated radar API failure") end
            return self.radarEmitting, self.radarTarget
        end
        function u:GetTemplate() return { unitId = self.slotID } end
        function u:GetNumber() return self.number or 1 end
        function u:GetVelocityVec3() return self.velocity end
        s.units[name] = u
        return u
    end
    function s:addPilot(name, ucid, id)
        id = id or 10
        local g = { name = "Group" .. id, id = id + 1000, units = {} }
        function g:GetName() return self.name end
        function g:GetID() return self.id end
        function g:GetUnits() return self.units end
        local p = newUnit("Player" .. id, id, name, g)
        local wing = newUnit("Wing" .. id, id + 100, nil, g)
        g.units = { p, wing }
        p.number, wing.number = 1, 2
        s.groups[g.name] = g
        s.connections[id] = { id = id, name = name, ucid = ucid, side = 2, slot = tostring(id) }
        s.players[#s.players + 1] = p.raw
        return p, wing
    end
    s.players = {}
    s.player, s.wingman = s:addPilot("Pilot", options.unscored and "" or "ucid-a", 10)

    function s:occupyWing(name, ucid, unit)
        local p = unit or self.wingman
        p.name = name or "WingPilot"
        self.connections[p.slotID] = { id = p.slotID, name = p.name,
            ucid = ucid or "ucid-wing", side = 2, slot = tostring(p.slotID) }
        self.players[#self.players + 1] = p.raw
        return p
    end
    function s:addCAPZones()
        self.zones = self.zones or {}
        for index, name in ipairs({ "CAP_ZONE_CENTRAL_COAST", "CAP_ZONE_GOLAN", "CAP_ZONE_NORTH_COAST", "CAP_ZONE_HOMS_WEST" }) do
            local zone = { center = { x = 100100, y = index * 10000 + 300 }, radius = 18288 }
            function zone:GetVec2() return self.center end
            function zone:GetRadius() return self.radius end
            function zone:IsVec3InZone(point)
                if self.failObservation then error("zone observation failed") end
                return point and (point.x - self.center.x)^2 + (point.z - self.center.y)^2 <= self.radius^2 or false
            end
            self.zones[name] = zone
        end
    end

    local coordinate = { WaypointAltType = { BARO = "BARO" } }
    coordinate.__index = coordinate
    function coordinate:NewFromVec3(v) return setmetatable({ x = v.x, y = v.y, z = v.z }, coordinate) end
    function coordinate:Translate(distance, heading, keepAltitude)
        assert(keepAltitude == true)
        local radians = math.rad(heading)
        return self:NewFromVec3({ x = self.x + distance * math.cos(radians),
            y = self.y, z = self.z + distance * math.sin(radians) })
    end
    function coordinate:SetAltitude(altitude, asl) assert(asl == true); self.y = altitude; return self end
    function coordinate:GetVec3() return { x = self.x, y = self.y, z = self.z } end
    function coordinate:GetVec2() return { x = self.x, y = self.z } end
    function coordinate:NewFromVec2(v)
        return self:NewFromVec3({ x = v.x, y = s.terrainHeight and s.terrainHeight(v) or 0, z = v.y })
    end
    function coordinate:GetLandHeight()
        return s.terrainHeight and s.terrainHeight({ x = self.x, y = self.z }) or 0
    end
    function coordinate:IsSurfaceTypeLand()
        return not s.surfaceLand or s.surfaceLand({ x = self.x, y = self.z })
    end
    function coordinate:ToStringLLDMS() return string.format("LL %d %d", self.x, self.z) end
    function coordinate:ToStringLLDDM(settings)
        assert(settings and settings.LL_Accuracy == 3, "Expected three decimal places in DDM minutes")
        return string.format("LL DDM %.3f %.3f", self.x, self.z)
    end
    function coordinate:ScanObjectsSquare(side, units, statics, scenery)
        assert(units and statics and scenery)
        s.scans = (s.scans or 0) + 1
        local lists = s.scanObjects and s.scanObjects(self, side) or { {}, {}, {} }
        return #lists[1] > 0, #lists[2] > 0, #lists[3] > 0, lists[1], lists[2], lists[3]
    end
    function coordinate:HeadingTo(other) return math.deg(math.atan2(other.z - self.z, other.x - self.x)) % 360 end
    function coordinate:WaypointAirTurningPoint(altitudeType, speed, tasks)
        return { position = self:GetVec3(), altitudeType = altitudeType, speed = speed, tasks = tasks }
    end
    coordinate.WaypointAirFlyOverPoint = coordinate.WaypointAirTurningPoint

    local templates = {
        TPL_INT_MIG29A_2 = { "MiG-29A", "MiG-29A" },
        TPL_INT_SU27_1 = { "Su-27" },
        TPL_INT_MIG29A_1 = { "MiG-29A" },
        TPL_SEAD_SA6 = { "Kub 1S91 str", "Kub 2P25 ln", "Kub 2P25 ln", "Kub 2P25 ln" },
        TPL_SEAD_SA8 = { "Osa 9A33 ln" }
    }
    s.groundTemplates = {}
    for _, name in ipairs({ "TPL_SEAD_SA6", "TPL_SEAD_SA8" }) do
        local data = { route = { points = { { x = 1000, y = 2000 } } }, units = {} }
        local offsets = { { 0, 0 }, { 140, 0 }, { 0, -140 }, { 0, 140 } }
        for i, kind in ipairs(templates[name]) do
            data.units[i] = { x = 1000 + offsets[i][1], y = 2000 + offsets[i][2], type = kind }
        end
        s.groundTemplates[name] = data
        s.groups[name] = { GetTemplate = function() return data end }
    end
    local spawn = {}
    function spawn:New(template)
        assert(templates[template] and s.missingTemplate ~= template, "Intercept template not found: " .. template)
        return setmetatable({ template = template }, { __index = spawn })
    end
    function spawn:NewWithAlias(template, alias)
        assert(string.match(alias, "^DT_INTERCEPT_%d+$") or string.match(alias, "^DT_SEAD_%d+$") or string.match(alias, "^DT_CAP_%d+$"),
            "unique assignment alias required")
        local instance = self:New(template)
        instance.alias = alias
        return instance
    end
    function spawn:InitHeading(heading) self.heading = heading; return self end
    function spawn:SpawnFromVec3(position)
        if s.failSpawn then return nil end
        local g = { position = position, heading = self.heading, units = {}, name = self.alias .. "#001",
            template = self.template, cleanupFailures = s.spawnCleanupFailures }
        g.raw = { isExist = function() return not g.destroyed end }
        local n = #s.spawns + 1
        for i, kind in ipairs(templates[self.template]) do
            local name = g.name .. "-" .. i
            assert(not s.units[name], "SPAWN reused a group/unit name")
            g.units[i] = newUnit(name, 2000 + n * 10 + i, nil, g, 1, kind)
            local ground = s.groundTemplates[self.template]
            if ground then
                local origin, data = ground.route.points[1], ground.units[i]
                g.units[i].kind = data.type
                local point = { x = position.x + data.x - origin.x, y = position.z + data.y - origin.y }
                g.units[i].position = { x = point.x, y = s.terrainHeight and s.terrainHeight(point) or 0, z = point.y }
            end
        end
        function g:EnRouteTaskEngageTargets(distance, types, priority)
            assert(distance == nil and priority == 0)
            assert(#types == 2 and types[1] == "Fighters" and types[2] == "Multirole fighters")
            return { id = "EngageTargets", types = types }
        end
        function g:TaskOrbit(center, altitude, speed)
            assert(center and altitude > 0 and speed > 0)
            return { id = "Orbit", params = { point = center:GetVec2(), altitude = altitude, speed = speed } }
        end
        function g:OptionROEOpenFire() self.openFire = true end
        function g:OptionAlarmStateRed()
            if s.failAlarm then error("simulated alarm failure") end
            self.alarmRed = true
        end
        function g:RouteStop()
            if s.failRouteStop then error("simulated route stop failure") end
            self.stopped = true
        end
        function g:SetFormation(formation)
            if s.failFormation then error("simulated formation failure") end
            self.formation = formation
            return self
        end
        function g:TaskWrappedAction(action, index)
            return { id = "WrappedAction", enabled = true, auto = false,
                number = index or 1, params = { action = action } }
        end
        function g:Route(route)
            if s.failRoute then error("simulated route failure") end
            self.route = route
        end
        function g:GetUnits() return self.units end
        function g:GetName() return self.name end
        function g:GetDCSObject() return not self.destroyed and self.raw or nil end
        function g:Destroy()
            self.destroyCalls = (self.destroyCalls or 0) + 1
            if self.cleanupFailures and self.cleanupFailures > 0 then
                self.cleanupFailures = self.cleanupFailures - 1
                error("simulated cleanup failure")
            end
            if self.cleanupFalse and self.cleanupFalse > 0 then
                self.cleanupFalse = self.cleanupFalse - 1
                return false
            end
            if self.cleanupNoEffect and self.cleanupNoEffect > 0 then
                self.cleanupNoEffect = self.cleanupNoEffect - 1
                return nil
            end
            self.destroyed = true
            for _, u in ipairs(self.units) do
                u.alive = false
                if s.cleanupEvents then s:event("Dead", u) end
            end
        end
        table.insert(s.spawns, g)
        return g
    end
    function spawn:SpawnFromVec2(point, minimum, maximum)
        assert(minimum == nil and maximum == nil, "ground spawn must omit airborne heights")
        local g = self:SpawnFromVec3({ x = point.x, y = s.terrainHeight and s.terrainHeight(point) or 0, z = point.y })
        if g then g.fromVec2 = true end
        return g
    end

    local env = setmetatable({ COORDINATE = coordinate, SPAWN = spawn }, { __index = _G })
    env.ENUMS = { Formation = { FixedWing = {
        LineAbreast = { Close = 65537, Open = 65538, Group = 65539 },
        Trail = { Close = 131073, Open = 131074, Group = 131075 },
        Wedge = { Close = 196609, Open = 196610, Group = 196611 },
        EchelonRight = { Close = 262145, Open = 262146, Group = 262147 },
        EchelonLeft = { Close = 327681, Open = 327682, Group = 327683 }
    } } }
    env.AI = { Option = { Air = { id = { FORMATION = 5 } } } }
    s.env = env
    env.ZONE = { FindByName = function(_, name) return s.zones and s.zones[name] end }
    s.runtimeZones = {}
    env.ZONE_RADIUS = { New = function(_, name, center, radius, doNotRegister)
        assert(doNotRegister == true)
        local zone = { name = name, center = center, radius = radius }
        function zone:GetVec2() return self.center end
        function zone:GetRadius() return self.radius end
        function zone:GetRandomVec2() return self.center end
        function zone:IsVec2InZone(p)
            return (p.x - self.center.x)^2 + (p.y - self.center.y)^2 <= self.radius^2
        end
        function zone:IsVec3InZone(p) return self:IsVec2InZone({ x = p.x, y = p.z }) end
        assert(not s.runtimeZones[name], "runtime circle constructed twice")
        s.runtimeZones[name] = zone
        return zone
    end }
    env.math = setmetatable({}, { __index = math })
    function env.math.random(minimum, maximum)
        local value = table.remove(s.randomValues, 1) or minimum
        assert(value >= minimum and value <= maximum, "random bounds changed")
        s.randomCalls[#s.randomCalls + 1] = { minimum = minimum, maximum = maximum, value = value }
        return value
    end
    env.env = { info = function(text) table.insert(s.logs, text) end,
        error = function(text) table.insert(s.errors, text) end }
    env.trigger = { action = { outText = function() end } }
    env.coalition = { side = { BLUE = 2, RED = 1 }, getPlayers = function() return s.players end }
    env.net = {
        get_player_list = function()
            if s.netFailure then error("simulated network API failure") end
            local ids = {}; for id in pairs(s.connections) do ids[#ids + 1] = id end; return ids
        end,
        get_player_info = function(id) return s.connections[id] end
    }
    env.UNIT = { FindByName = function(_, name) return s.units[name] end }
    env.GROUP = { FindByName = function(_, name) return s.groups[name] end }
    env.MESSAGE = { New = function(_, text, seconds)
        return { ToGroup = function(_, group)
            s.messages[#s.messages + 1] = { text = text, group = group:GetName(), seconds = seconds }
        end }
    end }
    env.timer = { getTime = function() return s.time end,
        scheduleFunction = function(callback, arg, due)
            table.insert(s.timers, { callback = callback, arg = arg, due = due })
        end }
    env.MENU_GROUP = { New = function(_, group)
        local gname = group:GetName(); s.commands[gname] = {}
        return { Remove = function() s.commands[gname] = nil end }
    end }
    env.MENU_GROUP_COMMAND = { New = function(_, group, title, menu, callback)
        s.commands[group:GetName()][title] = callback
    end }
    env.EVENTS = { Crash = 1, Dead = 2, PilotDead = 3, Ejection = 4, UnitLost = 5,
        RunwayTouch = 6, Land = 7, Takeoff = 8, RunwayTakeoff = 9 }
    env.BASE = { New = function()
        return { HandleEvent = function(subscriber, id, callback)
            s.handlers[id] = callback
            -- Bundled MOOSE EVENT:Init stores subscriber objects as weak keys.
            s.eventSubscribers[id] = s.eventSubscribers[id] or setmetatable({}, { __mode = "k" })
            s.eventSubscribers[id][subscriber] = callback
        end }
    end }
    local function runBundle()
        local chunk = assert(loadfile("build/DynamicTraining.lua")); setfenv(chunk, env)()
    end
    runBundle()
    s.reload = runBundle
    function s:mission(player)
        -- Inspect the real state owned by the bundled timer, without exposing
        -- gameplay modules or changing their production visibility.
        for i = 1, 100 do
            local name, value = debug.getupvalue(self.timers[1].callback, i)
            if not name then break end
            if name == "Missions" then return value.wings[(player or self.player).group:GetName()] end
        end
        error("Mission state upvalue unavailable")
    end
    function s:sites()
        for i = 1, 100 do
            local name, value = debug.getupvalue(self.timers[1].callback, i)
            if not name then break end
            if name == "Missions" then return value.sites end
        end
        error("Mission site state upvalue unavailable")
    end
    function s:command(title, player)
        player = player or self.player
        local commands = assert(self.commands[player.group:GetName()], "no group menu")
        assert(commands[title], "missing command")()
    end
    function s.generate() s:command("Task: Intercept") end
    function s:tick(time)
        self.time = time
        for _, scheduled in ipairs(self.timers) do
            if scheduled.due and scheduled.due <= time then scheduled.due = scheduled.callback(scheduled.arg, time) end
        end
    end
    function s:event(name, unit, place, time, raw)
        local id = assert(env.EVENTS[name])
        local event = { id = id, Time = time or self.time,
            IniDCSUnit = raw or unit.raw, IniUnit = unit, Place = place }
        if options.weakEventHandlers then
            for subscriber, callback in pairs(self.eventSubscribers[id] or {}) do callback(subscriber, event) end
            return
        end
        local callback = assert(self.handlers[id])
        callback(nil, event)
    end
    function s:complete(spawn)
        local g = spawn or self.spawns[#self.spawns]
        for _, u in ipairs(g.units) do u.alive = false; self:event("Dead", u) end
    end
    function s:base(side, category, name)
        local base = { side = side or 2, category = category or 0, name = name or "Home",
            position = { x = 100, y = 0, z = 300 } }
        function base:GetCoalition() return self.side end
        function base:GetAirbaseCategory() return self.category end
        function base:GetName() return self.name end
        function base:GetVec3() return self.position end
        return base
    end
    function s:carrier()
        local c = newUnit("Carrier", 3000, nil, nil, 2, "Stennis")
        c.position = { x = 100, y = 0, z = 300 }
        c.velocity = { x = 12, y = 0, z = 0 }
        return self:base(2, 2, "Carrier"), c
    end
    function s:land(base, time, player)
        player = player or self.player
        player.airborne = false
        player.position = { x = base.position.x, y = base.position.y + 20, z = base.position.z }
        self.time = time or self.time
        self:event("RunwayTouch", player, base)
    end
    function s:lastMessageContains(fragment)
        local message = assert(self.messages[#self.messages], "no message").text
        assert(string.find(message, fragment, 1, true), "expected '" .. fragment .. "' in: " .. message)
    end
    function s:score(expected, player)
        player = player or self.player
        self:command("Player Statistics", player)
        local text = self.messages[#self.messages].text
        assert(self.messages[#self.messages].seconds == 25)
        for _, category in ipairs({ "Intercept", "CAP", "SEAD", "DEAD" }) do
            assert(not string.find(text, category .. " Score:", 1, true), text)
        end
        local first = assert(string.find(text, "PLAYER STATISTICS: " .. player.name .. " [" .. player.unitName .. "]", 1, true))
        local last = string.find(text, "PLAYER STATISTICS:", first + 1, true)
        local section = string.sub(text, first, last and last - 1 or #text)
        assert(string.find(section, "Total Score: " .. expected .. "\n", 1, true), section)
    end
    function s:categoryScores(expected, player)
        player = player or self.player
        -- Inspect the existing persistence closure without exposing gameplay internals.
        for i = 1, 100 do
            local name, value = debug.getupvalue(self.env.DynamicTrainingPersistence.Initialize, i)
            if name == "Scoring" then
                local p = assert(value.Get(self.connections[player.slotID].ucid))
                for field, points in pairs(expected) do assert(p[field] == points, field) end
                return
            end
        end
        error("Missing Scoring module")
    end
    function s:abortSortie(target, actor)
        self:command("Abort Sortie: " .. target.name .. " [" .. target.unitName .. "]", actor)
    end
    function s:assertClean() assert(#self.errors == 0, table.concat(self.errors, "\n")) end
    return s
end
return scenario
