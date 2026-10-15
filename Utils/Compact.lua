local addonName, ns = ...

-- ============================================================================
-- Короткий вид записей для сохранений и пересылки
-- ============================================================================
-- В памяти аддон работает с прежними полями (rec.rating, score.guid…); короткий
-- вид — только на входе и выходе: SavedVariables (Database.lua, Match.lua,
-- Rating.lua) и пакеты кэша (Comm.lua). Сжатие по-прежнему AceSerializer + LibDeflate.
--   поля   по одной букве (name → n, class → c…);
--   класс  номер ClassID (ns.CLASS_IDS) вместо строки;
--   ключ   ник и GUID одной строкой: «Кронов-1602-0A1B2C3D» — ник, сервер GUID,
--          игрок. Сервер ника берётся по номеру сервера GUID через LibRealmInfo.
--          Совпадают они не всегда (связанные серверы: на сохранениях тестера —
--          у 106 записей из 158), тогда сервер ника пишется перед сервером GUID:
--          «Achso-554-1329-0A1B2C3D» — номером, а если LibRealmInfo его не
--          знает, то словом.
-- Записи старого вида (ключ «Player-…», длинные поля) читаются как раньше.

local CLASS_IDS, CLASS_BY_ID = ns.CLASS_IDS, ns.CLASS_BY_ID

local function ClassId(class) return CLASS_IDS[class] or class end
local function ClassToken(c) return CLASS_BY_ID[c] or c end

--- GUID «Player-сервер-игрок» + «Имя-Сервер» → одна строка; nil — не получается.
function ns.JoinKey(guid, nameRealm)
	if type(guid) ~= "string" or type(nameRealm) ~= "string" then return nil end
	local server, player = guid:match("^Player%-(%d+)%-(%x+)$")
	local name, realm = nameRealm:match("^([^%-]+)%-([^%-]+)$")
	if not server or not name then return nil end
	local id = ns.RealmIdOf(realm)
	if id and ns.RealmNameOf(id) ~= realm then id = nil end -- английское имя сервера разжалось бы в родное
	if id == tonumber(server) then return name .. "-" .. server .. "-" .. player end
	return name .. "-" .. (id or realm) .. "-" .. server .. "-" .. player
end

--- Обратно: guid, «Имя-Сервер»; nil — строка не из JoinKey.
function ns.SplitKey(key)
	if type(key) ~= "string" then return nil end
	local name, realm, server, player = key:match("^([^%-]+)%-([^%-]+)%-(%d+)%-(%x+)$")
	if not name then
		name, server, player = key:match("^([^%-]+)%-(%d+)%-(%x+)$")
		if not name then return nil end
		realm = server
	end
	realm = tonumber(realm) and ns.RealmNameOf(tonumber(realm)) or (not tonumber(realm) and realm)
	if not realm then return nil end
	return "Player-" .. server .. "-" .. player, name .. "-" .. realm
end

-- Длинное поле → буква. Незнакомые поля переносятся как есть.
local function Rename(rec, map)
	local out = {}
	for k, v in pairs(rec) do out[map[k] or k] = v end
	return out
end
local function Invert(map) local t = {}; for k, v in pairs(map) do t[v] = k end; return t end

-- ---------------------------------------------------------------------------
-- Кэш стычек (SkirmishData): { [guid] = { name, rating, … } }
-- ---------------------------------------------------------------------------
local SKIRMISH = { name = "n", rating = "r", bestRating = "b", played = "p", won = "w", class = "c",
	lastUpdate = "u", rd = "d", volatility = "v", matches = "m" }
local SKIRMISH_LONG = Invert(SKIRMISH)

function ns.CompactSkirmish(db)
	local out = {}
	for guid, rec in pairs(db) do
		local short = Rename(rec, SKIRMISH)
		short.winrate = nil -- считается из p и w
		short.c = ClassId(short.c)
		local key = ns.JoinKey(guid, rec.name)
		if key then short.n = nil else key = guid end
		out[key] = short
	end
	return out
end

local function Winrate(rec)
	local played = tonumber(rec.played) or 0
	rec.winrate = played > 0 and (100 * (tonumber(rec.won) or 0) / played) or 0
end

function ns.ExpandSkirmish(db)
	local out = {}
	for key, rec in pairs(db) do
		if type(key) == "string" and key:sub(1, 7) == "Player-" and rec.name then
			out[key] = rec -- старый вид
		elseif type(rec) == "table" then
			local long = Rename(rec, SKIRMISH_LONG)
			long.class = ClassToken(long.class)
			-- ник отдельным полем — значит ключ остался GUID (склеить не вышло)
			local guid, name = key, nil
			if not rec.n then guid, name = ns.SplitKey(key) end
			if guid then long.name = long.name or name else guid = key end
			Winrate(long)
			out[guid] = long
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Снимок кэша для сети: { [guid] = { n, r, b, p, w, c, u } } — поля уже короткие;
-- ключ — JoinKey, класс — номер, u — разница с base (ns.TimeBase).
-- ---------------------------------------------------------------------------
function ns.CompactSnapshot(snapshot, base)
	local out = {}
	for guid, rec in pairs(snapshot) do
		local short = { r = rec.r, b = rec.b, p = rec.p, w = rec.w, c = ClassId(rec.c), u = base - (tonumber(rec.u) or base) }
		local key = ns.JoinKey(guid, rec.n)
		if key then out[key] = short else short.n = rec.n; out[guid] = short end
	end
	return out
end

function ns.ExpandSnapshot(snapshot, base)
	local out = {}
	for key, rec in pairs(snapshot) do
		if type(rec) == "table" then
			local guid, name
			if not rec.n then guid, name = ns.SplitKey(key) end
			out[guid or key] = { n = name or rec.n, r = rec.r, b = rec.b, p = rec.p, w = rec.w,
				c = ClassToken(rec.c), u = base - (tonumber(rec.u) or 0) }
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Матч: { matchType, winner, scores = { [guid или «Имя-Сервер»] = { guid, name, class, faction, stats } } }
-- ---------------------------------------------------------------------------
-- Во время активного матча GUID — секрет (ns.SafeGuid даёт nil), строка счёта
-- лежит под «Имя-Сервер» без guid — так она и сохраняется, склеивать не с чем.
local MATCH = { matchType = "t", winner = "w", scores = "s" }
local SCORE = { guid = "g", name = "n", class = "c", faction = "f", stats = "s" }
local STAT = { pvpStatID = "i", pvpStatValue = "v" }
local MATCH_LONG, SCORE_LONG, STAT_LONG = Invert(MATCH), Invert(SCORE), Invert(STAT)

local function Stats(stats, map)
	if type(stats) ~= "table" then return stats end
	local out = {}
	for i, st in pairs(stats) do out[i] = type(st) == "table" and Rename(st, map) or st end
	return out
end

function ns.CompactMatch(db)
	if type(db) ~= "table" or type(db.scores) ~= "table" then return db end
	local out = Rename(db, MATCH)
	out.s = {}
	for key, score in pairs(db.scores) do
		local short = Rename(score, SCORE)
		short.c = ClassId(short.c)
		short.s = Stats(short.s, STAT)
		local joined = ns.JoinKey(score.guid, score.name)
		if joined and key == score.guid then
			key, short.g, short.n = joined, nil, nil
		elseif key == score.name then
			short.n = nil -- ник и так в ключе
		end
		out.s[key] = short
	end
	return out
end

function ns.ExpandMatch(db)
	if type(db) ~= "table" or type(db.s) ~= "table" or db.scores then return db end -- старый вид
	local out = Rename(db, MATCH_LONG)
	out.scores = {}
	for key, short in pairs(db.s) do
		local score = Rename(short, SCORE_LONG)
		score.class = ClassToken(score.class)
		score.stats = Stats(score.stats, STAT_LONG)
		local guid, name
		if not short.n and not short.g then guid, name = ns.SplitKey(key) end
		if guid then
			score.guid, score.name, key = guid, name, guid
		elseif not score.name then
			score.name = key
		end
		out.scores[key] = score
	end
	return out
end

--- Матч для SavedVariables и пересылки: короткий вид → AceSerializer + LibDeflate.
function ns.EncodeMatch(db) return ns.EncodeEntry(ns.CompactMatch(db)) end
function ns.DecodeMatch(blob) return ns.ExpandMatch(ns.DecodeEntry(blob)) end
