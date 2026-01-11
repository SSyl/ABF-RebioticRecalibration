local HookUtil = require("utils/HookUtil")
local UEHelpers = require("UEHelpers")
local AutoJumpCrouch = {}

-- Module state (set during Init)
local Config = nil
local Log = nil

local cachedPlayerPawn = nil
local autoCrouched = false

-- ============================================================
-- CORE LOGIC
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

function AutoJumpCrouch.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    local mode = Config.RequireJumpHeld and "Hold to crouch" or "Tap to crouch"
    Log.Info("AutoJumpCrouch - %s (Delay: %dms, Mode: %s)", status, Config.Delay, mode)
end

function AutoJumpCrouch.Cleanup()
    autoCrouched = false
    cachedPlayerPawn = nil
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function AutoJumpCrouch.RegisterInPlayHooks()
    -- POST-HOOK: Jump (fires AFTER jump launches, preserves sprint momentum)
    local success1 = HookUtil.RegisterNative(
        "/Script/Engine.Character:Jump",
        nil,  -- No PRE-HOOK
        AutoJumpCrouch.OnJump,  -- POST-HOOK
        Log
    )

    -- Blueprint hooks (always POST)
    local success2 = HookUtil.Register({
        {
            path = "/Game/Blueprints/Characters/Abiotic_Character_ParentBP.Abiotic_Character_ParentBP_C:TryApplyFallDamage",
            callback = AutoJumpCrouch.OnTryApplyFallDamage
        },
    }, Log)

    return success1 and success2
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function AutoJumpCrouch.OnJump(character)
    local player = GetLocalPlayer(character)
    if not player then return end

    autoCrouched = false  -- Clear stale state from previous jump

    -- Spam prevention - check falling first (more common than swimming)
    local okFalling, isFalling = pcall(function()
        return player.CharacterMovement:IsValid() and player.CharacterMovement:IsFalling()
    end)
    if okFalling and isFalling then
        Log.Debug("Already mid-air, skipping auto-crouch (spam prevention)")
        return
    end

    -- Swimming check (less common)
    local okSwimming, isSwimming = pcall(function()
        return player.CharacterMovement:IsValid() and player.CharacterMovement:IsSwimming()
    end)
    if okSwimming and isSwimming then
        Log.Debug("Swimming, skipping auto-crouch")
        return
    end

    -- For toggle-sprint users: stop sprinting so crouch works
    if Config.ClearSprintOnJump then
        local okSprinting, isSprinting = pcall(function() return player:IsSprinting() end)
        if okSprinting and isSprinting then
            local okToggle, err = pcall(function() player:ToggleSprint() end)
            if not okToggle then
                Log.Debug("ToggleSprint() failed: %s", tostring(err))
            end
        end
    end

    ExecuteWithDelay(Config.Delay, function()
        ExecuteInGameThread(function()
            if not player:IsValid() then return end

            -- Only crouch if still airborne (prevents ground crouch if landed before delay expired)
            local okFalling, isFalling = pcall(function()
                return player.CharacterMovement and player.CharacterMovement:IsFalling()
            end)
            if not (okFalling and isFalling) then
                Log.Debug("Landed before crouch delay expired, skipping")
                return
            end

            -- Check jump button hold state
            local okJumpHoldTime, jumpHoldTime = pcall(function() return player.JumpKeyHoldTime end)
            local isJumpHeld = okJumpHoldTime and jumpHoldTime and jumpHoldTime > 0

            if Config.RequireJumpHeld then
                -- Only crouch if jump IS held (hold to crouch)
                if not isJumpHeld then
                    Log.Debug("Jump button not held after delay, skipping auto-crouch")
                    return
                end
            else
                -- Only crouch if jump is NOT held (tap to crouch)
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

-- ============================================================
-- TryApplyFallDamage - Auto-uncrouch after landing (if we auto-crouched)
-- ============================================================

function AutoJumpCrouch.OnTryApplyFallDamage(character)
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

    -- Call UnCrouch even if not visibly crouched (clears queued crouch from sprinting)
    local okUncrouch, err = pcall(function() player:UnCrouch(false) end)

    if not okUncrouch then
        Log.Debug("UnCrouch() failed: %s", tostring(err))
    end
    autoCrouched = false
end

return AutoJumpCrouch
