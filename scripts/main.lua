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
        return false
    end

    return true
end

local function RegisterCraftingMenuResolutionFix()
    Log.CraftingMenu.Debug("Applying resolution fix...")
    return CraftingPreviewFix.ApplyResolutionFix()
end

local function RegisterLowHealthVignetteHooks(world)
    -- Filter out main menu maps
    local okMap, mapName = pcall(function()
        return world:GetFName():ToString()
    end)

    if not okMap then
        Log.LowHealthVignette.Debug("Failed to get map name, skipping vignette")
        return
    end

    Log.LowHealthVignette.Debug("Map detected: %s", mapName)

    if mapName == "Persistent_FrontEnd" or mapName == "MainMenu" then
        Log.LowHealthVignette.Debug("Skipping vignette setup - in main menu")
        return
    end

    Log.LowHealthVignette.Debug("Registering vignette hook...")

    -- Register UpdateHealth hook - widget will lazy-create on first health update
    local okHook, errHook = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/W_PlayerHUD_Main.W_PlayerHUD_Main_C:UpdateHealth", function(Context)
            local hud = Context:get()
            if not hud:IsValid() then return end
            LowHealthVignette.OnUpdateHealth(hud)
        end)
    end)
    if not okHook then
        Log.LowHealthVignette.Error("Failed to register UpdateHealth hook: %s", tostring(errHook))
    else
        Log.LowHealthVignette.Debug("UpdateHealth hook registered (widget will create on first update)")
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

-- Individual flags for run-once features (retry on failure)
local registeredCraftingMenuBrightness = nil
local registeredCraftingMenuResolution = nil

RegisterInitGameStatePostHook(function(ContextParam)
    Log.General.Debug("InitGameStatePostHook fired")

    -- Validate Context chain (trust but verify)
    local gameMode = ContextParam:get()
    if not gameMode or not gameMode:IsValid() then
        Log.General.Debug("Invalid GameMode in InitGameState hook, skipping")
        return
    end

    local world = gameMode:GetWorld()
    if not world or not world:IsValid() then
        Log.General.Debug("Invalid World in InitGameState hook, skipping")
        return
    end

    local gameState = world.GameState
    if not gameState or not gameState:IsValid() then
        Log.General.Debug("GameState is nil or invalid in InitGameState hook, skipping")
        return
    end

    Log.General.Debug("GameState validated: %s", gameState:GetFullName())

    -- RUN-ONCE features (with automatic retry on failure)
    if Config.CraftingMenu.Brightness.Enabled and not registeredCraftingMenuBrightness then
        local success = RegisterCraftingMenuBrightnessHook()
        if success then
            registeredCraftingMenuBrightness = true
            Log.General.Debug("CraftingMenuBrightness registered successfully")
        end
    end

    if Config.CraftingMenu.Resolution.Enabled and not registeredCraftingMenuResolution then
        local success = RegisterCraftingMenuResolutionFix()
        if success then
            registeredCraftingMenuResolution = true
            Log.General.Debug("CraftingMenuResolution registered successfully")
        end
    end

    -- RUN-ALWAYS features (execute on every map load)
    if Config.LowHealthVignette.Enabled then
        RegisterLowHealthVignetteHooks(world)
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
        return false
    end

    return true
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
        return false  -- Critical hook failed, retry later
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
        return false
    end

    local okPrompt, errPrompt = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/W_PlayerHUD_InteractionPrompt.W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts",
            function(Context, ShowPressInteract, ShowHoldInteract, ShowPressPackage, ShowHoldPackage,
                     ObjectUnderConstruction, ConstructionPercent, RequiresPower, Radioactive,
                     ShowDescription, ExtraNoteLines, HitActorParam, HitComponentParam, RequiresPlug)
                DistPadTweaks.OnUpdateInteractionPrompts(Context, HitActorParam)
            end)
    end)
    if not okPrompt then
        Log.DistPad.Debug("UpdateInteractionPrompts hook FAILED: %s", tostring(errPrompt))
        return false
    end

    if Config.DistributionPad.Indicator.RefreshOnBuiltContainer then
        local okConstruction, errConstruction = pcall(function()
            RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:OnRep_ConstructionModeActive", function(Context)
                DistPadTweaks.OnContainerConstructionComplete(Context)
            end)
        end)
        if not okConstruction then
            Log.DistPad.Debug("OnRep_ConstructionModeActive hook FAILED: %s", tostring(errConstruction))
            return false
        end
    end

    DistPadTweaks.RefreshCache()

    Log.DistPad.Debug("DistPad Indicator setup complete")
    return true
end

-- ============================================================
-- CONSOLIDATED LOADMAP HOOKS
-- Single hook for all features requiring LoadMapPostHook
-- ============================================================

-- Individual flags for run-once features (retry on failure)
local registeredDeployedObjectHooks = nil
local registeredDistPadIndicatorHooks = nil

RegisterLoadMapPostHook(function(Engine, World, URL)
    -- Validate URL parameter (catches parameter mismatches or early loading issues)
    if not URL:IsValid() then
        Log.General.Error("LoadMapPostHook: URL parameter is invalid - will retry on next map load")
        return
    end

    local okMap, mapName = pcall(function()
        return URL:GetMap()
    end)

    if not okMap then
        Log.General.Error("LoadMapPostHook: Failed to call GetMap() - %s", tostring(mapName))
        return
    end

    if not mapName or type(mapName) ~= "string" or mapName == "" then
        Log.General.Error("LoadMapPostHook: mapName is invalid (got %s: %s)", type(mapName), tostring(mapName))
        return
    end

    Log.General.Debug("LoadMapPostHook fired for map: %s", mapName)

    local inGameWorld = mapName ~= "MainMenu"

    -- Clean up vignette state when returning to main menu
    if not inGameWorld and Config.LowHealthVignette.Enabled then
        Log.General.Debug("Returning to main menu, cleaning up vignette")
        LowHealthVignette.Cleanup()
    end

    -- Skip if not in game world
    if not inGameWorld then
        Log.General.Debug("Not in game world (map: %s), skipping LoadMapPostHook", mapName)
        return
    end

    Log.General.Debug("LoadMapPostHook in gameplay map: %s", mapName)

    -- RUN-ONCE features (with automatic retry on failure)
    if (Config.FoodDisplayFix.Enabled or Config.DistributionPad.Range.Enabled) and not registeredDeployedObjectHooks then
        local success = RegisterDeployedObjectHooks()
        if success then
            registeredDeployedObjectHooks = true
            Log.General.Debug("DeployedObjectHooks registered successfully")
        end
    end

    if Config.DistributionPad.Indicator.Enabled and not registeredDistPadIndicatorHooks then
        local success = RegisterDistPadIndicatorHooks()
        if success then
            registeredDistPadIndicatorHooks = true
            Log.General.Debug("DistPadIndicatorHooks registered successfully")
        end
    end
end)

Log.General.Info("Mod loaded")
