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

    local promptTextSuccess = HookUtil.Register(
        "/Game/Blueprints/Widgets/W_PlayerHUD_InteractionPrompt.W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts",
        function(widget, ShowPressInteract, ShowHoldInteract, ShowPressPackage, ShowHoldPackage,
                 ObjectUnderConstruction, ConstructionPercent, RequiresPower, Radioactive,
                 ShowDescription, ExtraNoteLines, HitActorParam, HitComponentParam, RequiresPlug)
            Module.OnUpdateInteractionPrompts(widget, HitActorParam)
        end,
        Log,
        { warmup = true }
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
    local okClass, className = pcall(function()
        return vehicle:GetClass():GetFName():ToString()
    end)

    if not okClass or not SUPPORTED_VEHICLES[className] then return end

    local vehicleAddr = vehicle:GetAddress()
    if vehicleAddr and CanInteractCache[vehicleAddr] then
        pcall(function() SuccessParam:set(true) end)
        return
    end

    Log.Debug("OnCanInteractB: Supported vehicle, enabling tap F prompt for first time")

    local okSet = pcall(function()
        SuccessParam:set(true)
    end)

    if okSet and vehicleAddr then
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

        local okClass, className = pcall(function()
            return hitActor:GetClass():GetFName():ToString()
        end)

        if not okClass or not SUPPORTED_VEHICLES[className] then
            return
        end

        PromptTextCache.isSupported = true
    end

    local widgetAddr = widget:GetAddress()
    if not widgetAddr then return end

    if widgetAddr ~= TextBlockCache.widgetAddr then
        local ok, tb = pcall(function() return widget.PressPackageSuffix end)
        if ok and tb:IsValid() then
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

    pcall(function()
        textBlock:SetText(FText("toggle lights"))
    end)
end

function Module.OnVehicleInteractB(vehicle, InteractingCharacterParam, ComponentUsedParam)
    local okClass, className = pcall(function()
        return vehicle:GetClass():GetFName():ToString()
    end)

    if not okClass or not SUPPORTED_VEHICLES[className] then
        return
    end

    local okHeadlights, headlights = pcall(function()
        return vehicle.Headlights
    end)

    if not okHeadlights or not headlights:IsValid() then
        Log.Debug("OnVehicleInteractB: Failed to get Headlights component")
        return
    end

    local vehicleAddr = vehicle:GetAddress()
    if vehicleAddr and not ReplicationEnabledCache[vehicleAddr] then
        Log.Debug("OnVehicleInteractB: First interaction, enabling SpotLight replication")

        pcall(function()
            headlights:SetIsReplicated(true)
        end)

        ReplicationEnabledCache[vehicleAddr] = true
    end

    local okVisible, isVisible = pcall(function()
        return headlights:IsVisible()
    end)

    if not okVisible then
        Log.Debug("OnVehicleInteractB: Failed to get Headlights visibility")
        return
    end

    local newState = not isVisible

    local okSetVis = pcall(function()
        headlights:SetVisibility(newState, false)
    end)

    if not okSetVis then
        Log.Debug("OnVehicleInteractB: Failed to set Headlights visibility")
        return
    end

    Log.Info("Vehicle lights: %s", newState and "ON" or "OFF")

    if LightSwitchSound and LightSwitchSound:IsValid() then
        local okLoc, location = pcall(function() return vehicle:K2_GetActorLocation() end)
        if not okLoc or not location then
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
