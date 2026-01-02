--[[
============================================================================
CraftingPreviewFix - Fix Dark/Blurry 3D Item Preview in Crafting Menu
============================================================================

PURPOSE:
The 3D item preview in the crafting menu has two issues:
1. DARK: Items appear too dark due to low light intensity + auto-exposure
2. BLURRY: Low render target resolution (vanilla is 512x512)

HOW WE FIX IT:

Brightness Fix:
- The 3D preview uses a SceneCaptureComponent2D (Item_RenderTarget) to render
  the item to a texture, which is then displayed in the UI.
- Vanilla auto-exposure causes inconsistent brightness. We disable it by
  setting AutoExposureMethod to AEM_Manual (value 2).
- Then we set PointLight and PointLight1 to configured intensity (default 10,
  vs vanilla 4), and PointLight2 to half for subtle rim lighting.

Resolution Fix:
- The render target texture (3DItem_RenderTarget) is 512x512 in vanilla.
- We use KismetRenderingLibrary:ResizeRenderTarget2D to resize it to the
  configured resolution (default 1024, must be power of 2).
- This is a one-time fix applied at InitGameStatePostHook.

HOOKS (registered in main.lua):
- 3D_ItemDisplay_BP_C:Set3DPreviewMesh → OnSet3DPreviewMesh() [brightness]
- InitGameStatePostHook → ApplyResolutionFix() [resolution, one-time]

PERFORMANCE:
- Brightness: Fires when preview item changes (user scrolls crafting menu)
- Resolution: Fires once at game start
Both are infrequent, no per-frame overhead.
]]

local CraftingPreviewFix = {}

-- Module state (set during Init)
local Config = nil
local Log = nil

-- Cached reference to KismetRenderingLibrary (used for render target resize)
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

    local lightIntensity = Config.Brightness.LightIntensity

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
-- Returns true on success, false on failure (allows retry)
function CraftingPreviewFix.ApplyResolutionFix()
    local configResolution = Config.Resolution.Resolution
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
        return false
    end

    if not kismetRenderLib:IsValid() then
        Log.Error("Failed to find KismetRenderingLibrary")
        return false
    end

    local okSize, currentX, currentY = pcall(function()
        return renderTarget.SizeX, renderTarget.SizeY
    end)

    if okSize then
        Log.Debug("Current render target size: %dx%d", currentX, currentY)

        if currentX == targetResolution and currentY == targetResolution then
            Log.Debug("Render target already at target resolution, skipping resize")
            return true  -- Already correct = success
        end
    end

    local okResize, errResize = pcall(function()
        kismetRenderLib:ResizeRenderTarget2D(renderTarget, targetResolution, targetResolution)
    end)

    if okResize then
        Log.Debug("Resized crafting preview render target to %dx%d", targetResolution, targetResolution)
        return true
    else
        Log.Error("Failed to resize render target: %s", tostring(errResize))
        return false
    end
end

return CraftingPreviewFix
