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

-- Validate and convert RGB color (0-255) to UE format (0-1)
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
            logFunc("Invalid " .. fieldName .. " (must be {R=0-255, G=0-255, B=0-255}), using default", "warning")
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
-- QOL-FIXES-TWEAKS CONFIG VALIDATOR
-- ============================================================

local DEFAULTS = {
    Debug = false,
    DebugFlags = {
        MenuTweaks = nil,
        FoodDeployableFix = nil,
        CraftingPreview = nil,
        DistributionPad = nil,
    },
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
    DistributionPadDistance = {
        Enabled = false,
        DistanceMultiplier = 1.25,
    },
    DistributionPadIndicator = {
        Enabled = true,
        RefreshOnContainerDeploy = false,
        TextEnabled = true,
        Text = "[DistPad]",
        IconEnabled = true,
        Icon = "icon_hackingdevice",
        IconColor = { R = 114, G = 242, B = 255 },
    },
}

-- Check if debug is enabled for a specific feature
-- Returns: true if debug enabled, false otherwise
-- Logic: If DebugFlags[feature] is explicitly set (true/false), use it; otherwise use global Debug
function ConfigUtil.IsDebugEnabled(config, featureName)
    if config.DebugFlags and config.DebugFlags[featureName] ~= nil then
        return config.DebugFlags[featureName]
    end
    return config.Debug or false
end

function ConfigUtil.ValidateConfig(userConfig, logFunc)
    local config = userConfig or {}

    config.Debug = ConfigUtil.ValidateBoolean(
        config.Debug,
        DEFAULTS.Debug,
        logFunc,
        "Debug"
    )

    -- DebugFlags section (nil values are allowed - they mean "use global")
    config.DebugFlags = ConfigUtil.EnsureTable(config.DebugFlags, logFunc, "DebugFlags")

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

    -- DistributionPadDistance section
    config.DistributionPadDistance = ConfigUtil.EnsureTable(config.DistributionPadDistance, logFunc, "DistributionPadDistance")
    config.DistributionPadDistance.Enabled = ConfigUtil.ValidateBoolean(
        config.DistributionPadDistance.Enabled,
        DEFAULTS.DistributionPadDistance.Enabled,
        logFunc,
        "DistributionPadDistance.Enabled"
    )
    config.DistributionPadDistance.DistanceMultiplier = ConfigUtil.ValidateNumber(
        config.DistributionPadDistance.DistanceMultiplier,
        DEFAULTS.DistributionPadDistance.DistanceMultiplier,
        0.1,
        10.0,
        logFunc,
        "DistributionPadDistance.DistanceMultiplier"
    )

    -- DistributionPadIndicator section
    config.DistributionPadIndicator = ConfigUtil.EnsureTable(config.DistributionPadIndicator, logFunc, "DistributionPadIndicator")
    config.DistributionPadIndicator.Enabled = ConfigUtil.ValidateBoolean(
        config.DistributionPadIndicator.Enabled,
        DEFAULTS.DistributionPadIndicator.Enabled,
        logFunc,
        "DistributionPadIndicator.Enabled"
    )
    config.DistributionPadIndicator.RefreshOnContainerDeploy = ConfigUtil.ValidateBoolean(
        config.DistributionPadIndicator.RefreshOnContainerDeploy,
        DEFAULTS.DistributionPadIndicator.RefreshOnContainerDeploy,
        logFunc,
        "DistributionPadIndicator.RefreshOnContainerDeploy"
    )
    config.DistributionPadIndicator.TextEnabled = ConfigUtil.ValidateBoolean(
        config.DistributionPadIndicator.TextEnabled,
        DEFAULTS.DistributionPadIndicator.TextEnabled,
        logFunc,
        "DistributionPadIndicator.TextEnabled"
    )
    config.DistributionPadIndicator.Text = ConfigUtil.ValidateString(
        config.DistributionPadIndicator.Text,
        DEFAULTS.DistributionPadIndicator.Text,
        nil,
        logFunc,
        "DistributionPadIndicator.Text"
    )
    config.DistributionPadIndicator.TextPattern = config.DistributionPadIndicator.Text
        :gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
    config.DistributionPadIndicator.IconEnabled = ConfigUtil.ValidateBoolean(
        config.DistributionPadIndicator.IconEnabled,
        DEFAULTS.DistributionPadIndicator.IconEnabled,
        logFunc,
        "DistributionPadIndicator.IconEnabled"
    )
    config.DistributionPadIndicator.Icon = ConfigUtil.ValidateString(
        config.DistributionPadIndicator.Icon,
        DEFAULTS.DistributionPadIndicator.Icon,
        nil,
        logFunc,
        "DistributionPadIndicator.Icon"
    )
    config.DistributionPadIndicator.IconColor = ConfigUtil.ValidateColor(
        config.DistributionPadIndicator.IconColor,
        DEFAULTS.DistributionPadIndicator.IconColor,
        logFunc,
        "DistributionPadIndicator.IconColor"
    )

    return config
end

return ConfigUtil
