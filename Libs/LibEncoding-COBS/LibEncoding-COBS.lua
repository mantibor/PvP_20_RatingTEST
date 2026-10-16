local MAJOR, MINOR = "LibEncoding-COBS", 1

assert(LibStub, "LibEncoding-COBS requires LibStub")

local cobs = LibStub:NewLibrary(MAJOR, MINOR)

local strfind, strsub, strbyte, strchar, tconcat = strfind, strsub, strbyte, strchar, table.concat

local CHAR =  {}
for i = 1, 254 do
    CHAR[i] = strchar(i)
end

local NULL, CHAR255 = "\0", "\255"

-- PvP_20_RatingTEST: table.create есть не во всех версиях клиента — иначе обычная таблица
local buffer = table.create and table.create(2^10) or {}

function cobs.encode(input)
    local len, startPos, buffPos, chunkLen = #input, 1, 1

    local endPos = strfind(input, NULL, startPos, true)

    while endPos do
        chunkLen = endPos - startPos

        while chunkLen >= 254 do
            buffer[buffPos] = CHAR255
            buffer[buffPos + 1] = strsub(input, startPos, startPos + 253)

            startPos = startPos + 254
            chunkLen = chunkLen - 254
            buffPos = buffPos + 2
        end

        buffer[buffPos] = CHAR[chunkLen + 1]
        buffer[buffPos + 1] = strsub(input, startPos, endPos - 1)

        startPos = endPos + 1
        buffPos = buffPos + 2

        endPos = strfind(input, NULL, startPos, true)
    end

    chunkLen = len - startPos + 1

    while chunkLen >= 254 do
        buffer[buffPos] = CHAR255
        buffer[buffPos + 1] = strsub(input, startPos, startPos + 253)

        startPos = startPos + 254
        chunkLen = chunkLen - 254
        buffPos = buffPos + 2
    end

    buffer[buffPos] = CHAR[chunkLen + 1]
    buffer[buffPos + 1] = strsub(input, startPos, len)

    return tconcat(buffer, "", 1, buffPos + 1)
end

function cobs.decode(input)
    local len = #input
    local startPos = 1
    local buffPos = 1

    while startPos <= len do
        local code = strbyte(input, startPos)
        local endPos = startPos + code - 1

        buffer[buffPos] = strsub(input, startPos + 1, endPos)
        buffPos = buffPos + 1

        startPos = endPos + 1

        if code ~= 255 and startPos <= len then
            buffer[buffPos] = NULL
            buffPos = buffPos + 1
        end
    end

    return tconcat(buffer, "", 1, buffPos - 1)
end