--[[
============================================================================
FlashlightFlickerFix - Disable Ambient Flashlight Flicker
============================================================================

Disables flashlight flicker during ambient earthquakes (Debuff_QuakeDisruption)
while preserving camera shake and audio. Reaper disruption (Debuff_Disruption)
still triggers flicker normally. Stops FlashlightFlickerTimeline and resets alpha.

HOOKS:
- Abiotic_PlayerCharacter_C:ToggleFlickering

Queries buff state via HasBuff? on BuffDebuffComponent (works on host AND clients).
]]

local HookUtil = require("utils/HookUtil")
local PlayerUtil = require("utils/PlayerUtil")

-- ============================================================
-- MODULE METADATA
-- ============================================================

local Module = {
    name = "FlashlightFlickerFix",
    configKey = "FlashlightFlickerFix",

    schema = {
        { path = "Enabled", type = "boolean", default = true },
    },

    hookPoint = "Gameplay",
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("FlashlightFlickerFix - %s", status)
end

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

--- Query buff component for active buff using HasBuff?
--- @param player AAbiotic_PlayerCharacter_C The player character
--- @param buffName string The buff row name (e.g., "Debuff_QuakeDisruption")
--- @return boolean Whether the buff is active
local function HasActiveBuff(player, buffName)
    local buffComponent = player.BuffDebuffComponent
    if not buffComponent:IsValid() then return false end

    local outParams = {}
    local ok = pcall(function()
        buffComponent['HasBuff?'](
            buffComponent,
            FName(buffName),  -- BuffID
            {},               -- BuffRow (empty/default)
            false,            -- MustBeOnSameLimb
            0,                -- Limb (any)
            1,                -- CountRequired
            outParams,        -- FoundBuff (OUT)
            {}                -- OnLimbs (OUT)
        )
    end)

    return ok and outParams.FoundBuff == true
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function Module.RegisterHooks()
    return HookUtil.Register(
        "/Game/Blueprints/Characters/Abiotic_PlayerCharacter.Abiotic_PlayerCharacter_C:ToggleFlickering",
        Module.OnToggleFlickering,
        Log
    )
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnToggleFlickering(player, StartParam)
    local start = StartParam:get()
    if not start then return end

    local localPlayer = PlayerUtil.GetIfLocal(player)
    if not localPlayer then return end

    -- Reaper debuff takes priority - allow flicker as warning
    if HasActiveBuff(localPlayer, "Debuff_Disruption") then
        Log.Debug("Reaper nearby - allowing flicker")
        return
    end

    -- Ambient earthquake only - block the flicker
    if HasActiveBuff(localPlayer, "Debuff_QuakeDisruption") then
        Log.Debug("Ambient earthquake - blocking flicker")
        local timeline = localPlayer.FlashlightFlickerTimeline
        if timeline:IsValid() then
            timeline:Stop()
        end
        localPlayer.Light_FlickerAlpha = 1.0
    end
end

return Module
