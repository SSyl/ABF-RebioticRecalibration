print("=== [Rebiotic Recalibration] MOD LOADING ===\n")

--[[
============================================================================
Rebiotic Recalibration - Main Entry Point
============================================================================

Module-driven architecture:
1. Modules export metadata (name, schema, hookPoint, serverSupport, lifecycle functions)
2. main.lua orchestrates lifecycle detection and module registration
3. Adding a new feature = create module file + add to MODULES list

Hook Points:
- "MainMenu": Registers when main menu detected
- "Gameplay": Registers when gameplay map loaded (once per map)

Lifecycle Detection:
- Client/Host: Abiotic_PlayerCharacter_C:ReceiveBeginPlay fires for all player spawns
- Dedicated Server: Polls for Abiotic_Survival_GameState_C (set DedicatedServer.Enabled=true in config)

Server Support:
- Modules with serverSupport=true run on dedicated servers
- Modules without serverSupport are skipped on dedicated servers
- RegisterHooks receives isDedicatedServer param to skip client-only hooks
]]

local LogUtil = require("utils/LogUtil")
local ConfigMigration = require("utils/ConfigMigration")
local ConfigUtil = require("utils/ConfigUtil")
local HookUtil = require("utils/HookUtil")
local PlayerUtil = require("utils/PlayerUtil")
local UEHelpers = require("UEHelpers")

-- Dedicated server mode flag (set from Config.DedicatedServerMode after config loads)
local isDedicatedServer = false

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
    "core/FlashlightFlickerFix",
    "core/AutoJumpCrouch",
    "core/VehicleLightToggle",
    "core/HideHotbarHotkeys",
    "core/MinigameZoneFix",
    "core/CorpseGibFix",
    "core/PlayerTracker",
    "core/AmmoCounter",
    "core/TeleporterTags",
    "core/BedsKeepSpawn",
}

-- ============================================================
-- LOAD MODULES & BUILD SCHEMA
-- ============================================================

local Modules = {}
local SCHEMA = {
    { path = "DedicatedServer.Enabled", type = "boolean", default = false },
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
                    trim = entry.trim,
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
        print(string.format("[Rebiotic Recalibration] ERROR: Failed to load module '%s': %s", path, tostring(mod)))
    end
end

-- ============================================================
-- CONFIG MIGRATION
-- ============================================================

-- Get mod root path (parent of scripts folder)
local sourceInfo = debug.getinfo(1, "S").source
local modRoot = sourceInfo:match("@(.+[\\/])[Ss]cripts[\\/]")
if modRoot then
    modRoot = modRoot:gsub("[\\/]$", "")  -- Remove trailing slash
    local ok, msg = ConfigMigration.EnsureConfig(modRoot)
    if msg then
        print("[Rebiotic Recalibration] " .. msg)
    end
else
    print("[Rebiotic Recalibration] WARNING: Could not determine mod root path, config migration skipped")
end

-- ============================================================
-- CONFIG VALIDATION
-- ============================================================

-- Try to load config - fall back to empty table if missing/corrupted
local loadOk, UserConfig = pcall(require, "../config")
if not loadOk then
    print("[Rebiotic Recalibration] WARNING: Could not load config.lua, using defaults")
    UserConfig = {}
end

-- Schema validation fills missing fields with defaults
local configLogger = LogUtil.CreateLogger("Rebiotic Recalibration (Config)", false)
local Config = ConfigUtil.ValidateFromSchema(UserConfig, SCHEMA, configLogger)

-- Derived fields (computed from validated config)
if Config.DistributionPad and Config.DistributionPad.Indicator then
    Config.DistributionPad.Indicator.TextPattern = Config.DistributionPad.Indicator.Text
        :gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
end

-- Apply dedicated server mode from config
if Config.DedicatedServer and Config.DedicatedServer.Enabled then
    isDedicatedServer = true
end

-- ============================================================
-- CREATE LOGGERS & INITIALIZE MODULES
-- ============================================================

local Log = {
    General = LogUtil.CreateLogger("Rebiotic Recalibration", Config.DebugFlags.Misc),
}

for _, mod in ipairs(Modules) do
    -- Skip modules without serverSupport on dedicated servers
    if not isDedicatedServer or mod.serverSupport then
        local debugKey = mod.debugKey or mod.configKey
        local debugEnabled = Config.DebugFlags[debugKey] or false

        mod._log = LogUtil.CreateLogger("Rebiotic Recalibration|" .. mod.name, debugEnabled)

        mod._config = Config[mod.configKey]

        if mod.Init then
            mod.Init(mod._config, mod._log)
        end
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

local function RegisterModuleHooks(hookPoint, isDedicatedServer)
    for _, mod in ipairs(Modules) do
        if mod.hookPoint == hookPoint and mod.RegisterHooks then
            -- Skip modules without serverSupport on dedicated servers
            if isDedicatedServer and not mod.serverSupport then
                Log.General.Debug("Skipping %s (no dedicated server support)", mod.name)
            elseif IsModuleEnabled(mod) then
                local ok = mod.RegisterHooks(isDedicatedServer)
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
        PlayerUtil.Reset()
        gameplayFired = false
    end

    mainMenuFired = true
    Log.General.Debug("Main menu detected")
    RegisterModuleHooks("MainMenu", isDedicatedServer)
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
    RegisterModuleHooks("Gameplay", isDedicatedServer)
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

-- ============================================================
-- LIFECYCLE: DEDICATED SERVER (poll for GameState)
-- ============================================================

local function PollForGameState(attempts)
    attempts = attempts or 0
    if gameplayFired then return end
    if attempts > 100 then
        Log.General.Error("Failed to detect GameState after %d attempts", attempts)
        return
    end

    ExecuteInGameThread(function()
        local gameState = FindFirstOf("Abiotic_Survival_GameState_C")
        if gameState and gameState:IsValid() then
            gameplayFired = true
            Log.General.Debug("GameState detected - registering all server hooks")
            RegisterModuleHooks("MainMenu", true)
            RegisterModuleHooks("Gameplay", true)
        else
            ExecuteWithDelay(50, function()
                PollForGameState(attempts + 1)
            end)
        end
    end)
end

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

-- ============================================================
-- STARTUP: Choose detection path based on server type
-- ============================================================

if isDedicatedServer then
    Log.General.Info("Dedicated server detected - polling for GameState")
    PollForGameState()
else
    -- Client/Listen server: use PlayerCharacter detection
    ExecuteWithDelay(250, function() RegisterLifecycleHook() end)
    PollForMissedState()
end

Log.General.Info("Mod loaded (%d modules)", #Modules)
