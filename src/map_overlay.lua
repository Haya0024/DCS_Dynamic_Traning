-- Cosmetic F10 drawings only; no mission, recovery, coalition or menu changes.
local MapOverlay = {}
-- Keep ownership across module reloads so reinitialization can remove old drawings.
DynamicTrainingMapOverlayState = DynamicTrainingMapOverlayState or { marks = {}, lastID = 0 }
local state = DynamicTrainingMapOverlayState

local function Log(text)
    env.info("[DynamicTraining] MapOverlay: " .. text)
end

local function AllocateID()
    -- Use the same allocator as MOOSE markers/drawings, rather than a competing
    -- fixed ID pair. Reserve a high starting point away from ME/user marker IDs.
    UTILS._MarkID = math.max(UTILS._MarkID, Config.mapOverlay.minimumDrawingID - 1, state.lastID)
    local id = UTILS.GetMarkID()
    state.lastID = id
    state.marks[id] = true -- Track before the DCS call, including partial failures.
    return id
end

local function Remove(id)
    local ok, result = pcall(trigger.action.removeMark, id)
    if ok and result ~= false then state.marks[id] = nil; return true end
    Log("[ERROR] Drawing cleanup failed for ID " .. id .. ": " .. tostring(result))
    return false -- Retain the ID for retry; never create duplicates over it.
end

local function Refresh()
    local cfg = Config.mapOverlay
    if not (AIRBASE and AIRBASE.GetAllAirbases and Airbase and Airbase.Category and
        COORDINATE and COORDINATE.NewFromVec2 and
        UTILS and UTILS.GetMarkID and type(UTILS._MarkID) == "number" and
        trigger and trigger.action and trigger.action.circleToAll and
        trigger.action.textToAll and trigger.action.removeMark) then
        Log("[ERROR] Required airbase/drawing API unavailable; overlay skipped.")
        return false
    end

    -- Enumerate MOOSE's runtime database, then check each current coalition.
    -- No terrain-specific list and no cached Mission Editor coalition values.
    local targets, seen = {}, {}
    for _, base in pairs(AIRBASE.GetAllAirbases()) do
        local ok, target = pcall(function()
            -- MOOSE corrects DCS heliport category bugs during registration.
            if base:GetCoalition() ~= coalition.side.BLUE or
                base:GetAirbaseCategory() ~= Airbase.Category.AIRDROME or
                base.isHelipad or base.isShip then return end
            -- MOOSE GetVec2 uses the runway center; DCS getPoint/GetVec3 can
            -- return the runway threshold instead of the ME airbase center.
            local name, center = base:GetName(), base:GetVec2()
            assert(type(name) == "string" and name ~= "", "Invalid airbase name")
            assert(type(center) == "table" and type(center.x) == "number" and
                type(center.y) == "number", "Invalid airbase center")
            local point = COORDINATE:NewFromVec2(center):GetVec3()
            assert(type(point) == "table" and type(point.x) == "number" and
                type(point.y) == "number" and type(point.z) == "number", "Invalid airbase position")
            return { name = name, point = point }
        end)
        if not ok then Log("[ERROR] Airbase observation failed: " .. tostring(target))
        elseif target and not seen[target.name] then
            seen[target.name] = true
            targets[#targets + 1] = target
        end
    end
    table.sort(targets, function(a, b) return a.name < b.name end)

    -- Query first: an enumeration failure leaves the existing overlay intact.
    local clean = true
    local old = {}
    for id in pairs(state.marks) do old[#old + 1] = id end
    for _, id in ipairs(old) do if not Remove(id) then clean = false end end
    if not clean then return false end

    local names, success = {}, true
    for _, target in ipairs(targets) do
        local circleID, textID
        local ok, err = pcall(function()
            circleID = AllocateID()
            -- Direct DCS calls intentionally keep IDs owned here even if drawing
            -- throws. Signatures match bundled MOOSE COORDINATE wrappers; RGBA
            -- is passed directly so wrapper alpha mutation cannot alter Config.
            local result = trigger.action.circleToAll(coalition.side.BLUE, circleID,
                target.point, cfg.radiusMeters, cfg.outlineColor, cfg.fillColor, 1, true, "")
            assert(result ~= false, "Circle rejected")
            textID = AllocateID()
            -- DCS Vec3 x points north; decrease only x to put the label south
            -- (down on a north-up F10 map), leaving the airbase Circle centered.
            local textPoint = { x = target.point.x - cfg.textOffsetSouthMeters,
                y = target.point.y, z = target.point.z }
            result = trigger.action.textToAll(coalition.side.BLUE, textID, textPoint,
                cfg.textColor, cfg.textFillColor, cfg.fontSize, true, "BLUE AIRBASE\n" .. target.name)
            assert(result ~= false, "Text rejected")
        end)
        if ok then names[#names + 1] = target.name
        else
            success = false
            Log("[ERROR] Drawing failed for " .. target.name .. ": " .. tostring(err))
            if circleID then Remove(circleID) end
            if textID then Remove(textID) end
        end
    end
    Log(string.format("BLUE land airbases drawn: %d [%s]", #names, table.concat(names, ", ")))
    return success
end

function MapOverlay.RefreshFriendlyAirbases()
    -- Overlay errors must never prevent mission initialization or existing play.
    local ok, result = pcall(Refresh)
    if not ok then Log("[ERROR] Refresh failed: " .. tostring(result)); return false end
    return result
end

return MapOverlay
