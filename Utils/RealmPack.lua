local addonName, ns = ...

-- ============================================================================
-- Сжатие серверов в именах: «Кронов-Гордунни» ↔ «Кронов-1602»
-- ============================================================================
-- Номер — ID сервера Blizzard по LibRealmInfo. Внутри аддона имена всегда
-- полные: сжатие только на выходе и входе — Encode/Decode в Compression.lua
-- (сохранения и пакеты данных) и сообщения очереди в Comm.lua.
-- Номер отличается от прочих «-цифр» тем, что перед дефисом ровно один кусок
-- без цифр и точек: метка версии «V:09.10-06» и GUID «Player-1602-…» не подходят.
-- Неизвестный библиотеке сервер остаётся как есть.

local LRI = LibStub and LibStub("LibRealmInfo", true)
local toId, toName, toEnglish, regionOf

-- Регион в обозначениях LibRealmInfo: у аддона Америка — «NA», у библиотеки — «US».
-- Без этой замены у игроков NA ни один сервер не находился.
function ns.RealmRegion()
	local key = ns.GetRegionKey and ns.GetRegionKey()
	return key == "NA" and "US" or key
end

-- Одна таблица на сессию: GetRealmInfo в библиотеке перебирает все ~1200
-- серверов на каждый вызов, а имён в сохранениях — тысячи.
local function Build()
	toId, toName, toEnglish, regionOf = {}, {}, {}, {}
	if not LRI then return end
	local region = ns.RealmRegion()
	for id = 1, 4000 do
		local rid, _, apiName, _, _, _, realmRegion, _, _, _, englishApiName = LRI:GetRealmInfoByID(id)
		if rid then regionOf[rid] = realmRegion end
		if rid and apiName and (not region or realmRegion == region) then
			toName[rid] = apiName
			toEnglish[rid] = englishApiName or apiName
			toId[apiName] = rid
			-- английское имя того же сервера — тоже в номер (разжимается в родное)
			if englishApiName and not toId[englishApiName] then toId[englishApiName] = rid end
		end
	end
end

-- Номер сервера и обратно (Compact.lua, NamePack.lua)
function ns.RealmIdOf(realm) if not toId then Build() end return toId[realm] end
function ns.RealmNameOf(id) if not toName then Build() end return toName[id] end
-- Английское имя сервера слитно (HowlingFjord) — для лидерборда и армори
function ns.RealmEnglishName(realm)
	if not toId then Build() end
	local id = toId[realm]
	return id and toEnglish[id]
end
-- Регион сервера по номеру («EU», «US»…), любой регион; nil — LibRealmInfo его не знает
function ns.RealmRegionById(id) if not regionOf then Build() end return regionOf[id] end

-- Только «Имя-Сервер» с одним дефисом: GUID и составные строки не трогаем.
function ns.PackName(s)
	if type(s) ~= "string" then return s end
	local name, realm = s:match("^([^%-]+)%-([^%-#]+)$")
	if not name then return s end
	if not toId then Build() end
	local id = toId[realm]
	return id and (name .. "-" .. id) or s
end

function ns.UnpackName(s)
	if type(s) ~= "string" then return s end
	local name, id = s:match("^([^%-%d%.%s]+)%-(%d+)$")
	if not name then return s end
	if not toName then Build() end
	local realm = toName[tonumber(id)]
	return realm and (name .. "-" .. realm) or s
end

-- Копия таблицы с преобразованными строками (и ключами, и значениями).
-- Именно копия: Encode получает живые таблицы аддона (SkirmishDB, вайтлист).
local function Deep(v, fn)
	if type(v) == "string" then return fn(v) end
	if type(v) ~= "table" then return v end
	local out = {}
	for k, val in pairs(v) do out[Deep(k, fn)] = Deep(val, fn) end
	return out
end

function ns.PackNamesDeep(tbl) return Deep(tbl, ns.PackName) end
function ns.UnpackNamesDeep(tbl) return Deep(tbl, ns.UnpackName) end

-- Сообщения очереди: имена — поля между , ; ~ |. В составе после имени бывает
-- роль от хоста «=H/=D/=T» и пометка лидера «*»/«+» — их сохраняем.
local function MapTokens(text, fn)
	return (text:gsub("[^,;~|]+", function(token)
		local core, suffix = token:match("^(.-)(=[THD][%*%+]?)$")
		if not core then core, suffix = token:match("^(.-)([%*%+]?)$") end
		return fn(core) .. suffix
	end))
end

function ns.PackNamesInText(text) return MapTokens(text, ns.PackName) end
function ns.UnpackNamesInText(text) return MapTokens(text, ns.UnpackName) end
