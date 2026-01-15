--[[
============================================================================
DistributionPadTweaks - Distribution Pad Range + Indicator
============================================================================

Increases pad range (configurable multiplier) and shows icon/text when looking at
containers in range. Uses O(1) cache with ref-counting for overlapping coverage
and delta-based sync to minimize updates. Per-frame cache prevents repeated lookups.

HOOKS:
- AbioticDeployed_ParentBP_C:ReceiveBeginPlay (Deployed_DistributionPad_C filter)
- AbioticDeployed_ParentBP_C:ReceiveEndPlay (cleanup)
- Deployed_DistributionPad_C:OnRep_DistributionActive (sync on activation)
- W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts (per-frame indicator)
- AbioticDeployed_ParentBP_C:OnRep_ConstructionModeActive (optional refresh)

PERFORMANCE: Per-frame indicator hook with O(1) cache lookup and address caching
]]

local HookUtil = require("utils/HookUtil")
local WidgetUtil = require("utils/WidgetUtil")

-- ============================================================
-- MODULE METADATA
-- ============================================================

local Module = {
    name = "DistPadTweaks",
    configKey = "DistributionPad",
    debugKey = "DistributionPad",

    schema = {
        { path = "Indicator.Enabled", type = "boolean", default = true },
        { path = "Indicator.RefreshOnBuiltContainer", type = "boolean", default = true },
        { path = "Indicator.IconEnabled", type = "boolean", default = true },
        { path = "Indicator.Icon", type = "string", default = "hackingdevice" },
        { path = "Indicator.IconColor", type = "color", default = { R = 114, G = 242, B = 255 } },
        { path = "Indicator.IconSize", type = "number", default = 24, min = 1 },
        { path = "Indicator.IconOffset.Horizontal", type = "number", default = 0 },
        { path = "Indicator.IconOffset.Vertical", type = "number", default = 0 },
        { path = "Indicator.TextEnabled", type = "boolean", default = false },
        { path = "Indicator.Text", type = "string", default = "[DistPad]" },
        { path = "Range.Enabled", type = "boolean", default = false },
        { path = "Range.Multiplier", type = "number", default = 1.5, min = 0.1, max = 10.0 },
    },

    hookPoint = "MainMenu",

    isEnabled = function(cfg) return cfg.Range.Enabled or cfg.Indicator.Enabled end,

    cleanup = {
        gameplay = function(cfg) return cfg.Indicator.Enabled end,
    },
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

local DistPadCache = { inventories = {} }
local TrackedPads = {}
local isSyncingCache = false
local InteractionPromptCache = { lastActorAddr = nil, lastActorInRange = false }
local TextBlockCache = { widgetAddr = nil, textBlock = nil }
local DistPadIconTexture = nil
local DistPadIconWidget = CreateInvalidObject()
local cachedContainerClass = CreateInvalidObject()
local onRepHookRegistered = false

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

local function GetContainerClass()
    if not cachedContainerClass:IsValid() then
        cachedContainerClass = StaticFindObject("/Game/Blueprints/DeployedObjects/Furniture/Deployed_Container_ParentBP.Deployed_Container_ParentBP_C")
    end
    return cachedContainerClass
end

local function IncrementInventoryRefCount(inventoryAddr)
    DistPadCache.inventories[inventoryAddr] = (DistPadCache.inventories[inventoryAddr] or 0) + 1
end

local function DecrementInventoryRefCount(inventoryAddr)
    local count = DistPadCache.inventories[inventoryAddr]
    if not count then return end
    DistPadCache.inventories[inventoryAddr] = count > 1 and count - 1 or nil
end

local function SyncCacheFromPad(pad)
    if not pad:IsValid() then return end

    local okUpdate = pcall(function() pad:UpdateCompatibleContainers() end)
    if not okUpdate then return end

    local okPadAddr, padAddr = pcall(function() return pad:GetAddress() end)
    if not okPadAddr or not padAddr then return end

    local padData = TrackedPads[padAddr]
    local oldInventories = (padData and padData.inventories) or {}

    local oldSet = {}
    for _, addr in ipairs(oldInventories) do
        oldSet[addr] = true
    end

    local newInventories = {}
    local seenNew = {}
    local okRead, inventoryArray = pcall(function() return pad.AdditionalInventories end)

    if okRead and inventoryArray then
        local arraySize = #inventoryArray
        Log.Debug("SyncCacheFromPad: pad has %d inventories", arraySize)

        for i = 1, arraySize do
            local inv = inventoryArray[i]
            if inv and inv:IsValid() then
                local okAddr, addr = pcall(function() return inv:GetAddress() end)
                if okAddr and addr and not seenNew[addr] then
                    seenNew[addr] = true
                    newInventories[#newInventories + 1] = addr
                    if oldSet[addr] then
                        oldSet[addr] = nil
                    else
                        IncrementInventoryRefCount(addr)
                    end
                end
            end
        end
    end

    for addr in pairs(oldSet) do
        DecrementInventoryRefCount(addr)
    end

    local okPos, position = pcall(function() return pad:K2_GetActorLocation() end)

    TrackedPads[padAddr] = {
        pad = pad,
        position = okPos and position or nil,
        inventories = newInventories
    }
end

local function PurgePadFromCache(pad)
    if not pad:IsValid() then return end

    local okAddr, padAddr = pcall(function() return pad:GetAddress() end)
    if not okAddr or not padAddr then return end

    local padData = TrackedPads[padAddr]
    if not padData then return end

    for _, invAddr in ipairs(padData.inventories or {}) do
        DecrementInventoryRefCount(invAddr)
    end

    TrackedPads[padAddr] = nil
end

local function GetOrCreateDistPadIcon(widget)
    if not Config.Indicator.IconEnabled then return DistPadIconWidget end
    if DistPadIconWidget:IsValid() then return DistPadIconWidget end

    local radioactiveIcon = widget.RadioactiveIcon
    if not radioactiveIcon:IsValid() then return DistPadIconWidget end

    local parent = radioactiveIcon:GetParent()
    if not parent:IsValid() then return DistPadIconWidget end

    local newIcon, slot = WidgetUtil.CloneWidget(radioactiveIcon, parent, "DistPadIcon")
    if not newIcon:IsValid() then return DistPadIconWidget end

    if slot:IsValid() then
        local offsetH = Config.Indicator.IconOffset.Horizontal
        local offsetV = Config.Indicator.IconOffset.Vertical
        slot:SetHorizontalAlignment(1)
        slot:SetVerticalAlignment(2)
        slot:SetPadding({ Left = -40 + offsetH, Top = -225 - offsetV, Right = 0, Bottom = 0 })
    end

    local iconName = Config.Indicator.Icon
    if iconName == "" then return DistPadIconWidget end

    if not DistPadIconTexture then
        local searchPaths = {
            "/Game/Textures/GUI/Icons/icon_" .. iconName .. ".icon_" .. iconName,
            "/Game/Textures/GUI/icon_" .. iconName .. ".icon_" .. iconName,
        }
        for _, iconPath in ipairs(searchPaths) do
            local texture = StaticFindObject(iconPath)
            if texture:IsValid() then
                DistPadIconTexture = texture
                break
            end
        end
    end

    if DistPadIconTexture then
        local size = Config.Indicator.IconSize
        newIcon:SetBrushFromTexture(DistPadIconTexture, false)
        newIcon:SetDesiredSizeOverride({ X = size, Y = size })
        newIcon:SetColorAndOpacity(Config.Indicator.IconColor)
    end

    DistPadIconWidget = newIcon
    return newIcon
end

local function HideDistPadIcon()
    if DistPadIconWidget:IsValid() then
        DistPadIconWidget:SetVisibility(1)
    end
end

local function ShowDistPadIcon(widget)
    local icon = GetOrCreateDistPadIcon(widget)
    if icon:IsValid() then icon:SetVisibility(4) end
end

local function AppendDistPadText(widget)
    if not Config.Indicator.TextEnabled or Config.Indicator.Text == "" then return end

    local okAddr, widgetAddr = pcall(function() return widget:GetAddress() end)
    if not okAddr or not widgetAddr then return end

    if widgetAddr ~= TextBlockCache.widgetAddr then
        local ok, tb = pcall(function() return widget.InteractionObjectName end)
        if ok and tb:IsValid() then
            TextBlockCache.widgetAddr = widgetAddr
            TextBlockCache.textBlock = tb
        else
            TextBlockCache.widgetAddr = nil
            TextBlockCache.textBlock = nil
            return
        end
    end

    local textBlock = TextBlockCache.textBlock
    if not textBlock or not textBlock:IsValid() then
        TextBlockCache.widgetAddr = nil
        TextBlockCache.textBlock = nil
        return
    end

    local okGet, currentText = pcall(function() return textBlock:GetText():ToString() end)
    if not okGet or not currentText then return end
    if currentText:match(Config.Indicator.TextPattern) then return end

    pcall(function()
        textBlock:SetText(FText(currentText .. " " .. Config.Indicator.Text))
    end)
end

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    -- Compute derived field
    Config.Indicator.TextPattern = Config.Indicator.Text:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")

    local anyEnabled = Config.Range.Enabled or Config.Indicator.Enabled
    local status = anyEnabled and "Enabled" or "Disabled"
    Log.Info("DistPadTweaks - %s", status)
end

function Module.GameplayCleanup()
    DistPadCache.inventories = {}
    TrackedPads = {}
    InteractionPromptCache.lastActorAddr = nil
    InteractionPromptCache.lastActorInRange = false
    TextBlockCache.widgetAddr = nil
    TextBlockCache.textBlock = nil
    DistPadIconTexture = nil
    DistPadIconWidget = CreateInvalidObject()
    cachedContainerClass = CreateInvalidObject()
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function Module.RegisterHooks()
    Log.Debug("RegisterHooks called")
    local success = true

    -- Pad spawn hook (for Range and/or Indicator)
    if Config.Range.Enabled or Config.Indicator.Enabled then
        success = HookUtil.RegisterABFDeployedReceiveBeginPlay(
            "Deployed_DistributionPad_C",
            Module.OnPadReceiveBeginPlay,
            Log
        ) and success
    end

    -- Indicator-specific hooks
    if Config.Indicator.Enabled then
        success = HookUtil.Register(
            "/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveEndPlay",
            Module.OnReceiveEndPlay,
            Log
        ) and success

        success = HookUtil.Register(
            "/Game/Blueprints/Widgets/W_PlayerHUD_InteractionPrompt.W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts",
            function(widget, ShowPressInteract, ShowHoldInteract, ShowPressPackage, ShowHoldPackage,
                     ObjectUnderConstruction, ConstructionPercent, RequiresPower, Radioactive,
                     ShowDescription, ExtraNoteLines, HitActorParam, HitComponentParam, RequiresPlug)
                Module.OnUpdateInteractionPrompts(widget, HitActorParam)
            end,
            Log,
            { warmup = true }
        ) and success

        -- OnRep_DistributionActive is late-bound in OnPadReceiveBeginPlay
        -- (Blueprint not loaded until a pad spawns)

        if Config.Indicator.RefreshOnBuiltContainer then
            success = HookUtil.Register(
                "/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:OnRep_ConstructionModeActive",
                Module.OnContainerConstructionComplete,
                Log
            ) and success
        end
    end

    return success
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnPadReceiveBeginPlay(pad)
    Log.Debug("OnPadReceiveBeginPlay fired")

    if Config.Range.Enabled then
        Module.OnDistPadBeginPlay(pad)
    end

    if Config.Indicator.Enabled then
        Module.OnPadBeginPlay(pad)
    end
end

function Module.OnDistPadBeginPlay(pad)
    if not pad:IsValid() or not Config.Range.Enabled then return end

    local okSphere, sphere = pcall(function() return pad.ContainerOverlapSphere end)
    if okSphere and sphere:IsValid() then
        local newRadius = 1000 * Config.Range.Multiplier
        pcall(function() sphere:SetSphereRadius(newRadius, true) end)
    end
end

function Module.OnPadBeginPlay(pad)
    local okLoading, isLoading = pcall(function() return pad.IsCurrentlyLoadingFromSave end)
    isLoading = okLoading and isLoading or false
    -- Late-bind OnRep_DistributionActive hook (Blueprint now guaranteed to be loaded)
    if Config.Indicator.Enabled and not onRepHookRegistered then
        onRepHookRegistered = true
        local asset, wasFound, wasLoaded = LoadAsset("/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C")
        Log.Debug("LoadAsset Results: Found=%s, Loaded=%s", tostring(wasFound), tostring(wasLoaded))

        HookUtil.Register(
            "/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C:OnRep_DistributionActive",
            Module.OnRepDistributionActive,
            Log)
    end

    ExecuteWithDelay(isLoading and 1000 or 500, function()
        ExecuteInGameThread(function()
            if not pad:IsValid() then return end
            Log.Debug("OnPadBeginPlay: syncing pad (isLoading=%s)", tostring(isLoading))
            SyncCacheFromPad(pad)
        end)
    end)
end

function Module.OnRepDistributionActive(pad)
    local okActive, isActive = pcall(function() return pad.DistributionActive end)

    if okActive and isActive then
        Log.Debug("OnRep_DistributionActive: syncing pad")
        Module.SyncPad(pad)
    end
end

function Module.SyncPad(pad)
    if not pad:IsValid() then return end
    if isSyncingCache then return end

    isSyncingCache = true

    pcall(function()
        SyncCacheFromPad(pad)
    end)

    isSyncingCache = false
end

function Module.OnReceiveEndPlay(actor)
    local okAddr, addr = pcall(function() return actor:GetAddress() end)
    if okAddr and addr and TrackedPads[addr] then
        PurgePadFromCache(actor)
    end
end

function Module.OnUpdateInteractionPrompts(widget, HitActorParam)
    local okHitActor, hitActor = pcall(function() return HitActorParam:get() end)
    if not okHitActor or not hitActor:IsValid() then
        InteractionPromptCache.lastActorAddr = nil
        InteractionPromptCache.lastActorInRange = false
        HideDistPadIcon()
        return
    end

    local okActorAddr, actorAddr = pcall(function() return hitActor:GetAddress() end)
    if not okActorAddr or not actorAddr then
        InteractionPromptCache.lastActorAddr = nil
        InteractionPromptCache.lastActorInRange = false
        HideDistPadIcon()
        return
    end

    if actorAddr == InteractionPromptCache.lastActorAddr then
        if InteractionPromptCache.lastActorInRange then
            AppendDistPadText(widget)
            ShowDistPadIcon(widget)
        else
            HideDistPadIcon()
        end
        return
    end

    InteractionPromptCache.lastActorAddr = actorAddr
    InteractionPromptCache.lastActorInRange = false

    local okInv, containerInv = pcall(function() return hitActor.ContainerInventory end)
    if not okInv or not containerInv:IsValid() then
        HideDistPadIcon()
        return
    end

    local okInvAddr, invAddr = pcall(function() return containerInv:GetAddress() end)
    if not okInvAddr or not invAddr or not DistPadCache.inventories[invAddr] then
        HideDistPadIcon()
        return
    end

    InteractionPromptCache.lastActorInRange = true
    AppendDistPadText(widget)
    ShowDistPadIcon(widget)
end

function Module.OnContainerConstructionComplete(deployable)
    local okLoading, isLoading = pcall(function() return deployable.IsCurrentlyLoadingFromSave end)
    if okLoading and isLoading then return end

    local okActive, isActive = pcall(function() return deployable.ConstructionModeActive end)
    if not okActive or isActive then return end

    local containerClass = GetContainerClass()
    if not deployable:IsA(containerClass) then return end

    Log.Debug("OnContainerConstructionComplete: new container placed")

    local okContainerPos, containerPos = pcall(function() return deployable:K2_GetActorLocation() end)
    if not okContainerPos then return end

    local multiplier = Config.Range.Enabled and Config.Range.Multiplier or 1.0
    local rangeSquared = (1000 * multiplier * 1.10) ^ 2

    for _, padData in pairs(TrackedPads) do
        if padData.pad and padData.pad:IsValid() and padData.position then
            local dx = containerPos.X - padData.position.X
            local dy = containerPos.Y - padData.position.Y
            local dz = containerPos.Z - padData.position.Z
            if dx*dx + dy*dy + dz*dz <= rangeSquared then
                Module.SyncPad(padData.pad)
            end
        end
    end

    InteractionPromptCache.lastActorAddr = nil
end

return Module
