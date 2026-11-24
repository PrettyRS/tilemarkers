-- A small, bounded JSON decoder for untrusted HTTP responses. JSON null is distinct
-- from a missing field, so a null cannot silently become an empty array/object.
local Json = { null = {} }
local MAX_BYTES = 64 * 1024 * 1024
local MAX_DEPTH = 32
local MAX_VALUES = 100000

local function utf8(codepoint)
    if codepoint < 0x80 then
        return string.char(codepoint)
    elseif codepoint < 0x800 then
        return string.char(0xC0 + math.floor(codepoint / 64), 0x80 + codepoint % 64)
    elseif codepoint < 0x10000 then
        return string.char(0xE0 + math.floor(codepoint / 4096),
            0x80 + math.floor(codepoint / 64) % 64, 0x80 + codepoint % 64)
    end
    return string.char(0xF0 + math.floor(codepoint / 262144),
        0x80 + math.floor(codepoint / 4096) % 64,
        0x80 + math.floor(codepoint / 64) % 64, 0x80 + codepoint % 64)
end

local function validUtf8(value)
    local index = 1
    while index <= #value do
        local byte = value:byte(index)
        if byte < 0x80 then
            index = index + 1
        else
            local count
            if byte >= 0xC2 and byte <= 0xDF then
                count = 2
            elseif byte >= 0xE0 and byte <= 0xEF then
                count = 3
            elseif byte >= 0xF0 and byte <= 0xF4 then
                count = 4
            else
                return false
            end
            local second = value:byte(index + 1)
            if not second or second < 0x80 or second > 0xBF
                or (byte == 0xE0 and second < 0xA0)
                or (byte == 0xED and second > 0x9F)
                or (byte == 0xF0 and second < 0x90)
                or (byte == 0xF4 and second > 0x8F) then
                return false
            end
            for offset = 2, count - 1 do
                local continuation = value:byte(index + offset)
                if not continuation or continuation < 0x80 or continuation > 0xBF then
                    return false
                end
            end
            index = index + count
        end
    end
    return true
end

function Json.decode(text)
    if type(text) ~= "string" or #text > MAX_BYTES then
        return nil, "Invalid JSON: response is not text or exceeds 64 MiB"
    end

    local function parse()
        local index, length, values = 1, #text, 0
        local parseValue

        local function fail(message)
            error("Invalid JSON at byte " .. index .. ": " .. message, 0)
        end

        local function whitespace()
            local nextNonspace = text:find("[^ \t\r\n]", index)
            index = nextNonspace or length + 1
        end

        local function hexEscape()
            local digits = text:sub(index, index + 3)
            if #digits ~= 4 or not digits:match("^%x%x%x%x$") then
                fail("invalid Unicode escape")
            end
            index = index + 4
            return tonumber(digits, 16)
        end

        local escapes = {
            ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
            b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
        }
        local function parseString()
            index = index + 1
            local chunks
            while true do
                local stop = text:find('["\\%z\1-\31]', index)
                if not stop then
                    fail("unterminated string")
                end
                local segment = text:sub(index, stop - 1)
                if not validUtf8(segment) then
                    fail("invalid UTF-8 in string")
                end
                local marker = text:sub(stop, stop)
                if marker == '"' then
                    index = stop + 1
                    if not chunks then
                        return segment
                    end
                    chunks[#chunks + 1] = segment
                    return table.concat(chunks)
                elseif marker ~= '\\' then
                    index = stop
                    fail("unescaped control character")
                end
                chunks = chunks or {}
                chunks[#chunks + 1] = segment
                index = stop + 1
                local escaped = text:sub(index, index)
                if escaped == 'u' then
                    index = index + 1
                    local codepoint = hexEscape()
                    if codepoint >= 0xD800 and codepoint <= 0xDBFF then
                        if text:sub(index, index + 1) ~= '\\u' then
                            fail("missing low surrogate")
                        end
                        index = index + 2
                        local low = hexEscape()
                        if low < 0xDC00 or low > 0xDFFF then
                            fail("invalid low surrogate")
                        end
                        codepoint = 0x10000 + (codepoint - 0xD800) * 1024 + low - 0xDC00
                    elseif codepoint >= 0xDC00 and codepoint <= 0xDFFF then
                        fail("unpaired low surrogate")
                    end
                    chunks[#chunks + 1] = utf8(codepoint)
                else
                    local replacement = escapes[escaped]
                    if not replacement then
                        fail("invalid string escape")
                    end
                    chunks[#chunks + 1] = replacement
                    index = index + 1
                end
            end
        end

        local function digit(byte)
            return byte ~= nil and byte >= 48 and byte <= 57
        end

        local function parseNumber()
            local start = index
            if text:byte(index) == 45 then index = index + 1 end
            local first = text:byte(index)
            if first == 48 then
                index = index + 1
                if digit(text:byte(index)) then fail("leading zero") end
            elseif first and first >= 49 and first <= 57 then
                repeat index = index + 1 until not digit(text:byte(index))
            else
                fail("invalid number")
            end
            if text:byte(index) == 46 then
                index = index + 1
                if not digit(text:byte(index)) then fail("missing fractional digit") end
                repeat index = index + 1 until not digit(text:byte(index))
            end
            local exponent = text:byte(index)
            if exponent == 69 or exponent == 101 then
                index = index + 1
                local sign = text:byte(index)
                if sign == 43 or sign == 45 then index = index + 1 end
                if not digit(text:byte(index)) then fail("missing exponent digit") end
                repeat index = index + 1 until not digit(text:byte(index))
            end
            local number = tonumber(text:sub(start, index - 1))
            if not number or number == math.huge or number == -math.huge then
                fail("number out of range")
            end
            return number
        end

        parseValue = function(depth)
            values = values + 1
            if values > MAX_VALUES then fail("too many values") end
            whitespace()
            local character = text:sub(index, index)
            if character == '"' then return parseString() end
            if character == 't' and text:sub(index, index + 3) == "true" then
                index = index + 4
                return true
            end
            if character == 'f' and text:sub(index, index + 4) == "false" then
                index = index + 5
                return false
            end
            if character == 'n' and text:sub(index, index + 3) == "null" then
                index = index + 4
                return Json.null
            end
            if character == '-' or (character >= '0' and character <= '9') then
                return parseNumber()
            end
            if character ~= '{' and character ~= '[' then fail("expected value") end
            if depth > MAX_DEPTH then fail("too deeply nested") end

            local isObject = character == '{'
            local closing = isObject and '}' or ']'
            local result = {}
            index = index + 1
            whitespace()
            if text:sub(index, index) == closing then
                index = index + 1
                return result
            end
            while true do
                local key
                if isObject then
                    if text:sub(index, index) ~= '"' then fail("expected object key") end
                    key = parseString()
                    if result[key] ~= nil then fail("duplicate object key") end
                    whitespace()
                    if text:sub(index, index) ~= ':' then fail("expected colon") end
                    index = index + 1
                end
                local value = parseValue(depth + 1)
                if isObject then
                    result[key] = value
                else
                    result[#result + 1] = value
                end
                whitespace()
                local separator = text:sub(index, index)
                index = index + 1
                if separator == closing then return result end
                if separator ~= ',' then fail("expected comma or closing bracket") end
                whitespace()
            end
        end

        local result = parseValue(1)
        whitespace()
        if index <= length then fail("trailing content") end
        return result
    end

    local ok, value = pcall(parse)
    if not ok then return nil, value end
    return value
end

return Json
