-- Pinned MOOSE policy and SPOT methods execute unchanged. Only FSM dispatch,
-- native spots, world objects, scheduler and event services are test boundaries.
local source = rawget(_G, 'CASPinnedAutolaseSource')
local chunks = rawget(_G, 'CASPinnedAutolaseChunks') or {}
_G.CASPinnedAutolaseChunks = chunks
if not source then
    local file = assert(io.open('vendor/MOOSE/Moose.lua','rb'))
    source = file:read('*a'):gsub('\r\n','\n'); file:close()
    _G.CASPinnedAutolaseSource = source
end
return function(s, env)
    local noop = function() end
    local common = { T=noop,T2=noop,T3=noop,F=noop,I=noop,E=noop,SetEventPriority=noop,
        SetForgetTime=noop,SetAcceptZones=noop,SetRejectZones=noop,SetCorridorZones=noop,
        SetConflictZones=noop,SetClusterAnalysis=noop }
    s.mooseTasks, s.mooseSubscriptions, s.nativeSpots = {}, {}, {}
    function common:HandleEvent() s.mooseSubscriptions[self] = true end
    function common:UnHandleEvent() s.mooseSubscriptions[self] = nil end
    function s:runMoose(time)
        local count = #self.mooseTasks
        for i=1,count do
            local task = self.mooseTasks[i]
            if not task.cancelled and task.due <= time then
                task.cancelled = true; task.fn(task.owner,unpack(task.args))
            end
        end
    end
    env.SCHEDULER = { New=function()
        local scheduler={tasks={}}
        function scheduler:Schedule(owner,fn,args,delay)
            local task={owner=owner,fn=fn,args=args or {},due=s.time+math.abs(delay or 0)}
            self.tasks[#self.tasks+1]=task; s.mooseTasks[#s.mooseTasks+1]=task; return task
        end
        function scheduler:Clear() for _,t in ipairs(self.tasks) do t.cancelled=true end end
        function scheduler:Stop(task) if task then task.cancelled=true end end
        return scheduler
    end }
    local function fire(object,event,...)
        local args={...}
        for _,prefix in ipairs({'onbefore','OnBefore'}) do
            local handler=object[prefix..event]
            if handler and handler(object,'*',event,'*',unpack(args))==false then return false end
        end
        for _,prefix in ipairs({'onafter','OnAfter'}) do
            local handler=object[prefix..event]
            if handler then pcall(handler,object,'*',event,'*',unpack(args)) end
        end
    end
    env.FSM = { New=function()
        local object={CallScheduler=env.SCHEDULER:New()}
        function object:SetStartState() end
        function object:AddTransition(_,event)
            self[event]=function(o,...) return fire(o,event,...) end
            self['__'..event]=function(o,delay,...)
                return o.CallScheduler:Schedule(o,function(v,...) fire(v,event,...) end,{...},delay)
            end
        end
        return setmetatable(object,{__index=common})
    end }
    env.BASE.Inherit=function(_,child,parent)
        local previous=getmetatable(parent) and getmetatable(parent).__index
        return setmetatable(parent,{__index=function(_,key)
            return child[key] or (type(previous)=='table' and previous[key])
                or (type(previous)=='function' and previous(parent,key)) or common[key]
        end})
    end
    env.BASE.T=noop
    env.SET_GROUP={New=function()
        local set={Set={}}
        function set:FilterPrefixes(prefix) self.prefix=prefix; return self end
        function set:FilterCoalitions(side) self.side=side; return self end
        function set:FilterOnce()
            for name,g in pairs(s.groups) do if name:match(assert(self.prefix)) then self.Set[name]=g end end
            return self
        end
        return set
    end}
    env.AUTOLASE,env.INTEL,env.SPOT={},{},{}
    env.SMOKECOLOR={Red=1}
    env.radio={modulation={AM=0,FM=1}}
    env.UTILS.GenerateLaserCodes=function() return {1688} end
    env.UTILS.GetCoalitionName=function(side) return side==2 and 'BLUE' or 'RED' end
    env.Spot={}
    local function native(kind,observer,offset,point,code)
        if s.spotCreateFailure==kind then error('native '..kind..' creation failure') end
        assert(observer and offset.y==2 and point.y==point.y)
        local spot={kind=kind,point=env.UTILS.DeepCopy(point),code=code,updates=0}
        s.nativeSpots[#s.nativeSpots+1]=spot
        function spot:setPoint(p) assert(not self.destroyed); self.point=env.UTILS.DeepCopy(p); self.updates=self.updates+1 end
        function spot:destroy()
            if self.destroyFailures and self.destroyFailures>0 then
                self.destroyFailures=self.destroyFailures-1; error('native destroy failed')
            end
            if self.destroyFalse then return false end
            self.destroyed=true -- DCS destroy is a void-returning operation.
        end
        return spot
    end
    env.Spot.createLaser=function(...) return native('laser',...) end
    env.Spot.createInfraRed=function(...) return native('ir',...) end
    local function loadMethod(class,name)
        local key=class..':'..name
        if not chunks[key] then
            local start,header=source:find('\n[ \t]*function '..class..':'..name..'%(')
            assert(start,'Missing MOOSE method '..name)
            local finish=assert(source:find('\n[ \t]*function [%w_]+[:%.]',header+1),'Missing MOOSE method end '..name)
            chunks[key]=source:sub(start,finish-1)
        end
        local chunk=assert(loadstring(chunks[key],'@pinned-MOOSE/'..key))
        setfenv(chunk,env); chunk()
    end
    loadMethod('INTEL','New')
    for _,name in ipairs({'New','CanLase','GetLosFromUnit','GetLaserCode','SetRecceLaserCode',
        'SetLasingParameters','SetMaxLasingTargets','SetLaserCoolDown','SetLaserCodes','EnableSmokeMenu'}) do
        loadMethod('AUTOLASE',name)
    end
    for _,name in ipairs({'New','onafterLaseOn','onafterLasing'}) do loadMethod('SPOT',name) end
end
