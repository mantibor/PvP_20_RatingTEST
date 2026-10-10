local addonName, ns = ...
local L = ns.L

-- ============================================================================
-- 1. CONSTANTS AND CONFIGURATION
-- ============================================================================
local BUTTONS = {
	regular = {
		RandomBGButton = {
			sizeText = L["Random"], typeText = BATTLEGROUNDS,
			tooltipTitle = BONUS_BUTTON_RANDOM_BG_TITLE, tooltipBody = BONUS_BUTTON_RANDOM_BG_DESC,
			matchTypes = { random_bg = true }
		},
		Arena1Button = {
			sizeText = ARENA_CASUAL, typeText = ARENA,
			tooltipTitle = SKIRMISH, tooltipBody = BONUS_BUTTON_SKIRMISH_DESC
		},
		RandomEpicBGButton = {},
		BrawlButton = {},
		BrawlButton2 = {},
	},
	custom = {
		SoloShuffleButton = {
			sizeText = RATED_SOLO_SHUFFLE_SIZE, typeText = ARENA,
			tooltipTitle = PVP_RATED_SOLO_SHUFFLE, tooltipBody = RATED_SOLO_SHUFFLE_MODE_DESCRIPTION,
			matchTypes = { solo_shuffle = true }
		},
		Arena5v5Button = {
			sizeText = ARENA_5V5, typeText = ARENA,
			tooltipTitle = ARENA_BATTLES_5V5, matchTypes = { arena_5v5 = true }
		},
	},
}

local BUTTON_MATCH_TYPES = {}
for _, group in pairs(BUTTONS) do
	for btn, def in pairs(group) do
		if def.matchTypes then BUTTON_MATCH_TYPES[btn] = def.matchTypes end
	end
end

-- ============================================================================
-- 2. TIER UTILITIES (Using Config/PvPTiers.lua)
-- ============================================================================
local function GetTier(rating)
	for _, t in ipairs(ns.PvPTiers) do
		if rating >= t.min and rating <= t.max then return t end
	end
	return ns.PvPTiers[1]
end

-- ============================================================================
-- 3. WEEKLY DB & ACE3 INTEGRATION
-- ============================================================================
local AceDB = LibStub and LibStub("AceDB-3.0", true)

local function EnsureWeeklyFresh()
	if not (ns.db and ns.db.char) then return end
	local w = ns.db.char.weekly
	local now = GetServerTime()
	local savedReset = tonumber(w.resetTime) or 0
	if savedReset > 0 and now < savedReset then return w end
	
	local nextReset = ns.GetResetTime()
	w.resetTime = nextReset
	w.bestRating = 0
	w.lastDate = 0
	w.weeklyPlayed = 0
	w.weeklyWon = 0
	return w
end

local function RecordWeeklyArenaRating(rating, played, won)
	local w = EnsureWeeklyFresh()
	if not w or (tonumber(played) or 0) <= 0 then return end
	w.weeklyPlayed = played
	w.weeklyWon = math.min(won, played)
	rating = tonumber(rating) or 0
	if rating > 0 and rating > (tonumber(w.bestRating) or 0) then
		w.bestRating = rating
		w.lastDate = GetServerTime()
	end
end

local function GetWeeklyArenaStats()
	local w = EnsureWeeklyFresh()
	if not w then return 0, 0, 0 end
	local weeklyPlayed = tonumber(w.weeklyPlayed) or 0
	local weeklyWon = tonumber(w.weeklyWon) or 0
	local weeklyBest = tonumber(w.bestRating) or 0
	
	if ns.GetMySkirmishData then
		local skirmishData = ns.GetMySkirmishData()
		if skirmishData and (skirmishData.played or 0) > 0 then
			local seasonBest = skirmishData.bestRating or skirmishData.rating or 0
			if weeklyBest > seasonBest then
				w.bestRating = seasonBest
				weeklyBest = seasonBest
			end
		end
	end
	return weeklyPlayed, weeklyWon, weeklyBest
end

local function InitWeeklyDB()
	if AceDB and not ns.db then
		ns.db = AceDB:New("PVP20RCharDB", {
			char = { weekly = { resetTime = 0, bestRating = 0, lastDate = 0, weeklyPlayed = 0, weeklyWon = 0 } }
		}, true)
	end
	if ns.db then EnsureWeeklyFresh() end
end

-- ============================================================================
-- 4. ARCHIVE MATCH STATISTICS
-- ============================================================================
local function GetArchivedMatchResult(data, guid)
	local w = data.winner
	if w ~= 0 and w ~= 1 then return nil end
	if type(data.scores) == "table" then
		for _, s in pairs(data.scores) do
			if s and s.guid == guid and s.faction then
				return (s.faction == w) and "win" or "loss"
			end
		end
	end
end

local function GetArchiveTotals()
	local keys = ns.GetArchivedMatchKeys and ns.GetArchivedMatchKeys()
	if not keys then return nil end
	local myGuid = UnitGUID("player")
	local totals = {
		RandomBGButton = { wins = 0, losses = 0 },
		SoloShuffleButton = { wins = 0, losses = 0 },
		Arena5v5Button = { wins = 0, losses = 0 }
	}
	local typeToBtn = {
		random_bg = "RandomBGButton",
		solo_shuffle = "SoloShuffleButton",
		arena_5v5 = "Arena5v5Button" }
	
	for _, ts in ipairs(keys) do
		local data = ns.GetArchivedMatch(ts)
		local btnKey = data and typeToBtn[data.matchType]
		if btnKey then
			local w, l = 0, 0
			if data.matchType == "solo_shuffle" then
				local rw, rl = ns.GetShuffleRoundsForGuid and ns.GetShuffleRoundsForGuid(data, myGuid)
				if rw then w, l = rw, rl
				else
					local r = GetArchivedMatchResult(data, myGuid)
					if r == "win" then w = 1 elseif r == "loss" then l = 1 end
				end
			else
				local r = GetArchivedMatchResult(data, myGuid)
				if r == "win" then w = 1 elseif r == "loss" then l = 1 end
			end
			totals[btnKey].wins = totals[btnKey].wins + w
			totals[btnKey].losses = totals[btnKey].losses + l
		end
	end
	return totals
end

local function AggregateArchiveForTypes(typeSet)
	local season = { played = 0, won = 0 }
	local weekly = { played = 0, won = 0 }
	local keys = ns.GetArchivedMatchKeys and ns.GetArchivedMatchKeys()
	if not keys then return season, weekly end
	
	local myGuid = UnitGUID("player")
	local nextReset = ns.GetResetTime()
	local weekStart = nextReset - 604800
	
	for _, ts in ipairs(keys) do
		local data = ns.GetArchivedMatch(ts)
		if data and typeSet[data.matchType] then
			local p, w = 0, 0
			if data.matchType == "solo_shuffle" then
				local rw, rl, total = ns.GetShuffleRoundsForGuid and ns.GetShuffleRoundsForGuid(data, myGuid)
				if rw then p, w = rw + rl, rw
				else
					local r = GetArchivedMatchResult(data, myGuid)
					if r == "win" then p, w = 1, 1 elseif r == "loss" then p = 1 end
				end
			else
				local r = GetArchivedMatchResult(data, myGuid)
				if r == "win" then p, w = 1, 1 elseif r == "loss" then p = 1 end
			end
			season.played = season.played + p
			season.won = season.won + w
			if ts >= weekStart then
				weekly.played = weekly.played + p
				weekly.won = weekly.won + w
			end
		end
	end
	return season, weekly
end

-- ============================================================================
-- 5. GLOBAL BEST RATING & UI UPDATES
-- ============================================================================
local function GetBestRating()
	local maxRating = 0
	local skirmishData = ns.GetMySkirmishData and ns.GetMySkirmishData()
	if skirmishData then
		local sBest = tonumber(skirmishData.bestRating or skirmishData.rating) or 0
		if sBest > maxRating then maxRating = sBest end
	else
		local guid = UnitGUID("player")
		if guid and ns.SkirmishDB then
			local rec = ns.SkirmishDB[guid]
			if rec then
				local sBest = tonumber(rec.bestRating or rec.rating) or 0
				if sBest > maxRating then maxRating = sBest end
			end
		end
	end
	
	if ns.GetArchiveStatsForGuid then
		local stats = ns.GetArchiveStatsForGuid(UnitGUID("player"))
		if stats then
			local buckets = { stats.randomBG, stats.soloShuffle, stats.wargame }
			for _, bucket in ipairs(buckets) do
				if bucket then
					local bBest = tonumber(bucket.bestRating or bucket.rating) or 0
					if bBest > maxRating then maxRating = bBest end
				end
			end
		end
	end
	return maxRating
end

local function IsReady()
	return C_AddOns.IsAddOnLoaded("Blizzard_PVPUI") and HonorFrame and HonorFrame.BonusFrame
end

local function UpdateQueueButtonsStats()
	if not IsReady() then return end
	local myGuid = UnitGUID("player")
	
	local function UpdateRankOverlay(btn, rating, bracket)
		if not btn or not btn.Tier then return end
		local rank = nil
		if rating > 2300 and ns.Leaderboard and ns.Leaderboard.GetLeaderboardRank then
			rank = ns.Leaderboard.GetLeaderboardRank(myGuid, bracket)
		end
		if rank and btn.Tier.Ranking and btn.Tier.RankingShadow then
			btn.Tier.Ranking:SetText(rank)
			btn.Tier.Ranking:Show()
			btn.Tier.RankingShadow:Show()
		else
			if btn.Tier.Ranking then btn.Tier.Ranking:Hide() end
			if btn.Tier.RankingShadow then btn.Tier.RankingShadow:Hide() end
		end
	end

	-- A. DataArchive Buttons (RandomBG, SoloShuffle, Arena5v5)
	local archiveStats = ns.GetArchiveStatsForGuid and ns.GetArchiveStatsForGuid(myGuid)
	local archiveMapping = {
		RandomBGButton    = { stats = archiveStats and archiveStats.randomBG,    bracket = "RANDOM_BATTLEGROUNDS" },
		SoloShuffleButton = { stats = archiveStats and archiveStats.soloShuffle, bracket = "SOLO_SHUFFLE" },
		Arena5v5Button    = { stats = archiveStats and archiveStats.wargame,     bracket = "WARGAMES" },
	}
	for btnKey, data in pairs(archiveMapping) do
		local btn = HonorFrame.BonusFrame[btnKey]
		if btn then
			local rating, played, won = 0, 0, 0
			if data.stats then
				rating = data.stats.rating or 0
				won = data.stats.wins or 0
				played = won + (data.stats.losses or 0)
			end
			if btn.Tier and btn.Tier.Icon then btn.Tier.Icon:SetTexture(GetTier(rating).icon) end
			if btn.CurrentRating then btn.CurrentRating:SetText(tostring(rating)) end
			if btn.Winrate then
				local winrate = played > 0 and math.floor(100 * won / played) or 0
				btn.Winrate:SetText(format("%d - %d (%.1f%%)", won, played - won, winrate))
			end
			UpdateRankOverlay(btn, rating, data.bracket)
		end
	end

	-- B. Arena1Button (Skirmish)
	local c = ns.GetMySkirmishData and ns.GetMySkirmishData()
	local has = c and (tonumber(c.rating) or 0) > 0 and (tonumber(c.played) or 0) > 0
	if not has and myGuid and ns.SkirmishDB then
		local rec = ns.SkirmishDB[myGuid]
		if rec and (tonumber(rec.rating) or 0) > 0 then c = rec; has = true end
	end
	local skirmishRating = has and (tonumber(c.rating) or 0) or 0
	local skirmishPlayed = has and (tonumber(c.played) or 0) or 0
	local skirmishWon = has and (tonumber(c.won) or 0) or 0
	local arenaBtn = HonorFrame.BonusFrame.Arena1Button
	if arenaBtn then
		if arenaBtn.Tier and arenaBtn.Tier.Icon then arenaBtn.Tier.Icon:SetTexture(GetTier(skirmishRating).icon) end
		if arenaBtn.CurrentRating then arenaBtn.CurrentRating:SetText(tostring(skirmishRating)) end
		if arenaBtn.Winrate then
			local winrate = skirmishPlayed > 0 and math.floor(100 * skirmishWon / skirmishPlayed) or 0
			arenaBtn.Winrate:SetText(format("%d - %d (%.1f%%)", skirmishWon, skirmishPlayed - skirmishWon, winrate))
		end
		UpdateRankOverlay(arenaBtn, skirmishRating, "SKIRMISH")
	end
end

local function UpdateTierFrame()
	if not IsReady() then return end
	local bestRating = GetBestRating()
	if PVPQueueFrame and PVPQueueFrame.HonorInset and PVPQueueFrame.HonorInset.CasualPanel then
		local tf = PVPQueueFrame.HonorInset.CasualPanel.Tier
		if tf then
			local bestTier = GetTier(bestRating)
			tf.Icon:SetTexture(bestTier.icon)
			tf.currentTierName = bestTier.name
			if bestTier.min < 2300 then
				local tierMap = {[0]=1, [1000]=2, [1200]=3, [1400]=4, [1600]=5, [1800]=6, [1950]=7, [2100]=8}
				local nextIdx = tierMap[bestTier.min] + 1
				local nt = ns.PvPTiers[nextIdx]
				if nt then
					tf.NextTier:Show()
					tf.NextTier.Icon:SetTexture(nt.icon)
					tf.nextTierName = nt.name
					tf.nextTierRating = nt.min
				else
					tf.NextTier:Hide()
				end
			else
				tf.NextTier:Hide()
			end
		end
	end
end

-- ============================================================================
-- 6. BUTTON STATS & TOOLTIPS
-- ============================================================================
local function GetButtonStats(key)
	if key == "Arena1Button" then
		local c = ns.GetMySkirmishData and ns.GetMySkirmishData()
		local has = c and (tonumber(c.rating) or 0) > 0 and (tonumber(c.played) or 0) > 0
		if not has then
			local guid = UnitGUID("player")
			if guid and ns.SkirmishDB then
				local rec = ns.SkirmishDB[guid]
				if rec and (tonumber(rec.rating) or 0) > 0 then
					c = { rating = tonumber(rec.rating) or 0, played = tonumber(rec.played) or 0,
						  won = tonumber(rec.won) or 0, bestRating = tonumber(rec.bestRating) or 0 }
					has = true
				end
			end
		end
		local wp, ww, wb = GetWeeklyArenaStats()
		return {
			rating = has and (c.rating or 0) or 0, seasonBest = has and (c.bestRating or c.rating) or 0,
			seasonWon = has and c.won or 0, seasonPlayed = has and c.played or 0,
			weeklyBest = wb, weeklyWon = ww, weeklyPlayed = wp
		}
	end
	
	local typeSet = BUTTON_MATCH_TYPES[key]
	local season, weekly = { played = 0, won = 0 }, { played = 0, won = 0 }
	if typeSet then season, weekly = AggregateArchiveForTypes(typeSet) end
	
	local rating, seasonBest, weeklyBest = 0, 0, 0
	if ns.GetArchiveStatsForGuid then
		local stats = ns.GetArchiveStatsForGuid(UnitGUID("player"))
		if stats then
			local bucket
			if key == "RandomBGButton" then bucket = stats.randomBG
			elseif key == "SoloShuffleButton" then bucket = stats.soloShuffle
			elseif key == "Arena5v5Button" then bucket = stats.wargame end
			if bucket then
				rating = bucket.rating or 0
				seasonBest = bucket.bestRating or rating
				weeklyBest = bucket.weeklyBestRating or rating 
			end
		end
	end
	return {
		rating = rating, seasonBest = seasonBest,
		seasonWon = season.won, seasonPlayed = season.played,
		weeklyBest = weeklyBest, weeklyWon = weekly.won, weeklyPlayed = weekly.played
	}
end

local function GetButtonMeta(key)
	for _, group in pairs(BUTTONS) do if group[key] then return group[key] end end
end

-- ============================================================================
-- 7. UI SETUP (BUTTONS, TIERFRAME, FAKE QUEUE)
-- ============================================================================
local function CreateTierFrame()
	if not (PVPQueueFrame and PVPQueueFrame.HonorInset and PVPQueueFrame.HonorInset.CasualPanel) then return end
	local casualPanel = PVPQueueFrame.HonorInset.CasualPanel
	if casualPanel.Tier then return end
	local honorLevelDisplay = casualPanel.HonorLevelDisplay
	if not honorLevelDisplay then return end
	local tierFrame = CreateFrame("Frame", nil, casualPanel, "TierFrame")
	tierFrame:SetPoint("TOP", honorLevelDisplay, "BOTTOM", 0, -70)
	casualPanel.Tier = tierFrame
end

local function SetupAllButtons()
	local bf = HonorFrame.BonusFrame
	bf.WorldBattlesTexture:SetAtlas("pvpqueue-background-rated")
	bf.BrawlButton:Hide()
	bf.BrawlButton2:HookScript("OnShow", function(self) if self:IsShown() then self:Hide() end end)
	
	local function GetAllButtonKeys()
		local k = {}
		for key in pairs(BUTTONS.regular) do k[#k + 1] = key end
		for key in pairs(BUTTONS.custom) do k[#k + 1] = key end
		return k
	end

	for _, key in ipairs(GetAllButtonKeys()) do
		local isCustom = BUTTONS.custom[key] ~= nil
		local btn = bf[key]
		if not btn and isCustom then
			btn = CreateFrame("Button", nil, bf, "PvP20RatingButtonTemplate")
			btn.key = key
			bf[key] = btn
		end
		if btn then
			local meta = GetButtonMeta(key)
			btn:SetPushedAtlas("pvpqueue-button-down")
			btn:SetNormalAtlas("pvpqueue-button-up")
			btn:SetHighlightAtlas("pvpqueue-button-highlight", "ADD")
			btn.SelectedTexture:SetAtlas("pvpqueue-button-selected")
			btn:HookScript("OnSizeChanged", function(self, width, height)
				if width ~= 365 or height ~= 56 then
					self:SetSize(365, 56)
					self.Anchor:SetSize(365, 56)
				end
			end)
			if btn.Reward then
				btn.Reward:SetPoint("RIGHT", btn.Anchor, "RIGHT", -16, -2)
			end
			if meta and meta.sizeText then
				if not btn.TeamSizeText then
					if btn.Title then btn.Title:Hide() end
					btn.TeamSizeText = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
					btn.TeamSizeText:SetPoint("LEFT", btn.Anchor, 20, 7)

					btn.TeamTypeText = btn:CreateFontString(nil, "ARTWORK", "GameFontDisable")
					btn.TeamTypeText:SetPoint("LEFT", btn.Anchor, 19, 0)
					btn.TeamTypeText:SetPoint("TOP", btn.TeamSizeText, "BOTTOM", 0, -3)

					btn.TierIcon = btn:CreateTexture(nil, "ARTWORK")
					btn.TierIcon:SetSize(40, 40)
					btn.TierIcon:SetPoint("CENTER", btn.Anchor, -4, -1)

					btn.Tier = btn.Tier or CreateFrame("Frame", nil, btn, "PVPTierTemplate")
					btn.Tier:SetPoint("CENTER", btn.Anchor, -4, -1)

					btn.CurrentRating = btn:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
					btn.CurrentRating:SetPoint("LEFT", btn.TierIcon, "RIGHT", 4, 0)

					btn.Winrate = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
					btn.Winrate:SetPoint("TOPLEFT", btn.CurrentRating, "BOTTOMLEFT", 0, 0)
				end
				btn.TeamSizeText:SetText(meta.sizeText)
				if meta.typeText then
					btn.TeamTypeText:SetText(meta.typeText)
				end
				btn.Tier.Icon:SetTexture(2023043)
				btn.CurrentRating:SetText("0")
				btn.Winrate:SetText("0 - 0 (0.0%)")
			end
		end
	end
end

local function SetCustomPoints()
	local buttons = {
		"RandomBGButton",
		"Arena1Button",
		"RandomEpicBGButton",
		"BrawlButton",
		"BrawlButton2",
		"SoloShuffleButton",
		"Arena5v5Button"
	}
	local function Layout()
		local prev
		for _, key in ipairs(buttons) do
			local btn = HonorFrame.BonusFrame[key]
			if btn and btn:IsShown() then
				btn:ClearAllPoints()
				if not prev then btn:SetPoint("TOP", HonorFrame.BonusFrame, "TOP", 0, -8)
				else btn:SetPoint("TOP", prev, "BOTTOM", 0, 0) end
				prev = btn
			end
		end
	end
	Layout()
	for _, key in ipairs(buttons) do
		local btn = HonorFrame.BonusFrame[key]
		if btn then btn:HookScript("OnShow", Layout); btn:HookScript("OnHide", Layout) end
	end
end

local FakeQueueButton
local function UpdateFakeQueueButton()
	if not FakeQueueButton then return end
	local bf = HonorFrame.BonusFrame
	local isCustom, selectedKey = false, nil
	for key in pairs(BUTTONS.custom) do
		if bf.customSelectedButton == bf[key] then isCustom = true; selectedKey = key; break end
	end
	
	if isCustom then
		HonorFrame.QueueButton:Hide()
		FakeQueueButton:Show()
		FakeQueueButton:SetText(selectedKey == "SoloShuffleButton" and BATTLEFIELD_JOIN or HonorFrame.QueueButton:GetText())
		if selectedKey == "Arena5v5Button" and IsInGroup(1) and not UnitIsGroupLeader("player", 1) then
			FakeQueueButton:Disable()
		else
			FakeQueueButton:Enable()
		end
	else
		FakeQueueButton:Hide()
		HonorFrame.QueueButton:Show()
	end
end

local function OnCustomQueueClick(btnKey)
	if btnKey == "SoloShuffleButton" then
		ns.JoinSoloShuffle()
	elseif btnKey == "Arena5v5Button" then
		ns.JoinArena5v5()
	end
end

local function SetupFakeQueueButton()
	local bf = HonorFrame.BonusFrame
	if FakeQueueButton then return end
	local real = HonorFrame.QueueButton
	if not real then return end
	FakeQueueButton = CreateFrame("Button", "HonorFrame.QueueButton", HonorFrame, "UIPanelButtonTemplate")
	FakeQueueButton:SetAllPoints(real)
	FakeQueueButton:SetText(real:GetText())
	FakeQueueButton:Hide()
	FakeQueueButton:SetMotionScriptsWhileDisabled(true)
	FakeQueueButton:SetScript("OnClick", function()
		for key in pairs(BUTTONS.custom) do
			if bf.customSelectedButton == bf[key] then
				OnCustomQueueClick(key)
				break
			end
		end
	end)
	FakeQueueButton:SetScript("OnEnter", function(self)
		local isSoloShuffle = false
		for key in pairs(BUTTONS.custom) do
			if bf.customSelectedButton == bf[key] and key == "SoloShuffleButton" then
				isSoloShuffle = true
				break
			end
		end
		if not isSoloShuffle and IsInGroup(1) and not UnitIsGroupLeader("player", 1) then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(ERR_NOT_LEADER, 1, 0, 0, 1, 1)
			GameTooltip:Show()
		end
	end)
	FakeQueueButton:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	for key in pairs(BUTTONS.regular) do
		local realBtn = HonorFrame.BonusFrame[key]
		if realBtn then
			realBtn:HookScript("OnClick", function(self)
				if bf.customSelectedButton then
					bf.customSelectedButton.SelectedTexture:Hide()
					bf.customSelectedButton = nil
					if not self.SelectedTexture:IsShown() then
						self.SelectedTexture:Show()
					end
				end
				UpdateFakeQueueButton()
			end)
			realBtn.SelectedTexture:HookScript("OnShow", function(self)
				if bf.customSelectedButton and self:IsShown() then
					self:Hide()
				end
			end)
		end
	end
	UpdateFakeQueueButton()
end

local function SelectCustomButton(key)
	if not IsReady() then return false end
	local bf = HonorFrame.BonusFrame
	local btn = HonorFrame.BonusFrame[key]
	if not btn or bf.customSelectedButton == btn then return false end
	if bf.customSelectedButton then
		bf.customSelectedButton.SelectedTexture:Hide()
	end
	btn.SelectedTexture:Show()
	bf.customSelectedButton = btn
	if bf.selectedButton then
		bf.selectedButton.SelectedTexture:Hide()
		bf.selectedButton = nil
	end
	UpdateFakeQueueButton()
	return true
end

-- ============================================================================
-- 8. XML CALLBACKS (GLOBAL)
-- ============================================================================
function _G.CustomButton_OnClick(self)
	SelectCustomButton(self.key)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

function _G.CustomButton_OnEnter(self)
	_G.PvP20RatingButton_OnEnter(self)
end

function _G.CustomButton_OnLeave(self)
	_G.PvP20RatingButton_OnLeave(self)
end

function _G.PvP20RatingButton_OnEnter(self)
	if self.HighlightTexture then self.HighlightTexture:Show() end
	if not PvP20RatingTooltip then return end
	if GameTooltip then GameTooltip:Hide() end
	
	local key = self.key
	local meta = GetButtonMeta(key)
	local s = GetButtonStats(key)
	local t = PvP20RatingTooltip
	local isShuffle = (key == "SoloShuffleButton")
	
	t.Title:SetText((meta and (meta.tooltipTitle or meta.sizeText)) or PVP_RANK_0_NAME)
	local tierName = ns.PvPTiers[1].name
	for _, tier in ipairs(ns.PvPTiers) do
		if s.rating >= tier.min and s.rating <= tier.max then tierName = tier.name; break end
	end
	t.Tier:SetText(tierName .. " (" .. s.rating .. ")")
	
	t.WeeklyLabel:SetText(ARENA_WEEKLY_STATS)
	t.WeeklyBest:SetText(PVP_BEST_RATING .. s.weeklyBest)
	t.WeeklyWon:SetText(isShuffle and (PVP_ROUNDS_WON .. s.weeklyWon) or (PVP_GAMES_WON .. s.weeklyWon))
	t.WeeklyPlayed:SetText(isShuffle and (PVP_ROUNDS_PLAYED .. s.weeklyPlayed) or (PVP_GAMES_PLAYED .. s.weeklyPlayed))
	
	t.SeasonLabel:SetText(ARENA_SEASON_STATS)
	t.SeasonBest:SetText(PVP_BEST_RATING .. s.seasonBest)
	t.SeasonWon:SetText(isShuffle and (PVP_ROUNDS_WON .. s.seasonWon) or (PVP_GAMES_WON .. s.seasonWon))
	t.SeasonPlayed:SetText(isShuffle and (PVP_ROUNDS_PLAYED .. s.seasonPlayed) or (PVP_GAMES_PLAYED .. s.seasonPlayed))
	
	t.ModeDescription:SetWidth(t.maximumWidth - 40)
	t.ModeDescription:SetText((meta and meta.tooltipBody) or "")
	t.ModeDescription:SetShown((meta and meta.tooltipBody) ~= nil)
	
	t:ClearAllPoints()
	t:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", 0, 0)
	if t.Layout then
		t:Layout()
	end
	t:Show()
end

function _G.PvP20RatingButton_OnLeave(self)
	if self.HighlightTexture then self.HighlightTexture:Hide() end
	if PvP20RatingTooltip then PvP20RatingTooltip:Hide() end
end

function _G.TierFrame_OnLoad(self)
	self.Icon:SetTexture(2023043)
	self.currentTierName = PVP_RANK_0_NAME
end

function _G.TierFrame_OnEnter(self)
	if self.currentTierName then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, self.currentTierName)
		GameTooltip:Show()
	end
end

function _G.TierFrame_NextTier_OnEnter(self)
	local f = self:GetParent()
	if f.nextTierName then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local text = TOOLTIP_PVP_NEXT_RANK:format(f.nextTierName) .. " (" .. tostring(f.nextTierRating) .. ")"
		GameTooltip_SetTitle(GameTooltip, text)
		GameTooltip:Show()
	end
end

-- ============================================================================
-- 9. MAIN SETUP & EVENTS
-- ============================================================================
local function SetupBonusFrame()
	if not IsReady() or HonorFrame.BonusFrame.setupDone then return end
	SetupAllButtons()
	CreateTierFrame()
	UpdateTierFrame()
	UpdateQueueButtonsStats()
	SetCustomPoints()
	SetupFakeQueueButton()
	
	local bf = HonorFrame.BonusFrame
	local tooltipButtons = {
		"RandomBGButton",
		"Arena1Button",
		"SoloShuffleButton",
		"Arena5v5Button"
	}
	for _, key in ipairs(tooltipButtons) do
		local btn = bf[key]
		if btn then
			btn.key = key
			btn:HookScript("OnEnter", function(b)
				if GameTooltip then GameTooltip:Hide() end
				_G.PvP20RatingButton_OnEnter(b)
			end)
			btn:HookScript("OnLeave", _G.PvP20RatingButton_OnLeave)
		end
	end
	
	HonorFrame:HookScript("OnShow", function()
		EnsureWeeklyFresh()
		UpdateQueueButtonsStats()
		UpdateTierFrame()
		if HonorFrame:IsShown() and CanInspect("player") and not (InspectFrame and InspectFrame:IsShown()) then
			NotifyInspect("player")
		end
	end)
	HonorFrame.BonusFrame.setupDone = true
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("INSPECT_READY")
f:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == addonName then
			InitWeeklyDB()
		elseif arg1 == "Blizzard_PVPUI" then
			SetupBonusFrame()
		end
	elseif event == "INSPECT_READY" and arg1 == UnitGUID("player") then
		UpdateQueueButtonsStats()
		UpdateTierFrame()
		if GetInspectArenaData then
			local r, _, _, wp, ww = GetInspectArenaData(5)
			if (tonumber(r) or 0) > 0 then
				RecordWeeklyArenaRating(r, wp, ww)
			end
		end
	end
end)

-- ============================================================================
-- 10. EXPORTS
-- ============================================================================
ns.MainUI = {
	SelectCustomButton = SelectCustomButton,
	UpdateQueueButtonsStats = UpdateQueueButtonsStats,
	RecordWeeklyArenaRating = RecordWeeklyArenaRating,
}