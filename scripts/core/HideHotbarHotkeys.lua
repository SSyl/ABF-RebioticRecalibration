--[[
============================================================================
HideHotbarHotkeys - Hide Numeric Hotbar Indicators
============================================================================

Hides HotkeyNumberBox and HotkeyNumberText widgets on hotbar slots.
Uses address-based cache to identify hotbar slots (vs other inventory slots).

HOOKS: W_InventoryItemSlot_C:UpdateSlot_UI
PERFORMANCE: Fires on slot content changes with address caching
]]

local HookUtil = require("utils/HookUtil")

-- ============================================================
-- MODULE METADATA
-- ============================================================

local Module = {
    name = "HideHotbarHotkeys",
    configKey = "HideHotbarHotkeys",

    schema = {
        { path = "Enabled", type = "boolean", default = false },
    },

    hookPoint = "Gameplay",
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

local slotAddressCache = {}

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("HideHotbarHotkeys - %s", status)
end

function Module.GameplayCleanup()
    slotAddressCache = {}
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function Module.RegisterHooks()
    return HookUtil.Register(
        "/Game/Blueprints/Widgets/Inventory/W_InventoryItemSlot.W_InventoryItemSlot_C:UpdateSlot_UI",
        Module.OnInventorySlotUpdate,
        Log,
        { warmup = true, runPostWarmup = true }
    )
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnInventorySlotUpdate(slotWidget)
    Log.DebugOnce("UpdateSlot_UI hook fired")

    if not slotWidget:IsValid() then return end

    local okAddr, addr = pcall(function() return slotWidget:GetAddress() end)
    if not okAddr or not addr then return end

    local isHotbarSlot = slotAddressCache[addr]

    if isHotbarSlot == nil then
        local okName, fullName = pcall(function() return slotWidget:GetFullName() end)
        isHotbarSlot = okName and fullName and fullName:match("HotbarSlot") ~= nil
        slotAddressCache[addr] = isHotbarSlot
    end

    if not isHotbarSlot then return end

    local okBox, numberBox = pcall(function() return slotWidget.HotkeyNumberBox end)
    if okBox and numberBox:IsValid() then
        local okVis, currentVis = pcall(function() return numberBox:GetVisibility() end)
        if okVis and currentVis ~= 1 then
            pcall(function() numberBox:SetVisibility(1) end)
        end
    end

    local okText, numberText = pcall(function() return slotWidget.HotkeyNumberText end)
    if okText and numberText:IsValid() then
        local okVis, currentVis = pcall(function() return numberText:GetVisibility() end)
        if okVis and currentVis ~= 1 then
            pcall(function() numberText:SetVisibility(1) end)
        end
    end
end

return Module
