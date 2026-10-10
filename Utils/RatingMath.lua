local addonName, ns = ...
-- ============================================================================
-- Glicko-2 Rating System (WoW TWW/DF Model)
-- ============================================================================
local PI = math.pi
local Q = PI / 400
local Q_SQ = Q * Q

-- ============================================================================
-- Glicko-2 Core Functions
-- ============================================================================
local function g(rd)
    return 1 / math.sqrt(1 + 3 * Q_SQ * rd * rd / (PI * PI))
end

local function expectedScore(rating, opponentRating, opponentRD)
    return 1 / (1 + 10^(-g(opponentRD) * (opponentRating - rating) / 400))
end

local function updateRating(rating, rd, opponentRating, opponentRD, score)
    local E = expectedScore(rating, opponentRating, opponentRD)
    local d2 = 1 / (Q_SQ * g(opponentRD)^2 * E * (1 - E))
    local k = 400 / math.sqrt(1 + 3 * Q_SQ * rd * rd / (PI * PI))
    local newRating = rating + (k * g(opponentRD) * (score - E))
    return math.max(0, newRating)
end

local function updateRD(rd, volatility, d2)
    local preRD = math.sqrt(rd^2 + volatility^2)
    local newRD = 1 / math.sqrt(1/preRD^2 + 1/d2)
    return newRD
end

-- ============================================================================
-- Конфигурация режимов
-- ============================================================================
local MODE_CONFIG = {
    SKIRMISH = {
        initialRating = 0,
        initialRD = 350,
        minRD = 50,
        volatility = 0.06,
        maxDeltaWin = 96,    -- Максимум +96 за победу
        maxDeltaLoss = nil,
    },
    RANDOM_BG = {
        initialRating = 0,
        initialRD = 400,
        minRD = 70,
        volatility = 0.05,
        maxDeltaWin = 288,   -- Максимум +288 за победу
        maxDeltaLoss = nil,
    },
    SOLO_SHUFFLE = {
        initialRating = 0,
        initialRD = 350,
        minRD = 50,
        volatility = 0.06,
        maxDeltaWin = nil,
        maxDeltaLoss = nil,
    },
    WARGAMES = {
        initialRating = 0,
        initialRD = 400,
        minRD = 70,
        volatility = 0.05,
        maxDeltaWin = 288,
        maxDeltaLoss = nil,
    },
}

-- ============================================================================
-- API для работы с Glicko-2
-- ============================================================================
--- Обновление рейтинга после матча с ограничением delta
-- @param scoreOrWon boolean (true/false) или number (0.0 - 1.0 для агрегированного score)
-- @param db опциональная таблица для записи (используется для изолированной симуляции)
function ns.UpdateGlicko2Rating(guid, opponentRating, opponentRD, scoreOrWon, mode, db)
    db = db or ns.SkirmishDB -- Если БД не передана, используем глобальную SkirmishDB
    
    local rec = db[guid]
    if not rec then
        local config = MODE_CONFIG[mode]
        if not config then return end
        rec = {
            rating = config.initialRating,
            rd = config.initialRD,
            volatility = config.volatility,
            matches = 0,
        }
        db[guid] = rec
    end
    
    local config = MODE_CONFIG[mode]
    if not config then return end
    
    -- Нормализация score
    local score
    if type(scoreOrWon) == "boolean" then
        score = scoreOrWon and 1 or 0
    elseif type(scoreOrWon) == "number" then
        score = math.max(0, math.min(1, scoreOrWon))
    else
        score = 0.5
    end
    
    local won = (score > 0.5)
    
    -- Вычисляем d² для обновления RD
    local E = expectedScore(rec.rating, opponentRating, opponentRD)
    local d2 = 1 / (Q_SQ * g(opponentRD)^2 * E * (1 - E))
    
    -- Обновляем рейтинг
    local newRating = updateRating(rec.rating, rec.rd, opponentRating, opponentRD, score)
    
    -- Ограничиваем delta (только если задано в конфиге)
    local delta = newRating - rec.rating
    if won and config.maxDeltaWin then
        delta = math.min(delta, config.maxDeltaWin)
    elseif not won and config.maxDeltaLoss then
        delta = math.max(delta, -config.maxDeltaLoss)
    end
    
    newRating = rec.rating + delta
    newRating = math.max(0, newRating)
    
    -- Обновляем RD
    local newRD = updateRD(rec.rd, config.volatility, d2)
    newRD = math.max(config.minRD, newRD)
    
    -- Сохраняем (в переданную db, либо в глобальную SkirmishDB)
    rec.rating = newRating
    rec.rd = newRD
    rec.matches = (rec.matches or 0) + 1
    rec.lastUpdate = time()
    
    if rec.rating > (rec.bestRating or 0) then
        rec.bestRating = rec.rating
    end
    
    return rec.rating, rec.rd
end

--- Получение среднего рейтинга команды
function ns.GetTeamGlicko2Average(teamGuids, mode)
    local totalRating = 0
    local totalRD = 0
    local count = 0
    for _, guid in ipairs(teamGuids) do
        local rec = ns.SkirmishDB[guid]
        if rec and rec.rating then
            totalRating = totalRating + rec.rating
            totalRD = totalRD + rec.rd
            count = count + 1
        end
    end
    if count == 0 then return 0, 400 end
    return totalRating / count, totalRD / count
end

--- Проверка провизионального статуса
function ns.IsGlicko2Provisional(guid)
    local rec = ns.SkirmishDB[guid]
    if not rec then return true end
    return rec.rd > 200
end