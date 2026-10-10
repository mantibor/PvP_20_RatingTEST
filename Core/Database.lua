local addonName, ns = ...
-- ============================================================================
-- STATE INITIALIZATION
-- ============================================================================
ns.SkirmishDB = ns.SkirmishDB or {}
ns.ArchiveSortedKeys = {}
ns.ArchiveCache = {}

-- ============================================================================
-- REGION HELPERS
-- ============================================================================
function ns.GetRegionKey()
    return ns.REGION_KEYS[GetCurrentRegion()]
end

local function EnsureTable(parent, key)
    if type(parent[key]) ~= "table" then parent[key] = {} end
    return parent[key]
end

function ns.GetRegionDB()
    PvP_20_RatingDB = PvP_20_RatingDB or {}
    return EnsureTable(PvP_20_RatingDB, ns.GetRegionKey())
end

function ns.GetMatchDB()
    return EnsureTable(ns.GetRegionDB(), "MatchData")
end

-- ============================================================================
-- GENERIC DB COMPRESSION / DECOMPRESSION
-- ============================================================================
function ns.CompressDB(regionKey, sourceTable, filterFn)
    if not ns.CanCompress() or type(sourceTable) ~= "table" then return end
    local regionDB = ns.GetRegionDB()
    local data = sourceTable
    if filterFn then
        data = {}
        for k, v in pairs(sourceTable) do
            if filterFn(k, v) then data[k] = v end
        end
    end
    if not next(data) then
        regionDB[regionKey] = nil
        return
    end
    local blob = ns.EncodeEntry(data)
    if blob then regionDB[regionKey] = blob end
end

function ns.DecompressDB(regionKey, targetTable, filterFn)
    local regionDB = ns.GetRegionDB()
    local raw = regionDB[regionKey]
    local data
    if type(raw) == "string" then
        data = ns.DecodeEntry(raw)
    elseif type(raw) == "table" then
        data = raw
    end
    targetTable = targetTable or {}
    if type(data) ~= "table" then return targetTable end
    for k, v in pairs(data) do
        if not filterFn or filterFn(k, v) then
            targetTable[k] = v
        end
    end
    return targetTable
end

local function GetDB(regionKey)
    local regionDB = ns.GetRegionDB()
    local v = regionDB[regionKey]
    if type(v) == "string" then
        v = ns.DecodeEntry(v) or {}
        regionDB[regionKey] = v
    elseif type(v) ~= "table" then
        v = {}
        regionDB[regionKey] = v
    end
    return v
end

-- ============================================================================
-- BLACKLIST & WHITELIST
-- ============================================================================
function ns.GetBlacklistDB() return GetDB("Blacklist") end
function ns.GetWhitelistDB() return GetDB("Whitelist") end

function ns.AddToBlacklist(name)
    if not name or name == "" then return end
    ns.GetBlacklistDB()[name] = true
end

function ns.IsBlacklisted(name)
    local bl = ns.GetBlacklistDB()
    return type(bl) == "table" and name and bl[name] and true or false
end

function ns.IsInWhitelist(nameRealm)
    if not nameRealm or nameRealm == "" then return false end
    local wl = ns.GetWhitelistDB()
    return type(wl) == "table" and wl[nameRealm] ~= nil
end

function ns.ScanGroupForBlacklist()
    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "arena" and instanceType ~= "pvp" then return end
    local n = GetNumGroupMembers() or 0
    if n <= 1 then return end
    local prefix = IsInRaid() and "raid" or "party"
    local max = IsInRaid() and n or (n - 1)
    for i = 1, max do
        local unit = prefix .. i
        if UnitExists(unit) and UnitIsPlayer(unit) and UnitCanAttack("player", unit) and not UnitIsUnit(unit, "player") then
            local lvl = UnitLevel(unit)
            if lvl > 0 and lvl ~= 20 and lvl ~= 21 then
                local name = ns.FormatNameRealm(UnitName(unit))
                if name then ns.AddToBlacklist(name) end
            end
        end
    end
end

function ns.AddPlayer(nameRealm)
    if not nameRealm or nameRealm == "" or ns.IsBlacklisted(nameRealm) then return end
    ns.GetWhitelistDB()[nameRealm] = time()
end

-- ============================================================================
-- SKIRMISH DB (Shared Player Data)
-- ============================================================================
function ns.SaveSharedData(guid, senderName, rating, played, won, class, recency, incomingBest)
    if not guid or not played or played <= 0 or (tonumber(rating) or 0) <= 0 then return end
    if ns.IsBlacklisted(senderName) then return end
    
    local prev = ns.SkirmishDB[guid]
    if type(recency) ~= "number" or recency <= ns.EPOCH_MIN then recency = time() end
    if prev and type(prev.lastUpdate) == "number" and prev.lastUpdate >= recency then return end
    
    local bestRating = rating
    if type(incomingBest) == "number" and incomingBest > bestRating then
        bestRating = incomingBest
    end
    if prev and type(prev.bestRating) == "number" and prev.bestRating > bestRating then
        bestRating = prev.bestRating
    end
    
    -- [FIX] Сохраняем локальные параметры Glicko-2 (rd, volatility, matches), 
    -- чтобы они не стирались при обновлении данных из сети или после матча.
    ns.SkirmishDB[guid] = {
        name = senderName,
        rating = rating,
        bestRating = bestRating,
        played = played,
        won = won,
        class = class,
        winrate = played > 0 and (100 * won / played) or 0,
        lastUpdate = recency,
        rd = (prev and prev.rd) or 350,
        volatility = (prev and prev.volatility) or 0.06,
        matches = (prev and prev.matches) or 0,
    }
end

function ns.MergeSnapshot(snapshot)
    for guid, rec in pairs(snapshot) do
        if type(guid) == "string" and type(rec) == "table"
        and not ns.IsBlacklisted(rec.n)
        and (tonumber(rec.r) or 0) > 0
        and (tonumber(rec.u) or 0) > ns.EPOCH_MIN
        and (time() - (tonumber(rec.u) or 0)) <= ns.MAX_CACHE_AGE then
            
            local prev = ns.SkirmishDB[guid]
            local incomingTime = tonumber(rec.u) or 0
            local haveTime = (type(prev) == "table" and tonumber(prev.lastUpdate)) or 0
            
            if incomingTime > haveTime then
                ns.SaveSharedData(guid, rec.n or "?", tonumber(rec.r) or 0,
                    tonumber(rec.p) or 0, tonumber(rec.w) or 0,
                    rec.c, incomingTime, tonumber(rec.b))
            end
        end
    end
end

local myData = nil
function ns.SetMySkirmishData(rating, played, won)
    if type(rating) ~= "number" then return end
    played, won = tonumber(played) or 0, tonumber(won) or 0
    if myData and (myData.played or 0) > 0 and played == 0 then return end
    myData = { rating = rating, played = played, won = won }
    local guid = UnitGUID("player")
    if guid then
        ns.SaveSharedData(guid, ns.FormatNameRealm(UnitName("player")),
            rating, played, won, select(2, UnitClass("player")))
    end
end

function ns.GetMySkirmishData()
    local guid = UnitGUID("player")
    local rec = guid and ns.SkirmishDB[guid] or nil
    if myData then
        if rec and (tonumber(rec.bestRating) or 0) > 0 then
            myData.bestRating = rec.bestRating
        elseif not myData.bestRating then
            myData.bestRating = myData.rating
        end
        return myData
    end
    return rec or nil
end

-- ============================================================================
-- MIGRATION, SEASON RESET  & CLEANUP
-- ============================================================================
local function Migrate(regionDB, matchDB)
    for _, src in ipairs({ PvP_20_RatingDB, regionDB }) do
        for k, v in pairs(src) do
            if type(k) == "number" then matchDB[k] = v; src[k] = nil end
        end
    end
    
    if type(PvP_20_RatingSkirmishDB) == "table" then
        if not regionDB["SkirmishData"] and PvP_20_RatingSkirmishDB["__compressed"] then
            regionDB["SkirmishData"] = PvP_20_RatingSkirmishDB["__compressed"]
        end
        if not regionDB["SeasonReset"] and PvP_20_RatingSkirmishDB["__seasonReset"] then
            regionDB["SeasonReset"] = PvP_20_RatingSkirmishDB["__seasonReset"]
        end
        _G.PvP_20_RatingSkirmishDB = nil
    end
    
    local obsoleteKeys = { "__compressed", "__arenaLogCompressed", "__seasonReset", "__calib", "__arenaLog", "__debug" }
    for _, key in ipairs(obsoleteKeys) do
        if key == "__seasonReset" and regionDB[key] ~= nil and not regionDB["SeasonReset"] then
            regionDB["SeasonReset"] = regionDB[key]
        end
        regionDB[key] = nil
        PvP_20_RatingDB[key] = nil
    end
end
ns.Migrate = Migrate

function ns.SeasonReset(regionDB, matchDB)
    local seasonStart = ns.SEASON_START_UTC[GetCurrentRegion()]
    if not (seasonStart and seasonStart > 0) or GetServerTime() < seasonStart then return end
    local marker = tonumber(regionDB["SeasonReset"]) or 0
    if marker >= seasonStart then return end
    
    local keptSkirmish = {}
    for guid, rec in pairs(ns.SkirmishDB) do
        if type(rec) == "table" and (tonumber(rec.lastUpdate) or 0) >= seasonStart then
            keptSkirmish[guid] = rec
        end
    end
    ns.SkirmishDB = keptSkirmish
    
    for k in pairs(matchDB) do
        if type(k) == "number" and k < seasonStart then matchDB[k] = nil end
    end
    
    if type(ns.ArchiveSortedKeys) == "table" then
        local newKeys = {}
        for _, ts in ipairs(ns.ArchiveSortedKeys) do
            if ts >= seasonStart then newKeys[#newKeys + 1] = ts end
        end
        ns.ArchiveSortedKeys = newKeys
    end
    
    if type(ns.ArchiveCache) == "table" then
        for ts in pairs(ns.ArchiveCache) do
            if ts < seasonStart then ns.ArchiveCache[ts] = nil end
        end
    end
    
    ns.CompressDB("SkirmishData", ns.SkirmishDB, function(k, v) return type(k) == "string" and type(v) == "table" end)
    regionDB["SeasonReset"] = seasonStart
end

function ns.Cleanup()
    for guid, rec in pairs(ns.SkirmishDB) do
        if type(guid) == "string" and type(rec) == "table" then
            if ns.IsBlacklisted(rec.name) or (tonumber(rec.rating) or 0) <= 0 then
                ns.SkirmishDB[guid] = nil
            end
        end
    end
end

-- ============================================================================
-- EVENT FRAME: Инициализация БД при загрузке аддона
-- ============================================================================
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        local regionDB = ns.GetRegionDB()
        local matchDB = ns.GetMatchDB()
        
        Migrate(regionDB, matchDB)
        
        if ns.InitArchiveKeys then
            ns.InitArchiveKeys()
        end
        
        local skirmishFilter = function(k, v)
            return type(k) == "string" and type(v) == "table"
        end
        
        ns.DecompressDB("SkirmishData", ns.SkirmishDB, skirmishFilter)
        regionDB["Whitelist"] = ns.DecompressDB("Whitelist")
        regionDB["Blacklist"] = ns.DecompressDB("Blacklist")
        
        ns.SeasonReset(regionDB, matchDB)
        ns.Cleanup()
    elseif event == "PLAYER_LOGOUT" then
        local regionDB = ns.GetRegionDB()
        local skirmishFilter = function(k, v) return type(k) == "string" and type(v) == "table" end
        ns.CompressDB("SkirmishData", ns.SkirmishDB, skirmishFilter)
        ns.CompressDB("Whitelist", regionDB["Whitelist"])
        ns.CompressDB("Blacklist", regionDB["Blacklist"])
    end
end)