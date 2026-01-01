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
-- MENU TWEAKS HOOKS
-- Skip LAN Hosting Delay
-- ============================================================

if Config.MenuTweaks.SkipLANHostingDelay then
    local okConstruct, errConstruct = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:Construct", function(Context)
            local popup = Context:get()
            if not popup:IsValid() then return end
            MenuTweaks.OnConstruct(popup)  -- → core/MenuTweaks.lua:OnConstruct()
        end)
    end)
    if not okConstruct then
        Log.MenuTweaks.Error("Failed to register Construct hook: %s", tostring(errConstruct))
    end

    local okCountdown, errCountdown = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:CountdownInputDelay", function(Context)
            local popup = Context:get()
            if not popup:IsValid() then return end
            MenuTweaks.OnCountdownInputDelay(popup)  -- → core/MenuTweaks.lua:OnCountdownInputDelay()
        end)
    end)
    if not okCountdown then
        Log.MenuTweaks.Error("Failed to register CountdownInputDelay hook: %s", tostring(errCountdown))
    end

    local okUpdate, errUpdate = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:UpdateButtonWithDelayTime", function(Context, TextParam, OriginalTextParam)
            local popup = Context:get()
            if not popup:IsValid() then return end
            MenuTweaks.OnUpdateButtonWithDelayTime(popup, TextParam, OriginalTextParam)  -- → core/MenuTweaks.lua:OnUpdateButtonWithDelayTime()
        end)
    end)
    if not okUpdate then
        Log.MenuTweaks.Error("Failed to register UpdateButtonWithDelayTime hook: %s", tostring(errUpdate))
    end

    Log.MenuTweaks.Debug("LAN popup hooks registered")
end

-- ============================================================
-- CRAFTING MENU HOOKS
-- Brightness and Resolution fixes
-- ============================================================

if Config.CraftingMenu.Brightness.Enabled then
    local okBrightness, errBrightness = pcall(function()
        RegisterHook("/Game/Blueprints/Environment/Special/3D_ItemDisplay_BP.3D_ItemDisplay_BP_C:Set3DPreviewMesh", function(Context)
            local itemDisplay = Context:get()
            if not itemDisplay:IsValid() then return end
            CraftingPreviewFix.OnSet3DPreviewMesh(itemDisplay)  -- → core/CraftingPreviewFix.lua:OnSet3DPreviewMesh()
        end)
    end)
    if not okBrightness then
        Log.CraftingMenu.Error("Failed to register Set3DPreviewMesh hook: %s", tostring(errBrightness))
    else
        Log.CraftingMenu.Debug("Brightness hook registered (intensity: %.1f)", Config.CraftingMenu.Brightness.LightIntensity)
    end
end

local resolutionFixHook = false

if Config.CraftingMenu.Resolution.Enabled then
    RegisterInitGameStatePostHook(function()
        if resolutionFixHook then return end
        resolutionFixHook = true

        ExecuteInGameThread(function()
            CraftingPreviewFix.ApplyResolutionFix()  -- → core/CraftingPreviewFix.lua:ApplyResolutionFix()
        end)
    end)
    Log.CraftingMenu.Debug("Resolution fix registered (target: %d)", Config.CraftingMenu.Resolution.Resolution)
end

-- ============================================================
-- CONSOLIDATED DEPLOYED OBJECT HOOKS
-- Shared hook for FoodDisplayFix and DistributionPad.Range
-- ============================================================

local foodFixEnabled = Config.FoodDisplayFix.Enabled
local distPadRangeEnabled = Config.DistributionPad.Range.Enabled
local deployedObjectHooksRegistered = false

if foodFixEnabled or distPadRangeEnabled then
    -- Delay registration until Blueprint is loaded
    RegisterLoadMapPostHook(function()
        if deployedObjectHooksRegistered then return end

        -- Filter out main menu - only run in actual game world
        local gameState = UEHelpers.GetGameStateBase()
        if not gameState:IsValid() then
            return
        end

        local okGameState, gameStateClass = pcall(function()
            return gameState:GetClass():GetFName():ToString()
        end)

        if not okGameState or gameStateClass ~= "Abiotic_Survival_GameState_C" then
            return
        end

        deployedObjectHooksRegistered = true

        local okBeginPlay, errBeginPlay = pcall(function()
            RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveBeginPlay", function(Context)
                local obj = Context:get()
                if not obj:IsValid() then return end

                local okClass, className = pcall(function()
                    return obj:GetClass():GetFName():ToString()
                end)
                if not okClass then return end

                -- FoodDisplayFix: Handle Deployed_Food_* classes
                if foodFixEnabled and className:match("^Deployed_Food_") then
                    FoodFix.OnBeginPlay(obj)  -- → core/FoodFix.lua:OnBeginPlay()
                end

                -- DistributionPad.Range: Handle Deployed_DistributionPad_C
                if distPadRangeEnabled and className == "Deployed_DistributionPad_C" then
                    DistPadTweaks.OnDistPadBeginPlay(obj)  -- → core/DistributionPadTweaks.lua:OnDistPadBeginPlay()
                end
            end)
        end)

        if not okBeginPlay then
            Log.FoodFix.Error("Failed to register ReceiveBeginPlay hook: %s", tostring(errBeginPlay))
        else
            if foodFixEnabled then
                Log.FoodFix.Debug("Food display fix registered")
            end
            if distPadRangeEnabled then
                Log.DistPad.Debug("Distribution pad range registered (multiplier: %.2f)", Config.DistributionPad.Range.Multiplier)
            end
        end
    end)
end

-- ============================================================
-- DISTRIBUTION PAD INDICATOR HOOKS
-- Cache management and UI display
-- ============================================================

local distPadIndicatorHooksRegistered = false

if Config.DistributionPad.Indicator.Enabled then
    RegisterLoadMapPostHook(function()
        if distPadIndicatorHooksRegistered then return end

        -- Filter out main menu - only run in actual game world
        local gameState = UEHelpers.GetGameStateBase()
        if not gameState:IsValid() then
            Log.DistPad.Debug("Skipping indicator setup - no GameState found")
            return
        end

        local okClass, gameStateClass = pcall(function()
            return gameState:GetClass():GetFName():ToString()
        end)

        if not okClass or gameStateClass ~= "Abiotic_Survival_GameState_C" then
            Log.DistPad.Debug("Skipping indicator setup - not in game world (GameState: %s)", tostring(gameStateClass))
            return
        end

        distPadIndicatorHooksRegistered = true

        ExecuteWithDelay(1000, function()
            ExecuteInGameThread(function()
                Log.DistPad.Debug("Game map loaded, registering indicator hooks...")

                -- UpdateCompatibleContainers - fires when player walks on pad
                local okUpdate, errUpdate = pcall(function()
                    RegisterHook("/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C:UpdateCompatibleContainers", function(Context)
                        DistPadTweaks.OnUpdateCompatibleContainers(Context)  -- → core/DistributionPadTweaks.lua:OnUpdateCompatibleContainers()
                    end)
                end)
                if not okUpdate then
                    Log.DistPad.Debug("UpdateCompatibleContainers hook FAILED: %s", tostring(errUpdate))
                else
                    Log.DistPad.Debug("UpdateCompatibleContainers hook registered")
                end

                -- NotifyOnNewObject for new pads
                NotifyOnNewObject("/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C", function(pad)
                    DistPadTweaks.OnNewPadSpawned(pad)  -- → core/DistributionPadTweaks.lua:OnNewPadSpawned()
                end)
                Log.DistPad.Debug("NotifyOnNewObject for pads registered")

                -- ReceiveEndPlay - purge pad from cache when destroyed
                local okEndPlay, errEndPlay = pcall(function()
                    RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveEndPlay", function(Context, EndPlayReasonParam)
                        DistPadTweaks.OnReceiveEndPlay(Context)  -- → core/DistributionPadTweaks.lua:OnReceiveEndPlay()
                    end)
                end)
                if not okEndPlay then
                    Log.DistPad.Debug("ReceiveEndPlay hook FAILED: %s", tostring(errEndPlay))
                else
                    Log.DistPad.Debug("ReceiveEndPlay hook registered")
                end

                -- UpdateInteractionPrompts - show icon/text on containers
                local okPrompt, errPrompt = pcall(function()
                    RegisterHook("/Game/Blueprints/Widgets/W_PlayerHUD_InteractionPrompt.W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts",
                        function(Context, ShowPressInteract, ShowHoldInteract, ShowPressPackage, ShowHoldPackage,
                                 ObjectUnderConstruction, ConstructionPercent, RequiresPower, Radioactive,
                                 ShowDescription, ExtraNoteLines, HitActorParam, HitComponentParam, RequiresPlug)
                            DistPadTweaks.OnUpdateInteractionPrompts(Context, HitActorParam)  -- → core/DistributionPadTweaks.lua:OnUpdateInteractionPrompts()
                        end)
                end)
                if not okPrompt then
                    Log.DistPad.Debug("UpdateInteractionPrompts hook FAILED: %s", tostring(errPrompt))
                else
                    Log.DistPad.Debug("UpdateInteractionPrompts hook registered")
                end

                -- Container construction complete - refresh pads when new container built
                if Config.DistributionPad.Indicator.RefreshOnBuiltContainer then
                    local okConstruction, errConstruction = pcall(function()
                        RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:OnRep_ConstructionModeActive", function(Context)
                            DistPadTweaks.OnContainerConstructionComplete(Context)  -- → core/DistributionPadTweaks.lua:OnContainerConstructionComplete()
                        end)
                    end)
                    if not okConstruction then
                        Log.DistPad.Debug("OnRep_ConstructionModeActive hook FAILED: %s", tostring(errConstruction))
                    else
                        Log.DistPad.Debug("Container construction complete hook registered")
                    end
                end

                -- Initial cache refresh
                DistPadTweaks.RefreshCache()  -- → core/DistributionPadTweaks.lua:RefreshCache()

                Log.DistPad.Debug("DistPad Indicator setup complete")
            end)
        end)
    end)

    Log.DistPad.Debug("LoadMapPostHook registered for indicator setup")
end

-- ============================================================
-- LOW HEALTH VIGNETTE HOOKS
-- Red overlay when health drops below threshold
-- ============================================================

if Config.LowHealthVignette.Enabled then
    local okHook, errHook = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/W_PlayerHUD_Main.W_PlayerHUD_Main_C:UpdateHealth", function(Context)
            local hud = Context:get()
            if not hud:IsValid() then return end
            LowHealthVignette.OnUpdateHealth(hud)  -- → core/LowHealthVignette.lua:OnUpdateHealth()
        end)
    end)
    if not okHook then
        Log.LowHealthVignette.Error("Failed to register UpdateHealth hook: %s", tostring(errHook))
    else
        Log.LowHealthVignette.Debug("UpdateHealth hook registered (threshold: %.0f%%)", Config.LowHealthVignette.Threshold * 100)
    end
end

Log.General.Info("Mod loaded")
