print("=== [QoL Tweaks] MOD LOADING ===\n")

local LogUtil = require("LogUtil")
local ConfigUtil = require("ConfigUtil")

-- ============================================================
-- CONFIG
-- ============================================================

local UserConfig = require("../config")
local Config = ConfigUtil.ValidateConfig(UserConfig, LogUtil.CreateLogger("QoL Tweaks (Config)", UserConfig))

-- Feature-specific loggers (each checks its own DebugFlags entry)
-- Usage: Log.FeatureName.Debug("message")
local Log = {
    MenuTweaks = LogUtil.CreateLogger("QoL Tweaks|MenuTweaks", Config, "MenuTweaks"),
    FoodFix = LogUtil.CreateLogger("QoL Tweaks|FoodFix", Config, "FoodDeployableFix"),
    CraftingPreview = LogUtil.CreateLogger("QoL Tweaks|CraftingPreview", Config, "CraftingPreview"),
    DistPad = LogUtil.CreateLogger("QoL Tweaks|DistPad", Config, "DistributionPad"),
}

-- ============================================================
-- FEATURE: Skip LAN Hosting Delay
-- ============================================================

local function EnablePopupButtons(popup)
    local okYes, yesButton = pcall(function()
        return popup.Button_Yes
    end)
    if okYes and yesButton:IsValid() then
        pcall(function()
            yesButton:SetIsEnabled(true)
        end)
    end

    local okNo, noButton = pcall(function()
        return popup.Button_No
    end)
    if okNo and noButton:IsValid() then
        pcall(function()
            noButton:SetIsEnabled(true)
        end)
    end
end

local function ShouldSkipDelay(popup)
    if not popup:IsValid() then return false end

    local ok, title = pcall(function()
        return popup.Text_Title:ToString()
    end)

    return ok and title == "Hosting a LAN Server"
end

-- Cache for original button text values (populated on first UpdateButtonWithDelayTime call)
local LANPopupOriginalText = {}

local function RegisterLANPopupFix()
    if not Config.MenuTweaks.SkipLANHostingDelay then
        Log.MenuTweaks.Debug("LAN popup fix disabled")
        return
    end

    local okConstruct, errConstruct = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:Construct", function(Context)
            local popup = Context:get()
            if not popup:IsValid() then return end

            if ShouldSkipDelay(popup) then
                Log.MenuTweaks.Debug("LAN hosting popup detected - skipping delay")

                pcall(function()
                    popup.DelayBeforeAllowingInput = 0
                    popup.CloseBlockedByDelay = false
                    popup.DelayTimeLeft = 0
                end)

                EnablePopupButtons(popup)
            end
        end)
    end)

    if not okConstruct then
        Log.MenuTweaks.Error("Failed to register Construct hook: %s", tostring(errConstruct))
    else
        Log.MenuTweaks.Debug("LAN popup Construct hook registered")
    end

    local okCountdown, errCountdown = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:CountdownInputDelay", function(Context)
            local popup = Context:get()
            if not popup:IsValid() then return end

            if ShouldSkipDelay(popup) then
                pcall(function()
                    popup.DelayTimeLeft = 0
                    popup.CloseBlockedByDelay = false
                end)

                EnablePopupButtons(popup)
            end
        end)
    end)

    if not okCountdown then
        Log.MenuTweaks.Error("Failed to register CountdownInputDelay hook: %s", tostring(errCountdown))
    else
        Log.MenuTweaks.Debug("LAN popup CountdownInputDelay hook registered")
    end

    local okUpdate, errUpdate = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:UpdateButtonWithDelayTime", function(Context, TextParam, OriginalTextParam)
            local popup = Context:get()
            if not popup:IsValid() then return end

            if ShouldSkipDelay(popup) then
                -- Function already executed and formatted text with countdown
                -- Override it back to the original text
                local okText, textWidget = pcall(function()
                    return TextParam:get()
                end)
                if not okText or not textWidget:IsValid() then return end

                -- Get widget name to use as cache key
                local okName, widgetName = pcall(function()
                    return textWidget:GetFName():ToString()
                end)
                if not okName then return end

                -- Get original text from parameter
                local okOriginal, originalText = pcall(function()
                    return OriginalTextParam:get()
                end)

                local originalStr = ""
                if okOriginal and originalText then
                    local okStr, str = pcall(function()
                        return originalText:ToString()
                    end)
                    if okStr then originalStr = str end
                end

                -- Cache original text STRING on first call (when it's not empty)
                -- We cache the string, not the FText object, because FText may become invalid
                if originalStr ~= "" and not LANPopupOriginalText[widgetName] then
                    LANPopupOriginalText[widgetName] = originalStr
                    Log.MenuTweaks.Debug("Cached original text for %s: '%s'", widgetName, originalStr)
                end

                -- Use cached string to create fresh FText and set it
                local cachedStr = LANPopupOriginalText[widgetName]
                if cachedStr then
                    pcall(function()
                        textWidget:SetText(FText(cachedStr))
                    end)
                end
            end
        end)
    end)

    if not okUpdate then
        Log.MenuTweaks.Error("Failed to register UpdateButtonWithDelayTime hook: %s", tostring(errUpdate))
    else
        Log.MenuTweaks.Debug("LAN popup UpdateButtonWithDelayTime hook registered")
    end
end

-- ============================================================
-- FEATURE: Fix Food Deployable Broken Texture
-- ============================================================

local function ResetDeployedDurability(deployable)
    if not deployable:IsValid() then return false end

    local okMax, maxDur = pcall(function()
        return deployable.MaxDurability
    end)
    if not okMax or maxDur == nil then
        Log.FoodFix.Debug("Failed to get MaxDurability")
        return false
    end

    local okCurrent, currentDur = pcall(function()
        return deployable.CurrentDurability
    end)

    if okCurrent and currentDur == maxDur then
        Log.FoodFix.Debug("Deployable already at max durability")
        return false
    end

    Log.FoodFix.Debug("Resetting durability from %s to %s", tostring(currentDur), tostring(maxDur))

    pcall(function()
        local changeableData = deployable.ChangeableData
        if changeableData then
            local maxItemDur = changeableData.MaxItemDurability_6_F5D5F0D64D4D6050CCCDE4869785012B
            if maxItemDur then
                changeableData.CurrentItemDurability_4_24B4D0E64E496B43FB8D3CA2B9D161C8 = maxItemDur
                Log.FoodFix.Debug("Fixed ChangeableData.CurrentItemDurability to %s", tostring(maxItemDur))
            end
        end
    end)

    pcall(function()
        deployable.CurrentDurability = maxDur
    end)

    return true
end

local function RegisterFoodDeployableFix()
    local foodConfig = Config.FoodDeployableFix
    if not foodConfig.Enabled then
        Log.FoodFix.Debug("Food deployable fix disabled")
        return
    end

    local clientVisualOnly = foodConfig.ClientSideVisualOnly
    local fixExistingOnLoad = foodConfig.FixExistingOnLoad

    local ok, err = pcall(function()
        RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveBeginPlay", function(Context)
            local deployable = Context:get()
            if not deployable:IsValid() then return end

            local okClass, className = pcall(function()
                return deployable:GetClass():GetFName():ToString()
            end)
            if not okClass or not className:match("^Deployed_Food_") then return end

            Log.FoodFix.Debug("Food deployable ReceiveBeginPlay: %s", className)

            local okAuth, hasAuthority = pcall(function()
                return deployable:HasAuthority()
            end)

            if okAuth and hasAuthority then
                local okLoading, isLoading = pcall(function()
                    return deployable.IsCurrentlyLoadingFromSave
                end)

                if okLoading and isLoading then
                    if not fixExistingOnLoad then
                        Log.FoodFix.Debug("Skipping - loading from save (FixExistingOnLoad disabled)")
                        return
                    end

                    -- Poll until save loading completes
                    local function WaitForLoad(n)
                        if n > 20 then return end
                        ExecuteWithDelay(100, function()
                            ExecuteInGameThread(function()
                                if not deployable:IsValid() then return end
                                local _, stillLoading = pcall(function() return deployable.IsCurrentlyLoadingFromSave end)
                                if stillLoading then WaitForLoad(n + 1) else ResetDeployedDurability(deployable) end
                            end)
                        end)
                    end
                    WaitForLoad(0)
                else
                    ResetDeployedDurability(deployable)
                end
            elseif clientVisualOnly then
                Log.FoodFix.Debug("Client visual-only mode: hiding broken texture locally")
                pcall(function()
                    deployable.CurrentDurability = deployable.MaxDurability
                end)
            end
        end)
    end)

    if not ok then
        Log.FoodFix.Error("Failed to register food deployable fix: %s", tostring(err))
    else
        Log.FoodFix.Debug("Food deployable fix registered")
    end
end

-- ============================================================
-- FEATURE: Brighten Crafting Menu 3D Preview
-- ============================================================

local function ApplyPreviewBrightness(itemDisplay, lightIntensity)
    if not itemDisplay:IsValid() then return end

    -- Disable auto-exposure so light changes actually take effect
    -- (Auto-exposure compensates for brightness changes, defeating the purpose)
    local okCapture, sceneCapture = pcall(function()
        return itemDisplay.Item_RenderTarget
    end)

    if okCapture and sceneCapture:IsValid() then
        pcall(function()
            sceneCapture.PostProcessSettings.bOverride_AutoExposureMethod = true
            sceneCapture.PostProcessSettings.AutoExposureMethod = 2  -- AEM_Manual
        end)
    end

    -- Set light intensities directly
    local okLight, pointLight = pcall(function() return itemDisplay.PointLight end)
    if okLight and pointLight:IsValid() then
        pointLight:SetIntensity(lightIntensity)
    end

    local okLight1, pointLight1 = pcall(function() return itemDisplay.PointLight1 end)
    if okLight1 and pointLight1:IsValid() then
        pointLight1:SetIntensity(lightIntensity)
    end

    -- Back light uses half intensity for subtle rim lighting
    local okLight2, pointLight2 = pcall(function() return itemDisplay.PointLight2 end)
    if okLight2 and pointLight2:IsValid() then
        pointLight2:SetIntensity(lightIntensity / 2)
    end
end

local function RegisterCraftingPreviewBrightness()
    local previewConfig = Config.CraftingPreviewBrightness
    if not previewConfig.Enabled then
        Log.CraftingPreview.Debug("Crafting preview brightness disabled")
        return
    end

    local lightIntensity = previewConfig.LightIntensity or 4.0

    local ok, err = pcall(function()
        RegisterHook("/Game/Blueprints/Environment/Special/3D_ItemDisplay_BP.3D_ItemDisplay_BP_C:Set3DPreviewMesh", function(Context)
            local itemDisplay = Context:get()
            if not itemDisplay:IsValid() then return end

            ApplyPreviewBrightness(itemDisplay, lightIntensity)
        end)
    end)

    if not ok then
        Log.CraftingPreview.Error("Failed to register crafting preview brightness: %s", tostring(err))
    else
        Log.CraftingPreview.Debug("Crafting preview brightness registered (intensity: %.1f)", lightIntensity)
    end
end

-- ============================================================
-- FEATURE: Increase Crafting Preview Resolution
-- ============================================================

local KismetRenderingLibraryCache = nil

local function GetKismetRenderingLibrary()
    if KismetRenderingLibraryCache and KismetRenderingLibraryCache:IsValid() then
        return KismetRenderingLibraryCache
    end

    KismetRenderingLibraryCache = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
    return KismetRenderingLibraryCache
end

local function RoundToPowerOfTwo(value)
    -- ConfigUtil already validated type and bounds (1-8192)
    -- Just round to nearest power of 2
    value = math.floor(value)
    local power = math.floor(math.log(value) / math.log(2) + 0.5)
    return math.floor(2 ^ power)
end

local function RegisterCraftingPreviewResolution()
    local config = Config.CraftingPreviewResolution
    if not config.Enabled then
        Log.CraftingPreview.Debug("Crafting preview resolution disabled")
        return
    end

    local configResolution = config.Resolution or 1024
    local targetResolution = RoundToPowerOfTwo(configResolution)

    if configResolution ~= targetResolution then
        Log.CraftingPreview.Debug("Rounded resolution from %d to nearest power of 2: %d", configResolution, targetResolution)
    end

    RegisterInitGameStatePostHook(function(ContextParam)
        ExecuteInGameThread(function()
            local renderTarget = StaticFindObject(
                "/Game/Blueprints/Environment/Special/3DItem_RenderTarget.3DItem_RenderTarget"
            )
            local kismetRenderLib = GetKismetRenderingLibrary()

            if not renderTarget:IsValid() then
                Log.CraftingPreview.Error("Failed to find 3DItem_RenderTarget")
                return
            end

            if not kismetRenderLib:IsValid() then
                Log.CraftingPreview.Error("Failed to find KismetRenderingLibrary")
                return
            end

            local okSize, currentX, currentY = pcall(function()
                return renderTarget.SizeX, renderTarget.SizeY
            end)

            if okSize then
                Log.CraftingPreview.Debug("Current render target size: %dx%d", currentX, currentY)

                if currentX == targetResolution and currentY == targetResolution then
                    Log.CraftingPreview.Debug("Render target already at target resolution, skipping resize")
                    return
                end
            end

            local okResize, errResize = pcall(function()
                kismetRenderLib:ResizeRenderTarget2D(renderTarget, targetResolution, targetResolution)
            end)

            if okResize then
                Log.CraftingPreview.Debug("Resized crafting preview render target to %dx%d", targetResolution, targetResolution)
            else
                Log.CraftingPreview.Error("Failed to resize render target: %s", tostring(errResize))
            end
        end)
    end)
end

-- ============================================================
-- FEATURE: Distribution Pad Distance
-- ============================================================

local function RegisterDistributionPadDistance()
    local config = Config.DistributionPadDistance
    if not config.Enabled then
        Log.DistPad.Debug("Distance feature disabled")
        return
    end

    local multiplier = config.DistanceMultiplier or 1.25
    local defaultRadius = 1000
    local newRadius = defaultRadius * multiplier

    local ok, err = pcall(function()
        RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveBeginPlay", function(Context)
            local obj = Context:get()
            if not obj:IsValid() then return end

            -- Filter for distribution pads only (parent hook fires for all deployed objects)
            local okClass, className = pcall(function()
                return obj:GetClass():GetFName():ToString()
            end)
            if not okClass or className ~= "Deployed_DistributionPad_C" then return end

            local okSphere, sphere = pcall(function()
                return obj.ContainerOverlapSphere
            end)

            if okSphere and sphere:IsValid() then
                pcall(function()
                    sphere:SetSphereRadius(newRadius, true)
                end)
            end
        end)
    end)

    if not ok then
        Log.DistPad.Error("Failed to register distance feature: %s", tostring(err))
    else
        Log.DistPad.Debug("Distance feature registered (%.0f -> %.0f units)", defaultRadius, newRadius)
    end
end

-- ============================================================
-- Distribution Pad Container Indicator
-- ============================================================

-- Cache: inventory addresses that are in ANY pad's range
local DistPadCache = {
    inventories = {},      -- [inventoryAddress] = true
    lastRefresh = 0,       -- os.time() of last refresh
    maxAge = 900,          -- 15 minutes in seconds
}

local function RefreshDistPadCache()
    DistPadCache.inventories = {}
    DistPadCache.lastRefresh = os.time()

    local allPads = FindAllOf("Deployed_DistributionPad_C")
    if not allPads then
        Log.DistPad.Debug("RefreshCache: No distribution pads found")
        return
    end

    local padCount = 0
    local invCount = 0

    for _, pad in pairs(allPads) do
        if pad:IsValid() then
            padCount = padCount + 1

            -- Force the pad to update its container list (queries physics overlap)
            pcall(function()
                pad:UpdateCompatibleContainers()
            end)

            -- Now read the populated AdditionalInventories
            local okInvs, inventories = pcall(function()
                return pad.AdditionalInventories
            end)

            if okInvs and inventories then
                local count = #inventories
                for i = 1, count do
                    local inv = inventories[i]
                    if inv:IsValid() then
                        local addr = inv:GetAddress()
                        DistPadCache.inventories[addr] = true
                        invCount = invCount + 1
                    end
                end
            end
        end
    end

    Log.DistPad.Debug("RefreshCache: %d pads, %d inventories cached", padCount, invCount)
end

-- ============================================================
-- Distribution Pad Indicator: Interaction Prompt Hook
-- ============================================================

local function RegisterInteractionPromptHook()
    -- Cache: remember last actor we processed to avoid repeated lookups
    local lastActorAddr = nil
    local lastActorInRange = false

    local okHook, errHook = pcall(function()
        RegisterHook(
            "/Game/Blueprints/Widgets/W_PlayerHUD_InteractionPrompt.W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts",
            function(Context, ShowPressInteract, ShowHoldInteract, ShowPressPackage, ShowHoldPackage,
                     ObjectUnderConstruction, ConstructionPercent, RequiresPower, Radioactive,
                     ShowDescription, ExtraNoteLines, HitActorParam, HitComponentParam, RequiresPlug)

                local widget = Context:get()
                if not widget:IsValid() then return end

                -- Get HitActor from parameter
                local okHitActor, hitActor = pcall(function()
                    return HitActorParam:get()
                end)

                if not okHitActor or not hitActor or not hitActor:IsValid() then
                    lastActorAddr = nil
                    lastActorInRange = false
                    return
                end

                local actorAddr = hitActor:GetAddress()

                -- Fast path: same actor as last frame
                if actorAddr == lastActorAddr then
                    if not lastActorInRange then return end
                    -- Still in range - just append indicator (vanilla resets text each frame)
                    local okText, textBlock = pcall(function() return widget.InteractionObjectName end)
                    if okText and textBlock and textBlock:IsValid() then
                        local okGet, currentText = pcall(function() return textBlock:GetText():ToString() end)
                        if okGet and currentText and not currentText:match("%[DistPad%]") then
                            pcall(function() textBlock:SetText(FText(currentText .. " [DistPad]")) end)
                        end
                    end
                    return
                end

                -- New actor - do full check
                lastActorAddr = actorAddr
                lastActorInRange = false

                -- Check if it's a container (has ContainerInventory)
                local okInv, containerInv = pcall(function()
                    return hitActor.ContainerInventory
                end)

                if not okInv or not containerInv or not containerInv:IsValid() then
                    return
                end

                -- Check cache
                local invAddr = containerInv:GetAddress()
                local inRange = DistPadCache.inventories[invAddr] == true

                if not inRange then return end

                lastActorInRange = true

                -- Get InteractionObjectName TextBlock and append indicator
                local okText, textBlock = pcall(function()
                    return widget.InteractionObjectName
                end)

                if not okText or not textBlock or not textBlock:IsValid() then
                    return
                end

                local okGetText, currentText = pcall(function()
                    return textBlock:GetText():ToString()
                end)

                if not okGetText or not currentText then return end

                if not currentText:match("%[DistPad%]") then
                    pcall(function()
                        textBlock:SetText(FText(currentText .. " [DistPad]"))
                    end)
                end
            end
        )
    end)

    if not okHook then
        Log.DistPad.Debug("UpdateInteractionPrompts hook FAILED: %s", tostring(errHook))
        return false
    end

    Log.DistPad.Debug("UpdateInteractionPrompts hook registered")
    return true
end


local function RegisterDistPadIndicatorV2()
    if not Config.DistributionPadIndicator.Enabled then
        Log.DistPad.Debug("DistPad Indicator disabled")
        return
    end

    Log.DistPad.Debug("Setting up DistPad Indicator...")

    -- Register hooks after map loads (Blueprint needs to be available)
    RegisterLoadMapPostHook(function()
        ExecuteWithDelay(1000, function()
            ExecuteInGameThread(function()
                Log.DistPad.Debug("Map loaded, registering hooks and refreshing cache...")
                RegisterInteractionPromptHook()
                RefreshDistPadCache()
            end)
        end)
    end)

    Log.DistPad.Debug("LoadMapPostHook registered")
end

-- ============================================================
-- INITIALIZATION
-- ============================================================

-- Features with internal lifecycle hooks - call immediately
RegisterCraftingPreviewResolution()  -- Uses RegisterInitGameStatePostHook
RegisterDistPadIndicatorV2()         -- Uses RegisterLoadMapPostHook

-- Features hooking Blueprint functions - use delayed registration
-- (Blueprints may not be loaded at mod init)
ExecuteWithDelay(2500, function()
    RegisterLANPopupFix()
    RegisterFoodDeployableFix()
    RegisterCraftingPreviewBrightness()
    RegisterDistributionPadDistance()
end)
