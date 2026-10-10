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
local myTeamLeader = nil
local autoAcceptInviteUntil = 0
local hostFindResults = {}

-- ============================================================================
-- UTILITIES (зависят от StateMachine)
-- ============================================================================
local function GetQueueRoster()
    return ns.StateMachine and ns.StateMachine.GetQueueRoster() or {}
end

local function GetConstraints(queueKey)
    return ns.StateMachine and ns.StateMachine.GetConstraints(queueKey)
end

local function IsQueueSuspended()
    return ns.StateMachine and ns.StateMachine.IsQueueSuspended()
end

local function LeaveQueueByKey(key)
    return ns.StateMachine and ns.StateMachine.LeaveQueueByKey(key)
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
local function CheckTeam(team, constraints)
    local healers, subscribers = 0, 0
    local roster = GetQueueRoster()
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

local function HasCrossLink(teamA, teamB)
    for _, u in ipairs(teamA) do
        for _, v in ipairs(teamB) do
            local r1 = hostFindResults[u]
            local r2 = hostFindResults[v]
            if (r1 and r1.friends and r1.friends[v]) or (r2 and r2.friends and r2.friends[u]) then
                return true
            end
        end
    end
    return false
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

local function FindSetup(players, constraints)
    local n = #players
    if n ~= constraints.totalPlayers then return nil end
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
        if CheckTeam(teamA, constraints) and CheckTeam(teamB, constraints) and not HasCrossLink(teamA, teamB) then
            return { teamA, teamB }
        end
    end
    return nil
end

local function PickLeader(team)
    local best, bestTime = nil, math.huge
    local roster = GetQueueRoster()
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
    local myName = ns.FormatNameRealm(UnitName("player"))
    for name in pairs(currentRoster.set) do
        if name ~= myName then ns.SendWhisper("WG_READY", name, "ALERT") end
    end
end

local function SendReadyFail()
    if not currentRoster then return end
    local myName = ns.FormatNameRealm(UnitName("player"))
    for name in pairs(currentRoster.set) do
        if name ~= myName then ns.SendWhisper("WG_READY_FAIL", name, "ALERT") end
    end
end

local function PickArenaMapID()
    local ids = {}
    if ns.MAPS then
        for _, m in ipairs(ns.MAPS) do
            if m and m.pvpType == 4 and not m.isRandom and m.id then ids[#ids + 1] = m.id end
        end
    end
    if #ids == 0 then return nil end
    return ids[math.random(#ids)]
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

local function SendWargameRequest()
    if not currentRoster then return end
    local leaderA = currentRoster.teamA[1]
    local leaderB = currentRoster.teamB[1]
    if not leaderA or not leaderB then return end
    local roster = GetQueueRoster()
    local timeA = (roster[leaderA] and roster[leaderA].time) or 0
    local timeB = (roster[leaderB] and roster[leaderB].time) or 0
    local sender, receiver
    if timeA < timeB or (timeA == timeB and leaderA < leaderB) then sender, receiver = leaderA, leaderB
    else sender, receiver = leaderB, leaderA end
    local myName = ns.FormatNameRealm(UnitName("player"))
    if sender ~= myName and receiver ~= myName then return end
    if not BNetOnline(receiver) then
        ns.SendWhisper("WG_READY_FAIL", receiver, "ALERT")
        ResetWargameRequest()
        return
    end
    autoAcceptWargameUntil = GetTime() + 30
    if receiver == myName then
        expectedWargameFrom = sender
        return
    end
    if not CanSendWargameRequest(currentRoster) then
        ns.SendWhisper("WG_READY_FAIL", receiver, "ALERT")
        ResetWargameRequest()
        return
    end
    local friend = ns.FindBNetFriendByNameRealm(receiver)
    if not friend then
        ns.SendWhisper("WG_READY_FAIL", receiver, "ALERT")
        ResetWargameRequest()
        return
    end
    local accountName = friend.accountName or friend.battleTag
    if not accountName then return end
    local mapID = PickArenaMapID()
    if not mapID then
        ns.SendWhisper("WG_READY_FAIL", receiver, "ALERT")
        ResetWargameRequest()
        return
    end
    if not StartWarGameByName then
        ns.SendWhisper("WG_READY_FAIL", receiver, "ALERT")
        ResetWargameRequest()
        return
    end
    local ok, err = pcall(StartWarGameByName, accountName .. " " .. tostring(mapID))
    if not ok then
        ns.SendWhisper("WG_READY_FAIL", receiver, "ALERT")
        ResetWargameRequest()
    end
end

-- ============================================================================
-- AUTO-ACCEPT LOGIC
-- ============================================================================
local function AutoAcceptWargame()
    if GetTime() > autoAcceptWargameUntil then
        ResetWargameRequest()
        return
    end
    for i = 1, GetMaxBattlefieldID() do
        if GetBattlefieldStatus(i) == "confirm" then
            if pcall(AcceptBattlefieldPort, i, 1) then
                ResetWargameRequest()
                return
            end
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
    AcceptGroup()
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
    local leaving = {}
    if ns.StateMachine then
        LeaveQueueByKey()
    end
end

local function InviteTeam(team, myName)
    if not team then return end
    for _, name in ipairs(team) do
        if name ~= myName then
            C_PartyInfo.InviteUnit(name)
        end
    end
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
    local roster = GetQueueRoster()
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
    if wgCustomButton then
        wgCustomButton:Hide()
    end

    local myTeam, myName, isLeader = GetMyTeam()
    if PVPReadyPopup then
        PVPReadyPopup.startHide = false
        PVPReadyPopup:Setup(BuildReadyInfo())
    end

    if IsInGroup() then
        LeaveParty()
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

    if isLeader and myTeam then
        C_Timer.After(1.0, function()
            InviteTeam(myTeam, myName)
        end)
    end

    wgReadyPause = false
    wgReadyAccepted = {}
    wgReadyDeclined = {}
    RefreshFrames()
end

local function OnReady(sender)
    local senderNameRealm = ns.FormatNameRealm(sender)
    if not senderNameRealm or not wgReadyPause then return end
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

local function OnWargameSetup(sender, message)
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
            currentRoster = { teamA = teamA, teamB = teamB, set = set, queueKey = queueKey }
            ShowWargameSetupPopup(queueKey)
        end
    end
end

-- ============================================================================
-- HOST DISTRIBUTION
-- ============================================================================
local function HostDistributeWargames(queueKey)
    local roster = GetQueueRoster()
    local myName = ns.FormatNameRealm(UnitName("player"))
    local hostName, minTime = nil, math.huge
    for nameRealm, data in pairs(roster) do
        if data.time < minTime or (data.time == minTime and (not hostName or nameRealm < hostName)) then
            minTime = data.time
            hostName = nameRealm
        end
    end
    if hostName ~= myName then return end
    local constraints = GetConstraints(queueKey)
    local players = {}
    for name in pairs(roster) do players[#players + 1] = name end
    if #players ~= constraints.totalPlayers then return end
    local setup = FindSetup(players, constraints)
    if not setup then return end
    local teamA, teamB = setup[1], setup[2]
    local leaderA = PickLeader(teamA)
    local leaderB = PickLeader(teamB)
    if not leaderA or not leaderB then return end
    PlaceLeaderFirst(teamA, leaderA)
    PlaceLeaderFirst(teamB, leaderB)
    local roster = { teamA = teamA, teamB = teamB, set = {}, queueKey = queueKey }
    for _, name in ipairs(teamA) do roster.set[name] = true end
    for _, name in ipairs(teamB) do roster.set[name] = true end
    currentRoster = roster
    local msg = "WG_SETUP," .. queueKey .. "," .. table.concat(teamA, ";") .. "," .. table.concat(teamB, ";")
    for _, name in ipairs(players) do
        if name ~= myName then ns.SendWhisper(msg, name, "ALERT") end
    end
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
    if wgReadyPause and not IsInRoster(senderNameRealm) and message:sub(1, 7) ~= "QLEAVE," then return end
    if message:sub(1, 9) == "WG_SETUP," then
        OnWargameSetup(sender, message)
    elseif message:sub(1, 8) == "WG_READY" and not isSelf then
        OnReady(sender)
    elseif message:sub(1, 13) == "WG_READY_FAIL" and not isSelf then
        OnReadyFail(sender)
    end
end

-- ============================================================================
-- RELOAD & GROUP HANDLERS
-- ============================================================================
local function HandleReload()
    if not (wgReadyPause or pendingWargameRequest) then return end
    local roster = currentRoster or (pendingWargameRequest and pendingWargameRequest.roster)
    if roster and roster.set then
        local myName = ns.FormatNameRealm(UnitName("player"))
        for name in pairs(roster.set) do
            if name ~= myName then ns.SendWhisper("WG_READY_FAIL", name, "ALERT") end
        end
    end
    wgReadyPause = false
    currentRoster = nil
    wgReadyAccepted = {}
    wgReadyDeclined = {}
    ResetWargameRequest()
    if wgResultTimer then wgResultTimer:Cancel(); wgResultTimer = nil end
    RefreshFrames()
end

local function HandleGroupRosterUpdate()
    if not pendingWargameRequest then return end
    if GetTime() > pendingWargameRequest.deadline then return end
    local n = GetNumGroupMembers(1) or 0
    if n >= pendingWargameRequest.teamSize then
        local r = pendingWargameRequest.roster
        pendingWargameRequest = nil
        currentRoster = r
        SendWargameRequest()
        currentRoster = nil
    end
end

-- ============================================================================
-- EVENT FRAME
-- ============================================================================
local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("PARTY_INVITE_REQUEST")
f:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
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
}