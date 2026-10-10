-- Проверка двоичных сообщений очереди (Utils/BinaryPack.lua) вне игры:
-- туда-обратно точь-в-точь и размеры против прежней упаковки (серверы номерами).
-- Запуск: luajit tests/queuepack_check.lua [папка аддона]
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
load("Utils/RealmPack.lua", ns)
load("Utils/BinaryPack.lua", ns)

local P = { "Кронов-Гордунни", "Меро-ТкачСмерти", "Рекзеп-ВечнаяПесня", "Попынчик-Ревущийфьорд",
	"Разрез-Борейскаятундра", "Дуккир-Голдринн", "Øystein-Kazzak", "Lûcïa-Draenor", "Ёжик-Гордунни",
	"Длинноимяигрок-Гордунни" }
local function roles(list, codes)
	local out = {}
	for i, n in ipairs(list) do out[i] = n .. "=" .. codes:sub(i, i) .. (i == 1 and "*" or i == 6 and "+" or "") end
	return out
end
local teamA = roles({ P[1], P[2], P[3], P[4], P[5] }, "HDDDD")
local teamB = roles({ P[6], P[7], P[8], P[9], P[10] }, "HDDDT")
local messages = {
	"WG_SETUP,5V5," .. table.concat(teamA, ";") .. "," .. table.concat(teamB, ";"),
	"WG_SETUP,SS,Кронов-Гордунни=H*;Дуккир-Голдринн=D,Рекзеп-ВечнаяПесня=H+;Меро-ТкачСмерти=D",
	"H_LIST,5V5," .. table.concat(P, ";"),
	"H_LIST_RESP,5V5,Кронов-Гордунни,4," .. table.concat({ P[2], P[3], P[7], P[8] }, ";"),
	"Q_STAT,5V5,1791480058,R:H;D,S:1,V:10.10-06,M:Кронов-Гордунни|H|S~Меро-ТкачСмерти|D|~Øystein-Kazzak|D|A",
	"Q_STAT,SS,1791480058,R:D,V:10.10-06",
	-- неизвестный сервер, английское имя сервера, без сервера, пустые поля
	"H_LIST,SS,Имя-НетТакого;Bob-Silvermoon;Безсервера;;,0,007,12345678901234567890",
}
for _, text in ipairs(messages) do
	local bin = ns.PackQueueBinary(text)
	assert(bin, "не упаковалось: " .. text)
	assert(not bin:find("\0", 1, true), "ноль в пакете")
	local back = ns.UnpackQueueBinary(bin)
	assert(back == text, "\nбыло  " .. text .. "\nстало " .. tostring(back))
	print(string.format("%-12s текст %3d, серверы номерами %3d, двоичный %3d байт",
		text:match("^[^,]+"), #text, #ns.PackNamesInText(text), #bin))
end
assert(ns.UnpackQueueBinary("Q_STAT,SS,1") == nil, "обычный текст принят за двоичный")
print("всё ok")
