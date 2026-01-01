local MenuTweaks = {}

-- Module state (set during Init)
local Config = nil
local Log = nil

-- Cache for original button text values (populated on first UpdateButtonWithDelayTime call)
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
    if not popup:IsValid() then return false end

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
    Log.Debug("MenuTweaks initialized")
end

-- Called from RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:Construct") in main.lua
function MenuTweaks.OnConstruct(popup)
    if not ShouldSkipDelay(popup) then return end

    Log.Debug("LAN hosting popup detected - skipping delay")

    pcall(function()
        popup.DelayBeforeAllowingInput = 0
        popup.CloseBlockedByDelay = false
        popup.DelayTimeLeft = 0
    end)

    EnablePopupButtons(popup)
end

-- Called from RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:CountdownInputDelay") in main.lua
function MenuTweaks.OnCountdownInputDelay(popup)
    if not ShouldSkipDelay(popup) then return end

    pcall(function()
        popup.DelayTimeLeft = 0
        popup.CloseBlockedByDelay = false
    end)

    EnablePopupButtons(popup)
end

-- Called from RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:UpdateButtonWithDelayTime") in main.lua
-- TextParam and OriginalTextParam are RemoteUnrealParam from the hook
function MenuTweaks.OnUpdateButtonWithDelayTime(popup, TextParam, OriginalTextParam)
    if not ShouldSkipDelay(popup) then return end

    -- Function already executed and formatted text with countdown
    -- Override it back to the original text
    local okText, textWidget = pcall(function()
        return TextParam:get()
    end)
    if not okText or not textWidget:IsValid() then return end

    -- Get widget name to use as cache key
    local okName, widgetName = pcall(function()
        return textWidget:GetFName():ToString()
    end)
    if not okName then return end

    -- Get original text from parameter
    local okOriginal, originalText = pcall(function()
        return OriginalTextParam:get()
    end)

    local originalStr = ""
    if okOriginal and originalText then
        local okStr, str = pcall(function()
            return originalText:ToString()
        end)
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
        pcall(function()
            textWidget:SetText(FText(cachedStr))
        end)
    end
end

return MenuTweaks
