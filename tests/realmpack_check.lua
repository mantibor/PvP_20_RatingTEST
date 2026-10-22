-- Проверка Utils/RealmPack.lua и Utils/Compression.lua вне игры: настоящие LibRealmInfo,
-- LibDeflate, AceSerializer из папки аддона, функции WoW — заглушки.
-- Запуск: luajit tests/realmpack_check.lua (из папки аддона) или с путём к ней первым аргументом.
local A = arg[1] or (arg[0]:match("^(.*)[/\\]tests[/\\][^/\\]+$") or ".")
strmatch, strtrim, strlen = string.match, function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end, string.len
strsplit = function(d, s) local t = {}; for p in (s .. d):gmatch("(.-)" .. d:gsub("%p", "%%%0")) do t[#t + 1] = p end; return unpack(t) end
strsub, strbyte, strchar, gsub, format, tostring, tinsert = string.sub, string.byte, string.char, string.gsub, string.format, tostring, table.insert
UnitGUID = function() return "Player-1602-00000001" end
GetCurrentRegion = function() return 3 end
dofile(A .. "/Libs/LibStub/LibStub.lua")
local function load(path, ns) local f = assert(loadfile(A .. "/" .. path)); f("PvP_20_RatingTEST", ns) end
local ns = { REGION_KEYS = { [1] = "NA", [2] = "KR", [3] = "EU", [4] = "TW", [5] = "CN" } }
ns.GetRegionKey = function() return ns.REGION_KEYS[GetCurrentRegion()] end
loadfile(A .. "/Libs/LibRealmInfo/LibRealmInfo.lua")("PvP_20_RatingTEST")
loadfile(A .. "/Libs/LibDeflate/LibDeflate.lua")("PvP_20_RatingTEST")
local okSer = pcall(function() loadfile(A .. "/Libs/AceSerializer-3.0/AceSerializer-3.0.lua")("PvP_20_RatingTEST") end)
load("Utils/RealmPack.lua", ns)
load("Utils/Compression.lua", ns)

-- имена
local P, U = ns.PackName, ns.UnpackName
local cases = { ["Кронов-Гордунни"] = "Кронов-1602", ["Меро-ТкачСмерти"] = "Меро-1617",
  ["Рекзеп-ВечнаяПесня"] = "Рекзеп-1925", ["Попынчик-Ревущийфьорд"] = "Попынчик-1615",
  ["Разрез-Борейскаятундра"] = "Разрез-1625", ["Дуккир-Голдринн"] = "Дуккир-1928" }
for full, packed in pairs(cases) do
  assert(P(full) == packed, full .. " → " .. tostring(P(full)))
  assert(U(packed) == full, packed .. " → " .. tostring(U(packed)))
end
-- не трогаем: GUID, неизвестный сервер, метка версии, имя без сервера
for _, s in ipairs({ "Player-1602-01234567", "Name-НетТакогоСервера", "09.10-06", "Кронов", "V:09.10-06" }) do
  assert(P(s) == s and U(s) == s, "тронуто: " .. s)
end
-- запись сборок до 16.10 — с «#», английские имена серверов для лидерборда
assert(U("Кронов-#1602") == "Кронов-#1602") -- «#» больше не читается (переводит Migration.lua)
assert(ns.RealmEnglishName("Гордунни") == "Gordunni" and ns.RealmEnglishName("Ревущийфьорд") == "HowlingFjord" and ns.RealmEnglishName("Kazzak") == "Kazzak")
-- похожее на номер, но не ник: метка версии, поле M:
assert(U("V:15.10-01") == "V:15.10-01")
assert(U(P("M:Кронов-Гордунни")) == "M:Кронов-Гордунни")
print("имена ok")

-- текст очереди с пометками лидеров и полем M:
local q = "WG_SETUP,SS,Кронов-Гордунни*;Дуккир-Голдринн,Рекзеп-ВечнаяПесня+;Меро-ТкачСмерти"
local pq = ns.PackNamesInText(q)
assert(pq == "WG_SETUP,SS,Кронов-1602*;Дуккир-1928,Рекзеп-1925+;Меро-1617", pq)
assert(ns.UnpackNamesInText(pq) == q)
local qr = "WG_SETUP,SS,Кронов-Гордунни=H*;Дуккир-Голдринн=D,Рекзеп-ВечнаяПесня=H+;Меро-ТкачСмерти=D"
local pqr = ns.PackNamesInText(qr)
assert(pqr == "WG_SETUP,SS,Кронов-1602=H*;Дуккир-1928=D,Рекзеп-1925=H+;Меро-1617=D", pqr)
assert(ns.UnpackNamesInText(pqr) == qr)
print("состав с ролями ok: " .. #qr .. " → " .. #pqr .. " байт")
local st = "Q_STAT,SS,1791480058,R:H;D,S:1,V:09.10-07,M:Кронов-Гордунни|H|S~Меро-ТкачСмерти|D|"
assert(ns.UnpackNamesInText(ns.PackNamesInText(st)) == st)
print("текст ok: " .. #q .. " → " .. #pq .. " байт")

-- таблицы: копия, исходник не меняется
local db = { ["Player-1602-0A"] = { name = "Кронов-Гордунни", rating = 1500 }, wl = { ["Меро-ТкачСмерти"] = 123 } }
local packed = ns.PackNamesDeep(db)
assert(db["Player-1602-0A"].name == "Кронов-Гордунни" and db.wl["Меро-ТкачСмерти"] == 123, "исходник изменён")
assert(packed["Player-1602-0A"].name == "Кронов-1602" and packed.wl["Меро-1617"] == 123)
local back = ns.UnpackNamesDeep(packed)
assert(back["Player-1602-0A"].name == "Кронов-Гордунни" and back.wl["Меро-ТкачСмерти"] == 123)
print("таблицы ok")

-- полный путь сохранения: EncodeEntry → DecodeEntry
if okSer and ns.CanCompress() then
  local blob = ns.EncodeEntry(db)
  local got = ns.DecodeEntry(blob)
  assert(got["Player-1602-0A"].name == "Кронов-Гордунни" and got.wl["Меро-ТкачСмерти"] == 123)
  print("Encode/Decode ok")
else
  print("AceSerializer не загрузился без WoW — Encode/Decode не проверены")
end
