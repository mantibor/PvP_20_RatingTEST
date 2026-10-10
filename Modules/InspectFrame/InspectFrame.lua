local addonName, ns = ...

-- ============================================================================
-- UI UPDATE LOGIC
-- ============================================================================
local function IsInspectLevelValid()
	local unit = InspectFrame and InspectFrame.unit or "target"
	return ns.IsLevel(UnitLevel(unit))
end

local function UpdateVisibility()
	if not InspectPVPFrame or not InspectPvP20RatingFrame then return false end
	local isLvl = IsInspectLevelValid()
	
	local frames = {
		InspectPVPFrame.RatedBG,
		InspectPVPFrame.RatedSoloShuffle,
		InspectPVPFrame.RatedBGBlitz,
		InspectPVPFrame.Arena2v2,
		InspectPVPFrame.Arena3v3
	}
	for _, frame in ipairs(frames) do
		if frame then frame:SetShown(not isLvl) end
	end
	
	InspectPvP20RatingFrame:SetShown(isLvl)
	return isLvl
end

local function UpdateFrameData(frame, rating, won, lost)
	if not frame then return end
	rating = rating or 0
	won = won or 0
	lost = lost or 0
	local played = won + lost
	local wr = played > 0 and math.floor(100 * won / played) or 0
	
	frame.Rating:SetText(format("%d", rating))
	frame.Record:SetText(format("%d-%d", won, lost))
	frame.Winrate:SetText(format("(%d%%)", wr))
end

-- Экспортируем в _G, чтобы XML мог вызвать эту функцию через <OnLoad function="..."/>
function _G.InspectPvP20Rating_UpdateAllData()
	if not UpdateVisibility() then return end
	local frame = InspectPvP20RatingFrame
	if not frame or not frame:IsVisible() then return end
	
	local unit = InspectFrame and InspectFrame.unit or "target"
	if not UnitExists(unit) then return end
	local guid = UnitGUID(unit)
	
	-- Update SkirmishArena
	if frame.SkirmishArena then
		local rating, played, won = GetInspectArenaData(5)
		-- Fallback to cache if inspect returned zeros
		if not played or played == 0 then
			if guid and ns.SkirmishDB then
				local rec = ns.SkirmishDB[guid]
				if rec and (tonumber(rec.rating) or 0) > 0 then
					rating = tonumber(rec.rating) or 0
					played = tonumber(rec.played) or 0
					won    = tonumber(rec.won) or 0
				end
			end
		end
		UpdateFrameData(frame.SkirmishArena, rating, won, (played or 0) - (won or 0))
	end
	
	-- Update database-backed stats (RandomBG, SoloShuffle, Wargames)
	local stats = guid and ns.GetArchiveStatsForGuid and ns.GetArchiveStatsForGuid(guid)
	if stats then
		UpdateFrameData(frame.RandomBG, 
			stats.randomBG and stats.randomBG.rating,
			stats.randomBG and stats.randomBG.wins,
			stats.randomBG and stats.randomBG.losses)
		UpdateFrameData(frame.SoloShuffle,
			stats.soloShuffle and stats.soloShuffle.rating,
			stats.soloShuffle and stats.soloShuffle.wins,
			stats.soloShuffle and stats.soloShuffle.losses)
		UpdateFrameData(frame.Wargames,
			stats.wargame and stats.wargame.rating,
			stats.wargame and stats.wargame.wins,
			stats.wargame and stats.wargame.losses)
	end
end

-- ============================================================================
-- ATTACH & EVENTS
-- ============================================================================
local attached
local function AttachToInspectFrame()
	if attached or not InspectPVPFrame or not InspectPvP20RatingFrame then return end
	attached = true
	
	InspectPvP20RatingFrame:SetParent(InspectPVPFrame)
	InspectPvP20RatingFrame:SetPoint("TOPLEFT", InspectPVPFrame.BG, "TOPLEFT", 0, -45)
	
	hooksecurefunc("InspectPVPFrame_Update", _G.InspectPvP20Rating_UpdateAllData)
	UpdateVisibility()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("INSPECT_READY")
f:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == "Blizzard_InspectUI" then
		AttachToInspectFrame()
	elseif event == "INSPECT_READY" then
		_G.InspectPvP20Rating_UpdateAllData()
	end
end)