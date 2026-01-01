print("=== [QoL Tweaks] MOD LOADING ===\n")

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
    General = LogUtil.CreateLogger("QoL Tweaks", false),  -- Always enabled for mod-level messages
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
            local popup = Context:get()
            if not popup:IsValid() then return end
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
    Log.CraftingMenu.Debug("Registering brightness hook...")

    local okBrightness, errBrightness = pcall(function()
        RegisterHook("/Game/Blueprints/Environment/Special/3D_ItemDisplay_BP.3D_ItemDisplay_BP_C:Set3DPreviewMesh", function(Context)
            local itemDisplay = Context:get()
            if not itemDisplay:IsValid() then return end
            CraftingPreviewFix.OnSet3DPreviewMesh(itemDisplay)
        end)
    end)
    if not okBrightness then
        Log.CraftingMenu.Error("Failed to register Set3DPreviewMesh hook: %s", tostring(errBrightness))
    end
end

local function RegisterCraftingMenuResolutionFix()
    Log.CraftingMenu.Debug("Applying resolution fix...")
    CraftingPreviewFix.ApplyResolutionFix()
end

local function RegisterLowHealthVignetteHooks(ContextParam)
    Log.LowHealthVignette.Debug("Checking vignette setup...")

    -- Filter out main menu - check if we're in an actual game world
    local GameMode = ContextParam:get()
    if not GameMode:IsValid() then
        Log.LowHealthVignette.Debug("GameMode invalid, skipping vignette")
        return
    end

    local World = GameMode:GetWorld()
    if not World:IsValid() then
        Log.LowHealthVignette.Debug("World invalid, skipping vignette")
        return
    end

    local okMap, mapName = pcall(function()
        return World:GetFName():ToString()
    end)

    if not okMap then
        Log.LowHealthVignette.Debug("Failed to get map name, skipping vignette")
        return
    end

    Log.LowHealthVignette.Debug("Map detected: %s", mapName)

    -- Skip main menu maps
    if mapName == "Persistent_FrontEnd" or mapName == "MainMenu" then
        Log.LowHealthVignette.Debug("Skipping vignette setup - in main menu")
        return
    end

    Log.LowHealthVignette.Debug("Setting up vignette...")

    -- Pre-create vignette widget
    local hud = FindFirstOf("W_PlayerHUD_Main_C")
    if hud:IsValid() then
        LowHealthVignette.CreateWidget(hud)
    else
        Log.LowHealthVignette.Debug("HUD not found during setup, will lazy-create on first use")
    end

    -- Register UpdateHealth hook
    local okHook, errHook = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/W_PlayerHUD_Main.W_PlayerHUD_Main_C:UpdateHealth", function(Context)
            local hud = Context:get()
            if not hud:IsValid() then return end
            LowHealthVignette.OnUpdateHealth(hud)
        end)
    end)
    if not okHook then
        Log.LowHealthVignette.Error("Failed to register UpdateHealth hook: %s", tostring(errHook))
    end
end

-- ============================================================
-- IMMEDIATE REGISTRATION WITH RETRY
-- MenuTweaks needs to register immediately for main menu
-- ============================================================

local menuTweaksHooksRegistered = false

if Config.MenuTweaks.SkipLANHostingDelay then
    local function TryRegisterMenuTweaks()
        if menuTweaksHooksRegistered then return true end

        local success, result = pcall(RegisterMenuTweaksHooks)
        if success and result == true then
            menuTweaksHooksRegistered = true
            Log.MenuTweaks.Debug("MenuTweaks hooks registered successfully")
            return true
        else
            return false
        end
    end

    if not TryRegisterMenuTweaks() then
        local retryCount = 0
        local function retry()
            retryCount = retryCount + 1

            if retryCount > 10 then
                Log.MenuTweaks.Error("Failed to register MenuTweaks hooks after 10 retry attempts")
                return
            end

            Log.MenuTweaks.Debug("Retry attempt %d/10", retryCount)

            if TryRegisterMenuTweaks() then
                return
            end

            ExecuteWithDelay(2000, retry)
        end
        retry()
    end
end

-- ============================================================
-- CONSOLIDATED INITGAMESTATE HOOKS
-- Single hook for all features requiring InitGameStatePostHook
-- ============================================================

local initGameStateHookRegistered = false

RegisterInitGameStatePostHook(function(ContextParam)
    Log.General.Debug("InitGameStatePostHook fired")

    if initGameStateHookRegistered then
        Log.General.Debug("InitGameStatePostHook already processed, skipping")
        return
    end
    initGameStateHookRegistered = true

    if Config.CraftingMenu.Brightness.Enabled then
        RegisterCraftingMenuBrightnessHook()
    end

    if Config.CraftingMenu.Resolution.Enabled then
        RegisterCraftingMenuResolutionFix()
    end

    if Config.LowHealthVignette.Enabled then
        RegisterLowHealthVignetteHooks(ContextParam)
    end
end)

-- ============================================================
-- LOADMAP HOOK REGISTRATION FUNCTIONS
-- ============================================================

local function RegisterDeployedObjectHooks()
    local okBeginPlay, errBeginPlay = pcall(function()
        RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveBeginPlay", function(Context)
            local obj = Context:get()
            if not obj:IsValid() then return end

            local okClass, className = pcall(function()
                return obj:GetClass():GetFName():ToString()
            end)
            if not okClass then return end

            if Config.FoodDisplayFix.Enabled and className:match("^Deployed_Food_") then
                FoodFix.OnBeginPlay(obj)
            end

            if Config.DistributionPad.Range.Enabled and className == "Deployed_DistributionPad_C" then
                DistPadTweaks.OnDistPadBeginPlay(obj)
            end
        end)
    end)

    if not okBeginPlay then
        Log.General.Error("Failed to register ReceiveBeginPlay hook: %s", tostring(errBeginPlay))
    end
end

local function RegisterDistPadIndicatorHooks()
    Log.DistPad.Debug("Registering DistPad indicator hooks...")

    local okUpdate, errUpdate = pcall(function()
        RegisterHook("/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C:UpdateCompatibleContainers", function(Context)
            DistPadTweaks.OnUpdateCompatibleContainers(Context)
        end)
    end)
    if not okUpdate then
        Log.DistPad.Debug("UpdateCompatibleContainers hook FAILED: %s", tostring(errUpdate))
    end

    NotifyOnNewObject("/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C", function(pad)
        DistPadTweaks.OnNewPadSpawned(pad)
    end)

    local okEndPlay, errEndPlay = pcall(function()
        RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveEndPlay", function(Context)
            DistPadTweaks.OnReceiveEndPlay(Context)
        end)
    end)
    if not okEndPlay then
        Log.DistPad.Debug("ReceiveEndPlay hook FAILED: %s", tostring(errEndPlay))
    end

    local okPrompt, errPrompt = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/W_PlayerHUD_InteractionPrompt.W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts",
            function(Context, HitActorParam)
                DistPadTweaks.OnUpdateInteractionPrompts(Context, HitActorParam)
            end)
    end)
    if not okPrompt then
        Log.DistPad.Debug("UpdateInteractionPrompts hook FAILED: %s", tostring(errPrompt))
    end

    if Config.DistributionPad.Indicator.RefreshOnBuiltContainer then
        local okConstruction, errConstruction = pcall(function()
            RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:OnRep_ConstructionModeActive", function(Context)
                DistPadTweaks.OnContainerConstructionComplete(Context)
            end)
        end)
        if not okConstruction then
            Log.DistPad.Debug("OnRep_ConstructionModeActive hook FAILED: %s", tostring(errConstruction))
        end
    end

    DistPadTweaks.RefreshCache()

    Log.DistPad.Debug("DistPad Indicator setup complete")
end

-- ============================================================
-- CONSOLIDATED LOADMAP HOOKS
-- Single hook for all features requiring LoadMapPostHook
-- ============================================================

local loadMapHookRegistered = false

RegisterLoadMapPostHook(function()
    Log.General.Debug("LoadMapPostHook fired")

    local gameState = UEHelpers.GetGameStateBase()
    local inGameWorld = false

    if gameState:IsValid() then
        local okGameState, gameStateClass = pcall(function()
            return gameState:GetClass():GetFName():ToString()
        end)

        print(gameStateClass)

        inGameWorld = okGameState and gameStateClass == "Abiotic_Survival_GameState_C"
    end

    -- Clean up vignette state when returning to main menu
    if not inGameWorld and Config.LowHealthVignette.Enabled then
        Log.General.Debug("Returning to main menu, cleaning up vignette")
        LowHealthVignette.Cleanup()
    end

    if loadMapHookRegistered then
        Log.General.Debug("LoadMapPostHook already processed, skipping")
        return
    end

    -- Skip if not in game world (already checked above)
    if not inGameWorld then
        Log.General.Debug("Not in game world, skipping LoadMapPostHook")
        return
    end

    loadMapHookRegistered = true
    Log.General.Debug("LoadMapPostHook passed GameState filter")

    if Config.FoodDisplayFix.Enabled or Config.DistributionPad.Range.Enabled then
        RegisterDeployedObjectHooks()
    end

    if Config.DistributionPad.Indicator.Enabled then
        RegisterDistPadIndicatorHooks()
    end
end)

Log.General.Info("Mod loaded")
