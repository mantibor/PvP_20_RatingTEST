local addonName, ns = ...

local AceComm = LibStub and LibStub("AceComm-3.0", true)
local Comm = {}
if AceComm then AceComm:Embed(Comm) end

ns.MAX_RECORDS_PER_SEND = 19

-- ============================================================================
-- SYSTEM MESSAGE SUPPRESSION
-- ============================================================================
local suppressFilterActive = false
local lastSendTime        = 0
local suppressWatcher     = nil
local SUPPRESS_IDLE       = 1

local function SystemMsgFilter()
    return true
end

local function SetSystemMessagesSuppressed(on)
    if not ChatFrame_AddMessageEventFilter then return end
    if on and not suppressFilterActive then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", SystemMsgFilter)
        suppressFilterActive = true
    elseif not on and suppressFilterActive then
        ChatFrame_RemoveMessageEventFilter("CHAT_MSG_SYSTEM", SystemMsgFilter)
        suppressFilterActive = false
    end
end

local function SuppressWatcherTick()
    if not suppressFilterActive then
        if suppressWatcher then
            suppressWatcher:Cancel()
        end
        suppressWatcher = nil
        return
    end
    if (GetTime() - lastSendTime) >= SUPPRESS_IDLE then
        SetSystemMessagesSuppressed(false)
        if suppressWatcher then
            suppressWatcher:Cancel()
        end
        suppressWatcher = nil
    end
end

local function OnOurMessageSent()
    lastSendTime = GetTime()
    SetSystemMessagesSuppressed(true)
    if not suppressWatcher then
        suppressWatcher = C_Timer.NewTicker(0.25, SuppressWatcherTick)
    end
end

if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    hooksecurefunc(C_ChatInfo, "SendAddonMessage", function(prefix)
        if prefix == ns.PREFIX then
            OnOurMessageSent()
        end
    end)
end

-- ============================================================================
-- LOCAL UTILITIES
-- ============================================================================
local function IsRecipientValid(nameRealm)
    if not nameRealm or nameRealm == "" then return false end
    local candidates = {}
    for i = 1, 4 do candidates[#candidates + 1] = "party" .. i end
    for i = 1, 40 do candidates[#candidates + 1] = "raid" .. i end
    for _, unit in ipairs(candidates) do
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local unitName = ns.FormatNameRealm(UnitName(unit))
            if unitName and unitName:lower() == nameRealm:lower() then
                return UnitIsConnected(unit) and not UnitInOtherParty(unit)
            end
        end
    end
    return true
end

-- ============================================================================
-- SEND FUNCTIONS
-- ============================================================================
function ns.CanSendAddonMessage()
    local lvl = UnitLevel("player")
    if not ns.IsLevel(lvl) then return false end
    local _, instanceType = GetInstanceInfo()
    if instanceType == "arena" or instanceType == "pvp" then
        if C_PvP.IsMatchActive() and not C_PvP.IsMatchComplete() then return false end
    end
    return true
end

-- Сообщения очереди (Q_STAT, WG_SETUP, H_LIST…) — «ТЕГ_» в начале; пакеты
-- кэша стычек закодированы LibDeflate и подчёркивания не содержат.
function ns.IsQueuePayload(text)
    return type(text) == "string" and text:match("^%u+_") ~= nil
end

-- Ключи очередей в сети короче: SOLO_SHUFFLE ↔ SS, ARENA_5V5 ↔ 5V5.
-- Меняем только поле целиком (между запятыми), имена игроков не задеваются.
local KEY_PACK = { SOLO_SHUFFLE = "SS", ARENA_5V5 = "5V5" }
local KEY_UNPACK = { SS = "SOLO_SHUFFLE", ["5V5"] = "ARENA_5V5" }
local function MapFields(text, map)
    return (text:gsub("[^,]+", map))
end
-- Заодно серверы в именах — номерами (Utils/RealmPack.lua).
function ns.PackQueueKeys(text)
    if not ns.IsQueuePayload(text) then return text end
    return ns.PackNamesInText(MapFields(text, KEY_PACK))
end
function ns.UnpackQueueKeys(text)
    if not ns.IsQueuePayload(text) then return text end
    return ns.UnpackNamesInText(MapFields(text, KEY_UNPACK))
end

function ns.SendAddonMessage(channel, target, payload, prio)
    if not payload or not AceComm or not ns.CanSendAddonMessage() then return false end
    payload = ns.PackQueueKeys(payload)
    Comm:SendCommMessage(ns.PREFIX, payload, channel, target, prio or "BULK")
    return true
end

function ns.SendWhisper(payload, target, prio)
    if not payload or not target or target == "" or ns.IsBlacklisted(target) then return false end
    return ns.SendAddonMessage("WHISPER", target, payload, prio)
end

function ns.SendGroup(payload, prio)
    if IsInGroup(1) and (GetNumGroupMembers(1) or 0) > 1 then
        return ns.SendAddonMessage("PARTY", nil, payload, prio)
    end
end

function ns.SendGuild(payload, prio)
    if not IsInGuild() or not payload then return false end
    return ns.SendAddonMessage("GUILD", nil, payload, prio)
end

function ns.SendInstance(payload, prio)
    if (GetNumGroupMembers() or 0) <= 1 then return false
    elseif IsInGroup(2) and (GetNumGroupMembers(2) or 0) > 1 then
        return ns.SendAddonMessage("INSTANCE_CHAT", nil, payload, prio)
    elseif IsInGroup(1) and (GetNumGroupMembers(1) or 0) > 1 then
        local channel = (IsInRaid(1) and not GameLimitedMode_IsActive()) and "RAID" or "PARTY"
        return ns.SendAddonMessage(channel, nil, payload, prio)
    else return false end
end

-- ============================================================================
-- RANDOM CACHE ROTATION
-- ============================================================================
local SessionSentGUIDs = {}
function ns.ResetSessionSent()
    SessionSentGUIDs = {}
end

local function GetRandomCacheBatch()
    ns.ScanGroupForBlacklist()
    local allGuids = {}
    local now = time()
    for guid, rec in pairs(ns.SkirmishDB) do
        if type(guid) == "string" and type(rec) == "table" and not ns.IsBlacklisted(rec.name)
        and (tonumber(rec.rating) or 0) > 0 and ns.IsNew(rec.lastUpdate) and not SessionSentGUIDs[guid] then
            table.insert(allGuids, guid)
        end
    end
    if #allGuids == 0 then
        ns.ResetSessionSent()
        for guid, rec in pairs(ns.SkirmishDB) do
            if type(guid) == "string" and type(rec) == "table" and not ns.IsBlacklisted(rec.name)
            and (tonumber(rec.rating) or 0) > 0 and ns.IsNew(rec.lastUpdate) then
                table.insert(allGuids, guid)
            end
        end
    end
    if #allGuids == 0 then return nil end
    for i = #allGuids, 2, -1 do local j = math.random(i); allGuids[i], allGuids[j] = allGuids[j], allGuids[i] end
    
    local count = math.min(ns.MAX_RECORDS_PER_SEND, #allGuids)
    local snapshot = {}
    for i = 1, count do
        local guid = allGuids[i]
        local rec = ns.SkirmishDB[guid]
        snapshot[guid] = { n = rec.name, r = rec.rating, b = rec.bestRating or rec.rating, p = rec.played or 0, w = rec.won or 0, c = rec.class, u = rec.lastUpdate or now }
        SessionSentGUIDs[guid] = true
    end
    return ns.EncodeBinary("~S", snapshot) or ns.EncodeForSend({ v = ns.PROTOCOL_VERSION, s = snapshot })
end
ns.GetRandomCacheBatch = GetRandomCacheBatch

function ns.BuildFullCacheSnapshot()
    ns.ScanGroupForBlacklist()
    local now, snapshot = time(), {}
    for guid, rec in pairs(ns.SkirmishDB) do
        if type(guid) == "string" and type(rec) == "table" and not ns.IsBlacklisted(rec.name)
        and (tonumber(rec.rating) or 0) > 0 and ns.IsNew(rec.lastUpdate) then
            snapshot[guid] = { n = rec.name, r = rec.rating, b = rec.bestRating or rec.rating, p = rec.played or 0, w = rec.won or 0, c = rec.class, u = rec.lastUpdate or now }
        end
    end
    return snapshot
end

-- ============================================================================
-- HANDSHAKES & MATCH SYNC
-- ============================================================================
local function GetAllMatchTimestamps()
    local matchDB = ns.GetMatchDB()
    if not matchDB then return {} end
    local timestamps = {}
    for ts in pairs(matchDB) do
        if type(ts) == "number" then
            timestamps[#timestamps + 1] = ts
        end
    end
    table.sort(timestamps)
    return timestamps
end

local function GetWhitelistStats()
    local pd = ns.GetWhitelistDB()
    local count, latest = 0, 0
    for name, ts in pairs(pd) do
        count = count + 1
        if type(ts) == "number" and ts > latest then latest = ts end
    end
    return count, latest
end

function ns.SendHandshake(channel, target)
    local timestamps = GetAllMatchTimestamps()
    local matchCount = #timestamps
    local matchLastTs = matchCount > 0 and timestamps[matchCount] or nil
    local pdCount, pdLatest = GetWhitelistStats()
    if matchCount == 0 and pdCount == 0 then return end
    local payload = ns.EncodeForSend({ 
        v = ns.PROTOCOL_VERSION, 
        mth = matchCount > 0 and { c = matchCount, l = matchLastTs } or nil,
        pdh = pdCount > 0 and { c = pdCount, l = pdLatest } or nil
    })
    if payload then ns.SendAddonMessage(channel, target, payload, "BULK") end
end

function ns.BroadcastHandshake()
    local timestamps = GetAllMatchTimestamps()
    local matchCount = #timestamps
    local matchLastTs = matchCount > 0 and timestamps[matchCount] or nil
    local pdCount, pdLatest = GetWhitelistStats()
    if matchCount == 0 and pdCount == 0 then return end
    local payload = ns.EncodeForSend({ 
        v = ns.PROTOCOL_VERSION, 
        mth = matchCount > 0 and { c = matchCount, l = matchLastTs } or nil,
        pdh = pdCount > 0 and { c = pdCount, l = pdLatest } or nil
    })
    if payload then ns.SendInstance(payload) end
end

-- ============================================================================
-- RECEIVING AND MERGING
-- ============================================================================
local function OnCommReceived(prefix, payload, sender, distribution)
    if prefix ~= ns.PREFIX or ns.IsBlacklisted(sender) or not payload or #payload < 5 then return end
    local myName = ns.FormatNameRealm(UnitName("player"))
    local normalizedSender = ns.FormatNameRealm(sender)
    if normalizedSender and normalizedSender ~= myName then ns.AddPlayer(normalizedSender) end

    -- Сообщения очереди длиннее 255 байт (WG_SETUP из шести кириллических
    -- имён — 311) AceComm режет на куски, а очередь слушает сырой CHAT_MSG_ADDON
    -- и кусков не узнаёт. Собранное целиком отдаём ей отсюда. Короткие она
    -- уже получила сама, их не дублируем.
    if #payload > 255 and ns.IsQueuePayload(payload) then
        payload = ns.UnpackQueueKeys(payload)
        if ns.QLog then ns.QLog("<< " .. tostring(sender) .. " [" .. tostring(distribution) .. ", из частей]: " .. payload) end
        if ns.StateMachine and ns.StateMachine.HandleQueueMessage then
            ns.StateMachine.HandleQueueMessage(sender, payload)
        end
        return
    end

    -- двоичные пакеты (BinaryPack.lua) — в тот же вид, что прежние таблицы
    local data
    local bin, tag = ns.DecodeBinary(payload)
    if tag == "~S" then data = { v = ns.PROTOCOL_VERSION, s = bin }
    elseif tag == "~W" then data = { v = ns.PROTOCOL_VERSION, pd = bin }
    else data = ns.DecodePayload(payload) end
    if not data or data.v ~= ns.PROTOCOL_VERSION then return end
    
    -- 1. Запрос кэша игроков (REQ) — отвечаем батчем + хендшейком
    if data.req then
        local batch = GetRandomCacheBatch()
        
        if distribution == "PARTY" or distribution == "RAID" or distribution == "INSTANCE_CHAT" then
            if batch then ns.SendGroup(batch) end
            ns.BroadcastHandshake()
        else
            if batch then ns.SendWhisper(batch, normalizedSender) end
            ns.SendHandshake("WHISPER", normalizedSender)
        end
        return
    end
    
    -- 2. Получение кэша игроков (Snapshot)
    if type(data.s) == "table" then
        ns.MergeSnapshot(data.s)
        return
    end
    
    -- 3. Хендшейк матчей (mth)
    if type(data.mth) == "table" then
        local remoteCount = data.mth.c
        local remoteLastTs = data.mth.l
        local myTs = GetAllMatchTimestamps()
        local myCount = #myTs
        local myLastTs = myTs[#myTs] or 0
        
        if myCount < remoteCount or myLastTs < remoteLastTs then
            local reqPayload = ns.EncodeForSend({ v = ns.PROTOCOL_VERSION, mtr = true })
            if reqPayload then ns.SendWhisper(reqPayload, normalizedSender) end
        end
    end
    
    -- 4. Хендшейк whitelist (pdh)
    if type(data.pdh) == "table" then
        local remoteCount = data.pdh.c
        local remoteLastTs = data.pdh.l
        local myCount, myLastTs = GetWhitelistStats()
        
        if myCount < remoteCount or myLastTs < remoteLastTs then
            local reqPayload = ns.EncodeForSend({ v = ns.PROTOCOL_VERSION, pdr = true })
            if reqPayload then ns.SendWhisper(reqPayload, normalizedSender) end
        end
    end
    
    if data.mth or data.pdh then return end
    
    -- 5. Запрос списка timestamp'ов матчей (mtr)
    if data.mtr then
        local timestamps = GetAllMatchTimestamps()
        if #timestamps > 0 then
            local payload = ns.EncodeForSend({ v = ns.PROTOCOL_VERSION, mt = timestamps })
            if payload then ns.SendWhisper(payload, normalizedSender) end
        end
        return
    end
    
    -- 6. Получение списка timestamp'ов (mt)
    if type(data.mt) == "table" then
        local matchDB = ns.GetMatchDB()
        if matchDB then
            local missing = {}
            for _, ts in ipairs(data.mt) do
                if not matchDB[ts] then missing[#missing + 1] = ts end
            end
            if #missing > 0 then
                local req = ns.EncodeForSend({ v = ns.PROTOCOL_VERSION, mr = missing })
                if req then ns.SendWhisper(req, normalizedSender) end
            end
        end
        return
    end
    
    -- 7. Запрос тел матчей (mr)
    if type(data.mr) == "table" then
        local matchDB = ns.GetMatchDB()
        if matchDB then
            local matches = {}
            for _, ts in ipairs(data.mr) do
                local raw = matchDB[ts]
                if raw then
                    if type(raw) == "string" then
                        matches[tostring(ts)] = raw
                    elseif type(raw) == "table" and ns.CanCompress() then
                        matches[tostring(ts)] = ns.EncodeMatch(raw)
                    end
                end
            end
            if next(matches) then
                local resp = ns.EncodeForSend({ v = ns.PROTOCOL_VERSION, md = matches })
                if resp then ns.SendWhisper(resp, normalizedSender) end
            end
        end
        return
    end
    
    -- 8. Получение тел матчей (md)
    if type(data.md) == "table" then
        local matchDB = ns.GetMatchDB()
        if matchDB then
            local added = 0
            for tsStr, d in pairs(data.md) do
                local ts = tonumber(tsStr)
                if ts and not matchDB[ts] then
                    matchDB[ts] = d
                    added = added + 1
                end
            end
            if added > 0 and ns.Leaderboard_Update then ns.Leaderboard_Update() end
        end
        return
    end
    
    -- 9. Запрос whitelist (pdr)
    if data.pdr then
        local pd = ns.GetWhitelistDB()
        if next(pd) then
            local payload = ns.EncodeBinary("~W", pd) or ns.EncodeForSend({ v = ns.PROTOCOL_VERSION, pd = pd })
            if payload then ns.SendWhisper(payload, normalizedSender) end
        end
        return
    end
    
    -- 10. Получение whitelist (pd)
    if type(data.pd) == "table" then
        local localPD = ns.GetWhitelistDB()
        for name, ts in pairs(data.pd) do
            if type(name) == "string" and type(ts) == "number" then
                if not localPD[name] or ts > localPD[name] then localPD[name] = ts end
            end
        end
        return
    end
end

-- ============================================================================
-- NETWORK EVENTS & MATCH COMPLETE SYNC
-- ============================================================================
local syncedInCurrentGroup = false

local function HandleRosterUpdate()
    if IsInGroup(LE_PARTY_CATEGORY_HOME) then
        if not syncedInCurrentGroup then
            syncedInCurrentGroup = true
            local req = ns.EncodeForSend({ v = ns.PROTOCOL_VERSION, req = true })
            if req then ns.SendInstance(req) end
            ns.BroadcastHandshake()
        end
    else
        syncedInCurrentGroup = false
    end
end

local function HandleMatchComplete()
    local enemyNames = {}
    local myGuid = UnitGUID("player")
    local total = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
    if total == 0 then return end

    local myFaction
    for i = 1, total do
        local ok, score = pcall(C_PvP.GetScoreInfo, i)
        if ok and score and score.guid == myGuid then myFaction = score.faction; break end
    end

    for i = 1, total do
        local ok, score = pcall(C_PvP.GetScoreInfo, i)
        if ok and score and score.guid and score.guid ~= myGuid then
            if myFaction ~= nil and score.faction ~= myFaction then
                local name = (score.name and score.name ~= "") and ns.FormatNameRealm(score.name) or nil
                if name then enemyNames[#enemyNames + 1] = name end
            end
        end
    end

    -- 1. Отправляем ТОЛЬКО запрос кэша врагам (шепотом)
    local req = ns.EncodeForSend({ v = ns.PROTOCOL_VERSION, req = true })
    if req then
        for _, name in ipairs(enemyNames) do
            if IsRecipientValid(name) then ns.SendWhisper(req, name) end
        end
    end

    -- 2. Отправляем случайный батч в СВОЮ группу
    local batch = GetRandomCacheBatch()
    if batch then
        ns.SendGroup(batch)
    end

    -- 3. Хендшейк отправляем только в группу
    ns.BroadcastHandshake()
end

local function HandlePlayerLogin()
    ns.ResetSessionSent()
    C_Timer.After(3, function()
        if not ns.CanSendAddonMessage() then return end
        local fullSnapshot = ns.BuildFullCacheSnapshot()
        if fullSnapshot and next(fullSnapshot) then
            local payload = ns.EncodeBinary("~S", fullSnapshot) or ns.EncodeForSend({ v = ns.PROTOCOL_VERSION, s = fullSnapshot })
            if payload then ns.SendGuild(payload) end
        end
        ns.SendHandshake("GUILD", nil)
    end)
end

-- ============================================================================
-- EVENT FRAME
-- ============================================================================
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        if AceComm then
            Comm:RegisterComm(ns.PREFIX, function(prefix, message, distribution, sender)
                OnCommReceived(prefix, message, sender, distribution)
            end)
        end
        self:RegisterEvent("GROUP_ROSTER_UPDATE")
        self:RegisterEvent("PVP_MATCH_COMPLETE")
        self:RegisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_LOGIN" then
        HandlePlayerLogin()
    elseif event == "PLAYER_LOGOUT" then
        if suppressWatcher then
            suppressWatcher:Cancel()
            suppressWatcher = nil
        end
        SetSystemMessagesSuppressed(false)
    elseif event == "GROUP_ROSTER_UPDATE" then
        HandleRosterUpdate()
    elseif event == "PVP_MATCH_COMPLETE" then
        HandleMatchComplete()
    end
end)