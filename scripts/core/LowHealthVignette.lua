--[[
============================================================================
LowHealthVignette - Red Screen Edge Effect When Low on Health
============================================================================

PURPOSE:
Adds a red vignette effect around the screen edges when the player's health
drops below a configurable threshold. Provides visual feedback that you're
in danger. Optionally pulses for a "heartbeat" effect.

HOW IT WORKS:

Widget Creation:
- We clone the existing EyeLid_Top UImage widget (used for the blindfold
  effect) because it's already configured for fullscreen overlay.
- We replace its texture with T_Gradient_Radial (a radial gradient that
  fades from transparent center to opaque edges - perfect for vignette).
- We tint it with the configured color (default: dark red).
- Widget is created lazily on first health update below threshold.

Health Tracking:
- We hook W_PlayerHUD_Main_C:UpdateHealth which fires when health changes.
- We read hud.LastHealthPercentage and compare against Config.Threshold.
- We only show/hide on threshold crossing, not every health update.

Pulse Animation:
- When visible and PulseEnabled, we run a LoopAsync at ~30 FPS.
- The async loop does pure Lua math (sine wave), then uses ExecuteInGameThread
  to update the widget's alpha.
- The pulse oscillates between 40% and 100% of the base alpha.

HOOKS:
- W_PlayerHUD_Main_C:UpdateHealth → OnUpdateHealth()

PERFORMANCE:
- Health updates fire when health changes (not every frame).
- Pulse loop only runs when vignette is visible (player is low health).
- Cleanup() clears state when returning to menu.
]]

local HookUtil = require("utils/HookUtil")
local WidgetUtil = require("utils/WidgetUtil")
local LowHealthVignette = {}

-- Module state (set during Init)
local Config = nil
local Log = nil

-- Cached widget references (created lazily, cleared on Cleanup)
local VignetteWidget = nil
local VignetteTexture = nil

-- Visibility state tracking
local IsVignetteVisible = false
local LastBelowThreshold = nil  -- nil = unknown, true = below, false = above

-- Pulse animation state
local IsPulsing = false
local PulseTime = 0
local PULSE_SPEED = 2.0  -- Seconds per full heartbeat cycle
local PULSE_MIN = 0.4    -- Multiplier for minimum alpha (base * 0.4)
local PULSE_MAX = 1.0    -- Multiplier for maximum alpha (base * 1.0)

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

local function GetOrCreateVignetteWidget(hud)
    -- Return cached widget if still valid
    if VignetteWidget and VignetteWidget:IsValid() then
        return VignetteWidget
    end

    Log.Debug("Creating vignette widget...")

    -- Get EyeLid_Top (UImage) to use as template - UImage supports textures with alpha
    local okTemplate, templateImage = pcall(function()
        return hud.EyeLid_Top
    end)
    if not okTemplate or not templateImage or not templateImage:IsValid() then
        Log.Debug("Failed to get EyeLid_Top template")
        return nil
    end
    Log.Debug("Got EyeLid_Top template: %s", templateImage:GetFullName())

    -- Get parent (PrimaryHUDCanvas)
    local okParent, parent = pcall(function()
        return templateImage:GetParent()
    end)
    if not okParent or not parent or not parent:IsValid() then
        Log.Debug("Failed to get EyeLid_Top parent")
        return nil
    end
    Log.Debug("Got parent: %s", parent:GetFullName())

    -- Clone widget using WidgetUtil
    local newWidget, slot = WidgetUtil.CloneWidget(templateImage, parent, "LowHealthVignetteWidget")
    if not newWidget then
        Log.Debug("WidgetUtil.CloneWidget failed")
        return nil
    end
    Log.Debug("Created vignette widget: %s", newWidget:GetFullName())

    -- Configure slot for fullscreen
    if slot and slot:IsValid() then
        pcall(function()
            -- Anchors: stretch to fill entire screen
            slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
            -- Offsets: large negative to push edges way off screen (makes center larger)
            slot:SetOffsets({ Left = -250, Top = -250, Right = -250, Bottom = -250 })
            -- Alignment
            slot:SetAlignment({ X = 0, Y = 0 })
            -- ZOrder: behind most elements
            slot:SetZOrder(-1)
        end)
        Log.Debug("Configured slot: Anchors, Offsets, ZOrder")
    end

    -- Reset RenderTransform (cloned from EyeLid_Top which has offset positioning)
    pcall(function()
        newWidget:SetRenderTranslation({ X = 0, Y = 0 })
    end)
    Log.Debug("Reset render translation")

    -- Load radial gradient texture for vignette effect
    if not VignetteTexture then
        local okTexture, texture = pcall(function()
            return StaticFindObject("/Game/Particles/T_Gradient_Radial.T_Gradient_Radial")
        end)
        if okTexture and texture and texture:IsValid() then
            VignetteTexture = texture
            Log.Debug("Loaded vignette texture: T_Gradient_Radial")
        else
            Log.Debug("Failed to load T_Gradient_Radial texture")
            return nil
        end
    end

    -- Apply texture to UImage
    pcall(function()
        newWidget:SetBrushFromTexture(VignetteTexture, false)
    end)
    Log.Debug("Applied radial gradient texture to vignette")

    -- Set color tint (UImage uses SetColorAndOpacity)
    local color = Config.Color
    pcall(function()
        newWidget:SetColorAndOpacity({ R = color.R, G = color.G, B = color.B, A = color.A })
    end)
    Log.Debug("Set vignette color: R=%.2f G=%.2f B=%.2f A=%.2f", color.R, color.G, color.B, color.A)

    -- Start hidden
    pcall(function()
        newWidget:SetVisibility(1) -- Collapsed
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
        -- Stop condition (pure Lua check) - check FIRST before any other work
        if not IsPulsing then return true end

        -- Check if widget was cleared during map transition
        if not VignetteWidget then
            IsPulsing = false
            return true
        end

        -- Update time (33ms tick ≈ 30 FPS) - pure Lua math on async thread
        PulseTime = PulseTime + 0.033

        -- Sine wave oscillation between PULSE_MIN and PULSE_MAX
        local cycle = (PulseTime / PULSE_SPEED) * math.pi * 2
        local wave = (math.sin(cycle) + 1) / 2  -- 0 to 1
        local multiplier = PULSE_MIN + (PULSE_MAX - PULSE_MIN) * wave

        -- Calculate pulsing alpha
        local baseAlpha = Config.Color.A
        local pulseAlpha = baseAlpha * multiplier
        local color = Config.Color

        -- UObject access requires game thread
        ExecuteInGameThread(function()
            -- Double-check conditions on game thread (widget might have been cleaned up)
            if not IsPulsing or not VignetteWidget then
                return
            end

            -- IsValid() can lie during GC - pcall protects against access violations
            if not VignetteWidget:IsValid() then
                IsPulsing = false
                return
            end

            -- SetColorAndOpacity can throw during map transition even if IsValid() passed
            local ok = pcall(function()
                VignetteWidget:SetColorAndOpacity({ R = color.R, G = color.G, B = color.B, A = pulseAlpha })
            end)

            -- If SetColorAndOpacity failed, widget is being destroyed - stop pulsing
            if not ok then
                IsPulsing = false
            end
        end)

        return false  -- Continue loop
    end)
end

local function ShowVignette(hud)
    if IsVignetteVisible then return end

    local widget = GetOrCreateVignetteWidget(hud)
    if not widget then return end  -- Widget creation failed, will retry next frame

    IsVignetteVisible = true  -- Only set after widget confirmed to exist

    pcall(function()
        widget:SetVisibility(4) -- SelfHitTestInvisible
    end)

    StartPulseLoop()
end

local function HideVignette()
    if not IsVignetteVisible then return end
    IsVignetteVisible = false

    -- Stop pulse animation
    if IsPulsing then
        Log.Debug("Stopped pulse animation")
    end
    IsPulsing = false

    if VignetteWidget and VignetteWidget:IsValid() then
        pcall(function()
            VignetteWidget:SetVisibility(1) -- Collapsed
        end)
    end
end

-- ============================================================
-- CORE LOGIC
-- ============================================================

function LowHealthVignette.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("LowHealthVignette - %s", status)
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function LowHealthVignette.RegisterInPlayHooks()
    return HookUtil.Register(
        "/Game/Blueprints/Widgets/W_PlayerHUD_Main.W_PlayerHUD_Main_C:UpdateHealth",
        LowHealthVignette.OnUpdateHealth,
        Log
    )
end

-- ============================================================
-- LIFECYCLE
-- ============================================================

-- Called when returning to main menu to clean up cached widgets
function LowHealthVignette.Cleanup()
    Log.Debug("Cleaning up vignette state")

    -- Stop pulse animation
    IsPulsing = false

    -- TODO: Verify in LiveView that widget is destroyed when parent HUD is destroyed
    -- Currently we only clear references, assuming UE destroys children with parent.
    -- If widgets accumulate across map transitions, add RemoveFromParent() here.

    VignetteWidget = nil
    VignetteTexture = nil
    IsVignetteVisible = false
    LastBelowThreshold = nil
    PulseTime = 0
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

-- Called when player health updates
-- Widget lazy-creates on first call via ShowVignette -> GetOrCreateVignetteWidget
function LowHealthVignette.OnUpdateHealth(hud)
    -- Get health percentage from the HUD's cached value
    local okHealth, healthPercent = pcall(function()
        return hud.LastHealthPercentage
    end)

    if not okHealth then
        Log.Debug("Failed to get LastHealthPercentage")
        return
    end

    -- Dead (hp <= 0) folds into belowThreshold = false, hiding vignette via state change
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

return LowHealthVignette
