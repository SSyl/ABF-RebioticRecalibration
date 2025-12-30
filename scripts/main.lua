print("=== [QoL Tweaks] MOD LOADING ===\n")

local LogUtil = require("LogUtil")
local ConfigUtil = require("ConfigUtil")

-- ============================================================
-- CONFIG
-- ============================================================

local UserConfig = require("../config")
local Config = ConfigUtil.ValidateConfig(UserConfig, LogUtil.CreateLogger("QoL Tweaks (Config)", UserConfig))
local Log = LogUtil.CreateLogger("QoL Tweaks", Config)

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
        Log.Debug("LAN popup fix disabled")
        return
    end

    local okConstruct, errConstruct = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:Construct", function(Context)
            local popup = Context:get()
            if not popup:IsValid() then return end

            if ShouldSkipDelay(popup) then
                Log.Debug("LAN hosting popup detected - skipping delay")

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
        Log.Error("Failed to register Construct hook: %s", tostring(errConstruct))
    else
        Log.Debug("LAN popup Construct hook registered")
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
        Log.Error("Failed to register CountdownInputDelay hook: %s", tostring(errCountdown))
    else
        Log.Debug("LAN popup CountdownInputDelay hook registered")
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
                    Log.Debug("Cached original text for %s: '%s'", widgetName, originalStr)
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
        Log.Error("Failed to register UpdateButtonWithDelayTime hook: %s", tostring(errUpdate))
    else
        Log.Debug("LAN popup UpdateButtonWithDelayTime hook registered")
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
        Log.Debug("Failed to get MaxDurability")
        return false
    end

    local okCurrent, currentDur = pcall(function()
        return deployable.CurrentDurability
    end)

    if okCurrent and currentDur == maxDur then
        Log.Debug("Deployable already at max durability")
        return false
    end

    Log.Debug("Resetting durability from %s to %s", tostring(currentDur), tostring(maxDur))

    pcall(function()
        local changeableData = deployable.ChangeableData
        if changeableData then
            local maxItemDur = changeableData.MaxItemDurability_6_F5D5F0D64D4D6050CCCDE4869785012B
            if maxItemDur then
                changeableData.CurrentItemDurability_4_24B4D0E64E496B43FB8D3CA2B9D161C8 = maxItemDur
                Log.Debug("Fixed ChangeableData.CurrentItemDurability to %s", tostring(maxItemDur))
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
        Log.Debug("Food deployable fix disabled")
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

            Log.Debug("Food deployable ReceiveBeginPlay: %s", className)

            local okAuth, hasAuthority = pcall(function()
                return deployable:HasAuthority()
            end)

            if okAuth and hasAuthority then
                local okLoading, isLoading = pcall(function()
                    return deployable.IsCurrentlyLoadingFromSave
                end)

                if okLoading and isLoading then
                    if not fixExistingOnLoad then
                        Log.Debug("Skipping - loading from save (FixExistingOnLoad disabled)")
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
                Log.Debug("Client visual-only mode: hiding broken texture locally")
                pcall(function()
                    deployable.CurrentDurability = deployable.MaxDurability
                end)
            end
        end)
    end)

    if not ok then
        Log.Error("Failed to register food deployable fix: %s", tostring(err))
    else
        Log.Debug("Food deployable fix registered")
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
        Log.Debug("Crafting preview brightness disabled")
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
        Log.Error("Failed to register crafting preview brightness: %s", tostring(err))
    else
        Log.Debug("Crafting preview brightness registered (intensity: %.1f)", lightIntensity)
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
        Log.Debug("Crafting preview resolution disabled")
        return
    end

    local configResolution = config.Resolution or 1024
    local targetResolution = RoundToPowerOfTwo(configResolution)

    if configResolution ~= targetResolution then
        Log.Debug("Rounded resolution from %d to nearest power of 2: %d", configResolution, targetResolution)
    end

    RegisterInitGameStatePostHook(function(ContextParam)
        ExecuteInGameThread(function()
            local renderTarget = StaticFindObject(
                "/Game/Blueprints/Environment/Special/3DItem_RenderTarget.3DItem_RenderTarget"
            )
            local kismetRenderLib = GetKismetRenderingLibrary()

            if not renderTarget:IsValid() then
                Log.Error("Failed to find 3DItem_RenderTarget")
                return
            end

            if not kismetRenderLib:IsValid() then
                Log.Error("Failed to find KismetRenderingLibrary")
                return
            end

            local okSize, currentX, currentY = pcall(function()
                return renderTarget.SizeX, renderTarget.SizeY
            end)

            if okSize then
                Log.Debug("Current render target size: %dx%d", currentX, currentY)

                if currentX == targetResolution and currentY == targetResolution then
                    Log.Debug("Render target already at target resolution, skipping resize")
                    return
                end
            end

            local okResize, errResize = pcall(function()
                kismetRenderLib:ResizeRenderTarget2D(renderTarget, targetResolution, targetResolution)
            end)

            if okResize then
                Log.Debug("Resized crafting preview render target to %dx%d", targetResolution, targetResolution)
            else
                Log.Error("Failed to resize render target: %s", tostring(errResize))
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
        Log.Debug("Distribution pad distance disabled")
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
        Log.Error("Failed to register distribution pad distance: %s", tostring(err))
    else
        Log.Debug("Distribution pad distance registered (%.0f -> %.0f units)", defaultRadius, newRadius)
    end
end

-- ============================================================
-- INITIALIZATION
-- ============================================================

ExecuteWithDelay(2500, function()
    Log.Debug("Registering hooks...")

    RegisterLANPopupFix()
    RegisterFoodDeployableFix()
    RegisterCraftingPreviewBrightness()
    RegisterCraftingPreviewResolution()
    RegisterDistributionPadDistance()

    Log.Debug("Hook registration complete")
end)

Log.Debug("Mod loaded")
