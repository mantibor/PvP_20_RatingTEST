-- Проверка вне игры: короткий вид базы (Utils/Compact.lua), пакеты списков ников
-- (Utils/NamePack.lua) и время разницей (Utils/Time.lua). Настоящие LibRealmInfo,
-- LibDeflate, AceSerializer; функции WoW — заглушки.
-- Запуск: luajit tests/compact_check.lua [папка аддона] [файл SavedVariables]
local A = arg[1] or (arg[0]:match("^(.*)[/\\]tests[/\\][^/\\]+$") or ".")
strmatch, strtrim, strlen, strfind = string.match, function(s) return s end, string.len, string.find
strsplit = function(d, s) local t = {}; for p in (s .. d):gmatch("(.-)" .. d:gsub("%p", "%%%0")) do t[#t + 1] = p end; return unpack(t) end
strsub, strbyte, strchar, gsub, format, tinsert = string.sub, string.byte, string.char, string.gsub, string.format, table.insert
local NOW = 1791480058
GetServerTime = function() return NOW end
GetCurrentRegion = function() return 3 end
dofile(A .. "/Libs/LibStub/LibStub.lua")
local function lib(path) assert(loadfile(A .. "/" .. path))("PvP_20_RatingTEST") end
lib("Libs/LibRealmInfo/LibRealmInfo.lua"); lib("Libs/LibDeflate/LibDeflate.lua")
lib("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
local ns = {}
for _, f in ipairs({ "Config/Constants.lua", "Utils/Time.lua", "Utils/Compression.lua", "Utils/RealmPack.lua",
	"Utils/Compact.lua", "Utils/NamePack.lua" }) do
	if f == "Utils/RealmPack.lua" then ns.GetRegionKey = function() return "EU" end end
	assert(loadfile(A .. "/" .. f))("PvP_20_RatingTEST", ns)
end

local function same(a, b, path)
	path = path or "?"
	if type(a) ~= "table" then assert(a == b, path .. ": " .. tostring(a) .. " ~= " .. tostring(b)); return end
	assert(type(b) == "table", path .. ": не таблица")
	for k, v in pairs(a) do same(v, b[k], path .. "." .. tostring(k)) end
	for k in pairs(b) do assert(a[k] ~= nil, path .. ": лишнее " .. tostring(k)) end
end

-- время: в пересылках — от начала сезона региона
assert(ns.GetServerTimeRounded() == math.floor(NOW / 60) * 60)
local base = ns.SeasonBase()
assert(base == ns.SEASON_START_UTC[3])
print("время ok")

-- ключ «ник + GUID»
local guid1, name1 = "Player-1602-0A1B2C3D", "Кронов-Гордунни"
assert(ns.JoinKey(guid1, name1) == "Кронов-1602-0A1B2C3D", ns.JoinKey(guid1, name1))
local guid2, name2 = "Player-1329-0B4F46BC", "Achso-Ravencrest"
print("ключи: " .. ns.JoinKey(guid1, name1) .. "   " .. ns.JoinKey(guid2, name2))
for _, p in ipairs({ { guid1, name1 }, { guid2, name2 }, { "Player-1329-00000001", "Имя-НетТакого" } }) do
	local g, n = ns.SplitKey(ns.JoinKey(p[1], p[2]))
	assert(g == p[1] and n == p[2], "ключ туда-обратно: " .. p[2])
end
print("ключи ok")

-- кэш стычек
local skirmish = {
	[guid1] = { name = name1, rating = 1734.567, bestRating = 1801.2, played = 57, won = 31, class = "WARRIOR",
		winrate = 100 * 31 / 57, lastUpdate = NOW, rd = 87.43, volatility = 0.06, matches = 57 },
	[guid2] = { name = name2, rating = 1500, bestRating = 1500, played = 2, won = 0, class = "EVOKER",
		winrate = 0, lastUpdate = NOW - 5, rd = 350, volatility = 0.06, matches = 2 },
	["Player-1602-FFFFFFFF"] = { name = "Безсервера", rating = 1, bestRating = 1, played = 1, won = 1, class = "MONK",
		winrate = 100, lastUpdate = NOW, rd = 1, volatility = 0.07, matches = 1, extra = "незнакомое поле" },
}
local compact = ns.CompactSkirmish(skirmish)
same(skirmish, ns.ExpandSkirmish(compact), "кэш")
same(skirmish, ns.ExpandSkirmish(ns.DecodeEntry(ns.EncodeEntry(compact))), "кэш через AceSerializer")
same(skirmish, ns.ExpandSkirmish(skirmish), "старый вид читается")
print("кэш стычек ok")

-- снимок для сети
local snap = {}
for g, r in pairs(skirmish) do snap[g] = { n = r.name, r = r.rating, b = r.bestRating, p = r.played, w = r.won, c = r.class, u = r.lastUpdate } end
same(snap, ns.ExpandSnapshot(ns.CompactSnapshot(snap, base), base), "снимок")
print("снимок ok: " .. #ns.EncodeForSend({ v = "2", s = snap }) .. " → " .. #ns.EncodeForSend({ v = "3", s = ns.CompactSnapshot(snap, base) }) .. " байт")

-- матч: GUID известен / GUID был секретом (ключ — ник)
-- соло-суматоха: без фракций и победителя
local match = { matchType = "solo_shuffle", scores = {
	[guid1] = { guid = guid1, name = name1, class = "PRIEST", stats = { [1] = { pvpStatID = 1032, pvpStatValue = 4 } } },
	[guid2] = { guid = guid2, name = name2, class = "MAGE" },
	["Секрет-Гордунни"] = { name = "Секрет-Гордунни", class = "ROGUE" },
} }
-- старый матч SS с фракциями — при упаковке они пропадают
local oldSS = ns.CompactMatch({ matchType = "solo_shuffle", winner = 1, scores = { [guid2] = { guid = guid2, name = name2, class = "MAGE", faction = 1 } } })
assert(oldSS.w == nil and next(oldSS.s) and select(2, next(oldSS.s)).f == nil, "у SS осталась фракция")
same(match, ns.DecodeMatch(ns.EncodeMatch(match)), "матч")
same(match, ns.ExpandMatch(match), "старый вид матча читается")
print("матч ok: " .. #ns.EncodeEntry(match) .. " → " .. #ns.EncodeMatch(match) .. " байт")
-- поле боя: статы, кроме побед в раундах, не хранятся
local bg = { matchType = "random_bg", winner = 0, scores = { [guid1] = { guid = guid1, name = name1, class = "PRIEST", faction = 0,
	stats = { { pvpStatID = 1, pvpStatValue = 7 }, { pvpStatID = 2, pvpStatValue = 3 } } } } }
local bgBack = ns.DecodeMatch(ns.EncodeMatch(bg))
assert(bgBack.matchType == "random_bg" and bgBack.scores[guid1].stats == nil and ns.CompactMatch(bg).m == "RBG")
-- вид сборки 15.10-01: t и статы { i, v }
local v1 = { t = "solo_shuffle", w = 1, s = { ["Кронов-1602-0A1B2C3D"] = { c = 5, f = 0, s = { { i = 1032, v = 4 } } } } }
local e1 = ns.ExpandMatch(v1)
assert(e1.matchType == "solo_shuffle" and e1.scores[guid1].stats[1].pvpStatValue == 4, "матч 15.10-01")
print("поле боя и вид 15.10-01 ok")

-- пакеты списков ников
local P = { "Кронов-Гордунни", "Меро-ТкачСмерти", "Рекзеп-ВечнаяПесня", "Попынчик-Ревущийфьорд",
	"Разрез-Борейскаятундра", "Дуккир-Голдринн", "Øystein-Kazzak", "Lûcïa-Draenor", "Ёжик-Гордунни", "Achso-Ravencrest" }
local function team(i0, codes)
	local out = {}
	for i = 1, 5 do out[i] = P[i0 + i] .. "=" .. codes:sub(i, i) .. (i == 1 and (i0 == 0 and "*" or "+") or "") end
	return table.concat(out, ";")
end
local messages = {
	"WG_SETUP,5V5," .. team(0, "HDDDD") .. "," .. team(5, "HDDDT"),
	"WG_SETUP,SS,Кронов-Гордунни=H*;Дуккир-Голдринн=D;Ёжик-Гордунни=D,Рекзеп-ВечнаяПесня=H+;Меро-ТкачСмерти=D;Achso-Ravencrest=D",
	"H_LIST,5V5," .. table.concat(P, ";"),
	"H_LIST,SS,",
	"H_LIST_RESP,5V5,Кронов-Гордунни,3,Меро-ТкачСмерти;Øystein-Kazzak;Имя-НетТакого",
	"H_LIST_RESP,SS,Кронов-Гордунни,0,",
}
for _, text in ipairs(messages) do
	local bin = assert(ns.PackNameMessage(text), "не упаковалось: " .. text)
	local back = ns.UnpackNameMessage(bin)
	assert(back == text, "\nбыло  " .. text .. "\nстало " .. tostring(back))
	assert(not bin:find("\0", 1, true))
	print(string.format("%-12s текст %3d, серверы номерами %3d, пакет %3d байт", text:match("^[^,]+"), #text, #ns.PackNamesInText(text), #bin))
end
assert(ns.PackNameMessage("Q_STAT,SS,1") == nil)

-- вайтлист со временем
local wl = { ["Старичок-Гордунни"] = base - 3600, ["Кронов-Гордунни"] = NOW, ["Рекзеп-ВечнаяПесня"] = NOW - 86400, ["Bob-Silvermoon"] = NOW - 1, ["КРОНОВ-Гордунни"] = NOW - 7 }
local packedWL = ns.PackWhitelist(wl)
NOW = NOW + 30 -- пришёл через полминуты
same(wl, ns.UnpackWhitelist(packedWL), "вайтлист")
NOW = NOW - 30
print("вайтлист ok: " .. #ns.EncodeForSend({ v = "2", pd = wl }) .. " → " .. #packedWL .. " байт")

-- настоящие сохранения: кэш стычек и вайтлист — до и после
if arg[2] then
	local env = {}
	setfenv(assert(loadfile(arg[2])), env)()
	local rdb = env.PvP_20_RatingDB.EU
	local old = ns.DecodeEntry(rdb.SkirmishData)
	local n = 0; for _ in pairs(old) do n = n + 1 end
	local blob = ns.EncodeEntry(ns.CompactSkirmish(ns.ExpandSkirmish(old)))
	same(ns.ExpandSkirmish(old), ns.ExpandSkirmish(ns.DecodeEntry(blob)), "настоящий кэш")
	print(string.format("сохранения: кэш стычек %d записей, %d → %d байт", n, #rdb.SkirmishData, #blob))
	local w = ns.DecodeEntry(rdb.Whitelist)
	local cnt = 0; for _ in pairs(w) do cnt = cnt + 1 end
	print(string.format("сохранения: вайтлист %d ников, пересылка %d → %d байт", cnt, #ns.EncodeForSend({ v = "2", pd = w }), #ns.PackWhitelist(w)))
end
-- миграция: обычные сохранения (шаг 1 уже был) и сохранения со сборки 10.10-06 (двоичный формат)
assert(loadfile(A .. "/Core/Migration.lua"))("PvP_20_RatingTEST", ns)
local oldMatch = ns.EncodeEntry(match)
local rdb = { RealmPack = 1, SkirmishData = ns.EncodeEntry(skirmish) }
local mdb = { [1791000000] = oldMatch }
ns.RunMigrations(rdb, mdb)
assert(rdb.Schema == 4 and rdb.RealmPack == nil)
same(skirmish, ns.ExpandSkirmish(ns.DecodeEntry(rdb.SkirmishData)), "кэш после миграции")
same(match, ns.DecodeMatch(mdb[1791000000]), "матч после миграции")
assert(ns.DecodeEntry(mdb[1791000000]).s, "матч не в коротком виде")
local printed = print; print = function() end
local bin = { Migration = 2, SkirmishData = "~Kxx", Whitelist = "~Wxx", BinaryBackup = { keys = { SkirmishData = ns.EncodeEntry(skirmish) }, matches = {} } }
local binM = { [1791000000] = "~Mxx", [1791000180] = oldMatch }
ns.RunMigrations(bin, binM)
print = printed
assert(bin.Migration == nil and bin.BinaryBackup == nil and bin.Whitelist == nil and bin.Schema == 4)
same(skirmish, ns.ExpandSkirmish(ns.DecodeEntry(bin.SkirmishData)), "кэш из бэкапа")
assert(binM[1791000000] == nil and ns.DecodeMatch(binM[1791000180]))
-- «#» в старых сохранениях (сборки 10.10–16.10) переводится в «Кронов-1602»
local Ser, Def = LibStub("AceSerializer-3.0"), LibStub("LibDeflate")
local function RawBlob(t) return Def:EncodeForPrint(Def:CompressDeflate(Ser:Serialize(t))) end
local hdb = { Schema = 3, Whitelist = RawBlob({ ["Кронов-#1602"] = NOW }) }
ns.RunMigrations(hdb, {})
assert(hdb.Schema == 4 and ns.DecodeEntry(hdb.Whitelist)["Кронов-Гордунни"] == NOW, "«#» не переведён")
print("миграции ok")
print("всё ok")
