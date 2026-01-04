print("=== [QoL Tweaks] MOD LOADING ===\n")

--[[
============================================================================
QoL-Fixes-Tweaks - Main Entry Point
============================================================================

This file orchestrates all QoL features:
1. Loads and validates configuration from ../config.lua
2. Creates loggers for each feature module
3. Initializes feature modules with their config + logger
4. Registers hooks at appropriate lifecycle stages

HOOK REGISTRATION STRATEGY:

We register hooks at different lifecycle stages depending on what they need:

┌─────────────────────────────────────────────────────────────────────────────┐
│ InitGameStatePostHook (when GameState becomes valid) - FIRES FIRST          │
│ - CraftingMenu brightness hook (needs game objects to exist)               │
│ - CraftingMenu resolution fix (needs render target to exist)               │
│ - LowHealthVignette hook registration                                      │
└─────────────────────────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ LoadMapPostHook (when a map finishes loading) - FIRES SECOND                │
│ - MenuTweaks hooks (LAN hosting popup appears on MainMenu)                 │
│ - FoodFix hooks (need deployed objects to exist)                           │
│ - DistPad hooks (need pads and containers to exist)                        │
│ - Cleanup on menu return (via LoadMapPreHook)                              │
└─────────────────────────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ PollForMissedHooks (race condition fallback - Abiotic Factor specific)      │
│ - Invokes OnLoadMap/OnInitGameState if lifecycle hooks missed              │
│ - Polls every 100ms for up to 10 seconds                                   │
└─────────────────────────────────────────────────────────────────────────────┘

HOOK SUMMARY (for quick reference):

Feature              | Hook Target                                    | Fires When
---------------------|------------------------------------------------|---------------------------
MenuTweaks           | W_MenuPopup_YesNo_C:Construct                 | Popup created
MenuTweaks           | W_MenuPopup_YesNo_C:CountdownInputDelay       | Countdown tick
MenuTweaks           | W_MenuPopup_YesNo_C:UpdateButtonWithDelayTime | Button text update
CraftingPreviewFix   | 3D_ItemDisplay_BP_C:Set3DPreviewMesh          | Preview item changes
LowHealthVignette    | W_PlayerHUD_Main_C:UpdateHealth               | Health value changes
FoodFix              | AbioticDeployed_ParentBP_C:ReceiveBeginPlay   | Deployable spawns
DistPadTweaks (range)| AbioticDeployed_ParentBP_C:ReceiveBeginPlay   | Pad spawns (filtered)
DistPadTweaks        | Deployed_DistributionPad_C:UpdateCompatible...| Pad inventory updates
DistPadTweaks        | NotifyOnNewObject (DistributionPad)           | New pad created
DistPadTweaks        | AbioticDeployed_ParentBP_C:ReceiveEndPlay     | Deployable destroyed
DistPadTweaks        | W_PlayerHUD_InteractionPrompt_C:Update...     | PER-FRAME while aiming
DistPadTweaks        | AbioticDeployed_ParentBP_C:OnRep_Construction | Container built (optional)

]]

local UEHelpers = require("UEHelpers")
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
    { path = "DistributionPad.Indicator.Icon", type = "string", default = "icon_hackingdevice" },
    { path = "DistributionPad.Indicator.IconColor", type = "color", default = { R = 114, G = 242, B = 255 } },
    { path = "DistributionPad.Indicator.IconSize", type = "number", default = 32, min = 1 },
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
local configLogger = LogUtil.CreateLogger("QoL Tweaks (Config)", false)
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
    General = LogUtil.CreateLogger("QoL Tweaks", Config.DebugFlags.Misc),
    MenuTweaks = LogUtil.CreateLogger("QoL Tweaks|MenuTweaks", Config.DebugFlags.MenuTweaks),
    FoodFix = LogUtil.CreateLogger("QoL Tweaks|FoodFix", Config.DebugFlags.FoodDisplayFix),
    CraftingMenu = LogUtil.CreateLogger("QoL Tweaks|CraftingMenu", Config.DebugFlags.CraftingMenu),
    DistPad = LogUtil.CreateLogger("QoL Tweaks|DistPad", Config.DebugFlags.DistributionPad),
    LowHealthVignette = LogUtil.CreateLogger("QoL Tweaks|LowHealthVignette", Config.DebugFlags.LowHealthVignette),
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

-- Lifecycle hook tracking flags
local InitGameStatePostHookFired = false
local LoadMapPostHookFired = false

-- Run-once feature registration state (managed by TryRegister)
local Registered = {}

-- ============================================================
-- HOOK REGISTRATION FUNCTIONS
-- ============================================================

local function HookMenuTweaks()
    local ok, err = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:Construct", function(Context)
            local popup = Context:get()
            if not popup:IsValid() then return end
            MenuTweaks.OnConstruct(popup)
        end)
    end)
    if not ok then
        Log.MenuTweaks.Error("Construct hook failed: %s", tostring(err))
        return false
    end

    ok, err = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:CountdownInputDelay", function(Context)
            local popup = Context:get()
            if not popup:IsValid() then return end
            MenuTweaks.OnCountdownInputDelay(popup)
        end)
    end)
    if not ok then
        Log.MenuTweaks.Error("CountdownInputDelay hook failed: %s", tostring(err))
        return false
    end

    ok, err = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:UpdateButtonWithDelayTime", function(Context, TextParam, OriginalTextParam)
            local popup = Context:get()
            if not popup:IsValid() then return end
            MenuTweaks.OnUpdateButtonWithDelayTime(popup, TextParam, OriginalTextParam)
        end)
    end)
    if not ok then
        Log.MenuTweaks.Error("UpdateButtonWithDelayTime hook failed: %s", tostring(err))
        return false
    end

    return true
end

local function HookCraftingMenuBrightness()
    local ok, err = pcall(function()
        RegisterHook("/Game/Blueprints/Environment/Special/3D_ItemDisplay_BP.3D_ItemDisplay_BP_C:Set3DPreviewMesh", function(Context)
            local itemDisplay = Context:get()
            if not itemDisplay:IsValid() then return end
            CraftingPreviewFix.OnSet3DPreviewMesh(itemDisplay)
        end)
    end)
    if not ok then
        Log.CraftingMenu.Error("Set3DPreviewMesh hook failed: %s", tostring(err))
        return false
    end
    return true
end

local function HookLowHealthVignette()
    local ok, err = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/W_PlayerHUD_Main.W_PlayerHUD_Main_C:UpdateHealth", function(Context)
            local hud = Context:get()
            if not hud:IsValid() then return end
            LowHealthVignette.OnUpdateHealth(hud)
        end)
    end)
    if not ok then
        Log.LowHealthVignette.Error("UpdateHealth hook failed: %s", tostring(err))
        return false
    end
    return true
end

local function HookDistPadIndicator()
    local ok, err = pcall(function()
        RegisterHook(
        "/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C:UpdateCompatibleContainers",
            function(Context)
                DistPadTweaks.OnUpdateCompatibleContainers(Context)
            end)
    end)
    if not ok then
        Log.DistPad.Error("UpdateCompatibleContainers hook failed: %s", tostring(err))
        return false
    end

    NotifyOnNewObject("/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C",
        function(pad)
            DistPadTweaks.OnNewPadSpawned(pad)
        end)

    ok, err = pcall(function()
        RegisterHook(
        "/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveEndPlay",
            function(Context)
                DistPadTweaks.OnReceiveEndPlay(Context)
            end)
    end)
    if not ok then
        Log.DistPad.Error("ReceiveEndPlay hook failed: %s", tostring(err))
        return false
    end

    ok, err = pcall(function()
        RegisterHook(
            "/Game/Blueprints/Widgets/W_PlayerHUD_InteractionPrompt.W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts",
            function(Context, ShowPressInteract, ShowHoldInteract, ShowPressPackage, ShowHoldPackage,
                     ObjectUnderConstruction, ConstructionPercent, RequiresPower, Radioactive,
                     ShowDescription, ExtraNoteLines, HitActorParam, HitComponentParam, RequiresPlug)
                DistPadTweaks.OnUpdateInteractionPrompts(Context, HitActorParam)
            end)
    end)
    if not ok then
        Log.DistPad.Error("UpdateInteractionPrompts hook failed: %s", tostring(err))
        return false
    end

    if Config.DistributionPad.Indicator.RefreshOnBuiltContainer then
        ok, err = pcall(function()
            RegisterHook(
            "/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:OnRep_ConstructionModeActive",
                function(Context)
                    DistPadTweaks.OnContainerConstructionComplete(Context)
                end)
        end)
        if not ok then
            Log.DistPad.Error("OnRep_ConstructionModeActive hook failed: %s", tostring(err))
            return false
        end
    end

    return true
end


-- ============================================================
-- LIFECYCLE HANDLERS
-- ============================================================

--- Registers a run-once feature if enabled and not already registered.
--- State is tracked internally in the Registered table.
local function TryRegister(name, enabled, fn)
    if enabled and not Registered[name] then
        if fn() then
            Registered[name] = true
        else
            Log.General.Debug("%s registration failed. Retrying on next level change...", name)
        end
    end
end

local function OnInitGameState(gameMode)
    InitGameStatePostHookFired = true

    if not gameMode or not gameMode:IsValid() then
        Log.General.Debug("GameMode invalid, skipping InitGameState")
        return
    end

    local okWorld, world = pcall(function() return gameMode:GetWorld() end)
    if not okWorld or not world:IsValid() then
        Log.General.Debug("World invalid or inaccessible, skipping InitGameState")
        return
    end

    local okState, gameState = pcall(function() return world.GameState end)
    if not okState or not gameState:IsValid() then
        Log.General.Debug("GameState invalid or inaccessible, skipping InitGameState")
        return
    end

    -- RUN-ONCE features (with automatic retry on failure)
    TryRegister("CraftingMenuBrightness", Config.CraftingMenu.Brightness.Enabled, HookCraftingMenuBrightness)
    TryRegister("CraftingMenuResolution", Config.CraftingMenu.Resolution.Enabled, CraftingPreviewFix.ApplyResolutionFix)
    TryRegister("LowHealthVignette", Config.LowHealthVignette.Enabled, HookLowHealthVignette)
end

RegisterInitGameStatePostHook(function(ContextParam)
    local gameMode = ContextParam:get()
    if gameMode and gameMode:IsValid() then
        OnInitGameState(gameMode)
    end
end)

local function HookDeployedObjects()
    local ok, err = pcall(function()
        RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveBeginPlay", function(Context)
            local okObj, obj = pcall(function() return Context:get() end)
            if not okObj or not obj:IsValid() then return end

            local okClass, className = pcall(function()
                return obj:GetClass():GetFName():ToString()
            end)
            if not okClass or not className then return end

            if Config.FoodDisplayFix.Enabled and className:match("^Deployed_Food_") then
                FoodFix.OnBeginPlay(obj)
            end

            if Config.DistributionPad.Range.Enabled and className == "Deployed_DistributionPad_C" then
                DistPadTweaks.OnDistPadBeginPlay(obj)
            end
        end)
    end)

    if not ok then
        Log.General.Error("Failed to register ReceiveBeginPlay hook: %s", tostring(err))
        return false
    end

    return true
end

local function OnLoadMap(world)
    LoadMapPostHookFired = true

    if not world:IsValid() then
        return
    end

    local okFullName, fullName = pcall(function() return world:GetFullName() end)
    local mapName = okFullName and fullName and fullName:match("/Game/Maps/([^%.]+)")
    if not mapName then
        return
    end

    local isGameplayMap = not mapName:match("MainMenu")

    -- MenuTweaks registers on all maps (LAN hosting popup appears on MainMenu)
    TryRegister("MenuTweaks", Config.MenuTweaks.SkipLANHostingDelay, HookMenuTweaks)
    TryRegister("DeployedObjects", Config.FoodDisplayFix.Enabled or Config.DistributionPad.Range.Enabled, HookDeployedObjects)
    TryRegister("DistPadIndicator", Config.DistributionPad.Indicator.Enabled and isGameplayMap, HookDistPadIndicator)

    -- Cache refresh on every gameplay map load
    if Config.DistributionPad.Indicator.Enabled and isGameplayMap then
        DistPadTweaks.RefreshCache()
    end
end

-- Register PRE-hook for cleanup BEFORE map unloads (prevents widget access during transition)
RegisterLoadMapPreHook(function(Engine, World)
    -- Clean up widgets before old world is destroyed
    if Config.LowHealthVignette.Enabled then
        Log.General.Debug("LoadMapPRE: Cleaning up vignette")
        LowHealthVignette.Cleanup()
    end
    if Config.DistributionPad.Indicator.Enabled then
        Log.General.Debug("LoadMapPRE: Cleaning up DistPad cache and widgets")
        DistPadTweaks.Cleanup()
    end
end)

RegisterLoadMapPostHook(function(Engine, World)
    -- Extract actual UWorld from RemoteUnrealParam
    local world = World:get()
    if world and world:IsValid() then
        OnLoadMap(world)
    end
end)

-- ============================================================
-- RACE CONDITION FALLBACK -- SPECIAL ABIOTIC FACTOR CONDITION
-- ============================================================
-- If UE4SS initializes late and we miss lifecycle hooks, this fallback
-- ensures our wrapper functions still get called. You shouldn't ever have to do this.
-- HOWEVER, in Abiotic Factor, UE4SS isn't totally stable and there can be a race condition
-- where the game world is already loaded before UE4SS initializes, causing us to miss hooks.
-- This fallback checks if our hooks ran, and, if not, ready loaded, and if so, manually calls
-- Again, **DO NOT DO THIS FOR OTHER UE4SS GAMES. THIS IS A SPECIAL CASE FOR ABIOTIC FACTOR.**
-- ============================================================
local function PollForMissedHooks(attempts)
    attempts = attempts or 0

    ExecuteInGameThread(function()
        -- Fast path: all lifecycle hooks already fired
        if InitGameStatePostHookFired and LoadMapPostHookFired then
            return
        end

        local ExistingActor = FindFirstOf("Actor")
        if not ExistingActor:IsValid() then
            if attempts < 100 then
                ExecuteWithDelay(100, function()
                    PollForMissedHooks(attempts + 1)
                end)
            end
            return
        end

        -- World loaded - invoke missed lifecycle hooks
        if not InitGameStatePostHookFired then
            local GameMode = UEHelpers.GetGameModeBase()
            if GameMode:IsValid() then
                OnInitGameState(GameMode)
            end
        end

        if not LoadMapPostHookFired then
            local World = UEHelpers.GetWorld()
            if World:IsValid() then
                local okName, fullName = pcall(function() return World:GetFullName() end)
                if okName and fullName then
                    OnLoadMap(World)
                end
            end
        end

        -- Continue polling if not complete
        if not (InitGameStatePostHookFired and LoadMapPostHookFired) then
            if attempts < 100 then
                ExecuteWithDelay(100, function()
                    PollForMissedHooks(attempts + 1)
                end)
            else
                Log.General.Error("Fallback polling gave up after %d attempts", attempts + 1)
            end
        else
            Log.General.Debug("Fallback succeeded on attempt %d", attempts + 1)
        end
    end)
end

-- Start polling for missed hooks
PollForMissedHooks()

Log.General.Info("Mod loaded")
