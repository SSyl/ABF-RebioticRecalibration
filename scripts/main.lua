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

Lifecycle:
- Main menu detection via Abiotic_PlayerCharacter_C:ReceiveBeginPlay (fires at MainMenu map)
- Gameplay detection via Abiotic_Survival_GameState_C:ReceiveBeginPlay
- Cleanup runs when transitioning between states (before init of new state)
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
local gameplayHookRegistered = false
local mainMenuHookRegistered = false

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
    Log.General.Debug("Main menu detected: %s", character:GetFullName())
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
    Log.General.Debug("Gameplay detected: %s", gameState:GetFullName())
    RegisterModuleHooks("Gameplay")
end

-- Delayed registration of gameplay hook (Blueprint not loaded on mod init)
local function RegisterGameplayHook(attempts)
    attempts = attempts or 0
    if gameplayHookRegistered or attempts > 20 then return end

    local ok, err = pcall(function()
        RegisterHook(
            "/Game/Blueprints/Meta/Abiotic_Survival_GameState.Abiotic_Survival_GameState_C:ReceiveBeginPlay",
            function(Context)
                local gameState = Context:get()
                if not gameState:IsValid() then return end
                OnGameplayDetected(gameState)
            end
        )
    end)

    if ok then
        gameplayHookRegistered = true
        Log.General.Debug("Registered Abiotic_Survival_GameState_C:ReceiveBeginPlay hook")
    else
        ExecuteWithDelay(250, function()
            RegisterGameplayHook(attempts + 1)
        end)
    end
end

ExecuteWithDelay(250, function() RegisterGameplayHook() end)

-- Delayed registration of main menu hook (Blueprint not loaded on mod init)
local function RegisterMainMenuHook(attempts)
    attempts = attempts or 0
    if mainMenuHookRegistered or attempts > 20 then return end

    local ok = HookUtil.RegisterABFPlayerCharacterBeginPlay(function(character)
        local fullName = character:GetFullName()
        if fullName:find("/Game/Maps/MainMenu.MainMenu:PersistentLevel.", 1, true) then
            OnMainMenuDetected(character)
        end
    end, Log.General)

    if ok then
        mainMenuHookRegistered = true
        Log.General.Debug("Registered Abiotic_PlayerCharacter_C:ReceiveBeginPlay hook for main menu detection")
    else
        ExecuteWithDelay(250, function()
            RegisterMainMenuHook(attempts + 1)
        end)
    end
end

ExecuteWithDelay(250, function() RegisterMainMenuHook() end)

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
