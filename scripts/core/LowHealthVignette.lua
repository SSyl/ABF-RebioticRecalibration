--[[
============================================================================
LowHealthVignette - Red Screen Edge Effect When Low Health
============================================================================

Shows red vignette when health drops below threshold. Clones EyeLid_Top widget,
replaces texture with T_Gradient_Radial, and tints red. Optional pulse animation
uses LoopAsync (33ms, ~30 FPS) with sine wave to oscillate alpha 40%-100%.

HOOKS: W_PlayerHUD_Main_C:UpdateHealth
PERFORMANCE: Fires on health changes. Pulse loop only runs when vignette visible.
]]

local HookUtil = require("utils/HookUtil")
local WidgetUtil = require("utils/WidgetUtil")

-- ============================================================
-- MODULE METADATA
-- ============================================================

local Module = {
    name = "LowHealthVignette",
    configKey = "LowHealthVignette",

    schema = {
        { path = "Enabled", type = "boolean", default = true },
        { path = "Threshold", type = "number", default = 0.25, min = 0.01, max = 1.1 },
        { path = "Color", type = "widgetColor", default = { R = 128, G = 0, B = 0, A = 0.3 } },
        { path = "PulseEnabled", type = "boolean", default = true },
    },

    hookPoint = "Gameplay",
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

local VignetteWidget = CreateInvalidObject()
local VignetteTexture = CreateInvalidObject()

local IsVignetteVisible = false
local LastBelowThreshold = nil

local IsPulsing = false
local PulseTime = 0
local PULSE_SPEED = 2.0
local PULSE_MIN = 0.4
local PULSE_MAX = 1.0

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

local function GetOrCreateVignetteWidget(hud)
    if VignetteWidget:IsValid() then return VignetteWidget end

    Log.Debug("Creating vignette widget...")

    local templateImage = hud.EyeLid_Top
    if not templateImage:IsValid() then
        Log.Debug("Failed to get EyeLid_Top template")
        return VignetteWidget
    end

    local parent = templateImage:GetParent()
    if not parent:IsValid() then
        Log.Debug("Failed to get EyeLid_Top parent")
        return VignetteWidget
    end

    local newWidget, slot = WidgetUtil.CloneWidget(templateImage, parent, "LowHealthVignetteWidget")
    if not newWidget:IsValid() then
        Log.Debug("WidgetUtil.CloneWidget failed")
        return VignetteWidget
    end

    if slot:IsValid() then
        slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
        slot:SetOffsets({ Left = -250, Top = -250, Right = -250, Bottom = -250 })
        slot:SetAlignment({ X = 0, Y = 0 })
        slot:SetZOrder(-1)
    end

    newWidget:SetRenderTranslation({ X = 0, Y = 0 })

    if not VignetteTexture:IsValid() then
        local texture = StaticFindObject("/Game/Particles/T_Gradient_Radial.T_Gradient_Radial")
        if texture:IsValid() then
            VignetteTexture = texture
        else
            Log.Debug("Failed to load T_Gradient_Radial texture")
            return VignetteWidget
        end
    end

    newWidget:SetBrushFromTexture(VignetteTexture, false)

    local color = Config.Color
    newWidget:SetColorAndOpacity({ R = color.R, G = color.G, B = color.B, A = color.A })
    newWidget:SetVisibility(1)

    VignetteWidget = newWidget
    return newWidget
end

local function StartPulseLoop()
    if IsPulsing then return end
    if not Config.PulseEnabled then return end

    IsPulsing = true
    PulseTime = 0
    Log.Debug("Started pulse animation")

    LoopAsync(33, function()
        if not IsPulsing then return true end

        if not VignetteWidget then
            IsPulsing = false
            return true
        end

        PulseTime = PulseTime + 0.033

        local cycle = (PulseTime / PULSE_SPEED) * math.pi * 2
        local wave = (math.sin(cycle) + 1) / 2
        local multiplier = PULSE_MIN + (PULSE_MAX - PULSE_MIN) * wave

        local baseAlpha = Config.Color.A
        local pulseAlpha = baseAlpha * multiplier
        local color = Config.Color

        ExecuteInGameThread(function()
            if not IsPulsing or not VignetteWidget:IsValid() then
                IsPulsing = false
                return
            end

            VignetteWidget:SetColorAndOpacity({ R = color.R, G = color.G, B = color.B, A = pulseAlpha })
        end)

        return false
    end)
end

local function ShowVignette(hud)
    if IsVignetteVisible then return end

    local widget = GetOrCreateVignetteWidget(hud)
    if not widget:IsValid() then return end

    IsVignetteVisible = true
    widget:SetVisibility(4)
    StartPulseLoop()
end

local function HideVignette()
    if not IsVignetteVisible then return end
    IsVignetteVisible = false

    if IsPulsing then
        Log.Debug("Stopped pulse animation")
    end
    IsPulsing = false

    if VignetteWidget:IsValid() then
        VignetteWidget:SetVisibility(1)
    end
end

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("LowHealthVignette - %s", status)
end

function Module.GameplayCleanup()
    Log.Debug("Cleaning up vignette state")

    IsPulsing = false
    VignetteWidget = CreateInvalidObject()
    VignetteTexture = CreateInvalidObject()
    IsVignetteVisible = false
    LastBelowThreshold = nil
    PulseTime = 0
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function Module.RegisterHooks()
    return HookUtil.Register(
        "/Game/Blueprints/Widgets/W_PlayerHUD_Main.W_PlayerHUD_Main_C:UpdateHealth",
        Module.OnUpdateHealth,
        Log,
        { warmup = true }
    )
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnUpdateHealth(hud)
    local healthPercent = hud.LastHealthPercentage
    local belowThreshold = healthPercent > 0 and healthPercent < Config.Threshold
    if belowThreshold ~= LastBelowThreshold then
        LastBelowThreshold = belowThreshold
        if belowThreshold then
            ShowVignette(hud)
        else
            HideVignette()
        end
    end
end

return Module
