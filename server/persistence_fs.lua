-- Normalize host I/O without assuming DCS io.open returns a numeric errno.
local PersistenceFS = {}
function PersistenceFS.New(files, directories, system, reportCompatibility)
    local fs = {}
    local reportedCompatibility = false
    local function invoke(file, operation, argument)
        local ok, value, problem = pcall(function()
            if argument ~= nil then return file[operation](file, argument) end
            return file[operation](file)
        end)
        -- Some DCS host file methods perform the operation without a return.
        -- Explicit failure/exception still fails. ScoreStore verifies bytes by
        -- reopening before promotion; a nil result is never a storage receipt.
        local accepted = ok and value ~= false and problem == nil
        return accepted, operation .. "Return=" .. (ok and type(value) or "exception") ..
            "; " .. operation .. "Error=" .. type(problem)
    end
    local function absent(path)
        local normalized = path:gsub("\\", "/")
        local parent, filename = normalized:match("^(.*)/([^/]+)$")
        if not parent or type(directories.dir) ~= "function" then return false, "directory listing unavailable" end
        local iterator, directory
        local ok, found = pcall(function()
            iterator, directory = directories.dir(parent)
            assert(type(iterator) == "function", "invalid directory iterator")
            local count, exists = 0, false
            for entry in iterator, directory do
                assert(type(entry) == "string", "invalid directory entry")
                count = count + 1
                assert(count <= 10000, "directory inspection limit exceeded")
                if entry:lower() == filename:lower() then exists = true end
            end
            return exists
        end)
        if not ok and directory then pcall(function() directory:close() end) end
        if not ok then return false, "directory inspection failed: " .. tostring(found) end
        return not found, found and "existing file unreadable" or "confirmed absent"
    end
    function fs.ensureDirectory(path)
        local mode = directories.attributes(path, "mode")
        if mode == "directory" then return true end
        assert(not mode, "Score directory path is not a directory")
        assert(directories.mkdir(path), "Cannot create score directory")
        assert(directories.attributes(path, "mode") == "directory", "Cannot verify score directory")
        return true
    end
    function fs.read(path)
        local attrOK, attributes, attrProblem, attrCode = pcall(directories.attributes, path)
        local file, problem, code = files.open(path, "rb")
        if not file then
            -- Positive existence/permission observations win over absence.
            -- With no errno, only a completed parent listing proves missing.
            if not attrOK or attributes or (attrCode and attrCode ~= 2) or (code and code ~= 2) then
                local attrError = attrProblem
                if not attrOK then attrError = attributes end
                return nil, "unreadable", "openCode=" .. tostring(code) .. "; attrCode=" .. tostring(attrCode) ..
                    "; openError=" .. tostring(problem) .. "; attrError=" .. tostring(attrError)
            end
            if code == 2 or attrCode == 2 then return nil, "missing" end
            local missing, detail = absent(path)
            return nil, missing and "missing" or "unreadable", detail
        end
        local ok, text = pcall(function()
            local value, readError = file:read(4 * 1024 * 1024 + 1)
            assert(not readError, "Score read failed")
            return value or ""
        end)
        local closed, closeDetail = invoke(file, "close")
        assert(ok and closed, "Score read/close failed; " .. closeDetail)
        return text
    end
    function fs.write(path, text)
        local file = files.open(path, "wb")
        if not file then return false, "open failed" end
        local written, writeDetail = invoke(file, "write", text)
        local flushed, flushDetail = true, "flush=unavailable"
        if written then
            local lookupOK, flush = pcall(function() return file.flush end)
            if not lookupOK then flushed, flushDetail = false, "flushReturn=lookup exception"
            elseif type(flush) == "function" then flushed, flushDetail = invoke(file, "flush") end
        end
        local closed, closeDetail = invoke(file, "close")
        local detail = writeDetail .. "; " .. flushDetail .. "; " .. closeDetail
        if not (written and flushed and closed) then return false, detail end
        if not reportedCompatibility and (detail:find("Return=nil", 1, true) or flushDetail == "flush=unavailable") then
            reportedCompatibility = true
            if reportCompatibility then reportCompatibility("IO_COMPATIBILITY: " .. detail) end
        end
        return true
    end
    function fs.rename(from, to)
        local before = fs.read(from)
        if not before then return false end
        local ok, result, problem = pcall(system.rename, from, to)
        if not ok or result == false or problem ~= nil then return false end
        local remaining, state = fs.read(from)
        return remaining == nil and state == "missing" and fs.read(to) == before
    end
    function fs.remove(path)
        local ok, result, problem = pcall(system.remove, path)
        if not ok or result == false or problem ~= nil then return false end
        local remaining, state = fs.read(path)
        return remaining == nil and state == "missing"
    end
    return fs
end
return PersistenceFS
