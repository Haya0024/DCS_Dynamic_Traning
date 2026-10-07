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

function Notifications.RegisteredAircraft(record)
    local aircraft = {}
    for _, p in ipairs(record.participants) do
        aircraft[#aircraft + 1] = tostring(p.owner.unitName) .. " (objectID=" .. tostring(p.owner.objectID) .. ")"
    end
    Notifications.Debug(record, "Registered aircraft: " .. table.concat(aircraft, ", ") ..
        "\nWing: " .. record.groupName)
end

function Notifications.FailureEvent(event, reason)
    local object = event.IniDCSUnit or event.initiator
    local function observe(method)
        local ok, value = pcall(function() return object[method](object) end)
        return ok and value ~= nil and tostring(value) or "UNAVAILABLE"
    end
    -- Destruction can make raw methods unavailable. These probes are diagnostic
    -- only; scoring still uses the original object reference and captured ID.
    local name = event.IniUnitName or event.IniDCSUnitName or observe("getName")
    Notifications.Log("[DEBUG] Failure event received: event=" .. reason ..
        "; eventID=" .. tostring(event.id) .. "; time=" .. tostring(event.Time or event.time) ..
        "; unit=" .. tostring(name) .. "; objectID=" .. observe("getID") ..
        "; subscriberRetained=" .. tostring(DynamicTrainingRuntime and DynamicTrainingRuntime.eventHandler ~= nil))
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
