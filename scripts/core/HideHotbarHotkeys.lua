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

    local addr = slotWidget:GetAddress()
    if not addr then return end

    local isHotbarSlot = slotAddressCache[addr]

    if isHotbarSlot == nil then
        local fullName = slotWidget:GetFullName()
        isHotbarSlot = fullName and fullName:match("HotbarSlot") ~= nil
        slotAddressCache[addr] = isHotbarSlot
    end

    if not isHotbarSlot then return end

    local okBox, numberBox = pcall(function() return slotWidget.HotkeyNumberBox end)
    if okBox and numberBox:IsValid() then
        if numberBox:GetVisibility() ~= 1 then
            numberBox:SetVisibility(1)
        end
    end

    local okText, numberText = pcall(function() return slotWidget.HotkeyNumberText end)
    if okText and numberText:IsValid() then
        if numberText:GetVisibility() ~= 1 then
            numberText:SetVisibility(1)
        end
    end
end

return Module
