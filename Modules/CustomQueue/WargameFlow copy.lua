local addonName, ns = ...

-- ============================================================================
-- STATE
-- ============================================================================
local wgReadyPause = false
local currentRoster = nil
local wgReadyAccepted = {}
local wgReadyDeclined = {}
local wgResultTimer = nil
local wgCustomButton = nil
local expectedWargameFrom = nil
local autoAcceptWargameUntil = 0
local pendingWargameRequest = nil
local opponentGroupReady = false
local TrySendWargame
local setupSent = {}
local lastSetupNotice = {}
local myTeamLeader = nil
local autoAcceptInviteUntil = 0
local function SendQueue(payload)
    if ns.StateMachine and ns.StateMachine.SendQueueMessage then
        ns.StateMachine.SendQueueMessage(payload, "ALERT")
    end
end

local function Announce(text)
    print("|cff00ff00[PvP20R Queue]|r " .. text)
    SendQueue("Q_NOTE," .. (text:gsub(",", ";")))
end

-- ============================================================================
-- UTILITIES (зависят от StateMachine)
-- ============================================================================
local function GetQueueRoster()
    return ns.StateMachine and ns.StateMachine.GetQueueRoster() or {}
end

local function GetQueueBucket(queueKey)
    local bucket = queueKey and GetQueueRoster()[queueKey]
    return type(bucket) == "table" and bucket or {}
end

local function GetConstraints(queueKey)
    return ns.StateMachine and ns.StateMachine.GetConstraints(queueKey)
end

local function IsQueueSuspended()
    return ns.StateMachine and ns.StateMachine.IsQueueSuspended()
end

local function LeaveQueueByKey(key, keepWargame)
    return ns.StateMachine and ns.StateMachine.LeaveQueueByKey(key, keepWargame)
end

local function RefreshFrames()
    if QueueStatusFrame and QueueStatusFrame.Update then
        QueueStatusFrame:Update()
    end
end

local function BNetOnline(nameRealm)
    if not nameRealm then return false end
    local acc = ns.FindBNetFriendByNameRealm(nameRealm)
    if not acc or not acc.gameAccountInfo then return false end
    return acc.gameAccountInfo.isOnline and acc.gameAccountInfo.clientProgram == BNET_CLIENT_WOW
end

-- ============================================================================
-- WARGAME STATE MANAGEMENT
-- ============================================================================
local function ResetWargameRequest()
    expectedWargameFrom = nil
    autoAcceptWargameUntil = 0
    pendingWargameRequest = nil
    opponentGroupReady = false
end

local function ResetWargameState()
    wgReadyPause = false
    currentRoster = nil
    wgReadyAccepted = {}
    wgReadyDeclined = {}
    ResetWargameRequest()
    if wgResultTimer then
        wgResultTimer:Cancel()
        wgResultTimer = nil
    end
    RefreshFrames()
end

local function IsInRoster(nameRealm)
    if not currentRoster or not currentRoster.set or not nameRealm then return false end
    return currentRoster.set[nameRealm] == true
end

local function GetMyTeam()
    if not currentRoster then return nil, nil, false end
    local myName = ns.FormatNameRealm(UnitName("player"))
    for _, team in ipairs({ currentRoster.teamA, currentRoster.teamB }) do
        for idx, name in ipairs(team) do
            if name == myName then return team, myName, (idx == 1) end
        end
    end
    return nil, myName, false
end

local function GetReadyCount()
    local n = 0
    for _ in pairs(wgReadyAccepted) do n = n + 1 end
    return n
end

-- ============================================================================
-- TEAM BUILDING & HOST LOGIC
-- ============================================================================
local function CheckTeam(team, constraints, queueKey)
    local healers, subscribers = 0, 0
    local roster = GetQueueBucket(queueKey)
    for _, name in ipairs(team) do
        local data = roster[name]
        if not data then return false end
        if data.roles and data.roles:find("H") then healers = healers + 1 end
        if data.subscribed then subscribers = subscribers + 1 end
    end
    if healers ~= constraints.healersPerTeam then return false end
    if subscribers < constraints.minSubscribersPerTeam then return false end
    return true
end

local function GenerateCombinations(n, k)
    local result, combo = {}, {}
    local function rec(start, depth)
        if depth == k then
            local copy = {}
            for i = 1, k do copy[i] = combo[i] end
            result[#result + 1] = copy
            return
        end
        for i = start, n - (k - depth) + 1 do
            combo[depth + 1] = i
            rec(i + 1, depth + 1)
        end
    end
    rec(1, 0)
    return result
end

-- Объявлена до AssignLeaders: ниже по файлу local ещё не виден,
-- и запасной выбор лидеров падал на вызове nil.
local function PickLeader(team, queueKey)
    local best, bestTime = nil, math.huge
    local roster = GetQueueBucket(queueKey)
    for _, name in ipairs(team) do
        local data = roster[name]
        if data and data.subscribed and not data.appearOffline then
            local t = data.time or math.huge
            if t < bestTime or (t == bestTime and (not best or name < best)) then
                bestTime = t
                best = name
            end
        end
    end
    return best
end

local function PickFriendLeaders(queueKey, teamA, teamB)
    local bucket = GetQueueBucket(queueKey)
    local function dataOf(name)
        return bucket[name]
    end
    local function canLead(name)
        local data = dataOf(name)
        return data and data.subscribed
    end
    local bestSender, bestReceiver, bestTime
    local function consider(sender, receiver)
        if not canLead(sender) or not canLead(receiver) then return end
        local recv = dataOf(receiver)
        if not recv or recv.appearOffline then return end
        local who = ns.StateMachine and ns.StateMachine.QueueFriendSender and ns.StateMachine.QueueFriendSender(queueKey, sender, receiver)
        if who ~= sender then return end
        local t = dataOf(sender).time or math.huge
        if not bestSender or t < bestTime or (t == bestTime and sender < bestSender) then
            bestSender, bestReceiver, bestTime = sender, receiver, t
        end
    end
    for _, a in ipairs(teamA) do
        for _, b in ipairs(teamB) do
            consider(a, b)
            consider(b, a)
        end
    end
    return bestSender, bestReceiver
end

local function AssignLeaders(queueKey, teamA, teamB)
    local sender, receiver = PickFriendLeaders(queueKey, teamA, teamB)
    if sender and receiver then return sender, receiver, true end
    sender = PickLeader(teamA, queueKey) or teamA[1]
    receiver = PickLeader(teamB, queueKey) or teamB[1]
    if not sender or not receiver or sender == receiver then return nil end
    return sender, receiver, false
end

local function FindSetup(players, constraints, queueKey)
    local n = #players
    if n ~= constraints.totalPlayers then return nil end
    local fallback
    for _, c in ipairs(GenerateCombinations(n, constraints.teamSize)) do
        local inA = {}
        local teamA, teamB = {}, {}
        for _, idx in ipairs(c) do
            inA[idx] = true
            teamA[#teamA + 1] = players[idx]
        end
        for i = 1, n do
            if not inA[i] then teamB[#teamB + 1] = players[i] end
        end
        if CheckTeam(teamA, constraints, queueKey) and CheckTeam(teamB, constraints, queueKey) then
            local sender, receiver, friends = AssignLeaders(queueKey, teamA, teamB)
            if sender and receiver then
                local setup = { teamA, teamB, sender = sender, receiver = receiver, friends = friends }
                if friends then return setup end
                fallback = fallback or setup
            end
        end
    end
    if fallback then return fallback end
    local teamA, teamB = {}, {}
    for i, name in ipairs(players) do
        if i <= constraints.teamSize then teamA[#teamA + 1] = name else teamB[#teamB + 1] = name end
    end
    local sender, receiver, friends = AssignLeaders(queueKey, teamA, teamB)
    if not sender then sender, receiver = teamA[1], teamB[1] end
    return { teamA, teamB, sender = sender, receiver = receiver, friends = friends, relaxed = true }
end

local function PlaceLeaderFirst(team, leader)
    for i, name in ipairs(team) do
        if name == leader then
            team[1], team[i] = team[i], team[1]
            return
        end
    end
end

-- ============================================================================
-- WARGAME COMMUNICATION
-- ============================================================================
local function SendReady()
    if not currentRoster then return end
    SendQueue("WG_READY")
end

local function SendReadyFail()
    if not currentRoster then return end
    SendQueue("WG_READY_FAIL")
end

local function PickArenaMap()
    local maps = {}
    if ns.MAPS then
        for _, m in ipairs(ns.MAPS) do
            if m and m.pvpType == 4 and not m.isRandom and m.id then maps[#maps + 1] = m end
        end
    end
    if #maps == 0 then return nil end
    return maps[math.random(#maps)]
end

local function CanSendWargameRequest(roster)
    if not roster then return false end
    local constraints = GetConstraints(roster.queueKey)
    local myName = ns.FormatNameRealm(UnitName("player"))
    local iAmLeaderA = roster.teamA[1] == myName
    local iAmLeaderB = roster.teamB[1] == myName
    if not iAmLeaderA and not iAmLeaderB then return false end
    local groupSize = GetNumGroupMembers(1) or 0
    if groupSize < constraints.teamSize then return false end
    if IsInGroup(2) then return false end
    if UnitIsDeadOrGhost("player") then return false end
    return true
end

local function WargameFail(reason, tellOthers)
    print("|cffff0000[PvP20R Queue]|r Варгейм не отправлен: " .. reason)
    if tellOthers then SendQueue("WG_READY_FAIL") end
    ResetWargameRequest()
end

local function SendWargameRequest()
    if not currentRoster then return end
    local sender = currentRoster.sender or currentRoster.teamA[1]
    local receiver = currentRoster.receiver or currentRoster.teamB[1]
    if not sender or not receiver then
        WargameFail("не выбраны лидеры", false)
        return
    end
    local myName = ns.FormatNameRealm(UnitName("player"))
    if sender ~= myName and receiver ~= myName then return end
    if not BNetOnline(receiver) then
        WargameFail("принимающий лидер не в сети Battle.net: " .. receiver, true)
        return
    end
    autoAcceptWargameUntil = GetTime() + 45
    if receiver == myName then
        expectedWargameFrom = sender
        print("|cff00ff00[PvP20R Queue]|r Ждём вызов на варгейм от " .. sender .. ". Примем автоматически.")
        return
    end
    if not CanSendWargameRequest(currentRoster) then
        local n = GetNumGroupMembers(1) or 0
        WargameFail("наша группа ещё не собрана (" .. n .. ")", false)
        return
    end
    local friend = ns.FindBNetFriendByNameRealm(receiver)
    if not friend then
        WargameFail(sender .. " не дружит в Battle.net с " .. receiver, true)
        return
    end
    local accountName = friend.accountName or friend.battleTag
    if not accountName then
        WargameFail("у друга нет BattleTag", true)
        return
    end
    local map = PickArenaMap()
    if not map then
        WargameFail("нет карты арены", true)
        return
    end
    -- Очередь «Суматоха» запускает варгейм в режиме Суматохи: у Blizzard для
    -- этого своя функция, ею работает команда /wargame для Solo Shuffle
    -- (Blizzard_ChatFrameBase/Mainline/SlashCommandsOverrides.lua).
    -- StartWarGameByName давала обычную арену 3×3 (проверено в игре 08.10).
    local isShuffle = currentRoster.queueKey == "SOLO_SHUFFLE"
    local startFn = isShuffle and StartSoloShuffleWarGameByName or StartWarGameByName
    if not startFn then
        WargameFail((isShuffle and "StartSoloShuffleWarGameByName" or "StartWarGameByName") .. " недоступна на этом клиенте", true)
        return
    end
    local mapArg = ns.WargameMapArg(map)
    local ok, err = pcall(startFn, accountName .. " " .. mapArg)
    if ok then
        print("|cff00ff00[PvP20R Queue]|r Запрос на варгейм" .. (isShuffle and " (Суматоха)" or "") .. " отправлен: " .. receiver .. ", карта " .. mapArg)
    else
        WargameFail("игра не дала отправить запрос (" .. tostring(err) .. ")", true)
    end
end

-- ============================================================================
-- AUTO-ACCEPT LOGIC
-- ============================================================================
-- Окно готовности аддон рисует на PVPReadyDialog Blizzard и прячет настоящую
-- «Войти». PVPReadyDialog_Display её обратно не показывает (сверено с
-- Blizzard_GroupFinder/Mainline/PVPHelper.lua) — на настоящем входе на арену
-- кнопки не было.
local function RestoreEnterButton()
    if wgCustomButton then wgCustomButton:Hide() end
    if PVPReadyDialog then
        if PVPReadyDialog.enterButton then PVPReadyDialog.enterButton:Show() end
        if PVPReadyDialog.EnterBattleButton then PVPReadyDialog.EnterBattleButton:Show() end
    end
end

-- Вход на арену игра пускает только по клику игрока: AcceptBattlefieldPort
-- из обработчика события дал ADDON_ACTION_FORBIDDEN (проверено в игре 20:22).
-- Поэтому не жмём сами — возвращаем кнопку и зовём игрока.
local function AutoAcceptWargame()
    for i = 1, GetMaxBattlefieldID() do
        if GetBattlefieldStatus(i) == "confirm" then
            RestoreEnterButton()
            if GetTime() <= autoAcceptWargameUntil then
                ResetWargameRequest()
                PlaySound(SOUNDKIT.READY_CHECK)
                print("|cff00ff00[PvP20R Queue]|r Арена готова — нажмите «Войти».")
            end
            return
        end
    end
end

local function OnPartyInvite(inviterName, inviterRealm)
    if not myTeamLeader then return false end
    if GetTime() > autoAcceptInviteUntil then
        myTeamLeader = nil
        autoAcceptInviteUntil = 0
        return false
    end
    if not inviterName or inviterName == "" then return false end
    local inviterNameRealm = ns.FormatNameRealm(inviterName, inviterRealm)
    if not inviterNameRealm or inviterNameRealm ~= myTeamLeader then return false end
    if C_PartyInfo and C_PartyInfo.AcceptInvite then
        C_PartyInfo.AcceptInvite()
    elseif AcceptGroup then
        AcceptGroup()
    end
    if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
    myTeamLeader = nil
    autoAcceptInviteUntil = 0
    return true
end

-- ============================================================================
-- LEAVE QUEUES FOR WARGAME
-- ============================================================================
local function LeaveQueues()
    for i = 1, NUM_LE_LFG_CATEGORYS do
        if GetLFGMode(i) then
            LeaveLFG(i)
        end
    end

    if C_LFGList then
        if C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo() then
            C_LFGList.RemoveListing()
        end
        if C_LFGList.GetApplications and C_LFGList.GetApplicationInfo and C_LFGList.CancelApplication then
            for _, appID in ipairs(C_LFGList.GetApplications() or {}) do
                local _, status = C_LFGList.GetApplicationInfo(appID)
                if status == "applied" or status == "invited" then C_LFGList.CancelApplication(appID) end
            end
        end
    end

    for i = 1, GetMaxBattlefieldID() do
        if GetBattlefieldStatus(i) ~= "none" then
            BattlefieldMgrExitRequest(i)
        end
    end

    for i = 1, MAX_WORLD_PVP_QUEUES do
        local status, _, queueID = GetWorldPVPQueueStatus(i)
        if status and status ~= "none" and queueID then BattlefieldMgrExitRequest(queueID) end
    end

    if C_PetBattles and C_PetBattles.GetPVPMatchmakingInfo and C_PetBattles.StopPVPMatchmaking then
        local status = C_PetBattles.GetPVPMatchmakingInfo()
        if status and status ~= "" then
            C_PetBattles.StopPVPMatchmaking()
        end
    end
end

local function ClearMyQueueForWargame()
    if ns.StateMachine then
        LeaveQueueByKey(nil, true)
    end
end

local function NameInMyGroup(nameRealm)
    if not nameRealm then return false end
    if ns.FormatNameRealm(UnitName("player")) == nameRealm then return true end
    if not IsInGroup() then return false end
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) and ns.FormatNameRealm(UnitName(unit)) == nameRealm then
            return true
        end
    end
    return false
end

local function InviteMissing(team, myName)
    if not team or not C_PartyInfo or not C_PartyInfo.InviteUnit then return end
    for _, name in ipairs(team) do
        if name ~= myName and not NameInMyGroup(name) then
            C_PartyInfo.InviteUnit(name)
        end
    end
end

-- LeaveParty срабатывает не сразу. Пока лидер ещё в старой группе,
-- инвайт отвечает «уже состоит в группе». Ждём выход, потом зовём тех, кого ещё нет.
local function BeginTeamForm(team, myName, savedRoster)
    local constraints = GetConstraints(savedRoster.queueKey)
    local teamSize = (constraints and constraints.teamSize) or #team
    pendingWargameRequest = {
        roster = savedRoster,
        teamSize = teamSize,
        deadline = GetTime() + 45,
    }
    local tries = 0
    local function tick()
        if not pendingWargameRequest or pendingWargameRequest.roster ~= savedRoster then return end
        if GetTime() > pendingWargameRequest.deadline then return end
        tries = tries + 1
        if IsInGroup() and tries <= 8 then
            C_Timer.After(0.5, tick)
            return
        end
        InviteMissing(team, myName)
        local n = GetNumGroupMembers(1) or 0
        if n < teamSize and tries < 16 then
            C_Timer.After(1.5, tick)
        end
    end
    C_Timer.After(0.5, tick)
    C_Timer.After(45, function()
        if not pendingWargameRequest or pendingWargameRequest.roster ~= savedRoster then return end
        local n = GetNumGroupMembers(1) or 0
        if n < pendingWargameRequest.teamSize then
            print("|cffff0000[PvP20R Queue]|r Варгейм не отправлен: наша группа не собралась (" .. n .. "/" .. pendingWargameRequest.teamSize .. ")")
        elseif savedRoster.sender == myName and not opponentGroupReady then
            print("|cffff0000[PvP20R Queue]|r Варгейм не отправлен: вторая команда не сообщила, что собралась")
        end
        TrySendWargame()
    end)
end

-- ============================================================================
-- READY CHECK FLOW
-- ============================================================================
local function BuildReadyInfo()
    local queueKey = currentRoster and currentRoster.queueKey
    local constraints = GetConstraints(queueKey)
    local roleCounts   = { HEALER = 0, TANK = 0, DAMAGER = 0 }
    local roleAccepted = { HEALER = 0, TANK = 0, DAMAGER = 0 }
    local roleDeclined = { HEALER = 0, TANK = 0, DAMAGER = 0 }
    local roster = GetQueueBucket(queueKey)
    if currentRoster and currentRoster.set then
        for nameRealm in pairs(currentRoster.set) do
            local role = "DAMAGER"
            local data = roster[nameRealm]
            if data and data.roles then
                if data.roles:find("H") then role = "HEALER"
                elseif data.roles:find("T") then role = "TANK" end
            end
            roleCounts[role] = roleCounts[role] + 1
            if wgReadyAccepted[nameRealm] then roleAccepted[role] = roleAccepted[role] + 1 end
            if wgReadyDeclined[nameRealm] then roleDeclined[role] = roleDeclined[role] + 1 end
        end
    end
    local rolesList = {}
    for _, r in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        if roleCounts[r] > 0 then
            rolesList[#rolesList + 1] = {
                role = r, totalRole = roleCounts[r],
                totalAccepted = roleAccepted[r], totalDeclined = roleDeclined[r],
            }
        end
    end
    local declinedCount = 0
    for nameRealm in pairs(wgReadyDeclined) do
        if not currentRoster or not currentRoster.set or currentRoster.set[nameRealm] then
            declinedCount = declinedCount + 1
        end
    end
    return {
        roles = rolesList, totalNumPlayers = constraints.totalPlayers,
        numPlayersAccepted = GetReadyCount(), numPlayersDeclined = declinedCount,
    }
end

local function OnAllReady()
    if wgResultTimer then
        wgResultTimer:Cancel()
        wgResultTimer = nil
    end
    if PVPReadyDialog and PVPReadyDialog:IsShown() then
        if StaticPopupSpecial_Hide then
            StaticPopupSpecial_Hide(PVPReadyDialog)
        else
            PVPReadyDialog:Hide()
        end
    end
    RestoreEnterButton()

    local myTeam, myName, isLeader = GetMyTeam()
    local savedRoster = currentRoster
    -- startHide = true: окно покажет итог и само закроется по таймеру
    -- Blizzard (PvpPopup.lua, OnUpdate). С false оно висело до конца.
    if PVPReadyPopup then
        PVPReadyPopup.startHide = true
        PVPReadyPopup:Setup(BuildReadyInfo())
    end

    if IsInGroup() then
        C_PartyInfo.LeaveParty()
    end

    LeaveQueues()
    ClearMyQueueForWargame()

    if myTeam and myTeam[1] and myTeam[1] ~= myName then
        myTeamLeader = myTeam[1]
        autoAcceptInviteUntil = GetTime() + 30
    else
        myTeamLeader = nil
        autoAcceptInviteUntil = 0
    end

    if isLeader and myTeam and savedRoster then
        BeginTeamForm(myTeam, myName, savedRoster)
    end

    wgReadyPause = false
    wgReadyAccepted = {}
    wgReadyDeclined = {}
    RefreshFrames()
end

-- Состав из шести кириллических имён приходит по частям и потому позже
-- коротких WG_READY. Кто нажал «Войти» быстро, присылал согласие тем, у кого
-- окно ещё не открылось, — его выбрасывали, и у опоздавших счёт не доходил
-- до шести: группа не собиралась (20:08, Диффамация и Меро). Копим такие
-- согласия и засчитываем, когда окно откроется.
local earlyReady = {}

local function OnReady(sender)
    local senderNameRealm = ns.FormatNameRealm(sender)
    if not senderNameRealm then return end
    if not wgReadyPause then
        earlyReady[senderNameRealm] = GetTime()
        return
    end
    if not IsInRoster(senderNameRealm) then return end
    wgReadyAccepted[senderNameRealm] = true
    if PVPReadyPopup and PVPReadyPopup:IsShown() then
        PVPReadyPopup:Setup(BuildReadyInfo())
    end
    local queueKey = currentRoster and currentRoster.queueKey
    if GetReadyCount() >= GetConstraints(queueKey).totalPlayers then
        OnAllReady()
    end
end

local function OnReadyFail(sender)
    local senderNameRealm = ns.FormatNameRealm(sender)
    if not senderNameRealm or not wgReadyPause then return end
    if not IsInRoster(senderNameRealm) then return end
    wgReadyDeclined[senderNameRealm] = true
    if wgResultTimer then wgResultTimer:Cancel(); wgResultTimer = nil end
    wgReadyPause = false
    RefreshFrames()
    PlaySound(SOUNDKIT.LFG_DENIED)
    if PVPReadyPopup then
        PVPReadyPopup.startHide = true
        PVPReadyPopup:Setup(BuildReadyInfo())
    end
    C_Timer.After(5.2, function()
        currentRoster = nil
        wgReadyAccepted = {}
        wgReadyDeclined = {}
    end)
end

-- ============================================================================
-- WARGAME SETUP POPUP
-- ============================================================================
local function ShowWargameSetupPopup(queueKey)
    if wgResultTimer then
        wgResultTimer:Cancel()
        wgResultTimer = nil
    end
    if wgCustomButton then
        wgCustomButton:Hide()
    end
    if not PVPReadyDialog then return end
    wgReadyPause = true
    wgReadyAccepted = {}
    wgReadyDeclined = {}
    RefreshFrames()
    if not currentRoster then
        currentRoster = {
            teamA = {},
            teamB = {},
            set = {},
            queueKey = queueKey
        }
    end
    for name, at in pairs(earlyReady) do
        if GetTime() - at < 15 and IsInRoster(name) then
            wgReadyAccepted[name] = true
            if ns.QLog then ns.QLog("засчитал раннее «Войти» от " .. name) end
        end
    end
    earlyReady = {}
    local index = 1
    for i = 1, GetMaxBattlefieldID() do
        if GetBattlefieldStatus(i) == "none" then
            index = i
            break
        end
    end

    local displayName, isRated, queueType, gameType, role
    if queueKey == "ARENA_5V5" then
        displayName = ARENA_BATTLES_5V5
        isRated = true
        queueType = "ARENA"
        gameType = "5v5"
        role = "DAMAGER"
    else
        displayName = PVP_RATED_SOLO_SHUFFLE
        isRated = true
        queueType = "RATEDSHUFFLE"
        gameType = "3v3"
        role = "DAMAGER"
    end

    PVPReadyDialog_Display(PVPReadyDialog, index, displayName, isRated, queueType, gameType, role)
    if not PVPReadyDialog or not PVPReadyDialog:IsShown() then return end
    if PVPReadyDialog.enterButton then
        PVPReadyDialog.enterButton:Hide()
    end
    if PVPReadyDialog.EnterBattleButton then
        PVPReadyDialog.EnterBattleButton:Hide()
    end
    if not wgCustomButton then
        wgCustomButton = CreateFrame("Button", nil, PVPReadyDialog, "UIPanelButtonTemplate")
        local real = PVPReadyDialog.enterButton or PVPReadyDialog.EnterBattleButton
        wgCustomButton:SetAllPoints(real)
        wgCustomButton:SetText(real:GetText())
        wgCustomButton:SetScript("OnClick", function(self)
            if not wgReadyPause then return end
            if wgResultTimer then
                wgResultTimer:Cancel()
                wgResultTimer = nil
            end
            wgReadyAccepted[ns.FormatNameRealm(UnitName("player"))] = true
            SendReady()
            if StaticPopupSpecial_Hide then
                StaticPopupSpecial_Hide(PVPReadyDialog)
            else
                PVPReadyDialog:Hide()
            end
            self:Hide()
            if PVPReadyPopup then
                PVPReadyPopup.startHide = false
                PVPReadyPopup:Setup(BuildReadyInfo())
            end
            local queueKey = currentRoster and currentRoster.queueKey
            if GetReadyCount() >= GetConstraints(queueKey).totalPlayers then OnAllReady() end
        end)
    end
    wgCustomButton:Show()
    wgResultTimer = C_Timer.NewTimer(10.0, function()
        wgResultTimer = nil
        if not wgReadyPause then return end
        local myName = ns.FormatNameRealm(UnitName("player"))
        if myName and wgReadyAccepted[myName] then
            -- Кто не получил состав (старая версия без склейки длинных
            -- сообщений), тот и отказа не пришлёт: остальные висели в окне
            -- готовности бесконечно. Ещё 10 с — и сдаёмся, называя виноватых.
            local roster = currentRoster
            C_Timer.After(10, function()
                if not wgReadyPause or currentRoster ~= roster or not roster or not roster.set then return end
                local missing = {}
                for name in pairs(roster.set) do
                    if not wgReadyAccepted[name] then missing[#missing + 1] = name end
                end
                print("|cffff0000[PvP20R Queue]|r Готовность не собралась, нет «Войти» от: "
                    .. table.concat(missing, ", ") .. ". Хост пересоберёт матч через минуту.")
                wgReadyPause = false
                if PVPReadyPopup and PVPReadyPopup:IsShown() then
                    PVPReadyPopup:Hide()
                end
                RestoreEnterButton()
                RefreshFrames()
            end)
            return
        end
        SendReadyFail()
        if PVPReadyDialog and PVPReadyDialog:IsShown() then
            if StaticPopupSpecial_Hide then
                StaticPopupSpecial_Hide(PVPReadyDialog)
            else
                PVPReadyDialog:Hide()
            end
        end
        if wgCustomButton then
            wgCustomButton:Hide()
        end
        PlaySound(SOUNDKIT.LFG_DENIED)
        LeaveQueueByKey()
    end)
end

-- Хост шлёт состав и в гильдию, и шёпотом; длинный шёпот по частям
-- доходит на несколько секунд позже. Второй приход открывал окно заново
-- и стирал уже нажатые «Войти», проверка готовности не сходилась никогда.
local lastSetupMessage, lastSetupAt = nil, 0

local function OnWargameSetup(sender, message)
    if message == lastSetupMessage and GetTime() - lastSetupAt < 30 then
        if ns.QLog then ns.QLog("состав пришёл повторно, пропускаю") end
        return
    end
    lastSetupMessage, lastSetupAt = message, GetTime()
    local parts = {}
    for part in message:gmatch("([^,]+)") do parts[#parts + 1] = part end
    if #parts >= 4 then
        local queueKey = parts[2]
        local teamA, teamB = {}, {}
        for name in parts[3]:gmatch("([^;]+)") do teamA[#teamA + 1] = name end
        for name in parts[4]:gmatch("([^;]+)") do teamB[#teamB + 1] = name end
        if #teamA > 0 and #teamB > 0 and (queueKey == "SOLO_SHUFFLE" or queueKey == "ARENA_5V5") then
            local set = {}
            for _, name in ipairs(teamA) do set[name] = true end
            for _, name in ipairs(teamB) do set[name] = true end
            -- Состав слышат все в гильдии и вайтлисте. Окно «Войти» показывалось
            -- и тем, кого в нём нет; не нажал за 10 с — аддон выкидывал его из
            -- очереди (20:15, Лоренс и Эксп).
            if not set[ns.FormatNameRealm(UnitName("player"))] then
                if ns.QLog then ns.QLog("состав без меня, окно не показываю") end
                return
            end
            currentRoster = {
                teamA = teamA, teamB = teamB, set = set, queueKey = queueKey,
                sender = parts[5], receiver = parts[6],
            }
            ShowWargameSetupPopup(queueKey)
        end
    end
end

-- ============================================================================
-- HOST DISTRIBUTION
-- ============================================================================
local function HostDistributeWargames(queueKey)
    -- Раньше флаг ставился навсегда: после одной сорвавшейся попытки
    -- (кто-то не нажал «Войти», вышел) хост молчал до /reload.
    if setupSent[queueKey] and GetTime() - setupSent[queueKey] < 60 then
        if ns.QLog then ns.QLog("хост: состав уже рассылал " .. math.floor(GetTime() - setupSent[queueKey]) .. " с назад, жду") end
        return
    end
    if ns.QLog then ns.QLog("хост: раскладываю команды") end
    local bucket = GetQueueBucket(queueKey)
    local myName = ns.FormatNameRealm(UnitName("player"))
    local hostName, minTime = nil, math.huge
    for nameRealm, data in pairs(bucket) do
        local queuedAt = type(data) == "table" and data.time or nil
        if type(queuedAt) == "number" and (queuedAt < minTime or (queuedAt == minTime and (not hostName or nameRealm < hostName))) then
            minTime = queuedAt
            hostName = nameRealm
        end
    end
    if hostName ~= myName then return end
    local constraints = GetConstraints(queueKey)
    if not constraints then return end
    local players = {}
    for name in pairs(bucket) do players[#players + 1] = name end
    if #players < constraints.totalPlayers then return end
    if #players > 12 then
        table.sort(players, function(a, b)
            local ta = bucket[a] and bucket[a].time or math.huge
            local tb = bucket[b] and bucket[b].time or math.huge
            if ta == tb then return a < b end
            return ta < tb
        end)
        local trimmed = {}
        for i = 1, 12 do trimmed[i] = players[i] end
        players = trimmed
    end
    local setup
    if #players == constraints.totalPlayers then
        setup = FindSetup(players, constraints, queueKey)
    else
        local noticeKey = queueKey .. ":size"
        local now = GetTime()
        if not lastSetupNotice[noticeKey] or now - lastSetupNotice[noticeKey] > 30 then
            lastSetupNotice[noticeKey] = now
            print("|cff00ff00[PvP20R Queue]|r В очереди " .. #players .. ", для матча нужно " .. constraints.totalPlayers .. ". Собираю группу из них.")
        end
        for _, combo in ipairs(GenerateCombinations(#players, constraints.totalPlayers)) do
            local subset = {}
            for _, idx in ipairs(combo) do subset[#subset + 1] = players[idx] end
            setup = FindSetup(subset, constraints, queueKey)
            if setup then break end
        end
    end
    if ns.QLog then
        local pairsSeen = {}
        local friendOf = ns.StateMachine and ns.StateMachine.QueueFriendSender
        for i = 1, #players do
            for j = i + 1, #players do
                if friendOf and friendOf(queueKey, players[i], players[j]) then
                    pairsSeen[#pairsSeen + 1] = players[i] .. "+" .. players[j]
                end
            end
        end
        ns.QLog("хост: друзья по опросу: " .. (#pairsSeen > 0 and table.concat(pairsSeen, ", ") or "нет")
            .. (friendOf and "" or " (QueueFriendSender нет — старый StateMachine)"))
        if setup then
            ns.QLog("хост: лидеры " .. tostring(setup.sender) .. " -> " .. tostring(setup.receiver)
                .. (setup.friends and ", друзья" or ", НЕ друзья") .. (setup.relaxed and ", хилы не поровну" or ""))
        end
    end
    if not setup or not setup.sender or not setup.receiver then
        Announce("Матч не собрался: некого поставить лидерами. В очереди " .. #players .. ".")
        return
    end
    if setup.relaxed then
        Announce("Хилов не хватило на две ровные команды. Матч всё равно собирается из " .. constraints.totalPlayers .. " человек.")
    elseif not setup.friends then
        Announce("Лидеры не друзья в Battle.net (" .. setup.sender .. " и " .. setup.receiver .. "). Матч собирается, вызов может не уйти.")
    end
    local teamA, teamB = setup[1], setup[2]
    local sender, receiver = setup.sender, setup.receiver
    PlaceLeaderFirst(teamA, sender)
    PlaceLeaderFirst(teamB, receiver)
    if teamA[1] ~= sender then
        PlaceLeaderFirst(teamA, receiver)
        PlaceLeaderFirst(teamB, sender)
    end
    local roster = {
        teamA = teamA, teamB = teamB, set = {}, queueKey = queueKey,
        sender = sender, receiver = receiver,
    }
    for _, name in ipairs(teamA) do roster.set[name] = true end
    for _, name in ipairs(teamB) do roster.set[name] = true end
    setupSent[queueKey] = GetTime()
    currentRoster = roster
    print("|cff00ff00[PvP20R Queue]|r Лидеры: " .. sender .. " вызывает " .. receiver)
    local msg = "WG_SETUP," .. queueKey .. "," .. table.concat(teamA, ";") .. "," .. table.concat(teamB, ";") .. "," .. sender .. "," .. receiver
    SendQueue(msg)
    ShowWargameSetupPopup(queueKey)
end

-- ============================================================================
-- INCOMING MESSAGE DISPATCHER
-- ============================================================================
local function OnMessage(sender, message)
    if not message or message == "" then return end
    local myName = ns.FormatNameRealm(UnitName("player"))
    local senderNameRealm = ns.FormatNameRealm(sender)
    local isSelf = (senderNameRealm == myName)
    if wgReadyPause and not IsInRoster(senderNameRealm) and message:sub(1, 8) ~= "Q_LEAVE," then return end
    if message:sub(1, 9) == "WG_SETUP," then
        OnWargameSetup(sender, message)
    elseif message:sub(1, 14) == "WG_GROUP_READY" and not isSelf then
        opponentGroupReady = true
        print("|cff00ff00[PvP20R Queue]|r Вторая команда собрана.")
        TrySendWargame()
    -- WG_READY_FAIL тоже начинается с WG_READY: проверять его первым,
    -- иначе отказ засчитывался как согласие.
    elseif message:sub(1, 13) == "WG_READY_FAIL" and not isSelf then
        OnReadyFail(sender)
    elseif message:sub(1, 8) == "WG_READY" and not isSelf then
        OnReady(sender)
    end
end

-- ============================================================================
-- RELOAD & GROUP HANDLERS
-- ============================================================================
local function HandleReload()
    if not (wgReadyPause or pendingWargameRequest) then return end
    local roster = currentRoster or (pendingWargameRequest and pendingWargameRequest.roster)
    if roster and roster.set then
        SendQueue("WG_READY_FAIL")
    end
    wgReadyPause = false
    currentRoster = nil
    wgReadyAccepted = {}
    wgReadyDeclined = {}
    ResetWargameRequest()
    if wgResultTimer then wgResultTimer:Cancel(); wgResultTimer = nil end
    RefreshFrames()
end

function TrySendWargame()
    if not pendingWargameRequest then return end
    local request = pendingWargameRequest
    if GetTime() > request.deadline then return end
    local n = GetNumGroupMembers(1) or 0
    if n < request.teamSize then return end
    local roster = request.roster
    local myName = ns.FormatNameRealm(UnitName("player"))
    currentRoster = roster
    -- Группа собрана — окну готовности больше нечего показывать.
    if PVPReadyPopup and PVPReadyPopup:IsShown() then
        StaticPopupSpecial_Hide(PVPReadyPopup)
    end
    if roster.receiver == myName then
        if not request.announced then
            request.announced = true
            SendQueue("WG_GROUP_READY")
            expectedWargameFrom = roster.sender
            autoAcceptWargameUntil = GetTime() + 45
            print("|cff00ff00[PvP20R Queue]|r Наша команда собрана. Ждём вызов от " .. tostring(roster.sender))
        end
        return
    end
    if roster.sender ~= myName then return end
    if not opponentGroupReady then
        if not request.waitingPrinted then
            request.waitingPrinted = true
            print("|cff00ff00[PvP20R Queue]|r Наша команда собрана. Ждём, пока соберётся вторая.")
        end
        return
    end
    pendingWargameRequest = nil
    SendWargameRequest()
end

local function HandleGroupRosterUpdate()
    TrySendWargame()
end

-- ============================================================================
-- EVENT FRAME
-- ============================================================================
local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("PARTY_INVITE_REQUEST")
f:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
f:RegisterEvent("WARGAME_REQUESTED")
f:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, text, _, sender = ...
        if prefix == ns.PREFIX and text and text ~= "" then
            if text:sub(1, 9) == "WG_SETUP,"
            or text:sub(1, 8) == "WG_READY"
            or text:sub(1, 13) == "WG_READY_FAIL" then
                OnMessage(sender, text)
            end
        end
    elseif event == "PARTY_INVITE_REQUEST" then
        local inviterName, _, _, _, _, inviterRealm = ...
        OnPartyInvite(inviterName, inviterRealm)
    elseif event == "UPDATE_BATTLEFIELD_STATUS" then
        AutoAcceptWargame()
    elseif event == "WARGAME_REQUESTED" then
        if not (expectedWargameFrom and GetTime() <= autoAcceptWargameUntil and WarGameRespond) then return end
        WarGameRespond(true)
        if PVPFramePopup and StaticPopupSpecial_Hide then
            StaticPopupSpecial_Hide(PVPFramePopup)
        end
    end
end)

-- ============================================================================
-- EXPORT
-- ============================================================================
ns.WargameFlow = {
    ResetWargameState = ResetWargameState,
    IsWargamePaused = function() return wgReadyPause end,
    IsInRoster = IsInRoster,
    HandleMessage = OnMessage,
    HostDistributeWargames = HostDistributeWargames,
    HandleReload = HandleReload,
    HandleGroupRosterUpdate = HandleGroupRosterUpdate,
    -- Для /pvp20r dev: снимок внутреннего состояния, только чтение.
    GetDebugState = function()
        return {
            readyPause = wgReadyPause,
            roster = currentRoster,
            accepted = wgReadyAccepted,
            pending = pendingWargameRequest,
            opponentGroupReady = opponentGroupReady,
            expectedFrom = expectedWargameFrom,
            acceptLeft = autoAcceptWargameUntil - GetTime(),
            myTeamLeader = myTeamLeader,
        }
    end,
}