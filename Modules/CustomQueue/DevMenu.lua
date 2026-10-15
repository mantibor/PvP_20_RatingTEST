local addonName, ns = ...

-- ============================================================================
-- DEV MENU: /pvp20r dev
-- Кто в очереди, кто хост и лидеры, на каком шаге встал варгейм.
-- Журнал пишет сообщения аддона, системные ответы игры и блокировки
-- защищённых функций; переживает /reload (PvP20RDevLog).
-- ============================================================================
local MAX_LOG = 400
local QUEUE_TOKENS = { Q = true, G = true, H = true, WG = true, N = true } -- N — пакеты списков ников (NamePack.lua)

local frame, textBox, refreshQueued

local function Plain(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return nil end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function IsQueueMessage(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return false end
    local token = text:match("^(%u+)_")
    return token and QUEUE_TOKENS[token]
end

local Refresh

local function Log(text)
    text = Plain(text)
    if not text then return end
    PvP20RDevLog = PvP20RDevLog or {}
    local log = PvP20RDevLog
    log[#log + 1] = date("%H:%M:%S") .. "  " .. text
    while #log > MAX_LOG do table.remove(log, 1) end
    if frame and frame:IsShown() and not refreshQueued then
        refreshQueued = true
        C_Timer.After(0.3, function() refreshQueued = false; Refresh() end)
    end
end
ns.QLog = Log

-- ============================================================================
-- CAPTURE
-- ============================================================================
hooksecurefunc(DEFAULT_CHAT_FRAME, "AddMessage", function(_, msg)
    if type(msg) == "string" and not (issecretvalue and issecretvalue(msg))
    and msg:find("[PvP20R Queue]", 1, true) then
        Log(msg)
    end
end)

-- Шёпот уходит каждому из вайтлиста: одна строка на сообщение, а не на адресата.
local lastWhisper, lastWhisperAt = nil, 0
hooksecurefunc(ns, "SendAddonMessage", function(channel, target, payload)
    if not IsQueueMessage(payload) then return end
    if channel == "WHISPER" then
        if payload == lastWhisper and GetTime() - lastWhisperAt < 1 then return end
        lastWhisper, lastWhisperAt = payload, GetTime()
        Log(">> шёпот вайтлисту: " .. payload)
    else
        Log(">> " .. tostring(channel) .. ": " .. payload)
    end
end)

local lastBattlefield, lastGroupSize
local notFoundCount = 0
local notFoundPattern = ERR_CHAT_PLAYER_NOT_FOUND_S
    and "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", ".+") .. "$"

local function BattlefieldSummary()
    local parts = {}
    for i = 1, GetMaxBattlefieldID() do
        local status, mapName = GetBattlefieldStatus(i)
        if status and status ~= "none" then parts[#parts + 1] = i .. ":" .. status .. " " .. tostring(mapName) end
    end
    return #parts > 0 and table.concat(parts, ", ") or "нет"
end

local ev = CreateFrame("Frame")
for _, e in ipairs({
    "CHAT_MSG_ADDON", "CHAT_MSG_SYSTEM", "UI_ERROR_MESSAGE",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
    "WARGAME_REQUESTED", "UPDATE_BATTLEFIELD_STATUS",
    "GROUP_ROSTER_UPDATE", "PARTY_INVITE_REQUEST",
}) do ev:RegisterEvent(e) end

ev:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender = ...
        if prefix == ns.PREFIX and IsQueueMessage(text) then
            Log("<< " .. tostring(sender) .. " [" .. tostring(channel) .. "]: " .. ns.UnpackQueueKeys(text))
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local text = Plain((...))
        -- «Персонаж не найден» — шёпот офлайн-людям из вайтлиста на каждый
        -- Q_STAT, десятки строк в минуту. Считаем, а не пишем.
        if text and notFoundPattern and text:match(notFoundPattern) then
            notFoundCount = notFoundCount + 1
        elseif text then
            Log("игра: " .. text)
        end
    elseif event == "UI_ERROR_MESSAGE" then
        local _, text = ...
        text = Plain(text)
        if text then Log("ошибка игры: " .. text) end
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local who, func = ...
        Log("!! " .. event .. ": " .. tostring(who) .. " -> " .. tostring(func))
    elseif event == "WARGAME_REQUESTED" then
        local challenger, area, timeout = ...
        Log("вызов на варгейм от " .. tostring(Plain(challenger) or challenger) .. ", арена " .. tostring(area) .. ", " .. tostring(timeout) .. " с")
    elseif event == "UPDATE_BATTLEFIELD_STATUS" then
        local s = BattlefieldSummary()
        if s ~= lastBattlefield then
            lastBattlefield = s
            Log("поля боя: " .. s)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        local n = GetNumGroupMembers(1) or 0
        if n ~= lastGroupSize then
            lastGroupSize = n
            Log("группа: " .. n .. " чел." .. (UnitIsGroupLeader("player") and ", я лидер" or ""))
        end
    elseif event == "PARTY_INVITE_REQUEST" then
        local name, _, _, _, _, realm = ...
        Log("приглашение в группу от " .. tostring(ns.FormatNameRealm(name, realm)))
    end
end)

-- ============================================================================
-- STATE TEXT
-- ============================================================================
local function Ago(serverTime)
    if type(serverTime) ~= "number" then return "?" end
    local s = math.max(0, GetServerTime() - serverTime)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function YesNo(v) return v and "да" or "нет" end

local function BuildState()
    local out = {}
    local function add(s) out[#out + 1] = s end
    local myName = ns.FormatNameRealm(UnitName("player"))
    local sm = ns.StateMachine
    add("Я: " .. tostring(myName) .. "   группа: " .. (GetNumGroupMembers(1) or 0)
        .. (UnitIsGroupLeader("player") and " (лидер)" or ""))
    add("Шёпот офлайн-людям из вайтлиста («не найден»): " .. notFoundCount .. " раз с загрузки")
    add("Поля боя: " .. BattlefieldSummary()
        .. "   очередь приостановлена: " .. YesNo(sm and sm.IsQueueSuspended()))
    add("")

    local rosters = sm and sm.GetQueueRoster() or {}
    local anyQueue = false
    for queueKey, bucket in pairs(rosters) do
        if type(bucket) == "table" and next(bucket) then
            anyQueue = true
            local names, host, hostTime = {}, nil, math.huge
            for name, data in pairs(bucket) do
                names[#names + 1] = name
                local canHost = not data.premade or data.premade == name
                if canHost and type(data.time) == "number"
                and (data.time < hostTime or (data.time == hostTime and name < host)) then
                    host, hostTime = name, data.time
                end
            end
            table.sort(names, function(a, b) return (bucket[a].time or 0) < (bucket[b].time or 0) end)
            local need = sm.GetConstraints(queueKey).totalPlayers
            add(("== Очередь %s: %d/%d   хост: %s"):format(queueKey, #names, need, tostring(host)))
            for _, name in ipairs(names) do
                local d = bucket[name]
                local isFriend = name == myName and "я" or YesNo(ns.FindBNetFriendByNameRealm(name))
                local build = name == myName and ns.QUEUE_BUILD or d.build or "СТАРАЯ"
                add(("  %-28s роли %-6s подписка %-3s невидимка %-3s ждёт %s  BNet-друг: %s  версия: %s%s"):format(
                    name, d.roles or "-", YesNo(d.subscribed), YesNo(d.appearOffline),
                    Ago(d.time), isFriend, build, d.premade and ("  премейд " .. d.premade) or ""))
            end
            add("")
        end
    end
    if not anyQueue then add("Очереди пусты (ни одного Q_STAT не слышно)."); add("") end

    local wf = ns.WargameFlow and ns.WargameFlow.GetDebugState and ns.WargameFlow.GetDebugState()
    if wf then
        add("== Варгейм")
        local r = wf.roster or (wf.pending and wf.pending.roster)
        if r then
            add("  Команда A: " .. table.concat(r.teamA or {}, ", "))
            add("  Команда B: " .. table.concat(r.teamB or {}, ", "))
            add("  Вызывает: " .. tostring(r.sender) .. "  ->  принимает: " .. tostring(r.receiver)
                .. "   друзья по BNet (у меня): " .. YesNo(r.receiver and r.receiver ~= myName and ns.FindBNetFriendByNameRealm(r.receiver)))
        else
            add("  Состава нет.")
        end
        local accepted = 0
        for _ in pairs(wf.accepted or {}) do accepted = accepted + 1 end
        add("  Окно готовности открыто: " .. YesNo(wf.readyPause) .. "   нажали «Войти»: " .. accepted)
        if wf.pending then
            add(("  Собираю свою группу: %d/%d, до отмены %d с"):format(
                GetNumGroupMembers(1) or 0, wf.pending.teamSize or 0,
                math.max(0, math.floor((wf.pending.deadline or 0) - GetTime()))))
        else
            add("  Сбор своей группы: не идёт")
        end
        add("  Вторая команда сообщила, что собрана: " .. YesNo(wf.opponentGroupReady))
        add("  Жду вызов от: " .. tostring(wf.expectedFrom)
            .. (wf.acceptLeft > 0 and ("  (автопринятие ещё " .. math.floor(wf.acceptLeft) .. " с)") or ""))
        add("  Жду приглашение от лидера: " .. tostring(wf.myTeamLeader))
        add("  Арена шлётся как: " .. ((PvP_20_RatingDB and PvP_20_RatingDB.wgMapByID) and "ID" or "название"))
        local assigned = ns.WargameFlow.GetAssignedRole and ns.WargameFlow.GetAssignedRole()
        local plan = ns.WargameFlow.SpecPlan and ns.WargameFlow.SpecPlan()
        add("  Роль от хоста: " .. tostring(assigned or "нет (вне состава)") .. "   специализация: "
            .. (not plan and "подходит" or ("сменит на «" .. tostring(select(2, C_SpecializationInfo.GetSpecializationInfo(plan))) .. "»")))
    end
    return table.concat(out, "\n")
end

Refresh = function()
    if not frame or not frame:IsShown() then return end
    local log = PvP20RDevLog or {}
    local lines = {}
    for i = #log, 1, -1 do lines[#lines + 1] = log[i] end
    textBox:SetText(BuildState() .. "\n\n== Журнал (новые сверху)\n" .. table.concat(lines, "\n"))
end

-- ============================================================================
-- WINDOW
-- ============================================================================
local function MakeButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function CreateDevFrame()
    frame = CreateFrame("Frame", "PvP20RQueueDevFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(820, 560)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    tinsert(UISpecialFrames, frame:GetName())
    frame.TitleText:SetText("PvP20R — очередь и варгейм (dev)")

    local refresh = MakeButton(frame, "Обновить", 100, function() Refresh() end)
    refresh:SetPoint("TOPLEFT", 12, -30)
    local clear = MakeButton(frame, "Очистить журнал", 130, function() PvP20RDevLog = {}; Refresh() end)
    clear:SetPoint("LEFT", refresh, "RIGHT", 6, 0)

    local byName = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    byName:SetPoint("LEFT", clear, "RIGHT", 10, 0)
    local byNameLabel = byName.text or byName.Text
    byNameLabel:SetText("Арену слать числом (ID), старый способ")
    byName:SetScript("OnShow", function(self) self:SetChecked(PvP_20_RatingDB and PvP_20_RatingDB.wgMapByID) end)
    byName:SetScript("OnClick", function(self)
        PvP_20_RatingDB = PvP_20_RatingDB or {}
        PvP_20_RatingDB.wgMapByID = self:GetChecked() and true or nil
        Log("формат арены: " .. (PvP_20_RatingDB.wgMapByID and "ID" or "название"))
    end)

    -- Ручной вызов по клику: проверяет формат строки и то, пускает ли игра
    -- StartWarGameByName от аддона вообще. Аддон занял /wargame, так что
    -- штатной командой это теперь не проверить.
    local testBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    testBox:SetSize(300, 20)
    testBox:SetPoint("TOPLEFT", refresh, "BOTTOMLEFT", 6, -8)
    testBox:SetAutoFocus(false)
    testBox:SetText("BattleTag#1234 809")
    local test = MakeButton(frame, "Тест StartWarGameByName", 190, function()
        local arg = testBox:GetText()
        local ok, err = pcall(StartWarGameByName, arg)
        Log("тест StartWarGameByName(\"" .. arg .. "\"): " .. (ok and "вызов прошёл, ждём ответ игры" or ("ошибка " .. tostring(err))))
    end)
    test:SetPoint("LEFT", testBox, "RIGHT", 8, 0)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -86)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    textBox = CreateFrame("EditBox", nil, scroll)
    textBox:SetMultiLine(true)
    textBox:SetAutoFocus(false)
    textBox:SetFontObject(ChatFontNormal)
    textBox:SetWidth(760)
    textBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(textBox)

    frame:SetScript("OnShow", Refresh)
end

function ns.ToggleQueueDev()
    if not frame then CreateDevFrame() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

-- Короткие команды: /pvp20r dev неудобно набирать и забывается.
SLASH_PVP20RQDEV1, SLASH_PVP20RQDEV2 = "/dev", "/qdev"
SlashCmdList["PVP20RQDEV"] = ns.ToggleQueueDev
