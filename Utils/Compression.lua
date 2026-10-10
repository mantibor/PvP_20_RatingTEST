local addonName, ns = ...

-- ============================================================================
-- Compression & Serialization (LibDeflate + AceSerializer)
-- ============================================================================

local AceSerializer = LibStub and LibStub("AceSerializer-3.0", true)
local LibDeflate    = LibStub and LibStub("LibDeflate", true)

--- Проверяет, доступны ли библиотеки сжатия.
function ns.CanCompress()
	return AceSerializer and LibDeflate
end

-- Внутренняя функция сжатия. Сериализует таблицу, сжимает Deflate,
-- кодирует через encodeFn.
local function Encode(tbl, encodeFn)
	if not ns.CanCompress() then return end
	-- серверы в именах — номерами (RealmPack.lua); исходная таблица не меняется
	if ns.PackNamesDeep then tbl = ns.PackNamesDeep(tbl) end
	local ok, s = pcall(AceSerializer.Serialize, AceSerializer, tbl)
	if not ok or type(s) ~= "string" then return end
	local c = LibDeflate:CompressDeflate(s, { level = 9 })
	if c then return encodeFn(c) end
end

-- Внутренняя функция распаковки. Пробует каждый декодер из списка,
-- затем DecompressDeflate и Deserialize.
local function Decode(blob, decoders)
	-- двоичный формат «~X…» (BinaryPack.lua)
	local bin = ns.DecodeBinary and ns.DecodeBinary(blob)
	if bin then return bin end
	if not ns.CanCompress() or type(blob) ~= "string" then return end
	local d
	for _, dec in ipairs(decoders) do
		d = dec(blob)
		if d then break end
	end
	if not d then return end
	d = LibDeflate:DecompressDeflate(d)
	if not d then return end
	local ok, data = AceSerializer:Deserialize(d)
	-- старые записи с полными именами проходят без изменений
	if ok then return ns.UnpackNamesDeep and ns.UnpackNamesDeep(data) or data end
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Сжимает таблицу для хранения в SavedVariables (Print-safe encoding).
function ns.EncodeEntry(data)
	return Encode(data, function(c)
		return LibDeflate:EncodeForPrint(c)
	end)
end

--- Сжимает таблицу для отправки через аддон-канал (AddonChannel encoding).
function ns.EncodeForSend(tbl)
	return Encode(tbl, function(c)
		return LibDeflate:EncodeForWoWAddonChannel(c)
	end)
end

--- Распаковывает запись из SavedVariables. Пробует оба декодера.
function ns.DecodeEntry(blob)
	return Decode(blob, {
		function(b)
			return LibDeflate:DecodeForPrint(b)
		end,
		function(b)
			return LibDeflate:DecodeForWoWAddonChannel(b)
		end,
	})
end

--- Распаковывает сетевой пакет. Только AddonChannel encoding.
function ns.DecodePayload(blob)
	return Decode(blob, {
		function(b)
			return LibDeflate:DecodeForWoWAddonChannel(b)
		end,
	})
end