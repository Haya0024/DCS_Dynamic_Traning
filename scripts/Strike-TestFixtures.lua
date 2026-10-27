-- MOOSE static boundary fixture; production mission code is always bundled unchanged.
return function(s, env, options, newUnit)
    s.smokes, s.activeSmokes, s.smokeStops = {}, {}, {}
    env.SMOKECOLOR = { Green = 0, Red = 1, White = 2, Orange = 3, Blue = 4 }
    function env.COORDINATE:Smoke(color, duration, delay, name, offset, direction, distance)
        assert(duration == nil and delay == nil and offset == false and direction == 0 and distance == 0)
        if s.failSmokeBefore then error('smoke unavailable') end
        local mark = { point = self:GetVec3(), color = color, name = name }
        s.smokes[#s.smokes + 1], s.activeSmokes[name] = mark, mark
        if s.failSmokeAfter then error('post-emission failure') end
        return self
    end
    function env.COORDINATE:StopSmoke(name)
        if s.smokeStopFailures and s.smokeStopFailures > 0 then
            s.smokeStopFailures = s.smokeStopFailures - 1; error('smoke stop unavailable')
        end
        s.smokeStops[#s.smokeStops + 1] = name
        s.activeSmokes[name] = nil
    end
    s.staticTemplates, s.statics, s.staticSpawns = {}, {}, {}
    local config = dofile("src/config.lua").strike
    for index, site in ipairs(config.sites) do
        for i, member in ipairs(config.members) do
            local groupName = member.prefix .. "_" .. site.id .. "_" .. member.suffix
            -- Real ME statics contain both bare unit names and '-1' suffixes.
            local name = groupName .. ((index + i) % 2 == 0 and "-1" or "")
            local data = { name = name, type = member.type, x = index * 100000 + (i - 1) * 10,
                y = 300 + (i - 1) * 10, heading = 0.8, unitId = 5000 + index * 100 + i }
            s.staticTemplates[name] = { name = groupName, units = { data }, dead = false }
        end
    end
    if options.strikeTemplates then s.staticTemplates = options.strikeTemplates end
    function s:static(data, generated)
        local u = newUnit(data.name, data.unitId, nil, nil, 1, data.type)
        u.position = { x = data.x, y = 0, z = data.y }; u.heading = data.heading; u.life = 100
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
        s.statics['TPL_CMD_SITE01_01-1'].cleanupFailures = options.strikeOriginalCleanupFailures
    end
    env.STATIC = { FindByName = function(_, name) return s.statics[name] end }
    env.StaticObject = { getByName = function(name)
        local object = s.statics[name]
        return object and object.alive and object.raw or nil
    end }
    env._DATABASE = { Templates = { Statics = {} }, GetStaticGroupTemplate = function(_, name)
        local group = s.staticTemplates[name]
        return group, group and (group.coalition or 1), nil, 0
    end }
    for name, group in pairs(s.staticTemplates) do
        env._DATABASE.Templates.Statics[name] = { StaticName = group.name }
    end
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
