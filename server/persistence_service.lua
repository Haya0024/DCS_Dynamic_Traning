-- Storage transaction coordinator. No DCS callbacks or native I/O here.
local PersistenceService = {}
function PersistenceService.New(bridge, fs, directory, output)
    local service = { phase = "WAITING_MISSION", attached = false, committed = 0 }
    function service.Reset()
        service.store, service.bootstrap, service.session = nil, nil, nil
        service.attached, service.committed, service.phase = false, 0, "WAITING_MISSION"
        service.waiting, service.reportedConnected = false, false
    end
    function service.Poll()
        service.phase = "PROTOCOL"
        local protocol = bridge.GetProtocol()
        if protocol ~= 1 then
            service.phase = "WAITING_ENDPOINT"
            if not service.waiting then
                local ok, context = pcall(bridge.GetContext)
                output.transition("WAITING_ENDPOINT", "protocol=" .. tostring(protocol) .. "; " ..
                    (ok and tostring(context) or "type probe unavailable"))
                service.waiting = true
            end
            return false
        end
        service.waiting = false
        if not service.store then
            service.phase = "DIRECTORY"
            fs.ensureDirectory(directory)
            service.store = ScoreStore.New(directory .. "/scores.dat", fs)
        end
        if not service.bootstrap then
            service.phase = "LOAD"
            local data, source = service.store.Load()
            assert(data.counter < 9007199254740991, "Score run counter exhausted")
            data.counter = data.counter + 1
            data.session, data.revision = data.counter, 0
            local encoded = ScoreData.Encode(data)
            service.phase = "BOOTSTRAP"
            service.store.Save(data)
            service.bootstrap, service.session, service.committed = encoded, data.session, 0
            output.info("BOOTSTRAP_COMMITTED: run=" .. string.format("%.0f", data.session) .. "; source=" .. source)
            if source == "backup" then output.warning("Recovered score backup") end
        end
        if not service.attached then
            service.phase = "ATTACH"
            assert(bridge.Initialize(service.bootstrap) == true, "Persistence initialization rejected")
            service.attached = true
        end
        service.phase = "SNAPSHOT"
        local payload = bridge.ExportSnapshot()
        assert(type(payload) == "string", "Persistence snapshot unavailable")
        if payload ~= "" then
            service.phase = "VALIDATE"
            local data = ScoreData.Decode(payload)
            assert(data.session == service.session and data.counter == service.session, "Stale score session rejected")
            assert(data.revision >= service.committed, "Regressing score revision rejected")
            if data.revision > service.committed then
                service.phase = "SAVE"
                service.store.Save(data)
                service.committed = data.revision
                output.info("SNAPSHOT_COMMITTED: run=" .. string.format("%.0f", data.session) ..
                    "; revision=" .. string.format("%.0f", data.revision))
            end
        end
        service.phase = "ACK"
        assert(bridge.Acknowledge(service.session, service.committed) == true, "Persistence acknowledgement rejected")
        service.phase = "CONNECTED"
        if not service.reportedConnected then
            output.info("Connected via " .. bridge.description .. "; storage and acknowledgement confirmed.")
            service.reportedConnected = true
        end
        output.transition("CONNECTED", "Mission endpoint attached; storage and acknowledgement confirmed.")
        return true
    end
    return service
end
return PersistenceService
