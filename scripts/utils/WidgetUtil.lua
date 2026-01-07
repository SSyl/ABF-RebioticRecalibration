--[[
============================================================================
WidgetUtil - Widget Creation and Manipulation Helpers
============================================================================

PURPOSE:
Provides helpers for common UMG widget operations:
- Cloning widgets with StaticConstructObject
- Adding widgets to parents (smart parent type detection)

Eliminates duplication between LowHealthVignette and DistributionPadTweaks.

USAGE:
```lua
local newWidget, slot = WidgetUtil.CloneWidget(templateWidget, parentWidget, "MyWidgetName")
if newWidget then
    -- Configure the slot (feature-specific)
    slot:SetAnchors({...})
    slot:SetPadding({...})
end
```
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
--- @return UObject|nil newWidget The cloned widget (or nil on failure)
--- @return UObject|nil slot The slot object for positioning (or nil on failure)
function WidgetUtil.CloneWidget(templateWidget, parent, widgetName)
    if not templateWidget or not templateWidget:IsValid() then
        return nil, nil
    end

    if not parent or not parent:IsValid() then
        return nil, nil
    end

    -- Clone widget using template parameter (copies all properties)
    local newWidget = StaticConstructObject(
        templateWidget:GetClass(),
        parent,
        FName(widgetName),
        0, 0, false, false,
        templateWidget  -- Template - auto-copies font, colors, shadows, all styling
    )

    if not newWidget or not newWidget:IsValid() then
        return nil, nil
    end

    -- Add to parent based on parent's class type
    local okClass, parentClassName = pcall(function()
        return parent:GetClass():GetFName():ToString()
    end)

    if not okClass then
        return nil, nil
    end

    local ok, slot
    if parentClassName == "Overlay" then
        ok, slot = pcall(function() return parent:AddChildToOverlay(newWidget) end)
    elseif parentClassName == "HorizontalBox" then
        ok, slot = pcall(function() return parent:AddChildToHorizontalBox(newWidget) end)
    elseif parentClassName == "VerticalBox" then
        ok, slot = pcall(function() return parent:AddChildToVerticalBox(newWidget) end)
    elseif parentClassName == "CanvasPanel" then
        ok, slot = pcall(function() return parent:AddChildToCanvas(newWidget) end)
    else
        -- Generic AddChild fallback
        ok, slot = pcall(function() return parent:AddChild(newWidget) end)
    end

    if not ok or not slot then
        return nil, nil
    end

    return newWidget, slot
end

return WidgetUtil
