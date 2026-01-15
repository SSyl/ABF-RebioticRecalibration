--[[
============================================================================
WidgetUtil - Widget Creation and Manipulation Helpers
============================================================================

Helpers for UMG widget operations. CloneWidget uses StaticConstructObject with
template parameter to copy all styling, then auto-detects parent type (Overlay,
HorizontalBox, VerticalBox, CanvasPanel) to add child appropriately.

API:
- CloneWidget(templateWidget, parent, widgetName) -> newWidget, slot
]]

local WidgetUtil = {}

-- ============================================================
-- WIDGET CLONING
-- ============================================================

--- Clones a widget using StaticConstructObject with template parameter
--- Automatically detects parent type and adds child appropriately
--- @param templateWidget UObject Widget to clone
--- @param parent UObject Parent widget to add to
--- @param widgetName string Name for the new widget
--- @return UObject newWidget The cloned widget (invalid on failure)
--- @return UObject slot The slot object for positioning (invalid on failure)
function WidgetUtil.CloneWidget(templateWidget, parent, widgetName)
    local invalid = CreateInvalidObject()
    if not templateWidget:IsValid() then return invalid, invalid end
    if not parent:IsValid() then return invalid, invalid end

    -- Clone widget using template parameter (copies all properties)
    local newWidget = StaticConstructObject(
        templateWidget:GetClass(),
        parent,
        FName(widgetName),
        0, 0, false, false,
        templateWidget  -- Template - auto-copies font, colors, shadows, all styling
    )

    if not newWidget:IsValid() then return invalid, invalid end

    -- Add to parent based on parent's class type
    local parentClassName = parent:GetClass():GetFName():ToString()

    local slot
    if parentClassName == "Overlay" then
        slot = parent:AddChildToOverlay(newWidget)
    elseif parentClassName == "HorizontalBox" then
        slot = parent:AddChildToHorizontalBox(newWidget)
    elseif parentClassName == "VerticalBox" then
        slot = parent:AddChildToVerticalBox(newWidget)
    elseif parentClassName == "CanvasPanel" then
        slot = parent:AddChildToCanvas(newWidget)
    else
        slot = parent:AddChild(newWidget)
    end

    if not slot:IsValid() then return invalid, invalid end

    return newWidget, slot
end

return WidgetUtil
