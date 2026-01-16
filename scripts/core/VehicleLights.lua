--[[
============================================================================
VehicleLights - Manual Headlight Control for Vehicles
============================================================================

Adds tap-F interaction to toggle vehicle headlights (SUV, Forklift, SecurityCart).
Enables SpotLight replication for multiplayer sync. Changes interaction prompt
text from "package" to "toggle lights". Plays light switch sound on toggle.

HOOKS:
- ABF_Vehicle_ParentBP_C:CanInteractWith_B (enable tap-F prompt)
- ABF_Vehicle_ParentBP_C:InteractWith_B (toggle lights)
- W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts (custom prompt text)

PERFORMANCE: Per-frame prompt hook with address caching
]]

local HookUtil = require("utils/HookUtil")
local UEHelpers = require("UEHelpers")

-- ============================================================
-- MODULE METADATA
-- ============================================================

local Module = {
    name = "VehicleLights",
    configKey = "VehicleLights",

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

local SUPPORTED_VEHICLES = {
    ["ABF_Vehicle_SUV_C"] = true,
    ["ABF_Vehicle_Forklift_C"] = true,
    ["ABF_Vehicle_SecurityCart_C"] = true,
}

local CanInteractCache = {}
local ReplicationEnabledCache = {}
local PromptTextCache = { lastVehicleAddr = nil, isSupported = false }
local TextBlockCache = { widgetAddr = nil, textBlock = nil }
local LightSwitchSound = nil
local GameplayStaticsCache = nil

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("VehicleLights - %s", status)
end

function Module.GameplayCleanup()
    Log.Debug("Cleaning up VehicleLights state")
    CanInteractCache = {}
    ReplicationEnabledCache = {}
    PromptTextCache.lastVehicleAddr = nil
    PromptTextCache.isSupported = false
    TextBlockCache.widgetAddr = nil
    TextBlockCache.textBlock = nil
    LightSwitchSound = nil
    GameplayStaticsCache = nil
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function Module.RegisterHooks()
    Log.Debug("RegisterHooks called")

    local canInteractSuccess = HookUtil.Register(
        "/Game/Blueprints/Vehicles/ABF_Vehicle_ParentBP.ABF_Vehicle_ParentBP_C:CanInteractWith_B",
        function(vehicle, HitComponentParam, SuccessParam)
            Module.OnCanInteractB(vehicle, HitComponentParam, SuccessParam)
        end,
        Log
    )

    local promptTextSuccess = HookUtil.RegisterABFInteractionPromptUpdate(
        Module.OnUpdateInteractionPrompts,
        Log
    )

    local interactSuccess = HookUtil.Register(
        "/Game/Blueprints/Vehicles/ABF_Vehicle_ParentBP.ABF_Vehicle_ParentBP_C:InteractWith_B",
        function(vehicle, InteractingCharacterParam, ComponentUsedParam)
            Module.OnVehicleInteractB(vehicle, InteractingCharacterParam, ComponentUsedParam)
        end,
        Log
    )

    ExecuteInGameThread(function()
        local sound, wasFound, didLoad = LoadAsset("SoundWave'/Game/Audio/Environment/Buttons/s_lightswitch_02.s_lightswitch_02'")
        if wasFound and didLoad and sound:IsValid() then
            LightSwitchSound = sound
            Log.Debug("Pre-loaded light switch sound")
        end
    end)

    return canInteractSuccess and promptTextSuccess and interactSuccess
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnCanInteractB(vehicle, HitComponentParam, SuccessParam)
    local className = vehicle:GetClass():GetFName():ToString()
    if not SUPPORTED_VEHICLES[className] then return end

    local vehicleAddr = vehicle:GetAddress()
    if vehicleAddr and CanInteractCache[vehicleAddr] then
        SuccessParam:set(true)
        return
    end

    Log.Debug("OnCanInteractB: Supported vehicle, enabling tap F prompt for first time")

    SuccessParam:set(true)
    if vehicleAddr then
        CanInteractCache[vehicleAddr] = true
    end
end

function Module.OnUpdateInteractionPrompts(widget, HitActorParam)
    local okHitActor, hitActor = pcall(function() return HitActorParam:get() end)
    if not okHitActor or not hitActor:IsValid() then
        PromptTextCache.lastVehicleAddr = nil
        PromptTextCache.isSupported = false
        return
    end

    local actorAddr = hitActor:GetAddress()
    if not actorAddr then
        PromptTextCache.lastVehicleAddr = nil
        PromptTextCache.isSupported = false
        return
    end

    if actorAddr == PromptTextCache.lastVehicleAddr then
        if not PromptTextCache.isSupported then return end
    else
        PromptTextCache.lastVehicleAddr = actorAddr
        PromptTextCache.isSupported = false

        local className = hitActor:GetClass():GetFName():ToString()
        if not SUPPORTED_VEHICLES[className] then
            return
        end

        PromptTextCache.isSupported = true
    end

    local widgetAddr = widget:GetAddress()
    if not widgetAddr then return end

    if widgetAddr ~= TextBlockCache.widgetAddr then
        local tb = widget.PressPackageSuffix
        if tb:IsValid() then
            TextBlockCache.widgetAddr = widgetAddr
            TextBlockCache.textBlock = tb
        else
            TextBlockCache.widgetAddr = nil
            TextBlockCache.textBlock = nil
            return
        end
    end

    local textBlock = TextBlockCache.textBlock
    if not textBlock or not textBlock:IsValid() then
        TextBlockCache.widgetAddr = nil
        TextBlockCache.textBlock = nil
        return
    end

    textBlock:SetText(FText("toggle lights"))
end

function Module.OnVehicleInteractB(vehicle, InteractingCharacterParam, ComponentUsedParam)
    local className = vehicle:GetClass():GetFName():ToString()
    if not SUPPORTED_VEHICLES[className] then
        return
    end

    local headlights = vehicle.Headlights
    if not headlights:IsValid() then
        Log.Debug("OnVehicleInteractB: Failed to get Headlights component")
        return
    end

    local vehicleAddr = vehicle:GetAddress()
    if vehicleAddr and not ReplicationEnabledCache[vehicleAddr] then
        Log.Debug("OnVehicleInteractB: First interaction, enabling SpotLight replication")
        headlights:SetIsReplicated(true)
        ReplicationEnabledCache[vehicleAddr] = true
    end

    local isVisible = headlights:IsVisible()
    local newState = not isVisible

    headlights:SetVisibility(newState, false)
    Log.Info("Vehicle lights: %s", newState and "ON" or "OFF")

    if LightSwitchSound and LightSwitchSound:IsValid() then
        local location = vehicle:K2_GetActorLocation()
        if not location then
            Log.Debug("Failed to get vehicle location")
            return
        end

        if not GameplayStaticsCache or not GameplayStaticsCache:IsValid() then
            GameplayStaticsCache = UEHelpers.GetGameplayStatics()
        end
        if not GameplayStaticsCache or not GameplayStaticsCache:IsValid() then
            Log.Debug("GameplayStatics not valid")
            return
        end

        local okSound, errSound = pcall(function()
            GameplayStaticsCache:PlaySoundAtLocation(
                vehicle,           -- WorldContextObject
                LightSwitchSound,  -- Sound
                location,          -- Location
                {},                -- Rotation (default)
                1.0,               -- VolumeMultiplier
                1.0,               -- PitchMultiplier
                0.0,               -- StartTime
                nil,               -- AttenuationSettings
                nil,               -- ConcurrencySettings
                nil,               -- OwningActor
                nil                -- InitialParams
            )
        end)
        if not okSound then
            Log.Debug("PlaySoundAtLocation failed: %s", tostring(errSound))
        end
    else
        Log.Debug("LightSwitchSound not valid")
    end
end

return Module
