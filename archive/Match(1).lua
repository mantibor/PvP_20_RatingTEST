local addonName, ns = ...

local liveSnapshot = {}
local snapshotActive = false
local currentMatchType = nil

local UNIT_EVENT_TO_UNIT = {
	PLAYER_TARGET_CHANGED = "target",
	PLAYER_FOCUS_CHANGED = "focus",
	UPDATE_MOUSEOVER_UNIT = "mouseover",
	NAME_PLATE_UNIT_ADDED = true,
	ARENA_OPPONENT_UPDATE = true,
}

local UNIT_FRAME_EVENTS = {}
for ev in pairs(UNIT_EVENT_TO_UNIT) do
	UNIT_FRAME_EVENTS[#UNIT_FRAME_EVENTS + 1] = ev
end

-- ============================================================================
-- MATCH TYPE & SNAPSHOT
-- ============================================================================
function ns.GetMatchType()
	if not IsWargame() and C_PvP.IsBattleground() and not C_PvP.IsRatedBattleground() then
		return "random_bg"
	end
	if IsWargame() and C_PvP.IsArena() then
		if C_PvP.IsSoloShuffle() then
			return "solo_shuffle"
		end
		local perFaction = {}
		local numScores = GetNumBattlefieldScores() or 0
		for i = 1, numScores do
			local ok, score = pcall(C_PvP.GetScoreInfo, i)
			if ok and score and score.faction then
				perFaction[score.faction] = (perFaction[score.faction] or 0) + 1
				if perFaction[score.faction] == 5 then
					return "arena_5v5"
				end
			end
		end
	end
end

function ns.SampleScoreboard()
	ns.ScanGroupForBlacklist()
	local numScores = GetNumBattlefieldScores() or 0
	for i = 1, numScores do
		local ok, score = pcall(C_PvP.GetScoreInfo, i)
		if ok and score and score.name and score.name ~= "" then
			local playerName = ns.FormatNameRealm(score.name) or score.name
			if playerName then
				local guid = ns.SafeGuid(score.guid)
				local key = guid or playerName
				local row = { name = playerName, guid = guid, class = score.classToken, faction = score.faction }
				if type(score.stats) == "table" then
					local stats = {}
					for idx, stat in ipairs(score.stats) do
						if stat and stat.pvpStatValue and not (issecretvalue and issecretvalue(stat.pvpStatValue)) then
							stats[idx] = { pvpStatID = stat.pvpStatID, pvpStatValue = stat.pvpStatValue }
						end
					end
					row.stats = stats
				end
				liveSnapshot[key] = row
			end
		end
	end
end

function ns.SetSnapshotActive(on, matchType)
	snapshotActive = on and true or false
	if on then
		currentMatchType = matchType or ns.GetMatchType()
	else
		wipe(liveSnapshot)
	end
end

local function CheckUnitForBlacklist(unit)
	if not snapshotActive then return end
	local _, instanceType = GetInstanceInfo()
	if instanceType ~= "arena" and instanceType ~= "pvp" then return end
	if not UnitExists(unit) or not UnitIsPlayer(unit) or not UnitCanAttack("player", unit) or UnitIsUnit(unit, "player") then return end
	local unitName, unitRealm = UnitName(unit)
	if issecretvalue and issecretvalue(unitName) then return end
	local unitFullName = ns.FormatNameRealm(unitName, unitRealm)
	if not unitFullName then return end
	for _, row in pairs(liveSnapshot) do
		if row.name == unitFullName then ns.AddToBlacklist(unitFullName); return end
	end
end

-- ============================================================================
-- MATCH COMPLETE HANDLERS
-- ============================================================================
local function GetScoreRows()
	local rows = {}
	local total = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
	for i = 1, total do
		local ok, score = pcall(C_PvP.GetScoreInfo, i)
		if ok and score then rows[#rows + 1] = score end
	end
	return rows
end

local function UpdateSkirmishDBOnMatchComplete()
	if not IsArenaSkirmish() then return end
	local rows = GetScoreRows()
	if #rows == 0 then return end
	local myGuid = UnitGUID("player")
	local myFaction
	for _, s in ipairs(rows) do
		if ns.SafeGuid(s.guid) == myGuid then myFaction = s.faction; break end
	end
	if myFaction == nil then myFaction = 0 end
	local winnerFaction
	if GetBattlefieldWinner then
		local w = GetBattlefieldWinner()
		if w == 0 or w == 1 then winnerFaction = w end
	end

	local allySum, allyN, enemySum, enemyN = 0, 0, 0, 0
	for _, s in ipairs(rows) do
		local rec = ns.SkirmishDB[ns.SafeGuid(s.guid)]
		local r = rec and tonumber(rec.rating)
		if r and r > 0 then
			if s.faction == myFaction then allySum, allyN = allySum + r, allyN + 1
			else enemySum, enemyN = enemySum + r, enemyN + 1 end
		end
	end
	local BASELINE = 1500
	local effAllyAvg = allyN > 0 and math.floor(allySum / allyN + 0.5) or BASELINE
	local effEnemyAvg = enemyN > 0 and math.floor(enemySum / enemyN + 0.5) or BASELINE
	local recency = time()

	for _, s in ipairs(rows) do
		local guid = ns.SafeGuid(s.guid)
		if guid then
			local isAlly = (s.faction == myFaction)
			local won = (winnerFaction ~= nil) and (s.faction == winnerFaction)
			local oldRec = ns.SkirmishDB[guid]
			local old = oldRec and tonumber(oldRec.rating) or 0
			local has = oldRec and (tonumber(oldRec.played) or 0) > 0
			local newRating = ns.ComputeNewRatingSkirmish(old, has, won, isAlly and effEnemyAvg or effAllyAvg, isAlly and effAllyAvg or effEnemyAvg)
			local name = (oldRec and oldRec.name) or ns.FormatNameRealm(s.name) or s.name
			local prevPlayed = (oldRec and tonumber(oldRec.played)) or 0
			local prevWon = (oldRec and tonumber(oldRec.won)) or 0
			local prevBest = (oldRec and tonumber(oldRec.bestRating)) or 0
			ns.SaveSharedData(guid, name, newRating, prevPlayed + 1, prevWon + (won and 1 or 0), (oldRec and oldRec.class) or s.classToken, recency, prevBest)
		end
	end
end

function ns.HandleMatchStateChanged(frame)
	local isLvl = (UnitLevel("player") == 20 or UnitLevel("player") == 21)
	local state = C_PvP.GetActiveMatchState and C_PvP.GetActiveMatchState()
	if state == Enum.PvPMatchState.Engaged and isLvl then
		local mt = ns.GetMatchType()
		if mt then
			ns.SetSnapshotActive(true, mt)
			ns.SampleScoreboard()
			for _, ev in ipairs(UNIT_FRAME_EVENTS) do frame:RegisterEvent(ev) end
		else ns.SetSnapshotActive(false) end
	else
		ns.SetSnapshotActive(false)
		for _, ev in ipairs(UNIT_FRAME_EVENTS) do frame:UnregisterEvent(ev) end
	end
end

function ns.HandleMatchComplete()
	if C_Commentator and C_Commentator.IsSpectating and C_Commentator.IsSpectating() then return end
	local lvl = UnitLevel("player")
	if lvl ~= 20 and lvl ~= 21 then ns.SetSnapshotActive(false); return end
	ns.ScanGroupForBlacklist()
	if IsArenaSkirmish() then C_Timer.After(0.1, UpdateSkirmishDBOnMatchComplete) end
	
	local mt = currentMatchType or ns.GetMatchType()
	if not mt then ns.SetSnapshotActive(false); return end
	currentMatchType = nil
	
	local db = { matchType = mt, scores = {} }
	if C_PvP.GetActiveMatchWinner then
		local ok, w = pcall(C_PvP.GetActiveMatchWinner)
		if ok and (w == 0 or w == 1) and not (issecretvalue and issecretvalue(w)) then db.winner = w end
	end
	ns.SampleScoreboard()
	for key, row in pairs(liveSnapshot) do
		local score = { guid = row.guid, name = row.name, class = row.class, faction = row.faction }
		if db.matchType == "solo_shuffle" and row.stats then score.stats = row.stats end
		db.scores[key] = score
	end
	wipe(liveSnapshot)
	ns.SetSnapshotActive(false)
	
	local playerCount = 0
	for _ in pairs(db.scores) do playerCount = playerCount + 1 end
	if playerCount < 16 then return end
	
	local matchDB = ns.GetMatchDB()
	local ts = math.floor(GetServerTime() / 180) * 180
	while matchDB[ts] do ts = ts + 1 end
	matchDB[ts] = db
	table.insert(ns.ArchiveSortedKeys, ts)
	table.sort(ns.ArchiveSortedKeys)
	
	if ns.UpdateQueueButtonsStats then ns.UpdateQueueButtonsStats() end
	C_Timer.After(1, function()
		local blob = ns.EncodeEntry(db)
		if blob then ns.ArchiveCache[ts] = db; matchDB[ts] = blob end
	end)
end

-- ============================================================================
-- EVENT FRAME: Обработка событий матча
-- ============================================================================
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PVP_MATCH_STATE_CHANGED")
f:RegisterEvent("PVP_MATCH_COMPLETE")

f:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" or event == "PVP_MATCH_STATE_CHANGED" then
        ns.HandleMatchStateChanged(self)
    elseif event == "PVP_MATCH_COMPLETE" then
        ns.HandleMatchComplete()
    elseif UNIT_EVENT_TO_UNIT[event] then
        local src = UNIT_EVENT_TO_UNIT[event]
        if src == true then
            if arg1 then CheckUnitForBlacklist(arg1) end
        else
            CheckUnitForBlacklist(src)
        end
    end
end)