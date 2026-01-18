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
local PlayerUtil = require("utils/PlayerUtil")

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
        { path = "AmmoGood", type = "textcolor", default = { R = 114, G = 242, B = 255 } },
        { path = "AmmoLow", type = "textcolor", default = { R = 255, G = 200, B = 32 } },
        { path = "NoAmmo", type = "textcolor", default = { R = 249, G = 41, B = 41 } },
    },

    hookPoint = "Gameplay",
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

-- Widget caches (ShowMaxCapacity mode)
local inventoryTextWidget = CreateInvalidObject()
local separatorWidget = CreateInvalidObject()

-- Cached references for OnRep_CurrentInventory hook
local cachedWidget = CreateInvalidObject()
local cachedWeapon = CreateInvalidObject()

-- Change detection state
local lastWeaponAddress = nil
local lastInventoryAmmo = nil
local cachedMaxCapacity = nil

-- Cached classes for IsA checks
local cachedWeaponClass = CreateInvalidObject()
local cachedPlayerCharacterClass = CreateInvalidObject()

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

function Module.GameplayCleanup()
    cachedWidget = CreateInvalidObject()
    cachedWeapon = CreateInvalidObject()
    inventoryTextWidget = CreateInvalidObject()
    separatorWidget = CreateInvalidObject()
    cachedWeaponClass = CreateInvalidObject()
    cachedPlayerCharacterClass = CreateInvalidObject()
    lastWeaponAddress = nil
    lastInventoryAmmo = nil
    cachedMaxCapacity = nil
    Log.Debug("AmmoCounter state cleaned up")
end

-- ============================================================
-- CLASS HELPERS
-- ============================================================

local function GetWeaponClass()
    if not cachedWeaponClass:IsValid() then
        cachedWeaponClass = StaticFindObject("/Game/Blueprints/Items/Weapons/Abiotic_Weapon_ParentBP.Abiotic_Weapon_ParentBP_C")
    end
    return cachedWeaponClass
end

local function GetPlayerCharacterClass()
    if not cachedPlayerCharacterClass:IsValid() then
        cachedPlayerCharacterClass = StaticFindObject("/Game/Blueprints/Characters/Abiotic_PlayerCharacter.Abiotic_PlayerCharacter_C")
    end
    return cachedPlayerCharacterClass
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

    if not weapon:IsValid() then return data end

    data.loadedAmmo = weapon.CurrentRoundsInMagazine
    data.maxCapacity = cachedMax or weapon.MaxMagazineSize

    local outParams = {}
    weapon:InventoryHasAmmoForCurrentWeapon(false, outParams, {}, {})
    if outParams.Count ~= nil then
        data.inventoryAmmo = outParams.Count
    end

    data.isValidWeapon = (data.loadedAmmo ~= nil and data.maxCapacity ~= nil)

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

local function SetWidgetColor(widget, slateColor)
    if not widget:IsValid() or not slateColor then return end
    widget:SetColorAndOpacity(slateColor)
end

-- ============================================================
-- WIDGET HELPERS (ShowMaxCapacity mode)
-- ============================================================

local function SetSlotPosition(slot, left, top, right, bottom)
    if not slot:IsValid() then return end
    slot:SetOffsets({
        Left = left,
        Top = top,
        Right = right,
        Bottom = bottom
    })
end

-- ============================================================
-- WIDGET CREATION (ShowMaxCapacity mode)
-- ============================================================

local function CreateSeparatorWidget(widget)
    if separatorWidget:IsValid() then return separatorWidget end

    local originalSep = widget.Image_0
    local canvas = widget.VisCanvas

    if not originalSep:IsValid() or not canvas:IsValid() then return separatorWidget end

    local newSeparator = WidgetUtil.CloneWidget(originalSep, canvas, "InventoryAmmoSeparator")
    if newSeparator:IsValid() then
        separatorWidget = newSeparator
    end

    return separatorWidget
end

local function CreateInventoryWidget(widget)
    if inventoryTextWidget:IsValid() then return inventoryTextWidget end

    local textTemplate = widget.Text_CurrentAmmo
    local canvas = widget.VisCanvas

    if not textTemplate:IsValid() or not canvas:IsValid() then return inventoryTextWidget end

    local newWidget = WidgetUtil.CloneWidget(textTemplate, canvas, "Text_InventoryAmmo")
    if newWidget:IsValid() then
        newWidget:SetJustification(0)  -- 0 = Left
        inventoryTextWidget = newWidget
    end

    return inventoryTextWidget
end

-- ============================================================
-- WIDGET POSITIONING (ShowMaxCapacity mode)
-- ============================================================

local function RepositionShowMaxCapacityWidgets(widget, maxCapacity)
    if not maxCapacity then return end

    local originalSep = widget.Image_0
    local maxAmmoText = widget.Text_MaxAmmo

    if not originalSep:IsValid() or not maxAmmoText:IsValid() then return end

    local originalSlot = originalSep.Slot
    local maxSlot = maxAmmoText.Slot

    if not originalSlot:IsValid() or not maxSlot:IsValid() then return end

    local originalOffsets = originalSlot:GetOffsets()
    local maxOffsets = maxSlot:GetOffsets()

    local baseDistance = maxOffsets.Left - originalOffsets.Left

    if not separatorWidget:IsValid() or not inventoryTextWidget:IsValid() then return end

    local sepSlot = separatorWidget.Slot
    local invSlot = inventoryTextWidget.Slot

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
    local textWidget = widget.Text_CurrentAmmo

    if textWidget:IsValid() and loadedAmmo ~= nil then
        local color = GetLoadedAmmoColor(loadedAmmo, maxCapacity)
        SetWidgetColor(textWidget, color)
    end
end

local function UpdateSimpleMode(widget, inventoryAmmo, maxCapacity)
    local textWidget = widget.Text_MaxAmmo

    if not textWidget:IsValid() then return end

    textWidget:SetText(FText(tostring(inventoryAmmo)))

    local color = GetInventoryAmmoColor(inventoryAmmo, maxCapacity)
    SetWidgetColor(textWidget, color)
end

local function UpdateShowMaxCapacityMode(widget, inventoryAmmo, maxCapacity, weaponChanged)
    if not separatorWidget:IsValid() then
        CreateSeparatorWidget(widget)
    end

    if not inventoryTextWidget:IsValid() then
        CreateInventoryWidget(widget)
    end

    if not separatorWidget:IsValid() or not inventoryTextWidget:IsValid() then return end

    if weaponChanged then
        RepositionShowMaxCapacityWidgets(widget, maxCapacity)
    end

    inventoryTextWidget:SetText(FText(tostring(inventoryAmmo)))

    local color = GetInventoryAmmoColor(inventoryAmmo, maxCapacity)
    SetWidgetColor(inventoryTextWidget, color)
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
    local currentWeaponAddress = weapon:GetAddress()
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
    if not cachedWidget:IsValid() then return end
    if not cachedWeapon:IsValid() then return end

    local outParams = {}
    cachedWeapon:InventoryHasAmmoForCurrentWeapon(false, outParams, {}, {})

    if outParams.Count == nil then return end

    local inventoryAmmo = outParams.Count
    local maxCapacity = cachedWeapon.MaxMagazineSize

    UpdateInventoryAmmoDisplay(cachedWidget, inventoryAmmo, maxCapacity, false, true)

    Log.Debug("Inventory ammo changed: %d", inventoryAmmo)
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function Module.RegisterHooks()
    local success = true

    -- Main ammo display hook (per-frame, needs warmup to avoid crash on load)
    success = HookUtil.Register(
        "/Game/Blueprints/Widgets/W_HUD_AmmoCounter.W_HUD_AmmoCounter_C:UpdateAmmo",
        Module.OnUpdateAmmo,
        Log,
        { warmup = true }
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
    local visCanvas = widget.VisCanvas

    if not visCanvas:IsValid() then return end

    local visibility = visCanvas:GetVisibility()

    -- SelfHitTest (3) = active, Collapsed (1) = hidden
    if visibility ~= 3 then
        cachedWidget = CreateInvalidObject()
        cachedWeapon = CreateInvalidObject()
        return
    end

    local player = PlayerUtil.Get()
    if not player then return end

    local weapon = player.ItemInHand_BP

    if not weapon:IsValid() then
        cachedMaxCapacity = nil
        cachedWidget = CreateInvalidObject()
        cachedWeapon = CreateInvalidObject()
        return
    end

    local weaponClass = GetWeaponClass()
    if not weapon:IsA(weaponClass) then
        cachedMaxCapacity = nil
        cachedWidget = CreateInvalidObject()
        cachedWeapon = CreateInvalidObject()
        return
    end

    cachedWidget = widget
    cachedWeapon = weapon

    UpdateAmmoDisplay(widget, weapon)
end

function Module.OnRepCurrentInventory(inventory)
    local owner = inventory:GetOwner()
    if not owner:IsValid() then return end

    -- Early exit: only process PlayerCharacter inventories
    local playerClass = GetPlayerCharacterClass()
    if not owner:IsA(playerClass) then
        return
    end

    -- Filter: only process local player's inventory
    if not PlayerUtil.IsLocal(owner) then return end

    OnInventoryChanged()
end

return Module
