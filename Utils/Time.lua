local addonName, ns = ...

-- ============================================================================
-- Time & Reset Utilities
-- ============================================================================

--- Возвращает timestamp начала текущей игровой недели (серверное время)(округлённый до минуты).
function ns.GetWeekStart()
	local now = GetServerTime()
	local untilReset = C_DateAndTime.GetSecondsUntilWeeklyReset()
	local nextReset = math.floor((now + untilReset) / 60) * 60
	return nextReset - 604800
end

--- Возвращает timestamp следующего еженедельного сброса (округлённый до минуты).
function ns.GetResetTime()
	local now = GetServerTime()
	local untilReset = C_DateAndTime.GetSecondsUntilWeeklyReset()
	return math.floor((now + untilReset) / 60) * 60
end

--- Проверяет, является ли timestamp «новым» (не устаревшим).
--- Возвращает true, если ts отсутствует, меньше EPOCH_MIN
--- или не старше MAX_CACHE_AGE секунд.
function ns.IsNew(ts)
	ts = tonumber(ts)
	if not ts or ts <= ns.EPOCH_MIN then return true end
	return (time() - ts) <= ns.MAX_CACHE_AGE
end