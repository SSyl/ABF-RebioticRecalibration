local CraftingPreviewFix = {}

-- Module state (set during Init)
local Config = nil
local Log = nil

-- Cached references
local KismetRenderingLibraryCache = nil

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

local function GetKismetRenderingLibrary()
    if KismetRenderingLibraryCache and KismetRenderingLibraryCache:IsValid() then
        return KismetRenderingLibraryCache
    end

    KismetRenderingLibraryCache = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
    return KismetRenderingLibraryCache
end

local function RoundToPowerOfTwo(value)
    value = math.floor(value)
    local power = math.floor(math.log(value) / math.log(2) + 0.5)
    return math.floor(2 ^ power)
end

-- ============================================================
-- CORE LOGIC
-- ============================================================

function CraftingPreviewFix.Init(config, log)
    Config = config
    Log = log
    Log.Debug("CraftingPreviewFix initialized")
end

-- Called from RegisterHook("/Game/Blueprints/Environment/Special/3D_ItemDisplay_BP.3D_ItemDisplay_BP_C:Set3DPreviewMesh") in main.lua
function CraftingPreviewFix.OnSet3DPreviewMesh(itemDisplay)
    if not itemDisplay:IsValid() then return end

    local lightIntensity = Config.CraftingPreviewBrightness.LightIntensity

    -- Disable auto-exposure so light changes actually take effect
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

-- Called from RegisterInitGameStatePostHook in main.lua
function CraftingPreviewFix.ApplyResolutionFix()
    local configResolution = Config.CraftingPreviewResolution.Resolution
    local targetResolution = RoundToPowerOfTwo(configResolution)

    if configResolution ~= targetResolution then
        Log.Debug("Rounded resolution from %d to nearest power of 2: %d", configResolution, targetResolution)
    end

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
end

return CraftingPreviewFix
