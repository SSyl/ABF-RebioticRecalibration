--[[
============================================================================
AmmoCounter - Enhanced Ammo Display with Color Coding
============================================================================

Enhances the ammo counter HUD to show inventory ammo count with color coding.
Colors loaded ammo based on percentage (good/low/empty) and inventory ammo
based on configurable threshold. Optional mode shows max capacity alongside.

Two display modes:
- Simple (default): "Loaded | Inventory" (replaces max capacity)
- ShowMaxCapacity: "Loaded | MaxCap | Inventory"

HOOKS:
- W_HUD_AmmoCounter_C:UpdateAmmo (per-frame, color updates)
- Abiotic_InventoryComponent_C:OnRep_CurrentInventory (event-driven inventory changes)

PERFORMANCE: Per-frame hook with visibility early-exit and change detection caching
]]

local HookUtil = require("utils/HookUtil")
local WidgetUtil = require("utils/WidgetUtil")
local UEHelpers = require("UEHelpers")

-- ============================================================
-- MODULE METADATA
-- ============================================================

local Module = {
    name = "AmmoCounter",
    configKey = "AmmoCounter",

    schema = {
        { path = "Enabled", type = "boolean", default = true },
        { path = "LoadedAmmoWarning", type = "number", default = 0.5, min = 0, max = 1 },
        { path = "InventoryAmmoWarning", type = "number", default = 0, min = 0 },  -- 0 = adaptive
        { path = "ShowMaxCapacity", type = "boolean", default = false },
        { path = "AmmoGood", type = "color", default = { R = 114, G = 242, B = 255 } },
        { path = "AmmoLow", type = "color", default = { R = 255, G = 200, B = 32 } },
        { path = "NoAmmo", type = "color", default = { R = 249, G = 41, B = 41 } },
    },

    hookPoint = "PostInit",
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

-- Widget caches (ShowMaxCapacity mode)
local inventoryTextWidget = nil
local separatorWidget = nil

-- Cached references for OnRep_CurrentInventory hook
local cachedPlayerPawn = nil
local cachedWidget = nil
local cachedWeapon = nil

-- Change detection state
local lastWeaponAddress = nil
local lastInventoryAmmo = nil
local cachedMaxCapacity = nil

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    local thresholdDesc = Config.InventoryAmmoWarning == 0 and "adaptive" or tostring(Config.InventoryAmmoWarning)
    Log.Info("AmmoCounter - %s (InventoryWarning: %s)", status, thresholdDesc)
end

function Module.Cleanup()
    cachedPlayerPawn = nil
    cachedWidget = nil
    cachedWeapon = nil
    inventoryTextWidget = nil
    separatorWidget = nil
    lastWeaponAddress = nil
    lastInventoryAmmo = nil
    cachedMaxCapacity = nil
    Log.Debug("AmmoCounter state cleaned up")
end

-- ============================================================
-- DATA READING
-- ============================================================

local function GetWeaponAmmoData(weapon, cachedMax)
    local data = {
        loadedAmmo = nil,
        maxCapacity = nil,
        inventoryAmmo = nil,
        isValidWeapon = false
    }

    if not weapon:IsValid() then
        Log.DebugOnce("GetWeaponAmmoData: weapon invalid")
        return data
    end

    local okLoaded, loaded = pcall(function()
        return weapon.CurrentRoundsInMagazine
    end)
    if not okLoaded then
        Log.WarningOnce("Failed to read CurrentRoundsInMagazine: %s", tostring(loaded))
    elseif loaded == nil then
        Log.WarningOnce("CurrentRoundsInMagazine returned nil")
    else
        data.loadedAmmo = loaded
    end

    if cachedMax then
        data.maxCapacity = cachedMax
    else
        local okCapacity, capacity = pcall(function()
            return weapon.MaxMagazineSize
        end)
        if not okCapacity then
            Log.WarningOnce("Failed to read MaxMagazineSize: %s", tostring(capacity))
        elseif capacity == nil then
            Log.WarningOnce("MaxMagazineSize returned nil")
        else
            data.maxCapacity = capacity
        end
    end

    local okInv, outParams = pcall(function()
        local params = {}
        weapon:InventoryHasAmmoForCurrentWeapon(false, params, {}, {})
        return params
    end)
    if not okInv then
        Log.WarningOnce("Failed to call InventoryHasAmmoForCurrentWeapon: %s", tostring(outParams))
    elseif not outParams or outParams.Count == nil then
        Log.WarningOnce("InventoryHasAmmoForCurrentWeapon returned no Count (outParams=%s)", type(outParams))
    else
        data.inventoryAmmo = outParams.Count
    end

    data.isValidWeapon = (data.loadedAmmo ~= nil and data.maxCapacity ~= nil)

    if not data.isValidWeapon then
        Log.WarningOnce("Weapon data incomplete: loadedAmmo=%s, maxCapacity=%s", type(data.loadedAmmo), type(data.maxCapacity))
    end

    return data
end

-- ============================================================
-- COLOR LOGIC
-- ============================================================

local function GetLoadedAmmoColor(loadedAmmo, maxCapacity)
    if loadedAmmo == 0 then
        return Config.NoAmmo
    elseif maxCapacity > 0 then
        local percentage = loadedAmmo / maxCapacity
        return (percentage <= Config.LoadedAmmoWarning) and Config.AmmoLow or Config.AmmoGood
    else
        Log.Error("Invalid state: loadedAmmo=%s but maxCapacity=%s", tostring(loadedAmmo), tostring(maxCapacity))
        return Config.AmmoGood
    end
end

local function GetInventoryAmmoColor(inventoryAmmo, maxCapacity)
    -- 0 = adaptive (use maxCapacity as threshold)
    local threshold = Config.InventoryAmmoWarning
    if threshold == 0 then
        threshold = maxCapacity
    end

    if inventoryAmmo == 0 then
        return Config.NoAmmo
    elseif inventoryAmmo <= threshold then
        return Config.AmmoLow
    else
        return Config.AmmoGood
    end
end

local function SetWidgetColor(widget, color)
    if not widget:IsValid() or not color then
        return false
    end

    local ok = pcall(function()
        widget:SetColorAndOpacity({
            SpecifiedColor = color,
            ColorUseRule = "UseColor_Specified"
        })
    end)

    return ok
end

-- ============================================================
-- WIDGET HELPERS (ShowMaxCapacity mode)
-- ============================================================

local function GetWidgetSlot(widget)
    local ok, slot = pcall(function()
        return widget.Slot
    end)
    return (ok and slot:IsValid()) and slot or nil
end

local function GetSlotOffsets(slot)
    if not slot then return nil end
    local ok, offsets = pcall(function()
        return slot:GetOffsets()
    end)
    return ok and offsets or nil
end

local function SetSlotPosition(slot, left, top, right, bottom)
    if not slot then return false end

    local ok = pcall(function()
        slot:SetOffsets({
            Left = left,
            Top = top,
            Right = right,
            Bottom = bottom
        })
    end)

    return ok
end

-- ============================================================
-- WIDGET CREATION (ShowMaxCapacity mode)
-- ============================================================

local function CreateSeparatorWidget(widget)
    if separatorWidget and separatorWidget:IsValid() then
        return separatorWidget
    end

    local okSep, originalSep = pcall(function()
        return widget.Image_0
    end)

    local okCanvas, canvas = pcall(function()
        return widget.VisCanvas
    end)

    if not (okSep and originalSep:IsValid()) or not (okCanvas and canvas:IsValid()) then
        Log.Error("Failed to get separator template or canvas")
        return nil
    end

    local newSeparator = WidgetUtil.CloneWidget(originalSep, canvas, "InventoryAmmoSeparator")
    if not newSeparator then
        Log.Error("Failed to create separator widget")
        return nil
    end

    separatorWidget = newSeparator
    return newSeparator
end

local function CreateInventoryWidget(widget)
    if inventoryTextWidget and inventoryTextWidget:IsValid() then
        return inventoryTextWidget
    end

    local okText, textTemplate = pcall(function()
        return widget.Text_CurrentAmmo
    end)

    local okCanvas, canvas = pcall(function()
        return widget.VisCanvas
    end)

    if not (okText and textTemplate:IsValid()) or not (okCanvas and canvas:IsValid()) then
        Log.Error("Failed to get text template or canvas")
        return nil
    end

    local newWidget = WidgetUtil.CloneWidget(textTemplate, canvas, "Text_InventoryAmmo")
    if not newWidget then
        Log.Error("Failed to create inventory text widget")
        return nil
    end

    pcall(function()
        newWidget:SetJustification(0)  -- 0 = Left
    end)

    inventoryTextWidget = newWidget
    return newWidget
end

-- ============================================================
-- WIDGET POSITIONING (ShowMaxCapacity mode)
-- ============================================================

local function RepositionShowMaxCapacityWidgets(widget, maxCapacity)
    if not maxCapacity then return end

    local okOrigSep, originalSep = pcall(function() return widget.Image_0 end)
    local okMaxText, maxAmmoText = pcall(function() return widget.Text_MaxAmmo end)

    if not (okOrigSep and okMaxText and originalSep:IsValid() and maxAmmoText:IsValid()) then
        return
    end

    local originalSlot = GetWidgetSlot(originalSep)
    local maxSlot = GetWidgetSlot(maxAmmoText)

    if not (originalSlot and maxSlot) then
        return
    end

    local originalOffsets = GetSlotOffsets(originalSlot)
    local maxOffsets = GetSlotOffsets(maxSlot)

    if not (originalOffsets and maxOffsets) then
        return
    end

    local baseDistance = maxOffsets.Left - originalOffsets.Left

    if not (separatorWidget and separatorWidget:IsValid() and inventoryTextWidget and inventoryTextWidget:IsValid()) then
        return
    end

    local sepSlot = GetWidgetSlot(separatorWidget)
    local invSlot = GetWidgetSlot(inventoryTextWidget)

    if not (sepSlot and invSlot) then
        return
    end

    local digitCount = string.len(tostring(maxCapacity))
    local extraOffset = digitCount * 18

    SetSlotPosition(
        sepSlot,
        maxOffsets.Left + baseDistance + extraOffset,
        originalOffsets.Top,
        originalOffsets.Right,
        originalOffsets.Bottom
    )

    SetSlotPosition(
        invSlot,
        maxOffsets.Left + (baseDistance * 2) + extraOffset,
        -10.0,
        57.0,
        maxOffsets.Bottom
    )
end

-- ============================================================
-- WIDGET UPDATES
-- ============================================================

local function UpdateLoadedAmmoColor(widget, loadedAmmo, maxCapacity)
    local okText, textWidget = pcall(function()
        return widget.Text_CurrentAmmo
    end)

    if okText and textWidget:IsValid() and loadedAmmo ~= nil then
        local color = GetLoadedAmmoColor(loadedAmmo, maxCapacity)
        SetWidgetColor(textWidget, color)
    end
end

local function UpdateSimpleMode(widget, inventoryAmmo, maxCapacity)
    local okText, textWidget = pcall(function()
        return widget.Text_MaxAmmo
    end)

    if not okText or not textWidget:IsValid() then
        return
    end

    pcall(function()
        textWidget:SetText(FText(tostring(inventoryAmmo)))
    end)

    local color = GetInventoryAmmoColor(inventoryAmmo, maxCapacity)
    SetWidgetColor(textWidget, color)
end

local function UpdateShowMaxCapacityMode(widget, inventoryAmmo, maxCapacity, weaponChanged)
    local sepWidget = separatorWidget
    if not sepWidget or not sepWidget:IsValid() then
        separatorWidget = nil
        sepWidget = CreateSeparatorWidget(widget)
    end

    local invWidget = inventoryTextWidget
    if not invWidget or not invWidget:IsValid() then
        inventoryTextWidget = nil
        invWidget = CreateInventoryWidget(widget)
    end

    if not sepWidget or not invWidget then
        return
    end

    if weaponChanged then
        RepositionShowMaxCapacityWidgets(widget, maxCapacity)
    end

    pcall(function()
        invWidget:SetText(FText(tostring(inventoryAmmo)))
    end)

    local color = GetInventoryAmmoColor(inventoryAmmo, maxCapacity)
    SetWidgetColor(invWidget, color)
end

local function UpdateInventoryAmmoDisplay(widget, inventoryAmmo, maxCapacity, weaponChanged, inventoryChanged)
    if not inventoryAmmo then
        return
    end

    if not inventoryChanged and not weaponChanged then
        return
    end

    if Config.ShowMaxCapacity then
        UpdateShowMaxCapacityMode(widget, inventoryAmmo, maxCapacity, weaponChanged)
    else
        UpdateSimpleMode(widget, inventoryAmmo, maxCapacity)
    end
end

-- ============================================================
-- MAIN UPDATE LOGIC
-- ============================================================

local function UpdateAmmoDisplay(widget, weapon)
    local okAddr, currentWeaponAddress = pcall(function()
        return weapon:GetAddress()
    end)
    if not okAddr then
        return
    end

    local weaponChanged = (currentWeaponAddress ~= lastWeaponAddress)

    local maxCapacityToUse = (weaponChanged or not cachedMaxCapacity) and nil or cachedMaxCapacity

    local data = GetWeaponAmmoData(weapon, maxCapacityToUse)

    if not data.isValidWeapon then
        return
    end

    local inventoryChanged = (data.inventoryAmmo ~= lastInventoryAmmo)

    -- Always update loaded ammo color (runs every frame and will get overridden otherwise)
    UpdateLoadedAmmoColor(widget, data.loadedAmmo, data.maxCapacity)

    if inventoryChanged or weaponChanged then
        UpdateInventoryAmmoDisplay(widget, data.inventoryAmmo, data.maxCapacity, weaponChanged, inventoryChanged)
    end

    lastWeaponAddress = currentWeaponAddress
    lastInventoryAmmo = data.inventoryAmmo
    cachedMaxCapacity = data.maxCapacity
end

-- ============================================================
-- INVENTORY CHANGE DETECTION
-- ============================================================

local function OnInventoryChanged()
    if not cachedWidget or not cachedWidget:IsValid() then
        return
    end

    if not cachedWeapon or not cachedWeapon:IsValid() then
        return
    end

    local okInv, outParams = pcall(function()
        local params = {}
        cachedWeapon:InventoryHasAmmoForCurrentWeapon(false, params, {}, {})
        return params
    end)

    if not okInv or not outParams or outParams.Count == nil then
        return
    end

    local inventoryAmmo = outParams.Count

    local okMax, maxCapacity = pcall(function()
        return cachedWeapon.MaxMagazineSize
    end)

    if not okMax or not maxCapacity then
        return
    end

    UpdateInventoryAmmoDisplay(cachedWidget, inventoryAmmo, maxCapacity, false, true)

    Log.Debug("Inventory ammo changed: %d", inventoryAmmo)
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function Module.RegisterHooks()
    local success = true

    -- Main ammo display hook (per-frame)
    success = HookUtil.Register(
        "/Game/Blueprints/Widgets/W_HUD_AmmoCounter.W_HUD_AmmoCounter_C:UpdateAmmo",
        Module.OnUpdateAmmo,
        Log
    ) and success

    -- Inventory change detection hook (event-driven)
    success = HookUtil.Register(
        "/Game/Blueprints/Characters/Abiotic_InventoryComponent.Abiotic_InventoryComponent_C:OnRep_CurrentInventory",
        Module.OnRepCurrentInventory,
        Log
    ) and success

    return success
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnUpdateAmmo(widget)
    -- Filter by visibility (game hides VisCanvas for items that don't use ammo)
    local okVis, visCanvas = pcall(function()
        return widget.VisCanvas
    end)

    if not okVis or not visCanvas:IsValid() then
        return
    end

    local visibility = visCanvas:GetVisibility()

    -- SelfHitTest (3) = active, Collapsed (1) = hidden
    if visibility ~= 3 then
        cachedWidget = nil
        cachedWeapon = nil
        return
    end

    if not cachedPlayerPawn or not cachedPlayerPawn:IsValid() then
        cachedPlayerPawn = UEHelpers.GetPlayer()
        if not cachedPlayerPawn or not cachedPlayerPawn:IsValid() then
            return
        end
    end

    local okWeapon, weapon = pcall(function()
        return cachedPlayerPawn.ItemInHand_BP
    end)

    if not okWeapon or not weapon:IsValid() then
        cachedMaxCapacity = nil
        cachedWidget = nil
        cachedWeapon = nil
        return
    end

    if not weapon:IsA("/Game/Blueprints/Items/Weapons/Abiotic_Weapon_ParentBP.Abiotic_Weapon_ParentBP_C") then
        cachedMaxCapacity = nil
        cachedWidget = nil
        cachedWeapon = nil
        return
    end

    cachedWidget = widget
    cachedWeapon = weapon

    UpdateAmmoDisplay(widget, weapon)
end

function Module.OnRepCurrentInventory(inventory)
    local okOwner, owner = pcall(function() return inventory:GetOwner() end)
    if not okOwner or not owner:IsValid() then return end

    -- Early exit: only process PlayerCharacter inventories
    if not owner:IsA("/Game/Blueprints/Characters/Abiotic_PlayerCharacter.Abiotic_PlayerCharacter_C") then
        return
    end

    if not cachedPlayerPawn or not cachedPlayerPawn:IsValid() then
        cachedPlayerPawn = UEHelpers.GetPlayer()
        if not cachedPlayerPawn or not cachedPlayerPawn:IsValid() then
            return
        end
    end

    -- Filter: only process local player's inventory (compare addresses)
    local ownerAddr = owner:GetAddress()
    local playerAddr = cachedPlayerPawn:GetAddress()
    if ownerAddr ~= playerAddr then
        return
    end

    OnInventoryChanged()
end

return Module
