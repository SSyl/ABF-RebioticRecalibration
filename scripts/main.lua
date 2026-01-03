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
│ InitGameStatePostHook (when GameState becomes valid)                        │
│ - CraftingMenu brightness hook (needs game objects to exist)               │
│ - CraftingMenu resolution fix (needs render target to exist)               │
│ - LowHealthVignette hook registration (filters out menu maps)              │
└─────────────────────────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ RegisterLoadMapPostHook (when a map finishes loading)                       │
│ - FoodFix hooks (need deployed objects to exist)                           │
│ - DistPad hooks (need pads and containers to exist)                        │
│ - Cleanup on menu return (clears stale state)                              │
└─────────────────────────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ PollForMissedHooks (race condition fallback - Abiotic Factor specific)      │
│ - MenuTweaks hooks (Blueprint loaded on-demand when popup is triggered)    │
│ - Simulates InitGameStatePostHook if missed                                │
│ - Simulates LoadMapPostHook if missed                                      │
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
    { path = "FoodDisplayFix.FixExistingOnLoad", type = "boolean", default = false },

    -- CraftingMenu.Brightness
    { path = "CraftingMenu.Brightness.Enabled", type = "boolean", default = true },
    { path = "CraftingMenu.Brightness.LightIntensity", type = "number", default = 10.0, min = 0.1 },

    -- CraftingMenu.Resolution
    { path = "CraftingMenu.Resolution.Enabled", type = "boolean", default = true },
    { path = "CraftingMenu.Resolution.Resolution", type = "number", default = 1024, min = 1, max = 8192 },

    -- DistributionPad.Indicator
    { path = "DistributionPad.Indicator.Enabled", type = "boolean", default = true },
    { path = "DistributionPad.Indicator.RefreshOnBuiltContainer", type = "boolean", default = false },
    { path = "DistributionPad.Indicator.IconEnabled", type = "boolean", default = true },
    { path = "DistributionPad.Indicator.Icon", type = "string", default = "icon_hackingdevice" },
    { path = "DistributionPad.Indicator.IconColor", type = "color", default = { R = 114, G = 242, B = 255 } },
    { path = "DistributionPad.Indicator.TextEnabled", type = "boolean", default = false },
    { path = "DistributionPad.Indicator.Text", type = "string", default = "[DistPad]" },

    -- DistributionPad.Range
    { path = "DistributionPad.Range.Enabled", type = "boolean", default = false },
    { path = "DistributionPad.Range.Multiplier", type = "number", default = 1.25, min = 0.1, max = 10.0 },

    -- LowHealthVignette
    { path = "LowHealthVignette.Enabled", type = "boolean", default = true },
    { path = "LowHealthVignette.Threshold", type = "number", default = 0.25, min = 0.01, max = 1.1 },
    { path = "LowHealthVignette.Color", type = "color", default = { R = 128, G = 0, B = 0, A = 0.3 } },
    { path = "LowHealthVignette.PulseEnabled", type = "boolean", default = true },

    -- DebugFlags
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
    General = LogUtil.CreateLogger("QoL Tweaks", true),  -- DEBUG ENABLED FOR DIAGNOSIS
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
-- INITGAMESTATE HOOK REGISTRATION FUNCTIONS
-- ============================================================

local function RegisterMenuTweaksHooks()
    Log.MenuTweaks.Debug("Registering MenuTweaks hooks...")

    local okConstruct, errConstruct = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:Construct", function(Context)
            Log.MenuTweaks.Debug("Construct hook fired")
            local popup = Context:get()
            if not popup:IsValid() then
                Log.MenuTweaks.Debug("Popup invalid after :get()")
                return
            end
            MenuTweaks.OnConstruct(popup)
        end)
    end)
    if not okConstruct then
        return false
    end

    local okCountdown, errCountdown = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:CountdownInputDelay", function(Context)
            local popup = Context:get()
            if not popup:IsValid() then return end
            MenuTweaks.OnCountdownInputDelay(popup)
        end)
    end)
    if not okCountdown then
        return false
    end

    local okUpdate, errUpdate = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:UpdateButtonWithDelayTime", function(Context, TextParam, OriginalTextParam)
            local popup = Context:get()
            if not popup:IsValid() then return end
            MenuTweaks.OnUpdateButtonWithDelayTime(popup, TextParam, OriginalTextParam)
        end)
    end)
    if not okUpdate then
        return false
    end

    Log.MenuTweaks.Debug("LAN popup hooks registered")
    return true
end

local function RegisterCraftingMenuBrightnessHook()
    local okBrightness, errBrightness = pcall(function()
        RegisterHook("/Game/Blueprints/Environment/Special/3D_ItemDisplay_BP.3D_ItemDisplay_BP_C:Set3DPreviewMesh", function(Context)
            local itemDisplay = Context:get()
            if not itemDisplay:IsValid() then return end
            CraftingPreviewFix.OnSet3DPreviewMesh(itemDisplay)
        end)
    end)

    if not okBrightness then
        Log.CraftingMenu.Error("Failed to register Set3DPreviewMesh hook: %s", tostring(errBrightness))
        return false
    end

    return true
end

local function RegisterCraftingMenuResolutionFix()
    return CraftingPreviewFix.ApplyResolutionFix()
end

local function RegisterLowHealthVignetteHooks()
    Log.LowHealthVignette.Debug("Attempting to register vignette hook...")

    -- Register UpdateHealth hook - widget will lazy-create on first health update
    local okHook, errHook = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/W_PlayerHUD_Main.W_PlayerHUD_Main_C:UpdateHealth", function(Context)
            local hud = Context:get()
            if not hud:IsValid() then return end
            LowHealthVignette.OnUpdateHealth(hud)
        end)
    end)

    if not okHook then
        Log.LowHealthVignette.Debug("Failed to register UpdateHealth hook (Blueprint may not exist yet): %s", tostring(errHook))
        return false
    end

    return true
end

-- ============================================================
-- CONSOLIDATED INITGAMESTATE HOOKS
-- Single hook for all features requiring InitGameStatePostHook
-- ============================================================

-- Lifecycle hook tracking flags
local InitGameStatePostHookFired = false
local LoadMapPostHookFired = false
local menuTweaksHooksRegistered = false

-- Run-once feature registration state (managed by TryRegister)
local Registered = {}

-- ============================================================
-- HOOK WRAPPER FUNCTIONS
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

    local okFullName, fullName = pcall(function()
        return gameState:GetFullName()
    end)

    if okFullName and fullName then
        Log.General.Debug("GameState validated: %s", fullName)
    end

    -- RUN-ONCE features (with automatic retry on failure)
    TryRegister("CraftingMenuBrightness", Config.CraftingMenu.Brightness.Enabled, RegisterCraftingMenuBrightnessHook)
    TryRegister("CraftingMenuResolution", Config.CraftingMenu.Resolution.Enabled, RegisterCraftingMenuResolutionFix)
    TryRegister("LowHealthVignette", Config.LowHealthVignette.Enabled, RegisterLowHealthVignetteHooks)
end

RegisterInitGameStatePostHook(function(ContextParam)
    local gameMode = ContextParam:get()
    if gameMode and gameMode:IsValid() then
        OnInitGameState(gameMode)
    end
end)

-- ============================================================
-- LOADMAP HOOK REGISTRATION FUNCTIONS
-- ============================================================

local function RegisterDeployedObjectHooks()
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

local function RegisterDistPadIndicatorHooks()
    local ok, err = pcall(function()
        RegisterHook("/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C:UpdateCompatibleContainers", function(Context)
            DistPadTweaks.OnUpdateCompatibleContainers(Context)
        end)
    end)
    if not ok then
        Log.DistPad.Error("UpdateCompatibleContainers hook failed: %s", tostring(err))
        return false
    end

    NotifyOnNewObject("/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C", function(pad)
        DistPadTweaks.OnNewPadSpawned(pad)
    end)

    ok, err = pcall(function()
        RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveEndPlay", function(Context)
            DistPadTweaks.OnReceiveEndPlay(Context)
        end)
    end)
    if not ok then
        Log.DistPad.Error("ReceiveEndPlay hook failed: %s", tostring(err))
        return false
    end

    ok, err = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/W_PlayerHUD_InteractionPrompt.W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts",
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
            RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:OnRep_ConstructionModeActive", function(Context)
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
-- CONSOLIDATED LOADMAP HOOKS
-- Single hook for all features requiring LoadMapPostHook
-- ============================================================

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

    TryRegister("DeployedObjectHooks", Config.FoodDisplayFix.Enabled or Config.DistributionPad.Range.Enabled, RegisterDeployedObjectHooks)
    TryRegister("DistPadIndicatorHooks", Config.DistributionPad.Indicator.Enabled and isGameplayMap, RegisterDistPadIndicatorHooks)

    -- Cache needs refresh on every gameplay map load (cleared in LoadMapPreHook)
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

Log.General.Info("Mod loaded")

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
    Log.General.Debug("Entered Fallback")
    attempts = attempts or 0

    ExecuteInGameThread(function()
        -- Fast path: if MenuTweaks registered and lifecycle hooks handled, nothing to do
        if menuTweaksHooksRegistered and InitGameStatePostHookFired and LoadMapPostHookFired then
            Log.General.Debug("Fallback check: All hooks registered, no fallback needed")
            return
        end

        Log.General.Debug("Fallback check: Polling for hooks (attempt %d)", attempts + 1)
        Log.General.Debug("InitGameState=%s, LoadMap=%s (MenuTweaks registers lazily)",
            tostring(InitGameStatePostHookFired), tostring(LoadMapPostHookFired))

        local ExistingActor = FindFirstOf("Actor")
        if not ExistingActor or not ExistingActor:IsValid() then
            -- No actors yet - either hooks will fire normally, or world hasn't loaded yet
            if attempts < 100 then  -- Poll for up to 10 seconds (100 * 100ms) for potato PCs
                Log.General.Debug("Fallback check: No actors found yet, polling again in 100ms")
                ExecuteWithDelay(100, function()
                    PollForMissedHooks(attempts + 1)
                end)
            else
                Log.General.Debug("Fallback check: Gave up after %d attempts, assuming hooks will fire normally", attempts + 1)
            end
            return
        end

        Log.General.Debug("Fallback check: Game world loaded (main menu or gameplay)")

        -- Attempt MenuTweaks registration if enabled and not already registered
        -- This retries automatically via the outer polling loop
        if Config.MenuTweaks.SkipLANHostingDelay and not menuTweaksHooksRegistered then
            Log.MenuTweaks.Debug("Fallback: Attempting MenuTweaks hooks registration...")
            local success, result = pcall(RegisterMenuTweaksHooks)
            if success and result == true then
                menuTweaksHooksRegistered = true
                Log.MenuTweaks.Debug("Fallback: MenuTweaks hooks registered successfully")
            else
                Log.MenuTweaks.Debug("Fallback: MenuTweaks registration failed (Blueprint not loaded yet), will retry")
            end
        end

        -- If InitGameState hook hasn't fired, manually invoke with real GameMode
        if not InitGameStatePostHookFired then
            Log.General.Debug("Fallback: Game already initialized, manually invoking OnInitGameState")

            local GameMode = UEHelpers.GetGameModeBase()
            if GameMode and GameMode:IsValid() then
                Log.General.Debug("Fallback: GameMode valid, invoking OnInitGameState")
                -- Call the actual function with real GameMode directly
                OnInitGameState(GameMode)
            else
                Log.General.Debug("Fallback: GameMode not yet valid")
            end
        end

        -- If LoadMap hook hasn't fired, manually invoke callback for current map
        if not LoadMapPostHookFired then
            Log.General.Debug("Fallback: World already loaded, manually invoking OnLoadMap")

            local World = UEHelpers.GetWorld()
            if World and World:IsValid() then
                local okFullName, fullName = pcall(function()
                    return World:GetFullName()
                end)

                if okFullName and fullName then
                    -- Pass World directly (already a UWorld from UEHelpers)
                    OnLoadMap(World)                
                else
                    Log.General.Debug("Fallback: Failed to get World:GetFullName()")
                end
            else
                Log.General.Debug("Fallback: World not valid yet")
            end
        end

        -- Continue polling if gameplay hooks not registered
        -- Note: MenuTweaks is excluded - it registers lazily when the Blueprint loads
        local gameplayHooksComplete = InitGameStatePostHookFired and LoadMapPostHookFired

        if not gameplayHooksComplete then
            if attempts < 100 then
                Log.General.Debug("Fallback check: Not all hooks ready, polling again in 100ms")
                ExecuteWithDelay(100, function()
                    PollForMissedHooks(attempts + 1)
                end)
            else
                Log.General.Error("Fallback check: Gave up after %d attempts. MenuTweaks Blueprint may not have loaded", attempts + 1)
            end
        else
            Log.General.Debug("Fallback check: All hooks registered successfully. Stopping polling")
        end
    end)
end

-- Start polling for missed hooks
PollForMissedHooks()
