local addonName, ns = ...

-- ============================================================================
-- Двоичная упаковка кэша стычек (сеть и SavedVariables), без LibDeflate
-- ============================================================================
-- Запись — байты, а не таблица AceSerializer:
--   GUID   «Player-1602-0A1B2C3D» → номер сервера (varint) + 4 байта вместо
--          8 шестнадцатеричных знаков; приставка «Player-» не пишется;
--   имя    буквы по 6 бит из своего алфавита (русские + латинские), регистр
--          не пишется: в WoW имя всегда «с заглавной, остальные строчные».
--          Буква не из алфавита или «не тот» регистр — сырым UTF-8;
--   сервер 0 — тот же, что в GUID; иначе номер по LibRealmInfo (RealmPack);
--          неизвестный библиотеке — строкой;
--   класс  1 байт по ns.CLASS_IDS;
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
-- Запись и чтение байтов
-- ---------------------------------------------------------------------------
local function Writer()
	local w = { parts = {}, acc = 0, nbits = 0 }
	function w.byte(v) w.parts[#w.parts + 1] = schar(v) end
	function w.varint(v)
		v = math.floor(tonumber(v) or 0)
		if v < 0 then v = 0 end
		repeat
			local b = v % 128
			v = (v - b) / 128
			w.byte(v > 0 and b + 128 or b)
		until v == 0
	end
	function w.raw(s) w.varint(#s); w.parts[#w.parts + 1] = s end
	-- биты для имени: копим до байта
	function w.bits(v, n)
		w.acc = bor(lshift(w.acc, n), v); w.nbits = w.nbits + n
		while w.nbits >= 8 do
			w.nbits = w.nbits - 8
			w.byte(band(rshift(w.acc, w.nbits), 255))
		end
		w.acc = band(w.acc, lshift(1, w.nbits) - 1)
	end
	function w.align()
		if w.nbits > 0 then w.byte(band(lshift(w.acc, 8 - w.nbits), 255)); w.acc, w.nbits = 0, 0 end
	end
	function w.result() return concat(w.parts) end
	return w
end

local function Reader(s)
	local r = { pos = 1, acc = 0, nbits = 0 }
	function r.byte()
		local b = sbyte(s, r.pos); r.pos = r.pos + 1
		if not b then error("конец данных") end
		return b
	end
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
		local n = r.varint()
		local v = s:sub(r.pos, r.pos + n - 1); r.pos = r.pos + n
		return v
	end
	function r.bits(n)
		while r.nbits < n do r.acc = bor(lshift(r.acc, 8), r.byte()); r.nbits = r.nbits + 8 end
		r.nbits = r.nbits - n
		local v = band(rshift(r.acc, r.nbits), lshift(1, n) - 1)
		r.acc = band(r.acc, lshift(1, r.nbits) - 1)
		return v
	end
	function r.align() r.acc, r.nbits = 0, 0 end
	function r.done() return r.pos > #s end
	return r
end

-- ---------------------------------------------------------------------------
-- Имя: 6-битный алфавит
-- ---------------------------------------------------------------------------
local LOWER = { "а","б","в","г","д","е","ё","ж","з","и","й","к","л","м","н","о","п","р","с","т","у","ф","х","ц","ч","ш","щ","ъ","ы","ь","э","ю","я",
	"a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z" }
local UPPER = { "А","Б","В","Г","Д","Е","Ё","Ж","З","И","Й","К","Л","М","Н","О","П","Р","С","Т","У","Ф","Х","Ц","Ч","Ш","Щ","Ъ","Ы","Ь","Э","Ю","Я",
	"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z" }
local SYMBOL_OF_LOWER, SYMBOL_OF_UPPER = {}, {}
for i, ch in ipairs(LOWER) do SYMBOL_OF_LOWER[ch] = i end
for i, ch in ipairs(UPPER) do SYMBOL_OF_UPPER[ch] = i end
local ESCAPE = 0 -- дальше 8 бит длины символа в байтах и сами байты

local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"

local function WriteName(w, name)
	local chars = {}
	for ch in name:gmatch(UTF8_CHAR) do chars[#chars + 1] = ch end
	w.varint(#chars)
	for i, ch in ipairs(chars) do
		local sym = (i == 1) and SYMBOL_OF_UPPER[ch] or (i > 1 and SYMBOL_OF_LOWER[ch])
		if sym then
			w.bits(sym, 6)
		else
			w.bits(ESCAPE, 6); w.bits(#ch, 8)
			for k = 1, #ch do w.bits(sbyte(ch, k), 8) end
		end
	end
	w.align()
end

local function ReadName(r)
	local n, out = r.varint(), {}
	for i = 1, n do
		local sym = r.bits(6)
		if sym == ESCAPE then
			local len, bytes = r.bits(8), {}
			for k = 1, len do bytes[k] = schar(r.bits(8)) end
			out[i] = concat(bytes)
		else
			out[i] = (i == 1) and UPPER[sym] or LOWER[sym]
		end
	end
	r.align()
	return concat(out)
end

-- ---------------------------------------------------------------------------
-- GUID и «Имя-Сервер»
-- ---------------------------------------------------------------------------
local GUID_RAW, GUID_PLAYER = 0, 1

local function WriteGuid(w, guid)
	local server, hex = guid:match("^Player%-(%d+)%-(%x%x%x%x%x%x%x%x)$")
	if not server then w.byte(GUID_RAW); w.raw(guid); return nil end
	w.byte(GUID_PLAYER); w.varint(tonumber(server))
	for k = 1, 8, 2 do w.byte(tonumber(hex:sub(k, k + 1), 16)) end
	return tonumber(server)
end

local function ReadGuid(r)
	if r.byte() == GUID_RAW then return r.raw(), nil end
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
local function WriteClass(w, class) w.byte(CLASS_IDS[class] or 0) end
local function ReadClass(r) return CLASS_BY_ID[r.byte()] end

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
		w.byte((s.guid and 1 or 0) + (keyIsGuid and 2 or 0) + (s.stats and 4 or 0))
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
		local flags = r.byte()
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
