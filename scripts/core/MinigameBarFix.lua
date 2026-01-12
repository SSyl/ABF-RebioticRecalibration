--[[
============================================================================
MinigameBarFix - Fix Success Zone Visual Size Mismatch
============================================================================

Fixes minigame success zones appearing smaller than hitbox. Uses SetRenderScale
to stretch zones (1.14x large, 1.25x small). Traverses WidgetTree to find Image
widgets by slot name (CanvasPanelSlot_9/10) due to name collision on direct access.

HOOKS:
- W_HUD_ContinenceMinigame_C:Tick (one-time fix per widget)
- W_HUD_WeightliftingMinigame_C:Tick (one-time fix per widget)

PERFORMANCE: Tick hook with address-based guard, only modifies once per widget instance
]]

local HookUtil = require("utils/HookUtil")
local MinigameBarFix = {}

-- Module state (set during Init)
local Config = nil
local Log = nil

-- Track which widgets we've modified (by address)
local modifiedWidgets = {}

-- Track widgets where we've verified scale persists (by address)
local verifiedWidgets = {}

-- Scale values for success zones
local LARGE_ZONE_SCALE = 1.14
local SMALL_ZONE_SCALE = 1.25

-- ============================================================
-- CORE LOGIC
-- ============================================================

function MinigameBarFix.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("MinigameBarFix - %s", status)
end

function MinigameBarFix.Cleanup()
    -- Clear widget caches on map transition
    modifiedWidgets = {}
    verifiedWidgets = {}
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function MinigameBarFix.RegisterInPlayHooks()
    ExecuteInGameThread(function()
        local okLoadContinence = pcall(function()
            LoadAsset("/Game/Blueprints/Widgets/HUD/W_HUD_ContinenceMinigame.W_HUD_ContinenceMinigame_C")
        end)

        if okLoadContinence then
            HookUtil.Register(
                "/Game/Blueprints/Widgets/HUD/W_HUD_ContinenceMinigame.W_HUD_ContinenceMinigame_C:Tick",
                MinigameBarFix.OnMinigameTick,
                Log
            )
        end

        local okLoadWeightlifting = pcall(function()
            LoadAsset("/Game/Blueprints/Widgets/HUD/W_HUD_WeightliftingMinigame.W_HUD_WeightliftingMinigame_C")
        end)

        if okLoadWeightlifting then
            HookUtil.Register(
                "/Game/Blueprints/Widgets/HUD/W_HUD_WeightliftingMinigame.W_HUD_WeightliftingMinigame_C:Tick",
                MinigameBarFix.OnMinigameTick,
                Log
            )
        end
    end)

    return true
end

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

-- Shared function to apply scale to minigame success zones
local function ApplyMinigameScale(minigameWidget)
    -- Navigate widget tree to access Image widgets individually
    -- Direct property access (widget.Image_0) always resolves to widget.Image
    local widgetTree = minigameWidget.WidgetTree
    if not (widgetTree and widgetTree:IsValid()) then return false end

    local canvasPanel = widgetTree.RootWidget
    if not (canvasPanel and canvasPanel:IsValid()) then return false end

    local slots = canvasPanel.Slots
    if not slots then return false end

    local appliedCount = 0

    slots:ForEach(function(index, slotElement)
        local slot = slotElement:get()
        if not slot:IsValid() then return end

        local content = slot.Content
        if not (content and content:IsValid()) then return end

        if not content:IsA("/Script/UMG.Image") then return end

        local okSlotName, slotName = pcall(function() return slot:GetFName():ToString() end)
        if not okSlotName then return end

        if slotName == "CanvasPanelSlot_9" then
            content:SetRenderTransformPivot({X = 0.0, Y = 0.5})
            content:SetRenderScale({X = LARGE_ZONE_SCALE, Y = 1.0})
            appliedCount = appliedCount + 1
        elseif slotName == "CanvasPanelSlot_10" then
            content:SetRenderTransformPivot({X = 0.0, Y = 0.5})
            content:SetRenderScale({X = SMALL_ZONE_SCALE, Y = 1.0})
            appliedCount = appliedCount + 1
        end
    end)

    return appliedCount > 0
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

-- Called on every Tick - applies scale on first Tick, then verifies persistence
function MinigameBarFix.OnMinigameTick(minigameWidget)
    local addr = minigameWidget:GetAddress()
    if not addr then return end

    -- Already verified this widget's scale persists, early out
    if verifiedWidgets[addr] then return end

    -- First Tick: apply scale
    if not modifiedWidgets[addr] then
        modifiedWidgets[addr] = true
        Log.Debug("Minigame Tick - applying scale (first time)")
        ApplyMinigameScale(minigameWidget)
        return
    end

    -- Second+ Tick: check if scale persisted
    local widgetTree = minigameWidget.WidgetTree
    if not (widgetTree and widgetTree:IsValid()) then return end

    local canvasPanel = widgetTree.RootWidget
    if not (canvasPanel and canvasPanel:IsValid()) then return end

    local slots = canvasPanel.Slots
    if not slots then return end

    local needsReapply = false

    slots:ForEach(function(index, slotElement)
        if needsReapply then return end  -- Already detected reset, skip rest

        local slot = slotElement:get()
        if not slot:IsValid() then return end

        local content = slot.Content
        if not (content and content:IsValid()) then return end

        if not content:IsA("/Script/UMG.Image") then return end

        local okSlotName, slotName = pcall(function() return slot:GetFName():ToString() end)
        if not okSlotName then return end

        if slotName == "CanvasPanelSlot_9" or slotName == "CanvasPanelSlot_10" then
            local expectedScale = slotName == "CanvasPanelSlot_9" and LARGE_ZONE_SCALE or SMALL_ZONE_SCALE
            local okScale, currentScale = pcall(function() return content.RenderTransform.Scale.X end)

            if not okScale or math.abs(currentScale - expectedScale) > 0.01 then
                needsReapply = true
            end
        end
    end)

    if needsReapply then
        Log.Warning("Minigame scale was reset by game, re-applying every Tick")
        ApplyMinigameScale(minigameWidget)
    else
        -- Scale persisted! Mark as verified so we don't check again
        verifiedWidgets[addr] = true
        Log.Debug("Minigame scale persisted correctly, Tick check disabled for this widget")
    end
end

return MinigameBarFix
