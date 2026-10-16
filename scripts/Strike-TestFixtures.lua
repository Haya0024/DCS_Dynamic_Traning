-- MOOSE static boundary fixture; production mission code is always bundled unchanged.
return function(s, env, options, newUnit)
    s.staticTemplates, s.statics, s.staticSpawns, s.airbases = {}, {}, {}, {}
    local config = dofile("src/config.lua").strike
    for index, site in ipairs(config.sites) do
        local base = { name = site.airbase, side = 1, point = { x = index * 100000, y = 300 } }
        function base:GetCoalition() return self.side end
        function base:GetVec2() return self.point end
        function base:GetName() return self.name end
        s.airbases[site.airbase] = base
        for k, kind in ipairs(config.targets) do for i, suffix in ipairs(kind.suffixes) do
            local name = "TPL_STRIKE_" .. site.id .. "_" .. suffix .. "-1"
            local data = { name = name, type = kind.type, x = base.point.x + k * 100,
                y = base.point.y + i * 10, heading = 0.8, unitId = 5000 + index * 100 + k * 10 + i }
            s.staticTemplates[name] = { name = name:sub(1, -3), units = { data }, dead = false }
        end end
    end
    if options.strikeTemplates then s.staticTemplates = options.strikeTemplates end
    if options.strikeAirbases then s.airbases = options.strikeAirbases end
    function s:static(data, generated)
        local u = newUnit(data.name, data.unitId, nil, nil, 1, data.type)
        u.position = { x = data.x, y = 0, z = data.y }; u.heading = data.heading
        function u:GetDCSObject() return self.alive and self.raw or nil end
        function u:GetVec2() return { x = self.position.x, y = self.position.z } end
        function u:Destroy(events)
            assert(events == false)
            self.destroyCalls = (self.destroyCalls or 0) + 1
            if self.cleanupFailures and self.cleanupFailures > 0 then
                self.cleanupFailures = self.cleanupFailures - 1; error("static cleanup failure")
            end
            if self.cleanupFalse then return false end
            if self.cleanupNoEffect then return end
            self.alive = false
            return true
        end
        u.raw.destroy = function() u:Destroy(false) end
        self.statics[data.name] = u
        if generated then self.staticSpawns[#self.staticSpawns + 1] = u end
        return u
    end
    for _, group in pairs(s.staticTemplates) do s:static(group.units[1]) end
    if options.strikeOriginalCleanupFailures then
        s.statics['TPL_STRIKE_SITE01_TANK_01-1'].cleanupFailures = options.strikeOriginalCleanupFailures
    end
    env.STATIC = { FindByName = function(_, name) return s.statics[name] end }
    env.StaticObject = { getByName = function(name)
        local object = s.statics[name]
        return object and object.alive and object.raw or nil
    end }
    env.AIRBASE = { FindByName = function(_, name) return s.airbases[name] end }
    env._DATABASE = { GetStaticGroupTemplate = function(_, name)
        local group = s.staticTemplates[name]
        return group, group and (group.coalition or 1), nil, 0
    end }
    env.SPAWNSTATIC = { NewFromStatic = function(_, name)
        local data = assert(s.staticTemplates[name]).units[1]
        local copied = {}; for k,v in pairs(data) do copied[k]=v end
        local spawn = { TemplateStaticUnit = copied }
        function spawn:Spawn(heading, alias)
            assert(heading == nil and self.TemplateStaticUnit.unitId == nil)
            s.staticAttempts = (s.staticAttempts or 0) + 1
            if s.failStaticAt == s.staticAttempts then return nil end
            local source = self.TemplateStaticUnit
            local object = s:static({ name = alias, unitId = 10000 + s.staticAttempts,
                x = source.x, y = source.y, heading = source.heading, type = source.type }, true)
            if s.throwStaticAt == s.staticAttempts then error("error after native static creation") end
            return object
        end
        return spawn
    end }
end
