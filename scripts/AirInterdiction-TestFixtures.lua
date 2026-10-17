-- MOOSE group boundary only; gameplay modules run from the production bundle.
return function(s, env, options, newUnit)
    local function copy(v)
        if type(v) ~= 'table' then return v end
        local out={}; for k,x in pairs(v) do out[k]=copy(x) end; return out
    end
    s.interdictionTemplates={}
    for i=1,6 do
        local name=string.format('TPL_AI_%02d',i)
        local points={}
        for j,p in ipairs({{0,0},{2000,0},{2000,1000},{0,1000}}) do
            points[j]={x=i*100000+p[1],y=300+p[2],action='On Road',speed=9.25,
                task={id='ComboTask',params={tasks={}}}}
        end
        points[1].task.params.tasks={{id='WrappedAction',params={action={id='Option',params={name=30,value=60.96}}}}}
        points[4].task.params.tasks={{id='GoToWaypoint',enabled=true,params={fromWaypointIndex=4,nWaypointIndx=1}}}
        local data={name=name,CoalitionID=1,CategoryID=2,lateActivation=true,route={points=points},units={}}
        for j,kind in ipairs({'Tigr_233036','BTR-70','Ural-375'}) do
            data.units[j]={name=name..'-'..j,unitId=8000+i*10+j,type=kind,x=points[1].x,y=points[1].y+j*60.96}
        end
        s.interdictionTemplates[name]=data
    end
    if options.interdictionTemplates then s.interdictionTemplates=options.interdictionTemplates end
    for name,data in pairs(s.interdictionTemplates) do
        s.groups[name]={GetTemplate=function() return copy(data) end}
    end
    env.Group={getByName=function(name)
        local g=s.groups[name]; return g and not g.destroyed and g.raw or nil
    end}
    local previous=env.SPAWN.NewWithAlias
    function env.SPAWN:NewWithAlias(template,alias)
        if not alias:find('^DT_INTERDICTION_%d+$') then return previous(self,template,alias) end
        assert(s.interdictionTemplates[template] and template~=s.missingInterdictionTemplate)
        return {Spawn=function()
            if s.failInterdictionSpawnBefore then error('spawn unavailable') end
            local data=copy(s.interdictionTemplates[template])
            local g={name=alias..'#001',template=template,route=data.route,units={}}
            g.raw={isExist=function() return not g.destroyed end,destroy=function() g:Destroy(false) end}
            for j,unit in ipairs(data.units) do
                local u=newUnit(g.name..'-'..j,9000+#s.spawns*10+j,nil,g,1,unit.type)
                u.life=100
                u.position={x=unit.x,y=0,z=unit.y}
                function u:IsGround() return true end
                g.units[j]=u
            end
            function g:GetName() return self.name end
            function g:GetUnits() return self.units end
            function g:GetDCSObject() return not self.destroyed and self.raw or nil end
            function g:Destroy(events)
                assert(events==false)
                self.destroyCalls=(self.destroyCalls or 0)+1
                if self.cleanupFailures and self.cleanupFailures>0 then
                    self.cleanupFailures=self.cleanupFailures-1; error('convoy cleanup unavailable')
                end
                if self.cleanupFalse then return false end
                if self.cleanupNoEffect then return end
                self.destroyed=true
                for _,u in ipairs(self.units) do u.alive=false; if s.cleanupEvents then s:event('Dead',u) end end
            end
            s.spawns[#s.spawns+1]=g; s.groups[g.name]=g
            if s.interdictionInvalidCount then table.remove(g.units) end
            if s.failInterdictionSpawnAfter then error('spawn failed after creation') end
            if s.nilInterdictionSpawnAfter then return nil end
            return g
        end}
    end
end
