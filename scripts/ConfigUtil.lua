-- ============================================================
-- CONFIG UTILITIES
-- Handles configuration validation and provides config-related helpers
-- Generic utilities that work across different mod types
-- ============================================================

local ConfigUtil = {}

-- ============================================================
-- GENERIC VALIDATORS
-- ============================================================

function ConfigUtil.ValidateBoolean(value, default, logFunc, fieldName)
    if type(value) ~= "boolean" then
        if value ~= nil and logFunc and fieldName then
            logFunc("Invalid " .. fieldName .. " (must be boolean), using " .. tostring(default), "warning")
        end
        return default
    end
    return value
end

function ConfigUtil.ValidateNumber(value, default, min, max, logFunc, fieldName)
    if type(value) ~= "number" then
        if value ~= nil and logFunc and fieldName then
            logFunc("Invalid " .. fieldName .. " (must be number), using " .. tostring(default), "warning")
        end
        return default
    end

    if (min and value < min) or (max and value > max) then
        if logFunc and fieldName then
            local bounds = ""
            if min and max then
                bounds = " (must be " .. min .. "-" .. max .. ")"
            elseif min then
                bounds = " (must be >= " .. min .. ")"
            elseif max then
                bounds = " (must be <= " .. max .. ")"
            end
            logFunc("Invalid " .. fieldName .. bounds .. ", using " .. tostring(default), "warning")
        end
        return default
    end

    return value
end

function ConfigUtil.ValidateString(value, default, allowedValues, logFunc, fieldName)
    if type(value) ~= "string" then
        if value ~= nil and logFunc and fieldName then
            logFunc("Invalid " .. fieldName .. " (must be string), using " .. tostring(default), "warning")
        end
        return default
    end

    if allowedValues then
        local valid = false
        for _, allowed in ipairs(allowedValues) do
            if value == allowed then
                valid = true
                break
            end
        end
        if not valid then
            if logFunc and fieldName then
                logFunc("Invalid " .. fieldName .. " (not in allowed values), using " .. tostring(default), "warning")
            end
            return default
        end
    end

    return value
end

-- Ensure a table exists, creating empty table if nil
function ConfigUtil.EnsureTable(value, logFunc, fieldName)
    if value == nil then
        return {}
    end
    if type(value) ~= "table" then
        if logFunc and fieldName then
            logFunc("Invalid " .. fieldName .. " (must be table), using empty table", "warning")
        end
        return {}
    end
    return value
end

-- ============================================================
-- QOL-FIXES-TWEAKS CONFIG VALIDATOR
-- ============================================================

local DEFAULTS = {
    Debug = false,
    MenuTweaks = {
        SkipLANHostingDelay = true,
    },
    FoodDeployableFix = {
        Enabled = true,
        FixExistingOnLoad = false,
        ClientSideVisualOnly = false,
    },
    CraftingPreviewBrightness = {
        Enabled = true,
        LightIntensity = 10.0,
    },
    CraftingPreviewResolution = {
        Enabled = true,
        Resolution = 1024,
    },
}

function ConfigUtil.ValidateConfig(userConfig, logFunc)
    local config = userConfig or {}

    config.Debug = ConfigUtil.ValidateBoolean(
        config.Debug,
        DEFAULTS.Debug,
        logFunc,
        "Debug"
    )

    -- MenuTweaks section
    config.MenuTweaks = ConfigUtil.EnsureTable(config.MenuTweaks, logFunc, "MenuTweaks")
    config.MenuTweaks.SkipLANHostingDelay = ConfigUtil.ValidateBoolean(
        config.MenuTweaks.SkipLANHostingDelay,
        DEFAULTS.MenuTweaks.SkipLANHostingDelay,
        logFunc,
        "MenuTweaks.SkipLANHostingDelay"
    )

    -- FoodDeployableFix section
    config.FoodDeployableFix = ConfigUtil.EnsureTable(config.FoodDeployableFix, logFunc, "FoodDeployableFix")
    config.FoodDeployableFix.Enabled = ConfigUtil.ValidateBoolean(
        config.FoodDeployableFix.Enabled,
        DEFAULTS.FoodDeployableFix.Enabled,
        logFunc,
        "FoodDeployableFix.Enabled"
    )
    config.FoodDeployableFix.FixExistingOnLoad = ConfigUtil.ValidateBoolean(
        config.FoodDeployableFix.FixExistingOnLoad,
        DEFAULTS.FoodDeployableFix.FixExistingOnLoad,
        logFunc,
        "FoodDeployableFix.FixExistingOnLoad"
    )
    config.FoodDeployableFix.ClientSideVisualOnly = ConfigUtil.ValidateBoolean(
        config.FoodDeployableFix.ClientSideVisualOnly,
        DEFAULTS.FoodDeployableFix.ClientSideVisualOnly,
        logFunc,
        "FoodDeployableFix.ClientSideVisualOnly"
    )

    -- CraftingPreviewBrightness section
    config.CraftingPreviewBrightness = ConfigUtil.EnsureTable(config.CraftingPreviewBrightness, logFunc, "CraftingPreviewBrightness")
    config.CraftingPreviewBrightness.Enabled = ConfigUtil.ValidateBoolean(
        config.CraftingPreviewBrightness.Enabled,
        DEFAULTS.CraftingPreviewBrightness.Enabled,
        logFunc,
        "CraftingPreviewBrightness.Enabled"
    )
    config.CraftingPreviewBrightness.LightIntensity = ConfigUtil.ValidateNumber(
        config.CraftingPreviewBrightness.LightIntensity,
        DEFAULTS.CraftingPreviewBrightness.LightIntensity,
        0.1,
        nil,
        logFunc,
        "CraftingPreviewBrightness.LightIntensity"
    )

    -- CraftingPreviewResolution section
    config.CraftingPreviewResolution = ConfigUtil.EnsureTable(config.CraftingPreviewResolution, logFunc, "CraftingPreviewResolution")
    config.CraftingPreviewResolution.Enabled = ConfigUtil.ValidateBoolean(
        config.CraftingPreviewResolution.Enabled,
        DEFAULTS.CraftingPreviewResolution.Enabled,
        logFunc,
        "CraftingPreviewResolution.Enabled"
    )
    config.CraftingPreviewResolution.Resolution = ConfigUtil.ValidateNumber(
        config.CraftingPreviewResolution.Resolution,
        DEFAULTS.CraftingPreviewResolution.Resolution,
        1,
        8192,
        logFunc,
        "CraftingPreviewResolution.Resolution"
    )

    return config
end

return ConfigUtil
