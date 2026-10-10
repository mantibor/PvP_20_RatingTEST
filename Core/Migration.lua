local addonName, ns = ...

-- ============================================================================
-- Миграции сохранений: шаги по номерам, каждый выполняется один раз
-- ============================================================================
-- Номер выполненного шага — regionDB["Migration"]. Вызывается из Database.lua
-- на ADDON_LOADED: после InitArchiveKeys, до распаковки кэшей.
-- Новый шаг — дописать функцию в конец STEPS.

local function Count(t)
	local n = 0
	if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
	return n
end

local function Blob(raw)
	if type(raw) == "string" then return raw end
	if type(raw) == "table" then return rawget(raw, "blob") end
end

local STEPS = {
	-- 1. Серверы в именах — номерами LibRealmInfo (RealmPack.lua). Кэш стычек,
	--    вайтлист и чёрный список перепаковываются сами на PLAYER_LOGOUT,
	--    а записи матчей лежат готовыми блобами — их перепаковываем здесь.
	function(regionDB, matchDB)
		local done = 0
		for ts, raw in pairs(matchDB) do
			local blob = Blob(raw)
			if type(ts) == "number" and type(blob) == "string" then
				local data = ns.DecodeEntry(blob)
				local packed = type(data) == "table" and ns.EncodeEntry(data)
				if packed then matchDB[ts] = packed; done = done + 1 end
			end
		end
		return "серверы номерами, матчей " .. done
	end,

	-- 2. Двоичный формат (BinaryPack.lua): кэш стычек, вайтлист, архив матчей.
	--    Старые блобы откладываются в BinaryBackup: на следующей загрузке, когда
	--    новый формат уже прошёл запись в файл и чтение, CheckBackup их сверит.
	function(regionDB, matchDB)
		local backup = { keys = {}, matches = {} }
		local counts = {}
		for key, tag in pairs({ SkirmishData = "~K", Whitelist = "~W" }) do
			local old = regionDB[key]
			local data = type(old) == "string" and ns.DecodeEntry(old)
			local packed = type(data) == "table" and next(data) and ns.EncodeBinary(tag, data)
			if packed then
				backup.keys[key] = old
				regionDB[key] = packed
				counts[#counts + 1] = key .. " " .. #old .. " → " .. #packed .. " байт"
			end
		end
		local done = 0
		for ts, raw in pairs(matchDB) do
			local blob = Blob(raw)
			if type(ts) == "number" and type(blob) == "string" and blob:sub(1, 1) ~= "~" then
				local data = ns.DecodeEntry(blob)
				local packed = type(data) == "table" and ns.EncodeBinary("~M", data)
				if packed then backup.matches[ts] = blob; matchDB[ts] = packed; done = done + 1 end
			end
		end
		regionDB["BinaryBackup"] = backup
		counts[#counts + 1] = "матчей " .. done
		return "двоичный формат: " .. table.concat(counts, ", ")
	end,
}

-- Сверка после шага 2: новый блоб должен читаться и давать столько же записей,
-- сколько старый. Не сошлось — возвращаем старый (потерь нет), потом бэкап убираем.
local function CheckBackup(regionDB, matchDB)
	local backup = regionDB["BinaryBackup"]
	if type(backup) ~= "table" then return end
	local restored = 0
	for key, old in pairs(backup.keys or {}) do
		if Count(ns.DecodeEntry(regionDB[key] or "")) ~= Count(ns.DecodeEntry(old)) then
			regionDB[key] = old; restored = restored + 1
		end
	end
	for ts, old in pairs(backup.matches or {}) do
		local new = ns.DecodeEntry(Blob(matchDB[ts]) or "")
		local was = ns.DecodeEntry(old)
		if not new or Count(new.scores) ~= Count(was and was.scores) then
			matchDB[ts] = old; restored = restored + 1
		end
	end
	regionDB["BinaryBackup"] = nil
	if restored > 0 then
		-- файл сохранений портит этот формат — дальше пишем по-старому
		regionDB["BinaryOff"] = 1
		print("|cFFFF8000PvP 20 Rating:|r двоичный формат не прочитался после перезагрузки, старые данные возвращены (" .. restored .. ")")
	end
end

function ns.RunMigrations(regionDB, matchDB)
	if not ns.CanCompress() then return end
	CheckBackup(regionDB, matchDB)
	-- прежняя метка шага 1
	local done = tonumber(regionDB["Migration"]) or (regionDB["RealmPack"] == 1 and 1 or 0)
	regionDB["RealmPack"] = nil
	for step = done + 1, #STEPS do
		local note = STEPS[step](regionDB, matchDB)
		done = step
		if ns.DebugPrint then ns.DebugPrint("Миграция " .. step .. ": " .. tostring(note)) end
	end
	regionDB["Migration"] = done
end
