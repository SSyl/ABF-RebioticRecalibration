--[[
============================================================================
CorpseGibFix - Prevent Gibsplosion VFX on Map Load
============================================================================

Fixes visual bug where previously-destroyed decorative corpses play gore VFX
(blood splatter + sound) every time the area loads. The game spawns corpses,
then applies saved IsGibbed state ~260-290ms later, triggering RefreshGibbedState
which plays VFX even though corpse was already destroyed in a prior session.

Fix: On ReceiveBeginPlay, cache and clear GibParticles/GibbedSound properties.
Restore after configurable threshold (default 500ms). Save-load gibs happen
within this window and find nil properties, preventing VFX. Normal gameplay
gibs (player attacks corpse) happen after restoration.

HOOKS: CharacterCorpse_ParentBP_C:ReceiveBeginPlay
PERFORMANCE: Fires on corpse spawn, uses ExecuteWithDelay for restoration
]]

local HookUtil = require("utils/HookUtil")

-- ============================================================
-- MODULE METADATA
-- ============================================================

local Module = {
    -- Identity
    name = "CorpseGibFix",
    configKey = "CorpseGibFix",

    -- Config schema (paths relative to configKey)
    schema = {
        { path = "Enabled", type = "boolean", default = true },
        { path = "Threshold", type = "number", default = 500 },
    },

    -- Hook point: "PreInit", "PostInit", or nil for no hooks
    hookPoint = "PostInit",
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

-- Cache original GibParticles/GibbedSound to restore after threshold
local CorpseGibAssets = {}

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("CorpseGibFix - %s (Threshold: %dms)", status, Config.Threshold)
end

function Module.Cleanup()
    CorpseGibAssets = {}
    Log.Debug("CorpseGibFix state cleaned up")
end

function Module.RegisterHooks()
    Log.Debug("Registering corpse hooks...")

    ExecuteInGameThread(function()
        pcall(function()
            LoadAsset("/Game/Blueprints/Environment/Special/CharacterCorpse_ParentBP")
        end)

        local success = HookUtil.Register(
            "/Game/Blueprints/Environment/Special/CharacterCorpse_ParentBP.CharacterCorpse_ParentBP_C:ReceiveBeginPlay",
            Module.OnReceiveBeginPlay,
            Log
        )

        if success then
            Log.Debug("Corpse hooks registered")
        else
            Log.Warning("Corpse hooks failed to register")
        end
    end)

    return true
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnReceiveBeginPlay(corpse)
    local okAddr, addr = pcall(function() return corpse:GetAddress() end)
    if not okAddr or not addr then return end

    -- Pre-emptive fix: Cache and clear gib assets to prevent save-load gibsplosion
    local okParticles, particles = pcall(function() return corpse.GibParticles end)
    local hasParticles = okParticles and particles and particles:IsValid()

    local okSound, sound = pcall(function() return corpse.GibbedSound end)
    local hasSound = okSound and sound and sound:IsValid()

    if not hasParticles and not hasSound then
        return
    end

    CorpseGibAssets[addr] = {
        particles = hasParticles and particles or nil,
        sound = hasSound and sound or nil
    }

    if hasParticles then
        pcall(function() corpse.GibParticles = nil end)
    end
    if hasSound then
        pcall(function() corpse.GibbedSound = nil end)
    end

    Log.Debug("Cleared gib assets for corpse 0x%X", addr)

    -- Restore after threshold (for normal gameplay gibs)
    ExecuteWithDelay(Config.Threshold, function()
        ExecuteInGameThread(function()
            local cached = CorpseGibAssets[addr]
            if not cached then return end

            CorpseGibAssets[addr] = nil

            if not corpse:IsValid() then
                Log.Debug("Corpse 0x%X no longer valid, skipping restore", addr)
                return
            end

            if cached.particles then
                pcall(function() corpse.GibParticles = cached.particles end)
                cached.particles = nil
            end
            if cached.sound then
                pcall(function() corpse.GibbedSound = cached.sound end)
                cached.sound = nil
            end

            Log.Debug("Restored gib assets for corpse 0x%X", addr)
        end)
    end)
end

return Module
