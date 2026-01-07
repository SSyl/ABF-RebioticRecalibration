--[[
============================================================================
MenuTweaks - Skip LAN Hosting Delay
============================================================================

PURPOSE:
When hosting a LAN server, the vanilla game shows a popup with a 3-second
countdown before allowing you to click "Yes". This module skips that delay.

HOW IT WORKS:
The popup uses three mechanisms to enforce the delay:
1. DelayBeforeAllowingInput - initial delay value
2. CloseBlockedByDelay - prevents closing during countdown
3. DelayTimeLeft - remaining countdown time

We hook three Blueprint functions to disable all three:
- Construct: Initial popup creation - zero out the delay values
- CountdownInputDelay: Called each tick during countdown - force to 0
- UpdateButtonWithDelayTime: Updates button text with countdown - restore original

HOOKS:
- W_MenuPopup_YesNo_C:Construct           → OnConstruct()
- W_MenuPopup_YesNo_C:CountdownInputDelay → OnCountdownInputDelay()
- W_MenuPopup_YesNo_C:UpdateButtonWithDelayTime → OnUpdateButtonWithDelayTime()

PERFORMANCE:
These hooks only fire when the LAN hosting popup is open (rare event).
No per-frame overhead.
]]

local HookUtil = require("utils/HookUtil")
local MenuTweaks = {}

-- Module state (set during Init)
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
    -- popup is already validated by HookUtil.Register
    local ok, title = pcall(function()
        return popup.Text_Title:ToString()
    end)

    return ok and title == "Hosting a LAN Server"
end

-- ============================================================
-- CORE LOGIC
-- ============================================================

function MenuTweaks.Init(config, log)
    Config = config
    Log = log

    local status = Config.SkipLANHostingDelay and "Enabled" or "Disabled"
    Log.Info("MenuTweaks - %s", status)
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function MenuTweaks.RegisterPrePlayHooks()
    return HookUtil.Register({
        {
            path = "/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:Construct",
            callback = MenuTweaks.OnConstruct
        },
        {
            path = "/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:CountdownInputDelay",
            callback = MenuTweaks.OnCountdownInputDelay
        },
        {
            path = "/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:UpdateButtonWithDelayTime",
            callback = MenuTweaks.OnUpdateButtonWithDelayTime
        },
    }, Log)
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

-- Called when popup is constructed
function MenuTweaks.OnConstruct(popup)
    if not ShouldSkipDelay(popup) then return end

    pcall(function()
        popup.DelayBeforeAllowingInput = 0
        popup.CloseBlockedByDelay = false
        popup.DelayTimeLeft = 0
    end)

    EnablePopupButtons(popup)
end

-- Called each tick during countdown
function MenuTweaks.OnCountdownInputDelay(popup)
    if not ShouldSkipDelay(popup) then return end

    pcall(function()
        popup.DelayTimeLeft = 0
        popup.CloseBlockedByDelay = false
    end)

    EnablePopupButtons(popup)
end

-- Called when button text is updated with countdown time
-- TextParam and OriginalTextParam are RemoteUnrealParam from the hook
function MenuTweaks.OnUpdateButtonWithDelayTime(popup, TextParam, OriginalTextParam)
    if not ShouldSkipDelay(popup) then return end

    local okText, textWidget = pcall(function()
        return TextParam:get()
    end)
    if not okText or not textWidget or not textWidget:IsValid() then return end

    local okName, widgetName = pcall(function() return textWidget:GetFName():ToString() end)
    if not okName then return end

    local okOriginal, originalText = pcall(function() return OriginalTextParam:get() end)

    local originalStr = ""
    if okOriginal and originalText then
        local okStr, str = pcall(function() return originalText:ToString() end)
        if okStr then originalStr = str end
    end

    -- Cache original text STRING on first call (when it's not empty)
    -- We cache the string, not the FText object, because FText may become invalid
    if originalStr ~= "" and not OriginalButtonText[widgetName] then
        OriginalButtonText[widgetName] = originalStr
        Log.Debug("Cached original text for %s: '%s'", widgetName, originalStr)
    end

    -- Use cached string to create fresh FText and set it
    local cachedStr = OriginalButtonText[widgetName]
    if cachedStr then
        pcall(function() textWidget:SetText(FText(cachedStr)) end) 
    end
end

return MenuTweaks
