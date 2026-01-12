--[[
============================================================================
MenuTweaks - Skip LAN Hosting Delay
============================================================================

Removes the 3-second countdown on LAN hosting confirmation popup. Hooks
Construct/CountdownInputDelay to zero out delay properties, and hooks
UpdateButtonWithDelayTime to restore original button text (cached as string).

HOOKS:
- W_MenuPopup_YesNo_C:Construct
- W_MenuPopup_YesNo_C:CountdownInputDelay
- W_MenuPopup_YesNo_C:UpdateButtonWithDelayTime

PERFORMANCE: Only fires when LAN popup is open (rare event)
]]

local HookUtil = require("utils/HookUtil")

-- ============================================================
-- MODULE METADATA
-- ============================================================

local Module = {
    name = "MenuTweaks",
    configKey = "MenuTweaks",

    schema = {
        { path = "SkipLANHostingDelay", type = "boolean", default = true },
    },

    hookPoint = "PreInit",

    -- Custom enable check (not standard "Enabled" field)
    isEnabled = function(cfg) return cfg.SkipLANHostingDelay end,
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

local OriginalButtonText = {}

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

local function EnablePopupButtons(popup)
    local okYes, yesButton = pcall(function()
        return popup.Button_Yes
    end)
    if okYes and yesButton:IsValid() then
        pcall(function()
            yesButton:SetIsEnabled(true)
        end)
    end

    local okNo, noButton = pcall(function()
        return popup.Button_No
    end)
    if okNo and noButton:IsValid() then
        pcall(function()
            noButton:SetIsEnabled(true)
        end)
    end
end

local function ShouldSkipDelay(popup)
    local ok, title = pcall(function()
        return popup.Text_Title:ToString()
    end)

    return ok and title == "Hosting a LAN Server"
end

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    local status = Config.SkipLANHostingDelay and "Enabled" or "Disabled"
    Log.Info("MenuTweaks - %s", status)
end

function Module.RegisterHooks()
    return HookUtil.Register({
        {
            path = "/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:Construct",
            callback = Module.OnConstruct
        },
        {
            path = "/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:CountdownInputDelay",
            callback = Module.OnCountdownInputDelay
        },
        {
            path = "/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:UpdateButtonWithDelayTime",
            callback = Module.OnUpdateButtonWithDelayTime
        },
    }, Log)
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnConstruct(popup)
    if not ShouldSkipDelay(popup) then return end

    pcall(function()
        popup.DelayBeforeAllowingInput = 0
        popup.CloseBlockedByDelay = false
        popup.DelayTimeLeft = 0
    end)

    EnablePopupButtons(popup)
end

function Module.OnCountdownInputDelay(popup)
    if not ShouldSkipDelay(popup) then return end

    pcall(function()
        popup.DelayTimeLeft = 0
        popup.CloseBlockedByDelay = false
    end)

    EnablePopupButtons(popup)
end

function Module.OnUpdateButtonWithDelayTime(popup, TextParam, OriginalTextParam)
    if not ShouldSkipDelay(popup) then return end

    local okText, textWidget = pcall(function()
        return TextParam:get()
    end)
    if not okText or not textWidget:IsValid() then return end

    local okName, widgetName = pcall(function() return textWidget:GetFName():ToString() end)
    if not okName then return end

    local okOriginal, originalText = pcall(function() return OriginalTextParam:get() end)

    local originalStr = ""
    if okOriginal and originalText then
        local okStr, str = pcall(function() return originalText:ToString() end)
        if okStr then originalStr = str end
    end

    if originalStr ~= "" and not OriginalButtonText[widgetName] then
        OriginalButtonText[widgetName] = originalStr
        Log.Debug("Cached original text for %s: '%s'", widgetName, originalStr)
    end

    local cachedStr = OriginalButtonText[widgetName]
    if cachedStr then
        pcall(function() textWidget:SetText(FText(cachedStr)) end)
    end
end

return Module
