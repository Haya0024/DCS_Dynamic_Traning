-- Execute the pinned MOOSE transformation functions. Only native spawning,
-- wrapper registration, logging and event scheduling are boundary doubles.
-- This checks coalition.addGroup inputs, not terrain, detection or laser spots.
return function(templates, config)
    local file=assert(io.open('vendor/MOOSE/Moose.lua','rb'))
    local source=file:read('*a'):gsub('\r\n','\n'); file:close()
    local function copy(value)
        if type(value)~='table' then return value end
        local result={}; for key,child in pairs(value) do result[key]=copy(child) end; return result
    end
    local noop=function() end
    local common={F=noop,T=noop,T2=noop,T3=noop,I=noop,E=noop,SetEventPriority=noop,HandleEvent=noop}
    local environment=setmetatable({SPAWN={},DATABASE={},UTILS={DeepCopy=copy},
        BASE={New=function() return {} end,I=noop},
        Group={Category={AIRPLANE=0,HELICOPTER=1,GROUND=2}},
        SCHEDULER={New=function() return {Schedule=noop} end},
        COORDINATE={New=function(_,x,y,z) return {x=x,y=y,z=z} end},
        EVENTS={Birth=1,Crash=2,UnitLost=3,RemoveUnit=4},
        env={getValueDictByKey=function(name) return name end}
    },{__index=_G})
    function environment.BASE:Inherit(parent,object)
        return setmetatable(object,{__index=function(_,key) return parent[key] or common[key] end})
    end
    local function loadMethod(class,name)
        local start=assert(source:find('\nfunction '..class..':'..name..'%('),'Missing pinned MOOSE method: '..name)
        local finish=assert(source:find('\nfunction [%w_]+:',start+1),'Method end unavailable: '..name)
        local chunk=assert(loadstring(source:sub(start,finish-1),'@pinned-MOOSE/'..class..':'..name))
        setfenv(chunk,environment); chunk()
    end
    for _,name in ipairs({'NewFromTemplate','Spawn','SpawnWithIndex','SpawnGroupName',
        '_GetSpawnIndex','_InitializeSpawnGroups','_Prepare','_RandomizeRoute','_RandomizeTemplate','_RandomizeZones'}) do
        loadMethod('SPAWN',name)
    end
    loadMethod('DATABASE','Spawn'); loadMethod('DATABASE','_RegisterGroupTemplate')
    environment.Observations=dofile('src/observations.lua')
    local jtacChunk=assert(loadfile('src/jtac.lua')); setfenv(jtacChunk,environment)
    local jtac=jtacChunk()
    local scenarios=0
    for _,site in ipairs(config.sites) do for _,radio in ipairs(config.radioSlots) do
        local native,submitted,byID={},{},{}
        local db=setmetatable({Templates={Groups={},Units={}}},{__index=function(_,key)
            return environment.DATABASE[key] or common[key]
        end})
        environment._DATABASE=db
        function db:AddGroup(name) return assert(native[name]) end
        function db:AddUnit(name) assert(type(name)=='string') end
        environment.coalition={addGroup=function(country,category,data)
            assert(category==2 and (country==0 or country==2))
            assert(data.groupId==nil and data.lateActivation==false)
            local id=800000+#submitted+1
            local group={GetID=function() return id end,GetName=function() return data.name end,SetAIOnOff=noop}
            native[data.name],byID[id]=group,group
            submitted[#submitted+1]=copy(data)
            for _,task in ipairs(data.route.points[1].task.params.tasks) do
                if task.id=='FAC_EngageGroup' then assert(byID[task.params.groupId], 'FAC references a non-spawned group') end
            end
            return group
        end}
        local function spawn(data,original,alias)
            return environment.SPAWN:NewFromTemplate(data,original,alias):Spawn()
        end
        local originalEnemy,originalFriendly,originalJTAC=templates[site.enemy],templates[site.friendly],templates[site.jtac]
        local stripped=jtac.Extract(originalJTAC,originalEnemy.groupId)
        local enemy=spawn(originalEnemy,site.enemy,'AUDIT_ENEMY')
        spawn(originalFriendly,site.friendly,'AUDIT_FRIENDLY')
        spawn(stripped,site.jtac,'AUDIT_JTAC')
        for i,original in ipairs({originalEnemy,originalFriendly,stripped}) do
            local sent=submitted[i]
            assert(#sent.units==#original.units)
            for n,unit in ipairs(sent.units) do
                local before=original.units[n]
                for _,field in ipairs({'x','y','heading','type','skill'}) do
                    assert(unit[field]==before[field], 'MOOSE changed '..field..' for '..site.id)
                end
                assert(unit.unitId==nil and unit.name~=before.name)
            end
            local wp,originalWP=sent.route.points[1],original.route.points[1]
            assert(wp.x==originalWP.x and wp.y==originalWP.y and wp.alt==originalWP.alt and wp.speed==0)
        end
        for _,task in ipairs(submitted[3].route.points[1].task.params.tasks) do
            assert(not task.id:find('^FAC'), 'Native FAC survived the spawn transformation')
        end
        assert(originalEnemy.groupId and originalJTAC.groupId and originalEnemy.units[1].unitId)
        scenarios=scenarios+1
    end end
    return scenarios
end
