--[[
============================================================================
HideHotbarHotkeys - Hide or Customize Hotbar Key Indicators
============================================================================

Two modes:
  - Hide: Hides HotkeyNumberBox and HotkeyNumberText widgets
  - ShowBindings: Displays actual keybindings (e.g., if rebound from 1 to Z)

Uses address-based cache to identify hotbar slots (vs other inventory slots).
Note: ShowBindings reads keybindings on map load. Restart game after changing bindings.

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
        { path = "Mode", type = "string", default = "Hide" }, -- "Hide" or "ShowBindings"
    },

    hookPoint = "Gameplay",
}

-- ============================================================
-- CONSTANTS
-- ============================================================

-- FKey names to display strings (2 chars max for hotbar fit)
local KEY_DISPLAY = {
    -- Number row
    One = "1", Two = "2", Three = "3", Four = "4", Five = "5",
    Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
    -- Numpad
    NumPadZero = "N0", NumPadOne = "N1", NumPadTwo = "N2", NumPadThree = "N3",
    NumPadFour = "N4", NumPadFive = "N5", NumPadSix = "N6", NumPadSeven = "N7",
    NumPadEight = "N8", NumPadNine = "N9",
    -- Special keys
    PageUp = "PU", PageDown = "PD", Home = "Hm", End = "Ed",
    Insert = "In", Delete = "De", Escape = "Es",
    SpaceBar = "Sp", Tab = "Tb", CapsLock = "CL",
    LeftShift = "LS", RightShift = "RS",
    LeftControl = "LC", RightControl = "RC",
    LeftAlt = "LA", RightAlt = "RA",
    BackSpace = "BS", Enter = "En",
    -- Arrow keys
    Up = "^", Down = "v", Left = "<", Right = ">",
    -- Mouse
    LeftMouseButton = "M1", RightMouseButton = "M2", MiddleMouseButton = "M3",
    ThumbMouseButton = "M4", ThumbMouseButton2 = "M5",
}

-- Widget slot identifier to action name mapping
-- Widget names: HotbarSlot_1, HotbarSlot_FannyPack1, etc.
-- Action names: HotbarSlot1, HotbarSlot9, HotbarSlot10
local SLOT_TO_ACTION = {
    ["1"] = "HotbarSlot1",
    ["2"] = "HotbarSlot2",
    ["3"] = "HotbarSlot3",
    ["4"] = "HotbarSlot4",
    ["5"] = "HotbarSlot5",
    ["6"] = "HotbarSlot6",
    ["7"] = "HotbarSlot7",
    ["8"] = "HotbarSlot8",
    ["FannyPack1"] = "HotbarSlot9",
    ["FannyPack2"] = "HotbarSlot10",
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

local slotAddressCache = {}    -- address -> { isHotbar = bool, slotId = string }
local hotbarKeyCache = {}      -- actionName -> displayKey (e.g., "HotbarSlot1" -> "Z")

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

local function GetDisplayKey(keyName)
    if KEY_DISPLAY[keyName] then
        return KEY_DISPLAY[keyName]
    end
    -- Truncate unknown keys to 2 chars
    return keyName:sub(1, 2)
end

local function ExtractSlotId(fullName)
    -- Match FannyPack first (more specific pattern)
    local fannyId = fullName:match("HotbarSlot_(FannyPack%d)")
    if fannyId then return fannyId end

    -- Match regular slot numbers
    local slotNum = fullName:match("HotbarSlot_(%d+)")
    return slotNum
end

local function ProcessMapping(mapping)
    local okAction, actionName = pcall(function()
        return mapping.ActionName:ToString()
    end)
    local okKey, keyName = pcall(function()
        return mapping.Key.KeyName:ToString()
    end)

    if okAction and okKey and actionName:match("^HotbarSlot") then
        hotbarKeyCache[actionName] = GetDisplayKey(keyName)
        Log.Debug("Cached binding: %s = %s", actionName, hotbarKeyCache[actionName])
    end
end

local function ProcessMappingGroup(group)
    local actionMappings = group.ActionMappings
    if not actionMappings then return end

    local count = #actionMappings
    for mappingIdx = 1, count do
        local mapping = actionMappings[mappingIdx]
        if mapping then
            ProcessMapping(mapping)
        end
    end
end

local function ReadCurrentBindings()
    hotbarKeyCache = {}

    local inputMappingManager = FindFirstOf("InputMappingManager")
    if not inputMappingManager:IsValid() then
        Log.Debug("InputMappingManager not found, using defaults")
        return
    end

    -- Direct property access - PlayerInputOverrides is TArray<FPlayerInputMappings>
    local playerInputOverrides = inputMappingManager.PlayerInputOverrides

    playerInputOverrides:ForEach(function(overrideIdx, overrideElement)
        local playerOverride = overrideElement:get()

        local mappingOverrides = playerOverride.MappingOverrides
        if not mappingOverrides then return end

        local mappingGroups = mappingOverrides.MappingGroups
        if not mappingGroups then return end

        local groupCount = #mappingGroups
        for groupIdx = 1, groupCount do
            local group = mappingGroups[groupIdx]
            if group then
                ProcessMappingGroup(group)
            end
        end
    end)
end

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    local mode = Config.Mode or "Hide"
    Log.Info("HideHotbarHotkeys - %s (Mode: %s)", status, mode)
end

function Module.GameplayCleanup()
    slotAddressCache = {}
    hotbarKeyCache = {}
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function Module.RegisterHooks()
    local success = HookUtil.RegisterABFInventorySlotUpdateUI(Module.OnInventorySlotUpdate, Log)

    if Config.Mode == "ShowBindings" then
        ReadCurrentBindings()
    end

    return success
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnInventorySlotUpdate(slotWidget)
    Log.DebugOnce("UpdateSlot_UI hook fired")

    if not slotWidget:IsValid() then return end

    local addr = slotWidget:GetAddress()
    if not addr then return end

    local cached = slotAddressCache[addr]

    if cached == nil then
        local fullName = slotWidget:GetFullName()
        local slotId = ExtractSlotId(fullName)
        cached = {
            isHotbar = slotId ~= nil,
            slotId = slotId,
        }
        slotAddressCache[addr] = cached
    end

    if not cached.isHotbar then return end

    if Config.Mode == "Hide" then
        Module.HideSlotIndicators(slotWidget)
    elseif Config.Mode == "ShowBindings" then
        Module.ShowSlotBinding(slotWidget, cached.slotId)
    end
end

function Module.HideSlotIndicators(slotWidget)
    local numberBox = slotWidget.HotkeyNumberBox
    if numberBox:IsValid() and numberBox:GetVisibility() ~= 1 then
        numberBox:SetVisibility(1)
    end

    local numberText = slotWidget.HotkeyNumberText
    if numberText:IsValid() and numberText:GetVisibility() ~= 1 then
        numberText:SetVisibility(1)
    end
end

function Module.ShowSlotBinding(slotWidget, slotId)
    local numberText = slotWidget.HotkeyNumberText
    if not numberText:IsValid() then return end

    local actionName = SLOT_TO_ACTION[slotId]
    if not actionName then return end

    local boundKey = hotbarKeyCache[actionName]
    if not boundKey then return end

    numberText:SetText(FText(boundKey))
end

return Module
