--[[
============================================================================
CraftingPreviewFix - Fix Dark/Blurry 3D Item Preview
============================================================================

Fixes dark and blurry 3D preview in crafting menu. Disables auto-exposure
(sets to AEM_Manual), increases light intensity, and resizes render target
from 512x512 to configurable resolution (default 1024, must be power of 2).

HOOKS:
- 3D_ItemDisplay_BP_C:Set3DPreviewMesh (brightness, fires on item change)
- ApplyResolutionFix() called once at startup

PERFORMANCE: Brightness hook fires on preview item change, resolution once at startup
]]

local HookUtil = require("utils/HookUtil")

-- ============================================================
-- MODULE METADATA
-- ============================================================

local Module = {
    name = "CraftingPreviewFix",
    configKey = "CraftingMenu",
    debugKey = "CraftingMenu",

    schema = {
        { path = "Brightness.Enabled", type = "boolean", default = true },
        { path = "Brightness.LightIntensity", type = "number", default = 10.0, min = 0.1 },
        { path = "Resolution.Enabled", type = "boolean", default = true },
        { path = "Resolution.Resolution", type = "number", default = 1024, min = 1, max = 8192 },
    },

    -- Complex: Two independent features with separate enable conditions
    -- main.lua will check isEnabled which returns true if either is enabled
    hookPoint = "Gameplay",

    -- Enable if EITHER brightness or resolution is enabled
    isEnabled = function(cfg) return cfg.Brightness.Enabled or cfg.Resolution.Enabled end,
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

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
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    local anyEnabled = Config.Brightness.Enabled or Config.Resolution.Enabled
    local status = anyEnabled and "Enabled" or "Disabled"
    Log.Info("CraftingPreviewFix - %s", status)
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function Module.RegisterHooks()
    local success = true

    -- Register brightness hook if enabled
    if Config.Brightness.Enabled then
        success = HookUtil.Register(
            "/Game/Blueprints/Environment/Special/3D_ItemDisplay_BP.3D_ItemDisplay_BP_C:Set3DPreviewMesh",
            Module.OnSet3DPreviewMesh,
            Log
        ) and success
    end

    -- Apply resolution fix once if enabled
    if Config.Resolution.Enabled then
        success = Module.ApplyResolutionFix() and success
    end

    return success
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnSet3DPreviewMesh(itemDisplay)
    local lightIntensity = Config.Brightness.LightIntensity

    local sceneCapture = itemDisplay.Item_RenderTarget
    if sceneCapture:IsValid() then
        sceneCapture.PostProcessSettings.bOverride_AutoExposureMethod = true
        sceneCapture.PostProcessSettings.AutoExposureMethod = 2
    end

    local pointLight = itemDisplay.PointLight
    if pointLight:IsValid() then
        pointLight:SetIntensity(lightIntensity)
    end

    local pointLight1 = itemDisplay.PointLight1
    if pointLight1:IsValid() then
        pointLight1:SetIntensity(lightIntensity)
    end

    local pointLight2 = itemDisplay.PointLight2
    if pointLight2:IsValid() then
        pointLight2:SetIntensity(lightIntensity / 2)
    end
end

function Module.ApplyResolutionFix()
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

    local currentX, currentY = renderTarget.SizeX, renderTarget.SizeY
    Log.Debug("Current render target size: %dx%d", currentX or 0, currentY or 0)

    if currentX == targetResolution and currentY == targetResolution then
        Log.Debug("Render target already at target resolution, skipping resize")
        return true
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

return Module
