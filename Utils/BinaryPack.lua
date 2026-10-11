local addonName, ns = ...

-- ============================================================================
-- Двоичная упаковка кэша стычек (сеть и SavedVariables), без LibDeflate
-- ============================================================================
-- Запись — поток битов, а не таблица AceSerializer:
--   GUID   «Player-1602-0A1B2C3D» → 1 бит вида + номер сервера (varint) + 32 бита
--          вместо 8 шестнадцатеричных знаков; приставка «Player-» не пишется;
--   имя    алфавит на весь ник (2 бита) и по 5–6 бит на букву, см. «Имя» ниже;
--   сервер 0 — тот же, что в GUID; иначе номер по LibRealmInfo (RealmPack);
--          неизвестный библиотеке — строкой;
--   класс  4 бита по ns.CLASS_IDS;
--   числа  varint (7 бит в байте), время — секунды от ns.EPOCH_MIN.
-- Готовые байты проходят COBS: в аддон-канале нельзя байт \0. LibEncoding-COBS
-- берётся, если установлена; иначе — встроенный COBS ниже (тот же алгоритм).

local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local schar, sbyte, concat = string.char, string.byte, table.concat

-- ---------------------------------------------------------------------------
-- COBS
-- ---------------------------------------------------------------------------
local function CobsEncode(s)
	local out, block, n = {}, {}, 0
	local function flush()
		out[#out + 1] = schar(n + 1) .. concat(block)
		block, n = {}, 0
	end
	for i = 1, #s do
		local c = s:sub(i, i)
		if c == "\0" then
			flush()
		else
			n = n + 1; block[n] = c
			if n == 254 then
				out[#out + 1] = "\255" .. concat(block)
				block, n = {}, 0
				-- после полного блока «виртуального» нуля нет
				if i == #s then return concat(out) .. "\1" end
			end
		end
	end
	flush()
	return concat(out)
end

local function CobsDecode(s)
	local out, i, len = {}, 1, #s
	while i <= len do
		local code = sbyte(s, i)
		if code == 0 then return nil end
		out[#out + 1] = s:sub(i + 1, i + code - 1)
		i = i + code
		if code < 255 and i <= len then out[#out + 1] = "\0" end
	end
	return concat(out)
end

-- LibEncoding-COBS: имена функций в описании не указаны — берём, только если
-- её результат совпадает с нашим разбором (проверка при загрузке).
local Lib = LibStub and LibStub("LibEncoding-COBS", true)
if Lib then
	local enc = Lib.Encode or Lib.encode
	local dec = Lib.Decode or Lib.decode
	local probe = "a\0b\0\0" .. string.rep("x", 300)
	local ok, e = pcall(enc, Lib, probe)
	if not ok then ok, e = pcall(enc, probe) end
	if ok and type(e) == "string" and not e:find("\0", 1, true) and CobsDecode(e) == probe then
		CobsEncode = function(s) local r = enc(Lib, s); if type(r) ~= "string" then r = enc(s) end; return r end
		if dec then
			local okd = pcall(dec, Lib, e)
			CobsDecode = okd and function(s) return dec(Lib, s) end or function(s) return dec(s) end
		end
	end
end
ns.CobsEncode = function(s) return CobsEncode(s) end
ns.CobsDecode = function(s) return CobsDecode(s) end

-- ---------------------------------------------------------------------------
-- Поток битов: всё пишется подряд, без выравнивания по байтам
-- ---------------------------------------------------------------------------
local function Writer()
	local w = { parts = {}, acc = 0, nbits = 0 }
	function w.bits(v, n)
		w.acc = bor(lshift(w.acc, n), v); w.nbits = w.nbits + n
		while w.nbits >= 8 do
			w.nbits = w.nbits - 8
			w.parts[#w.parts + 1] = schar(band(rshift(w.acc, w.nbits), 255))
		end
		w.acc = band(w.acc, lshift(1, w.nbits) - 1)
	end
	function w.byte(v) w.bits(v, 8) end
	function w.varint(v)
		v = math.floor(tonumber(v) or 0)
		if v < 0 then v = 0 end
		repeat
			local b = v % 128
			v = (v - b) / 128
			w.byte(v > 0 and b + 128 or b)
		until v == 0
	end
	function w.raw(s) w.varint(#s); for k = 1, #s do w.byte(sbyte(s, k)) end end
	function w.result()
		if w.nbits > 0 then w.parts[#w.parts + 1] = schar(band(lshift(w.acc, 8 - w.nbits), 255)) end
		return concat(w.parts)
	end
	return w
end

local function Reader(s)
	local r = { pos = 1, acc = 0, nbits = 0 }
	function r.bits(n)
		while r.nbits < n do
			local b = sbyte(s, r.pos); r.pos = r.pos + 1
			if not b then error("конец данных") end
			r.acc = bor(lshift(r.acc, 8), b); r.nbits = r.nbits + 8
		end
		r.nbits = r.nbits - n
		local v = band(rshift(r.acc, r.nbits), lshift(1, n) - 1)
		r.acc = band(r.acc, lshift(1, r.nbits) - 1)
		return v
	end
	function r.byte() return r.bits(8) end
	function r.varint()
		local v, mul = 0, 1
		while true do
			local b = r.byte()
			v = v + (b % 128) * mul
			if b < 128 then return v end
			mul = mul * 128
		end
	end
	function r.raw()
		local out = {}
		for k = 1, r.varint() do out[k] = schar(r.byte()) end
		return concat(out)
	end
	-- конец: целые байты кончились, в последнем — только добивка нулями
	function r.done() return r.pos > #s and r.acc == 0 end
	return r
end

-- ---------------------------------------------------------------------------
-- Имя: алфавит на весь ник
-- ---------------------------------------------------------------------------
-- 2 бита — алфавит, 4 бита — число букв, дальше буквы. Смешанных ников
-- (кириллица с латиницей) нет: из 1933 ников армори и логов — ни одного.
--   0 латиница, 5 бит: a–z и пять частых диакритик (ø í ë î è)
--   1 кириллица, 5 бит: без ё и ъ
--   2 латиница с диакритикой, 6 бит: a–z и Latin-1 (à…ÿ, ß)
--   3 как есть, UTF-8: ник длиннее 15 букв или «не по правилам» игры
-- Код буквы 0 в алфавитах 0–2 — экранирование: 8 бит длины и сами байты.
-- Регистр не пишется: ник хранится строчными, при чтении первая буква
-- поднимается. Если ник не равен «Заглавная + строчные» (игра других не
-- даёт, но вдруг) — алфавит 3, чтобы вернуть его точь-в-точь.
local function Letters(lower, upper)
	local t = { lower = {}, upper = {}, code = {} }
	local i = 0
	for ch in lower:gmatch("[%z\1-\127\194-\244][\128-\191]*") do i = i + 1; t.lower[i] = ch; t.code[ch] = i end
	i = 0
	for ch in upper:gmatch("[%z\1-\127\194-\244][\128-\191]*") do i = i + 1; t.upper[i] = ch end
	return t
end
local LAT = "abcdefghijklmnopqrstuvwxyz"
local LAT_UP = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local ALPHABETS = {
	[0] = Letters(LAT .. "øíëîè", LAT_UP .. "ØÍËÎÈ"),
	[1] = Letters("абвгдежзийклмнопрстуфхцчшщыьэюя", "АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЫЬЭЮЯ"),
	[2] = Letters(LAT .. "àáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿß", LAT_UP .. "ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞŸß"),
}
local WIDTH = { [0] = 5, [1] = 5, [2] = 6 }
local RAW_NAME = 3
local ESCAPE = 0

-- строчные и заглавные по всем алфавитам сразу: «ё» и «ъ» — только для регистра
local TO_LOWER, TO_UPPER = { ["Ё"] = "ё", ["Ъ"] = "ъ" }, { ["ё"] = "Ё", ["ъ"] = "Ъ" }
for _, a in pairs(ALPHABETS) do
	for i, low in ipairs(a.lower) do
		if a.upper[i] ~= low then TO_LOWER[a.upper[i]] = low; TO_UPPER[low] = a.upper[i] end
	end
end

local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"

-- буквы ника строчными; nil — ник не «Заглавная + строчные»
local function LowerChars(name)
	local chars = {}
	for ch in name:gmatch(UTF8_CHAR) do chars[#chars + 1] = ch end
	for i, ch in ipairs(chars) do
		local low = TO_LOWER[ch] or ch
		if (i == 1) ~= (TO_LOWER[ch] ~= nil) then return nil end
		chars[i] = low
	end
	return chars
end

local function Cost(chars, a)
	local bits = 0
	for _, ch in ipairs(chars) do
		bits = bits + WIDTH[a] + (ALPHABETS[a].code[ch] and 0 or 8 + 8 * #ch)
	end
	return bits
end

local function WriteName(w, name)
	local chars = LowerChars(name)
	local best, bestCost
	if chars and #chars <= 15 then
		for a = 0, 2 do
			local c = Cost(chars, a)
			if not bestCost or c < bestCost then best, bestCost = a, c end
		end
	end
	if not best then w.bits(RAW_NAME, 2); w.raw(name); return end
	w.bits(best, 2); w.bits(#chars, 4)
	local codes, width = ALPHABETS[best].code, WIDTH[best]
	for _, ch in ipairs(chars) do
		local sym = codes[ch]
		if sym then
			w.bits(sym, width)
		else
			w.bits(ESCAPE, width); w.bits(#ch, 8)
			for k = 1, #ch do w.bits(sbyte(ch, k), 8) end
		end
	end
end

local function ReadName(r)
	local a = r.bits(2)
	if a == RAW_NAME then return r.raw() end
	local letters, width, out = ALPHABETS[a].lower, WIDTH[a], {}
	for i = 1, r.bits(4) do
		local sym = r.bits(width)
		if sym == ESCAPE then
			local bytes = {}
			for k = 1, r.bits(8) do bytes[k] = schar(r.bits(8)) end
			out[i] = concat(bytes)
		else
			out[i] = letters[sym]
		end
	end
	if out[1] then out[1] = TO_UPPER[out[1]] or out[1] end
	return concat(out)
end

-- ---------------------------------------------------------------------------
-- GUID и «Имя-Сервер»
-- ---------------------------------------------------------------------------
-- 1 бит вида: 1 — «Player-сервер-8hex» (номер сервера + 32 бита), 0 — строкой
local function WriteGuid(w, guid)
	local server, hex = guid:match("^Player%-(%d+)%-(%x%x%x%x%x%x%x%x)$")
	if not server then w.bits(0, 1); w.raw(guid); return nil end
	w.bits(1, 1); w.varint(tonumber(server))
	for k = 1, 8, 2 do w.byte(tonumber(hex:sub(k, k + 1), 16)) end
	return tonumber(server)
end

local function ReadGuid(r)
	if r.bits(1) == 0 then return r.raw(), nil end
	local server = r.varint()
	local hex = string.format("%02X%02X%02X%02X", r.byte(), r.byte(), r.byte(), r.byte())
	return "Player-" .. server .. "-" .. hex, server
end

-- сервер имени: 0 — как в GUID; 1 — строкой; 2+ — номер+2
local function WriteNameRealm(w, nameRealm, guidServer)
	local name, realm = tostring(nameRealm):match("^([^%-]+)%-(.+)$")
	WriteName(w, name or tostring(nameRealm))
	local id = realm and ns.RealmIdOf and ns.RealmIdOf(realm)
	if not realm then w.varint(1); w.raw("")
	elseif id and id == guidServer then w.varint(0)
	elseif id then w.varint(id + 2)
	else w.varint(1); w.raw(realm) end
end

local function ReadNameRealm(r, guidServer)
	local name = ReadName(r)
	local code = r.varint()
	local realm
	if code == 0 then realm = guidServer and ns.RealmNameOf and ns.RealmNameOf(guidServer)
	elseif code == 1 then realm = r.raw()
	else realm = ns.RealmNameOf and ns.RealmNameOf(code - 2) end
	if realm and realm ~= "" then return name .. "-" .. realm end
	return name
end


-- ---------------------------------------------------------------------------
-- Числа
-- ---------------------------------------------------------------------------
local EPOCH = ns.EPOCH_MIN or 0
local function WriteTime(w, t) w.varint(math.max(0, (tonumber(t) or EPOCH) - EPOCH)) end
local function ReadTime(r) return r.varint() + EPOCH end
-- рейтинг Glicko-2 дробный: храним десятые
local function WriteTenths(w, v) w.varint(math.floor((tonumber(v) or 0) * 10 + 0.5)) end
local function ReadTenths(r) return r.varint() / 10 end
local function WriteInt(w, v)
	v = tonumber(v) or 0
	if v ~= math.floor(v) then error("дробное число") end
	w.varint(v >= 0 and v * 2 or -v * 2 - 1)
end
local function ReadInt(r) local v = r.varint(); return v % 2 == 0 and v / 2 or -(v + 1) / 2 end

-- Поле, которого упаковщик не знает, потерялось бы — такие таблицы
-- остаются в прежнем формате (AceSerializer + Deflate).
local function OnlyKeys(tbl, allowed)
	if type(tbl) ~= "table" then return false end
	for k in pairs(tbl) do if not allowed[k] then return false end end
	return true
end
local function Set(...) local s = {}; for i = 1, select("#", ...) do s[select(i, ...)] = true end; return s end

local CLASS_IDS, CLASS_BY_ID = ns.CLASS_IDS, ns.CLASS_BY_ID
-- 4 бита: classID 1–13, 0 — неизвестен
local function WriteClass(w, class) w.bits(CLASS_IDS[class] or 0, 4) end
local function ReadClass(r) return CLASS_BY_ID[r.bits(4)] end

-- ---------------------------------------------------------------------------
-- Кэш стычек
-- ---------------------------------------------------------------------------
local SKIRMISH_KEYS = Set("name", "rating", "bestRating", "played", "won", "class", "winrate", "lastUpdate", "rd", "volatility", "matches")
local SNAPSHOT_KEYS = Set("n", "r", "b", "p", "w", "c", "u")

local function WriteSkirmish(w, guid, rec, full)
	if not OnlyKeys(rec, full and SKIRMISH_KEYS or SNAPSHOT_KEYS) then error("лишнее поле") end
	local server = WriteGuid(w, guid)
	WriteNameRealm(w, (full and rec.name or rec.n) or "?", server)
	WriteClass(w, full and rec.class or rec.c)
	WriteTenths(w, full and rec.rating or rec.r)
	WriteTenths(w, full and rec.bestRating or rec.b)
	w.varint(full and rec.played or rec.p)
	w.varint(full and rec.won or rec.w)
	WriteTime(w, full and rec.lastUpdate or rec.u)
	if full then
		WriteTenths(w, rec.rd or 350)
		w.varint(math.floor((tonumber(rec.volatility) or 0.06) * 1e5 + 0.5))
		w.varint(rec.matches)
	end
end

local function ReadSkirmish(r, full)
	local guid, server = ReadGuid(r)
	local name = ReadNameRealm(r, server)
	local class = ReadClass(r)
	local rating, best = ReadTenths(r), ReadTenths(r)
	local played, won = r.varint(), r.varint()
	local updated = ReadTime(r)
	if not full then
		return guid, { n = name, r = rating, b = best, p = played, w = won, c = class, u = updated }
	end
	return guid, {
		name = name, rating = rating, bestRating = best, played = played, won = won, class = class,
		winrate = played > 0 and (100 * won / played) or 0, lastUpdate = updated,
		rd = ReadTenths(r), volatility = r.varint() / 1e5, matches = r.varint(),
	}
end

-- ---------------------------------------------------------------------------
-- Белый список: «Имя-Сервер» → время
-- ---------------------------------------------------------------------------
local function WriteWhite(w, nameRealm, ts)
	if type(ts) ~= "number" then error("не время") end
	WriteNameRealm(w, nameRealm, nil)
	WriteTime(w, ts)
end
local function ReadWhite(r) return ReadNameRealm(r, nil), ReadTime(r) end

-- ---------------------------------------------------------------------------
-- Матч: { matchType, winner, scores = { [guid или имя] = { guid, name, class, faction, stats } } }
-- ---------------------------------------------------------------------------
local MATCH_KEYS = Set("matchType", "winner", "scores")
local SCORE_KEYS = Set("guid", "name", "class", "faction", "stats")
local STAT_KEYS = Set("pvpStatID", "pvpStatValue")

local function WriteMatch(w, db)
	if not OnlyKeys(db, MATCH_KEYS) or type(db.scores) ~= "table" then error("не матч") end
	w.raw(tostring(db.matchType or ""))
	w.varint(db.winner and db.winner + 1 or 0)
	local keys = {}
	for k in pairs(db.scores) do keys[#keys + 1] = k end
	w.varint(#keys)
	for _, key in ipairs(keys) do
		local s = db.scores[key]
		if not OnlyKeys(s, SCORE_KEYS) or type(key) ~= "string" then error("не строка счёта") end
		local keyIsGuid = (s.guid ~= nil and s.guid == key)
		w.bits((s.guid and 1 or 0) + (keyIsGuid and 2 or 0) + (s.stats and 4 or 0), 3)
		if not keyIsGuid then w.raw(key) end
		local server = s.guid and WriteGuid(w, s.guid)
		WriteNameRealm(w, s.name or "?", server)
		WriteClass(w, s.class)
		w.varint(s.faction and s.faction + 1 or 0)
		if s.stats then
			local idx = {}
			for i in pairs(s.stats) do idx[#idx + 1] = i end
			w.varint(#idx)
			for _, i in ipairs(idx) do
				local st = s.stats[i]
				if not OnlyKeys(st, STAT_KEYS) then error("не стат") end
				WriteInt(w, i); WriteInt(w, st.pvpStatID); WriteInt(w, st.pvpStatValue)
			end
		end
	end
end

local function ReadMatch(r)
	local db = { scores = {} }
	local mt = r.raw(); if mt ~= "" then db.matchType = mt end
	local winner = r.varint(); if winner > 0 then db.winner = winner - 1 end
	for _ = 1, r.varint() do
		local flags = r.bits(3)
		local key = (flags % 4 < 2) and r.raw() or nil
		local s = {}
		local server
		if flags % 2 == 1 then s.guid, server = ReadGuid(r) end
		s.name = ReadNameRealm(r, server)
		s.class = ReadClass(r)
		local faction = r.varint(); if faction > 0 then s.faction = faction - 1 end
		if flags >= 4 then
			s.stats = {}
			for _ = 1, r.varint() do
				local i = ReadInt(r)
				s.stats[i] = { pvpStatID = ReadInt(r), pvpStatValue = ReadInt(r) }
			end
		end
		db.scores[key or s.guid] = s
	end
	return db
end

-- ---------------------------------------------------------------------------
-- Обёртки: метка из двух знаков + COBS(байт формата + данные)
-- ---------------------------------------------------------------------------
-- «~» не бывает первым байтом выхода LibDeflate (EncodeForPrint — только
-- буквы, цифры и скобки; у сырого Deflate это был бы запрещённый тип блока),
-- поэтому старый и новый формат различаются по первому знаку. Метки без «ТЕГ_» —
-- очередь эти пакеты не трогает; старые клиенты их просто не разберут.
local FORMAT = 1

local function PackMap(map, writeOne, ...)
	local w = Writer()
	w.byte(FORMAT)
	local keys = {}
	for k in pairs(map) do keys[#keys + 1] = k end
	w.varint(#keys)
	for _, k in ipairs(keys) do writeOne(w, k, map[k], ...) end
	return w.result()
end

local function UnpackMap(r, readOne, ...)
	local out = {}
	for _ = 1, r.varint() do
		local k, v = readOne(r, ...)
		out[k] = v
	end
	return out
end

local CODECS = {
	["~K"] = { -- кэш стычек в SavedVariables, с параметрами Glicko-2
		pack = function(t) return PackMap(t, WriteSkirmish, true) end,
		unpack = function(r) return UnpackMap(r, ReadSkirmish, true) end },
	["~S"] = { -- снимок кэша стычек для сети
		pack = function(t) return PackMap(t, WriteSkirmish, false) end,
		unpack = function(r) return UnpackMap(r, ReadSkirmish, false) end },
	["~W"] = { -- белый список (и сохранения, и сеть)
		pack = function(t) return PackMap(t, WriteWhite) end,
		unpack = function(r) return UnpackMap(r, ReadWhite) end },
	["~M"] = { -- один матч архива
		pack = function(t) local w = Writer(); w.byte(FORMAT); WriteMatch(w, t); return w.result() end,
		unpack = ReadMatch },
}

--- Упаковывает таблицу кодеком tag. nil — таблица не подходит (лишние поля).
function ns.EncodeBinary(tag, tbl)
	local ok, bytes = pcall(CODECS[tag].pack, tbl)
	if ok then return tag .. CobsEncode(bytes) end
end

--- Распаковывает «~X…». Возвращает таблицу и метку; nil — не наш формат или битые данные.
function ns.DecodeBinary(blob)
	if type(blob) ~= "string" then return end
	local tag = blob:sub(1, 2)
	local codec = CODECS[tag]
	if not codec then return end
	local bytes = CobsDecode(blob:sub(3))
	if not bytes then return end
	local ok, data = pcall(function()
		local r = Reader(bytes)
		if r.byte() ~= FORMAT then error("неизвестный формат") end
		local t = codec.unpack(r)
		if not r.done() then error("лишние байты") end
		return t
	end)
	if ok then return data, tag end
end

--- Матч архива: двоичный формат, а если в записи есть незнакомые поля — прежний.
function ns.EncodeMatch(db)
	local off = ns.GetRegionDB and ns.GetRegionDB()["BinaryOff"]
	return (not off and ns.EncodeBinary("~M", db)) or ns.EncodeEntry(db)
end

-- ============================================================================
-- Сообщения очереди (Q_STAT, H_LIST, H_LIST_RESP, WG_SETUP…) — одним пакетом
-- ============================================================================
-- Текст режется на элементы, каждый — 3 бита вида:
--   0 кусок текста: 6 бит длины, 1 бит «только ASCII», по 7 или 8 бит на байт
--   1 ник «Имя-Сервер»: имя как выше + номер сервера в таблице сообщения,
--     2 бита роли от хоста (=T/=H/=D) и 2 бита пометки лидера (*/+)
--   2 число из 3+ цифр без ведущего нуля (время, счётчики): varint
--   3–7 разделители , ; | ~ :
-- Серверы сообщения (предложение Харфа): различные номера по возрастанию,
-- первый целиком, дальше разности — в EU номера кучкуются (500–647,
-- 1080–1127…), разности маленькие. Ник хранит только индекс в этой таблице.
-- Очередь об этом не знает: упаковка в ns.PackQueueKeys, распаковка в
-- ns.UnpackQueueKeys (Comm.lua), туда приходит уже прежний текст.
local QUEUE_TAG = "Q_B" -- «Q_» — чтобы IsQueuePayload и /dev узнавали пакет
local SEP_CODE = { [","] = 3, [";"] = 4, ["|"] = 5, ["~"] = 6, [":"] = 7 }
local SEP_CHAR = { [3] = ",", [4] = ";", [5] = "|", [6] = "~", [7] = ":" }
local ROLE_CODE, ROLE_CHAR = { T = 1, H = 2, D = 3 }, { [1] = "T", [2] = "H", [3] = "D" }
local MARK_CODE, MARK_CHAR = { ["*"] = 1, ["+"] = 2 }, { [1] = "*", [2] = "+" }

-- Разбор текста на элементы
local function Items(text)
	local items, realms = {}, {}
	local function literal(s)
		for i = 1, #s, 63 do items[#items + 1] = { kind = 0, text = s:sub(i, i + 62) } end
	end
	local function plain(s)
		-- числа из 3+ цифр без ведущего нуля — varint, остальное текстом
		local pos = 1
		while pos <= #s do
			local a, b = s:find("[1-9]%d%d+", pos)
			if not a then literal(s:sub(pos)); break end
			if a > pos then literal(s:sub(pos, a - 1)) end
			local digits = s:sub(a, b)
			if #digits <= 15 then items[#items + 1] = { kind = 2, value = tonumber(digits) }
			else literal(digits) end
			pos = b + 1
		end
	end
	for token, sep in text:gmatch("([^,;|~:]*)([,;|~:]?)") do
		if token ~= "" then
			local core, role, mark = token:match("^(.-)=([THD])([%*%+]?)$")
			if not core then core, mark = token:match("^(.-)([%*%+]?)$") end
			local name, realm = core:match("^([^%-]+)%-([^%-]+)$")
			local id = realm and ns.RealmIdOf and ns.RealmIdOf(realm)
			-- английское имя сервера разжалось бы в родное — такой ник оставляем текстом
			if id and ns.RealmNameOf(id) ~= realm then id = nil end
			local chars = id and LowerChars(name)
			if chars and #chars <= 15 then
				items[#items + 1] = { kind = 1, name = name, realm = id, role = ROLE_CODE[role] or 0, mark = MARK_CODE[mark] or 0 }
				realms[id] = true
			else
				plain(token)
			end
		end
		if sep ~= "" then items[#items + 1] = { kind = SEP_CODE[sep] } end
	end
	return items, realms
end

local function BitsFor(n) local b = 0; while lshift(1, b) < n do b = b + 1 end; return b end

function ns.PackQueueBinary(text)
	local ok, packed = pcall(function()
		local items, realmSet = Items(text)
		local realms, index = {}, {}
		for id in pairs(realmSet) do realms[#realms + 1] = id end
		table.sort(realms)
		local w = Writer()
		w.byte(FORMAT)
		w.varint(#realms)
		local prev = 0
		for i, id in ipairs(realms) do w.varint(id - prev); prev = id; index[id] = i - 1 end
		local idxBits = BitsFor(#realms)
		w.varint(#items)
		for _, it in ipairs(items) do
			w.bits(it.kind, 3)
			if it.kind == 0 then
				local ascii = not it.text:find("[\128-\255]")
				w.bits(#it.text, 6); w.bits(ascii and 1 or 0, 1)
				for k = 1, #it.text do w.bits(sbyte(it.text, k), ascii and 7 or 8) end
			elseif it.kind == 1 then
				WriteName(w, it.name)
				w.bits(index[it.realm], idxBits)
				w.bits(it.role, 2); w.bits(it.mark, 2)
			elseif it.kind == 2 then
				w.varint(it.value)
			end
		end
		return QUEUE_TAG .. CobsEncode(w.result())
	end)
	if ok then return packed end
end

function ns.UnpackQueueBinary(payload)
	if type(payload) ~= "string" or payload:sub(1, #QUEUE_TAG) ~= QUEUE_TAG then return end
	local bytes = CobsDecode(payload:sub(#QUEUE_TAG + 1))
	if not bytes then return end
	local ok, text = pcall(function()
		local r = Reader(bytes)
		if r.byte() ~= FORMAT then error("неизвестный формат") end
		local realms, prev = {}, 0
		for i = 1, r.varint() do prev = prev + r.varint(); realms[i] = prev end
		local idxBits = BitsFor(#realms)
		local out = {}
		for _ = 1, r.varint() do
			local kind = r.bits(3)
			if kind == 0 then
				local len, width = r.bits(6), (r.bits(1) == 1) and 7 or 8
				for _ = 1, len do out[#out + 1] = schar(r.bits(width)) end
			elseif kind == 1 then
				local name = ReadName(r)
				local realm = ns.RealmNameOf(realms[r.bits(idxBits) + 1]) or error("сервер не найден")
				local role, mark = r.bits(2), r.bits(2)
				out[#out + 1] = name .. "-" .. realm .. (role > 0 and ("=" .. ROLE_CHAR[role]) or "") .. (MARK_CHAR[mark] or "")
			elseif kind == 2 then
				out[#out + 1] = string.format("%d", r.varint())
			else
				out[#out + 1] = SEP_CHAR[kind]
			end
		end
		if not r.done() then error("лишние байты") end
		return concat(out)
	end)
	if ok then return text end
end
