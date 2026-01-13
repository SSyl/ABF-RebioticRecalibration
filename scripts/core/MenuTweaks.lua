--[[
============================================================================
MenuTweaks - Main Menu Enhancements
============================================================================

SkipLANHostingDelay: Removes the 3-second countdown on LAN hosting confirmation
popup. Hooks Construct/CountdownInputDelay to zero out delay properties, and
hooks UpdateButtonWithDelayTime to restore original button text.

CustomServerButton: Adds a button to the main menu that connects directly to a
configured server IP/port. Button is created lazily on first menu button click.

HOOKS:
- W_MenuPopup_YesNo_C:Construct (LAN delay)
- W_MenuPopup_YesNo_C:CountdownInputDelay (LAN delay)
- W_MenuPopup_YesNo_C:UpdateButtonWithDelayTime (LAN delay)
- W_MainMenuButton_C:BndEvt__..._OnButtonClickedEvent__DelegateSignature (custom button)

PERFORMANCE: LAN hooks fire only when popup open. Button hook fires on menu clicks.
]]

local HookUtil = require("utils/HookUtil")
local UEHelpers = require("UEHelpers")

-- ============================================================
-- MODULE METADATA
-- ============================================================

local Module = {
    name = "MenuTweaks",
    configKey = "MenuTweaks",

    schema = {
        { path = "SkipLANHostingDelay", type = "boolean", default = false },
        { path = "CustomServerButton.Enabled", type = "boolean", default = false },
        { path = "CustomServerButton.IP", type = "string", default = "127.0.0.1" },
        { path = "CustomServerButton.Port", type = "number", default = 7777, min = 1, max = 65535 },
        { path = "CustomServerButton.Password", type = "string", default = "" },
        { path = "CustomServerButton.ButtonText", type = "string", default = "Custom Server Button" },
        { path = "CustomServerButton.Icon", type = "string", default = "icon_hackingdevice" },
        { path = "CustomServerButton.TextColor", type = "color", default = { R = 42, G = 255, B = 45 } },
    },

    hookPoint = "PreInit",

    isEnabled = function(cfg)
        return cfg.SkipLANHostingDelay or cfg.CustomServerButton.Enabled
    end,
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

-- SkipLANHostingDelay state
local OriginalButtonText = {}

-- CustomServerButton state
local CustomServerBtn = nil
local ButtonIconTexture = nil

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

-- CustomServerButton helpers

local function CreateServerButton()
    if CustomServerBtn and CustomServerBtn:IsValid() then
        return CustomServerBtn
    end

    local canvas = FindObject("CanvasPanel", "CanvasPanel_42", EObjectFlags.RF_NoFlags, EObjectFlags.RF_WasLoaded)
    if not canvas:IsValid() then
        Log.Debug("Canvas not found (not in main menu)")
        return nil
    end

    local buttonClass = StaticFindObject("/Game/Blueprints/Widgets/MenuSystem/W_MainMenuButton.W_MainMenuButton_C")
    if not buttonClass:IsValid() then
        Log.Debug("Button class not found")
        return nil
    end

    local btn = StaticConstructObject(buttonClass, canvas, FName("Button_CustomServer"))
    if not btn:IsValid() then
        Log.Debug("Failed to create button")
        return nil
    end

    local cfg = Config.CustomServerButton

    if cfg.Icon and cfg.Icon ~= "" then
        if not ButtonIconTexture then
            local okTexture, texture = pcall(function()
                return StaticFindObject("/Game/Textures/GUI/Icons/" .. cfg.Icon .. "." .. cfg.Icon)
            end)
            if okTexture and texture and texture:IsValid() then
                ButtonIconTexture = texture
            end
        end
        if ButtonIconTexture then
            pcall(function() btn.Icon = ButtonIconTexture end)
        end
    end

    pcall(function()
        btn.RenderTransform.Scale = { X = 0.8, Y = 0.8 }
        btn.DefaultTextColor = cfg.TextColor
    end)

    local slot = canvas:AddChildToCanvas(btn)
    if slot and slot:IsValid() then
        pcall(function()
            slot:SetPosition({ X = 155, Y = 680.0 })
            slot:SetAnchors({ Min = { X = 0.0, Y = 1.0 }, Max = { X = 0.0, Y = 1.0 } })
        end)
    end

    local okLabel, labelText = pcall(function() return btn.ButtonLabelText end)
    if okLabel and labelText and labelText:IsValid() then
        pcall(function() labelText:SetText(FText(cfg.ButtonText)) end)
    end

    CustomServerBtn = btn
    Log.Debug("Created custom server button")
    return btn
end

local function ConnectToServer()
    local cfg = Config.CustomServerButton

    local master = FindFirstOf("W_MainMenu_Master_C")
    if not master:IsValid() then
        Log.Warning("Master menu not found")
        return
    end

    local okBrowser, serverBrowser = pcall(function() return master.W_ServerBrowser end)
    if not okBrowser or not serverBrowser:IsValid() then
        Log.Warning("ServerBrowser not found")
        return
    end

    local kismet = UEHelpers.GetKismetSystemLibrary()
    if not kismet:IsValid() then
        Log.Warning("KismetSystemLibrary not found")
        return
    end

    local cmd = "open " .. cfg.IP .. ":" .. tostring(cfg.Port)
    if cfg.Password and cfg.Password ~= "" then
        cmd = cmd .. "?pw=" .. cfg.Password
    end

    Log.Info("Connecting to %s:%d", cfg.IP, cfg.Port)
    pcall(function()
        kismet:ExecuteConsoleCommand(serverBrowser, cmd, nil)
    end)
end

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    local lanStatus = Config.SkipLANHostingDelay and "Enabled" or "Disabled"
    local btnStatus = Config.CustomServerButton.Enabled and "Enabled" or "Disabled"
    Log.Info("MenuTweaks - SkipLANHostingDelay: %s, CustomServerButton: %s", lanStatus, btnStatus)
end

function Module.Cleanup()
    OriginalButtonText = {}
    CustomServerBtn = nil
    ButtonIconTexture = nil
end

function Module.RegisterHooks()
    local success = true

    if Config.SkipLANHostingDelay then
        success = HookUtil.Register({
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
        }, Log) and success
    end

    if Config.CustomServerButton.Enabled then
        success = HookUtil.Register(
            "/Game/Blueprints/Widgets/MenuSystem/W_MainMenuButton.W_MainMenuButton_C:BndEvt__AbioticButton_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature",
            Module.OnMenuButtonClicked,
            Log
        ) and success
    end

    return success
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

-- CustomServerButton callbacks

function Module.OnMenuButtonClicked(btn)
    local master = FindFirstOf("W_MainMenu_Master_C")
    if not master:IsValid() then return end

    if not CustomServerBtn or not CustomServerBtn:IsValid() then
        CreateServerButton()
    end

    local okName, fullName = pcall(function() return btn:GetFullName() end)
    if okName and fullName and fullName:find("Button_CustomServer") then
        ConnectToServer()
    end
end

return Module
