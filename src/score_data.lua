-- Shared pure-data codec. Mission and hook use the same bounded schema.
local ScoreData = {}
ScoreData.fields = { "totalScore", "careerPoints", "interceptScore", "seadScore", "deadScore",
    "missionCount", "primarySuccessCount", "rtbSuccessCount", "recoveryFailureCount",
    "failedCount", "abortCount", "deathCount", "capScore" }
local legacyFields = {}
for i = 1, #ScoreData.fields - 1 do legacyFields[i] = ScoreData.fields[i] end
local function integer(n)
    return type(n) == "number" and n >= 0 and n <= 9007199254740991 and n == math.floor(n)
end
local function hex(s)
    return (s:gsub(".", function(c) return string.format("%02x", string.byte(c)) end))
end
local function unhex(s)
    assert(#s % 2 == 0 and not s:find("[^0-9a-f]"), "Invalid encoded string")
    return (s:gsub("..", function(c) return string.char(tonumber(c, 16)) end))
end
function ScoreData.Empty()
    return { counter = 0, session = 0, revision = 0, players = {} }
end
function ScoreData.Validate(data)
    assert(type(data) == "table" and integer(data.counter) and integer(data.session)
        and data.session <= data.counter and integer(data.revision), "Invalid score metadata")
    assert(type(data.players) == "table", "Invalid score accounts")
    local count = 0
    for ucid, p in pairs(data.players) do
        count = count + 1
        assert(count <= 10000 and type(ucid) == "string" and #ucid > 0 and #ucid <= 128,
            "Invalid score identity or account limit")
        assert(type(p) == "table" and type(p.lastKnownName or "") == "string"
            and #(p.lastKnownName or "") <= 256, "Invalid score name")
        for _, field in ipairs(ScoreData.fields) do assert(integer(p[field]), "Invalid score field: " .. field) end
    end
    return data
end
local function encode(data, version)
    ScoreData.Validate(data)
    local fields = version == 1 and legacyFields or ScoreData.fields
    local lines = { string.format("DT_SCORE\t%d\t%.0f\t%.0f\t%.0f", version, data.counter, data.session, data.revision) }
    local keys = {}
    for ucid in pairs(data.players) do keys[#keys + 1] = ucid end
    table.sort(keys)
    for _, ucid in ipairs(keys) do
        local p = data.players[ucid]
        local parts = { "P", hex(ucid), hex(p.lastKnownName or "") }
        for _, field in ipairs(fields) do parts[#parts + 1] = string.format("%.0f", p[field]) end
        lines[#lines + 1] = table.concat(parts, "\t")
    end
    local body = table.concat(lines, "\n") .. "\n"
    -- A trailer detects truncated complete rows, not just malformed fields.
    local sum = 0
    for i = 1, #body do sum = (sum * 31 + body:byte(i)) % 2147483647 end
    local text = body .. string.format("END\t%d\t%.0f\n", #keys, sum)
    assert(#text <= 4 * 1024 * 1024, "Score file exceeds limit")
    return text
end
function ScoreData.Encode(data) return encode(data, 2) end
function ScoreData.Decode(text)
    assert(type(text) == "string" and #text <= 4 * 1024 * 1024, "Invalid score file size")
    local body, rows, expected = text:match("^(.*\n)END\t(%d+)\t(%d+)\n$")
    assert(body, "Missing score trailer")
    local sum = 0
    for i = 1, #body do sum = (sum * 31 + body:byte(i)) % 2147483647 end
    assert(sum == tonumber(expected), "Score checksum mismatch")
    local header, rest = body:match("^([^\n]+)\n(.*)$")
    local version, counter, session, revision = header:match("^DT_SCORE\t(%d+)\t(%d+)\t(%d+)\t(%d+)$")
    version = tonumber(version)
    assert(counter and (version == 1 or version == 2), "Unsupported score schema")
    local fields = version == 1 and legacyFields or ScoreData.fields
    local data = { counter = tonumber(counter), session = tonumber(session), revision = tonumber(revision), players = {} }
    local count = 0
    for line in rest:gmatch("([^\n]+)\n") do
        local parts = {}
        for value in (line .. "\t"):gmatch("([^\t]*)\t") do parts[#parts + 1] = value end
        assert(#parts == 3 + #fields and parts[1] == "P", "Invalid score row")
        local ucid, name = unhex(parts[2]), unhex(parts[3])
        assert(not data.players[ucid], "Duplicate score identity")
        local p = { lastKnownName = name, capScore = 0 }
        for i, field in ipairs(fields) do
            assert(parts[i + 3]:match("^%d+$"), "Invalid score number")
            p[field] = tonumber(parts[i + 3])
        end
        data.players[ucid], count = p, count + 1
    end
    assert(count == tonumber(rows), "Score row count mismatch")
    ScoreData.Validate(data)
    assert(encode(data, version) == text, "Noncanonical score file")
    return data
end
return ScoreData
