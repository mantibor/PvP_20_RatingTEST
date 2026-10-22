local addonName, ns = ...

-- ============================================================================
-- Пересылка списков ников: вайтлист, H_LIST, H_LIST_RESP, WG_SETUP
-- ============================================================================
-- Сообщение — поток битов, поверх него LibDeflate:EncodeForWoWAddonChannel
-- (в аддон-канале нельзя байт \0; сжатия тут нет, только замена этого байта):
--   ник     2 бита алфавита, 4 бита числа букв, по 5–6 бит на букву;
--           регистр не пишется — строчные по таблице букв ниже, первая буква
--           поднимается при чтении;
--   сервер  номера LibRealmInfo всех серверов сообщения — по возрастанию,
--           первый целиком, дальше разности; ник хранит индекс в этом списке.
-- Пакет уходит, только если разжимается точь-в-точь в исходный текст
-- (проверка в ns.PackQueueKeys) — иначе прежний текстовый вид.

local LibDeflate = LibStub("LibDeflate")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local schar, sbyte, concat = string.char, string.byte, table.concat

local FORMAT = 1

-- ---------------------------------------------------------------------------
-- Поток битов
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
	function w.varint(v)
		v = math.floor(tonumber(v) or 0)
		if v < 0 then error("отрицательное") end
		repeat
			local b = v % 128
			v = (v - b) / 128
			w.bits(v > 0 and b + 128 or b, 8)
		until v == 0
	end
	-- со знаком: 0, -1, 1, -2… → 0, 1, 2, 3…
	function w.signed(v) w.varint(v >= 0 and v * 2 or -v * 2 - 1) end
	function w.raw(s) w.varint(#s); for k = 1, #s do w.bits(sbyte(s, k), 8) end end
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
	function r.varint()
		local v, mul = 0, 1
		while true do
			local b = r.bits(8)
			v = v + (b % 128) * mul
			if b < 128 then return v end
			mul = mul * 128
		end
	end
	function r.signed() local v = r.varint(); return v % 2 == 0 and v / 2 or -(v + 1) / 2 end
	function r.raw()
		local out = {}
		for k = 1, r.varint() do out[k] = schar(r.bits(8)) end
		return concat(out)
	end
	function r.done() return r.pos > #s and r.acc == 0 end
	return r
end

local function BitsFor(n) local b = 0; while lshift(1, b) < n do b = b + 1 end; return b end

-- ---------------------------------------------------------------------------
-- Ник: алфавит на весь ник
-- ---------------------------------------------------------------------------
-- Смешанных ников (кириллица с латиницей) нет — проверено на 1933 никах армори
-- и логов. Алфавиты:
--   0 латиница, 5 бит: a–z и пять частых диакритик
--   1 кириллица, 5 бит: без ё и ъ (они — через экранирование)
--   2 латиница с диакритикой, 6 бит: a–z и строчные Latin-1
--   3 ник как есть (UTF-8): длиннее 15 букв или не «Заглавная + строчные»
-- Код буквы 0 — экранирование: 8 бит длины и байты буквы.
local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"
local function Chars(s)
	local out = {}
	for ch in s:gmatch(UTF8_CHAR) do out[#out + 1] = ch end
	return out
end

local function Letters(s)
	local t = { letter = Chars(s), code = {} }
	for i, ch in ipairs(t.letter) do t.code[ch] = i end
	return t
end
local LAT = "abcdefghijklmnopqrstuvwxyz"
local ALPHABETS = {
	[0] = Letters(LAT .. "øíëîè"),
	[1] = Letters("абвгдежзийклмнопрстуфхцчшщыьэюя"),
	[2] = Letters(LAT .. "àáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿß"),
}
local WIDTH = { [0] = 5, [1] = 5, [2] = 6 }
local RAW_NAME, ESCAPE = 3, 0

-- Строчные и заглавные — парами, по всем буквам алфавитов (и ё, ъ для регистра).
-- Буква не из этих пар регистра не меняет.
local LOWER = LAT .. "абвгдеёжзийклмнопрстуфхцчшщъыьэюяàáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿ"
local UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞŸ"
local TO_LOWER, TO_UPPER = {}, {}
do
	local low, up = Chars(LOWER), Chars(UPPER)
	for i, ch in ipairs(low) do TO_LOWER[up[i]] = ch; TO_UPPER[ch] = up[i] end
end

local function Lower(chars)
	local out = {}
	for i, ch in ipairs(chars) do out[i] = TO_LOWER[ch] or ch end
	return out
end

local function Capitalize(chars)
	if not chars[1] then return "" end
	return (TO_UPPER[chars[1]] or chars[1]) .. concat(chars, "", 2)
end

local function WriteNick(w, nick)
	local lower = Lower(Chars(nick))
	local n = #lower
	local best, bestCost
	if n <= 15 and Capitalize(lower) == nick then
		for a = 0, 2 do
			local cost = 0
			for i = 1, n do
				local ch = lower[i]
				cost = cost + WIDTH[a] + (ALPHABETS[a].code[ch] and 0 or 8 + 8 * #ch)
			end
			if not bestCost or cost < bestCost then best, bestCost = a, cost end
		end
	end
	if not best then w.bits(RAW_NAME, 2); w.raw(nick); return end
	w.bits(best, 2); w.bits(n, 4)
	local codes, width = ALPHABETS[best].code, WIDTH[best]
	for i = 1, n do
		local ch = lower[i]
		if codes[ch] then
			w.bits(codes[ch], width)
		else
			w.bits(ESCAPE, width); w.bits(#ch, 8)
			for k = 1, #ch do w.bits(sbyte(ch, k), 8) end
		end
	end
end

local function ReadNick(r)
	local a = r.bits(2)
	if a == RAW_NAME then return r.raw() end
	local letters, width, out = ALPHABETS[a].letter, WIDTH[a], {}
	for i = 1, r.bits(4) do
		local sym = r.bits(width)
		if sym == ESCAPE then
			local bytes = {}
			for k = 1, r.bits(8) do bytes[k] = schar(r.bits(8)) end
			out[i] = concat(bytes)
		else
			out[i] = letters[sym] or error("нет буквы")
		end
	end
	return Capitalize(out)
end

-- ---------------------------------------------------------------------------
-- Список «Имя-Сервер» с таблицей серверов
-- ---------------------------------------------------------------------------
-- Сервер, которого нет в LibRealmInfo (или записанный не родным именем),
-- идёт строкой: индекс = число серверов в таблице, дальше строка.
local function SplitName(nameRealm)
	local name, realm = nameRealm:match("^([^%-]+)%-([^%-]+)$")
	if not name then error("не «Имя-Сервер»: " .. nameRealm) end
	local id = ns.RealmIdOf(realm)
	if id and ns.RealmNameOf(id) ~= realm then id = nil end
	return name, realm, id
end

local function WriteRealmTable(w, names)
	local set, ids, index = {}, {}, {}
	for _, nameRealm in ipairs(names) do
		local _, _, id = SplitName(nameRealm)
		if id and not set[id] then set[id] = true; ids[#ids + 1] = id end
	end
	table.sort(ids)
	w.varint(#ids)
	local prev = 0
	for i, id in ipairs(ids) do w.varint(id - prev); prev = id; index[id] = i - 1 end
	return { index = index, bits = BitsFor(#ids + 1), count = #ids }
end

local function ReadRealmTable(r)
	local ids, prev = {}, 0
	for i = 1, r.varint() do prev = prev + r.varint(); ids[i] = prev end
	return { ids = ids, bits = BitsFor(#ids + 1), count = #ids }
end

local function WriteName(w, rt, nameRealm)
	local name, realm, id = SplitName(nameRealm)
	WriteNick(w, name)
	if id then
		w.bits(rt.index[id], rt.bits)
	else
		w.bits(rt.count, rt.bits); w.raw(realm)
	end
end

local function ReadName(r, rt)
	local name = ReadNick(r)
	local idx = r.bits(rt.bits)
	local realm = (idx == rt.count) and r.raw() or ns.RealmNameOf(rt.ids[idx + 1]) or error("сервер не найден")
	return name .. "-" .. realm
end

local function Split(s, sep)
	local out = {}
	if s == "" then return out end
	for part in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
	return out
end

-- ---------------------------------------------------------------------------
-- Сообщения
-- ---------------------------------------------------------------------------
-- Метка «N_x»: «N_» — чтобы ns.IsQueuePayload и /dev видели пакет очереди.
local ROLE_CODE, ROLE_CHAR = { T = 1, H = 2, D = 3 }, { [1] = "T", [2] = "H", [3] = "D" }
local MARK_CODE, MARK_CHAR = { ["*"] = 1, ["+"] = 2 }, { [1] = "*", [2] = "+" }

local function Team(text)
	local out = {}
	for i, token in ipairs(Split(text, ";")) do
		local name, role, mark = token:match("^(.-)=([THD])([%*%+]?)$")
		if not name then name, mark = token:match("^(.-)([%*%+]?)$") end
		out[i] = { name = name, role = ROLE_CODE[role] or 0, mark = MARK_CODE[mark] or 0 }
	end
	return out
end

local function TeamText(team)
	local out = {}
	for i, p in ipairs(team) do
		out[i] = p.name .. (p.role > 0 and ("=" .. ROLE_CHAR[p.role]) or "") .. (MARK_CHAR[p.mark] or "")
	end
	return concat(out, ";")
end

local CODECS = {
	-- H_LIST,KEY,имя;имя;…
	L = {
		match = function(text) local key, list = text:match("^H_LIST,([^,]*),(.*)$"); return key and { key = key, names = Split(list, ";") } end,
		write = function(w, m)
			w.raw(m.key)
			local rt = WriteRealmTable(w, m.names)
			w.varint(#m.names)
			for _, n in ipairs(m.names) do WriteName(w, rt, n) end
		end,
		read = function(r)
			local key = r.raw()
			local rt = ReadRealmTable(r)
			local names = {}
			for i = 1, r.varint() do names[i] = ReadName(r, rt) end
			return "H_LIST," .. key .. "," .. concat(names, ";")
		end,
	},
	-- H_LIST_RESP,KEY,отвечающий,число,имя;имя;… — число равно числу имён, его не пишем
	R = {
		match = function(text)
			local key, reporter, count, list = text:match("^H_LIST_RESP,([^,]*),([^,]*),(%d+),(.*)$")
			if not key then return nil end
			local found = Split(list, ";")
			if tonumber(count) ~= #found then return nil end
			return { key = key, reporter = reporter, found = found }
		end,
		write = function(w, m)
			w.raw(m.key)
			local all = { m.reporter }
			for _, n in ipairs(m.found) do all[#all + 1] = n end
			local rt = WriteRealmTable(w, all)
			w.varint(#m.found)
			for _, n in ipairs(all) do WriteName(w, rt, n) end
		end,
		read = function(r)
			local key = r.raw()
			local rt = ReadRealmTable(r)
			local count = r.varint()
			local reporter, found = ReadName(r, rt), {}
			for i = 1, count do found[i] = ReadName(r, rt) end
			return string.format("H_LIST_RESP,%s,%s,%d,%s", key, reporter, count, concat(found, ";"))
		end,
	},
	-- WG_SETUP,KEY,команда A,команда B; игрок — имя[=роль][*|+]
	S = {
		match = function(text)
			local key, a, b = text:match("^WG_SETUP,([^,]*),([^,]*),([^,]*)$")
			return key and { key = key, a = Team(a), b = Team(b) }
		end,
		write = function(w, m)
			w.raw(m.key)
			local names = {}
			for _, team in ipairs({ m.a, m.b }) do for _, p in ipairs(team) do names[#names + 1] = p.name end end
			local rt = WriteRealmTable(w, names)
			for _, team in ipairs({ m.a, m.b }) do
				w.varint(#team)
				for _, p in ipairs(team) do WriteName(w, rt, p.name); w.bits(p.role, 2); w.bits(p.mark, 2) end
			end
		end,
		read = function(r)
			local key = r.raw()
			local rt = ReadRealmTable(r)
			local teams = {}
			for t = 1, 2 do
				teams[t] = {}
				for i = 1, r.varint() do teams[t][i] = { name = ReadName(r, rt), role = r.bits(2), mark = r.bits(2) } end
			end
			return "WG_SETUP," .. key .. "," .. TeamText(teams[1]) .. "," .. TeamText(teams[2])
		end,
	},
}

local function Encode(tag, write, m)
	local w = Writer()
	w.bits(FORMAT, 8)
	write(w, m)
	return "N_" .. tag .. LibDeflate:EncodeForWoWAddonChannel(w.result())
end

local function Decode(payload, read)
	local bytes = LibDeflate:DecodeForWoWAddonChannel(payload:sub(4)) or error("не раскодировалось")
	local r = Reader(bytes)
	if r.bits(8) ~= FORMAT then error("неизвестный формат") end
	local out = read(r)
	if not r.done() then error("лишние байты") end
	return out
end

--- Сообщение очереди с ником-списком → пакет «N_L/N_R/N_S…»; nil — не подходит.
function ns.PackNameMessage(text)
	for tag, codec in pairs(CODECS) do
		local m = codec.match(text)
		if m then
			local ok, packed = pcall(Encode, tag, codec.write, m)
			return ok and packed or nil
		end
	end
end

--- Пакет «N_L/N_R/N_S…» → прежний текст; nil — не наш пакет или битый.
function ns.UnpackNameMessage(payload)
	if type(payload) ~= "string" or payload:sub(1, 2) ~= "N_" then return nil end
	local codec = CODECS[payload:sub(3, 3)]
	if not codec then return nil end
	local ok, text = pcall(Decode, payload, codec.read)
	return ok and text or nil
end

-- ---------------------------------------------------------------------------
-- Вайтлист: { ["Имя-Сервер"] = время } → «N_W…»
-- ---------------------------------------------------------------------------
-- Время — секунд от начала сезона региона (ns.SeasonBase), со знаком.
function ns.PackWhitelist(list)
	local base = ns.SeasonBase()
	local names = {}
	for name, ts in pairs(list) do
		if type(name) == "string" and type(ts) == "number" and pcall(SplitName, name) then names[#names + 1] = name end
	end
	local ok, packed = pcall(Encode, "W", function(w)
		local rt = WriteRealmTable(w, names)
		w.varint(#names)
		for _, name in ipairs(names) do WriteName(w, rt, name); w.signed(math.floor(list[name]) - base) end
	end)
	return ok and packed or nil
end

function ns.UnpackWhitelist(payload)
	if type(payload) ~= "string" or payload:sub(1, 3) ~= "N_W" then return nil end
	local ok, list = pcall(Decode, payload, function(r)
		local base = ns.SeasonBase()
		local rt = ReadRealmTable(r)
		local out = {}
		for _ = 1, r.varint() do
			local name = ReadName(r, rt)
			out[name] = base + r.signed()
		end
		return out
	end)
	return ok and list or nil
end
