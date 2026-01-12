--[[
============================================================================
FlashlightFlicker - Disable Ambient Flashlight Flicker
============================================================================

Disables flashlight flicker during ambient earthquakes (Debuff_QuakeDisruption)
while preserving camera shake and audio. Reaper disruption (Debuff_Disruption)
still triggers flicker normally. Stops FlashlightFlickerTimeline and resets alpha.

HOOKS:
- Abiotic_CharacterBuffComponent_C:BuffReceived
- Abiotic_CharacterBuffComponent_C:BuffRemoved
- Abiotic_PlayerCharacter_C:ToggleFlickering
]]

local HookUtil = require("utils/HookUtil")
local UEHelpers = require("UEHelpers")

local FlashlightFlicker = {}

-- Module state (set during Init)
local Config = nil
local Log = nil

-- Cached references
local cachedPlayerPawn = nil

-- State tracking
local hasAmbientDebuff = false
local hasReaperDebuff = false

-- ============================================================
-- CORE LOGIC
-- ============================================================

function FlashlightFlicker.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("FlashlightFlicker - %s", status)
end

function FlashlightFlicker.Cleanup()
    -- Reset state flags on respawn/zone transition
    hasAmbientDebuff = false
    hasReaperDebuff = false
    cachedPlayerPawn = nil

    Log.Debug("FlashlightFlicker state cleaned up")
end

-- Helper to get/refresh cached player pawn and validate against an actor
local function GetLocalPlayer(actor)
    -- Refresh cache if needed
    if not cachedPlayerPawn or not cachedPlayerPawn:IsValid() then
        cachedPlayerPawn = UEHelpers.GetPlayer()
    end

    -- Validate actor is the local player
    if not actor:IsValid() then return nil end
    if not cachedPlayerPawn or not cachedPlayerPawn:IsValid() then return nil end

    local actorAddr = actor:GetAddress()
    local playerAddr = cachedPlayerPawn:GetAddress()
    if actorAddr ~= playerAddr then return nil end

    return cachedPlayerPawn
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function FlashlightFlicker.RegisterInPlayHooks()
    return HookUtil.Register({
        {
            path = "/Game/Blueprints/Characters/Abiotic_CharacterBuffComponent.Abiotic_CharacterBuffComponent_C:BuffReceived",
            callback = FlashlightFlicker.OnBuffReceived
        },
        {
            path = "/Game/Blueprints/Characters/Abiotic_CharacterBuffComponent.Abiotic_CharacterBuffComponent_C:BuffRemoved",
            callback = FlashlightFlicker.OnBuffRemoved
        },
        {
            path = "/Game/Blueprints/Characters/Abiotic_PlayerCharacter.Abiotic_PlayerCharacter_C:ToggleFlickering",
            callback = FlashlightFlicker.OnToggleFlickering
        },
    }, Log)
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

-- Track when ambient earthquake debuff is applied
function FlashlightFlicker.OnBuffReceived(buffComponent, BuffRowHandleParam)
    local okBuff, buffHandle = pcall(function() return BuffRowHandleParam:get() end)
    if not okBuff or not buffHandle then return end

    local okRowName, rowName = pcall(function() return buffHandle.RowName:ToString() end)
    if not okRowName then return end

    -- Track reaper disruption (critical warning - takes priority)
    if rowName == "Debuff_Disruption" then
        local okOwner, owner = pcall(function() return buffComponent:GetOwner() end)
        if not okOwner then return end

        local player = GetLocalPlayer(owner)
        if not player then return end

        hasReaperDebuff = true
        Log.Debug("Reaper disruption detected - allowing flicker")
    end

    -- Track ambient earthquake disruption
    if rowName == "Debuff_QuakeDisruption" then
        local okOwner, owner = pcall(function() return buffComponent:GetOwner() end)
        if not okOwner then return end

        local player = GetLocalPlayer(owner)
        if not player then return end

        hasAmbientDebuff = true

        -- Only stop timeline if no reaper is present (reaper takes priority)
        if not hasReaperDebuff then
            Log.Debug("Ambient earthquake - stopping timeline")
            pcall(function()
                -- Stop the timeline directly
                local timeline = player.FlashlightFlickerTimeline
                if timeline and timeline:IsValid() then
                    timeline:Stop()
                end

                player.Light_FlickerAlpha = 1.0
            end)
        else
            Log.Debug("Reaper active - not stopping timeline")
        end
    end
end

-- Clear flag when ambient debuff expires
function FlashlightFlicker.OnBuffRemoved(buffComponent, BuffRowHandleParam)
    local okBuff, buffHandle = pcall(function() return BuffRowHandleParam:get() end)
    if not okBuff or not buffHandle then return end

    local okRowName, rowName = pcall(function() return buffHandle.RowName:ToString() end)
    if not okRowName then return end

    -- Clear reaper disruption flag
    if rowName == "Debuff_Disruption" then
        local okOwner, owner = pcall(function() return buffComponent:GetOwner() end)
        if not okOwner then return end

        local player = GetLocalPlayer(owner)
        if not player then return end

        hasReaperDebuff = false
        Log.Debug("Reaper disruption removed")
    end

    -- Clear ambient earthquake flag
    if rowName == "Debuff_QuakeDisruption" then
        local okOwner, owner = pcall(function() return buffComponent:GetOwner() end)
        if not okOwner then return end

        local player = GetLocalPlayer(owner)
        if not player then return end

        hasAmbientDebuff = false
        Log.Debug("Ambient earthquake debuff removed")
    end
end

-- Block flicker if caused by ambient earthquake (unless reaper is present)
function FlashlightFlicker.OnToggleFlickering(player, StartParam)
    local okStart, start = pcall(function() return StartParam:get() end)
    if not okStart then return end

    -- Only intercept when turning flicker ON
    if not start then return end

    local cachedPlayer = GetLocalPlayer(player)
    if not cachedPlayer then return end

    -- Reaper takes priority - always allow reaper flicker
    if hasReaperDebuff then
        Log.Debug("Allowed flicker (reaper warning)")
        return
    end

    -- Block ambient earthquake flicker only if no reaper is present
    if hasAmbientDebuff then
        Log.Debug("Blocked ambient earthquake flicker - stopping timeline")

        pcall(function()
            -- Stop timeline if it's running
            local timeline = cachedPlayer.FlashlightFlickerTimeline
            if timeline and timeline:IsValid() then
                timeline:Stop()
            end

            cachedPlayer.Light_FlickerAlpha = 1.0
        end)
        return
    end

    -- Allow flicker for any other sources
    Log.Debug("Allowed flicker (other threat)")
end

return FlashlightFlicker
