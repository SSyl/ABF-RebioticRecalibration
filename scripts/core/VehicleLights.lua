local HookUtil = require("utils/HookUtil")
local VehicleLights = {}

-- Module state (set during Init)
local Config = nil
local Log = nil

-- Vehicle types that support headlights (Sleigh excluded)
local SUPPORTED_VEHICLES = {
    ["ABF_Vehicle_SUV_C"] = true,
    ["ABF_Vehicle_Forklift_C"] = true,
    ["ABF_Vehicle_SecurityCart_C"] = true,
}

-- Cache for CanInteractWith_B (per-frame hook, only set once per vehicle)
local CanInteractCache = {}  -- vehicleAddr -> true

-- Cache for SetIsReplicated (one-time setup per vehicle)
local ReplicationEnabledCache = {}  -- vehicleAddr -> true

-- Per-frame cache for UpdateInteractionPrompts to avoid repeated vehicle type checks
local PromptTextCache = { lastVehicleAddr = nil, isSupported = false }
local TextBlockCache = { widgetAddr = nil, textBlock = nil }

local LightSwitchSound = nil

-- ============================================================
-- CORE LOGIC
-- ============================================================

function VehicleLights.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("VehicleLights - %s", status)
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function VehicleLights.RegisterInPlayHooks()
    Log.Debug("RegisterInPlayHooks called")

    -- Hook CanInteractWith_B to enable tap F prompt
    local canInteractSuccess = HookUtil.Register(
        "/Game/Blueprints/Vehicles/ABF_Vehicle_ParentBP.ABF_Vehicle_ParentBP_C:CanInteractWith_B",
        function(vehicle, HitComponentParam, SuccessParam)
            VehicleLights.OnCanInteractB(vehicle, HitComponentParam, SuccessParam)
        end,
        Log
    )

    -- Hook UpdateInteractionPrompts to customize F key prompt text
    local promptTextSuccess = HookUtil.Register(
        "/Game/Blueprints/Widgets/W_PlayerHUD_InteractionPrompt.W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts",
        function(widget, ShowPressInteract, ShowHoldInteract, ShowPressPackage, ShowHoldPackage,
                 ObjectUnderConstruction, ConstructionPercent, RequiresPower, Radioactive,
                 ShowDescription, ExtraNoteLines, HitActorParam, HitComponentParam, RequiresPlug)
            VehicleLights.OnUpdateInteractionPrompts(widget, HitActorParam)
        end,
        Log
    )

    -- Hook tap F on vehicle (InteractWith_B)
    local interactSuccess = HookUtil.Register(
        "/Game/Blueprints/Vehicles/ABF_Vehicle_ParentBP.ABF_Vehicle_ParentBP_C:InteractWith_B",
        function(vehicle, InteractingCharacterParam, ComponentUsedParam)
            VehicleLights.OnVehicleInteractB(vehicle, InteractingCharacterParam, ComponentUsedParam)
        end,
        Log
    )

    return canInteractSuccess and promptTextSuccess and interactSuccess
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function VehicleLights.OnCanInteractB(vehicle, HitComponentParam, SuccessParam)
    local okClass, className = pcall(function()
        return vehicle:GetClass():GetFName():ToString()
    end)

    if not okClass or not SUPPORTED_VEHICLES[className] then return end

    -- Cache check: only set once per vehicle (this fires every frame)
    local vehicleAddr = vehicle:GetAddress()
    if vehicleAddr and CanInteractCache[vehicleAddr] then
        pcall(function() SuccessParam:set(true) end)
        return
    end

    Log.Debug("OnCanInteractB: Supported vehicle, enabling tap F prompt for first time")

    -- Set Success parameter to true (enables tap F prompt)
    local okSet = pcall(function()
        SuccessParam:set(true)
    end)

    if okSet and vehicleAddr then
        CanInteractCache[vehicleAddr] = true
        Log.Debug("OnCanInteractB: Successfully enabled tap F")
    end
end

function VehicleLights.OnUpdateInteractionPrompts(widget, HitActorParam)
    local okHitActor, hitActor = pcall(function() return HitActorParam:get() end)
    if not okHitActor or not hitActor or not hitActor:IsValid() then
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

    -- Fast path: same vehicle as last frame
    if actorAddr == PromptTextCache.lastVehicleAddr then
        if not PromptTextCache.isSupported then return end
        -- Supported vehicle, update text
    else
        -- New actor - check if it's a supported vehicle
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

    -- Get/cache TextBlock widget
    local widgetAddr = widget:GetAddress()
    if not widgetAddr then return end

    if widgetAddr ~= TextBlockCache.widgetAddr then
        local ok, tb = pcall(function() return widget.PressPackageSuffix end)
        if ok and tb and tb:IsValid() then
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

    -- Game resets text to "package" every frame, so we must set it every frame
    pcall(function()
        textBlock:SetText(FText("toggle lights"))
    end)
end

function VehicleLights.OnVehicleInteractB(vehicle, InteractingCharacterParam, ComponentUsedParam)
    Log.Debug("OnVehicleInteractB fired")

    local okClass, className = pcall(function()
        return vehicle:GetClass():GetFName():ToString()
    end)

    if not okClass then
        Log.Debug("OnVehicleInteractB: Failed to get vehicle class name")
        return
    end

    Log.Debug("OnVehicleInteractB: Vehicle class = %s", className)

    if not SUPPORTED_VEHICLES[className] then
        Log.Debug("OnVehicleInteractB: Vehicle type not supported (no headlights)")
        return
    end

    Log.Debug("OnVehicleInteractB: Supported vehicle, toggling lights")

    local okHeadlights, headlights = pcall(function()
        return vehicle.Headlights
    end)

    if not okHeadlights or not headlights or not headlights:IsValid() then
        Log.Debug("OnVehicleInteractB: Failed to get Headlights component")
        return
    end

    -- Enable replication on first interaction (one-time setup per vehicle)
    local vehicleAddr = vehicle:GetAddress()
    if vehicleAddr and not ReplicationEnabledCache[vehicleAddr] then
        Log.Debug("OnVehicleInteractB: First interaction, enabling SpotLight replication")

        -- Enable replication on SpotLight component
        -- This causes visibility changes to replicate to clients
        pcall(function()
            headlights:SetIsReplicated(true)
        end)
        Log.Debug("OnVehicleInteractB: Enabled replication on Headlights (SpotLight)")

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
    Log.Debug("OnVehicleInteractB: Current visibility = %s, toggling to %s", tostring(isVisible), tostring(newState))

    -- Set SpotLight visibility (replicates to clients via SetIsReplicated)
    local okSetVis = pcall(function()
        headlights:SetVisibility(newState, false)
    end)

    if not okSetVis then
        Log.Debug("OnVehicleInteractB: Failed to set Headlights visibility")
        return
    end

    Log.Debug("OnVehicleInteractB: Set Headlights visibility to %s", tostring(newState))
    Log.Info("Vehicle lights: %s", newState and "ON" or "OFF")

    -- Play light switch sound (local-only)
    ExecuteInGameThread(function()
        -- Load sound if not cached (must be on game thread)
        if not LightSwitchSound then
            local sound, wasFound, didLoad = LoadAsset("SoundWave'/Game/Audio/Environment/Buttons/s_lightswitch_02.s_lightswitch_02'")
            if wasFound and didLoad and sound and sound:IsValid() then
                LightSwitchSound = sound
                Log.Debug("OnVehicleInteractB: Loaded light switch sound")
            else
                Log.Debug("OnVehicleInteractB: Failed to load light switch sound (found=%s, loaded=%s)", tostring(wasFound), tostring(didLoad))
            end
        end

        if LightSwitchSound and LightSwitchSound:IsValid() then
            local UEHelpers = require("UEHelpers")

            local playerController = UEHelpers.GetPlayerController()
            if not playerController or not playerController:IsValid() then
                return
            end

            local okLoc, location = pcall(function() return vehicle:K2_GetActorLocation() end)
            if not okLoc or not location then
                return
            end

            pcall(function()
                playerController:ClientPlaySoundAtLocation(LightSwitchSound, location, 1.0, 1.0)
            end)
        end
    end)
end

-- ============================================================
-- CLEANUP
-- ============================================================

function VehicleLights.Cleanup()
    Log.Debug("Cleaning up VehicleLights state")
    CanInteractCache = {}
    ReplicationEnabledCache = {}
    PromptTextCache.lastVehicleAddr = nil
    PromptTextCache.isSupported = false
    TextBlockCache.widgetAddr = nil
    TextBlockCache.textBlock = nil
    LightSwitchSound = nil
end

return VehicleLights
