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
local CanInteractCache = {}  -- vehicleAddr → true

-- Cached light switch sound
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

    -- Hook tap F on vehicle (InteractWith_B) - server-side only
    local interactSuccess = HookUtil.Register(
        "/Game/Blueprints/Vehicles/ABF_Vehicle_ParentBP.ABF_Vehicle_ParentBP_C:InteractWith_B",
        function(vehicle, InteractingCharacterParam, ComponentUsedParam)
            VehicleLights.OnVehicleInteractB(vehicle, InteractingCharacterParam, ComponentUsedParam)
        end,
        Log
    )

    -- Hook OnRep for client-side visual updates
    local onRepSuccess = HookUtil.Register(
        "/Game/Blueprints/Vehicles/ABF_Vehicle_ParentBP.ABF_Vehicle_ParentBP_C:OnRep_VehicleLightsOn",
        function(vehicle)
            VehicleLights.OnRepVehicleLightsOn(vehicle)
        end,
        Log
    )

    return canInteractSuccess and interactSuccess and onRepSuccess
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

-- Called when VehicleLightsOn property replicates (client-side)
function VehicleLights.OnRepVehicleLightsOn(vehicle)
    Log.Debug("OnRepVehicleLightsOn fired (property changed)")

    -- Get current light state
    local okLights, lightsOn = pcall(function()
        return vehicle.VehicleLightsOn
    end)

    if not okLights then
        Log.Debug("OnRepVehicleLightsOn: Failed to get VehicleLightsOn")
        return
    end

    Log.Debug("OnRepVehicleLightsOn: VehicleLightsOn = %s", tostring(lightsOn))

    -- Update cosmetic effects
    local okToggle = pcall(function()
        vehicle:ToggleHeadlightsFX(lightsOn)
    end)

    if okToggle then
        Log.Debug("OnRepVehicleLightsOn: Called ToggleHeadlightsFX(%s)", tostring(lightsOn))
    end

    -- Update actual light component
    local okHeadlights, headlights = pcall(function()
        return vehicle.Headlights
    end)

    if okHeadlights and headlights and headlights:IsValid() then
        local okSetVis = pcall(function()
            headlights:SetVisibility(lightsOn, false)
        end)

        if okSetVis then
            Log.Debug("OnRepVehicleLightsOn: Set Headlights visibility to %s", tostring(lightsOn))
        end
    end
end

-- Called to check if tap F should be available (CanInteractWith_B)
function VehicleLights.OnCanInteractB(vehicle, HitComponentParam, SuccessParam)
    -- Check if this vehicle type supports lights
    local okClass, className = pcall(function()
        return vehicle:GetClass():GetFName():ToString()
    end)

    if not okClass or not SUPPORTED_VEHICLES[className] then
        return  -- Don't enable tap F for unsupported vehicles
    end

    -- Cache check: only set once per vehicle (this fires every frame)
    local okAddr, vehicleAddr = pcall(function() return vehicle:GetAddress() end)
    if okAddr and vehicleAddr and CanInteractCache[vehicleAddr] then
        -- Already set for this vehicle, just return true
        pcall(function() SuccessParam:set(true) end)
        return
    end

    Log.Debug("OnCanInteractB: Supported vehicle, enabling tap F prompt for first time")

    -- Set Success parameter to true (enables tap F prompt)
    local okSet = pcall(function()
        SuccessParam:set(true)
    end)

    if okSet and okAddr and vehicleAddr then
        CanInteractCache[vehicleAddr] = true
        Log.Debug("OnCanInteractB: Successfully enabled tap F")
    end
end

-- Called when player presses F on vehicle (InteractWith_B)
function VehicleLights.OnVehicleInteractB(vehicle, InteractingCharacterParam, ComponentUsedParam)
    Log.Debug("OnVehicleInteractB fired")

    -- Check if this vehicle type supports lights
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

    -- Check if we have authority (are we on the server?)
    local okAuth, hasAuth = pcall(function() return vehicle:HasAuthority() end)
    Log.Debug("OnVehicleInteractB: HasAuthority = %s", tostring(hasAuth))

    Log.Debug("OnVehicleInteractB: Supported vehicle, toggling lights")

    -- Get current light state
    local okLights, lightsOn = pcall(function()
        return vehicle.VehicleLightsOn
    end)

    if not okLights then
        Log.Debug("OnVehicleInteractB: Failed to get VehicleLightsOn property")
        return
    end

    Log.Debug("OnVehicleInteractB: Current VehicleLightsOn = %s", tostring(lightsOn))

    local newState = not lightsOn

    -- Set the property
    local okSet = pcall(function()
        vehicle.VehicleLightsOn = newState
    end)

    if not okSet then
        Log.Debug("OnVehicleInteractB: Failed to set VehicleLightsOn")
        return
    end

    Log.Debug("OnVehicleInteractB: Set VehicleLightsOn = %s", tostring(newState))

    -- Call OnRep to trigger replication (for multiplayer)
    local okOnRep = pcall(function()
        vehicle:OnRep_VehicleLightsOn()
    end)

    if okOnRep then
        Log.Debug("OnVehicleInteractB: Called OnRep_VehicleLightsOn()")
    else
        Log.Debug("OnVehicleInteractB: Failed to call OnRep_VehicleLightsOn")
    end

    -- Also manually update visuals (OnRep might not do everything we need)
    local okToggle = pcall(function()
        vehicle:ToggleHeadlightsFX(newState)
    end)

    if okToggle then
        Log.Debug("OnVehicleInteractB: Called ToggleHeadlightsFX(%s)", tostring(newState))
    end

    -- Enable/disable the actual light component
    local okHeadlights, headlights = pcall(function()
        return vehicle.Headlights
    end)

    if okHeadlights and headlights and headlights:IsValid() then
        local okSetVis = pcall(function()
            headlights:SetVisibility(newState, false)
        end)

        if okSetVis then
            Log.Debug("OnVehicleInteractB: Set Headlights visibility to %s", tostring(newState))
            Log.Info("Vehicle lights: %s", newState and "ON" or "OFF")
        end
    end

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

            -- Get player controller
            local playerController = UEHelpers.GetPlayerController()
            if not playerController or not playerController:IsValid() then
                return
            end

            local okLoc, location = pcall(function() return vehicle:K2_GetActorLocation() end)
            if not okLoc or not location then
                return
            end

            -- Use ClientPlaySoundAtLocation (local-only)
            pcall(function()
                playerController:ClientPlaySoundAtLocation(LightSwitchSound, location, 1.0, 1.0)
            end)
        end
    end)
end

-- ============================================================
-- CLEANUP (OPTIONAL)
-- ============================================================

function VehicleLights.Cleanup()
    Log.Debug("Cleaning up VehicleLights state")
    CanInteractCache = {}
end

return VehicleLights
