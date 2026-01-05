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

HOOK REGISTRATION STRATEGY:

We register hooks at different lifecycle stages depending on what they need:

┌─────────────────────────────────────────────────────────────────────────────┐
│ InitGameStatePreHook (before GameState initializes)                         │
│ - Cleanup widgets from previous map (vignette, DistPad indicators)         │
└─────────────────────────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ PollForMissedHook - when GameStateBase exists (main menu or gameplay)       │
│ - MenuTweaks hooks (LAN hosting popup appears on MainMenu)                 │
└─────────────────────────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ Abiotic_Survival_GameState_C:ReceiveBeginPlay (gameplay maps only)          │
│ - CraftingMenu brightness hook (needs game objects to exist)               │
│ - CraftingMenu resolution fix (needs render target to exist)               │
│ - LowHealthVignette hook registration                                      │
│ - FoodFix hooks (need deployed objects to exist)                           │
│ - DistPad hooks (need pads and containers to exist)                        │
│ - DistPad cache refresh (every gameplay map)                               │
└─────────────────────────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ PollForMissedHook (race condition fallback - Abiotic Factor specific)       │
│ - Polls every 100ms until GameStateBase exists                             │
│ - Registers ReceiveBeginPlay hook + MenuTweaks once GameStateBase found    │
│ - Invokes OnGameState if already in gameplay (missed the hook)             │
└─────────────────────────────────────────────────────────────────────────────┘

NOTE: We use RegisterHook on Abiotic_Survival_GameState_C:ReceiveBeginPlay
instead of RegisterInitGameStatePostHook because ReceiveBeginPlay fires
when clients join a server, while InitGameStatePostHook only fires on
main menu loads.

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

-- Hook tracking flags
local GameStateHookFired = false
local hookRegistered = false

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

local OnRepDistributionActiveHooked = false

local function TryRegisterOnRepDistributionActiveHook(attempts)
    if OnRepDistributionActiveHooked then return true end
    attempts = attempts or 0

    Log.DistPad.Debug("TryRegisterOnRepDistributionActiveHook: attempt %d", attempts + 1)

    local ok, err = pcall(function()
        RegisterHook(
            "/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C:OnRep_DistributionActive",
            function(Context)
                local pad = Context:get()
                if not pad:IsValid() then return end

                local okActive, isActive = pcall(function() return pad.DistributionActive end)

                -- Only sync when someone steps ON the pad (true), not when stepping OFF (false)
                if okActive and isActive then
                    Log.DistPad.Debug("OnRep_DistributionActive: DistributionActive = true, calling UpdateCompatibleContainers")
                    pcall(function() pad:UpdateCompatibleContainers() end)
                end
            end)
    end)

    if ok then
        OnRepDistributionActiveHooked = true
        Log.DistPad.Debug("OnRep_DistributionActive hook registered successfully (attempt %d)", attempts + 1)
        return true
    else
        Log.DistPad.Debug("OnRep_DistributionActive hook failed: %s", tostring(err))
    end

    -- Retry with delay (500ms intervals, max 20 attempts = 10 seconds)
    if attempts < 20 then
        ExecuteWithDelay(500, function()
            ExecuteInGameThread(function()
                TryRegisterOnRepDistributionActiveHook(attempts + 1)
            end)
        end)
    else
        Log.DistPad.Debug("OnRep_DistributionActive hook registration gave up after %d attempts", attempts + 1)
    end

    return false
end

local function TryRegisterUpdateCompatibleContainersHook(attempts)
    if DistPadTweaks.UpdateCompatibleContainersHooked then return true end
    attempts = attempts or 0

    Log.DistPad.Debug("TryRegisterUpdateCompatibleContainersHook: attempt %d", attempts + 1)

    local ok, err = pcall(function()
        RegisterHook(
        "/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C:UpdateCompatibleContainers",
            function(Context)
                DistPadTweaks.OnUpdateCompatibleContainers(Context)
            end)
    end)

    if ok then
        DistPadTweaks.UpdateCompatibleContainersHooked = true
        Log.DistPad.Debug("UpdateCompatibleContainers hook registered successfully (attempt %d)", attempts + 1)
        return true
    else
        Log.DistPad.Debug("UpdateCompatibleContainers hook failed: %s", tostring(err))
    end

    -- Retry with delay (500ms intervals, max 20 attempts = 10 seconds)
    if attempts < 20 then
        ExecuteWithDelay(500, function()
            ExecuteInGameThread(function()
                TryRegisterUpdateCompatibleContainersHook(attempts + 1)
            end)
        end)
    else
        Log.DistPad.Debug("UpdateCompatibleContainers hook registration gave up after %d attempts", attempts + 1)
    end

    return false
end

local function HookDistPadIndicator()
    -- Try immediate registration (works on host), with retry loop for clients
    TryRegisterUpdateCompatibleContainersHook()
    TryRegisterOnRepDistributionActiveHook()

    -- NotifyOnNewObject fires when pads spawn/replicate - also try registration there
    NotifyOnNewObject("/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C",
        function(pad)
            Log.DistPad.Debug("NotifyOnNewObject fired for DistributionPad")
            TryRegisterUpdateCompatibleContainersHook()
            TryRegisterOnRepDistributionActiveHook()
            DistPadTweaks.OnNewPadSpawned(pad)
        end)

    local ok, err = pcall(function()
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
                    DistPadTweaks.OnConstructionComplete(Context)
                end)
        end)
        if not ok then
            Log.DistPad.Error("OnRep_ConstructionModeActive hook failed: %s", tostring(err))
            return false
        end
    end

    return true
end

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

local function OnGameState(world)
    GameStateHookFired = true

    if not world:IsValid() then return end

    -- RUN-ONCE features (with automatic retry on failure)
    TryRegister("CraftingMenuBrightness", Config.CraftingMenu.Brightness.Enabled, HookCraftingMenuBrightness)
    TryRegister("CraftingMenuResolution", Config.CraftingMenu.Resolution.Enabled, CraftingPreviewFix.ApplyResolutionFix)
    TryRegister("LowHealthVignette", Config.LowHealthVignette.Enabled, HookLowHealthVignette)

    -- MAP-SPECIFIC LOGIC
    local okFullName, fullName = pcall(function() return world:GetFullName() end)
    local mapName = okFullName and fullName and fullName:match("/Game/Maps/([^%.]+)")
    if not mapName then
        return
    end

    local isGameplayMap = not mapName:match("MainMenu")

    -- MenuTweaks is registered earlier in PollForMissedHook (needs main menu)
    TryRegister("DeployedObjects", Config.FoodDisplayFix.Enabled or Config.DistributionPad.Range.Enabled, HookDeployedObjects)
    TryRegister("DistPadIndicator", Config.DistributionPad.Indicator.Enabled and isGameplayMap, HookDistPadIndicator)

    -- Cache refresh on every gameplay map load
    if Config.DistributionPad.Indicator.Enabled and isGameplayMap then
        DistPadTweaks.RefreshCache()
    end
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
        if not hookRegistered then
            local ok = pcall(RegisterHook,
                "/Game/Blueprints/Meta/Abiotic_Survival_GameState.Abiotic_Survival_GameState_C:ReceiveBeginPlay",
                OnGameStateHook
            )
            if ok then
                hookRegistered = true
                Log.General.Debug("Hook registered")
            end

            -- MenuTweaks registers here (main menu) - LAN popup appears before gameplay
            TryRegister("MenuTweaks", Config.MenuTweaks.SkipLANHostingDelay, HookMenuTweaks)
        end

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
