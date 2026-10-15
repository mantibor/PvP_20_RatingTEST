local addonName, ns = ...
-- ============================================================================
-- ARCHIVE KEYS  & CACHE
-- ============================================================================
function ns.InitArchiveKeys()
    local matchDB = ns.GetMatchDB()
    local kept = {}
    for ts, data in pairs(matchDB) do
        if type(ts) ~= "number" then
            matchDB[ts] = nil
        else
            local isBlob = type(data) == "string"
            local isTable = type(data) == "table"
            if isBlob or (isTable and type(rawget(data, "blob")) == "string") then
                kept[#kept + 1] = ts
            elseif isTable and rawget(data, "matchType") and type(rawget(data, "scores")) == "table" and ns.CanCompress() then
                local blob = ns.EncodeEntry(data)
                if blob then 
                    matchDB[ts] = blob
                    kept[#kept + 1] = ts
                else 
                    matchDB[ts] = nil 
                end
            else
                matchDB[ts] = nil
            end
        end
    end
    table.sort(kept)
    ns.ArchiveSortedKeys = kept
end

function ns.GetArchivedMatchKeys() 
    return ns.ArchiveSortedKeys 
end

function ns.GetArchivedMatch(ts)
    local matchDB = ns.GetMatchDB()
    if not matchDB[ts] then return nil end
    local cached = ns.ArchiveCache[ts]
    if cached then return cached end
    
    local raw = matchDB[ts]
    local decoded = {}
    if type(raw) == "string" then
        decoded = ns.DecodeEntry(raw)
    elseif type(raw) == "table" then
        decoded = type(rawget(raw, "blob")) == "string" and ns.DecodeEntry(rawget(raw, "blob")) or raw
    end
    if type(decoded) ~= "table" then decoded = {} end
    ns.ArchiveCache[ts] = decoded
    return decoded
end

-- ============================================================================
-- SOLO SHUFFLE ROUNDS PARSER
-- ============================================================================
function ns.GetShuffleRoundsForGuid(data, guid, playerName)
    local scores = data and data.scores
    if type(scores) ~= "table" then return end
    local myWon, sumWon, n = nil, 0, 0
    for _, row in pairs(scores) do
        if type(row) ~= "table" or type(row.stats) ~= "table" then return end
        local val, count = nil, 0
        for _, stat in pairs(row.stats) do
            count = count + 1
            val = stat and stat.pvpStatValue
        end
        if count ~= 1 or type(val) ~= "number" then return end
        n = n + 1
        sumWon = sumWon + val
        if (guid and row.guid == guid) or (playerName and row.name == playerName) then myWon = val end
    end
    if not myWon or n < 2 then return end
    local total = math.floor(sumWon / (n / 2) + 0.5)
    return myWon, math.max(total - myWon, 0), total
end

-- ============================================================================
-- CHRONOLOGICAL RATING SIMULATION (Glicko-2)
-- ============================================================================
local bgSimCache = {}
local bgSimKeyCount = 0

local function SimulateRatings(matchType, weekStart)
    -- 🌟 СОЗДАЕМ ЛОКАЛЬНУЮ БД В ПАМЯТИ для изолированной симуляции
    local simDB = {} 
    
    local ratings, rd, volatility = {}, {}, {}
    local wins, losses, bestR = {}, {}, {}
    local lastChange = {} -- изменение рейтинга в последнем матче игрока (для таблицы счёта)
    local weeklyWins, weeklyLosses, weeklyBestR = {}, {}, {}
    
    for _, ts in ipairs(ns.ArchiveSortedKeys) do
        local data = ns.GetArchivedMatch(ts)
        if data and data.matchType == matchType and (data.winner == 0 or data.winner == 1) then
            local isWeekly = ts >= weekStart
            local scores = data.scores
            if type(scores) == "table" then
                local factions = { [0] = {}, [1] = {} }
                for _, score in pairs(scores) do
                    if type(score) == "table" and score.guid and (score.faction == 0 or score.faction == 1) then
                        factions[score.faction][#factions[score.faction] + 1] = score.guid
                    end
                end
                for faction, guids in pairs(factions) do
                    local enemyGuids = factions[1 - faction]
                    local eSum, eRD, eN = 0, 0, 0
                    for _, eGuid in ipairs(enemyGuids) do
                        local eR = ratings[eGuid] or 0
                        if eR > 0 then
                            eSum = eSum + eR
                            eRD = eRD + (rd[eGuid] or 400)
                            eN = eN + 1
                        end
                    end
                    local enemyAvg = eN > 0 and math.floor(eSum / eN + 0.5) or 0
                    local enemyAvgRD = eN > 0 and eRD / eN or 400
                    local isWin = (faction == data.winner)
                    
                    for _, g in ipairs(guids) do
                        -- 🌟 ПЕРЕДАЕМ simDB КАК ПОСЛЕДНИЙ АРГУМЕНТ
                        local modeKey = matchType == "random_bg" and "RANDOM_BG" or "WARGAMES"
                        local before = ratings[g] or 0
                        local newRating, newRD = ns.UpdateGlicko2Rating(g, enemyAvg, enemyAvgRD, isWin, modeKey, simDB)
                        lastChange[g] = newRating - before

                        ratings[g] = newRating
                        rd[g] = newRD
                        
                        if isWin then wins[g] = (wins[g] or 0) + 1 else losses[g] = (losses[g] or 0) + 1 end
                        if newRating > (bestR[g] or 0) then bestR[g] = newRating end
                        
                        if isWeekly then
                            if isWin then weeklyWins[g] = (weeklyWins[g] or 0) + 1 else weeklyLosses[g] = (weeklyLosses[g] or 0) + 1 end
                            if newRating > (weeklyBestR[g] or 0) then weeklyBestR[g] = newRating end
                        end
                    end
                end
            end
        end
    end
    
    local result = {}
    for g, r in pairs(ratings) do
        local w, l = wins[g] or 0, losses[g] or 0
        local ww, wl = weeklyWins[g] or 0, weeklyLosses[g] or 0
        result[g] = {
            rating = r, rd = rd[g], wins = w, losses = l, played = w + l, 
            bestRating = bestR[g] or 0, lastChange = lastChange[g] or 0,
            weeklyWins = ww, weeklyLosses = wl, weeklyPlayed = ww + wl,
            weeklyBestRating = weeklyBestR[g] or 0,
        }
    end
    return result
end

local MATCH_TYPE_BUCKET = {
    random_bg = "randomBG",
    arena_5v5 = "wargame"
}
local statsCacheByGuid = {}

-- ============================================================================
-- UNIFIED API FOR UI (Leaderboard, Tooltips, Scoreboard)
-- ============================================================================
function ns.GetArchiveStatsForGuid(guid)
    if not guid then return end
    local keyCount = #ns.ArchiveSortedKeys
    local cached = statsCacheByGuid[guid]
    if cached and cached.keyCount == keyCount then return cached.totals end
    
    local weekStart = ns.GetWeekStart()
    if not (bgSimKeyCount == keyCount and next(bgSimCache)) then
        bgSimCache.randomBG = SimulateRatings("random_bg", weekStart)
        bgSimCache.wargame = SimulateRatings("arena_5v5", weekStart)
        bgSimKeyCount = keyCount
    end
    
    local playerName = nil
    local skirmishRec = ns.SkirmishDB[guid]
    if skirmishRec and skirmishRec.name then playerName = skirmishRec.name end
    
    local totals = {
        randomBG    = { wins = 0, losses = 0, played = 0, rating = 0, rd = 400, bestRating = 0, weeklyWins = 0, weeklyLosses = 0, weeklyPlayed = 0, weeklyBestRating = 0 },
        soloShuffle = { wins = 0, losses = 0, played = 0, rating = 0, rd = 350, bestRating = 0, weeklyWins = 0, weeklyLosses = 0, weeklyPlayed = 0, weeklyBestRating = 0 },
        wargame     = { wins = 0, losses = 0, played = 0, rating = 0, rd = 400, bestRating = 0, weeklyWins = 0, weeklyLosses = 0, weeklyPlayed = 0, weeklyBestRating = 0 },
        skirmish    = { wins = 0, losses = 0, played = 0, rating = 0, rd = 350, bestRating = 0, weeklyWins = 0, weeklyLosses = 0, weeklyPlayed = 0, weeklyBestRating = 0 },
    }
    
    -- 1. Random BG и Wargames из симуляции Glicko-2
    local rbSim = bgSimCache.randomBG and bgSimCache.randomBG[guid]
    if rbSim then
        totals.randomBG.rating = rbSim.rating
        totals.randomBG.rd = rbSim.rd
        totals.randomBG.bestRating = rbSim.bestRating
        totals.randomBG.weeklyBestRating = rbSim.weeklyBestRating
        totals.randomBG.lastChange = rbSim.lastChange
    end
    
    local wgSim = bgSimCache.wargame and bgSimCache.wargame[guid]
    if wgSim then
        totals.wargame.rating = wgSim.rating
        totals.wargame.rd = wgSim.rd
        totals.wargame.bestRating = wgSim.bestRating
        totals.wargame.weeklyBestRating = wgSim.weeklyBestRating
        totals.wargame.lastChange = wgSim.lastChange
    end
    
    -- 2. Skirmish: ПРИОРИТЕТ реальных данных Blizzard API из SkirmishDB
    if skirmishRec and type(skirmishRec) == "table" and (tonumber(skirmishRec.rating) or 0) > 0 then
        totals.skirmish.rating = tonumber(skirmishRec.rating)
        totals.skirmish.rd = tonumber(skirmishRec.rd) or 350
        totals.skirmish.bestRating = tonumber(skirmishRec.bestRating) or totals.skirmish.rating
        totals.skirmish.played = tonumber(skirmishRec.played) or 0
        totals.skirmish.wins = tonumber(skirmishRec.won) or 0
        totals.skirmish.losses = totals.skirmish.played - totals.skirmish.wins
        if (tonumber(skirmishRec.lastUpdate) or 0) >= weekStart then
            totals.skirmish.weeklyPlayed = totals.skirmish.played
            totals.skirmish.weeklyWins = totals.skirmish.wins
            totals.skirmish.weeklyLosses = totals.skirmish.losses
            totals.skirmish.weeklyBestRating = totals.skirmish.bestRating
        end
    end
    
    -- 3. Подсчет W/L из архива для Random BG и Wargames
    for _, ts in ipairs(ns.ArchiveSortedKeys) do
        local data = ns.GetArchivedMatch(ts)
        if data and data.winner and (data.winner == 0 or data.winner == 1) then
            local playerScore = nil
            if type(data.scores) == "table" then
                if guid then
                    playerScore = data.scores[guid]
                    if not playerScore then
                        for _, score in pairs(data.scores) do
                            if type(score) == "table" and score.guid == guid then playerScore = score; break end
                        end
                    end
                end
                if not playerScore and playerName then
                    for _, score in pairs(data.scores) do
                        if type(score) == "table" and score.name == playerName then playerScore = score; break end
                    end
                end
            end
            if playerScore then
                local isWin = (playerScore.faction == data.winner)
                local isWeekly = ts >= weekStart
                local bucketName = MATCH_TYPE_BUCKET[data.matchType]
                if bucketName then
                    local b = totals[bucketName]
                    if isWin then b.wins = b.wins + 1 else b.losses = b.losses + 1 end
                    b.played = b.wins + b.losses
                    if isWeekly then
                        if isWin then b.weeklyWins = b.weeklyWins + 1 else b.weeklyLosses = b.weeklyLosses + 1 end
                        b.weeklyPlayed = b.weeklyWins + b.weeklyLosses
                    end
                end
            end
        end
    end
    
    -- 4. Solo Shuffle (Агрегированный Glicko-2 в локальной симуляции)
    local shuffleSimDB = {}
    for _, ts in ipairs(ns.ArchiveSortedKeys) do
        local data = ns.GetArchivedMatch(ts)
        if data and data.matchType == "solo_shuffle" then
            local bucket = totals.soloShuffle
            local isWeekly = ts >= weekStart
            local rw, rl, total = ns.GetShuffleRoundsForGuid(data, guid, playerName)
            if rw and total > 0 then
                bucket.wins = bucket.wins + rw
                bucket.losses = bucket.losses + rl
                bucket.played = bucket.played + total
                
                -- 🌟 Агрегированный score для Glicko-2 с передачей локальной БД
                local newRating, newRD = ns.UpdateGlicko2Rating(guid, 1500, 350, rw / total, "SOLO_SHUFFLE", shuffleSimDB)
                bucket.rating = newRating
                bucket.rd = newRD
                if newRating > (bucket.bestRating or 0) then bucket.bestRating = newRating end
                
                if isWeekly then
                    bucket.weeklyPlayed = bucket.weeklyPlayed + total
                    bucket.weeklyWins = bucket.weeklyWins + rw
                    bucket.weeklyLosses = bucket.weeklyLosses + rl
                    if newRating > (bucket.weeklyBestRating or 0) then bucket.weeklyBestRating = newRating end
                end
            end
        end
    end
    
    statsCacheByGuid[guid] = { keyCount = keyCount, totals = totals }
    return totals
end