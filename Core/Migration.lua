local addonName, ns = ...

-- ============================================================================
-- Миграции сохранений: шаги по номерам, каждый выполняется один раз
-- ============================================================================
-- Номер выполненного шага — regionDB["Schema"]. Вызывается из Database.lua на
-- ADDON_LOADED: после InitArchiveKeys, до распаковки кэшей. Новый шаг —
-- функция в конец STEPS.

local function Blob(raw)
	if type(raw) == "string" then return raw end
	if type(raw) == "table" then return rawget(raw, "blob") end
end

local STEPS = {
	-- 1. Серверы в именах — номерами LibRealmInfo (Utils/RealmPack.lua). Кэш
	--    стычек, вайтлист и чёрный список перепаковываются сами на PLAYER_LOGOUT,
	--    записи матчей лежат готовыми блобами — их перепаковываем здесь.
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

	-- 2. Короткий вид (Utils/Compact.lua): поля по одной букве, класс номером,
	--    ник и GUID одной строкой. Кэш стычек и архив матчей.
	function(regionDB, matchDB)
		local done = 0
		for ts, raw in pairs(matchDB) do
			local blob = Blob(raw)
			if type(ts) == "number" and type(blob) == "string" then
				local data = ns.DecodeMatch(blob)
				local packed = type(data) == "table" and ns.EncodeMatch(data)
				if packed then matchDB[ts] = packed; done = done + 1 end
			end
		end
		local skirmish = type(regionDB["SkirmishData"]) == "string" and ns.DecodeEntry(regionDB["SkirmishData"])
		if type(skirmish) == "table" then
			regionDB["SkirmishData"] = ns.EncodeEntry(ns.CompactSkirmish(ns.ExpandSkirmish(skirmish))) or regionDB["SkirmishData"]
		end
		return "короткий вид, матчей " .. done
	end,
}

-- Двоичный формат из PR #2 (ветка binary-cache, сборка 10.10-06) отменён. Кто
-- успел на нём зайти, у того блобы «~K/~W/~M» и номер шага в regionDB["Migration"].
-- Есть бэкап прежних блобов — возвращаем его; нет — двоичные блобы убираем:
-- кэш и матчи заново придут от других игроков.
local function DropBinaryFormat(regionDB, matchDB)
	if regionDB["Migration"] == nil and regionDB["BinaryBackup"] == nil then return end
	local backup = type(regionDB["BinaryBackup"]) == "table" and regionDB["BinaryBackup"] or {}
	local dropped = 0
	for key, old in pairs(backup.keys or {}) do regionDB[key] = old end
	for ts, old in pairs(backup.matches or {}) do matchDB[ts] = old end
	for _, key in ipairs({ "SkirmishData", "Whitelist" }) do
		if type(regionDB[key]) == "string" and regionDB[key]:sub(1, 1) == "~" then regionDB[key] = nil; dropped = dropped + 1 end
	end
	for ts, raw in pairs(matchDB) do
		if type(raw) == "string" and raw:sub(1, 1) == "~" then matchDB[ts] = nil; dropped = dropped + 1 end
	end
	if (tonumber(regionDB["Migration"]) or 0) >= 1 then regionDB["Schema"] = regionDB["Schema"] or 1 end
	regionDB["Migration"], regionDB["BinaryBackup"], regionDB["BinaryOff"] = nil, nil, nil
	if dropped > 0 then
		print("|cFFFF8000PvP 20 Rating:|r двоичный формат отменён, без бэкапа убрано блобов: " .. dropped .. " — данные придут от других игроков")
	end
end

function ns.RunMigrations(regionDB, matchDB)
	if not ns.CanCompress() then return end
	DropBinaryFormat(regionDB, matchDB)
	-- прежняя метка шага 1
	local done = tonumber(regionDB["Schema"]) or (regionDB["RealmPack"] == 1 and 1 or 0)
	regionDB["RealmPack"] = nil
	for step = done + 1, #STEPS do
		local note = STEPS[step](regionDB, matchDB)
		done = step
		if ns.DebugPrint then ns.DebugPrint("Миграция " .. step .. ": " .. tostring(note)) end
	end
	regionDB["Schema"] = done
end
