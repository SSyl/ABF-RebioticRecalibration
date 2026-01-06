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
│ - DeployedObjects hook (parent class always loaded)                        │
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

-- Hook/feature registration tracking (managed by TryRegister and manual registration)
local HookRegistered = {
    -- Manual hook registration
    GameState = false,              -- Abiotic_Survival_GameState_C:ReceiveBeginPlay
    DistActive = false,             -- Deployed_DistributionPad_C:OnRep_DistributionActive

    -- Feature registration (managed by TryRegister)
    MenuTweaks = false,             -- W_MenuPopup_YesNo_C hooks (3 hooks)
    DeployedObjects = false,        -- AbioticDeployed_ParentBP_C:ReceiveBeginPlay
    CraftingMenuBrightness = false, -- 3D_ItemDisplay_BP_C:Set3DPreviewMesh
    CraftingMenuResolution = false, -- One-time render target resize
    LowHealthVignette = false,      -- W_PlayerHUD_Main_C:UpdateHealth
    DistPadIndicator = false,       -- DistPad indicator hooks (3 hooks)
}

-- Lifecycle event tracking
local GameStateHookFired = false

-- ============================================================
-- HOOK REGISTRATION FUNCTIONS
-- ============================================================

--- Registers a run-once feature if enabled and not already registered.
--- State is tracked internally in the HookRegistered table.
--- @param name string Feature/hook name (must be pre-defined in HookRegistered)
--- @param enabled boolean Whether registration should attempt
--- @param fn function Function that performs registration, returns true on success
--- @param delay number|nil Optional delay in milliseconds before attempting registration
local function TryRegister(name, enabled, fn, delay)
    -- Validate name exists in HookRegistered (catches typos)
    if HookRegistered[name] == nil then
        error(string.format("TryRegister: '%s' is not defined in HookRegistered table", name))
    end

    if not enabled or HookRegistered[name] then return end

    if delay and delay > 0 then
        ExecuteWithDelay(delay, function()
            if fn() then
                HookRegistered[name] = true
            else
                Log.General.Debug("%s registration failed. Retrying on next level change...", name)
            end
        end)
    else
        if fn() then
            HookRegistered[name] = true
        else
            Log.General.Debug("%s registration failed. Retrying on next level change...", name)
        end
    end
end

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

-- Called when first pad's BeginPlay fires - Blueprint guaranteed to be loaded
local function RegisterDistActiveHook()
    return TryRegister("DistActive", true, function()
        local ok, err = pcall(function()
            RegisterHook(
                "/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C:OnRep_DistributionActive",
                function(Context)
                    local pad = Context:get()
                    if not pad:IsValid() then return end

                    local okActive, isActive = pcall(function() return pad.DistributionActive end)

                    -- Only sync when someone steps ON the pad (true), not when stepping OFF (false)
                    if okActive and isActive then
                        Log.DistPad.Debug("OnRep_DistributionActive: DistributionActive = true, syncing pad")
                        DistPadTweaks.SyncPad(pad)
                    end
                end)
        end)

        if ok then
            Log.DistPad.Debug("OnRep_DistributionActive hook registered successfully")
        else
            Log.DistPad.Error("OnRep_DistributionActive hook registration failed: %s", tostring(err))
        end
        return ok
    end, 250) -- 250ms delay for Blueprint to fully initialize
end

local function HookDistPadIndicator()
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

            -- DistPad indicator detection (for newly placed or replicating pads)
            if Config.DistributionPad.Indicator.Enabled and className == "Deployed_DistributionPad_C" then
                -- First pad triggers OnRep_DistributionActive hook registration (Blueprint now loaded)
                local DistActiveHook = not HookRegistered.DistActive and RegisterDistActiveHook or nil
                DistPadTweaks.OnPadBeginPlay(obj, DistActiveHook)
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

    -- MenuTweaks and DeployedObjects registered earlier in PollForMissedHook
    TryRegister("DistPadIndicator", Config.DistributionPad.Indicator.Enabled and isGameplayMap, HookDistPadIndicator)
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

        -- MenuTweaks registers here (main menu) - LAN popup appears before gameplay
        TryRegister("MenuTweaks", Config.MenuTweaks.SkipLANHostingDelay, HookMenuTweaks)

        -- DeployedObjects hook can register early - parent class always loaded
        TryRegister("DeployedObjects",
            Config.FoodDisplayFix.Enabled or Config.DistributionPad.Range.Enabled or Config.DistributionPad.Indicator.Enabled,
            HookDeployedObjects)

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
