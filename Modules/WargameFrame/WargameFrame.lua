local addonName, ns = ...
local L = ns.L

-- ============================================================================
-- 1. CONSTANTS AND CONFIGURATION
-- ============================================================================
local SEP = "|"
local QUERY_TIMEOUT = 0.3

local MODES = {
	WARGAMES = {
		title = WARGAMES,
		icon = "Interface\\Icons\\ability_warrior_offensivestance",
		showBracket = true,
		showTarget = true,
	},
	SPECTATOR = {
		title = L["Spectator Mode"],
		icon = "Interface\\Icons\\inv_leatherworking_70_loveseat",
		showBracket = true,
		showTarget = false,
	}
}

local UI_EVENTS = {
	"LFG_UPDATE",
	"LFG_QUEUE_STATUS_UPDATE",
	"UPDATE_BATTLEFIELD_STATUS",
	"LOBBY_MATCHMAKER_QUEUE_STATUS_UPDATE",
	"LFG_LIST_ACTIVE_ENTRY_UPDATE",
	"LFG_LIST_SEARCH_RESULTS_RECEIVED",
	"LFG_LIST_SEARCH_RESULT_UPDATED",
	"LFG_LIST_APPLICANT_UPDATED",
	"PET_BATTLE_QUEUE_STATUS",
	"GROUP_ROSTER_UPDATE",
	"PLAYER_TARGET_CHANGED",
	"PARTY_LEADER_CHANGED",
	"PLAYER_ENTERING_WORLD"
}

local FRIEND_EVENTS = {
	"BN_FRIEND_INFO_CHANGED",
	"BN_FRIEND_ACCOUNT_ONLINE",
	"BN_FRIEND_ACCOUNT_OFFLINE",
	"BN_FRIEND_LIST_SIZE_CHANGED",
	"FRIENDLIST_UPDATE"
}

-- ============================================================================
-- 2. STATE
-- ============================================================================
local CurrentMode = MODES.WARGAMES
local CurrentBracket = 1
local MapArena, MapBattleground
local UseTarget = false
local BNetPartyLeader
local SpectatorLeaders = {}
local PendingQueries = {}

-- ============================================================================
-- 3. HELPERS
-- ============================================================================
local function ChatPrint(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8000PvP 20 Rating:|r " .. msg)
end

local function ErrorPrint(msg)
	UIErrorsFrame:AddMessage("PvP 20 Rating: " .. msg, 1, 0.1, 0.1, 1)
end

local function GetGroupSize()
	return math.max(GetNumGroupMembers(1) or 0, 1)
end

local function IsWarGameTargetValid()
	return UnitExists("target") and UnitIsPlayer("target")
		and not UnitIsUnit("player", "target") and UnitLeadsAnyGroup("target")
end

local function GetLevelBracket(level)
	if level < 20 then return 10, 19 end
	local min = math.floor((level - 20) / 10) * 10 + 20
	return min, min + 9
end

local function IsWargameMode()
	return CurrentMode == MODES.WARGAMES
end

local function IsSpectatorMode() return
	CurrentMode == MODES.SPECTATOR
end

local function IsTargetAllowed()
	if not IsWargameMode() then return false end
	local bracket = ns.BRACKETS[CurrentBracket]
	return bracket == nil or bracket.name ~= PVP_RATED_SOLO_SHUFFLE
end

local function IsBattleground()
	local bracket = ns.BRACKETS[CurrentBracket]
	return (IsWargameMode() or IsSpectatorMode()) and bracket and bracket.size == 0
end

local function GetCurrentMapIndex()
	return IsBattleground() and MapBattleground or MapArena
end

local function SetCurrentMapIndex(index)
	if IsBattleground() then MapBattleground = index else MapArena = index end
end

local function FindDefaultMapIndex(pvpType)
	for i, map in ipairs(ns.MAPS) do
		if map.isRandom and map.pvpType == pvpType then return i end
	end
	return 1
end

local function GetGroupUnitToken()
	local size = GetGroupSize()
	return size > (MAX_PARTY_MEMBERS + 1) and "raid" or "party", size > (MAX_PARTY_MEMBERS + 1) and size or size - 1
end

local function GetLeaderDisplayText(info)
	if not info then return end
	local accName = info.accountName or info.battleTag
	local charName = info.gameAccountInfo and info.gameAccountInfo.characterName
	local className = info.gameAccountInfo and info.gameAccountInfo.className
	if charName and charName ~= "" then
		return "|cff82c5ff" .. accName .. "|r " .. ns.GetClassColorText(className, "(" .. charName .. ")")
	end
	return "|cff82c5ff" .. accName .. "|r"
end

-- ============================================================================
-- 4. COMMUNICATION & VALIDATION
-- ============================================================================
local function CheckQueueState()
	local inQueue, paused = false, true
	for i = 1, NUM_LE_LFG_CATEGORYS do
		local mode, submode = GetLFGMode(i)
		if mode and submode ~= "noteleport" then
			inQueue = true
			if mode == "queued" or mode == "abandonedInDungeon" or mode == "rolecheck" or mode == "proposal" then
				paused = false
			end
		end
	end
	if C_LFGList and select(2, C_LFGList.GetNumApplications()) > 0 then
		inQueue = true
		for _, app in ipairs(C_LFGList.GetApplications()) do
			if select(2, C_LFGList.GetApplicationInfo(app)) == "applied" then paused = false; break end
		end
	end
	for i = 1, GetMaxBattlefieldID() do
		local status, _, _, _, suspend = GetBattlefieldStatus(i)
		if status and status ~= "none" then
			inQueue = true
			if status == "queued" and not suspend then paused = false end
		end
	end
	for i = 1, MAX_WORLD_PVP_QUEUES do
		local status = GetWorldPVPQueueStatus(i)
		if status and status ~= "none" then
			inQueue = true
			if status == "queued" then paused = false end
		end
	end
	if C_PetBattles and C_PetBattles.GetPVPMatchmakingInfo() == "queued" then inQueue, paused = true, false end
	local inProgress, _, _, _, _, isBG = GetLFGRoleUpdate()
	if inProgress and isBG then inQueue, paused = true, false end
	local rcInProgress, rcIsBG = GetLFGReadyCheckUpdate()
	if rcInProgress and rcIsBG then inQueue, paused = true, false end
	if CanHearthAndResurrectFromArea() then inQueue, paused = true, false end
	return (inQueue and paused) and L["You cannot start a War Game while in a suspended queue state."] or nil
end

local function HandleIncomingLeaderMsg(payload, sender)
	if not payload or payload == "" then return false end
	local sep = payload:find(SEP, 1, true)
	local kind = sep and payload:sub(1, sep - 1) or payload
	if kind == "Q" then
		local suspended = CheckQueueState() ~= nil
		local inLFGList = C_LFGList and (select(2, C_LFGList.GetNumApplications()) > 0 or C_LFGList.HasActiveEntryInfo())
		local dead, offline, otherParty = false, false, false
		local token, max = GetGroupUnitToken()
		for i = 1, max do
			local unit = token .. i
			if UnitIsDeadOrGhost(unit) then
				dead = true
			elseif not UnitIsConnected(unit) then
				offline = true
			elseif UnitInOtherParty(unit) then
				otherParty = true
			end
		end
		local leaderUnit = "player"
		local prefix, maxG = IsInRaid(1) and "raid" or "party", IsInRaid(1) and math.min(GetNumGroupMembers(1) or 0, 40) or 4
		for i = 1, maxG do
			if UnitIsGroupLeader(prefix .. i) then
				leaderUnit = prefix .. i
				break
			end
		end
		local validationStr = string.format("%s,%s,%s,%s,%s,%d,%s,%d",
			tostring(suspended),
			tostring(inLFGList),
			tostring(dead),
			tostring(offline),
			tostring(otherParty),
			GetGroupSize(),
			ns.FormatNameRealm(UnitName(leaderUnit)),
			UnitLevel(leaderUnit) or 0)
		ns.SendWhisper("R" .. SEP .. validationStr, sender, "ALERT")
		return true
	elseif kind == "R" then
		local pending = PendingQueries[sender]
		if not pending then return false end
		if pending.timer then
			pending.timer:Cancel()
		end
		local data = {}
		for val in (sep and payload:sub(sep + 1) or ""):gmatch("([^,]+)") do
			data[#data + 1] = val
		end
		if #data >= 8 then
			pending.response = {
				suspendedQueue = data[1] == "true",
				inLFGList = data[2] == "true",
				hasDead = data[3] == "true",
				hasOffline = data[4] == "true",
				hasOtherParty = data[5] == "true",
				groupSize = tonumber(data[6]) or 0,
				leaderName = data[7],
				leaderLevel = tonumber(data[8]) or 0,
				sender = sender,
			}
		end
		if pending.callback then pending.callback(pending.callbackArgs, sender) end
		return true
	end
	return false
end

-- ============================================================================
-- 5. TRAVEL PASS / INVITE (Глобальные функции для XML/Populate)
-- ============================================================================
function WargameTravelPassButton_OnEnter(self)
	local friendIndex = self:GetParent().id
	local inviteTypeToButtonText = {
		["INVITE"] = TRAVEL_PASS_INVITE, ["SUGGEST_INVITE"] = SUGGEST_INVITE, ["REQUEST_INVITE"] = REQUEST_INVITE,
		["INVITE_CROSS_FACTION"] = TRAVEL_PASS_INVITE_CROSS_FACTION, ["SUGGEST_INVITE_CROSS_FACTION"] = SUGGEST_INVITE_CROSS_FACTION,
		["REQUEST_INVITE_CROSS_FACTION"] = REQUEST_INVITE_CROSS_FACTION,
	}
	local canCross = C_PartyInfo and C_PartyInfo.CanFormCrossFactionParties and C_PartyInfo.CanFormCrossFactionParties()
	local playerFaction = UnitFactionGroup("player")
	local primary = nil
	for i = 1, C_BattleNet.GetFriendNumGameAccounts(friendIndex) do
		local info = C_BattleNet.GetFriendGameAccountInfo(friendIndex, i)
		if info and info.playerGuid and info.clientProgram == BNET_CLIENT_WOW and info.wowProjectID == WOW_PROJECT_ID and info.realmID ~= 0 and (info.factionName == playerFaction or canCross) then
			primary = info; break
		end
	end
	local inviteType = (primary and GetDisplayedInviteType and GetDisplayedInviteType(primary.playerGuid)) or "INVITE"
	local isCrossFaction = primary and primary.factionName and primary.factionName ~= playerFaction
	inviteType = isCrossFaction and (inviteType .. "_CROSS_FACTION") or inviteType
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(inviteTypeToButtonText[inviteType] or TRAVEL_PASS_INVITE, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
	if isCrossFaction and primary then GameTooltip:AddLine(CROSS_FACTION_INVITE_TOOLTIP:format(FACTION_LABELS_FROM_STRING[primary.factionName] or FACTION_NEUTRAL), nil, nil, nil, true) end
	local restriction = FriendsFrame_GetInviteRestriction(friendIndex)
	local restrictionText = FriendsFrame_GetInviteRestrictionText(restriction)
	if restrictionText ~= "" then GameTooltip:AddLine(restrictionText, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, true)
	elseif (inviteType == "REQUEST_INVITE" or inviteType == "REQUEST_INVITE_CROSS_FACTION") and C_SocialQueue and primary then
		local group = C_SocialQueue.GetGroupForPlayer(primary.playerGuid)
		local members = C_SocialQueue.GetGroupMembers(group)
		local numDisplayed = 0
		for i = 1, #members do
			if members[i].guid ~= primary.playerGuid then
				if numDisplayed == 0 then GameTooltip:AddLine(SOCIAL_QUEUE_ALSO_IN_GROUP)
				elseif numDisplayed >= 7 then GameTooltip:AddLine(SOCIAL_QUEUE_AND_MORE, GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b, 1); break end
				if SocialQueueUtil_GetRelationshipInfo then
					local name, color = SocialQueueUtil_GetRelationshipInfo(members[i].guid, nil, members[i].clubId)
					GameTooltip:AddLine(color .. name .. FONT_COLOR_CODE_CLOSE)
				end
				numDisplayed = numDisplayed + 1
			end
		end
	end
	GameTooltip:Show()
end

function WargameTravelPassButton_OnClick(self)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	local friendIndex = self:GetParent().id
	local canCross = C_PartyInfo and C_PartyInfo.CanFormCrossFactionParties and C_PartyInfo.CanFormCrossFactionParties()
	local playerFaction = UnitFactionGroup("player")
	local accounts, primary = {}, nil
	local isCrossFaction = false
	for i = 1, C_BattleNet.GetFriendNumGameAccounts(friendIndex) do
		local info = C_BattleNet.GetFriendGameAccountInfo(friendIndex, i)
		if info and info.playerGuid and info.clientProgram == BNET_CLIENT_WOW and info.wowProjectID == WOW_PROJECT_ID and info.realmID ~= 0 and (info.factionName == playerFaction or canCross) then
			if not primary then primary = info; isCrossFaction = (info.factionName ~= playerFaction) end
			accounts[#accounts + 1] = info
		end
	end
	if #accounts == 0 then return end
	if #accounts > 1 or isCrossFaction then
		local accountInfo = C_BattleNet.GetFriendAccountInfo(friendIndex)
		local headerText = accountInfo and (accountInfo.accountName or accountInfo.battleTag) or ""
		MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
			rootDescription:SetTag("MENU_WARGAME_TRAVELPAS_INVITE")
			rootDescription:CreateTitle(headerText)
			for _, gameAccountInfo in ipairs(accounts) do
				local factionAtlas = gameAccountInfo.factionName == "Horde" and "communities-icon-faction-horde" or "communities-icon-faction-alliance"
				local name = gameAccountInfo.characterName or ""
				local realm = gameAccountInfo.realmDisplayName or ""
				local text = "|A:" .. factionAtlas .. ":16:14:0:0|a " .. name
				if realm ~= "" then text = text .. " - " .. realm end
				text = text .. string.format(FRIENDS_TOOLTIP_WOW_TOON_TEMPLATE, "", gameAccountInfo.characterLevel or 0, gameAccountInfo.raceName or UNKNOWN, gameAccountInfo.className or UNKNOWN)
				rootDescription:CreateButton(text, function()
					if FriendsFrame_InviteOrRequestToJoin and gameAccountInfo.playerGuid then FriendsFrame_InviteOrRequestToJoin(gameAccountInfo.playerGuid, gameAccountInfo.gameAccountID)
					elseif gameAccountInfo.gameAccountID then BNInviteFriend(gameAccountInfo.gameAccountID) end
				end)
			end
		end)
	else
		local gameAccountInfo = accounts[1]
		if FriendsFrame_InviteOrRequestToJoin and gameAccountInfo.playerGuid then FriendsFrame_InviteOrRequestToJoin(gameAccountInfo.playerGuid, gameAccountInfo.gameAccountID)
		elseif gameAccountInfo.gameAccountID then BNInviteFriend(gameAccountInfo.gameAccountID) end
	end
end

-- ============================================================================
-- 6. FRIEND LIST POPULATION & CUSTOM MENU
-- ============================================================================
local UnitPopupMenuBnFriendWargame = CreateFromMixins(UnitPopupTopLevelMenuMixin)
UnitPopupManager:RegisterMenu("BN_FRIEND_WARGAME", UnitPopupMenuBnFriendWargame)
function UnitPopupMenuBnFriendWargame:GetEntries()
	local originalEntries = UnitPopupMenuBnFriend:GetEntries()
	local filteredEntries = {}
	for _, entry in ipairs(originalEntries) do if entry ~= UnitPopupViewHousesButtonMixin then table.insert(filteredEntries, entry) end end
	return filteredEntries
end

local UnitPopupMenuBnFriendOfflineWargame = CreateFromMixins(UnitPopupTopLevelMenuMixin)
UnitPopupManager:RegisterMenu("BN_FRIEND_OFFLINE_WARGAME", UnitPopupMenuBnFriendOfflineWargame)
function UnitPopupMenuBnFriendOfflineWargame:GetEntries()
	local originalEntries = UnitPopupMenuBnFriendOffline:GetEntries()
	local filteredEntries = {}
	for _, entry in ipairs(originalEntries) do if entry ~= UnitPopupViewHousesButtonMixin then table.insert(filteredEntries, entry) end end
	return filteredEntries
end

local function PopulateFriendRow(button, accountInfo, friendIndex)
	button.id = friendIndex
	button.buttonType = FRIENDS_BUTTON_TYPE_BNET
	if FriendsFrame_UpdateFriendButton then FriendsFrame_UpdateFriendButton(button, { id = friendIndex, buttonType = FRIENDS_BUTTON_TYPE_BNET }) end
	local locked = WargameFrame:IsFriendSelectionLocked()
	button:EnableMouse(not locked)
	local isSelected = (IsSpectatorMode() and SpectatorLeaders[accountInfo.battleTag]) or (not IsSpectatorMode() and accountInfo.battleTag == BNetPartyLeader)
	if isSelected then button:LockHighlight() else button:UnlockHighlight() end
	local gameInfo = accountInfo.gameAccountInfo
	local isOnline = gameInfo and gameInfo.isOnline
	local charName = gameInfo and gameInfo.characterName
	local isOnlineWoW = isOnline and charName and charName ~= ""
	if button.info and gameInfo.richPresence and gameInfo.richPresence ~= "" then button.info:SetText(gameInfo.richPresence) end
	if locked then
		if button.status then button.status:SetDesaturated(true) end
		if button.gameIcon then button.gameIcon:SetDesaturated(true) end
		if button.Favorite then button.Favorite:SetDesaturated(true) end
		if button.highlight then button.highlight:SetVertexColor(FRIENDS_GRAY_COLOR:GetRGB()) end
		if button.info then button.info:SetTextColor(FRIENDS_GRAY_COLOR:GetRGB()) end
		if button.name then
			if isOnlineWoW then
				local accountText = FRIENDS_GRAY_COLOR:WrapTextInColorCode(accountInfo.accountName or "")
				local charText = FRIENDS_GRAY_COLOR:WrapTextInColorCode("(" .. charName .. ")")
				button.name:SetText(accountText .. " " .. charText)
			else button.name:SetText(FRIENDS_GRAY_COLOR:WrapTextInColorCode(accountInfo.accountName or "")) end
		end
	else
		if button.highlight then button.highlight:SetVertexColor(HIGHLIGHT_LIGHT_BLUE:GetRGB()) end
		if button.info then button.info:SetTextColor(FRIENDS_GRAY_COLOR:GetRGB()) end
		if button.name then
			if isOnlineWoW then
				local classKey = ns.GetClassKey(gameInfo.className)
				local classColor = (classKey and RAID_CLASS_COLORS[classKey]) and RAID_CLASS_COLORS[classKey] or FRIENDS_BNET_NAME_COLOR
				local accountText = FRIENDS_BNET_NAME_COLOR:WrapTextInColorCode(accountInfo.accountName or "")
				local charText = classColor:WrapTextInColorCode("(" .. charName .. ")")
				button.name:SetText(accountText .. " " .. charText)
			else
				local color = isOnline and FRIENDS_BNET_NAME_COLOR or FRIENDS_GRAY_COLOR
				button.name:SetText(color:WrapTextInColorCode(accountInfo.accountName or ""))
			end
		end
	end
	local tp = button.travelPassButton
	if tp then
		local restriction = FriendsFrame_GetInviteRestriction(friendIndex)
		local canInvite = FriendsFrame_GetInviteRestrictionText(restriction) == ""
		local faction = gameInfo and gameInfo.factionName
		local atlasBase = "friendslist-invitebutton-default"
		if faction and faction ~= UnitFactionGroup("player") then atlasBase = (faction == "Horde") and "friendslist-invitebutton-horde" or "friendslist-invitebutton-alliance" end
		tp.NormalTexture:SetAtlas(atlasBase .. "-normal")
		tp.PushedTexture:SetAtlas(atlasBase .. "-pressed")
		tp.DisabledTexture:SetAtlas(atlasBase .. "-disabled")
		tp:SetShown(isOnline)
		tp:SetEnabled(canInvite and not locked)
		tp:SetScript("OnEnter", WargameTravelPassButton_OnEnter)
		tp:SetScript("OnClick", WargameTravelPassButton_OnClick)
	end
end

-- ============================================================================
-- 7. START BUTTON LOGIC
-- ============================================================================
function WargameFrame_UpdateStartButton()
	local button = WargameFrame.StartButton
	button.tooltip = nil
	local checks = {
		function()
			if IsInGroup(1) and not UnitIsGroupLeader("player", 1) then return WARGAME_REQ_LEADER end
			if IsSpectatorMode() then
				local leaders = {}
				for _, info in pairs(SpectatorLeaders) do leaders[#leaders + 1] = info end
				if #leaders < 2 then return L["Select two Battle.net friends to start a War Game."] end
				for _, leaderInfo in ipairs(leaders) do
					if not leaderInfo or not leaderInfo.gameAccountInfo then return ERR_TRAVEL_PASS_NOT_WOW end
					local gameInfo = leaderInfo.gameAccountInfo
					if not gameInfo.isOnline or gameInfo.clientProgram ~= BNET_CLIENT_WOW then return ERR_TRAVEL_PASS_NOT_WOW end
					if not gameInfo.isInCurrentRegion then return L["This friend is playing World of Warcraft in a different region."] end
					if gameInfo.wowProjectID ~= WOW_PROJECT_ID then return ERR_TRAVEL_PASS_WRONG_PROJECT end
					if IsInGroup(1) and gameInfo.characterName ~= "" then
						local friendName = ns.FormatNameRealm(gameInfo.characterName, gameInfo.realmName)
						if friendName then
							friendName = friendName:lower()
							local token, max = GetGroupUnitToken()
							for i = 1, max do
								if ns.FormatNameRealm(UnitName(token .. i)):lower() == friendName then return L["You cannot challenge a friend who is in your group."] end
							end
						end
					end
				end
			elseif BNetPartyLeader and not UseTarget then
				local info = ns.FindBNetFriendByBattleTag(BNetPartyLeader)
				if not info or not info.gameAccountInfo then return ERR_TRAVEL_PASS_NOT_WOW end
				local gameInfo = info.gameAccountInfo
				if not gameInfo.isOnline or gameInfo.clientProgram ~= BNET_CLIENT_WOW then return ERR_TRAVEL_PASS_NOT_WOW end
				if not gameInfo.isInCurrentRegion then return L["This friend is playing World of Warcraft in a different region."] end
				if gameInfo.wowProjectID ~= WOW_PROJECT_ID then return ERR_TRAVEL_PASS_WRONG_PROJECT end
			end
		end,
		function()
			if C_LFGList then
				if select(2, C_LFGList.GetNumApplications()) > 0 then return CANNOT_DO_THIS_WITH_LFGLIST_APP end
				if C_LFGList.HasActiveEntryInfo() then return CANNOT_DO_THIS_WHILE_LFGLIST_LISTED end
			end
		end,
		function()
			if IsSpectatorMode() then return end
			local groupSize = GetGroupSize()
			local minSize, maxSize
			if IsBattleground() then
				local map = ns.MAPS[GetCurrentMapIndex()]
				if map then
					if map.isRandom then
						local pvpType = 3
						local size = groupSize
						local pool = ns.RANDOM_BG_POOLS[size <= 10 and 1 or (size <= 15 and 2 or 3)]
						local minS, maxS = 999, 0
						for _, m in ipairs(ns.MAPS) do
							if not m.isRandom and m.pvpType == pvpType and (pvpType ~= 3 or (pool and pool.ids[m.id])) then
								minS = math.min(minS, m.minPlayers or 1)
								maxS = math.max(maxS, m.maxPlayers or groupSize)
							end
						end
						minSize, maxSize = minS, maxS
					else minSize, maxSize = map.minPlayers or 1, map.maxPlayers or groupSize end
				end
			else
				local bracket = ns.BRACKETS[CurrentBracket]
				if bracket then minSize, maxSize = bracket.size, bracket.size end
			end
			minSize, maxSize = minSize or 1, maxSize or groupSize
			if groupSize < minSize then return (IsBattleground() and L["Your group needs %d more |4player:players; to join this battleground."] or PVP_ARENA_NEED_MORE):format(minSize - groupSize)
			elseif groupSize > maxSize then return (IsBattleground() and L["Your group needs %d less |4player:players; to join this battleground."] or PVP_ARENA_NEED_LESS):format(groupSize - maxSize) end
		end,
		function()
			local token, max = GetGroupUnitToken()
			for i = 1, max do
				local unit = token .. i
				if UnitIsDeadOrGhost(unit) then return L["You cannot start a War Game because one of your group members is dead."] end
				if not UnitIsConnected(unit) then return L["You cannot start a War Game because one of your group members is disconnected."] end
				if UnitInOtherParty and UnitInOtherParty(unit) then return L["You cannot start a War Game because one of your group members is in instance group."] end
			end
		end,
		CheckQueueState,
		function()
			if IsSpectatorMode() then return end
			local playerMin = GetLevelBracket(UnitLevel("player"))
			if IsWargameMode() and UseTarget then
				if not IsWarGameTargetValid() then return WARGAME_REQ_TARGET end
				local targetLevel = UnitLevel("target")
				if targetLevel and playerMin ~= GetLevelBracket(targetLevel) then return L["You cannot start a War Game because both party leaders are not in the same level range."] end
			elseif BNetPartyLeader then
				local info = ns.FindBNetFriendByBattleTag(BNetPartyLeader)
				if info and info.gameAccountInfo and info.gameAccountInfo.characterLevel and playerMin ~= GetLevelBracket(info.gameAccountInfo.characterLevel) then return L["You cannot start a War Game because both party leaders are not in the same level range."] end
			end
		end,
		function()
			if IsSpectatorMode() then return end
			if IsWargameMode() and UseTarget then
				if not IsWarGameTargetValid() then return WARGAME_REQ_TARGET end
			elseif not BNetPartyLeader then return L["Select a Battle.net friend to challenge, or check Target."] end
		end,
	}
	for _, check in ipairs(checks) do
		button.tooltip = check()
		if button.tooltip then button:Disable(); return end
	end
	button:Enable()
end

-- ============================================================================
-- 8. WARGAME FRAME MIXIN
-- ============================================================================
WargameFrameMixin = WargameFrameMixin or {}
function WargameFrameMixin:IsFriendSelectionLocked()
	return IsWargameMode() and UseTarget
end

function WargameFrameMixin:UpdateTargetCheckButtonState()
	local locked = self:IsFriendSelectionLocked()
	local alpha = locked and 0.8 or 1
	for _, widget in ipairs({ self.ScrollBox, self.ScrollBar, self.SearchBox }) do
		widget:EnableMouse(not locked)
		if widget.EnableMouseWheel then widget:EnableMouseWheel(not locked) end
		widget:SetAlpha(alpha)
	end
	if self.ScrollBox.DesaturateHierarchy then pcall(self.ScrollBox.DesaturateHierarchy, self.ScrollBox, locked and 1 or 0) end
	if self.ScrollBar.DesaturateHierarchy then pcall(self.ScrollBar.DesaturateHierarchy, self.ScrollBar, locked and 1 or 0) end
	self.ScrollBlocker:SetShown(locked)
	if locked then self.SearchBox:ClearFocus() end
	self.TargetCheckButton:SetShown(IsTargetAllowed())
	local targetText = TARGET
	if locked and UnitExists("target") and UnitIsPlayer("target") then
		local _, targetClass = UnitClass("target")
		targetText = TARGET .. ": " .. ns.GetClassColorText(targetClass, UnitName("target"))
	end
	self.TargetCheckButton.Text:SetText(targetText)
	self:RefreshFriendList()
end

function WargameFrameMixin:RefreshMapList()
	local pvpType = IsBattleground() and 3 or 4
	if not GetCurrentMapIndex() then SetCurrentMapIndex(FindDefaultMapIndex(pvpType)) end
	self.MapDropdown:SetupMenu(function(dropdown, rootDescription)
		for i, map in ipairs(ns.MAPS) do
			if map.pvpType == pvpType then
				rootDescription:CreateRadio(map.name, function() return GetCurrentMapIndex() == i end, function() SetCurrentMapIndex(i); self:UpdateStartButtonState() end, i)
			end
		end
	end)
	if not ns.MAPS[GetCurrentMapIndex()] or ns.MAPS[GetCurrentMapIndex()].pvpType ~= pvpType then SetCurrentMapIndex(FindDefaultMapIndex(pvpType)) end
	self:UpdateStartButtonState()
end

function WargameFrameMixin:UpdateStartButtonState() WargameFrame_UpdateStartButton() end
function WargameFrameMixin:RegisterEvents()
	for _, event in ipairs(UI_EVENTS) do self:RegisterEvent(event) end
	for _, event in ipairs(FRIEND_EVENTS) do self:RegisterEvent(event) end
end
function WargameFrameMixin:UnregisterEvents()
	for _, event in ipairs(UI_EVENTS) do self:UnregisterEvent(event) end
	for _, event in ipairs(FRIEND_EVENTS) do self:UnregisterEvent(event) end
end
function WargameFrameMixin:OnEvent(event)
	if event == "PLAYER_TARGET_CHANGED" then self:UpdateTargetCheckButtonState()
	elseif event == "BN_FRIEND_INFO_CHANGED" or event == "BN_FRIEND_ACCOUNT_ONLINE" or event == "BN_FRIEND_ACCOUNT_OFFLINE" or event == "BN_FRIEND_LIST_SIZE_CHANGED" or event == "FRIENDLIST_UPDATE" then self:RefreshFriendList() end
	self:UpdateStartButtonState()
end

function WargameFrameMixin:OnLoad()
	self:SetScript("OnDragStart", self.StartMoving)
	self:SetScript("OnDragStop", self.StopMovingOrSizing)
	self:SetPortraitToAsset(CurrentMode.icon)
	self.TargetCheckButton:SetChecked(UseTarget)
	self.ScrollBlocker = CreateFrame("Frame", nil, self)
	self.ScrollBlocker:SetPoint("TOPLEFT", self.SearchBox, "TOPLEFT", -4, 2)
	self.ScrollBlocker:SetPoint("BOTTOMRIGHT", self.ScrollBar, "BOTTOMRIGHT", 2, -2)
	self.ScrollBlocker:EnableMouse(true)
	self.ScrollBlocker:Hide()
	self.BracketDropdown:SetupMenu(function(dropdown, rootDescription)
		for i, bracket in ipairs(ns.BRACKETS) do
			rootDescription:CreateRadio(bracket.name, function() return CurrentBracket == i end, function()
				CurrentBracket = i
				self.BracketDropdown:SetText(bracket.name)
				self:RefreshMapList()
				self:UpdateStartButtonState()
				self:UpdateTargetCheckButtonState()
			end, i)
		end
	end)
	C_AddOns.LoadAddOn("Blizzard_FriendsFrame")
	if not _G.playerRealmID then _G.playerRealmID = GetRealmID() end
	if not _G.playerRealmName then _G.playerRealmName = GetRealmName() end
	if not _G.playerFactionGroup then _G.playerFactionGroup = UnitFactionGroup("player") end
	self:InitFriendScrollBox()
	self:RefreshMapList()
end

function WargameFrameMixin:OnShow() self:RegisterEvents(); self:RefreshFriendList(); self:UpdateStartButtonState() end
function WargameFrameMixin:OnHide() self:UnregisterEvents(); PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end

function WargameFrameMixin:OpenFor(customButtonKey)
	local modeMap = { SpectatorButton = MODES.SPECTATOR, WargamesButton = MODES.WARGAMES }
	local newMode = modeMap[customButtonKey] or MODES.WARGAMES
	if PVEFrame and self:GetParent() ~= PVEFrame then self:SetParent(PVEFrame) end
	if (customButtonKey == "WargamesButton") and ns.MainUI and ns.MainUI.SelectCustomButton then ns.MainUI.SelectCustomButton(customButtonKey) end
	local modeChanged = CurrentMode ~= newMode
	if modeChanged then CurrentMode = newMode end
	if modeChanged or not self:IsShown() then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
	self:SetTitle(CurrentMode.title)
	self:SetPortraitToAsset(CurrentMode.icon)
	self.BracketDropdown:SetShown(CurrentMode.showBracket)
	self.TargetCheckButton:SetShown(IsTargetAllowed())
	if ns.BRACKETS[CurrentBracket] then self.BracketDropdown:SetText(ns.BRACKETS[CurrentBracket].name) end
	self:RefreshMapList()
	self:UpdateTargetCheckButtonState()
	self:ClearAllPoints()
	self:SetPoint("TOPLEFT", PVEFrame, "TOPRIGHT", 10, 0)
	self:Show()
	self:UpdateStartButtonState()
end

-- ============================================================================
-- 9. SEND QUEUE FUNCTIONS
-- ============================================================================
function WargameFrameMixin:GetSelectedMap()
	local pvpType = IsBattleground() and 3 or 4
	local map = ns.MAPS[GetCurrentMapIndex()]
	if map and map.isRandom then
		local size = GetGroupSize()
		local pool = (pvpType == 3) and ns.RANDOM_BG_POOLS[size <= 10 and 1 or (size <= 15 and 2 or 3)]
		local candidates = {}
		for _, m in ipairs(ns.MAPS) do
			if not m.isRandom and m.pvpType == pvpType and (pvpType ~= 3 or (pool and pool.ids[m.id])) then candidates[#candidates + 1] = m end
		end
		map = #candidates > 0 and candidates[math.random(#candidates)] or nil
	end
	if not map then return nil, nil end
	local mapDescription = map.name
	if not IsBattleground() then
		local bracket = ns.BRACKETS[CurrentBracket]
		if bracket then mapDescription = mapDescription .. " (" .. bracket.name .. ")" end
	end
	return map, mapDescription
end

local function ValidateResponse(response, targetName, isSpectator, myData)
	if not response then return nil, nil end
	if not isSpectator and myData and response.groupSize ~= myData.groupSize then
		return L["You cannot start a War Game because %s's group size does not match yours."]:format(targetName)
	end
	if response.suspendedQueue then
		return L["You cannot start a War Game because %s's group is in a suspended queue state."]:format(targetName)
	end
	if response.inLFGList then
		return L["You cannot start a War Game because %s's group has an active LFG listing."]:format(targetName)
	end
	if response.hasOffline then
		return L["You cannot start a War Game because one of %s's group members is disconnected."]:format(targetName)
	end
	if response.hasOtherParty then
		return L["You cannot start a War Game because one of %s's group members is in instance group."]:format(targetName)
	end
	if response.hasDead then
		return L["You cannot start a War Game because one of %s's group members is dead."]:format(targetName)
	end
	local leaderInfo = ns.FindBNetFriendByNameRealm(response.leaderName)
	if not leaderInfo then
		return L["You cannot start a War Game because %s's leader is not in your friend list (%s)."]:format(targetName, response.leaderName)
	end
	if not isSpectator and myData and GetLevelBracket(myData.leaderLevel) ~= GetLevelBracket(response.leaderLevel) then
		return L["You cannot start a War Game because you and the group leader of %s are in different level ranges."]:format(targetName)
	end
	return nil, leaderInfo
end

function WargameFrameMixin:QueryTargetLeader(targetNameRealm, callback, callbackArgs)
	local prev = PendingQueries[targetNameRealm]
	if prev and prev.timer then
		prev.timer:Cancel()
	end
	PendingQueries[targetNameRealm] = { callback = callback, callbackArgs = callbackArgs }
	ns.SendWhisper("Q", targetNameRealm, "ALERT")
	PendingQueries[targetNameRealm].timer = C_Timer.NewTimer(QUERY_TIMEOUT, function()
		local pending = PendingQueries[targetNameRealm]
		if pending then
			PendingQueries[targetNameRealm] = nil
			if pending.callback then
				pending.callback(pending.callbackArgs, targetNameRealm)
			end
		end
	end)
end

function WargameFrameMixin:SendSpectatorQueue(map, mapDescription)
	local leaders = {}
	for _, info in pairs(SpectatorLeaders) do leaders[#leaders + 1] = info end
	if #leaders < 2 then return end
	local data = { leaders = leaders, map = map, mapDescription = mapDescription, responses = {}, queriesSent = 0, queriesCompleted = 0 }
	local function getLeaderNames(leader)
		local charName, realm = leader.gameAccountInfo and leader.gameAccountInfo.characterName, leader.gameAccountInfo and leader.gameAccountInfo.realmName
		local nameRealm = ns.FormatNameRealm(charName, realm)
		return nameRealm, nameRealm or GetLeaderDisplayText(leader)
	end
	local function tryFinish(d)
		if d.queriesCompleted < d.queriesSent then return end
		local leaderInfos, errors = {}, {}
		d.responsesByIndex = {}
		for i, leader in ipairs(d.leaders) do
			local nameRealm, displayName = getLeaderNames(leader)
			local response = d.responses[nameRealm]
			if response then
				local err, leaderInfo = ValidateResponse(response, displayName, true, nil)
				if err then errors[#errors + 1] = err else leaderInfos[#leaderInfos + 1] = leaderInfo end
				d.responsesByIndex[i] = response
			else leaderInfos[#leaderInfos + 1] = leader; d.responsesByIndex[i] = nil end
		end
		if d.responsesByIndex[1] and d.responsesByIndex[2] then
			local r1, r2 = d.responsesByIndex[1], d.responsesByIndex[2]
			local _, name1 = getLeaderNames(d.leaders[1])
			local _, name2 = getLeaderNames(d.leaders[2])
			if r1.leaderName == r2.leaderName then ErrorPrint(L["You cannot start a War Game because %s and %s are in the same group."]:format(name1, name2)); return end
			if r1.groupSize ~= r2.groupSize then ErrorPrint(L["You cannot start a War Game because %s and %s have different group sizes."]:format(name1, name2)); return end
			if GetLevelBracket(r1.leaderLevel) ~= GetLevelBracket(r2.leaderLevel) then ErrorPrint(L["You cannot start a War Game because %s and %s are not in the same level range."]:format(name1, name2)); return end
		end
		if #errors > 0 then for _, err in ipairs(errors) do ErrorPrint(err) end; return end
		if #leaderInfos == 2 then
			local a, b = leaderInfos[1], leaderInfos[2]
			local bracket = ns.BRACKETS[CurrentBracket]
			StartSpectatorWarGame(a.accountName, b.accountName, bracket and bracket.size or 0, d.map.name, false)
			ChatPrint(L["War Game request sent to "] .. GetLeaderDisplayText(a) .. " vs " .. GetLeaderDisplayText(b) .. " - " .. d.mapDescription .. ".")
		end
	end
	for _, leader in ipairs(leaders) do
		local nameRealm = getLeaderNames(leader)
		data.queriesSent = data.queriesSent + 1
		if nameRealm then
			self:QueryTargetLeader(nameRealm, function(d, sender)
				local pending = PendingQueries[sender]
				d.responses[sender] = pending and pending.response
				d.queriesCompleted = d.queriesCompleted + 1
				tryFinish(d)
			end, data)
		else data.queriesCompleted = data.queriesCompleted + 1; tryFinish(data) end
	end
end

function WargameFrameMixin:SendTargetWarGame(map, mapDescription)
	if not IsWarGameTargetValid() then return end
	local targetName = ns.FormatNameRealm(UnitName("target"))
	local _, targetClass = UnitClass("target")
	if not targetName then
		StartWarGame("target", map.name)
		ChatPrint(L["War Game request sent to "] .. ns.GetClassColorText(targetClass, targetName) .. " - " .. mapDescription .. ".")
		return
	end
	local targetData = { map = map, mapDescription = mapDescription, targetName = targetName, targetClass = targetClass, myData = { groupSize = IsInGroup() and GetGroupSize() or 0, leaderLevel = UnitLevel("player") } }
	self:QueryTargetLeader(targetName, function(d, sender)
		local pending = PendingQueries[sender]
		local err = ValidateResponse(pending and pending.response, d.targetName, false, d.myData)
		if err then ErrorPrint(err); return end
		StartWarGame("target", d.map.name)
		ChatPrint(L["War Game request sent to "] .. ns.GetClassColorText(d.targetClass, d.targetName) .. " - " .. d.mapDescription .. ".")
	end, targetData)
end

function WargameFrameMixin:SendBNetFriendWarGame(map, mapDescription, accountName, accountInfo, mode)
	mode = mode or CurrentMode
	if not accountName then
		accountInfo = ns.FindBNetFriendByBattleTag(BNetPartyLeader)
		if not accountInfo then return end
		local targetNameRealm = ns.FormatNameRealm(accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.characterName, accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.realmName)
		if not targetNameRealm then
			accountName = accountInfo.accountName or accountInfo.battleTag
			StartWarGameByName(accountName .. " " .. map.name)
			ChatPrint(L["War Game request sent to "] .. GetLeaderDisplayText(accountInfo) .. " - " .. mapDescription .. ".")
			return
		end
		local friendData = { map = map, mapDescription = mapDescription, accountInfo = accountInfo, mode = mode, myData = { groupSize = IsInGroup() and GetGroupSize() or 0, leaderLevel = UnitLevel("player") } }
		self:QueryTargetLeader(targetNameRealm, function(d, sender)
			local pending = PendingQueries[sender]
			local err = ValidateResponse(pending and pending.response, targetNameRealm, false, d.myData)
			if err then ErrorPrint(err); return end
			local targetAccountName = pending and pending.response and pending.response.leaderName and ns.FindBNetFriendByNameRealm(pending.response.leaderName)
			local targetInfo = targetAccountName or d.accountInfo
			local finalAccountName = targetAccountName and (targetAccountName.accountName or targetAccountName.battleTag) or d.accountInfo.accountName or d.accountInfo.battleTag
			StartWarGameByName(finalAccountName .. " " .. d.map.name)
			ChatPrint(L["War Game request sent to "] .. GetLeaderDisplayText(targetInfo) .. " - " .. d.mapDescription .. ".")
		end, friendData)
		return
	end
	StartWarGameByName(accountName .. " " .. map.name)
	ChatPrint(L["War Game request sent to "] .. GetLeaderDisplayText(accountInfo) .. " - " .. mapDescription .. ".")
end

function WargameFrameMixin:SendQueue()
	local map, mapDescription = self:GetSelectedMap()
	if not map then return end
	if IsSpectatorMode() then self:SendSpectatorQueue(map, mapDescription)
	elseif UseTarget and IsTargetAllowed() then self:SendTargetWarGame(map, mapDescription)
	else self:SendBNetFriendWarGame(map, mapDescription) end
end

function WargameFrameMixin:RefreshFriendList()
	local needle = self.searchText
	local pinned, favs, online, offline = {}, {}, {}, {}
	if IsSpectatorMode() then
		for i = 1, BNGetNumFriends() do
			local info = C_BattleNet.GetFriendAccountInfo(i)
			if info and SpectatorLeaders[info.battleTag] then pinned[#pinned + 1] = { accountInfo = info, index = i } end
		end
	end
	for i = 1, BNGetNumFriends() do
		local info = C_BattleNet.GetFriendAccountInfo(i)
		if info then
			local matches = true
			if needle and needle ~= "" then
				local lowerNeedle = needle:lower()
				local candidates = { info.battleTag, info.note, info.accountName, info.gameAccountInfo and info.gameAccountInfo.characterName }
				matches = false
				for _, s in ipairs(candidates) do if type(s) == "string" and s:lower():find(lowerNeedle, 1, true) then matches = true; break end end
			end
			if matches and not (IsSpectatorMode() and SpectatorLeaders[info.battleTag]) then
				local entry = { accountInfo = info, index = i }
				if info.isFavorite then favs[#favs + 1] = entry
				elseif info.gameAccountInfo.isOnline then online[#online + 1] = entry
				else offline[#offline + 1] = entry end
			end
		end
	end
	local dataProvider = CreateDataProvider()
	local function insertWithDivider(list, hasMore)
		for _, entry in ipairs(list) do dataProvider:Insert(entry) end
		if hasMore and #list > 0 then dataProvider:Insert({ isDivider = true }) end
	end
	insertWithDivider(pinned, #favs + #online + #offline > 0)
	insertWithDivider(favs, #online + #offline > 0)
	insertWithDivider(online, #offline > 0)
	insertWithDivider(offline, false)
	self.ScrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition)
end

function WargameFrameMixin:InitFriendScrollBox()
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtentCalculator(function(_, elementData) return elementData.isDivider and 16 or 34 end)
	view:SetElementFactory(function(factory, elementData)
		if elementData.isDivider then factory("FriendsFrameFriendDividerTemplate")
		else factory("WargameFrameFriendButtonTemplate", function(button, data) PopulateFriendRow(button, data.accountInfo, data.index) end) end
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view)
end

-- ============================================================================
-- 10. FRIEND BUTTON MIXIN
-- ============================================================================
WargameFrameFriendButtonMixin = WargameFrameFriendButtonMixin or {}
function WargameFrameFriendButtonMixin:OnLoad()
	if FriendsListButtonMixin and FriendsListButtonMixin.OnLoad then FriendsListButtonMixin.OnLoad(self) end
end

function WargameFrameFriendButtonMixin:OnClick(button)
	if WargameFrame:IsFriendSelectionLocked() then return end
	local accountInfo = C_BattleNet.GetFriendAccountInfo(self.id)
	if not accountInfo then return end
	if button == "RightButton" then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		local isOnline = accountInfo.gameAccountInfo.isOnline
		local which = isOnline and "BN_FRIEND_WARGAME" or "BN_FRIEND_OFFLINE_WARGAME"
		local contextData = { name = accountInfo.accountName, friendsList = true, bnetIDAccount = accountInfo.bnetAccountID, battleTag = accountInfo.battleTag }
		UnitPopup_OpenMenu(which, contextData)
		return
	end
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	if IsSpectatorMode() then
		local tag = accountInfo.battleTag
		if SpectatorLeaders[tag] then SpectatorLeaders[tag] = nil
		else
			local count = 0
			for _ in pairs(SpectatorLeaders) do count = count + 1 end
			if count < 2 then SpectatorLeaders[tag] = accountInfo end
		end
	else BNetPartyLeader = (BNetPartyLeader == accountInfo.battleTag) and nil or accountInfo.battleTag end
	WargameFrame:RefreshFriendList()
	WargameFrame:UpdateStartButtonState()
end

function WargameFrameFriendButtonMixin:OnEnter()
	if WargameFrame:IsFriendSelectionLocked() then return end
	local accountInfo = C_BattleNet.GetFriendAccountInfo(self.id)
	if not accountInfo then return end
	local tooltip = FriendsTooltip
	if not tooltip then return end
	tooltip.height = 0; tooltip.maxWidth = 0
	local anchor, text
	local numGameAccounts = 0
	local battleTag = accountInfo.battleTag
	local noCharacterName = true
	local nameText, nameColor = FriendsFrame_GetBNetAccountNameAndStatus(accountInfo, noCharacterName)
	anchor = FriendsFrameTooltip_SetLine(FriendsTooltipHeader, nil, nameText)
	FriendsTooltipHeader:SetTextColor(nameColor:GetRGB())
	local gameAccountInfo = accountInfo.gameAccountInfo
	if gameAccountInfo and gameAccountInfo.gameAccountID then
		local showRichPresence = true
		if gameAccountInfo.clientProgram and gameAccountInfo.wowProjectID then showRichPresence = FriendsListUtil.ShouldShowRichPresenceOnly(accountInfo) end
		if showRichPresence then
			local characterName = FriendsFrame_GetFormattedCharacterName(gameAccountInfo.characterName, accountInfo.battleTag, gameAccountInfo.clientProgram, gameAccountInfo.timerunningSeasonID)
			FriendsFrameTooltip_SetLine(FriendsTooltipGameAccount1Name, nil, characterName)
			anchor = FriendsFrameTooltip_SetLine(FriendsTooltipGameAccount1Info, nil, gameAccountInfo.richPresence, -4)
		else
			local raceName = gameAccountInfo.raceName or UNKNOWN
			local className = gameAccountInfo.className or UNKNOWN
			local playerFaction = UnitFactionGroup("player")
			local canCooperate = gameAccountInfo.realmID and gameAccountInfo.realmID > 0 and gameAccountInfo.factionName == playerFaction
			local charName = gameAccountInfo.characterName
			if not canCooperate and charName then charName = charName .. CANNOT_COOPERATE_LABEL end
			local txt = string.format(FRIENDS_TOOLTIP_WOW_TOON_TEMPLATE, charName, gameAccountInfo.characterLevel, raceName, className)
			if gameAccountInfo.timerunningSeasonID then txt = TimerunningUtil.AddSmallIcon(txt) end
			FriendsFrameTooltip_SetLine(FriendsTooltipGameAccount1Name, nil, txt)
			local areaName = gameAccountInfo.areaName or UNKNOWN
			if gameAccountInfo.isInCurrentRegion then
				local realmName = gameAccountInfo.realmDisplayName or UNKNOWN
				anchor = FriendsFrameTooltip_SetLine(FriendsTooltipGameAccount1Info, nil, BNET_FRIEND_TOOLTIP_ZONE_AND_REALM:format(areaName, realmName), -4)
			else
				local regionNames = { [1] = NORTH_AMERICA, [2] = KOREA, [3] = EUROPE, [4] = TAIWAN, [5] = CHINA }
				local regionNameString = regionNames[gameAccountInfo.regionID] or UNKNOWN
				anchor = FriendsFrameTooltip_SetLine(FriendsTooltipGameAccount1Info, nil, BNET_FRIEND_TOOLTIP_ZONE_AND_REGION:format(areaName, regionNameString), -4)
			end
		end
	else FriendsTooltipGameAccount1Info:Hide(); FriendsTooltipGameAccount1Name:Hide() end
	if accountInfo.note ~= "" then FriendsTooltipNoteIcon:Show(); anchor = FriendsFrameTooltip_SetLine(FriendsTooltipNoteText, anchor, accountInfo.note, -8)
	else FriendsTooltipNoteIcon:Hide(); FriendsTooltipNoteText:Hide() end
	if accountInfo.customMessage ~= "" then
		FriendsTooltipBroadcastIcon:Show()
		if not HasTimePassed(accountInfo.customMessageTime, SECONDS_PER_YEAR) then accountInfo.customMessage = accountInfo.customMessage.."|n"..FRIENDS_BROADCAST_TIME_COLOR_CODE..string.format(BNET_BROADCAST_SENT_TIME, FriendsFrame_GetLastOnline(accountInfo.customMessageTime)..FONT_COLOR_CODE_CLOSE) end
		anchor = FriendsFrameTooltip_SetLine(FriendsTooltipBroadcastText, anchor, accountInfo.customMessage, -8)
		tooltip.hasBroadcast = true
	else FriendsTooltipBroadcastIcon:Hide(); FriendsTooltipBroadcastText:Hide(); tooltip.hasBroadcast = nil end
	if gameAccountInfo and gameAccountInfo.isOnline then FriendsTooltipLastOnline:Hide(); numGameAccounts = C_BattleNet.GetFriendNumGameAccounts(self.id)
	else text = FriendsFrame_GetLastOnlineText(accountInfo); anchor = FriendsFrameTooltip_SetLine(FriendsTooltipLastOnline, anchor, text, -4) end
	local gameAccountIndex = 1
	local characterNameString, gameAccountInfoString
	if numGameAccounts > 1 then
		local headerSet = false
		for i = 1, numGameAccounts do
			local altGameAccountInfo = C_BattleNet.GetFriendGameAccountInfo(self.id, i)
			if altGameAccountInfo and not altGameAccountInfo.hasFocus and (altGameAccountInfo.clientProgram ~= BNET_CLIENT_APP) and (altGameAccountInfo.clientProgram ~= BNET_CLIENT_CLNT) then
				local areaName = altGameAccountInfo.areaName or UNKNOWN
				local raceName = altGameAccountInfo.raceName or UNKNOWN
				local className = altGameAccountInfo.className or UNKNOWN
				local gameText = altGameAccountInfo.richPresence or ""
				if not headerSet then FriendsFrameTooltip_SetLine(FriendsTooltipOtherGameAccounts, anchor, nil, -8); headerSet = true end
				gameAccountIndex = gameAccountIndex + 1
				if gameAccountIndex > FRIENDS_TOOLTIP_MAX_GAME_ACCOUNTS then break end
				characterNameString = _G["FriendsTooltipGameAccount"..gameAccountIndex.."Name"]
				gameAccountInfoString = _G["FriendsTooltipGameAccount"..gameAccountIndex.."Info"]
				text = ""
				if C_Texture.IsTitleIconTextureReady(altGameAccountInfo.clientProgram, Enum.TitleIconVersion.Small) then
					C_Texture.GetTitleIconTexture(altGameAccountInfo.clientProgram, Enum.TitleIconVersion.Small, function(success, texture) if success then text = BNet_GetClientEmbeddedTexture(texture, 32, 32, 0).." " end end)
				end
				if (altGameAccountInfo.clientProgram == BNET_CLIENT_WOW) and (altGameAccountInfo.wowProjectID == WOW_PROJECT_ID) then
					local playerFaction = UnitFactionGroup("player")
					local canCooperate = altGameAccountInfo.realmName == GetRealmName() and altGameAccountInfo.factionName == playerFaction
					local altCharName = altGameAccountInfo.characterName
					if not canCooperate and altCharName then altCharName = altCharName .. CANNOT_COOPERATE_LABEL end
					text = text..string.format(FRIENDS_TOOLTIP_WOW_TOON_TEMPLATE, altCharName, altGameAccountInfo.characterLevel, raceName, className)
					gameText = areaName
				else
					local characterName = ""
					if altGameAccountInfo.isOnline then characterName = FriendsFrame_GetFormattedCharacterName(altGameAccountInfo.characterName, battleTag, altGameAccountInfo.clientProgram, altGameAccountInfo.timerunningSeasonID) end
					text = text..characterName
				end
				FriendsFrameTooltip_SetLine(characterNameString, nil, text)
				FriendsFrameTooltip_SetLine(gameAccountInfoString, nil, gameText)
			end
		end
		if not headerSet then FriendsTooltipOtherGameAccounts:Hide() end
	else FriendsTooltipOtherGameAccounts:Hide() end
	for i = gameAccountIndex + 1, FRIENDS_TOOLTIP_MAX_GAME_ACCOUNTS do
		characterNameString = _G["FriendsTooltipGameAccount"..i.."Name"]
		gameAccountInfoString = _G["FriendsTooltipGameAccount"..i.."Info"]
		if characterNameString then characterNameString:Hide() end
		if gameAccountInfoString then gameAccountInfoString:Hide() end
	end
	if numGameAccounts > FRIENDS_TOOLTIP_MAX_GAME_ACCOUNTS then FriendsFrameTooltip_SetLine(FriendsTooltipGameAccountMany, nil, string.format(FRIENDS_TOOLTIP_TOO_MANY_CHARACTERS, numGameAccounts - FRIENDS_TOOLTIP_MAX_GAME_ACCOUNTS), 0)
	else FriendsTooltipGameAccountMany:Hide() end
	tooltip.button = self
	tooltip:SetParent(UIParent)
	tooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 36, 0)
	tooltip:SetHeight(tooltip.height + FRIENDS_TOOLTIP_MARGIN_WIDTH)
	tooltip:SetWidth(math.min(FRIENDS_TOOLTIP_MAX_WIDTH, tooltip.maxWidth + FRIENDS_TOOLTIP_MARGIN_WIDTH))
	tooltip:Show()
end

function WargameFrameFriendButtonMixin:OnLeave()
	if FriendsTooltip then FriendsTooltip.button = nil; FriendsTooltip:Hide() end
end

-- ============================================================================
-- 11. UI HANDLERS & INIT (Глобальные для XML)
-- ============================================================================
function WargameFrameTargetCheckButton_OnClick(self)
	PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	UseTarget = self:GetChecked()
	WargameFrame:UpdateTargetCheckButtonState()
	WargameFrame:UpdateStartButtonState()
end

function WargameFrameStartButton_OnClick(self)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	WargameFrame:SendQueue()
end

-- ============================================================================
-- 12. EVENT FRAME
-- ============================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
	if event == "ADDON_LOADED" and arg1 == addonName then
		if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, ns.PREFIX) end
	elseif event == "CHAT_MSG_ADDON" and arg1 == ns.PREFIX then
		HandleIncomingLeaderMsg(arg2, arg4)
	elseif event == "UI_ERROR_MESSAGE" and arg1 == 895 and type(arg2) == "string" then
		ChatPrint("|cffff0000" .. arg2 .. (arg2:sub(-1) == "." and " " or ". ") .. "|r")
	end
end)

-- ============================================================================
-- 13. SLASH COMMANDS & EXPORTS
-- ============================================================================
local function OpenWargame(mode)
	if not PVEFrame then
		if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_PVPUI")
		elseif LoadAddOn then pcall(LoadAddOn, "Blizzard_PVPUI") end
	end
	if not PVEFrame then return end
	if not PVEFrame:IsShown() then ShowUIPanel(PVEFrame) end
	if PVEFrame_ShowFrame then PVEFrame_ShowFrame("PVPUIFrame") end
	if WargameFrame and WargameFrame.OpenFor then WargameFrame:OpenFor(mode) end
end

SLASH_WARGAME1, SLASH_WARGAME2 = "/wg", "/wargame"
SlashCmdList["WARGAME"] = function() OpenWargame("WargamesButton") end

SLASH_WARGAMESPEC1 = "/wgs"
SlashCmdList["WARGAMESPEC"] = function() OpenWargame("SpectatorButton") end

-- Экспорт для других модулей (например, HonorFrame)
ns.WargameUI = {
	OpenFor = function(mode) OpenWargame(mode) end,
}
