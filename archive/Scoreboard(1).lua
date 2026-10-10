local addonName, ns = ...
local L = ns.L

-- ============================================================================
-- STATE
-- ============================================================================
ns._skirmishRatings = ns._skirmishRatings or {}
ns._skirmishRatingsByIndex = ns._skirmishRatingsByIndex or {}
ns.lastArenaApprox = nil

-- ============================================================================
-- MATCH TYPE DETECTION
-- ============================================================================
local function GetLocalMatchType()
    if IsArenaSkirmish() then return "skirmish" end
    return ns.GetMatchType and ns.GetMatchType()
end

local function IsSupportedPvPMatch()
    local mt = GetLocalMatchType()
    return mt == "skirmish" or mt == "random_bg" or mt == "arena_5v5"
end

-- ============================================================================
-- SCORE ROWS & CACHED RATING
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

local function CachedRating(guid)
    guid = ns.SafeGuid(guid)
    if not guid then return 0, false end
    local rec = ns.SkirmishDB and ns.SkirmishDB[guid]
    if type(rec) == "table" and rec.rating ~= nil then
        return tonumber(rec.rating) or 0, true
    end
    return 0, false
end

-- ============================================================================
-- MAIN RECOMPUTE
-- ============================================================================
local function RecomputeRatings()
    wipe(ns._skirmishRatings)
    wipe(ns._skirmishRatingsByIndex)
    ns.lastArenaApprox = nil

    local kind = GetLocalMatchType()
    if kind ~= "skirmish" and kind ~= "random_bg" and kind ~= "arena_5v5" then return end

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

    local matchComplete = C_PvP.IsMatchComplete and C_PvP.IsMatchComplete()

    if kind == "random_bg" or kind == "arena_5v5" then
        local archiveKey = (kind == "arena_5v5") and "wargame" or "randomBG"
        local allySumPost, allyN = 0, 0
        local enemySumPost, enemyN = 0, 0
        local playerData = {}

        for i, s in ipairs(rows) do
            local guid = ns.SafeGuid(s.guid)
            local postRating = 0
            if ns.GetArchiveStatsForGuid then
                local stats = ns.GetArchiveStatsForGuid(guid)
                if stats and stats[archiveKey] then
                    postRating = stats[archiveKey].rating or 0
                end
            end
            playerData[i] = {
                guid = guid, faction = s.faction, postRating = postRating,
                won = (winnerFaction ~= nil) and (s.faction == winnerFaction),
            }
            if s.faction == myFaction then allySumPost = allySumPost + postRating; allyN = allyN + 1
            else enemySumPost = enemySumPost + postRating; enemyN = enemyN + 1 end
        end

        local realAllyAvgPost = allyN > 0 and math.floor(allySumPost / allyN + 0.5) or 0
        local realEnemyAvgPost = enemyN > 0 and math.floor(enemySumPost / enemyN + 0.5) or 0
        local allySumOld, allyNOld = 0, 0
        local enemySumOld, enemyNOld = 0, 0

        for i, data in ipairs(playerData) do
            local guid = data.guid
            local postRating = data.postRating
            local won = data.won
            local entry

            if matchComplete then
                local enemyAvg = (data.faction == myFaction) and realEnemyAvgPost or realAllyAvgPost
                local calcDelta = ns.CalculateBGRatingDelta and ns.CalculateBGRatingDelta(postRating, enemyAvg, won) or 0
                local oldRating = postRating - calcDelta
                if oldRating < 0 then oldRating = 0; calcDelta = postRating end
                entry = { new = postRating, change = calcDelta, old = oldRating, hasData = true }
            else
                entry = { new = postRating, change = 0, old = postRating, hasData = postRating > 0 }
            end

            ns._skirmishRatingsByIndex[i] = entry
            if guid then ns._skirmishRatings[guid] = entry end

            local avgVal = matchComplete and entry.old or entry.new
            if entry.hasData then
                if data.faction == myFaction then allySumOld = allySumOld + avgVal; allyNOld = allyNOld + 1
                else enemySumOld = enemySumOld + avgVal; enemyNOld = enemyNOld + 1 end
            end
        end

        local realAllyAvg = allyNOld > 0 and math.floor(allySumOld / allyNOld + 0.5) or 0
        local realEnemyAvg = enemyNOld > 0 and math.floor(enemySumOld / enemyNOld + 0.5) or 0
        local mine = myGuid and ns._skirmishRatings[myGuid] or nil

        if mine then
            ns.lastArenaApprox = {
                approxRating = mine.new, ratingChange = mine.change, oldRating = mine.old,
                realAllyAvg = realAllyAvg, realEnemyAvg = realEnemyAvg,
                allyKnownCount = allyNOld, enemyKnownCount = enemyNOld,
            }
        end
    else
        -- =====================================================================
        -- ARENA SKIRMISH: Glicko-2 модель
        -- =====================================================================
        local allySum, allyN = 0, 0
        local enemySum, enemyN = 0, 0
        for _, s in ipairs(rows) do
            local r, has = CachedRating(s.guid)
            if has then
                if s.faction == myFaction then
                    allySum, allyN = allySum + r, allyN + 1
                else
                    enemySum, enemyN = enemySum + r, enemyN + 1
                end
            end
        end
        local realAllyAvg = allyN > 0 and math.floor(allySum / allyN + 0.5) or 0
        local realEnemyAvg = enemyN > 0 and math.floor(enemySum / enemyN + 0.5) or 0
        
        -- Получаем RD из SkirmishDB
        local allyRD, enemyRD = 350, 350
        if allyN > 0 then
            local totalRD = 0
            for _, s in ipairs(rows) do
                if s.faction == myFaction then
                    local rec = PVP20R.SkirmishDB[s.guid]
                    if rec and rec.rd then totalRD = totalRD + rec.rd end
                end
            end
            allyRD = totalRD / allyN
        end
        if enemyN > 0 then
            local totalRD = 0
            for _, s in ipairs(rows) do
                if s.faction ~= myFaction then
                    local rec = PVP20R.SkirmishDB[s.guid]
                    if rec and rec.rd then totalRD = totalRD + rec.rd end
                end
            end
            enemyRD = totalRD / enemyN
        end
        
        for i, s in ipairs(rows) do
            local isAlly = (s.faction == myFaction)
            local won = (winnerFaction ~= nil) and (s.faction == winnerFaction)
            local guid = SafeGuid(s.guid)
            
            -- Glicko-2 обновление (ЗАМЕНА ComputeNewRatingSkirmish)
            local opponentAvg = isAlly and realEnemyAvg or realAllyAvg
            local opponentRD = isAlly and enemyRD or allyRD
            local old, has = CachedRating(guid)
            
            local newRating, newRD = PVP20R.UpdateGlicko2Rating(guid, opponentAvg, opponentRD, won, "SKIRMISH")
            local change = has and (newRating - old) or 0
            
            local entry = {
                new = newRating,
                change = change,
                old = has and old or 0,
                hasData = has,
            }
            PVP20R._skirmishRatingsByIndex[i] = entry
            if guid then PVP20R._skirmishRatings[guid] = entry end
        end
        
        local mine = myGuid and PVP20R._skirmishRatings[myGuid] or nil
        if not mine then
            for i, s in ipairs(rows) do
                if IsPlayerGuid and IsPlayerGuid(s.guid) then
                    mine = PVP20R._skirmishRatingsByIndex[i]
                    break
                end
            end
        end
        if mine then
            PVP20R.lastArenaApprox = {
                approxRating = mine.new,
                ratingChange = mine.change,
                oldRating = mine.old,
                allyAvg = realAllyAvg,
                enemyAvg = realEnemyAvg,
                realAllyAvg = realAllyAvg,
                realEnemyAvg = realEnemyAvg,
                allyKnownCount = allyN,
                enemyKnownCount = enemyN,
            }
        end
    end
end

-- ============================================================================
-- TABLE INTEGRATION
-- ============================================================================
local NEW_RATING_KEY    = "pvp20rNewRating"
local CHANGE_RATING_KEY = "pvp20rRatingChange"
local RATING_KEY        = "pvp20rRating"
local ROUNDS_KEY        = "pvp20rRoundsWon"

local function GetRoundsLabel()
    return GetLocale() == "ruRU" and "Раундов\nвыиграно" or "Rounds\nWon"
end

local ROUNDS_WON_PATTERNS = { "rounds won", "раундов выиграно" }

local function NormalizeHeaderText(text)
    if type(text) ~= "string" or text == "" then return nil end
    if issecretvalue and issecretvalue(text) then return nil end
    local s = text:gsub(":%s*$", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s ~= "" and string.lower(s) or nil
end

local function PlainString(value)
    if type(value) ~= "string" or value == "" then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function HeaderLabel(column)
    if not column or not column.GetHeaderFrame then return nil end
    local header = column:GetHeaderFrame()
    if not header then return nil end
    local stored = PlainString(header.textID)
    if stored then return stored end
    if header.text and header.text.GetText then
        local plain = PlainString(header.text:GetText())
        if plain then return plain end
    end
    if header.GetText then return PlainString(header:GetText()) end
end

local function IsRoundsLabel(text)
    local normalized = NormalizeHeaderText(PlainString(text))
    if not normalized then return false end
    for _, pat in ipairs(ROUNDS_WON_PATTERNS) do
        if normalized:find(pat, 1, true) then return true end
    end
    return normalized == "rounds" or normalized == "раундов"
end

local function IsKillingBlowsLabel(text)
    local normalized = NormalizeHeaderText(PlainString(text))
    if not normalized then return false end
    local kb = NormalizeHeaderText(PlainString(SCORE_KILLING_BLOWS))
    return kb and normalized == kb
end

local function BuilderColumns(tableBuilder)
    if tableBuilder.GetColumns then
        local columns = tableBuilder:GetColumns()
        if type(columns) == "table" then return columns end
    end
    return tableBuilder.columns
end

local function BuilderHasRoundsColumn(tableBuilder)
    local columns = BuilderColumns(tableBuilder)
    if type(columns) ~= "table" then return false end
    for _, column in ipairs(columns) do
        if IsRoundsLabel(HeaderLabel(column)) then return true end
    end
    return false
end

local function StripRoundsColumn(tableBuilder)
    local columns = BuilderColumns(tableBuilder)
    if type(columns) ~= "table" then return end
    local pool = tableBuilder.GetHeaderPoolCollection and tableBuilder:GetHeaderPoolCollection()
    for i = #columns, 1, -1 do
        local column = columns[i]
        if IsRoundsLabel(HeaderLabel(column)) then
            if column.Reset then column:Reset() end
            local header = column.GetHeaderFrame and column:GetHeaderFrame()
            local released = false
            if header and pool and pool.Release then released = pool:Release(header) end
            if header and not released and header.Hide then header:Hide() end
            table.remove(columns, i)
        end
    end
end

local function MoveRoundsColumnBeforeKillingBlows(tableBuilder, roundsColumn)
    local columns = BuilderColumns(tableBuilder)
    if type(columns) ~= "table" or #columns == 0 then return end
    local kbIndex
    for i, column in ipairs(columns) do
        if IsKillingBlowsLabel(HeaderLabel(column)) then kbIndex = i; break end
    end
    if not kbIndex then return end
    local lastIndex = #columns
    if columns[lastIndex] ~= roundsColumn then
        for i = lastIndex, 1, -1 do
            if columns[i] == roundsColumn then lastIndex = i; break end
        end
    end
    if lastIndex == kbIndex or lastIndex == kbIndex + 1 then return end
    table.remove(columns, lastIndex)
    if lastIndex < kbIndex then kbIndex = kbIndex - 1 end
    table.insert(columns, kbIndex, roundsColumn)
end

-- ============================================================================
-- EARNINGS: ratingFrame (используем ns.PvPTiers)
-- ============================================================================
local earningsHooksDone = false

local function UpdateEarningsRating()
    if not IsSupportedPvPMatch() then return end
    local results = _G.PVPMatchResults
    if not results then return end
    local ratingFrame = results.ratingFrame
    local ratingButton = results.ratingButton
    local ratingText = results.ratingText
    local progress = results.progressContainer
    local earnings = results.earningsContainer
    if not (ratingFrame and ratingButton and progress) then return end

    local approx = ns.lastArenaApprox
    if not approx then RecomputeRatings(); approx = ns.lastArenaApprox end
    if not approx then return end

    local ratingVal = tonumber(approx.approxRating) or 0
    local tier
    for _, t in ipairs(ns.PvPTiers) do
        if ratingVal >= t.min and ratingVal <= t.max then tier = t; break end
    end
    if not tier then tier = ns.PvPTiers[1] end
    local icon = tier.icon

    local iconRegion
    if ratingButton then
        if ratingButton.Icon then iconRegion = ratingButton.Icon
        elseif ratingButton.icon then iconRegion = ratingButton.icon
        else
            local regions = { ratingButton:GetRegions() }
            for _, region in ipairs(regions) do
                if region and region.IsObjectType and region:IsObjectType("Texture") then iconRegion = region; break end
            end
        end
    end
    if icon and iconRegion then iconRegion:SetTexture(icon); iconRegion:Show() end

    if ratingButton.Init then ratingButton:Init(approx.oldRating or 0, approx.ratingChange or 0) end
    if ratingButton.RankingShadow then ratingButton.RankingShadow:Hide() end
    if ratingButton.Ranking then ratingButton.Ranking:Hide() end

    local change = approx.ratingChange or 0
    if ratingText then
        if change ~= 0 then ratingText:SetText(PVP_RATING_CHANGE:format(FormatValueWithSign(change)))
        else ratingText:SetText(PVP_RATING_UNCHANGED) end
        ratingText:Show()
    end

    ratingFrame:ClearAllPoints()
    local prev = (results.conquestFrame and results.conquestFrame:IsShown() and results.conquestFrame) or
                 (results.honorFrame and results.honorFrame:IsShown() and results.honorFrame)
    if prev then ratingFrame:SetPoint("LEFT", prev, "RIGHT", 22, 0)
    else ratingFrame:SetPoint("TOPLEFT", results.progressHeader, "BOTTOMLEFT", 3, -11) end
    ratingFrame:Show()

    local hasItems = results.rewardsContainer and results.rewardsContainer:IsShown()
    progress:ClearAllPoints()
    if hasItems then progress:SetPoint("TOPLEFT", results.rewardsContainer, "TOPRIGHT", 50, 0)
    else progress:SetPoint("TOPLEFT") end
    progress:Show()

    if earnings then earnings:Show(); earnings:MarkDirty() end
    progress:MarkDirty()
    ratingFrame:MarkDirty()
end

-- ============================================================================
-- HOOKS SETUP
-- ============================================================================
local function SetupPVPMatchHooks()
    -- 1) Hook ConstructPVPMatchTable с отложенным выполнением
    if not ns._pvpMatchTableHooked and _G.ConstructPVPMatchTable then
        ns._pvpMatchTableHooked = true
        hooksecurefunc("ConstructPVPMatchTable", function(tableBuilder, useAlternateColor)
            if not IsSupportedPvPMatch() then return end
            ns._pendingTableBuilder = tableBuilder
            ns._pendingUseAlt = useAlternateColor
            C_Timer.After(0, function()
                local tb = ns._pendingTableBuilder
                if not tb then return end
                ns._pendingTableBuilder = nil
                if not IsSupportedPvPMatch() then return end

                RecomputeRatings()

                local kind = GetLocalMatchType()
                local textPadding = 15

                if kind == "skirmish" or kind == "arena_5v5" then
                    StripRoundsColumn(tb)
                end

                if kind == "solo_shuffle" and not BuilderHasRoundsColumn(tb) then
                    local col = tb:AddColumn()
                    col:ConstructHeader("BUTTON", "PVPHeaderStringTemplate", GetRoundsLabel(), "CENTER", ROUNDS_KEY)
                    col:ConstrainToHeader(textPadding)
                    col:ConstructCells("FRAME", "PVPCellStringTemplate", ROUNDS_KEY, useAlternateColor)
                    MoveRoundsColumnBeforeKillingBlows(tb, col)
                end

                local matchComplete = C_PvP.IsMatchComplete and C_PvP.IsMatchComplete()
                if matchComplete then
                    local col = tb:AddColumn()
                    col:ConstructHeader("BUTTON", "PVPHeaderStringTemplate", BATTLEGROUND_NEW_RATING, "CENTER", NEW_RATING_KEY)
                    col:ConstrainToHeader(textPadding)
                    col:ConstructCells("FRAME", "PVPCellStringTemplate", NEW_RATING_KEY, useAlternateColor)

                    col = tb:AddColumn()
                    col:ConstructHeader("BUTTON", "PVPHeaderStringTemplate", SCORE_RATING_CHANGE, "CENTER", CHANGE_RATING_KEY)
                    col:ConstrainToHeader(textPadding)
                    col:ConstructCells("FRAME", "PVPCellStringTemplate", CHANGE_RATING_KEY, useAlternateColor)
                else
                    local col = tb:AddColumn()
                    col:ConstructHeader("BUTTON", "PVPHeaderStringTemplate", BATTLEGROUND_RATING, "CENTER", RATING_KEY)
                    col:ConstrainToHeader(textPadding)
                    col:ConstructCells("FRAME", "PVPCellStringTemplate", RATING_KEY, useAlternateColor)
                end

                tb:Arrange()
            end)
        end)
    end

    -- 2) Hook Cell Populate
    if not ns._pvpCellPopulateHooked and PVPCellStringMixin and PVPCellStringMixin.Populate then
        ns._pvpCellPopulateHooked = true
        hooksecurefunc(PVPCellStringMixin, "Populate", function(self, rowData, dataIndex)
            local key = self.dataProviderKey
            if key == NEW_RATING_KEY or key == CHANGE_RATING_KEY or key == RATING_KEY then
                local info
                local guid = ns.SafeGuid(rowData and rowData.guid)
                if guid then info = ns._skirmishRatings[guid] end
                if not info and type(dataIndex) == "number" then info = ns._skirmishRatingsByIndex[dataIndex] end

                if not info or not info.hasData then
                    if self.text then self.text:SetText("0") end
                    return
                end

                local text
                if key == CHANGE_RATING_KEY then
                    local ch = info.change or 0
                    text = (ch > 0 and ("+" .. ch)) or tostring(ch)
                elseif key == RATING_KEY then
                    text = tostring(info.old or info.new or "")
                else
                    text = tostring(info.new or "")
                end
                if self.text then self.text:SetText(text) end
            end
        end)
    end

    -- 3) Hook Matchmaking Text
    if not ns._pvpMatchmakingHooked and PVPMatchUtil and PVPMatchUtil.UpdateMatchmakingText then
        ns._pvpMatchmakingHooked = true
        hooksecurefunc(PVPMatchUtil, "UpdateMatchmakingText", function(fontString)
            if not IsSupportedPvPMatch() or not fontString then return end
            RecomputeRatings()
            local approx = ns.lastArenaApprox
            if not approx then return end
            local allyText = HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(BreakUpLargeNumbers(approx.realAllyAvg))
            local enemyText = HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(BreakUpLargeNumbers(approx.realEnemyAvg))
            local text = L["Your Team's Average Rating: %s"]:format(allyText) .. "\n" .. L["Enemy Team's Average Rating: %s"]:format(enemyText)
            if text then fontString:SetText(text); fontString:Show() end
        end)
    end

    -- 4) Setup Earnings Hooks
    if not earningsHooksDone then
        local frame = _G.PVPMatchResults
        if frame then
            earningsHooksDone = true
            if frame.DisplayRewards then
                hooksecurefunc(frame, "DisplayRewards", UpdateEarningsRating)
            end
        end
    end
end

-- ============================================================================
-- EVENT FRAME (FIXED)
-- ============================================================================
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PVP_MATCH_COMPLETE")
f:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        -- Пытаемся поставить хуки как при загрузке своего аддона,
        -- так и при загрузке Blizzard_PVPMatch (порядок может быть любым).
        if arg1 == addonName then
            SetupPVPMatchHooks()
        end
        return
    end
    if event == "UPDATE_BATTLEFIELD_SCORE" then
        if IsSupportedPvPMatch() then RecomputeRatings() end
        return
    end
    if event == "PVP_MATCH_COMPLETE" then
        if IsSupportedPvPMatch() then
            RecomputeRatings()
            UpdateEarningsRating()
        end
    end
end)

-- ============================================================================
-- EXPORT
-- ============================================================================
ns.Scoreboard = {
    Recompute = RecomputeRatings,
    GetLastApprox = function() return ns.lastArenaApprox end,
}