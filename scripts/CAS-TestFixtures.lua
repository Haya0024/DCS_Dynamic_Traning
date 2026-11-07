-- MOOSE boundary simulation only; the bundled production CAS logic is exercised.
return function(s, env, options, newUnit)
    local copy = env.UTILS.DeepCopy
    dofile('scripts/CAS-Autolase-TestBoundary.lua')(s, env)
    s.casTemplates = {}
    local kinds = { enemy = { 'BMP-2', 'BMP-2', 'Ural-375' }, friendly = { 'M-113', 'M 818', 'M-113' },
        jtac = { 'M1045 HMMWV TOW' } }
    for index, role in ipairs({ 'enemy', 'friendly', 'jtac' }) do
        local name = 'TPL_CAS_' .. role:upper() .. '_01'
        local tasks = {
            { id = 'WrappedAction', enabled = true, params = { action = { id = 'Option', params = { name = 0, value = 4 } } } },
            { id = 'WrappedAction', enabled = true, params = { action = { id = 'Option', params = { name = 8 } } } }
        }
        if role == 'jtac' then
            table.insert(tasks, 1, { id = 'FAC_EngageGroup', enabled = true, params = {
                groupId = 501, designation = 'Laser', visible = true, laserCode = 1688, weaponType = 9663676414,
                priority = 0, callname = 1, number = 1, frequency = 133000000, modulation = 0, datalink = true } })
        end
        local x = role == 'enemy' and 81000 or 80400
        local t = { name = name, groupId = 500 + index, CoalitionID = role == 'enemy' and 1 or 2,
            CategoryID = 2, lateActivation = true, route = { points = { { x = x, y = 800, speed = 0,
                action = 'Off Road', task = { id = 'ComboTask', params = { tasks = tasks } } } } }, units = {} }
        for j, kind in ipairs(kinds[role]) do
            t.units[j] = { name = name .. '-' .. j, unitId = 17000 + index * 10 + j, type = kind,
                x = x + (j - 1) * 30, y = 800 + (j - 1) * 40, heading = 1.2, skill = 'Average' }
        end
        s.casTemplates[name] = t
    end
    if options.casTemplates then s.casTemplates = options.casTemplates end
    for name, data in pairs(s.casTemplates) do s.groups[name] = { GetTemplate = function() return copy(data) end } end
    local previous = env.SPAWN.NewFromTemplate
    function env.SPAWN:NewFromTemplate(data, name, alias)
        if not alias:find('^DT_CAS_') then return previous(self, data, name, alias) end
        local role = assert(alias:match('^DT_CAS_%d+_(%u+)$')):lower()
        assert(data.name == name and s.casTemplates[name])
        if s.casConstructorFailure == role then error('CAS constructor unavailable') end
        return { Spawn = function()
            if s.casBeforeFailure == role then error('CAS spawn before creation') end
            local g = { name = alias .. '#001', id = 30000 + #s.spawns, data = copy(data), units = {}, role = role }
            if s.casStringGroupID then g.id = tostring(g.id) end
            g.raw = { isExist = function() return not g.destroyed end, destroy = function() g:Destroy(false) end }
            for i, u in ipairs(data.units) do
                local id = 40000 + #s.spawns * 10 + i
                if s.casStringUnitIDs then id = tostring(id) end
                local unit = newUnit(g.name .. '-' .. i, id, nil, g, data.CoalitionID, u.type)
                unit.position = { x = u.x, y = 0, z = u.y }; unit.life = 100
                function unit:IsGround() return true end
                function unit:IsAlive()
                    if s.casInactiveUntil and s.time < s.casInactiveUntil then return false end
                    return self.alive
                end
                function unit:IsLOS(target)
                    assert(self.kind == 'M1045 HMMWV TOW' and target.side == 1)
                    if s.casLOSError then error('LOS observation failed') end
                    return s.casLOS ~= false
                end
                function unit:GetCoord()
                    local c=env.COORDINATE:NewFromVec3(self.position); c.unit=self; return c
                end
                unit.GetPointVec3=unit.GetCoord
                function unit:GetHeight() return self.position.y end
                function unit:GetThreatLevel() return self.threat or (self.kind=='BMP-2' and 4 or 1) end
                g.units[i] = unit
            end
            function g:GetID() return self.id end
            function g:GetName() return self.name end
            function g:GetUnits()
                if s.casUnitsUnavailableUntil and s.time < s.casUnitsUnavailableUntil then return {} end
                if s.casReverseUnits then
                    local reversed = {}; for i=#self.units,1,-1 do reversed[#reversed+1]=self.units[i] end
                    return reversed
                end
                return self.units
            end
            function g:GetDCSObject() return not self.destroyed and self.raw or nil end
            function g:Destroy(events)
                assert(events == false); self.destroyCalls = (self.destroyCalls or 0) + 1
                if self.cleanupFailures and self.cleanupFailures > 0 then
                    self.cleanupFailures = self.cleanupFailures - 1; error('CAS cleanup unavailable')
                end
                if self.cleanupFalse then return false end
                if self.cleanupNoEffect then return end
                self.destroyed = true
                for _, u in ipairs(self.units) do u.alive = false; if s.cleanupEvents then s:event('Dead', u) end end
            end
            s.spawns[#s.spawns + 1] = g; s.groups[g.name] = g
            if s.casInvalidCount == role then table.remove(g.units) end
            if s.casInvalidType == role then g.units[1].kind = 'Unexpected' end
            if s.casAfterFailure == role then error('CAS spawn after creation') end
            if s.casNilAfter == role then return nil end
            return g
        end }
    end
    function env.COORDINATE:Get3DDistance(other)
        return math.sqrt((self.x-other.x)^2+(self.y-other.y)^2+(self.z-other.z)^2)
    end
    function env.COORDINATE:IsLOS(other,offset)
        assert(offset==2.5)
        if s.casLOSError then error('LOS observation failed') end
        if s.casLOSNil then return nil end
        return s.casLOS~=false and (not other.unit or other.unit.los~=false)
    end
    function env.COORDINATE:AddY(v) self.y=self.y+v; return self end
    function env.COORDINATE:AddX(v) self.x=self.x+v; return self end
end
