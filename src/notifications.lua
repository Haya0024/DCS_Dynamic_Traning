-- Screen output and its matching DCS log. Gameplay code owns when to notify.
local Notifications = {}

function Notifications.Global(text, seconds)
    env.info("[DynamicTraining] MESSAGE [ALL]\n" .. text)
    trigger.action.outText(text, seconds)
end

function Notifications.Group(group, text, seconds)
    if group then pcall(function()
        env.info("[DynamicTraining] MESSAGE [" .. group:GetName() .. "]\n" .. text)
        MESSAGE:New(text, seconds or 10):ToGroup(group)
    end) end
end

function Notifications.Log(text)
    env.info("[DynamicTraining] " .. text)
end

function Notifications.Debug(record, text)
    local id = record.id or (record.category .. " assignment " .. record.assignmentID)
    Notifications.Log("[DEBUG] " .. id .. "\n" .. text)
end

function Notifications.Try(label, group, callback)
    local ok, result = pcall(callback)
    if not ok then
        env.error("[DynamicTraining] " .. label .. ": " .. tostring(result))
        Notifications.Group(group, "ERROR: " .. label .. ". See DCS log.", 15)
    end
    return ok, result
end

return Notifications
