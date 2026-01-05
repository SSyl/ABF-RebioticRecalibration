local DistributionPadTweaks = {}

-- Module state (set during Init)
local Config = nil
local Log = nil

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
    if not pad or not pad:IsValid() then
        Log.Debug("SyncCacheFromPad: invalid pad")
        return
    end

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
                        Log.Debug("SyncCacheFromPad: added new inventory to cache")
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
    if not pad then return end

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
-- Clone existing widget via StaticConstructObject template param (copies all properties)

local function CloneWidget(templateWidget, parent, widgetName)
    local newWidget = StaticConstructObject(
        templateWidget:GetClass(), parent, FName(widgetName),
        0, 0, false, false, templateWidget
    )
    if not newWidget or not newWidget:IsValid() then
        Log.Debug("StaticConstructObject failed for %s", widgetName)
        return nil
    end

    local parentClass = parent:GetClass():GetFName():ToString()
    local ok, slot
    if parentClass == "Overlay" then
        ok, slot = pcall(function() return parent:AddChildToOverlay(newWidget) end)
    elseif parentClass == "HorizontalBox" then
        ok, slot = pcall(function() return parent:AddChildToHorizontalBox(newWidget) end)
    elseif parentClass == "VerticalBox" then
        ok, slot = pcall(function() return parent:AddChildToVerticalBox(newWidget) end)
    elseif parentClass == "CanvasPanel" then
        ok, slot = pcall(function() return parent:AddChildToCanvas(newWidget) end)
    else
        ok, slot = pcall(function() return parent:AddChild(newWidget) end)
    end

    if not ok or not slot then
        Log.Debug("Failed to add %s to %s", widgetName, parentClass)
        return nil
    end

    return newWidget, slot
end

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

    local newIcon, slot = CloneWidget(radioactiveIcon, parent, "DistPadIcon")
    if not newIcon then return nil end

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
end

-- Called from consolidated ReceiveBeginPlay hook in main.lua (filtered to DistributionPad)
function DistributionPadTweaks.OnDistPadBeginPlay(pad)
    if not pad:IsValid() or not Config.Range.Enabled then return end

    local okSphere, sphere = pcall(function() return pad.ContainerOverlapSphere end)
    if okSphere and sphere and sphere:IsValid() then
        local newRadius = 1000 * Config.Range.Multiplier
        pcall(function() sphere:SetSphereRadius(newRadius, true) end)
    end
end

-- Called from RegisterHook on UpdateCompatibleContainers in main.lua
function DistributionPadTweaks.OnUpdateCompatibleContainers(Context)
    if isSyncingCache then return end
    isSyncingCache = true

    local ok, err = pcall(function()
        local pad = Context:get()
        if pad and pad:IsValid() then
            Log.Debug("OnUpdateCompatibleContainers: syncing cache for pad")
            SyncCacheFromPad(pad)

            -- Log cache state after sync
            local invCount = 0
            for _ in pairs(DistPadCache.inventories) do invCount = invCount + 1 end
            local padCount = 0
            for _ in pairs(TrackedPads) do padCount = padCount + 1 end
            Log.Debug("OnUpdateCompatibleContainers: cache now has %d inventories, %d pads", invCount, padCount)
        end
    end)

    isSyncingCache = false

    if not ok then
        Log.Debug("OnUpdateCompatibleContainers failed: %s", tostring(err))
    end
end

-- Called from NotifyOnNewObject in main.lua
function DistributionPadTweaks.OnNewPadSpawned(pad)
    Log.Debug("OnNewPadSpawned called, hook registered: %s", tostring(DistributionPadTweaks.UpdateCompatibleContainersHooked))

    ExecuteWithDelay(1000, function()
        ExecuteInGameThread(function()
            if not pad:IsValid() then
                Log.Debug("OnNewPadSpawned: pad invalid after delay")
                return
            end

            Log.Debug("OnNewPadSpawned: calling UpdateCompatibleContainers")
            local ok, err = pcall(function() pad:UpdateCompatibleContainers() end)
            if not ok then
                Log.Debug("OnNewPadSpawned: UpdateCompatibleContainers failed: %s", tostring(err))
            end
        end)
    end)
end

-- Called from ReceiveEndPlay hook in main.lua
function DistributionPadTweaks.OnReceiveEndPlay(Context)
    local okActor, actor = pcall(function() return Context:get() end)
    if not okActor or not actor or not actor:IsValid() then return end

    local okAddr, addr = pcall(function() return actor:GetAddress() end)
    if okAddr and addr and TrackedPads[addr] then
        PurgePadFromCache(actor)
    end
end

-- Per-frame hook: O(1) cache lookup instead of O(pads). Caches last actor to skip repeat lookups.
function DistributionPadTweaks.OnUpdateInteractionPrompts(Context, HitActorParam)
    local widget = Context:get()
    if not widget or not widget:IsValid() then return end

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
-- Detects when containers or pads finish construction (not loading from save)
function DistributionPadTweaks.OnConstructionComplete(Context)
    local okGet, deployable = pcall(function() return Context:get() end)
    if not okGet or not deployable or not deployable:IsValid() then return end

    -- Skip objects loading from save
    local okLoading, isLoading = pcall(function() return deployable.IsCurrentlyLoadingFromSave end)
    if okLoading and isLoading then return end

    -- Only trigger when construction COMPLETES (ConstructionModeActive becomes false)
    local okActive, isActive = pcall(function() return deployable.ConstructionModeActive end)
    if not okActive or isActive then return end

    -- Check if it's a DistributionPad
    local okClass, className = pcall(function() return deployable:GetClass():GetFName():ToString() end)
    if okClass and className == "Deployed_DistributionPad_C" then
        Log.Debug("OnConstructionComplete: new DistributionPad placed, calling UpdateCompatibleContainers")
        pcall(function() deployable:UpdateCompatibleContainers() end)
        return
    end

    -- Check if it's a Container
    local okIsContainer, isContainer = pcall(function()
        return deployable:IsA("/Game/Blueprints/DeployedObjects/Furniture/Deployed_Container_ParentBP.Deployed_Container_ParentBP_C")
    end)
    if not okIsContainer or not isContainer then return end

    Log.Debug("OnConstructionComplete: new container placed, updating nearby pads")

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
                pcall(function() padData.pad:UpdateCompatibleContainers() end)
            end
        end
    end

    InteractionPromptCache.lastActorAddr = nil
end

-- Rebuild cache on map load. Only place we call FindAllOf (expensive).
-- UpdateCompatibleContainersHooked is set by main.lua when the hook registers
DistributionPadTweaks.UpdateCompatibleContainersHooked = false

function DistributionPadTweaks.RefreshCache(attempts)
    attempts = attempts or 0

    Log.Debug("RefreshCache called (attempt %d)", attempts + 1)

    -- Longer initial delay to allow client replication
    -- First attempt: 8 seconds to let clients fully replicate all pads
    -- Subsequent attempts: 2.5 seconds
    local delay = attempts == 0 and 8000 or 2500

    ExecuteWithDelay(delay, function()
        ExecuteInGameThread(function()
            Log.Debug("RefreshCache: executing after %dms delay (attempt %d)", delay, attempts + 1)

            -- Wait for hook to be ready before refreshing
            if not DistributionPadTweaks.UpdateCompatibleContainersHooked then
                if attempts < 15 then
                    Log.Debug("RefreshCache: waiting for hook (attempt %d/%d)", attempts + 1, 15)
                    DistributionPadTweaks.RefreshCache(attempts + 1)
                else
                    Log.Debug("RefreshCache: gave up waiting for hook after %d attempts", attempts + 1)
                end
                return
            end

            Log.Debug("RefreshCache: hook is ready, clearing cache and finding pads")
            DistPadCache.inventories = {}
            TrackedPads = {}

            local allPads = FindAllOf("Deployed_DistributionPad_C")

            -- Count valid pads
            local padCount = 0
            if allPads then
                for _, pad in pairs(allPads) do
                    if pad:IsValid() then
                        padCount = padCount + 1
                        Log.Debug("RefreshCache: triggering UpdateCompatibleContainers on pad %d", padCount)
                        pcall(function() pad:UpdateCompatibleContainers() end)
                    end
                end
            end

            Log.Debug("RefreshCache: found %d valid pads (attempt %d)", padCount, attempts + 1)

            -- Retry if no valid pads found (client replication may be delayed)
            if padCount == 0 and attempts < 5 then
                Log.Debug("RefreshCache: no pads found, retrying...")
                DistributionPadTweaks.RefreshCache(attempts + 1)
            elseif padCount == 0 then
                Log.Debug("RefreshCache: no pads found after %d attempts, giving up", attempts + 1)
            end
        end)
    end)
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
    DistPadIconWidget = nil
end

return DistributionPadTweaks
