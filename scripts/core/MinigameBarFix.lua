local HookUtil = require("utils/HookUtil")
local MinigameBarFix = {}

-- Module state (set during Init)
local Config = nil
local Log = nil

-- Track which widgets we've already modified (by address)
local modifiedWidgets = {}

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
    -- Clear modified widgets cache on map transition
    modifiedWidgets = {}
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
                function(minigameWidget)
                    local addr = minigameWidget:GetAddress()
                    if modifiedWidgets[addr] then return end
                    MinigameBarFix.OnMinigameCreated(minigameWidget)
                end,
                Log
            )
        end

        local okLoadWeightlifting = pcall(function()
            LoadAsset("/Game/Blueprints/Widgets/HUD/W_HUD_WeightliftingMinigame.W_HUD_WeightliftingMinigame_C")
        end)

        if okLoadWeightlifting then
            HookUtil.Register(
                "/Game/Blueprints/Widgets/HUD/W_HUD_WeightliftingMinigame.W_HUD_WeightliftingMinigame_C:Tick",
                function(minigameWidget)
                    local addr = minigameWidget:GetAddress()
                    if modifiedWidgets[addr] then return end
                    MinigameBarFix.OnMinigameCreated(minigameWidget)
                end,
                Log
            )
        end
    end)

    return true
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function MinigameBarFix.OnMinigameCreated(minigameWidget)
    local addr = minigameWidget:GetAddress()
    if modifiedWidgets[addr] then return end
    modifiedWidgets[addr] = true

    Log.Debug("Applying minigame bar fixes to widget at %s", tostring(addr))

    -- Navigate widget tree to access Image widgets individually
    -- Direct property access (widget.Image_0) always resolves to widget.Image
    local widgetTree = minigameWidget.WidgetTree
    if not (widgetTree and widgetTree:IsValid()) then return end

    local canvasPanel = widgetTree.RootWidget
    if not (canvasPanel and canvasPanel:IsValid()) then return end

    local slots = canvasPanel.Slots
    if not slots then return end

    slots:ForEach(function(index, slotElement)
        local slot = slotElement:get()
        if not slot:IsValid() then return end

        local content = slot.Content
        if not (content and content:IsValid()) then return end

        if not content:IsA("/Script/UMG.Image") then return end

        local okSlotName, slotName = pcall(function() return slot:GetFName():ToString() end)
        if not okSlotName then return end

        if slotName == "CanvasPanelSlot_9" then
            Log.Debug("Fixing CanvasPanelSlot_9 (large success zone) - Scale.X = %.2f", LARGE_ZONE_SCALE)
            content:SetRenderTransformPivot({X = 0.0, Y = 0.5})
            content:SetRenderScale({X = LARGE_ZONE_SCALE, Y = 1.0})
        elseif slotName == "CanvasPanelSlot_10" then
            Log.Debug("Fixing CanvasPanelSlot_10 (small success zone) - Scale.X = %.2f", SMALL_ZONE_SCALE)
            content:SetRenderTransformPivot({X = 0.0, Y = 0.5})
            content:SetRenderScale({X = SMALL_ZONE_SCALE, Y = 1.0})
        end
    end)
end

return MinigameBarFix
