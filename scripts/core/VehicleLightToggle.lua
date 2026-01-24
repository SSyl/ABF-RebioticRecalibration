--[[
============================================================================
VehicleLightToggle - Manual Headlight Control for Vehicles
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
    name = "VehicleLightToggle",
    configKey = "VehicleLightToggle",
    serverSupport = true,  -- Headlight toggle needs server authority

    schema = {
        { path = "Enabled", type = "boolean", default = true },
        { path = "SoundVolume", type = "number", default = 75, min = 0, max = 100 },
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
local LightSwitchSound = CreateInvalidObject()
local GameplayStaticsCache = CreateInvalidObject()

-- State tracking for headlight visibility (to detect replicated changes)
local HeadlightStateCache = {}  -- vehicleAddr -> lastKnownVisibility

local SOUND_ASSET = "SoundWave'/Game/Audio/Environment/Buttons/s_lightswitch_02.s_lightswitch_02'"

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("VehicleLightToggle - %s", status)
end

function Module.GameplayCleanup()
    Log.Debug("Cleaning up VehicleLightToggle state")
    CanInteractCache = {}
    ReplicationEnabledCache = {}
    HeadlightStateCache = {}
    PromptTextCache.lastVehicleAddr = nil
    PromptTextCache.isSupported = false
    TextBlockCache.widgetAddr = nil
    TextBlockCache.textBlock = nil
    LightSwitchSound = CreateInvalidObject()
    GameplayStaticsCache = CreateInvalidObject()
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function Module.RegisterHooks(isDedicatedServer)
    Log.Debug("RegisterHooks called (isDedicatedServer=%s)", tostring(isDedicatedServer))

    local canInteractSuccess = HookUtil.Register(
        "/Game/Blueprints/Vehicles/ABF_Vehicle_ParentBP.ABF_Vehicle_ParentBP_C:CanInteractWith_B",
        function(vehicle, HitComponentParam, SuccessParam)
            Module.OnCanInteractB(vehicle, HitComponentParam, SuccessParam)
        end,
        Log
    )

    local interactSuccess = HookUtil.Register(
        "/Game/Blueprints/Vehicles/ABF_Vehicle_ParentBP.ABF_Vehicle_ParentBP_C:InteractWith_B",
        function(vehicle, InteractingCharacterParam, ComponentUsedParam)
            Module.OnVehicleInteractB(vehicle, InteractingCharacterParam, ComponentUsedParam)
        end,
        Log
    )

    -- Client-only hooks (prompt text, sound effects)
    local promptTextSuccess = true
    if not isDedicatedServer then
        promptTextSuccess = HookUtil.RegisterABFInteractionPromptUpdate(
            Module.OnUpdateInteractionPrompts,
            Log
        )

        -- LocalFX hook - fires on the client that initiates the interaction (for sound)
        HookUtil.Register(
            "/Game/Blueprints/Vehicles/ABF_Vehicle_ParentBP.ABF_Vehicle_ParentBP_C:InteractWith_B_LocalFX",
            function(vehicle, HoldParam)
                Module.OnVehicleInteractB_LocalFX(vehicle)
            end,
            Log
        )

        if Config.SoundVolume > 0 then
            ExecuteInGameThread(function()
                local sound, wasFound, didLoad = LoadAsset(SOUND_ASSET)
                if wasFound and didLoad and sound:IsValid() then
                    LightSwitchSound = sound
                    Log.Debug("Pre-loaded light switch sound")
                end
            end)
        end
    end

    return canInteractSuccess and promptTextSuccess and interactSuccess
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnCanInteractB(vehicle, HitComponentParam, SuccessParam)
    if not vehicle:IsValid() then return end

    local className = vehicle:GetClass():GetFName():ToString()
    if not SUPPORTED_VEHICLES[className] then return end

    local vehicleAddr = vehicle:GetAddress()

    -- Sync FX state with actual headlight visibility (catches replicated changes)
    local headlights = vehicle.Headlights
    if headlights:IsValid() and vehicleAddr then
        local isVisible = headlights:IsVisible()
        local lastState = HeadlightStateCache[vehicleAddr]

        if lastState ~= isVisible then
            HeadlightStateCache[vehicleAddr] = isVisible
            Log.Debug("OnCanInteractB: Syncing FX state to %s", tostring(isVisible))
            vehicle:ToggleHeadlightsFX(isVisible)
        end
    end

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
    if not widget:IsValid() then return end

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
    if not vehicle:IsValid() then return end

    local className = vehicle:GetClass():GetFName():ToString()
    if not SUPPORTED_VEHICLES[className] then return end

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
end

function Module.OnVehicleInteractB_LocalFX(vehicle)
    if not vehicle:IsValid() then return end

    local className = vehicle:GetClass():GetFName():ToString()
    if not SUPPORTED_VEHICLES[className] then return end

    local headlights = vehicle.Headlights
    if not headlights:IsValid() then return end

    -- Toggle cosmetic FX locally (headlight textures/bloom)
    local newState = not headlights:IsVisible()
    vehicle:ToggleHeadlightsFX(newState)

    -- Play light switch sound
    if Config.SoundVolume == 0 then return end
    if not LightSwitchSound:IsValid() then return end

    if not GameplayStaticsCache:IsValid() then GameplayStaticsCache = UEHelpers.GetGameplayStatics() end
    if not GameplayStaticsCache:IsValid() then return end

    local volumeMultiplier = Config.SoundVolume / 100

    local okSound, errSound = pcall(function()
        GameplayStaticsCache:SpawnSoundAttached(
            LightSwitchSound,       -- Sound
            headlights,             -- AttachToComponent
            FName("None"),          -- AttachPointName (no socket)
            {X=0, Y=0, Z=0},        -- Location (relative)
            {Pitch=0, Yaw=0, Roll=0}, -- Rotation (relative)
            0,                      -- LocationType (KeepRelativeOffset)
            true,                   -- bStopWhenAttachedToDestroyed
            volumeMultiplier,       -- VolumeMultiplier
            1.0,                    -- PitchMultiplier
            0.0,                    -- StartTime
            nil,                    -- AttenuationSettings
            nil,                    -- ConcurrencySettings
            true                    -- bAutoDestroy
        )
    end)
    if not okSound then
        Log.Debug("OnVehicleInteractB_LocalFX: SpawnSoundAttached failed: %s", tostring(errSound))
    end
end

return Module
