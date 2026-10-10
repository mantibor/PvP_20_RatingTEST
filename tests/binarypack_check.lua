-- Проверка Utils/BinaryPack.lua вне игры: туда-обратно для кэша стычек,
-- сетевого снимка, вайтлиста и матча; COBS на краях; размеры.
-- Запуск: luajit tests/binarypack_check.lua [папка аддона] [файл SavedVariables]
-- С файлом сохранений — ещё и перепаковка настоящих данных с размерами до и после.
local A = arg[1] or (arg[0]:match("^(.*)[/\\]tests[/\\][^/\\]+$") or ".")
strmatch, strtrim, strlen = string.match, function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end, string.len
strsplit = function(d, s) local t = {}; for p in (s .. d):gmatch("(.-)" .. d:gsub("%p", "%%%0")) do t[#t + 1] = p end; return unpack(t) end
strsub, strbyte, strchar, gsub, format, tinsert = string.sub, string.byte, string.char, string.gsub, string.format, table.insert
GetCurrentRegion = function() return 3 end
dofile(A .. "/Libs/LibStub/LibStub.lua")
local function load(path, ns) local f = assert(loadfile(A .. "/" .. path)); f("PvP_20_RatingTEST", ns) end
local ns = {}
load("Config/Constants.lua", ns)
ns.GetRegionKey = function() return ns.REGION_KEYS[GetCurrentRegion()] end
loadfile(A .. "/Libs/LibRealmInfo/LibRealmInfo.lua")("PvP_20_RatingTEST")
loadfile(A .. "/Libs/LibDeflate/LibDeflate.lua")("PvP_20_RatingTEST")
pcall(function() loadfile(A .. "/Libs/AceSerializer-3.0/AceSerializer-3.0.lua")("PvP_20_RatingTEST") end)
load("Utils/Compression.lua", ns)
load("Utils/RealmPack.lua", ns)
load("Utils/BinaryPack.lua", ns)

local function same(a, b, path)
	path = path or "?"
	if type(a) == "number" and type(b) == "number" then
		assert(math.abs(a - b) <= 0.05 + 1e-9, path .. ": " .. a .. " ~= " .. b); return
	end
	if type(a) ~= "table" then assert(a == b, path .. ": " .. tostring(a) .. " ~= " .. tostring(b)); return end
	assert(type(b) == "table", path .. ": не таблица")
	for k, v in pairs(a) do same(v, b[k], path .. "." .. tostring(k)) end
	for k in pairs(b) do assert(a[k] ~= nil, path .. ": лишнее " .. tostring(k)) end
end

-- COBS на краях: нули, блоки 254 и 255
for _, s in ipairs({ "", "\0", "\0\0", "a", string.rep("x", 253), string.rep("x", 254), string.rep("x", 255),
	string.rep("x", 254) .. "\0", "\0" .. string.rep("y", 600) .. "\0z" }) do
	local e = ns.CobsEncode(s)
	assert(not e:find("\0", 1, true), "ноль в COBS")
	assert(ns.CobsDecode(e) == s, "COBS туда-обратно, длина " .. #s)
end
print("COBS ok")

local now = ns.EPOCH_MIN + 9000000
local skirmish = {
	["Player-1602-0A1B2C3D"] = { name = "Кронов-Гордунни", rating = 1734.567, bestRating = 1801.2, played = 57, won = 31,
		class = "WARRIOR", winrate = 100 * 31 / 57, lastUpdate = now, rd = 87.43, volatility = 0.06, matches = 57 },
	["Player-1617-00000001"] = { name = "Меро-ТкачСмерти", rating = 1500, bestRating = 1500, played = 1, won = 0,
		class = "EVOKER", winrate = 0, lastUpdate = now - 5, rd = 350, volatility = 0.06, matches = 0 },
	-- сервер имени не совпадает с сервером GUID, имя с буквой не из алфавита
	["Player-1602-FFFFFFFF"] = { name = "Àrthas-ВечнаяПесня", rating = 0, bestRating = 0, played = 0, won = 0,
		class = "DEMONHUNTER", winrate = 0, lastUpdate = now, rd = 350, volatility = 0.06, matches = 0 },
	-- неизвестный библиотеке сервер, имя с неправильным регистром
	["Player-9999-12345678"] = { name = "КРОНОВ-НетТакого", rating = 1, bestRating = 2, played = 3, won = 3,
		class = "MONK", winrate = 100, lastUpdate = now, rd = 1, volatility = 0.07, matches = 300 },
}
local blob = ns.EncodeBinary("~K", skirmish)
same(skirmish, ns.DecodeEntry(blob), "кэш")
print("кэш стычек ok: 4 записи, " .. #blob .. " байт")

-- незнакомое поле — двоичный формат отказывается (данные не теряются)
local extra = { ["Player-1602-0A1B2C3D"] = { name = "Кронов-Гордунни", rating = 1, foo = 1 } }
assert(ns.EncodeBinary("~K", extra) == nil, "лишнее поле не замечено")
print("лишнее поле → прежний формат ok")

local snap = {}
for guid, r in pairs(skirmish) do snap[guid] = { n = r.name, r = r.rating, b = r.bestRating, p = r.played, w = r.won, c = r.class, u = r.lastUpdate } end
local s = ns.EncodeBinary("~S", snap)
local got, tag = ns.DecodeBinary(s)
assert(tag == "~S"); same(snap, got, "снимок")
assert(not s:find("\0", 1, true))
print("сетевой снимок ok: " .. #s .. " байт; прежний вид " .. #(ns.EncodeForSend({ v = "2", s = snap }) or ""))

local wl = { ["Кронов-Гордунни"] = now, ["Рекзеп-ВечнаяПесня"] = now - 100, ["Bob-Silvermoon"] = now - 1, ["Безсервера"] = now }
local w = ns.EncodeBinary("~W", wl)
same(wl, ns.DecodeEntry(w), "вайтлист")
print("вайтлист ok: " .. #w .. " байт; прежний вид " .. #(ns.EncodeEntry(wl) or ""))

local match = { matchType = "solo_shuffle", winner = 1, scores = {} }
for i = 1, 6 do
	local guid = string.format("Player-1602-%08X", i * 7919)
	match.scores[guid] = { guid = guid, name = "Игрок" .. string.rep("а", i) .. "-Гордунни", class = ns.CLASS_BY_ID[i], faction = i % 2,
		stats = { [1] = { pvpStatID = 1032, pvpStatValue = i }, [3] = { pvpStatID = 7, pvpStatValue = -2 } } }
end
match.scores["Безгуида-Гордунни"] = { name = "Безгуида-Гордунни", class = "MAGE" }
local m = ns.EncodeMatch(match)
assert(m:sub(1, 2) == "~M")
same(match, ns.DecodeEntry(m), "матч")
print("матч ok: " .. #m .. " байт; прежний вид " .. #(ns.EncodeEntry(match) or ""))

-- настоящие сохранения
local sv = arg[2]
if sv then
	local env = {}
	setfenv(assert(loadfile(sv)), env)()
	for region, rdb in pairs(env.PvP_20_RatingDB or {}) do
		if type(rdb) == "table" then
			for key, tag in pairs({ SkirmishData = "~K", Whitelist = "~W" }) do
				local old = rdb[key]
				if type(old) == "string" then
					local data = ns.DecodeEntry(old)
					local new = ns.EncodeBinary(tag, data)
					local n = 0; for _ in pairs(data) do n = n + 1 end
					assert(new, region .. " " .. key .. ": двоичный формат отказался")
					-- старые записи без Glicko-2 получают значения по умолчанию, как в SaveSharedData
					if key == "SkirmishData" then
						for _, r in pairs(data) do r.rd, r.volatility, r.matches = r.rd or 350, r.volatility or 0.06, r.matches or 0 end
					end
					same(data, ns.DecodeEntry(new), key)
					print(string.format("%s %s: %d записей, %d → %d байт (%.0f%%), по %.1f байт на запись",
						region, key, n, #old, #new, 100 * #new / #old, #new / n))
				end
			end
		end
	end
end
print("всё ok")
