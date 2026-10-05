-- Filesystem adapter is injected by the hook, keeping storage fault-testable.
local ScoreStore = {}
function ScoreStore.New(path, fs)
    local store = { path = path, fs = fs }
    local function readValid(name)
        local text, problem = fs.read(name)
        if not text then return nil, problem end
        local ok, data = pcall(ScoreData.Decode, text)
        if ok then return data, nil, text end
        return nil, "corrupt"
    end
    function store.Load()
        local data, problem = readValid(path)
        if data then return data, "primary" end
        local backup, backupProblem = readValid(path .. ".bak")
        if backup then return backup, "backup" end
        if problem == "missing" and backupProblem == "missing" then return ScoreData.Empty(), "new" end
        error("Score storage unreadable; primary/backup preserved")
    end
    local function checkedWrite(name, text)
        assert(fs.write(name, text), "Score write/flush/close failed")
        local observed = assert(fs.read(name), "Score verification read failed")
        assert(observed == text, "Score write verification failed")
        ScoreData.Decode(observed)
    end
    function store.Save(data)
        local text = ScoreData.Encode(data)
        checkedWrite(path .. ".tmp", text)
        local current, readProblem = fs.read(path)
        assert(current or readProblem == "missing", "Cannot inspect existing score file")
        local valid = current and pcall(ScoreData.Decode, current)
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
