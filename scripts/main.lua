print("=== [Rebiotic Fixer] MOD LOADING ===\n")

--[[
============================================================================
Rebiotic Fixer - Main Entry Point
============================================================================

This file orchestrates all Rebiotic Fixer features:
1. Loads and validates configuration from ../config.lua
2. Creates loggers for each feature module
3. Initializes feature modules with their config + logger
4. Registers hooks at appropriate lifecycle stages

]]

local LogUtil = require("utils/LogUtil")
local ConfigUtil = require("utils/ConfigUtil")

-- ============================================================
-- SCHEMA & CONFIG VALIDATION
-- ============================================================

local SCHEMA = {
    -- MenuTweaks
    { path = "MenuTweaks.SkipLANHostingDelay", type = "boolean", default = true },

    -- FoodDisplayFix
    { path = "FoodDisplayFix.Enabled", type = "boolean", default = true },
    { path = "FoodDisplayFix.FixExistingFoodOnLoad", type = "boolean", default = false },

    -- CraftingMenu.Brightness
    { path = "CraftingMenu.Brightness.Enabled", type = "boolean", default = true },
    { path = "CraftingMenu.Brightness.LightIntensity", type = "number", default = 10.0, min = 0.1 },

    -- CraftingMenu.Resolution
    { path = "CraftingMenu.Resolution.Enabled", type = "boolean", default = true },
    { path = "CraftingMenu.Resolution.Resolution", type = "number", default = 1024, min = 1, max = 8192 },

    -- DistributionPad.Indicator
    { path = "DistributionPad.Indicator.Enabled", type = "boolean", default = true },
    { path = "DistributionPad.Indicator.RefreshOnBuiltContainer", type = "boolean", default = true },
    { path = "DistributionPad.Indicator.IconEnabled", type = "boolean", default = true },
    { path = "DistributionPad.Indicator.Icon", type = "string", default = "hackingdevice" },
    { path = "DistributionPad.Indicator.IconColor", type = "color", default = { R = 114, G = 242, B = 255 } },
    { path = "DistributionPad.Indicator.IconSize", type = "number", default = 24, min = 1 },
    { path = "DistributionPad.Indicator.IconOffset.Horizontal", type = "number", default = 0 },
    { path = "DistributionPad.Indicator.IconOffset.Vertical", type = "number", default = 0 },
    { path = "DistributionPad.Indicator.TextEnabled", type = "boolean", default = false },
    { path = "DistributionPad.Indicator.Text", type = "string", default = "[DistPad]" },

    -- DistributionPad.Range
    { path = "DistributionPad.Range.Enabled", type = "boolean", default = false },
    { path = "DistributionPad.Range.Multiplier", type = "number", default = 1.5, min = 0.1, max = 10.0 },

    -- LowHealthVignette
    { path = "LowHealthVignette.Enabled", type = "boolean", default = true },
    { path = "LowHealthVignette.Threshold", type = "number", default = 0.25, min = 0.01, max = 1.1 },
    { path = "LowHealthVignette.Color", type = "color", default = { R = 128, G = 0, B = 0, A = 0.3 } },
    { path = "LowHealthVignette.PulseEnabled", type = "boolean", default = true },

    -- DebugFlags
    { path = "DebugFlags.Misc", type = "boolean", default = false },
    { path = "DebugFlags.MenuTweaks", type = "boolean", default = false },
    { path = "DebugFlags.FoodDisplayFix", type = "boolean", default = false },
    { path = "DebugFlags.CraftingMenu", type = "boolean", default = false },
    { path = "DebugFlags.DistributionPad", type = "boolean", default = false },
    { path = "DebugFlags.LowHealthVignette", type = "boolean", default = false },
}

local UserConfig = require("../config")
local configLogger = LogUtil.CreateLogger("Rebiotic Fixer (Config)", false)
local Config = ConfigUtil.ValidateFromSchema(UserConfig, SCHEMA, configLogger)

-- Derived fields (computed from validated config)
Config.DistributionPad.Indicator.TextPattern = Config.DistributionPad.Indicator.Text
    :gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")

-- ============================================================
-- FEATURE MODULES & LOGGERS
-- ============================================================

local MenuTweaks = require("core/MenuTweaks")
local FoodFix = require("core/FoodFix")
local CraftingPreviewFix = require("core/CraftingPreviewFix")
local DistPadTweaks = require("core/DistributionPadTweaks")
local LowHealthVignette = require("core/LowHealthVignette")

local Log = {
    General = LogUtil.CreateLogger("Rebiotic Fixer", Config.DebugFlags.Misc),
    MenuTweaks = LogUtil.CreateLogger("Rebiotic Fixer|MenuTweaks", Config.DebugFlags.MenuTweaks),
    FoodFix = LogUtil.CreateLogger("Rebiotic Fixer|FoodFix", Config.DebugFlags.FoodDisplayFix),
    CraftingMenu = LogUtil.CreateLogger("Rebiotic Fixer|CraftingMenu", Config.DebugFlags.CraftingMenu),
    DistPad = LogUtil.CreateLogger("Rebiotic Fixer|DistPad", Config.DebugFlags.DistributionPad),
    LowHealthVignette = LogUtil.CreateLogger("Rebiotic Fixer|LowHealthVignette", Config.DebugFlags.LowHealthVignette),
}

-- Initialize feature modules
MenuTweaks.Init(Config.MenuTweaks, Log.MenuTweaks)
FoodFix.Init(Config.FoodDisplayFix, Log.FoodFix)
CraftingPreviewFix.Init(Config.CraftingMenu, Log.CraftingMenu)
DistPadTweaks.Init(Config.DistributionPad, Log.DistPad)
LowHealthVignette.Init(Config.LowHealthVignette, Log.LowHealthVignette)

-- ============================================================
-- MODULE STATE
-- ============================================================

-- Hook/feature registration tracking
local HookRegistered = {
    GameState = false,              -- Abiotic_Survival_GameState_C:ReceiveBeginPlay
    MenuTweaks = false,
    FoodFix = false,
    CraftingMenuBrightness = false,
    CraftingMenuResolution = false,
    LowHealthVignette = false,
    DistPadTweaksPrePlay = false,   -- DistPad early registration (catches objects from save)
    DistPadTweaks = false,          -- DistPad standard registration (gameplay hooks)
}

-- Lifecycle event tracking
local GameStateHookFired = false

-- ============================================================
-- HOOK REGISTRATION FUNCTIONS
-- ============================================================

--- Registers a run-once feature if enabled and not already registered
--- @param name string Feature name (must be pre-defined in HookRegistered)
--- @param enabled boolean Whether registration should attempt
--- @param fn function Function that performs registration, returns true on success
local function TryRegister(name, enabled, fn)
    -- Validate name exists in HookRegistered (catches typos)
    if HookRegistered[name] == nil then
        error(string.format("TryRegister: '%s' is not defined in HookRegistered table", name))
    end

    if not enabled or HookRegistered[name] then return end

    if fn() then
        HookRegistered[name] = true
    else
        Log.General.Debug("%s registration failed. Retrying on next level change...", name)
    end
end

-- ============================================================
-- LIFECYCLE HANDLERS
-- ============================================================

local function OnGameState(world)
    GameStateHookFired = true

    if not world:IsValid() then return end

    -- InPlay hooks - only register during active gameplay (with automatic retry on failure)
    TryRegister("CraftingMenuBrightness", Config.CraftingMenu.Brightness.Enabled, CraftingPreviewFix.RegisterInPlayHooks)
    TryRegister("CraftingMenuResolution", Config.CraftingMenu.Resolution.Enabled, CraftingPreviewFix.ApplyResolutionFix)
    TryRegister("LowHealthVignette", Config.LowHealthVignette.Enabled, LowHealthVignette.RegisterInPlayHooks)
    TryRegister("DistPadTweaks", Config.DistributionPad.Indicator.Enabled, DistPadTweaks.RegisterInPlayHooks)
end

-- Hook callback for GameState:ReceiveBeginPlay
local function OnGameStateHook(Context)
    Log.General.Debug("Abiotic_Survival_GameState:ReceiveBeginPlay fired")

    local gameState = Context:get()
    if not gameState:IsValid() then return end

    local okWorld, world = pcall(function() return gameState:GetWorld() end)
    if okWorld and world and world:IsValid() then
        OnGameState(world)
    end
end

-- Register PRE-hook for cleanup BEFORE new map initializes
RegisterInitGameStatePreHook(function(Context)
    if Config.LowHealthVignette.Enabled then
        Log.General.Debug("InitGameStatePRE: Cleaning up vignette")
        LowHealthVignette.Cleanup()
    end
    if Config.DistributionPad.Indicator.Enabled then
        Log.General.Debug("InitGameStatePRE: Cleaning up DistPad cache and widgets")
        DistPadTweaks.Cleanup()
    end
end)

-- ============================================================
-- GAMESTATE HOOK REGISTRATION VIA POLLING
-- ============================================================
-- Blueprint may not be loaded at mod init.
-- Poll until GameState exists, then register hook + handle current map.

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

        -- Register hook once any GameState exists (even main menu)
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

        -- PrePlay hooks - must register before gameplay to catch objects from save and main menu popups
        TryRegister("MenuTweaks", Config.MenuTweaks.SkipLANHostingDelay, MenuTweaks.RegisterPrePlayHooks)
        TryRegister("FoodFix", Config.FoodDisplayFix.Enabled, FoodFix.RegisterPrePlayHooks)
        TryRegister("DistPadTweaksPrePlay",
            Config.DistributionPad.Range.Enabled or Config.DistributionPad.Indicator.Enabled,
            DistPadTweaks.RegisterPrePlayHooks)

        -- If already in gameplay map, handle current map manually
        local gameState = FindFirstOf("Abiotic_Survival_GameState_C")
        if gameState:IsValid() then
            Log.General.Debug("Gameplay GameState found, invoking OnGameState")
            local okWorld, world = pcall(function() return gameState:GetWorld() end)
            if okWorld and world and world:IsValid() then
                OnGameState(world)
            end
        end
    end)
end

PollForMissedHook()

Log.General.Info("Mod loaded")
