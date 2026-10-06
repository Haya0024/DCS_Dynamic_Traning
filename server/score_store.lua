-- Filesystem adapter is injected by the hook, keeping storage fault-testable.
local ScoreStore = {}
function ScoreStore.New(path, fs)
    local store = { path = path, fs = fs }
    local function readValid(name)
        local text, problem, detail = fs.read(name)
        if not text then return nil, problem, detail end
        local ok, data = pcall(ScoreData.Decode, text)
        if ok then return data end
        if type(data) == "string" and data:find("Unsupported score schema", 1, true) then return nil, "unsupported" end
        return nil, "corrupt"
    end
    function store.Load()
        local data, problem, detail = readValid(path)
        if data then return data, "primary" end
        local backup, backupProblem, backupDetail = readValid(path .. ".bak")
        if backup and (problem == "missing" or problem == "corrupt") then return backup, "backup" end
        if problem == "missing" and backupProblem == "missing" then return ScoreData.Empty(), "new" end
        error("Score storage unreadable; primary/backup preserved; primary=" .. tostring(problem) ..
            "; backup=" .. tostring(backupProblem) .. "; primaryDetail=" .. tostring(detail) ..
            "; backupDetail=" .. tostring(backupDetail))
    end
    local function checkedWrite(name, text)
        local written, problem = fs.write(name, text)
        assert(written, "Score write/flush/close failed; " .. tostring(problem))
        local observed = assert(fs.read(name), "Score verification read failed")
        assert(observed == text, "Score write verification failed")
        ScoreData.Decode(observed)
    end
    function store.Save(data)
        local text = ScoreData.Encode(data)
        checkedWrite(path .. ".tmp", text)
        local current, readProblem = fs.read(path)
        assert(current or readProblem == "missing", "Cannot inspect existing score file")
        local valid, decodeProblem
        if current then valid, decodeProblem = pcall(ScoreData.Decode, current) end
        assert(not (type(decodeProblem) == "string" and decodeProblem:find("Unsupported score schema", 1, true)),
            "Unsupported score schema; existing primary preserved")
        if valid then
            checkedWrite(path .. ".bak.tmp", current)
            local oldBackup, problem = fs.read(path .. ".bak")
            assert(oldBackup or problem == "missing", "Cannot inspect score backup")
            if oldBackup then assert(fs.remove(path .. ".bak"), "Cannot replace score backup") end
            assert(fs.rename(path .. ".bak.tmp", path .. ".bak"), "Cannot promote score backup")
        end
        -- Windows rename does not replace an existing destination. The verified
        -- backup remains available across the short primary replacement window.
        local old, oldProblem = fs.read(path .. ".old")
        assert(old or oldProblem == "missing", "Cannot inspect score rollback file")
        if old then assert(fs.remove(path .. ".old"), "Cannot clear score rollback file") end
        if current then assert(fs.rename(path, path .. ".old"), "Cannot stage previous score file") end
        if not fs.rename(path .. ".tmp", path) then
            if current then fs.rename(path .. ".old", path) end
            error("Cannot promote score file; retry required")
        end
        if current then fs.remove(path .. ".old") end
        return true
    end
    return store
end
return ScoreStore
