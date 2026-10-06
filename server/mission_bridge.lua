-- Private host-side adapter for the fixed mission persistence endpoints.
local MissionBridge = { description = "mission/a_do_script+scalar-sentinel" }
function MissionBridge.New(network)
    local bridge = { description = MissionBridge.description }
    local function execute(code)
        assert(network and type(network.dostring_in) == "function", "DCS persistence bridge API unavailable")
        -- Real SSE is separate from the manager. The trailing scalar preserves
        -- the payload under the reported native return shift/drop regression.
        -- Only strings/numbers cross native boundaries; replies are never run.
        local wrapped = [[local function encode()
local ok, value = pcall(function()
]] .. code .. "\n" .. [[end)
if not ok then return "DTBR1:E" .. tostring(value) end
local kind = type(value)
if kind == "nil" then return "DTBR1:N" end
if kind == "boolean" then return value and "DTBR1:B1" or "DTBR1:B0" end
if kind == "number" then return "DTBR1:D" .. tostring(value) end
if kind == "string" then return "DTBR1:S" .. value end
return "DTBR1:EUnsupported bridge result type: " .. kind
end
return encode(), 0]]
        local invocation = "local first, second = a_do_script(" .. string.format("%q", wrapped) .. ")\n" .. [[
if type(first) == "string" and first:sub(1, 6) == "DTBR1:" then return first end
if type(second) == "string" and second:sub(1, 6) == "DTBR1:" then return second end
return "DTBRIDGE_INVALID:first=" .. type(first) .. ";second=" .. type(second)]]
        local reply, status = network.dostring_in("mission", invocation)
        assert(status ~= false and type(reply) == "string" and reply:sub(1, 6) == "DTBR1:",
            "DCS mission bridge rejected/invalid reply; replyType=" .. type(reply) .. "; replyBytes=" ..
            (type(reply) == "string" and #reply or 0) .. "; status=" .. tostring(status) ..
            (type(reply) == "string" and reply:match("^DTBRIDGE_INVALID:first=%a+;second=%a+$") and "; " .. reply or ""))
        local tag, value = reply:sub(7, 7), reply:sub(8)
        if tag == "N" and value == "" then return nil end
        if tag == "B" and (value == "1" or value == "0") then return value == "1" end
        if tag == "D" then
            local number = tonumber(value)
            assert(number and number == number and number ~= math.huge and number ~= -math.huge,
                "Invalid numeric bridge reply")
            return number
        end
        if tag == "S" then return value end
        if tag == "E" then error("Mission persistence bridge: " .. value) end
        error("Invalid typed mission bridge reply")
    end
    function bridge.GetProtocol()
        return execute("return DynamicTrainingPersistence and DynamicTrainingPersistence.protocol")
    end
    function bridge.GetContext()
        return execute([[return "endpoint=" .. type(DynamicTrainingPersistence) ..
            "; trigger=" .. type(trigger) .. "; timer=" .. type(timer) ..
            "; coalition=" .. type(coalition) .. "; a_do_script=" .. type(a_do_script)]])
    end
    function bridge.Initialize(payload)
        assert(type(payload) == "string", "Invalid bootstrap argument")
        return execute("return DynamicTrainingPersistence.Initialize(" .. string.format("%q", payload) .. ")")
    end
    function bridge.ExportSnapshot() return execute("return DynamicTrainingPersistence.ExportSnapshot()") end
    function bridge.Acknowledge(session, revision)
        return execute(string.format("return DynamicTrainingPersistence.Acknowledge(%.0f, %.0f)", session, revision))
    end
    function bridge.SetError()
        return execute('if DynamicTrainingPersistence then DynamicTrainingPersistence.SetError("Storage unavailable") end')
    end
    return bridge
end
return MissionBridge
