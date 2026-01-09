--[[
============================================================================
FlashlightFlicker - Disable Ambient Flashlight Flicker
============================================================================

PURPOSE:
Prevents flashlight from flickering during ambient earthquake events while
keeping the immersive camera shake and audio. Flicker is still triggered
by threats like Reapers.

BEHAVIOR:
- Ambient earthquakes: No flicker (camera shake + audio still work)
- Reaper disruption: Flicker works normally (warning system intact)

IMPLEMENTATION:
When Debuff_QuakeDisruption (ambient earthquake) is applied to the local player,
stops the FlashlightFlickerTimeline directly and resets the alpha to 1.0.
Debuff_Disruption (Reaper) works normally since we don't intercept it.

HOOKS:
- Abiotic_CharacterBuffComponent_C:BuffReceived → Stop timeline when QuakeDisruption detected
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

-- ============================================================
-- CORE LOGIC
-- ============================================================

function FlashlightFlicker.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("FlashlightFlicker - %s", status)
end

-- Helper to get/refresh cached player pawn, optionally validating against an actor
local function GetLocalPlayer(actor)
    -- Refresh cache if needed
    if not cachedPlayerPawn or not cachedPlayerPawn:IsValid() then
        cachedPlayerPawn = UEHelpers.GetPlayer()
    end

    -- If no actor provided, just return cached player
    if not actor then
        return cachedPlayerPawn
    end

    -- If actor provided, validate and compare addresses
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

    if rowName == "Debuff_QuakeDisruption" then
        local okOwner, owner = pcall(function() return buffComponent:GetOwner() end)
        if not okOwner then return end

        local player = GetLocalPlayer(owner)
        if not player then return end

        hasAmbientDebuff = true
        Log.Debug("Ambient earthquake debuff applied - stopping timeline")

        pcall(function()
            player.LightFlickerEnabled = false

            -- Stop the timeline directly
            local timeline = player.FlashlightFlickerTimeline
            if timeline and timeline:IsValid() then
                timeline:Stop()
                Log.Debug("Stopped FlashlightFlickerTimeline")
            end

            -- Reset alpha to 1.0 (no flicker)
            player.Light_FlickerAlpha = 1.0
        end)
    end
end

-- Clear flag when ambient debuff expires
function FlashlightFlicker.OnBuffRemoved(buffComponent, BuffRowHandleParam)
    local okBuff, buffHandle = pcall(function() return BuffRowHandleParam:get() end)
    if not okBuff or not buffHandle then return end

    local okRowName, rowName = pcall(function() return buffHandle.RowName:ToString() end)
    if not okRowName then return end

    if rowName == "Debuff_QuakeDisruption" then
        local okOwner, owner = pcall(function() return buffComponent:GetOwner() end)
        if not okOwner then return end

        local player = GetLocalPlayer(owner)
        if not player then return end

        hasAmbientDebuff = false
        Log.Debug("Ambient earthquake debuff removed - re-enabling flicker")

        pcall(function()
            player.LightFlickerEnabled = true
        end)
    end
end

-- Block flicker if caused by ambient earthquake
function FlashlightFlicker.OnToggleFlickering(player, StartParam)
    local okStart, start = pcall(function() return StartParam:get() end)
    if not okStart then return end

    -- Only intercept when turning flicker ON
    if not start then return end

    local cachedPlayer = GetLocalPlayer(player)
    if not cachedPlayer then return end

    -- If ambient earthquake debuff is active, block the flicker
    if hasAmbientDebuff then
        Log.Debug("Blocked ambient earthquake flicker - stopping timeline")

        pcall(function()
            cachedPlayer.LightFlickerEnabled = false

            -- Stop timeline if it's running
            local timeline = cachedPlayer.FlashlightFlickerTimeline
            if timeline and timeline:IsValid() then
                timeline:Stop()
            end

            -- Reset alpha to 1.0
            cachedPlayer.Light_FlickerAlpha = 1.0
        end)

        StartParam:set(false)
        return
    end

    -- Allow flicker for reapers and any other sources
    Log.Debug("Allowed flicker (reaper or other threat)")
end

return FlashlightFlicker
