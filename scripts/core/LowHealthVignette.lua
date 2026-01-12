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
        { path = "Color", type = "color", default = { R = 128, G = 0, B = 0, A = 0.3 } },
        { path = "PulseEnabled", type = "boolean", default = true },
    },

    hookPoint = "PostInit",
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

local VignetteWidget = nil
local VignetteTexture = nil

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
    if VignetteWidget and VignetteWidget:IsValid() then
        return VignetteWidget
    end

    Log.Debug("Creating vignette widget...")

    local okTemplate, templateImage = pcall(function()
        return hud.EyeLid_Top
    end)
    if not okTemplate or not templateImage or not templateImage:IsValid() then
        Log.Debug("Failed to get EyeLid_Top template")
        return nil
    end

    local okParent, parent = pcall(function()
        return templateImage:GetParent()
    end)
    if not okParent or not parent or not parent:IsValid() then
        Log.Debug("Failed to get EyeLid_Top parent")
        return nil
    end

    local newWidget, slot = WidgetUtil.CloneWidget(templateImage, parent, "LowHealthVignetteWidget")
    if not newWidget then
        Log.Debug("WidgetUtil.CloneWidget failed")
        return nil
    end

    if slot and slot:IsValid() then
        pcall(function()
            slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
            slot:SetOffsets({ Left = -250, Top = -250, Right = -250, Bottom = -250 })
            slot:SetAlignment({ X = 0, Y = 0 })
            slot:SetZOrder(-1)
        end)
    end

    pcall(function()
        newWidget:SetRenderTranslation({ X = 0, Y = 0 })
    end)

    if not VignetteTexture then
        local okTexture, texture = pcall(function()
            return StaticFindObject("/Game/Particles/T_Gradient_Radial.T_Gradient_Radial")
        end)
        if okTexture and texture and texture:IsValid() then
            VignetteTexture = texture
        else
            Log.Debug("Failed to load T_Gradient_Radial texture")
            return nil
        end
    end

    pcall(function()
        newWidget:SetBrushFromTexture(VignetteTexture, false)
    end)

    local color = Config.Color
    pcall(function()
        newWidget:SetColorAndOpacity({ R = color.R, G = color.G, B = color.B, A = color.A })
    end)

    pcall(function()
        newWidget:SetVisibility(1)
    end)

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
            if not IsPulsing or not VignetteWidget then
                return
            end

            if not VignetteWidget:IsValid() then
                IsPulsing = false
                return
            end

            local ok = pcall(function()
                VignetteWidget:SetColorAndOpacity({ R = color.R, G = color.G, B = color.B, A = pulseAlpha })
            end)

            if not ok then
                IsPulsing = false
            end
        end)

        return false
    end)
end

local function ShowVignette(hud)
    if IsVignetteVisible then return end

    local widget = GetOrCreateVignetteWidget(hud)
    if not widget then return end

    IsVignetteVisible = true

    pcall(function()
        widget:SetVisibility(4)
    end)

    StartPulseLoop()
end

local function HideVignette()
    if not IsVignetteVisible then return end
    IsVignetteVisible = false

    if IsPulsing then
        Log.Debug("Stopped pulse animation")
    end
    IsPulsing = false

    if VignetteWidget and VignetteWidget:IsValid() then
        pcall(function()
            VignetteWidget:SetVisibility(1)
        end)
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

function Module.Cleanup()
    Log.Debug("Cleaning up vignette state")

    IsPulsing = false
    VignetteWidget = nil
    VignetteTexture = nil
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
        Log
    )
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnUpdateHealth(hud)
    local okHealth, healthPercent = pcall(function()
        return hud.LastHealthPercentage
    end)

    if not okHealth then
        Log.Debug("Failed to get LastHealthPercentage")
        return
    end

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
