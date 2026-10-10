local addonName, ns = ...

-- ============================================================================
-- STATE & EXPORTS
-- ============================================================================
ns.LeaderboardData = {}
local LD = ns.LeaderboardData

-- ============================================================================
-- HELPERS
-- ============================================================================
function LD.safeNum(v)
	local n = tonumber(v)
	return (n and n == n) and n or 0
end

function LD.RatingColor(rating)
	rating = tonumber(rating) or 0
	for _, f in ipairs(LD.RATING_FILTERS) do
		if (not f.min or rating >= f.min) and (not f.max or rating <= f.max) then
			return f.color
		end
	end
	return "FFD100"
end

function LD.IsBetter(a, b)
	if not a or not b then return false end
	local aRating = LD.safeNum(a.rating);  local bRating = LD.safeNum(b.rating)
	if aRating ~= bRating then return aRating > bRating end
	
	local aBest = LD.safeNum(a.bestRating or a.best or a.rating)
	local bBest = LD.safeNum(b.bestRating or b.best or b.rating)
	if aBest ~= bBest then return aBest > bBest end
	
	local aPlayed = LD.safeNum(a.played); local bPlayed = LD.safeNum(b.played)
	local aWon    = LD.safeNum(a.won);    local bWon    = LD.safeNum(b.won)
	local aWR = aPlayed > 0 and (aWon / aPlayed) or 0
	local bWR = bPlayed > 0 and (bWon / bPlayed) or 0
	if aWR ~= bWR then return aWR > bWR end
	
	if aWon ~= bWon then return aWon > bWon end
	local aLoss = aPlayed - aWon; local bLoss = bPlayed - bWon
	if aLoss ~= bLoss then return aLoss < bLoss end
	
	local aTime = LD.safeNum(a.lastUpdate); local bTime = LD.safeNum(b.lastUpdate)
	if aTime ~= bTime then return aTime > bTime end
	
	local aName = tostring(a.name or ""):lower(); local bName = tostring(b.name or ""):lower()
	if aName ~= bName then return aName < bName end
	return tostring(a.guid or "") < tostring(b.guid or "")
end

-- ============================================================================
-- DATA PROCESSING
-- ============================================================================
local function PassesRatingFilter(rating, ratingFilters)
	if not next(ratingFilters) then return false end
	for filter, enabled in pairs(ratingFilters) do
		if enabled then
			if (not filter.min or rating >= filter.min) and (not filter.max or rating <= filter.max) then
				return true
			end
		end
	end
	return false
end

function LD.InjectArchiveRatings(aggregates, bracket)
	for guid, agg in pairs(aggregates) do
		local stats = ns.GetArchiveStatsForGuid and ns.GetArchiveStatsForGuid(guid)
		if stats then
			local bucket
			if bracket == "RANDOM_BATTLEGROUNDS" then bucket = stats.randomBG
			elseif bracket == "SOLO_SHUFFLE" then bucket = stats.soloShuffle
			elseif bracket == "WARGAMES" then bucket = stats.wargame end
			if bucket then
				agg.rating = bucket.rating or 0
				agg.best = bucket.bestRating or bucket.rating or 0
			end
		end
	end
end

function LD.BuildArchiveAggregates(matchTypes, useRounds)
	local typeSet = {}
	if type(matchTypes) == "string" then typeSet[matchTypes] = true
	else for _, t in ipairs(matchTypes or {}) do typeSet[t] = true end end
	
	local aggregates = {}
	local keys = ns.GetArchivedMatchKeys and ns.GetArchivedMatchKeys() or {}
	local getRounds = useRounds and ns.GetShuffleRoundsForGuid or nil
	
	for _, timestamp in ipairs(keys) do
		local data = ns.GetArchivedMatch and ns.GetArchivedMatch(timestamp)
		if data and typeSet[data.matchType] then
			local winner = data.winner
			if type(data.scores) == "table" then
				for _, score in pairs(data.scores) do
					if score and score.guid and score.name then
						local agg = aggregates[score.guid]
						if not agg then
							agg = { guid = score.guid, name = score.name, class = score.class, rating = 0, best = 0, played = 0, won = 0, lastUpdate = 0 }
							aggregates[score.guid] = agg
						end
						if useRounds and getRounds then
							local rw, rl, total = getRounds(data, score.guid)
							if rw then agg.played = agg.played + total; agg.won = agg.won + rw end
						else
							agg.played = agg.played + 1
							if (winner == 0 or winner == 1) and score.faction == winner then agg.won = agg.won + 1 end
						end
						if timestamp > agg.lastUpdate then
							agg.lastUpdate = timestamp; agg.name = score.name
							if score.class then agg.class = score.class end
						end
					end
				end
			end
		end
	end
	return aggregates
end

function LD.CollectEntries(bracketFilter, classFilter, ratingFilters, searchText, sortKey, sortAsc)
	local entries = {}
	local myGuid = UnitGUID("player")
	local normalizedSearch = searchText and searchText ~= "" and LD.NormalizeString(searchText) or nil
	local archiveCfg = LD.BRACKET_ARCHIVE_CONFIG[bracketFilter]
	
	if archiveCfg then
		local aggregates = LD.BuildArchiveAggregates(archiveCfg.matchTypes, archiveCfg.useRounds)
		LD.InjectArchiveRatings(aggregates, bracketFilter)
		for guid, agg in pairs(aggregates) do
			local include = true
			local rating = LD.safeNum(agg.rating)
			if rating <= 0 then include = false end
			if include and not PassesRatingFilter(rating, ratingFilters) then include = false end
			if include and normalizedSearch then
				local baseName = tostring(agg.name)
				local dn = LD.NormalizeString(LD.DisplayName(baseName) or baseName)
				local rn = LD.NormalizeString(baseName)
				if not (dn:find(normalizedSearch, 1, true) or rn:find(normalizedSearch, 1, true)) then include = false end
			end
			if include and classFilter and agg.class ~= classFilter then include = false end
			if include then
				agg.isSelf = (guid == myGuid)
				entries[#entries + 1] = agg
			end
		end
	else
		local db = ns.SkirmishDB
		if type(db) == "table" then
			for guid, data in pairs(db) do
				if type(guid) == "string" and type(data) == "table" then
					local rating = LD.safeNum(data.rating)
					if rating > 0 then
						if normalizedSearch then
							local baseName = tostring(data.name)
							local displayName = LD.NormalizeString(LD.DisplayName(baseName) or baseName)
							local rawName = LD.NormalizeString(baseName)
							if not (displayName:find(normalizedSearch, 1, true) or rawName:find(normalizedSearch, 1, true)) then rating = 0 end
						end
						if rating > 0 and classFilter and data.class ~= classFilter then rating = 0 end
						if rating > 0 and not PassesRatingFilter(rating, ratingFilters) then rating = 0 end
						if rating > 0 then
							entries[#entries + 1] = {
								guid = guid, name = tostring(data.name or "?"), class = data.class,
								rating = rating, best = LD.safeNum(data.bestRating or data.rating),
								played = LD.safeNum(data.played), won = LD.safeNum(data.won),
								lastUpdate = LD.safeNum(data.lastUpdate), isSelf = (guid == myGuid),
							}
						end
					end
				end
			end
		end
	end
	
	local function sortVal(e)
		if not e then return 0 end
		if sortKey == "name" then return tostring(e.name):lower()
		elseif sortKey == "best" then return LD.safeNum(e.best)
		elseif sortKey == "wr" then
			local played = LD.safeNum(e.played)
			return played > 0 and (LD.safeNum(e.won) / played) or 0
		elseif sortKey == "time" then return LD.safeNum(e.lastUpdate)
		else return LD.safeNum(e.rating) end
	end
	
	local function cmp(a, b)
		local ta, tb = type(a), type(b)
		if ta ~= tb then a, b = tostring(a), tostring(b) end
		if a == b then return nil end
		if sortAsc then return a < b else return a > b end
	end
	
	table.sort(entries, function(a, b)
		if not a or not b then return false end
		local res = cmp(sortVal(a), sortVal(b))
		if res ~= nil then return res end
		res = cmp(LD.safeNum(a.rating), LD.safeNum(b.rating))
		if res ~= nil then return res end
		res = cmp(LD.safeNum(a.best), LD.safeNum(b.best))
		if res ~= nil then return res end
		local aWR = LD.safeNum(a.played) > 0 and (LD.safeNum(a.won) / LD.safeNum(a.played)) or 0
		local bWR = LD.safeNum(b.played) > 0 and (LD.safeNum(b.won) / LD.safeNum(b.played)) or 0
		res = cmp(aWR, bWR)
		if res ~= nil then return res end
		res = cmp(LD.safeNum(a.won), LD.safeNum(b.won))
		if res ~= nil then return res end
		local aLoss = LD.safeNum(a.played) - LD.safeNum(a.won)
		local bLoss = LD.safeNum(b.played) - LD.safeNum(b.won)
		res = cmp(bLoss, aLoss)
		if res ~= nil then return res end
		res = cmp(LD.safeNum(a.lastUpdate), LD.safeNum(b.lastUpdate))
		if res ~= nil then return res end
		local an, bn = tostring(a.name):lower(), tostring(b.name):lower()
		if an ~= bn then return an < bn end
		return tostring(a.guid) < tostring(b.guid)
	end)
	return entries
end

-- ============================================================================
-- GLOBAL LEADERBOARD RANK API
-- ============================================================================
function LD.GetLeaderboardRank(guid, bracket)
	if not guid then return nil end
	bracket = bracket or "SKIRMISH"
	local all = {}
	
	if bracket == "SKIRMISH" then
		local db = ns.SkirmishDB
		if type(db) == "table" then
			for g, data in pairs(db) do
				if type(g) == "string" and type(data) == "table" then
					local rating = tonumber(data.rating) or 0
					if rating > 0 then
						all[#all + 1] = {
							guid = g, name = data.name, rating = rating,
							bestRating = tonumber(data.bestRating or data.rating) or 0,
							played = tonumber(data.played) or 0, won = tonumber(data.won) or 0,
							lastUpdate = tonumber(data.lastUpdate) or 0,
						}
					end
				end
			end
		end
	else
		local archiveCfg = LD.BRACKET_ARCHIVE_CONFIG[bracket]
		if archiveCfg then
			local aggregates = LD.BuildArchiveAggregates(archiveCfg.matchTypes, archiveCfg.useRounds)
			LD.InjectArchiveRatings(aggregates, bracket)
			for g, agg in pairs(aggregates) do
				if (agg.rating or 0) > 0 then all[#all + 1] = agg end
			end
		end
	end
	
	if #all == 0 then return nil end
	table.sort(all, LD.IsBetter)
	for i, e in ipairs(all) do
		if e.guid == guid then return i end
	end
	return nil
end