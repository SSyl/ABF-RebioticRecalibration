--[[
============================================================================
TeleporterTags - Visual Tags for Synced Personal Teleporters
============================================================================

Adds visual identification to Personal Teleporters synced to teleport benches:
- Color overlay: Tints icon based on bench name hash (unique color per destination)
- Text overlay: Shows abbreviated bench name on inventory icon
- Tooltip fix: Forces tooltip refresh to show custom name on first hover

HOOKS: W_InventoryItemSlot_C:UpdateSlot_UI
PERFORMANCE: Per-frame hook with address caching and memoized abbreviation results
]]

local HookUtil = require("utils/HookUtil")

-- ============================================================
-- MODULE METADATA
-- ============================================================

local Module = {
    name = "TeleporterTags",
    configKey = "TeleporterTags",

    schema = {
        { path = "Enabled", type = "boolean", default = true },
        { path = "IconColor.Enabled", type = "boolean", default = false },
        { path = "Text.Enabled", type = "boolean", default = true },
        { path = "Text.Scale", type = "number", default = 0.8, min = 0.1, max = 2.0 },
        { path = "Text.Position", type = "string", default = "TOP" },
        { path = "Text.AbbreviationMode", type = "string", default = "Simple" },
        { path = "Text.Color", type = "textcolor", default = { R = 255, G = 186, B = 40 } },
    },

    hookPoint = "Gameplay",
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

-- Cache to track teleporter bench names per slot
-- Key: slot address, Value: bench name string (or false for unsynced teleporter)
local slotCache = {}

-- Cache for abbreviated results (memoization to avoid recalculating same bench names)
-- Key: "benchName|mode|scale", Value: abbreviated and truncated string
local abbreviationCache = {}

-- Derived config values (computed once in Init)
local TextSettings = nil
local UseCustomTextColor = false

-- ============================================================
-- CONSTANTS
-- ============================================================

-- Base width budget at TextScale = 1.0 (tuned for optimal fit at 0.8 scale = 4.55)
local BASE_WIDTH = 3.64

-- Y position offsets for text positioning
local TEXT_POSITIONS = {
    TOP = -67,
    CENTER = -30,
    BOTTOM = -10,
}

-- Character width lookup table (extracted from TeX Gyre Adventor Regular)
-- Values are normalized to font size (units per em)
local CHAR_WIDTHS = {
    A=0.74, B=0.574, C=0.813, D=0.744, E=0.536, F=0.485, G=0.872, H=0.683,
    I=0.226, J=0.482, K=0.591, L=0.462, M=0.919, N=0.74, O=0.869, P=0.592,
    Q=0.871, R=0.607, S=0.498, T=0.426, U=0.655, V=0.702, W=0.96, X=0.609,
    Y=0.592, Z=0.48,
    a=0.683, b=0.682, c=0.647, d=0.685, e=0.65, f=0.314, g=0.673, h=0.61,
    i=0.2, j=0.203, k=0.502, l=0.2, m=0.938, n=0.61, o=0.655, p=0.682,
    q=0.682, r=0.301, s=0.388, t=0.339, u=0.608, v=0.554, w=0.831, x=0.48,
    y=0.536, z=0.425,
    ["0"]=0.554, ["1"]=0.554, ["2"]=0.554, ["3"]=0.554, ["4"]=0.554,
    ["5"]=0.554, ["6"]=0.554, ["7"]=0.554, ["8"]=0.554, ["9"]=0.554,
    [" "]=0.277,
}
local AVG_CHAR_WIDTH = 0.55

-- Default game text color (orange, normalized and rounded to match ValidateColor output)
local function round3(x) return math.floor(x * 1000 + 0.5) / 1000 end
local DEFAULT_TEXT_COLOR = { R = 1.0, G = round3(186/255), B = round3(40/255) }

-- ============================================================
-- HELPER FUNCTIONS - Color
-- ============================================================

local function HSLtoRGB(h, s, l)
    local c = (1 - math.abs(2 * l - 1)) * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = l - c / 2

    local r, g, b
    if h >= 0 and h < 60 then
        r, g, b = c, x, 0
    elseif h >= 60 and h < 120 then
        r, g, b = x, c, 0
    elseif h >= 120 and h < 180 then
        r, g, b = 0, c, x
    elseif h >= 180 and h < 240 then
        r, g, b = 0, x, c
    elseif h >= 240 and h < 300 then
        r, g, b = x, 0, c
    else
        r, g, b = c, 0, x
    end

    return r + m, g + m, b + m
end

local function StringToColor(text)
    if not text or text == "" then
        return nil
    end

    local hash = 5381
    for i = 1, #text do
        hash = ((hash << 5) + hash) + string.byte(text, i)
    end

    local hue = (hash % 360)
    local saturation = 0.9
    local lightness = 0.6

    local r, g, b = HSLtoRGB(hue, saturation, lightness)

    return { R = r, G = g, B = b, A = 1.0 }
end

-- ============================================================
-- HELPER FUNCTIONS - Text Processing
-- ============================================================

local function ComputeTextSettings(config)
    local scale = config.Text.Scale
    local positionStr = (config.Text.Position or "TOP"):upper()

    return {
        scale = scale,
        maxWidth = BASE_WIDTH / scale,
        yPosition = TEXT_POSITIONS[positionStr] or TEXT_POSITIONS.TOP,
    }
end

local function IsDefaultTextColor(slateColor)
    local color = slateColor.SpecifiedColor
    return color.R == DEFAULT_TEXT_COLOR.R
        and color.G == DEFAULT_TEXT_COLOR.G
        and color.B == DEFAULT_TEXT_COLOR.B
end

local function AbbreviateName(benchName)
    if not benchName then return "" end

    local maxWidth = TextSettings.maxWidth
    local scale = TextSettings.scale
    local mode = (Config.Text.AbbreviationMode or "simple"):lower()

    -- Check cache first
    local cacheKey = benchName .. "|" .. mode .. "|" .. scale
    if abbreviationCache[cacheKey] then
        return abbreviationCache[cacheKey]
    end

    -- Apply abbreviation mode
    local result = ""
    if mode == "firstletter" then
        for word in benchName:gmatch("%S+") do
            result = result .. word:sub(1, 1)
        end
    elseif mode == "firsttwo" or mode == "firstthree" then
        local n = (mode == "firsttwo") and 2 or 3
        for word in benchName:gmatch("%S+") do
            result = result .. word:sub(1, n)
        end
    elseif mode == "firstword" then
        local firstWord = benchName:match("%S+")
        result = firstWord or ""
    elseif mode == "vowelremoval" then
        for word in benchName:gmatch("%S+") do
            if #word > 0 then
                result = result .. word:sub(1, 1)
                if #word > 1 then
                    result = result .. word:sub(2):gsub("[aeiouAEIOU]", "")
                end
            end
        end
    else
        -- "simple" mode: remove spaces
        result = benchName:gsub("%s", "")
    end

    -- Truncate based on cumulative character width (single-pass)
    local truncated = ""
    local width = 0
    for i = 1, #result do
        local char = result:sub(i, i)
        local charWidth = CHAR_WIDTHS[char] or AVG_CHAR_WIDTH
        if width + charWidth > maxWidth then
            break
        end
        truncated = truncated .. char
        width = width + charWidth
    end

    abbreviationCache[cacheKey] = truncated
    return truncated
end

-- ============================================================
-- DATA EXTRACTION
-- ============================================================

-- Returns: bench name string if synced teleporter, false if unsynced, nil if not a teleporter
local function GetTeleporterBenchName(slot)
    if not slot:IsValid() then return nil end

    local okItem, itemInSlot = pcall(function()
        return slot.ItemInSlot
    end)
    if not okItem or not itemInSlot:IsValid() then return nil end

    local okRowName, rowName = pcall(function()
        return itemInSlot.ItemDataTable_18_BF1052F141F66A976F4844AB2B13062B.RowName:ToString()
    end)
    if not okRowName or rowName ~= "personalteleporter" then return nil end

    local okPlayerString, playerString = pcall(function()
        return itemInSlot.ChangeableData_12_2B90E1F74F648135579D39A49F5A2313.PlayerMadeString_42_CC0B72B24DBEAB2CC04454AAFFD4BBE9
    end)
    if not okPlayerString or playerString:type() ~= "FString" then return false end

    local okToString, playerStringLua = pcall(function()
        return playerString:ToString()
    end)
    if not okToString or not playerStringLua or playerStringLua == "" then return false end

    -- Extract bench name from format: "<GUID>,<BenchName>"
    local benchName = playerStringLua:match(",(.+)$")
    return benchName or false
end

-- ============================================================
-- UI MANIPULATION
-- ============================================================

local function ResetSlotToDefaults(slot)
    if not slot:IsValid() then return end

    local ok, stackText = pcall(function()
        return slot.StackText
    end)

    if ok and stackText:IsValid() then
        pcall(function()
            stackText:SetJustification(2)
            stackText:SetRenderTranslation({ X = 0.0, Y = 0.0 })
            stackText:SetRenderScale({ X = 1.0, Y = 1.0 })

            if UseCustomTextColor then
                stackText:SetColorAndOpacity({
                    SpecifiedColor = { R = 1.0, G = 0.730461, B = 0.155926, A = 1.0 },
                    ColorUseRule = "UseColor_Specified"
                })
            end
        end)
    end
end

-- Fix vanilla tooltip bug where custom item names don't show on first hover
local function FixItemTooltipData(slot)
    if not slot:IsValid() then return end

    local ok, hoverTooltip = pcall(function()
        return slot.HoverTooltip
    end)

    -- Create tooltip if it doesn't exist yet
    if not ok or not hoverTooltip:IsValid() then
        pcall(function()
            slot:ToggleItemTooltip(true)
            slot:ToggleItemTooltip(false)
        end)

        ok, hoverTooltip = pcall(function()
            return slot.HoverTooltip
        end)
    end

    -- Refresh tooltip to pick up PlayerMadeString
    if ok and hoverTooltip:IsValid() then
        pcall(function()
            hoverTooltip:RefreshTooltipInformation()
        end)
    end
end

local function ApplyColorOverlay(slot, benchName)
    if not slot:IsValid() then return end
    if not Config.IconColor.Enabled then return end

    local ok, iconWidget = pcall(function()
        return slot.Icon
    end)

    if not ok or not iconWidget:IsValid() then return end

    local color = StringToColor(benchName)
    if color then
        local colorOk = pcall(function()
            iconWidget:SetColorAndOpacity(color)
        end)

        if colorOk then
            Log.Debug("Applied color to '%s'", benchName)
        else
            Log.Debug("Failed to apply color to '%s'", benchName)
        end
    end
end

local function ApplyTextOverlay(slot, benchName)
    if not slot:IsValid() then return end
    if not Config.Text.Enabled then return end

    local abbrevName = AbbreviateName(benchName)

    local ok, stackText = pcall(function()
        return slot.StackText
    end)

    if not ok or not stackText:IsValid() then return end

    -- Check if text widget needs setup (Justification = 1/Center means already configured)
    local okJust, justification = pcall(function()
        return stackText.Justification
    end)

    local needsSetup = not okJust or justification ~= 1

    pcall(function()
        stackText:SetText(FText(abbrevName))
        stackText:SetVisibility(4)

        if needsSetup then
            stackText:SetJustification(1)
            stackText:SetRenderTransform({
                Translation = { X = -3.0, Y = TextSettings.yPosition },
                Scale = { X = TextSettings.scale, Y = TextSettings.scale },
                Shear = { X = 0.0, Y = 0.0 },
                Angle = 0.0
            })

            if UseCustomTextColor then
                stackText:SetColorAndOpacity(Config.Text.Color)
            end

            Log.Debug("Configured text overlay for: %s", abbrevName)
        end
    end)
end

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    -- Compute derived config values
    TextSettings = ComputeTextSettings(Config)
    UseCustomTextColor = not IsDefaultTextColor(Config.Text.Color)

    local colorStatus = UseCustomTextColor and "custom" or "default"
    Log.Debug("Text color: %s", colorStatus)

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("TeleporterTags - %s", status)
end

function Module.GameplayCleanup()
    slotCache = {}
    abbreviationCache = {}
    Log.Debug("TeleporterTags caches cleared")
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function Module.RegisterHooks()
    return HookUtil.Register(
        "/Game/Blueprints/Widgets/Inventory/W_InventoryItemSlot.W_InventoryItemSlot_C:UpdateSlot_UI",
        Module.OnSlotUpdate,
        Log,
        { warmup = true, runPostWarmup = true }
    )
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnSlotUpdate(slot)
    if not slot:IsValid() then return end

    local okAddr, slotAddr = pcall(function()
        return slot:GetAddress()
    end)
    if not okAddr or not slotAddr then return end

    local cachedBenchName = slotCache[slotAddr]

    -- Fast path: slot is cached
    if cachedBenchName ~= nil then
        local benchName = GetTeleporterBenchName(slot)

        if benchName == cachedBenchName then
            -- Same teleporter, reapply overlays (game can reset visibility)
            if benchName then
                ApplyColorOverlay(slot, benchName)
                ApplyTextOverlay(slot, benchName)
            end
            return
        elseif not benchName and cachedBenchName then
            -- Was a teleporter, now empty or different item
            ResetSlotToDefaults(slot)
            slotCache[slotAddr] = nil
            return
        end
    end

    -- Slow path: first time seeing this slot or item changed

    local okClass, className = pcall(function()
        return slot:GetClass():GetFName():ToString()
    end)
    if not okClass or className ~= "W_InventoryItemSlot_C" then return end

    local benchName = GetTeleporterBenchName(slot)

    -- Cache result (benchName or false for unsynced teleporter, nil already early-exited)
    slotCache[slotAddr] = benchName or false

    if benchName then
        Log.Debug("OnSlotUpdate: New teleporter in slot - %s", benchName)
    end

    if not benchName then return end

    -- Full setup for synced teleporter
    FixItemTooltipData(slot)
    ApplyColorOverlay(slot, benchName)
    ApplyTextOverlay(slot, benchName)
end

return Module
