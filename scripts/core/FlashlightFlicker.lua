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

-- ============================================================
-- MODULE METADATA
-- ============================================================

local Module = {
    name = "FlashlightFlicker",
    configKey = "FlashlightFlicker",

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

local cachedPlayerPawn = nil
local hasAmbientDebuff = false
local hasReaperDebuff = false

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("FlashlightFlicker - %s", status)
end

function Module.GameplayCleanup()
    hasAmbientDebuff = false
    hasReaperDebuff = false
    cachedPlayerPawn = CreateInvalidObject()
    Log.Debug("FlashlightFlicker state cleaned up")
end

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

local function GetLocalPlayer(actor)
    if not cachedPlayerPawn:IsValid() then
        cachedPlayerPawn = UEHelpers.GetPlayer()
    end

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

function Module.RegisterHooks()
    return HookUtil.Register({
        {
            path = "/Game/Blueprints/Characters/Abiotic_CharacterBuffComponent.Abiotic_CharacterBuffComponent_C:BuffReceived",
            callback = Module.OnBuffReceived
        },
        {
            path = "/Game/Blueprints/Characters/Abiotic_CharacterBuffComponent.Abiotic_CharacterBuffComponent_C:BuffRemoved",
            callback = Module.OnBuffRemoved
        },
        {
            path = "/Game/Blueprints/Characters/Abiotic_PlayerCharacter.Abiotic_PlayerCharacter_C:ToggleFlickering",
            callback = Module.OnToggleFlickering
        },
    }, Log)
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnBuffReceived(buffComponent, BuffRowHandleParam)
    local okBuff, buffHandle = pcall(function() return BuffRowHandleParam:get() end)
    if not okBuff or not buffHandle then return end

    local okRowName, rowName = pcall(function() return buffHandle.RowName:ToString() end)
    if not okRowName then return end

    if rowName == "Debuff_Disruption" then
        local owner = buffComponent:GetOwner()
        local cachedPlayer = GetLocalPlayer(owner)
        if not cachedPlayer then return end

        hasReaperDebuff = true
        Log.Debug("Reaper disruption detected - allowing flicker")
    end

    if rowName == "Debuff_QuakeDisruption" then
        local owner = buffComponent:GetOwner()
        local cachedPlayer = GetLocalPlayer(owner)
        if not cachedPlayer then return end

        hasAmbientDebuff = true

        if not hasReaperDebuff then
            Log.Debug("Ambient earthquake - stopping timeline")
            local timeline = cachedPlayer.FlashlightFlickerTimeline
            if timeline and timeline:IsValid() then
                timeline:Stop()
            end
            cachedPlayer.Light_FlickerAlpha = 1.0
        else
            Log.Debug("Reaper active - not stopping timeline")
        end
    end
end

function Module.OnBuffRemoved(buffComponent, BuffRowHandleParam)
    local okBuff, buffHandle = pcall(function() return BuffRowHandleParam:get() end)
    if not okBuff or not buffHandle then return end

    local okRowName, rowName = pcall(function() return buffHandle.RowName:ToString() end)
    if not okRowName then return end

    if rowName == "Debuff_Disruption" then
        local owner = buffComponent:GetOwner()
        local cachedPlayer = GetLocalPlayer(owner)
        if not cachedPlayer then return end

        hasReaperDebuff = false
        Log.Debug("Reaper disruption removed")
    end

    if rowName == "Debuff_QuakeDisruption" then
        local owner = buffComponent:GetOwner()
        local cachedPlayer = GetLocalPlayer(owner)
        if not cachedPlayer then return end

        hasAmbientDebuff = false
        Log.Debug("Ambient earthquake debuff removed")
    end
end

function Module.OnToggleFlickering(player, StartParam)
    local okStart, start = pcall(function() return StartParam:get() end)
    if not okStart then return end

    if not start then return end

    local cachedPlayer = GetLocalPlayer(player)
    if not cachedPlayer then return end

    if hasReaperDebuff then
        Log.Debug("Allowed flicker (reaper warning)")
        return
    end

    if hasAmbientDebuff then
        Log.Debug("Blocked ambient earthquake flicker - stopping timeline")
        local timeline = cachedPlayer.FlashlightFlickerTimeline
        if timeline and timeline:IsValid() then
            timeline:Stop()
        end
        cachedPlayer.Light_FlickerAlpha = 1.0
        return
    end

    Log.Debug("Allowed flicker (other threat)")
end

return Module
