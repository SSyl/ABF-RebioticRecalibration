local HookUtil = require("utils/HookUtil")
local HideHotbarHotkeys = {}

-- Module state (set during Init)
local Config = nil
local Log = nil

-- Cache hotbar slot addresses for O(1) lookup instead of string matching
local slotAddressCache = {}

-- ============================================================
-- CORE LOGIC
-- ============================================================

function HideHotbarHotkeys.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("HideHotbarHotkeys - %s", status)
end

function HideHotbarHotkeys.Cleanup()
    -- Clear address cache on map transition (slot addresses will be different)
    slotAddressCache = {}
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function HideHotbarHotkeys.RegisterInPlayHooks()
    -- Hook UpdateSlot_UI on inventory slots - this updates whenever slot content changes
    -- We filter to only hide hotbar slots (not all inventory slots in the game)
    return HookUtil.Register(
        "/Game/Blueprints/Widgets/Inventory/W_InventoryItemSlot.W_InventoryItemSlot_C:UpdateSlot_UI",
        HideHotbarHotkeys.OnInventorySlotUpdate,
        Log
    )
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function HideHotbarHotkeys.OnInventorySlotUpdate(slotWidget)
    Log.DebugOnce("UpdateSlot_UI hook fired")

    if not slotWidget:IsValid() then return end

    local okAddr, addr = pcall(function() return slotWidget:GetAddress() end)
    if not okAddr or not addr then return end

    local isHotbarSlot = slotAddressCache[addr]

    if isHotbarSlot == nil then
        -- First time seeing this slot - check if hotbar and cache result
        local okName, fullName = pcall(function() return slotWidget:GetFullName() end)
        isHotbarSlot = okName and fullName and fullName:match("HotbarSlot") ~= nil
        slotAddressCache[addr] = isHotbarSlot
    end

    if not isHotbarSlot then return end

    local okBox, numberBox = pcall(function() return slotWidget.HotkeyNumberBox end)
    if okBox and numberBox and numberBox:IsValid() then
        local okVis, currentVis = pcall(function() return numberBox:GetVisibility() end)
        if okVis and currentVis ~= 1 then
            local okHide, err = pcall(function() numberBox:SetVisibility(1) end)
            if not okHide then
                Log.Debug("Failed to hide HotkeyNumberBox: %s", tostring(err))
            end
        end
    end

    local okText, numberText = pcall(function() return slotWidget.HotkeyNumberText end)
    if okText and numberText and numberText:IsValid() then
        local okVis, currentVis = pcall(function() return numberText:GetVisibility() end)
        if okVis and currentVis ~= 1 then
            local okHide, err = pcall(function() numberText:SetVisibility(1) end)
            if not okHide then
                Log.Debug("Failed to hide HotkeyNumberText: %s", tostring(err))
            end
        end
    end
end

return HideHotbarHotkeys
