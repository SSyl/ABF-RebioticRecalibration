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

    -- FlashlightFlicker
    { path = "FlashlightFlicker.Enabled", type = "boolean", default = true },

    -- AutoJumpCrouch
    { path = "AutoJumpCrouch.Enabled", type = "boolean", default = false },
    { path = "AutoJumpCrouch.Delay", type = "number", default = 200, min = 0, max = 1000 },
    { path = "AutoJumpCrouch.ClearSprintOnJump", type = "boolean", default = true },
    { path = "AutoJumpCrouch.RequireJumpHeld", type = "boolean", default = true },
    { path = "AutoJumpCrouch.DisableAutoUncrouch", type = "boolean", default = false },

    -- VehicleLights
    { path = "VehicleLights.Enabled", type = "boolean", default = true },

    -- HideHotbarHotkeys
    { path = "HideHotbarHotkeys.Enabled", type = "boolean", default = false },

    -- MinigameBarFix
    { path = "MinigameBarFix.Enabled", type = "boolean", default = true },

    -- DebugFlags
    { path = "DebugFlags.Misc", type = "boolean", default = false },
    { path = "DebugFlags.MenuTweaks", type = "boolean", default = false },
    { path = "DebugFlags.FoodDisplayFix", type = "boolean", default = false },
    { path = "DebugFlags.CraftingMenu", type = "boolean", default = false },
    { path = "DebugFlags.DistributionPad", type = "boolean", default = false },
    { path = "DebugFlags.LowHealthVignette", type = "boolean", default = false },
    { path = "DebugFlags.FlashlightFlicker", type = "boolean", default = false },
    { path = "DebugFlags.AutoJumpCrouch", type = "boolean", default = false },
    { path = "DebugFlags.VehicleLights", type = "boolean", default = true },
    { path = "DebugFlags.HideHotbarHotkeys", type = "boolean", default = false },
    { path = "DebugFlags.MinigameBarFix", type = "boolean", default = false },
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
local FlashlightFlicker = require("core/FlashlightFlicker")
local AutoJumpCrouch = require("core/AutoJumpCrouch")
local VehicleLights = require("core/VehicleLights")
local HideHotbarHotkeys = require("core/HideHotbarHotkeys")
local MinigameBarFix = require("core/MinigameBarFix")

local Log = {
    General = LogUtil.CreateLogger("Rebiotic Fixer", Config.DebugFlags.Misc),
    MenuTweaks = LogUtil.CreateLogger("Rebiotic Fixer|MenuTweaks", Config.DebugFlags.MenuTweaks),
    FoodFix = LogUtil.CreateLogger("Rebiotic Fixer|FoodFix", Config.DebugFlags.FoodDisplayFix),
    CraftingMenu = LogUtil.CreateLogger("Rebiotic Fixer|CraftingMenu", Config.DebugFlags.CraftingMenu),
    DistPad = LogUtil.CreateLogger("Rebiotic Fixer|DistPad", Config.DebugFlags.DistributionPad),
    LowHealthVignette = LogUtil.CreateLogger("Rebiotic Fixer|LowHealthVignette", Config.DebugFlags.LowHealthVignette),
    FlashlightFlicker = LogUtil.CreateLogger("Rebiotic Fixer|FlashlightFlicker", Config.DebugFlags.FlashlightFlicker),
    AutoJumpCrouch = LogUtil.CreateLogger("Rebiotic Fixer|AutoJumpCrouch", Config.DebugFlags.AutoJumpCrouch),
    VehicleLights = LogUtil.CreateLogger("Rebiotic Fixer|VehicleLights", Config.DebugFlags.VehicleLights),
    HideHotbarHotkeys = LogUtil.CreateLogger("Rebiotic Fixer|HideHotbarHotkeys", Config.DebugFlags.HideHotbarHotkeys),
    MinigameBarFix = LogUtil.CreateLogger("Rebiotic Fixer|MinigameBarFix", Config.DebugFlags.MinigameBarFix),
}

-- Initialize feature modules
MenuTweaks.Init(Config.MenuTweaks, Log.MenuTweaks)
FoodFix.Init(Config.FoodDisplayFix, Log.FoodFix)
CraftingPreviewFix.Init(Config.CraftingMenu, Log.CraftingMenu)
DistPadTweaks.Init(Config.DistributionPad, Log.DistPad)
LowHealthVignette.Init(Config.LowHealthVignette, Log.LowHealthVignette)
FlashlightFlicker.Init(Config.FlashlightFlicker, Log.FlashlightFlicker)
AutoJumpCrouch.Init(Config.AutoJumpCrouch, Log.AutoJumpCrouch)
VehicleLights.Init(Config.VehicleLights, Log.VehicleLights)
HideHotbarHotkeys.Init(Config.HideHotbarHotkeys, Log.HideHotbarHotkeys)
MinigameBarFix.Init(Config.MinigameBarFix, Log.MinigameBarFix)

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
    DistPadTweaksPrePlay = false,
    DistPadTweaks = false,
    FlashlightFlicker = false,
    AutoJumpCrouch = false,
    VehicleLights = false,
    HideHotbarHotkeys = false,
    MinigameBarFix = false,
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
        Log.General.Debug("%s registration failed (Blueprint not loaded yet). Will retry on next map load.", name)
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
    TryRegister("FlashlightFlicker", Config.FlashlightFlicker.Enabled, FlashlightFlicker.RegisterInPlayHooks)
    TryRegister("AutoJumpCrouch", Config.AutoJumpCrouch.Enabled, AutoJumpCrouch.RegisterInPlayHooks)
    TryRegister("VehicleLights", Config.VehicleLights.Enabled, VehicleLights.RegisterInPlayHooks)
    TryRegister("HideHotbarHotkeys", Config.HideHotbarHotkeys.Enabled, HideHotbarHotkeys.RegisterInPlayHooks)
    TryRegister("MinigameBarFix", Config.MinigameBarFix.Enabled, MinigameBarFix.RegisterInPlayHooks)
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
    if Config.FlashlightFlicker.Enabled then
        Log.General.Debug("InitGameStatePRE: Cleaning up flashlight flicker state")
        FlashlightFlicker.Cleanup()
    end
    if Config.DistributionPad.Indicator.Enabled then
        Log.General.Debug("InitGameStatePRE: Cleaning up DistPad cache and widgets")
        DistPadTweaks.Cleanup()
    end
    if Config.AutoJumpCrouch.Enabled then
        Log.General.Debug("InitGameStatePRE: Cleaning up AutoJumpCrouch state")
        AutoJumpCrouch.Cleanup()
    end
    if Config.VehicleLights.Enabled then
        Log.General.Debug("InitGameStatePRE: Cleaning up VehicleLights state")
        VehicleLights.Cleanup()
    end
    if Config.HideHotbarHotkeys.Enabled then
        Log.General.Debug("InitGameStatePRE: Cleaning up HideHotbarHotkeys cache")
        HideHotbarHotkeys.Cleanup()
    end
    if Config.MinigameBarFix.Enabled then
        Log.General.Debug("InitGameStatePRE: Cleaning up MinigameBarFix cache")
        MinigameBarFix.Cleanup()
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

        -- PrePlay hooks - register early (before gameplay map loads)
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
