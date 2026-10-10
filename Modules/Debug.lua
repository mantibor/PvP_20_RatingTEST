local addonName, ns = ...

-- ============================================================================
-- DEBUG FLAG & HELPERS
-- ============================================================================
local function IsDebugOn()
    return PvP_20_RatingDB and PvP_20_RatingDB.Debug == true
end
ns.IsDebugOn = IsDebugOn

local function DebugPrint(msg)
    if IsDebugOn() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8000[PvP20R Debug]|r " .. tostring(msg))
    end
end
ns.DebugPrint = DebugPrint

-- ============================================================================
-- COLORS & FORMATTING
-- ============================================================================
local CLASS_COLORS = {
    WARRIOR     = "|cffC79C6E", PALADIN     = "|cffF58CBA", HUNTER      = "|cffABD473",
    ROGUE       = "|cffFFF569", PRIEST      = "|cffFFFFFF", DEATHKNIGHT = "|cffC41F3B",
    SHAMAN      = "|cff0070DE", MAGE        = "|cff69CCF0", WARLOCK     = "|cff9482C9",
    MONK        = "|cff00FF96", DRUID       = "|cffFF7D0A", DEMONHUNTER = "|cffA330C9",
    EVOKER      = "|cff33937F",
}
local cReset     = "|r"
local cSep       = "|cff666666"
local cLabel     = "|cff00ffff"
local cRating    = "|cffffd700"
local cGuid      = "|cff808080"
local cTime      = "|cffa0a0a0"
local cFactionH  = "|cffff0000"
local cFactionA  = "|cff0070ff"
local cName      = "|cffffd100"
local cDebugTag  = "|cffff8000[PvP20R Debug]|r"

local function GetClassColor(class)
    return CLASS_COLORS[tostring(class):upper()] or "|cffffffff"
end

-- ============================================================================
-- COMM DEBUG (Перехват через AceComm — ЕДИНСТВЕННЫЙ источник)
-- ============================================================================
local LibDeflate    = LibStub and LibStub("LibDeflate", true)
local AceSerializer = LibStub and LibStub("AceSerializer-3.0", true)
local AceCommLib    = LibStub and LibStub("AceComm-3.0", true)
local COMM_PREFIX   = ns.PREFIX

local function DecodePayloadDebug(payload)
    if not LibDeflate or not AceSerializer or not payload then return nil end
    local d = LibDeflate:DecodeForWoWAddonChannel(payload)
    if not d then return nil end
    d = LibDeflate:DecompressDeflate(d)
    if not d then return nil end
    local ok, tbl = AceSerializer:Deserialize(d)
    if ok and type(tbl) == "table" then return tbl end
    return nil
end

local function PrettySerialize(v, visited)
    visited = visited or {}
    local tv = type(v)
    if tv == "number" then
        return tostring(v)
    elseif tv == "string" then
        return '"' .. v .. '"'
    elseif tv == "boolean" then
        return v and "T" or "F"
    elseif tv == "nil" then
        return "nil"
    elseif tv == "table" then
        if visited[v] then return "<c>" end
        visited[v] = true
        local numKeys, strKeys = {}, {}
        for k in pairs(v) do
            if type(k) == "number" then numKeys[#numKeys + 1] = k
            else strKeys[#strKeys + 1] = tostring(k) end
        end
        table.sort(numKeys)
        table.sort(strKeys)
        local isArray = (#numKeys > 0 and #strKeys == 0
                         and numKeys[1] == 1 and numKeys[#numKeys] == #numKeys)
        local result
        if isArray then
            local parts = {}
            for _, k in ipairs(numKeys) do
                parts[#parts + 1] = PrettySerialize(v[k], visited)
            end
            result = "{ " .. table.concat(parts, ", ") .. " }"
        else
            local parts = {}
            for _, k in ipairs(numKeys) do
                parts[#parts + 1] = PrettySerialize(v[k], visited)
            end
            for _, k in ipairs(strKeys) do
                if k ~= "v" then
                    parts[#parts + 1] = k:upper() .. " = " .. PrettySerialize(v[k], visited)
                end
            end
            result = "{ " .. table.concat(parts, "; ") .. " }"
        end
        visited[v] = nil
        return result
    end
    return tostring(v)
end

local function FormatDecoded(tbl)
    local keys = {}
    for k in pairs(tbl) do
        if k ~= "v" then keys[#keys + 1] = tostring(k) end
    end
    table.sort(keys)
    if #keys == 1 then
        local k = keys[1]
        return k:upper() .. " = " .. PrettySerialize(tbl[k])
    end
    return PrettySerialize(tbl)
end

local function EscapeRaw(text, maxLen)
    maxLen = maxLen or 200
    local s = text:sub(1, maxLen)
    -- Кодом показываем только управляющие байты. Раньше кодировался всякий
    -- байт вне ASCII, и кириллица (два байта UTF-8 на букву) читалась как
    -- xD0x9A...; "\x" Lua 5.1 к тому же не знает и теряет обратную черту.
    -- "|" удваиваем, чтобы чат не принял кусок сообщения за цветовой код.
    s = s:gsub("[%z\1-\31\127]", function(c)
        return string.format("\\x%02X", c:byte())
    end):gsub("|", "||")
    if #text > maxLen then
        s = s .. "|cff888888... [+" .. (#text - maxLen) .. " chars]|r"
    end
    return s
end

local function PrintSnapshotTable(snapshot, direction, channel, targetOrSender)
    local count = 0
    for _ in pairs(snapshot) do count = count + 1 end
    local dirColor = direction == "IN" and "|cff9aff9a" or "|cff00ff00"
    local dirTag   = direction == "IN" and "[IN CACHE]" or "[OUT CACHE]"
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "%s %s%s|r | |cff00ccff%s|r | |cffffd700%s|r | |cff00ff00Игроков: %d|r",
        cDebugTag, dirColor, dirTag, channel or "?", targetOrSender or "?", count
    ))
    local list = {}
    for guid, rec in pairs(snapshot) do
        if type(rec) == "table" then list[#list + 1] = rec end
    end
    table.sort(list, function(a, b) return (tonumber(a.r) or 0) > (tonumber(b.r) or 0) end)
    for _, rec in ipairs(list) do
        local class = tostring(rec.c or ""):upper()
        local cClass = CLASS_COLORS[class] or "|cffffffff"
        local name = rec.n or "?"
        local r = tonumber(rec.r) or 0
        local b = tonumber(rec.b) or 0
        local p = tonumber(rec.p) or 0
        local w = tonumber(rec.w) or 0
        local wr = p > 0 and math.floor(100 * w / p) or 0
        local cWr = wr >= 50 and "|cff00ff00" or "|cffff0000"
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  %s%-18s|r | %sR:%d|r | %sB:%d|r | %s%d/%d (%s%d%%|r)",
            cClass, name, cRating, r, cLabel, b, cSep, w, p, cWr, wr
        ))
    end
end

local function HandleCommMessage(text, direction, channel, targetOrSender)
    if not text or text == "" then return end
    local tbl = DecodePayloadDebug(text)
    if tbl and type(tbl) == "table" then
        if type(tbl.s) == "table" or type(tbl.S) == "table" then
            PrintSnapshotTable(tbl.s or tbl.S, direction, channel, targetOrSender)
            return
        end
        local decodedStr = FormatDecoded(tbl)
        if #decodedStr > 600 then
            decodedStr = decodedStr:sub(1, 600) .. "|cff888888... [truncated]|r"
        end
        local dirColor = direction == "IN" and "|cff9aff9a" or "|cff00ff00"
        local dirTag   = direction == "IN" and "[IN]" or "[OUT]"
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "%s %s%s|r | |cff00ccff%s|r | |cffffd700%s|r | %s",
            cDebugTag, dirColor, dirTag, channel or "?", targetOrSender or "?", decodedStr
        ))
        return
    end
    local dirColor = direction == "IN" and "|cff9aff9a" or "|cff00ff00"
    local dirTag   = direction == "IN" and "[IN]" or "[OUT]"
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "%s %s%s|r | |cff00ccff%s|r | |cffffd700%s|r | |cff888888<raw %d>|r |cffffffff%s|r",
        cDebugTag, dirColor, dirTag, channel or "?", targetOrSender or "?",
        #text, EscapeRaw(text, 200)
    ))
end

-- [OUT] Перехватываем исходящие ДО нарезки на куски
if AceCommLib then
    hooksecurefunc(AceCommLib, "SendCommMessage", function(self, prefix, text, distribution, target, prio)
        if not IsDebugOn() then return end
        if prefix ~= COMM_PREFIX then return end
        HandleCommMessage(text, "OUT", distribution, target)
    end)
end

-- [IN] Перехватываем входящие УЖЕ СОБРАННЫЕ через AceComm
if AceCommLib then
    AceCommLib:RegisterComm(COMM_PREFIX, function(prefix, text, distribution, sender)
        if not IsDebugOn() then return end
        HandleCommMessage(text, "IN", distribution, sender)
    end)
end

-- ============================================================================
-- INSPECT DEBUG
-- ============================================================================
local debugFrame = CreateFrame("Frame")
debugFrame:RegisterEvent("INSPECT_READY")

local lastInspectDebugTime = {}
local INSPECT_DEBUG_THROTTLE = 2

local function FindUnitByGUID(guid)
    if not guid then return nil end
    local candidates = {}
    for i = 1, 4  do candidates[#candidates + 1] = "party" .. i end
    for i = 1, 40 do candidates[#candidates + 1] = "raid" .. i end
    for i = 1, 40 do candidates[#candidates + 1] = "nameplate" .. i end
    candidates[#candidates + 1] = "target"
    candidates[#candidates + 1] = "focus"
    candidates[#candidates + 1] = "mouseover"
    candidates[#candidates + 1] = "player"
    if InspectFrame and InspectFrame.unit then
        candidates[#candidates + 1] = InspectFrame.unit
    end
    for _, u in ipairs(candidates) do
        if UnitExists(u) and ns.SafeGuid(UnitGUID(u)) == guid then
            return u
        end
    end
    return nil
end

debugFrame:SetScript("OnEvent", function(self, event, ...)
    if not IsDebugOn() then return end
    if event == "INSPECT_READY" then
        local guid = ns.SafeGuid(...)
        if not guid then return end
        local now = GetTime()
        local lastTime = lastInspectDebugTime[guid]
        if lastTime and (now - lastTime) < INSPECT_DEBUG_THROTTLE then return end
        lastInspectDebugTime[guid] = now

        local _, classToken, _, _, _, name, realm = GetPlayerInfoByGUID(guid)
        if not realm or realm == "" then realm = GetNormalizedRealmName() end
        local classUpper = classToken and classToken:upper() or "UNKNOWN"
        local cClass = GetClassColor(classUpper)

        local unit = FindUnitByGUID(guid)
        DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ff00[INSPECT_READY]|r", cDebugTag))

        local level = "??"
        if unit and UnitExists(unit) then
            local uLevel = UnitLevel(unit)
            if uLevel > 0 then level = uLevel end
        end
        local nameRealmLevel = string.format("%s-%s, %s-го уровня", name or "?", realm, level)
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s%s|r", cClass, nameRealmLevel))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s%s|r", cGuid, guid))

        local rating, played, won = GetInspectArenaData(5)
        if type(rating) == "number" and rating > 0 then
            local weeklyPlayed, weeklyWon = 0, 0
            if ns.GetArchiveStatsForGuid then
                local stats = ns.GetArchiveStatsForGuid(guid)
                if stats and stats.randomBG then
                    weeklyPlayed = stats.randomBG.weeklyPlayed or 0
                    weeklyWon    = stats.randomBG.weeklyWins or 0
                end
            end
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "  %sArena:|r %s%d|r/%d/%d/%d/%d",
                cLabel, cRating, rating, played or 0, won or 0, weeklyPlayed, weeklyWon
            ))
        else
            DEFAULT_CHAT_FRAME:AddMessage("  " .. cLabel .. "Arena:|r |cff888888<нет данных>|r")
        end

        local specResult = false
        if unit and GetInspectSpecialization then
            local spec = tonumber(GetInspectSpecialization(unit)) or 0
            if spec > 0 then specResult = true end
        end
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  %sSpec:|r %s", cLabel, specResult and "|cff00ff00true|r" or "|cffff0000false|r"
        ))

        local invResult = false
        if unit and GetInventoryItemID then
            for slot = 1, 17 do
                local itemID = GetInventoryItemID(unit, slot)
                if type(itemID) == "number" and itemID > 0 then
                    invResult = true
                    break
                end
            end
        end
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  %sInv:|r %s", cLabel, invResult and "|cff00ff00true|r" or "|cffff0000false|r"
        ))
    end
end)

-- ============================================================================
-- UI PRINT HELPERS
-- ============================================================================
local function PrintHeader(title)
    DEFAULT_CHAT_FRAME:AddMessage(cDebugTag .. " |cff00ff00=== " .. title .. " ===|r")
end
local function PrintLine(text)
    DEFAULT_CHAT_FRAME:AddMessage("  " .. text)
end

-- ============================================================================
-- DATABASE DUMPS
-- ============================================================================
local function PrintPlayerCache()
    local db = ns.SkirmishDB or {}
    local list = {}
    for guid, rec in pairs(db) do
        if type(guid) == "string" and type(rec) == "table" then
            list[#list + 1] = { guid = guid, rec = rec }
        end
    end
    PrintHeader("PlayerCache (" .. #list .. ")")
    if #list == 0 then return PrintLine("пусто") end
    table.sort(list, function(a, b) return (tonumber(a.rec.rating) or 0) > (tonumber(b.rec.rating) or 0) end)
    for _, e in ipairs(list) do
        local r = e.rec
        local cClass = GetClassColor(r.class)
        local cWinrate = (tonumber(r.winrate) or 0) >= 50 and "|cff00ff00" or "|cffff0000"
        local timeStr = r.lastUpdate and date("%d.%m.%y %H:%M", r.lastUpdate) or "?"
        local line = cClass .. (r.name or "?") .. cReset .. cSep .. " | " ..
                     cLabel .. "rating=" .. cRating .. (r.rating or 0) .. cReset .. " " ..
                     cLabel .. "best=" .. cRating .. (r.bestRating or 0) .. cReset .. cSep .. " | " ..
                     cLabel .. "played=" .. (r.played or 0) .. " " ..
                     cLabel .. "won=" .. (r.won or 0) .. " " ..
                     cLabel .. "wr=" .. cWinrate .. string.format("%.1f", tonumber(r.winrate) or 0) .. cReset .. cSep .. " | " ..
                     cClass .. (r.class or "?") .. cReset .. cSep .. " | " ..
                     cLabel .. "upd=" .. cTime .. timeStr .. cReset .. cSep .. " | " ..
                     cLabel .. "guid=" .. cGuid .. e.guid
        PrintLine(line)
    end
end

local function PrintTimestamps()
    local matchDB = ns.GetMatchDB and ns.GetMatchDB()
    if not matchDB or not next(matchDB) then
        PrintHeader("MatchData timestamps")
        return PrintLine("пусто")
    end
    local tsList = {}
    for ts in pairs(matchDB) do
        if type(ts) == "number" then tsList[#tsList + 1] = ts end
    end
    table.sort(tsList)
    PrintHeader("MatchData timestamps (" .. #tsList .. ")")
    for _, ts in ipairs(tsList) do
        local d = matchDB[ts]
        local kind = type(d) == "string" and "compressed" or "table"
        local winner = nil
        if ns.GetArchivedMatch then
            local dec = ns.GetArchivedMatch(ts)
            if type(dec) == "table" then winner = dec.winner end
        end
        local cFaction = winner == 0 and cFactionH or (winner == 1 and cFactionA or "|cffffffff")
        PrintLine(cFaction .. ts .. cReset .. " | " .. date("%d.%m.%y %H:%M", ts) .. " | " .. kind)
    end
end

local function GetDecodedMatch(ts)
    if not ts then return nil, "Укажите timestamp" end
    local matchDB = ns.GetMatchDB and ns.GetMatchDB()
    if not matchDB or not matchDB[ts] then return nil, ("Матч %d не найден"):format(ts) end
    local decoded = ns.GetArchivedMatch and ns.GetArchivedMatch(ts)
    if not decoded then return nil, ("Не удалось декодировать %d"):format(ts) end
    return decoded
end

local function ColorizeValue(v, key, parent)
    local t = type(v)
    if t == "string" then
        if key == "class" then return GetClassColor(v) .. v .. cReset
        elseif key == "name" then return GetClassColor(parent and parent.class) .. v .. cReset
        elseif key == "guid" then return cGuid .. v .. cReset
        else return "|cffffffff" .. v .. cReset end
    elseif t == "number" then
        if key == "faction" or key == "winner" then
            if v == 0 then return cFactionH .. v .. cReset end
            if v == 1 then return cFactionA .. v .. cReset end
        end
        return cRating .. v .. cReset
    end
    return tostring(v)
end

local function DumpColored(tbl, indent, maxDepth)
    indent = indent or "  "
    maxDepth = maxDepth or 6
    if maxDepth <= 0 then return PrintLine(indent .. cSep .. "... (max depth)" .. cReset) end
    for k, v in pairs(tbl) do
        local keyStr = type(k) == "string" and ('"' .. k .. '"') or tostring(k)
        keyStr = cLabel .. keyStr .. cReset
        if type(v) == "table" then
            DEFAULT_CHAT_FRAME:AddMessage(indent .. keyStr .. " = {")
            DumpColored(v, indent .. "  ", maxDepth - 1)
            DEFAULT_CHAT_FRAME:AddMessage(indent .. "}")
        else
            DEFAULT_CHAT_FRAME:AddMessage(indent .. keyStr .. " = " .. ColorizeValue(v, k, tbl))
        end
    end
end

local function PrintTimestampDataRaw(ts)
    local decoded, err = GetDecodedMatch(ts)
    if not decoded then return PrintLine(err) end
    PrintHeader("Match " .. ts .. " (raw) | " .. date("%d.%m.%y %H:%M", ts))
    DumpColored(decoded, "  ", 6)
end

local function PrintPlayerStyled(score)
    local cClass = GetClassColor(score.class)
    local cFaction = score.faction == 0 and cFactionH or (score.faction == 1 and cFactionA or "|cffffffff")
    local line = cClass .. (score.name or "?") .. cReset .. cSep .. " | " ..
                 cClass .. (score.class or "?") .. cReset .. cSep .. " | " ..
                 cFaction .. (score.faction or "?") .. cReset .. cSep .. " | " ..
                 cGuid .. (score.guid or "?") .. cReset
    if type(score.stats) == "table" then
        local parts = {}
        for _, stat in pairs(score.stats) do
            if type(stat) == "table" then
                parts[#parts + 1] = cLabel .. (stat.pvpStatID or "?") .. cReset .. "=" .. cRating .. (stat.pvpStatValue or "?") .. cReset
            end
        end
        if #parts > 0 then line = line .. " " .. cSep .. "| [" .. table.concat(parts, ", ") .. "]" end
    end
    PrintLine(line)
end

local function PrintTimestampDataStyled(ts)
    local decoded, err = GetDecodedMatch(ts)
    if not decoded then return PrintLine(err) end
    local mt = decoded.matchType or "unknown"
    local winnerStr = decoded.winner == 0 and (cFactionH .. "Horde (0)") or
                      (decoded.winner == 1 and (cFactionA .. "Alliance (1)") or tostring(decoded.winner))
    PrintHeader("Match " .. ts .. " (styled) | " .. date("%d.%m.%y %H:%M", ts))
    PrintLine("matchType = " .. mt)
    PrintLine("winner    = " .. winnerStr .. cReset)
    if type(decoded.scores) ~= "table" then return PrintLine("scores = " .. tostring(decoded.scores)) end
    local horde, alliance, other = {}, {}, {}
    for _, score in pairs(decoded.scores) do
        if type(score) == "table" then
            if score.faction == 0 then horde[#horde + 1] = score
            elseif score.faction == 1 then alliance[#alliance + 1] = score
            else other[#other + 1] = score end
        end
    end
    if mt == "random_bg" or mt == "wg_arena" then
        PrintLine(cFactionH .. "--- Horde (0): " .. #horde .. " ---" .. cReset)
        for _, s in ipairs(horde) do PrintPlayerStyled(s) end
        PrintLine(cFactionA .. "--- Alliance (1): " .. #alliance .. " ---" .. cReset)
        for _, s in ipairs(alliance) do PrintPlayerStyled(s) end
        if #other > 0 then
            PrintLine("--- Other: " .. #other .. " ---")
            for _, s in ipairs(other) do PrintPlayerStyled(s) end
        end
    else
        for _, score in pairs(decoded.scores) do
            if type(score) == "table" then PrintPlayerStyled(score) end
        end
    end
end

local function PrintSeasonReset()
    local regionDB = ns.GetRegionDB and ns.GetRegionDB()
    local ts = regionDB and tonumber(regionDB["SeasonReset"]) or 0
    PrintHeader("SeasonReset")
    if ts > 0 then
        PrintLine("UTC epoch: " .. ts)
        PrintLine("local    : " .. date("%d.%m.%Y %H:%M:%S", ts))
    else
        PrintLine("не установлен")
    end
end

local function PrintBlacklist()
    local regionDB = ns.GetRegionDB and ns.GetRegionDB()
    local bl = regionDB and regionDB["Blacklist"]
    PrintHeader("Blacklist")
    if type(bl) ~= "table" or not next(bl) then return PrintLine("пусто") end
    local list = {}
    for name in pairs(bl) do list[#list + 1] = name end
    table.sort(list)
    for _, name in ipairs(list) do PrintLine(cName .. name .. cReset) end
    PrintLine("Всего: " .. #list)
end

local function PrintWhitelist()
    local regionDB = ns.GetRegionDB and ns.GetRegionDB()
    local players = regionDB and regionDB["Whitelist"]
    PrintHeader("Whitelist")
    if type(players) ~= "table" or not next(players) then return PrintLine("пусто") end
    local list = {}
    for name, ts in pairs(players) do list[#list + 1] = { name = name, ts = tonumber(ts) or 0 } end
    table.sort(list, function(a, b) return a.ts > b.ts end)
    for _, e in ipairs(list) do
        local d = e.ts > 1000000000 and date("%d.%m.%y %H:%M", e.ts) or "неизвестно"
        PrintLine(cName .. e.name .. cReset .. cSep .. " | " .. cReset .. cTime .. d .. cReset)
    end
    PrintLine("Всего: " .. #list)
end

local function PrintSkirmishData()
    local regionDB = ns.GetRegionDB and ns.GetRegionDB()
    PrintHeader("SkirmishData (raw regionDB)")
    if not regionDB or regionDB["SkirmishData"] == nil then return PrintLine("пусто") end
    local raw = regionDB["SkirmishData"]
    PrintLine(type(raw) == "string" and ("blob (" .. #raw .. " bytes)") or ("тип: " .. type(raw)))
    local cnt = 0
    for _ in pairs(ns.SkirmishDB or {}) do cnt = cnt + 1 end
    PrintLine("ns.SkirmishDB записей: " .. cnt)
end

-- ============================================================================
-- SLASH COMMAND REGISTRY
-- ============================================================================
local slashCommands = {}
local function RegisterCommand(cmd, func, desc)
    slashCommands[cmd] = { func = func, desc = desc }
end

RegisterCommand("debug", function()
    local v = not IsDebugOn()
    PvP_20_RatingDB = PvP_20_RatingDB or {}
    PvP_20_RatingDB.Debug = v
    DEFAULT_CHAT_FRAME:AddMessage(cDebugTag .. " Debug " .. (v and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end, "toggle debug (вкл/выкл цветной вывод IN/OUT и инспекций)")

RegisterCommand("cache", PrintPlayerCache, "расширенный кеш игроков (SkirmishDB)")

RegisterCommand("ts", function(rest)
    if rest and rest ~= "" then PrintTimestampDataRaw(tonumber(rest)) else PrintTimestamps() end
end, "список таймстемпов или raw данные матча (/pvp20r ts <ts>)")

RegisterCommand("ts2", function(rest)
    if rest and rest ~= "" then PrintTimestampDataStyled(tonumber(rest)) else PrintLine("Укажите timestamp: /pvp20r ts2 <ts>") end
end, "данные матча styled, по фракциям (/pvp20r ts2 <ts>)")

RegisterCommand("season", PrintSeasonReset, "SeasonReset в локальном времени")
RegisterCommand("bl",     PrintBlacklist,  "Blacklist")
RegisterCommand("wl",     PrintWhitelist,  "Whitelist")
RegisterCommand("sd",     PrintSkirmishData, "SkirmishData (raw + счётчик)")

RegisterCommand("testwhisper", function()
    local myName = ns.FormatNameRealm and ns.FormatNameRealm(UnitName("player")) or (UnitName("player") .. "-" .. GetRealmName():gsub("%s", ""))
    DebugPrint("Тест шепота самому себе: " .. myName)
    if ns.GetRandomCacheBatch and ns.SendWhisper then
        local batch = ns.GetRandomCacheBatch()
        if batch then
            DebugPrint("Размер батча: " .. #batch .. " символов")
            local ok = ns.SendWhisper(batch, myName)
            DebugPrint("SendWhisper (batch) -> " .. tostring(ok))
        else
            DebugPrint("GetRandomCacheBatch вернул nil (кэш пуст?)")
        end
    else
        DebugPrint("Функции GetRandomCacheBatch или SendWhisper не найдены!")
    end
    if ns.SendHandshake then
        DebugPrint("Отправка комбинированного хендшейка (WHISPER)...")
        ns.SendHandshake("WHISPER", myName)
    end
end, "тестовый прогон шепота аддон-сообщений самому себе (кэш + хендшейк)")

RegisterCommand("tw", function() slashCommands["testwhisper"].func() end, "алиас для testwhisper")

-- ============================================================================
-- СИМУЛЯЦИЯ РЕЙТИНГА (хронологическая история)
-- Формат: /pvp20r sr <target> <match_type>
-- ============================================================================
RegisterCommand("sr", function(rest)
    local args = {}
    for word in rest:gmatch("%S+") do args[#args + 1] = word:lower() end
    if #args < 2 then
        PrintLine("Использование: /pvp20r sr <name|target|Name-Realm> <rbg|arena5v5|ss>")
        PrintLine("Примеры:")
        PrintLine("  /pvp20r sr name rbg")
        PrintLine("  /pvp20r sr target arena5v5")
        PrintLine("  /pvp20r sr Чугунплита-Гордунни ss")
        return
    end
    local targetType = args[1]
    local matchTypeArg = args[2]
    local matchTypeMap = {
        rbg = "random_bg",
        arena5v5 = "arena_5v5",
        ss = "solo_shuffle",
    }
    local matchType = matchTypeMap[matchTypeArg]
    if not matchType then
        PrintLine("Неизвестный тип матча: " .. matchTypeArg .. " (используйте: rbg, arena5v5, ss)")
        return
    end

    local guid = nil
    local playerName = nil
    if targetType == "name" then
        guid = UnitGUID("player")
        playerName = ns.FormatNameRealm(UnitName("player"))
    elseif targetType == "target" then
        if not UnitExists("target") or not UnitIsPlayer("target") then
            PrintLine("Таргет не выбран или не является игроком")
            return
        end
        guid = UnitGUID("target")
        local tName, tRealm = UnitName("target")
        playerName = ns.FormatNameRealm(tName, tRealm)
    else
        playerName = ns.FormatNameRealm(targetType)
        for g, rec in pairs(ns.SkirmishDB) do
            if type(rec) == "table" and rec.name == playerName then
                guid = g
                break
            end
        end
        if not guid then
            PrintLine("Игрок " .. playerName .. " не найден в кэше")
            return
        end
    end
    if not guid then
        PrintLine("GUID не найден")
        return
    end

    local classToken = nil
    if targetType == "target" and UnitExists("target") then
        _, classToken = UnitClass("target")
    elseif targetType == "name" then
        _, classToken = UnitClass("player")
    else
        local rec = ns.SkirmishDB[guid]
        if rec then classToken = rec.class end
    end
    local cClass = GetClassColor(classToken)

    local matchTypeNames = {
        random_bg = "Random Battlegrounds",
        arena_5v5 = "Wargame Arena 5v5",
        solo_shuffle = "Solo Shuffle",
    }
    PrintHeader("Rating Simulation: " .. matchTypeNames[matchType])
    PrintLine("Name: " .. cClass .. (playerName or "?") .. "|r")
    PrintLine("---")

    local currentRating = 0
    local weekStart = ns.GetWeekStart and ns.GetWeekStart() or 0
    local matchCount = 0
    local weeklyCount = 0
    local keys = ns.GetArchivedMatchKeys and ns.GetArchivedMatchKeys() or {}
    for _, ts in ipairs(keys) do
        local data = ns.GetArchivedMatch and ns.GetArchivedMatch(ts)
        if data and data.matchType == matchType and data.winner and (data.winner == 0 or data.winner == 1) then
            local playerScore = nil
            if type(data.scores) == "table" then
                if data.scores[guid] then
                    playerScore = data.scores[guid]
                else
                    for key, score in pairs(data.scores) do
                        if type(score) == "table" and score.guid == guid then
                            playerScore = score
                            break
                        end
                    end
                end
                if not playerScore and playerName then
                    for key, score in pairs(data.scores) do
                        if type(score) == "table" and score.name == playerName then
                            playerScore = score
                            break
                        end
                    end
                end
            end
            if playerScore then
                local isWin = (playerScore.faction == data.winner)
                local isWeekly = ts >= weekStart
                local enemySum, enemyN = 0, 0
                for key, score in pairs(data.scores) do
                    if type(score) == "table" and score.faction ~= playerScore.faction and score.guid then
                        local enemyRec = ns.SkirmishDB[score.guid]
                        if enemyRec and (tonumber(enemyRec.rating) or 0) > 0 then
                            enemySum = enemySum + (tonumber(enemyRec.rating) or 0)
                            enemyN = enemyN + 1
                        end
                    end
                end
                local enemyAvg = enemyN > 0 and math.floor(enemySum / enemyN + 0.5) or 0
                local delta = 0
                if matchType == "random_bg" or matchType == "arena_5v5" then
                    if ns.CalculateBGRatingDelta then
                        delta = ns.CalculateBGRatingDelta(currentRating, enemyAvg, isWin)
                    end
                elseif matchType == "solo_shuffle" then
                    if ns.GetShuffleRoundsForGuid then
                        local rw, rl = ns.GetShuffleRoundsForGuid(data, guid, playerName)
                        if rw then delta = (rw * 500) - (rl * 50) end
                    end
                end
                local oldRating = currentRating
                currentRating = math.max(currentRating + delta, 0)
                matchCount = matchCount + 1
                if isWeekly then weeklyCount = weeklyCount + 1 end
                local deltaStr = delta > 0 and ("+" .. delta) or tostring(delta)
                local deltaColor = delta > 0 and "|cff00ff00" or (delta < 0 and "|cffff0000" or "|cffffffff")
                local winStr = isWin and "|cff00ff00WIN|r" or "|cffff0000LOSS|r"
                local weeklyStr = isWeekly and "|cff00ffffW|r" or ""
                PrintLine(string.format(
                    "%s | %s%d|r | %d | %s%s|r | %s %s",
                    ts, cRating, oldRating, enemyAvg, deltaColor, deltaStr, winStr, weeklyStr
                ))
            end
        end
    end
    PrintLine("---")
    PrintLine("Final Rating: " .. cRating .. currentRating .. "|r")
    PrintLine("Total Matches: " .. matchCount .. (weeklyCount > 0 and " (weekly: " .. weeklyCount .. ")" or ""))
end, "симуляция рейтинга (/pvp20r sr <name|target|Name-Realm> <rbg|arena5v5|ss>)")

RegisterCommand("dev", function()
    if ns.ToggleQueueDev then ns.ToggleQueueDev() end
end, "окно очереди и варгейма: кто в реге, лидеры, журнал шагов")

RegisterCommand("help", function()
    PrintHeader("PvP20R Debug Commands")
    local keys = {}
    for cmd in pairs(slashCommands) do keys[#keys + 1] = cmd end
    table.sort(keys)
    for _, cmd in ipairs(keys) do
        PrintLine("|cff00ffff/pvp20r " .. cmd .. "|r — " .. slashCommands[cmd].desc)
    end
end, "эта справка")

-- Dispatcher
SLASH_PVP20RDEBUG1 = "/pvp20r"
SLASH_PVP20RDEBUG2 = "/pvp20rdebug"
SlashCmdList["PVP20RDEBUG"] = function(args)
    args = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = args:match("^(%S*)%s*(.*)$")
    cmd = (cmd or ""):lower()
    local tsNum = tonumber(cmd)
    if tsNum and tsNum > 1000000000 then
        PrintTimestampDataRaw(tsNum)
        return
    end
    local command = slashCommands[cmd]
    if command then
        command.func(rest)
    else
        PrintLine("Неизвестная команда: " .. (cmd ~= "" and cmd or "пусто"))
        slashCommands["help"].func()
    end
end
