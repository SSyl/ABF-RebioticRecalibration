--[[
============================================================================
AutoJumpCrouch - Automatically Crouch During Jumps
============================================================================

Automatically crouches player after jump with configurable delay. Supports two modes:
tap-to-crouch (default) or hold-to-crouch. Auto-uncrouches on landing unless crouch
key is held. Clears sprint on jump for toggle-sprint users (config option).

HOOKS:
- Character:Jump (POST, native)
- Abiotic_Character_ParentBP_C:TryApplyFallDamage

PERFORMANCE: Fires on jump/landing, not per-frame
]]

local HookUtil = require("utils/HookUtil")
local UEHelpers = require("UEHelpers")

-- ============================================================
-- MODULE METADATA
-- ============================================================

local Module = {
    name = "AutoJumpCrouch",
    configKey = "AutoJumpCrouch",

    schema = {
        { path = "Enabled", type = "boolean", default = false },
        { path = "Delay", type = "number", default = 250, min = 0, max = 1000 },
        { path = "ClearSprintOnJump", type = "boolean", default = true },
        { path = "RequireJumpHeld", type = "boolean", default = true },
        { path = "DisableAutoUncrouch", type = "boolean", default = false },
    },

    hookPoint = "Gameplay",
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

local cachedPlayerPawn = nil
local autoCrouched = false

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

local function GetLocalPlayer(character)
    if not cachedPlayerPawn or not cachedPlayerPawn:IsValid() then
        cachedPlayerPawn = UEHelpers.GetPlayer()
    end

    if not character:IsValid() then return nil end
    if not cachedPlayerPawn or not cachedPlayerPawn:IsValid() then return nil end

    local characterAddr = character:GetAddress()
    local playerAddr = cachedPlayerPawn:GetAddress()
    if characterAddr ~= playerAddr then return nil end

    return cachedPlayerPawn
end

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    local mode = Config.RequireJumpHeld and "Hold to crouch" or "Tap to crouch"
    Log.Info("AutoJumpCrouch - %s (Delay: %dms, Mode: %s)", status, Config.Delay, mode)
end

function Module.GameplayCleanup()
    autoCrouched = false
    cachedPlayerPawn = nil
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function Module.RegisterHooks()
    local success1 = HookUtil.RegisterNative(
        "/Script/Engine.Character:Jump",
        nil,
        Module.OnJump,
        Log
    )

    local success2 = HookUtil.Register({
        {
            path = "/Game/Blueprints/Characters/Abiotic_Character_ParentBP.Abiotic_Character_ParentBP_C:TryApplyFallDamage",
            callback = Module.OnTryApplyFallDamage
        },
    }, Log)

    return success1 and success2
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnJump(character)
    local player = GetLocalPlayer(character)
    if not player then return end

    autoCrouched = false

    local okFalling, isFalling = pcall(function()
        return player.CharacterMovement:IsValid() and player.CharacterMovement:IsFalling()
    end)
    if okFalling and isFalling then
        Log.Debug("Already mid-air, skipping auto-crouch (spam prevention)")
        return
    end

    local okSwimming, isSwimming = pcall(function()
        return player.CharacterMovement:IsValid() and player.CharacterMovement:IsSwimming()
    end)
    if okSwimming and isSwimming then
        Log.Debug("Swimming, skipping auto-crouch")
        return
    end

    if Config.ClearSprintOnJump then
        local okSprinting, isSprinting = pcall(function() return player:IsSprinting() end)
        if okSprinting and isSprinting then
            pcall(function() player:ToggleSprint() end)
        end
    end

    ExecuteWithDelay(Config.Delay, function()
        ExecuteInGameThread(function()
            if not player:IsValid() then return end

            local okFalling, isFalling = pcall(function()
                return player.CharacterMovement and player.CharacterMovement:IsFalling()
            end)
            if not (okFalling and isFalling) then
                Log.Debug("Landed before crouch delay expired, skipping")
                return
            end

            local okJumpHoldTime, jumpHoldTime = pcall(function() return player.JumpKeyHoldTime end)
            local isJumpHeld = okJumpHoldTime and jumpHoldTime and jumpHoldTime > 0

            if Config.RequireJumpHeld then
                if not isJumpHeld then
                    Log.Debug("Jump button not held after delay, skipping auto-crouch")
                    return
                end
            else
                if isJumpHeld then
                    Log.Debug("Jump button still held after delay, skipping auto-crouch")
                    return
                end
            end

            local okCrouch, err = pcall(function() player:Crouch(false) end)

            if okCrouch then
                autoCrouched = true
            else
                Log.Debug("Crouch() failed: %s", tostring(err))
            end
        end)
    end)
end

function Module.OnTryApplyFallDamage(character)
    local player = GetLocalPlayer(character)
    if not player then return end

    if Config.DisableAutoUncrouch then
        autoCrouched = false
        return
    end

    if not autoCrouched then return end

    local okKeyHeld, isKeyHeld = pcall(function() return player.Local_KeyHeld_Crouch end)
    if okKeyHeld and isKeyHeld then
        Log.Debug("Crouch button held, staying crouched")
        autoCrouched = false
        return
    end

    pcall(function() player:UnCrouch(false) end)
    autoCrouched = false
end

return Module
