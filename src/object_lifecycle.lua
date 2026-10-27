-- Verified removal shared by groups/statics; site ownership stays with callers.
local ObjectLifecycle = { pending = {} }
function ObjectLifecycle.Remove(object)
    return pcall(function()
        assert(object:Destroy(false) ~= false, "Object deletion refused.")
        -- MOOSE normally returns nil from Destroy. Only a fresh native lookup
        -- and existence observation can confirm removal, not IsAlive().
        local raw = object:GetDCSObject()
        assert(raw == nil or raw:isExist() == false, "Object disappearance unconfirmed.")
    end)
end
function ObjectLifecycle.GroupReference(name)
    local ok, group = pcall(function() return GROUP:FindByName(name) end)
    if ok and group then return group end
    -- Native fallback is limited to our unique spawn alias: MOOSE can fail
    -- after native creation but before registering its group wrapper.
    return {
        GetDCSObject = function() return Group.getByName(name) end,
        Destroy = function() local raw = Group.getByName(name); if raw then raw:destroy() end end
    }
end
function ObjectLifecycle.Cleanup(object, seconds, label)
    if not object then return true end
    local pending = ObjectLifecycle.pending[object]
    if not pending then
        assert(Observations.Finite(seconds) and seconds > 0, "Invalid object cleanup interval.")
        pending = { seconds = seconds, label = label or "spawn rollback" }
        ObjectLifecycle.pending[object] = pending
    end
    if pending.cleaning then return false end
    pending.cleaning = true
    local ok, problem = ObjectLifecycle.Remove(object)
    pending.cleaning = nil
    if ok then ObjectLifecycle.pending[object] = nil
    else
        pending.retryAt = timer.getTime() + pending.seconds
        if not pending.reported then
            pending.reported = true
            env.error("[DynamicTraining] Object cleanup pending (" .. pending.label .. "): " .. tostring(problem))
        end
    end
    return ok
end
function ObjectLifecycle.CreateGroup(alias, create, retrySeconds)
    local ok, group = pcall(create)
    if ok and group then return group end
    ObjectLifecycle.Cleanup(ObjectLifecycle.GroupReference(alias .. "#001"), retrySeconds, alias)
    return nil, ok and "Group spawn returned nil." or tostring(group)
end
function ObjectLifecycle.Sweep(time)
    local objects = {}
    for object, pending in pairs(ObjectLifecycle.pending) do
        if not pending.cleaning and time >= pending.retryAt then objects[#objects + 1] = object end
    end
    for _, object in ipairs(objects) do
        if ObjectLifecycle.pending[object] then ObjectLifecycle.Cleanup(object) end
    end
end
return ObjectLifecycle
