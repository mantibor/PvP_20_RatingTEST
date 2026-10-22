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
-- CUSTOM SOLO SHUFFLE ROUND TRACKER (Fallback для бага Blizzard API)
-- ============================================================================
local ShuffleTracker = {
	active = false,
	winsStatID = 1032, -- Стандартный pvpStatID для побед в Solo Shuffle
	lastStats = {},    -- [guid] = { [statID] = value }
	trackedWins = {},  -- [guid] = number (накопленные победы)
}

local function ResetShuffleTracker()
	ShuffleTracker.active = false
	ShuffleTracker.lastStats = {}
	ShuffleTracker.trackedWins = {}
end

local function UpdateShuffleTracker()
	if not ShuffleTracker.active then return end
	
	local numScores = GetNumBattlefieldScores() or 0
	for i = 1, numScores do
		local ok, score = pcall(C_PvP.GetScoreInfo, i)
		if ok and score and score.guid and score.stats then
			local guid = score.guid
			local last = ShuffleTracker.lastStats[guid] or {}
			
			for _, stat in ipairs(score.stats) do
				local id = stat.pvpStatID
				local val = stat.pvpStatValue or 0
				local lastVal = last[id] or 0
				
				-- Если это стат побед и он увеличился -> фиксируем раунд
				if id == ShuffleTracker.winsStatID and val > lastVal then
					ShuffleTracker.trackedWins[guid] = (ShuffleTracker.trackedWins[guid] or 0) + (val - lastVal)
				end
				
				last[id] = val
			end
			ShuffleTracker.lastStats[guid] = last
		end
	end
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
		if ns.SafeGuid(s.guid) == myGuid then
			myFaction = s.faction
			break
		end
	end
	if myFaction == nil then myFaction = 0 end
	
	local winnerFaction
	if GetBattlefieldWinner then
		local w = GetBattlefieldWinner()
		if w == 0 or w == 1 then winnerFaction = w end
	end
	
	local allyGuids = {}
	local enemyGuids = {}
	for _, s in ipairs(rows) do
		local guid = ns.SafeGuid(s.guid)
		if guid then
			if s.faction == myFaction then allyGuids[#allyGuids + 1] = guid
			else enemyGuids[#enemyGuids + 1] = guid end
		end
	end
	
	-- соперник каждого — средний по другой команде (у врагов это наши)
	local enemyAvgRating, enemyAvgRD = ns.GetTeamGlicko2Average(enemyGuids, "SKIRMISH")
	local allyAvgRating, allyAvgRD = ns.GetTeamGlicko2Average(allyGuids, "SKIRMISH")
	
	local recency = time()
	local result = {}
	for _, s in ipairs(rows) do
		local guid = ns.SafeGuid(s.guid)
		if guid then
			local won = (winnerFaction ~= nil) and (s.faction == winnerFaction)
			local ally = (s.faction == myFaction)
			local before = ns.SkirmishDB[guid] and tonumber(ns.SkirmishDB[guid].rating) or 0
			local newRating, newRD = ns.UpdateGlicko2Rating(guid, ally and enemyAvgRating or allyAvgRating,
				ally and enemyAvgRD or allyAvgRD, won, "SKIRMISH")
			result[guid] = { old = before, new = newRating }
			
			local rec = ns.SkirmishDB[guid]
			local name = (rec and rec.name) or (ns.FormatNameRealm and ns.FormatNameRealm(s.name)) or s.name
			local prevBest = (rec and tonumber(rec.bestRating)) or 0
			local class = (rec and rec.class) or s.classToken
			
			ns.SaveSharedData(guid, name, newRating, (rec and tonumber(rec.played) or 0) + 1, 
				(rec and tonumber(rec.won) or 0) + (won and 1 or 0), class, recency, prevBest)
		end
	end
	-- новый рейтинг записан в базу — теперь его показывает таблица итогов (Scoreboard.lua)
	ns.LastSkirmishResult = result
	if ns.OnMatchSaved then ns.OnMatchSaved() end
end

function ns.HandleMatchStateChanged(frame)
	local isLvl = (UnitLevel("player") == 20 or UnitLevel("player") == 21)
	local state = C_PvP.GetActiveMatchState and C_PvP.GetActiveMatchState()
	
	if state == Enum.PvPMatchState.Engaged and isLvl then
		-- новый матч: итоги прошлого в таблице не показывать
		ns.MatchArchived, ns.LastSkirmishResult = false, nil
		local mt = ns.GetMatchType()
		if mt then
			ns.SetSnapshotActive(true, mt)
			ns.SampleScoreboard()
			
			-- 🌟 ЗАПУСК ТРЕКЕРА ДЛЯ SOLO SHUFFLE
			if mt == "solo_shuffle" then
				ResetShuffleTracker()
				ShuffleTracker.active = true
			end
			
			for _, ev in ipairs(UNIT_FRAME_EVENTS) do frame:RegisterEvent(ev) end
		else 
			ns.SetSnapshotActive(false) 
		end
	else
		ns.SetSnapshotActive(false)
		ResetShuffleTracker() -- 🌟 СБРОС ТРЕКЕРА
		for _, ev in ipairs(UNIT_FRAME_EVENTS) do frame:UnregisterEvent(ev) end
	end
end

function ns.HandleMatchComplete()
	if C_Commentator and C_Commentator.IsSpectating and C_Commentator.IsSpectating() then return end
	
	local lvl = UnitLevel("player")
	if lvl ~= 20 and lvl ~= 21 then 
		ns.SetSnapshotActive(false)
		ResetShuffleTracker()
		return 
	end
	
	ns.ScanGroupForBlacklist()
	if IsArenaSkirmish() then C_Timer.After(0.1, UpdateSkirmishDBOnMatchComplete) end
	
	local mt = currentMatchType or ns.GetMatchType()
	if not mt then 
		ns.SetSnapshotActive(false)
		ResetShuffleTracker()
		return 
	end
	
	currentMatchType = nil
	local db = { matchType = mt, scores = {} }
	
	-- у соло-суматохи нет фракций: ни победителя-фракции, ни фракции игрока не храним
	local isShuffle = (mt == "solo_shuffle")
	if not isShuffle and C_PvP.GetActiveMatchWinner then
		local ok, w = pcall(C_PvP.GetActiveMatchWinner)
		if ok and (w == 0 or w == 1) and not (issecretvalue and issecretvalue(w)) then db.winner = w end
	end
	
	ns.SampleScoreboard()
	
	-- 🌟 ФОРМИРОВАНИЕ SCORES С ИНЖЕКЦИЕЙ ДАННЫХ ТРЕКЕРА
	for key, row in pairs(liveSnapshot) do
		local score = { guid = row.guid, name = row.name, class = row.class, faction = not isShuffle and row.faction or nil }
		
		if db.matchType == "solo_shuffle" then
			local finalWins = nil
			
			-- 1. Пытаемся взять из финального снепшота (если API не сломался)
			if row.stats then
				for _, stat in ipairs(row.stats) do
					if stat.pvpStatID == ShuffleTracker.winsStatID then
						finalWins = stat.pvpStatValue
						break
					end
				end
			end
			
			-- 2. Fallback: Если API не вернул stats, берем из нашего трекера
			if not finalWins and ShuffleTracker.trackedWins[row.guid] then
				finalWins = ShuffleTracker.trackedWins[row.guid]
			end
			
			-- 3. Инжектируем данные в формате, который ожидает GetShuffleRoundsForGuid
			if finalWins then
				score.stats = { { pvpStatID = ShuffleTracker.winsStatID, pvpStatValue = finalWins } }
			end
		else
			score.stats = row.stats
		end
		
		db.scores[key] = score
	end
	
	ns.LastShuffleRounds = {}
	if mt == "solo_shuffle" then
		-- 1. Берем данные из нашего Fallback-трекера (если API Blizzard сломался)
		for guid, wins in pairs(ShuffleTracker.trackedWins) do
			ns.LastShuffleRounds[guid] = wins
		end
		-- 2. Перезаписываем/дополняем нативными данными из liveSnapshot (если API сработал)
		for key, row in pairs(liveSnapshot) do
			if row.guid and type(row.stats) == "table" then
				for _, stat in ipairs(row.stats) do
					if stat.pvpStatID == 1032 then
						ns.LastShuffleRounds[row.guid] = stat.pvpStatValue
					end
				end
			end
		end
	end
	
	wipe(liveSnapshot)
	ns.SetSnapshotActive(false)
	ResetShuffleTracker() -- 🌟 СБРОС ТРЕКЕРА ПОСЛЕ МАТЧА
	
	local playerCount = 0
	for _ in pairs(db.scores) do playerCount = playerCount + 1 end
	if playerCount < 16 then return end
	
	local matchDB = ns.GetMatchDB()
	local ts = math.floor(GetServerTime() / 180) * 180
	while matchDB[ts] do ts = ts + 1 end
	
	matchDB[ts] = db
	table.insert(ns.ArchiveSortedKeys, ts)
	table.sort(ns.ArchiveSortedKeys)
	-- матч в архиве — симуляция рейтинга его уже видит (Scoreboard ждёт этого)
	ns.MatchArchived = true
	if ns.OnMatchSaved then ns.OnMatchSaved() end
	
	if ns.UpdateQueueButtonsStats then ns.UpdateQueueButtonsStats() end
	
	C_Timer.After(1, function()
		local blob = ns.EncodeMatch(db)
		if blob then ns.ArchiveCache[ts] = db; matchDB[ts] = blob end
	end)
end

-- ============================================================================
-- EVENT FRAME
-- ============================================================================
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PVP_MATCH_STATE_CHANGED")
f:RegisterEvent("PVP_MATCH_COMPLETE")
f:RegisterEvent("UPDATE_BATTLEFIELD_SCORE") -- 🌟 ДОБАВЛЕНО ДЛЯ ТРЕКЕРА

f:SetScript("OnEvent", function(self, event, arg1)
	if event == "PLAYER_ENTERING_WORLD" or event == "PVP_MATCH_STATE_CHANGED" then
		ns.HandleMatchStateChanged(self)
	elseif event == "PVP_MATCH_COMPLETE" then
		ns.HandleMatchComplete()
	elseif event == "UPDATE_BATTLEFIELD_SCORE" then
		UpdateShuffleTracker() -- 🌟 ОБНОВЛЕНИЕ ТРЕКЕРА КАЖДЫЙ ТИК SCOREBOARD
	elseif UNIT_EVENT_TO_UNIT[event] then
		local src = UNIT_EVENT_TO_UNIT[event]
		if src == true then
			if arg1 then CheckUnitForBlacklist(arg1) end
		else
			CheckUnitForBlacklist(src)
		end
	end
end)