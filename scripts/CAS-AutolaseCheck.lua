-- Diagnostic entry only: no normal runtime, player directory or persistence.
CAS.Initialize()
local codes, index, plan, stage, deadline = {1688,1687,1686}, 1, nil, 'NEW', 0
local log = function(text) env.info('[CASAutolaseCheck] '..text) end
log('BEGIN runtime=training-18.1')
local function fail(problem)
    if plan then CAS.Close(plan) end
    stage='FAILED'; log('FAILED '..tostring(problem))
end
timer.scheduleFunction(function(_,time)
    local ok,problem=pcall(function()
        CAS.Sweep(time)
        if stage=='NEW' then
            local site=assert(CAS.sites[1]); assert(site.valid,'Invalid CAS site')
            plan=assert(CAS.Plan({x=site.point.x-8*1852,y=0,z=site.point.y},90000+index,codes[index]))
            stage,deadline='PREPARING',time+12
            local spawn=CAS.Spawn(plan)
            if spawn then stage,deadline='STANDBY',time+2 end
        elseif stage=='PREPARING' then
            assert(time<=deadline,'Preparation timeout')
            if CAS.Step(plan,time) then stage,deadline='STANDBY',time+2 end
        elseif stage=='STANDBY' then
            CASAutolase.Tick(plan,time)
            assert(not plan.autolase.spot and not plan.autolase.requested,'Acceptance started an unrequested laser')
            if time>=deadline then
                log('STANDBY_OK code='..codes[index])
                CASAutolase.SetRequested(plan,true,time)
                stage,deadline='FIRST_REQUEST',time+3
            end
        elseif stage=='FIRST_REQUEST' then
            CASAutolase.Tick(plan,time)
            if time>=deadline then
                local a=plan.autolase; local old=assert(a.spot,'No laser after request')
                CASAutolase.SetRequested(plan,false,time)
                assert(not a.spot and not old.Lasing and old:OnBeforeLasing()==false,'Laser stop failed')
                stage,deadline='PAUSED',time+2
            end
        elseif stage=='PAUSED' then
            CASAutolase.Tick(plan,time)
            assert(not plan.autolase.spot and not plan.autolase.requested,'Laser restarted without a request')
            if time>=deadline then
                log('PAUSE_OK code='..codes[index])
                CASAutolase.SetRequested(plan,true,time)
                stage,deadline='TRACKING',time+8
            end
        elseif stage=='TRACKING' then
            CASAutolase.Tick(plan,time)
            local a=assert(plan.autolase)
            if time>=deadline then
                assert(a.spot and a.target and a.spot.SpotLaser and a.spot.Lasing,'No actual native laser created: '..tostring(a.status))
                local point=a.spot.SpotLaser:getPoint()
                local target=a.target.unit:GetVec3()
                assert(Observations.Vec3(point),'Native spot point unavailable')
                local errorMeters=math.sqrt((point.x-target.x)^2+(point.y-target.y-1)^2+(point.z-target.z)^2)
                assert(errorMeters<0.1,'Native spot no longer follows its target')
                log(string.format('SPOT_OK code=%d targetID=%s errorMeters=%.3f',codes[index],tostring(a.target.objectID),errorMeters))
                CAS.Close(plan); stage,deadline='CLEANUP',time+15
            end
        elseif stage=='CLEANUP' then
            if not Missions.casSites[plan.site.id] then
                assert(not Missions.jtacSlots[codes[index]],'Code remained reserved')
                assert(not plan.autolase.spot,'Native spot handle still retained')
                log('CLEANUP_OK code='..codes[index])
                index=index+1
                if index>#codes then stage='COMPLETE'; log('COMPLETE standby=3 pause=3 spots=3 cleanup=3')
                else stage='NEW' end
            else assert(time<=deadline,'Cleanup timeout') end
        end
    end)
    if not ok and stage~='FAILED' then fail(problem) end
    -- Keep retrying cleanup after diagnostic failures, never restart the test.
    if stage=='COMPLETE' then return nil end
    return time+1
end,nil,timer.getTime()+2)
