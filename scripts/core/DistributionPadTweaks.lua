local HookUtil = require("utils/HookUtil")
local WidgetUtil = require("utils/WidgetUtil")
local DistributionPadTweaks = {}

-- Module state (set during Init)
local Config = nil
local Log = nil

-- Late-binding hook registration flag
local onRepHookRegistered = false

-- ============================================================
-- CACHE STATE
-- ============================================================
-- Cache provides O(1) lookup for "is container in any pad's range?" instead of O(pads) per frame.
-- Reference counting handles overlapping pad coverage - container stays cached until NO pads cover it.

local DistPadCache = { inventories = {} }  -- inventoryAddr → refCount
local TrackedPads = {}                      -- padAddr → { pad, position, inventories[] }

-- Re-entry guard: accessing AdditionalInventories can trigger OnRep → UpdateCompatibleContainers
-- again, causing infinite recursion. Observed as freezes in multiplayer testing.
local isSyncingCache = false

-- Per-frame caches to avoid repeated lookups while looking at the same container
local InteractionPromptCache = { lastActorAddr = nil, lastActorInRange = false }
local TextBlockCache = { widgetAddr = nil, textBlock = nil }
local DistPadIconTexture = nil
local DistPadIconWidget = nil

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

local function IncrementInventoryRefCount(inventoryAddr)
    DistPadCache.inventories[inventoryAddr] = (DistPadCache.inventories[inventoryAddr] or 0) + 1
end

local function DecrementInventoryRefCount(inventoryAddr)
    local count = DistPadCache.inventories[inventoryAddr]
    if not count then return end
    DistPadCache.inventories[inventoryAddr] = count > 1 and count - 1 or nil
end

-- ============================================================
-- CACHE SYNCHRONIZATION (DELTA-BASED)
-- ============================================================
-- UpdateCompatibleContainers fires frequently (e.g., player walks on pad trigger) even when
-- nothing changed. Naive approach would decrement all old + increment all new = 2N operations.
--
-- Delta approach: compare old vs new inventory lists, only update what actually changed.
-- Uses set difference: oldSet consumed by matches → remaining = removed, new entries = added.

local function SyncCacheFromPad(pad)
    if not pad:IsValid() then
        Log.Debug("SyncCacheFromPad: invalid pad")
        return
    end

    -- First: call Blueprint function to populate AdditionalInventories
    local okUpdate = pcall(function() pad:UpdateCompatibleContainers() end)
    if not okUpdate then
        Log.Debug("SyncCacheFromPad: UpdateCompatibleContainers failed")
        return
    end

    -- Then: read the populated data
    local okPadAddr, padAddr = pcall(function() return pad:GetAddress() end)
    if not okPadAddr or not padAddr then
        Log.Debug("SyncCacheFromPad: couldn't get pad address")
        return
    end

    local padData = TrackedPads[padAddr]
    local oldInventories = (padData and padData.inventories) or {}

    -- Build lookup set from old inventories
    local oldSet = {}
    for _, addr in ipairs(oldInventories) do
        oldSet[addr] = true
    end

    local newInventories = {}
    local seenNew = {}  -- Guard against duplicate entries in AdditionalInventories
    local okRead, inventoryArray = pcall(function() return pad.AdditionalInventories end)

    if okRead and inventoryArray then
        local arraySize = #inventoryArray
        Log.Debug("SyncCacheFromPad: pad has %d inventories in AdditionalInventories", arraySize)

        for i = 1, arraySize do
            local inv = inventoryArray[i]
            if inv and inv:IsValid() then
                local okAddr, addr = pcall(function() return inv:GetAddress() end)
                if okAddr and addr and not seenNew[addr] then
                    seenNew[addr] = true
                    newInventories[#newInventories + 1] = addr
                    if oldSet[addr] then
                        oldSet[addr] = nil  -- Unchanged, consume from old set
                    else
                        IncrementInventoryRefCount(addr)  -- Added
                    end
                end
            end
        end
    else
        Log.Debug("SyncCacheFromPad: couldn't read AdditionalInventories")
    end

    -- Remaining in oldSet = removed
    local removedCount = 0
    for addr in pairs(oldSet) do
        DecrementInventoryRefCount(addr)
        removedCount = removedCount + 1
    end
    if removedCount > 0 then
        Log.Debug("SyncCacheFromPad: removed %d inventories from cache", removedCount)
    end

    local okPos, position = pcall(function() return pad:K2_GetActorLocation() end)

    TrackedPads[padAddr] = {
        pad = pad,
        position = okPos and position or nil,
        inventories = newInventories
    }

    Log.Debug("SyncCacheFromPad: pad now tracking %d inventories (had %d)", #newInventories, #oldInventories)
end

-- Called when pad is destroyed - decrement ref counts for all its inventories
local function PurgePadFromCache(pad)
    -- Defensive check: pad should always be valid during ReceiveEndPlay, but log if not
    -- This helps us detect if cache cleanup ever fails and leaves stale data
    if not pad:IsValid() then
        Log.Debug("PurgePadFromCache: pad was invalid, cannot purge from cache")
        return
    end

    local okAddr, padAddr = pcall(function() return pad:GetAddress() end)
    if not okAddr or not padAddr then return end

    local padData = TrackedPads[padAddr]
    if not padData then return end

    for _, invAddr in ipairs(padData.inventories or {}) do
        DecrementInventoryRefCount(invAddr)
    end

    TrackedPads[padAddr] = nil
end

-- ============================================================
-- WIDGET HELPERS
-- ============================================================

-- Lazily create icon widget by cloning RadioactiveIcon, cached until Cleanup()
local function GetOrCreateDistPadIcon(widget)
    if not Config.Indicator.IconEnabled then return nil end
    if DistPadIconWidget and DistPadIconWidget:IsValid() then return DistPadIconWidget end

    local okRadio, radioactiveIcon = pcall(function() return widget.RadioactiveIcon end)
    if not okRadio or not radioactiveIcon or not radioactiveIcon:IsValid() then
        Log.Debug("Failed to get RadioactiveIcon")
        return nil
    end

    local okParent, parent = pcall(function() return radioactiveIcon:GetParent() end)
    if not okParent or not parent or not parent:IsValid() then
        Log.Debug("Failed to get RadioactiveIcon parent")
        return nil
    end

    local newIcon, slot = WidgetUtil.CloneWidget(radioactiveIcon, parent, "DistPadIcon")
    if not newIcon then
        Log.Debug("WidgetUtil.CloneWidget failed for DistPadIcon")
        return nil
    end

    if slot and slot:IsValid() then
        local offsetH = Config.Indicator.IconOffset.Horizontal
        local offsetV = Config.Indicator.IconOffset.Vertical
        pcall(function()
            slot:SetHorizontalAlignment(1)
            slot:SetVerticalAlignment(2)
            slot:SetPadding({ Left = -40 + offsetH, Top = -225 - offsetV, Right = 0, Bottom = 0 })
        end)
    end

    local iconName = Config.Indicator.Icon
    if iconName == "" then return nil end

    if not DistPadIconTexture then
        local searchPaths = {
            "/Game/Textures/GUI/Icons/icon_" .. iconName .. ".icon_" .. iconName,
            "/Game/Textures/GUI/icon_" .. iconName .. ".icon_" .. iconName,
        }
        for _, iconPath in ipairs(searchPaths) do
            local okLoad, texture = pcall(function() return StaticFindObject(iconPath) end)
            if okLoad and texture and texture:IsValid() then
                DistPadIconTexture = texture
                break
            end
        end
        if not DistPadIconTexture then
            Log.Debug("Failed to load icon texture: %s", iconName)
        end
    end

    if DistPadIconTexture then
        local size = Config.Indicator.IconSize
        pcall(function()
            newIcon:SetBrushFromTexture(DistPadIconTexture, false)
            newIcon:SetDesiredSizeOverride({ X = size, Y = size })
            newIcon:SetColorAndOpacity(Config.Indicator.IconColor)
        end)
    end

    DistPadIconWidget = newIcon
    return newIcon
end

local function HideDistPadIcon()
    if DistPadIconWidget and DistPadIconWidget:IsValid() then
        pcall(function() DistPadIconWidget:SetVisibility(1) end)
    end
end

local function ShowDistPadIcon(widget)
    local icon = GetOrCreateDistPadIcon(widget)
    if icon then pcall(function() icon:SetVisibility(4) end) end
end

-- Append indicator text to container name. Caches textBlock ref (called every frame).
local function AppendDistPadText(widget)
    if not Config.Indicator.TextEnabled or Config.Indicator.Text == "" then return end

    local okAddr, widgetAddr = pcall(function() return widget:GetAddress() end)
    if not okAddr or not widgetAddr then return end

    if widgetAddr ~= TextBlockCache.widgetAddr then
        local ok, tb = pcall(function() return widget.InteractionObjectName end)
        if ok and tb and tb:IsValid() then
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
-- CORE LOGIC
-- ============================================================

function DistributionPadTweaks.Init(config, log)
    Config = config
    Log = log

    local anyEnabled = Config.Range.Enabled or Config.Indicator.Enabled
    local status = anyEnabled and "Enabled" or "Disabled"
    Log.Info("DistPadTweaks - %s", status)
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

-- Register hooks that must exist before gameplay starts
function DistributionPadTweaks.RegisterPrePlayHooks()
    Log.Debug("RegisterPrePlayHooks called")

    -- Register to ReceiveBeginPlay for pads (both range and indicator features)
    if Config.Range.Enabled or Config.Indicator.Enabled then
        return HookUtil.RegisterABFDeployedReceiveBeginPlay(
            "Deployed_DistributionPad_C",
            DistributionPadTweaks.OnPadReceiveBeginPlay,
            Log
        )
    end

    return true
end

-- Register hooks for active gameplay (HUD, interactions)
function DistributionPadTweaks.RegisterInPlayHooks()
    Log.Debug("RegisterInPlayHooks called")
    local success = true

    -- Indicator feature hooks (gameplay only)
    if Config.Indicator.Enabled then
        success = HookUtil.Register({
            {
                path = "/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveEndPlay",
                callback = DistributionPadTweaks.OnReceiveEndPlay
            },
            {
                path = "/Game/Blueprints/Widgets/W_PlayerHUD_InteractionPrompt.W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts",
                callback = function(widget, ShowPressInteract, ShowHoldInteract, ShowPressPackage, ShowHoldPackage,
                                     ObjectUnderConstruction, ConstructionPercent, RequiresPower, Radioactive,
                                     ShowDescription, ExtraNoteLines, HitActorParam, HitComponentParam, RequiresPlug)
                    DistributionPadTweaks.OnUpdateInteractionPrompts(widget, HitActorParam)
                end
            },
        }, Log) and success

        -- Optional: refresh on container construction
        if Config.Indicator.RefreshOnBuiltContainer then
            success = HookUtil.Register(
                "/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:OnRep_ConstructionModeActive",
                DistributionPadTweaks.OnContainerConstructionComplete,
                Log
            ) and success
        end
    end

    Log.Debug("RegisterInPlayHooks complete (success: %s)", tostring(success))
    return success
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

-- Consolidated callback for pad BeginPlay (handles both range and indicator features)
function DistributionPadTweaks.OnPadReceiveBeginPlay(pad)
    Log.Debug("OnPadReceiveBeginPlay fired")

    -- Range feature
    if Config.Range.Enabled then
        DistributionPadTweaks.OnDistPadBeginPlay(pad)
    end

    -- Indicator feature
    if Config.Indicator.Enabled then
        DistributionPadTweaks.OnPadBeginPlay(pad)
    end
end

-- Adjusts pad range if enabled (Range feature)
function DistributionPadTweaks.OnDistPadBeginPlay(pad)
    if not pad:IsValid() or not Config.Range.Enabled then return end

    local okSphere, sphere = pcall(function() return pad.ContainerOverlapSphere end)
    if okSphere and sphere and sphere:IsValid() then
        local newRadius = 1000 * Config.Range.Multiplier
        pcall(function() sphere:SetSphereRadius(newRadius, true) end)
    end
end

-- Syncs each pad individually as it spawns (Indicator feature)
-- First pad also triggers OnRep_DistributionActive hook registration (Blueprint guaranteed loaded)
function DistributionPadTweaks.OnPadBeginPlay(pad)
    local okLoading, isLoading = pcall(function() return pad.IsCurrentlyLoadingFromSave end)
    isLoading = okLoading and isLoading or false

    -- Register OnRep_DistributionActive hook when first pad spawns (Blueprint now loaded)
    if not onRepHookRegistered then
        onRepHookRegistered = true
        ExecuteWithDelay(250, function()
            HookUtil.Register(
                "/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C:OnRep_DistributionActive",
                DistributionPadTweaks.OnRepDistributionActive,
                Log
            )
        end)
    end

    -- Wait for properties to replicate (longer delay if IsCurrentlyLoadingFromSave is true)
    ExecuteWithDelay(isLoading and 1000 or 500, function()
        ExecuteInGameThread(function()
            if not pad:IsValid() then return end
            Log.Debug("OnPadBeginPlay: syncing pad (isLoading=%s)", tostring(isLoading))
            SyncCacheFromPad(pad)
        end)
    end)
end

-- Called when pad's DistributionActive property replicates (late-bound hook)
function DistributionPadTweaks.OnRepDistributionActive(pad)
    local okActive, isActive = pcall(function() return pad.DistributionActive end)

    -- Only sync when someone steps ON the pad (true), not when stepping OFF (false)
    if okActive and isActive then
        Log.Debug("OnRep_DistributionActive: DistributionActive = true, syncing pad")
        DistributionPadTweaks.SyncPad(pad)
    end
end

-- Syncs a single pad's cache
-- TODO: Add HasAuthority check to skip UpdateCompatibleContainers on host (already called by native game)
function DistributionPadTweaks.SyncPad(pad)
    if not pad:IsValid() then return end
    if isSyncingCache then return end

    isSyncingCache = true

    local ok, err = pcall(function()
        Log.Debug("SyncPad: syncing cache for pad")
        SyncCacheFromPad(pad)

        -- Log cache state after sync
        local invCount = 0
        for _ in pairs(DistPadCache.inventories) do invCount = invCount + 1 end
        local padCount = 0
        for _ in pairs(TrackedPads) do padCount = padCount + 1 end
        Log.Debug("SyncPad: cache now has %d inventories, %d pads", invCount, padCount)
    end)

    isSyncingCache = false

    if not ok then
        Log.Debug("SyncPad failed: %s", tostring(err))
    end
end

-- Called from ReceiveEndPlay hook
function DistributionPadTweaks.OnReceiveEndPlay(actor)
    local okAddr, addr = pcall(function() return actor:GetAddress() end)
    if okAddr and addr and TrackedPads[addr] then
        PurgePadFromCache(actor)
    end
end

-- Per-frame hook: O(1) cache lookup instead of O(pads). Caches last actor to skip repeat lookups.
function DistributionPadTweaks.OnUpdateInteractionPrompts(widget, HitActorParam)
    local okHitActor, hitActor = pcall(function() return HitActorParam:get() end)
    if not okHitActor or not hitActor or not hitActor:IsValid() then
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

    -- Fast path: same actor as last frame
    if actorAddr == InteractionPromptCache.lastActorAddr then
        if InteractionPromptCache.lastActorInRange then
            AppendDistPadText(widget)
            ShowDistPadIcon(widget)
        else
            HideDistPadIcon()
        end
        return
    end

    -- New actor - full check
    InteractionPromptCache.lastActorAddr = actorAddr
    InteractionPromptCache.lastActorInRange = false

    local okInv, containerInv = pcall(function() return hitActor.ContainerInventory end)
    if not okInv or not containerInv or not containerInv:IsValid() then
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

-- Called from OnRep_ConstructionModeActive hook in main.lua
-- Detects when containers finish construction
-- Updates nearby pads to include the new container in their cache
function DistributionPadTweaks.OnContainerConstructionComplete(deployable)
    -- Skip if IsCurrentlyLoadingFromSave (shouldn't happen, but let's verify)
    local okLoading, isLoading = pcall(function() return deployable.IsCurrentlyLoadingFromSave end)
    if okLoading and isLoading then
        Log.Debug("Skipping container construction - IsCurrentlyLoadingFromSave == true")
        return
    end

    -- Only trigger when construction COMPLETES (ConstructionModeActive becomes false)
    local okActive, isActive = pcall(function() return deployable.ConstructionModeActive end)
    if not okActive or isActive then return end

    -- Check if it's a Container
    local okIsContainer, isContainer = pcall(function()
        return deployable:IsA("/Game/Blueprints/DeployedObjects/Furniture/Deployed_Container_ParentBP.Deployed_Container_ParentBP_C")
    end)
    if not okIsContainer or not isContainer then return end

    Log.Debug("OnContainerConstructionComplete: new container placed, updating nearby pads")

    local okContainerPos, containerPos = pcall(function() return deployable:K2_GetActorLocation() end)
    if not okContainerPos then return end

    -- Update nearby pads (avoids FindAllOf)
    local multiplier = Config.Range.Enabled and Config.Range.Multiplier or 1.0
    local rangeSquared = (1000 * multiplier * 1.10) ^ 2

    for _, padData in pairs(TrackedPads) do
        if padData.pad and padData.pad:IsValid() and padData.position then
            local dx = containerPos.X - padData.position.X
            local dy = containerPos.Y - padData.position.Y
            local dz = containerPos.Z - padData.position.Z
            if dx*dx + dy*dy + dz*dz <= rangeSquared then
                DistributionPadTweaks.SyncPad(padData.pad)
            end
        end
    end

    InteractionPromptCache.lastActorAddr = nil
end

-- Called on map transition to clear stale state
function DistributionPadTweaks.Cleanup()
    DistPadCache.inventories = {}
    TrackedPads = {}
    InteractionPromptCache.lastActorAddr = nil
    InteractionPromptCache.lastActorInRange = false
    TextBlockCache.widgetAddr = nil
    TextBlockCache.textBlock = nil
    DistPadIconTexture = nil

    -- TODO: Verify in LiveView that icon widget is destroyed when parent HUD is destroyed
    -- Currently we only clear references, assuming UE destroys children with parent.
    -- If widgets accumulate across map transitions, add RemoveFromParent() here.
    DistPadIconWidget = nil
end

return DistributionPadTweaks
