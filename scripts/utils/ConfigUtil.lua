local ConfigUtil = {}

-- ============================================================
-- GENERIC VALIDATORS
-- ============================================================

function ConfigUtil.ValidateBoolean(value, default, logFunc, fieldName)
    if type(value) ~= "boolean" then
        if value ~= nil and logFunc and fieldName then
            logFunc(string.format("Invalid %s (must be boolean), using %s", fieldName, tostring(default)), "warning")
        end
        return default
    end
    return value
end

function ConfigUtil.ValidateNumber(value, default, min, max, logFunc, fieldName)
    if type(value) ~= "number" then
        if value ~= nil and logFunc and fieldName then
            logFunc(string.format("Invalid %s (must be number), using %s", fieldName, tostring(default)), "warning")
        end
        return default
    end

    if (min and value < min) or (max and value > max) then
        if logFunc and fieldName then
            local bounds = ""
            if min and max then
                bounds = string.format(" (must be %s-%s)", min, max)
            elseif min then
                bounds = string.format(" (must be >= %s)", min)
            elseif max then
                bounds = string.format(" (must be <= %s)", max)
            end
            logFunc(string.format("Invalid %s%s, using %s", fieldName, bounds, tostring(default)), "warning")
        end
        return default
    end

    return value
end

function ConfigUtil.ValidateString(value, default, maxLength, trim, logFunc, fieldName)
    if type(value) ~= "string" then
        if value ~= nil and logFunc and fieldName then
            logFunc(string.format("Invalid %s (must be string), using %s", fieldName, tostring(default)), "warning")
        end
        return default
    end

    if maxLength and #value > maxLength then
        if trim then
            local trimmed = value:sub(1, maxLength)
            if logFunc and fieldName then
                logFunc(string.format("%s exceeded %d chars, trimmed", fieldName, maxLength), "warning")
            end
            return trimmed
        else
            if logFunc and fieldName then
                logFunc(string.format("%s exceeded %d chars, using default", fieldName, maxLength), "warning")
            end
            return default
        end
    end

    return value
end

function ConfigUtil.ValidateColor(value, default, logFunc, fieldName)
    local function isValidRGB(color)
        return type(color) == "table"
            and type(color.R) == "number" and color.R >= 0 and color.R <= 255
            and type(color.G) == "number" and color.G >= 0 and color.G <= 255
            and type(color.B) == "number" and color.B >= 0 and color.B <= 255
    end

    local source = value
    if not isValidRGB(value) then
        if value ~= nil and logFunc and fieldName then
            logFunc(string.format("Invalid %s (must be {R=0-255, G=0-255, B=0-255}), using default", fieldName), "warning")
        end
        source = default
    end

    return {
        R = source.R / 255,
        G = source.G / 255,
        B = source.B / 255,
        A = 1.0
    }
end

-- ============================================================
-- SCHEMA PROCESSOR
-- ============================================================

-- Helper: Get value at path (e.g., "Section.Field" -> config.Section.Field)
local function getValueAtPath(tbl, path)
    local current = tbl
    for segment in path:gmatch("[^%.]+") do
        if type(current) ~= "table" then return nil end
        current = current[segment]
    end
    return current
end

-- Helper: Set value at path, auto-creating nested tables as needed
local function setValueAtPath(tbl, path, value)
    local segments = {}
    for segment in path:gmatch("[^%.]+") do
        table.insert(segments, segment)
    end

    local current = tbl
    for i = 1, #segments - 1 do
        local segment = segments[i]
        if current[segment] == nil then
            current[segment] = {}
        end
        current = current[segment]
    end

    current[segments[#segments]] = value
end

function ConfigUtil.ValidateFromSchema(userConfig, schema, logFunc)
    local config = userConfig or {}

    for _, entry in ipairs(schema) do
        local path = entry.path
        local entryType = entry.type
        local default = entry.default
        local value = getValueAtPath(config, path)

        local validated
        if entryType == "boolean" then
            validated = ConfigUtil.ValidateBoolean(value, default, logFunc, path)
        elseif entryType == "number" then
            validated = ConfigUtil.ValidateNumber(value, default, entry.min, entry.max, logFunc, path)
        elseif entryType == "string" then
            validated = ConfigUtil.ValidateString(value, default, entry.maxLength, entry.trim, logFunc, path)
        elseif entryType == "color" then
            validated = ConfigUtil.ValidateColor(value, default, logFunc, path)
        else
            validated = value or default
        end

        setValueAtPath(config, path, validated)
    end

    return config
end

return ConfigUtil
