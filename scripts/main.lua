print("=== [Rebiotic Fixer] MOD LOADING ===\n")

--[[
============================================================================
Rebiotic Fixer - Main Entry Point
============================================================================

Module-driven architecture:
1. Modules export metadata (name, schema, hookPoint, lifecycle functions)
2. main.lua orchestrates lifecycle detection and module registration
3. Adding a new feature = create module file + add to MODULES list

Hook Points:
- "MainMenu": Registers when main menu detected
- "Gameplay": Registers when gameplay map loaded (once per map)

Lifecycle Detection (single hook):
- Abiotic_PlayerCharacter_C:ReceiveBeginPlay fires for all player spawns
- MainMenu path in character name → main menu
- Abiotic_Survival_GameState_C exists → gameplay
- Cleanup runs when transitioning between states
]]

local LogUtil = require("utils/LogUtil")
local ConfigUtil = require("utils/ConfigUtil")
local HookUtil = require("utils/HookUtil")
local UEHelpers = require("UEHelpers")

-- ============================================================
-- MODULE REGISTRY
-- ============================================================

-- Add new modules here - that's it!
local MODULE_PATHS = {
    "core/MenuTweaks",
    "core/FoodFix",
    "core/CraftingPreviewFix",
    "core/DistributionPadTweaks",
    "core/LowHealthVignette",
    "core/FlashlightFlicker",
    "core/AutoJumpCrouch",
    "core/VehicleLights",
    "core/HideHotbarHotkeys",
    "core/MinigameBarFix",
    "core/CorpseGibFix",
    "core/PlayerTracker",
    "core/AmmoCounter",
    "core/TeleporterTags",
}

-- ============================================================
-- LOAD MODULES & BUILD SCHEMA
-- ============================================================

local Modules = {}
local SCHEMA = {
    { path = "DebugFlags.Main", type = "boolean", default = false },
}

-- Load all modules and aggregate their schemas
for _, path in ipairs(MODULE_PATHS) do
    local ok, mod = pcall(require, path)
    if ok and mod then
        table.insert(Modules, mod)

        -- module schema entries are prefixed with configKey
        if mod.schema then
            for _, entry in ipairs(mod.schema) do
                table.insert(SCHEMA, {
                    path = mod.configKey .. "." .. entry.path,
                    type = entry.type,
                    default = entry.default,
                    min = entry.min,
                    max = entry.max,
                })
            end
        end

        local debugKey = mod.debugKey or mod.configKey
        table.insert(SCHEMA, {
            path = "DebugFlags." .. debugKey,
            type = "boolean",
            default = false,
        })
    else
        print(string.format("[Rebiotic Fixer] ERROR: Failed to load module '%s': %s", path, tostring(mod)))
    end
end

-- ============================================================
-- CONFIG VALIDATION
-- ============================================================

local UserConfig = require("../config")
local configLogger = LogUtil.CreateLogger("Rebiotic Fixer (Config)", false)
local Config = ConfigUtil.ValidateFromSchema(UserConfig, SCHEMA, configLogger)

-- Derived fields (computed from validated config)
if Config.DistributionPad and Config.DistributionPad.Indicator then
    Config.DistributionPad.Indicator.TextPattern = Config.DistributionPad.Indicator.Text
        :gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
end

-- ============================================================
-- CREATE LOGGERS & INITIALIZE MODULES
-- ============================================================

local Log = {
    General = LogUtil.CreateLogger("Rebiotic Fixer", Config.DebugFlags.Misc),
}

for _, mod in ipairs(Modules) do
    local debugKey = mod.debugKey or mod.configKey
    local debugEnabled = Config.DebugFlags[debugKey] or false

    mod._log = LogUtil.CreateLogger("Rebiotic Fixer|" .. mod.name, debugEnabled)

    mod._config = Config[mod.configKey]

    if mod.Init then
        mod.Init(mod._config, mod._log)
    end
end

-- ============================================================
-- HELPERS
-- ============================================================

local function IsModuleEnabled(mod)
    local cfg = mod._config
    if not cfg then return false end

    if mod.isEnabled then
        return mod.isEnabled(cfg)
    end

    return cfg.Enabled == true
end

local function RegisterModuleHooks(hookPoint)
    for _, mod in ipairs(Modules) do
        if mod.hookPoint == hookPoint and mod.RegisterHooks then
            if IsModuleEnabled(mod) then
                local ok = mod.RegisterHooks()
                if ok then
                    Log.General.Debug("Registered %s hooks for %s", hookPoint, mod.name)
                else
                    Log.General.Warning("Failed to register %s hooks for %s", hookPoint, mod.name)
                end
            end
        end
    end
end

local function RunModuleCleanup(cleanupType)
    local methodName = cleanupType .. "Cleanup"
    local cleanupKey = cleanupType:lower()

    for _, mod in ipairs(Modules) do
        local cleanupFn = mod[methodName]
        if cleanupFn then
            local shouldCleanup = false
            local cfg = mod._config

            if mod.cleanup and mod.cleanup[cleanupKey] then
                shouldCleanup = mod.cleanup[cleanupKey](cfg)
            elseif mod.isEnabled then
                shouldCleanup = mod.isEnabled(cfg)
            elseif cfg and cfg.Enabled then
                shouldCleanup = true
            end

            if shouldCleanup then
                Log.General.Debug("%s cleanup: %s", cleanupType, mod.name)
                cleanupFn()
            end
        end
    end
end

-- ============================================================
-- LIFECYCLE STATE
-- ============================================================

local mainMenuFired = false
local gameplayFired = false
local lifecycleHookRegistered = false

-- ============================================================
-- LIFECYCLE: MAIN MENU
-- ============================================================

local function OnMainMenuDetected(character)
    if mainMenuFired then return end

    -- Cleanup previous state if transitioning from gameplay
    if gameplayFired then
        HookUtil.ResetWarmup()
        RunModuleCleanup("Gameplay")
        gameplayFired = false
    end

    mainMenuFired = true
    Log.General.Debug("Main menu detected")
    RegisterModuleHooks("MainMenu")
end

-- ============================================================
-- LIFECYCLE: GAMEPLAY
-- ============================================================

local function OnGameplayDetected(gameState)
    if gameplayFired then return end

    -- Cleanup previous state if transitioning from main menu
    if mainMenuFired then
        HookUtil.ResetWarmup()
        RunModuleCleanup("MainMenu")
        mainMenuFired = false
    end

    gameplayFired = true
    Log.General.Debug("Gameplay detected")
    RegisterModuleHooks("Gameplay")
end

-- Delayed registration of lifecycle hook (Blueprint not loaded on mod init)
local function RegisterLifecycleHook(attempts)
    attempts = attempts or 0
    if lifecycleHookRegistered or attempts > 20 then return end

    local ok = HookUtil.RegisterABFPlayerCharacterBeginPlay(function(character)
        local fullName = character:GetFullName()
        local isMainMenuSpawn = fullName:find("/Game/Maps/MainMenu", 1, true)

        -- Smart early exits: only process potential transitions
        if mainMenuFired and isMainMenuSpawn then return end
        if gameplayFired and not isMainMenuSpawn then return end

        if isMainMenuSpawn then
            OnMainMenuDetected(character)
            return
        end

        -- Check for gameplay (Abiotic_Survival_GameState_C exists)
        local survivalGameState = FindFirstOf("Abiotic_Survival_GameState_C")
        if survivalGameState and survivalGameState:IsValid() then
            OnGameplayDetected(survivalGameState)
        else
            Log.General.Debug("PlayerCharacter: Unknown map: %s", fullName)
        end
    end, Log.General)

    if ok then
        lifecycleHookRegistered = true
        Log.General.Debug("Registered lifecycle hook (Abiotic_PlayerCharacter_C:ReceiveBeginPlay)")
    else
        ExecuteWithDelay(250, function()
            RegisterLifecycleHook(attempts + 1)
        end)
    end
end

ExecuteWithDelay(250, function() RegisterLifecycleHook() end)

-- ============================================================
-- LIFECYCLE: POLL FOR MISSED STATE (late init / hot-reload)
-- ============================================================

local function PollForMissedState(attempts)
    attempts = attempts or 0
    if attempts > 10 then return end
    if mainMenuFired or gameplayFired then return end

    ExecuteInGameThread(function()
        local base = UEHelpers.GetGameStateBase()
        if not base:IsValid() then
            ExecuteWithDelay(500, function()
                PollForMissedState(attempts + 1)
            end)
            return
        end

        local fullName = base:GetFullName()

        if fullName:find("Abiotic_Survival_GameState_C", 1, true) then
            OnGameplayDetected(base)
        elseif fullName:find("/Game/Maps/MainMenu.MainMenu:PersistentLevel.", 1, true) then
            -- At main menu - find the character for OnMainMenuDetected
            local character = FindFirstOf("Abiotic_PlayerCharacter_C")
            if character:IsValid() then
                local charName = character:GetFullName()
                if charName:find("/Game/Maps/MainMenu.MainMenu:PersistentLevel.", 1, true) then
                    OnMainMenuDetected(character)
                end
            end
        end
    end)
end

PollForMissedState()

Log.General.Info("Mod loaded (%d modules)", #Modules)
