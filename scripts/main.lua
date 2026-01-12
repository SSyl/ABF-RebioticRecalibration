print("=== [Rebiotic Fixer] MOD LOADING ===\n")

--[[
============================================================================
Rebiotic Fixer - Main Entry Point
============================================================================

Module-driven architecture:
1. Modules export metadata (name, schema, phase, lifecycle functions)
2. main.lua auto-wires everything from a simple MODULES list
3. Adding a new feature = create module file + add to MODULES list

]]

local LogUtil = require("utils/LogUtil")
local ConfigUtil = require("utils/ConfigUtil")

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
}

-- ============================================================
-- LOAD MODULES & BUILD SCHEMA
-- ============================================================

local Modules = {}
local SCHEMA = {
    -- General debug flag
    { path = "DebugFlags.Misc", type = "boolean", default = false },
}

-- Load all modules and aggregate their schemas
for _, path in ipairs(MODULE_PATHS) do
    local ok, mod = pcall(require, path)
    if ok and mod then
        table.insert(Modules, mod)

        -- Add module schema entries (prefixed with configKey)
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

        -- Add debug flag for this module
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

    -- Create logger for this module
    mod._log = LogUtil.CreateLogger("Rebiotic Fixer|" .. mod.name, debugEnabled)

    -- Get module's config section
    mod._config = Config[mod.configKey]

    -- Initialize module
    if mod.Init then
        mod.Init(mod._config, mod._log)
    end
end

-- ============================================================
-- HOOK REGISTRATION STATE
-- ============================================================

local HookRegistered = {
    GameState = false,
}

-- Initialize hook tracking for each module
for _, mod in ipairs(Modules) do
    if mod.hookPoint then
        HookRegistered[mod.name] = false
    end
    -- Support modules with multiple hook points
    if mod.preInit then
        HookRegistered[mod.name .. "_PreInit"] = false
    end
    if mod.postInit then
        HookRegistered[mod.name .. "_PostInit"] = false
    end
end

local GameStateHookFired = false

-- ============================================================
-- HOOK REGISTRATION HELPERS
-- ============================================================

local function TryRegister(name, enabled, fn)
    if HookRegistered[name] == nil then
        error(string.format("TryRegister: '%s' is not defined in HookRegistered table", name))
    end

    if not enabled or HookRegistered[name] then return end

    if fn() then
        HookRegistered[name] = true
    else
        Log.General.Debug("%s registration failed (Blueprint not loaded yet). Will retry on next map load.", name)
    end
end

-- Check if module feature is enabled
local function IsModuleEnabled(mod, hookPoint)
    local cfg = mod._config
    if not cfg then return false end

    -- Check hookPoint-specific enable condition
    if hookPoint == "PreInit" and mod.preInit and mod.preInit.isEnabled then
        return mod.preInit.isEnabled(cfg)
    elseif hookPoint == "PostInit" and mod.postInit and mod.postInit.isEnabled then
        return mod.postInit.isEnabled(cfg)
    end

    -- Check module-level enable condition
    if mod.isEnabled then
        return mod.isEnabled(cfg)
    end

    -- Default: check cfg.Enabled
    return cfg.Enabled == true
end

-- ============================================================
-- LIFECYCLE HANDLERS
-- ============================================================

local function OnGameState(world)
    GameStateHookFired = true

    if not world:IsValid() then return end

    -- Register PostInit hooks for all modules
    for _, mod in ipairs(Modules) do
        -- Simple hookPoint
        if mod.hookPoint == "PostInit" and mod.RegisterHooks then
            TryRegister(mod.name, IsModuleEnabled(mod, "PostInit"), mod.RegisterHooks)
        end

        -- Complex: separate postInit config
        if mod.postInit and mod.RegisterPostInitHooks then
            TryRegister(mod.name .. "_PostInit", IsModuleEnabled(mod, "PostInit"), mod.RegisterPostInitHooks)
        end
    end
end

local function OnGameStateHook(Context)
    Log.General.Debug("Abiotic_Survival_GameState:ReceiveBeginPlay fired")

    local gameState = Context:get()
    if not gameState:IsValid() then return end

    local okWorld, world = pcall(function() return gameState:GetWorld() end)
    if okWorld and world:IsValid() then
        OnGameState(world)
    end
end

-- Register PRE-hook for cleanup BEFORE new map initializes
RegisterInitGameStatePreHook(function(Context)
    for _, mod in ipairs(Modules) do
        if mod.Cleanup then
            -- Check if cleanup should run
            local shouldCleanup = false
            local cfg = mod._config

            if mod.cleanup and mod.cleanup.isEnabled then
                shouldCleanup = mod.cleanup.isEnabled(cfg)
            elseif cfg and cfg.Enabled then
                shouldCleanup = true
            end

            if shouldCleanup then
                Log.General.Debug("InitGameStatePRE: Cleaning up %s", mod.name)
                mod.Cleanup()
            end
        end
    end
end)

-- ============================================================
-- GAMESTATE HOOK REGISTRATION VIA POLLING
-- ============================================================

local function PollForMissedHook(attempts)
    attempts = attempts or 0

    if GameStateHookFired then return end

    ExecuteInGameThread(function()
        local base = FindFirstOf("GameStateBase")
        if not base:IsValid() then
            if attempts < 100 then
                ExecuteWithDelay(100, function()
                    PollForMissedHook(attempts + 1)
                end)
            else
                Log.General.Error("GameStateBase never found after %d attempts", attempts + 1)
            end
            return
        end

        -- Register hook once any GameState exists
        TryRegister("GameState", true, function()
            local ok = pcall(RegisterHook,
                "/Game/Blueprints/Meta/Abiotic_Survival_GameState.Abiotic_Survival_GameState_C:ReceiveBeginPlay",
                OnGameStateHook
            )
            if ok then
                Log.General.Debug("GameState hook registered")
            end
            return ok
        end)

        -- PreInit hooks for all modules
        for _, mod in ipairs(Modules) do
            -- Simple hookPoint
            if mod.hookPoint == "PreInit" and mod.RegisterHooks then
                TryRegister(mod.name, IsModuleEnabled(mod, "PreInit"), mod.RegisterHooks)
            end

            -- Complex: separate preInit config
            if mod.preInit and mod.RegisterPreInitHooks then
                TryRegister(mod.name .. "_PreInit", IsModuleEnabled(mod, "PreInit"), mod.RegisterPreInitHooks)
            end
        end

        -- If already in gameplay map, handle current map manually
        local gameState = FindFirstOf("Abiotic_Survival_GameState_C")
        if gameState:IsValid() then
            Log.General.Debug("Gameplay GameState found, invoking OnGameState")
            local okWorld, world = pcall(function() return gameState:GetWorld() end)
            if okWorld and world:IsValid() then
                OnGameState(world)
            end
        end
    end)
end

PollForMissedHook()

Log.General.Info("Mod loaded (%d modules)", #Modules)
