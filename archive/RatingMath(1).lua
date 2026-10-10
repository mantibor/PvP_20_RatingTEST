local addonName, ns = ...

-- ============================================================================
-- Rating Math: Elo / Flat / BG Models
-- ============================================================================
-- Все математические константы инкапсулированы здесь, так как они используются 
-- исключительно внутри формул расчета рейтинга.

local BASELINE        = 1500
local FLAT_GAIN       = 96
local FLAT_UNTIL      = 800
local TAPER_MIN       = 48
local K_FACTOR        = 32
local RATING_INFLATION = 1.3

--- Ожидаемый результат по формуле Эло (0..1).
function ns.EloExpected(mine, theirs)
	return 1 / (1 + 10 ^ ((theirs - mine) / 400))
end

--- Вычисляет новый рейтинг для стычки (Skirmish Arena).
--- До BASELINE — плоский набор (Flat Gain). Выше — Эло с инфляцией побед.
function ns.ComputeNewRatingSkirmish(oldRating, hasRating, won, enemyAvg, allyAvg)
	if not hasRating then oldRating = 0 end

	-- Flat-gain фаза (ниже BASELINE)
	if oldRating < BASELINE then
		if not won then return oldRating end
		local gain
		if oldRating < FLAT_UNTIL then
			gain = FLAT_GAIN
		else
			local t = (oldRating - FLAT_UNTIL) / (BASELINE - FLAT_UNTIL)
			gain = FLAT_GAIN + (TAPER_MIN - FLAT_GAIN) * t
		end
		return math.floor(oldRating + gain + 0.5)
	end

	-- Elo-фаза (выше BASELINE)
	local expected = ns.EloExpected(oldRating, enemyAvg or BASELINE)
	local score = won and 1 or 0
	local delta = K_FACTOR * (score - expected)
	if won then
		delta = delta * RATING_INFLATION
		if delta < 1 then delta = 1 end
	end
	local newRating = oldRating + delta
	if newRating < 0 then newRating = 0 end
	return math.floor(newRating + 0.5)
end

--- Вычисляет дельту рейтинга для случайных полей боя (Random BG).
--- До 1000 — упрощённая модель (CR_WIN с затуханием).
--- Выше 1000 — Эло с K=70, клиппинг ±65.
function ns.CalculateBGRatingDelta(currentRating, enemyAvgRating, isWin)
	currentRating = currentRating or 0

	-- Упрощённая модель для новичков
	if currentRating < 1000 then
		local CR_WIN = 288
		local t = math.max(0.0, 1.0 - currentRating / 2600)
		local delta = math.floor(CR_WIN * t + 0.5)
		return isWin and delta or -48
	end

	-- Эло-модель
	if not enemyAvgRating or enemyAvgRating <= 0 then
		enemyAvgRating = currentRating
	end
	local K = 70
	local diff = enemyAvgRating - currentRating
	local E = 1.0 / (1.0 + 10.0 ^ (diff / 400.0))
	local score = isWin and 1.0 or 0.0
	local delta = K * (score - E)
	if delta < -65 then delta = -65 end
	if delta >  65 then delta =  65 end
	return math.floor(delta + 0.5)
end