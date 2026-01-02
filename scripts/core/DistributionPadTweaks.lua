local DistributionPadTweaks = {}

-- Module state (set during Init)
local Config = nil
local Log = nil

-- ============================================================
-- CACHE STATE
-- ============================================================
--[[
    WHY WE NEED A CACHE:

    Distribution Pads let players access nearby containers from one spot.
    We want to show an indicator on containers that are in range of ANY pad.

    The naive approach would be: every frame, for each container the player
    looks at, loop through ALL pads and check if that container is in range.
    This is O(pads × containers) PER FRAME - way too slow.

    Instead, we maintain a cache that answers "is this container in any pad's
    range?" in O(1) time. The cache is updated only when pads change, not
    every frame.

    REFERENCE COUNTING:

    Multiple pads can cover the same container. If Pad A and Pad B both cover
    Container X, and then Pad A is destroyed, Container X should STILL show
    the indicator (because Pad B still covers it).

    We solve this with reference counting:
    - When a pad adds a container to its range: increment that container's count
    - When a pad removes a container from its range: decrement that container's count
    - When count reaches 0: remove from cache entirely

    This way, a container only leaves the cache when NO pads cover it.
]]

-- Maps inventory address → number of pads covering it
-- Example: { [0x12345] = 2, [0x67890] = 1 } means:
--   - Inventory at 0x12345 is covered by 2 pads
--   - Inventory at 0x67890 is covered by 1 pad
local DistPadCache = {
    inventories = {},
}

-- Maps pad address → information about that pad
-- We track each pad's inventories so we know what to decrement when the pad
-- is destroyed or its inventory list changes.
-- Example: { [0xABCDE] = { pad = <UObject>, position = <FVector>, inventories = {0x12345, 0x67890} } }
local TrackedPads = {}

--[[
    RE-ENTRY GUARD:

    In Unreal Engine multiplayer, accessing a replicated property (like
    AdditionalInventories) can sometimes trigger an OnRep callback, which
    might call UpdateCompatibleContainers again, causing infinite recursion.

    This flag prevents that: if we're already syncing, skip the nested call.
    This was added after observing actual freezes in multiplayer testing.
]]
local isSyncingCache = false

-- Per-frame optimization: remember the last actor we checked so we don't
-- repeat the cache lookup every single frame while looking at the same container
local InteractionPromptCache = {
    lastActorAddr = nil,      -- Address of the actor we last checked
    lastActorInRange = false, -- Was that actor in a pad's range?
}

-- Cached icon texture and widget for DistPad indicator
local DistPadIconTexture = nil
local DistPadIconWidget = nil

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

-- ============================================================
-- REFERENCE COUNT HELPERS
-- ============================================================
--[[
    These two functions manage the reference count for inventories in the cache.
    They encapsulate the increment/decrement logic so it's consistent everywhere.
]]

-- Increment the reference count for an inventory address.
-- Called when a pad newly covers this inventory.
local function IncrementInventoryRefCount(inventoryAddr)
    local currentCount = DistPadCache.inventories[inventoryAddr] or 0
    DistPadCache.inventories[inventoryAddr] = currentCount + 1
end

-- Decrement the reference count for an inventory address.
-- Called when a pad no longer covers this inventory.
-- If count reaches 0, remove from cache entirely (no pads cover it anymore).
local function DecrementInventoryRefCount(inventoryAddr)
    local currentCount = DistPadCache.inventories[inventoryAddr]
    if not currentCount then return end  -- Already not in cache, nothing to do

    if currentCount > 1 then
        DistPadCache.inventories[inventoryAddr] = currentCount - 1
    else
        -- Count would become 0, so remove entirely
        DistPadCache.inventories[inventoryAddr] = nil
    end
end

-- ============================================================
-- CACHE SYNCHRONIZATION (DELTA-BASED)
-- ============================================================
--[[
    SyncCacheFromPad: Updates our cache when a pad's inventory list changes.

    WHY DELTA-BASED?

    The game calls UpdateCompatibleContainers frequently - sometimes even when
    nothing has actually changed (e.g., player walks on pad trigger). The naive
    approach would be:
      1. Decrement ALL old inventory ref counts
      2. Increment ALL new inventory ref counts

    If the pad covers 20 containers and nothing changed, that's 40 wasted
    operations every time the hook fires. With the hook firing rapidly, this
    adds up to significant CPU waste.

    THE DELTA APPROACH:

    Instead of blindly decrementing everything and re-incrementing everything,
    we figure out what ACTUALLY changed:
      - Which inventories were ADDED? (in new list but not old) → increment only these
      - Which inventories were REMOVED? (in old list but not new) → decrement only these
      - Which inventories are UNCHANGED? (in both lists) → do nothing

    If nothing changed, we do 0 ref count operations instead of 2N.

    HOW IT WORKS (Set Difference Algorithm):

    1. Build a "lookup set" from old inventories: oldSet[addr] = true
    2. Loop through new inventories:
       - If addr is in oldSet: it's UNCHANGED, remove from oldSet (consume it)
       - If addr is NOT in oldSet: it's ADDED, increment ref count
    3. After the loop, anything still in oldSet was not in new list = REMOVED
       - Decrement ref count for each remaining item in oldSet

    This is O(N) instead of O(2N), and more importantly, if nothing changed,
    we skip all ref count operations entirely.
]]
local function SyncCacheFromPad(pad)
    if not pad or not pad:IsValid() then return end

    local padAddr = pad:GetAddress()
    local padData = TrackedPads[padAddr]
    local oldInventoryAddresses = (padData and padData.inventories) or {}

    -- STEP 1: Build a lookup set from old inventories for O(1) membership checks
    -- Using a table as a set: oldInventorySet[addr] = true means "addr was in old list"
    local oldInventorySet = {}
    for _, addr in ipairs(oldInventoryAddresses) do
        oldInventorySet[addr] = true
    end

    -- STEP 2: Read current inventories from the pad and detect changes
    local newInventoryAddresses = {}  -- Will hold the updated list
    local numAddedInventories = 0     -- Count for logging
    local numRemovedInventories = 0   -- Count for logging

    local readSuccess, inventoryArray = pcall(function()
        return pad.AdditionalInventories
    end)

    if readSuccess and inventoryArray then
        for i = 1, #inventoryArray do
            local inventory = inventoryArray[i]
            if inventory and inventory:IsValid() then
                local addr = inventory:GetAddress()

                -- Add to our new list (regardless of whether it's new or unchanged)
                newInventoryAddresses[#newInventoryAddresses + 1] = addr

                -- Check if this inventory was already covered by this pad
                if oldInventorySet[addr] then
                    -- UNCHANGED: This inventory was in the old list too.
                    -- Remove from oldInventorySet so we know it's accounted for.
                    -- No ref count change needed.
                    oldInventorySet[addr] = nil
                else
                    -- ADDED: This inventory is new (wasn't in old list).
                    -- Increment its ref count.
                    IncrementInventoryRefCount(addr)
                    numAddedInventories = numAddedInventories + 1
                end
            end
        end
    end

    -- STEP 3: Handle removed inventories
    -- Anything still in oldInventorySet was in the old list but NOT in the new list.
    -- These inventories are no longer covered by this pad → decrement their ref counts.
    for addr in pairs(oldInventorySet) do
        DecrementInventoryRefCount(addr)
        numRemovedInventories = numRemovedInventories + 1
    end

    -- STEP 4: Update the pad's position (used for distance checks elsewhere)
    local positionReadSuccess, position = pcall(function()
        return pad:K2_GetActorLocation()
    end)

    -- Log only if something actually changed (reduces log noise)
    if numAddedInventories > 0 or numRemovedInventories > 0 then
        Log.Debug("SyncCacheFromPad: pad %s changed (+%d/-%d, total=%d)",
                  tostring(padAddr), numAddedInventories, numRemovedInventories, #newInventoryAddresses)
    end

    -- STEP 5: Always update TrackedPads with fresh data
    -- Even if inventories didn't change, the pad object or position might have.
    -- We also store the new inventory list for the next sync comparison.
    TrackedPads[padAddr] = {
        pad = pad,
        position = positionReadSuccess and position or nil,
        inventories = newInventoryAddresses
    }
end

--[[
    PurgePadFromCache: Completely removes a pad from our tracking system.

    Called when a pad is destroyed (ReceiveEndPlay). We need to:
    1. Decrement ref counts for all inventories this pad was covering
    2. Remove the pad from TrackedPads entirely

    This ensures that if a pad is destroyed, any inventories it was covering
    will have their ref counts correctly decremented. If this was the only
    pad covering a particular container, that container will no longer show
    the indicator (which is correct behavior).
]]
local function PurgePadFromCache(pad)
    if not pad then return end

    local padAddr = pad:GetAddress()
    local padData = TrackedPads[padAddr]

    -- If we weren't tracking this pad, nothing to do
    if not padData then return end

    local inventoryAddresses = padData.inventories or {}

    -- Decrement ref count for each inventory this pad was covering
    for _, invAddr in ipairs(inventoryAddresses) do
        DecrementInventoryRefCount(invAddr)
    end

    -- Remove pad from our tracking table
    TrackedPads[padAddr] = nil

    Log.Debug("PurgePadFromCache: removed pad %s (%d inventories decremented)",
              tostring(padAddr), #inventoryAddresses)
end

-- ============================================================
-- WIDGET HELPERS
-- ============================================================
--[[
    CloneWidget: Creates a copy of an existing UE widget.

    Why cloning? Unreal widgets are complex objects with many properties.
    Rather than manually creating and configuring a widget from scratch
    (which would require setting dozens of properties), we clone an existing
    similar widget and modify just what we need.

    The template parameter in StaticConstructObject copies all properties
    from the source widget to the new widget.
]]
local function CloneWidget(templateWidget, parent, widgetName)
    local widgetClass = templateWidget:GetClass()
    local newWidget = StaticConstructObject(
        widgetClass,
        parent,
        FName(widgetName),
        0, 0, false, false,
        templateWidget  -- Template parameter - copies all properties
    )

    if not newWidget or not newWidget:IsValid() then
        Log.Debug("StaticConstructObject failed")
        return nil
    end

    -- Add to parent using appropriate method based on parent type
    local parentClassName = parent:GetClass():GetFName():ToString()
    Log.Debug("Parent class: %s", parentClassName)

    local ok, slot
    if parentClassName == "Overlay" then
        ok, slot = pcall(function() return parent:AddChildToOverlay(newWidget) end)
    elseif parentClassName == "HorizontalBox" then
        ok, slot = pcall(function() return parent:AddChildToHorizontalBox(newWidget) end)
    elseif parentClassName == "VerticalBox" then
        ok, slot = pcall(function() return parent:AddChildToVerticalBox(newWidget) end)
    elseif parentClassName == "CanvasPanel" then
        ok, slot = pcall(function() return parent:AddChildToCanvas(newWidget) end)
    else
        ok, slot = pcall(function() return parent:AddChild(newWidget) end)
    end

    if not ok or not slot then
        Log.Debug("Failed to add child to %s", parentClassName)
        return nil
    end

    return newWidget, slot
end

--[[
    GetOrCreateDistPadIcon: Lazily creates the indicator icon widget.

    We clone the existing RadioactiveIcon widget (which is already in the
    interaction prompt HUD) because it has all the right properties for
    an icon display. Then we customize it with our own texture and color.

    The widget is cached - once created, it persists until Cleanup() is called.
    This avoids creating a new widget every frame.
]]
local function GetOrCreateDistPadIcon(widget)
    if not Config.Indicator.IconEnabled then
        return nil
    end

    -- Return cached widget if still valid
    if DistPadIconWidget and DistPadIconWidget:IsValid() then
        return DistPadIconWidget
    end

    Log.Debug("Creating DistPad icon widget...")

    local okRadio, radioactiveIcon = pcall(function()
        return widget.RadioactiveIcon
    end)
    if not okRadio or not radioactiveIcon or not radioactiveIcon:IsValid() then
        Log.Debug("Failed to get RadioactiveIcon directly: okRadio=%s", tostring(okRadio))
        return nil
    end
    Log.Debug("Got RadioactiveIcon: %s", radioactiveIcon:GetFullName())

    local okParent, parent = pcall(function()
        return radioactiveIcon:GetParent()
    end)
    if not okParent or not parent or not parent:IsValid() then
        Log.Debug("Failed to get parent")
        return nil
    end
    Log.Debug("Got parent: %s", parent:GetFullName())

    local newIcon, slot = CloneWidget(radioactiveIcon, parent, "DistPadIcon")
    if not newIcon then
        Log.Debug("CloneWidget returned nil")
        return nil
    end
    Log.Debug("Created clone: %s", newIcon:GetFullName())

    -- Position icon: Center-Left alignment with offset
    if slot and slot:IsValid() then
        pcall(function()
            slot:SetHorizontalAlignment(1) -- Left
            slot:SetVerticalAlignment(2)   -- Center
            slot:SetPadding({ Left = -40, Top = -225, Right = 0, Bottom = 0 })
        end)
        Log.Debug("Set slot alignment and padding")
    end

    -- Load and set texture from config
    local iconName = Config.Indicator.Icon
    if iconName == "" then
        Log.Debug("Icon disabled in config")
        return nil
    end

    if not DistPadIconTexture then
        local iconPath = "/Game/Textures/GUI/Icons/" .. iconName .. "." .. iconName
        local okLoad, texture = pcall(function()
            return StaticFindObject(iconPath)
        end)
        if okLoad and texture and texture:IsValid() then
            DistPadIconTexture = texture
            Log.Debug("Loaded icon texture: %s", iconName)
        else
            Log.Debug("Failed to load icon texture: %s", iconPath)
        end
    end

    if DistPadIconTexture then
        pcall(function()
            newIcon:SetBrushFromTexture(DistPadIconTexture, false)
            newIcon:SetDesiredSizeOverride({ X = 32, Y = 32 })
            newIcon:SetColorAndOpacity(Config.Indicator.IconColor)
        end)
        Log.Debug("Set texture, size, and color on icon")
    end

    DistPadIconWidget = newIcon
    return newIcon
end

local function HideDistPadIcon()
    if DistPadIconWidget and DistPadIconWidget:IsValid() then
        pcall(function()
            DistPadIconWidget:SetVisibility(1) -- Collapsed
        end)
    end
end

local function ShowDistPadIcon(widget)
    local icon = GetOrCreateDistPadIcon(widget)
    if not icon then return end

    pcall(function()
        icon:SetVisibility(4) -- SelfHitTestInvisible
    end)
end

local function AppendDistPadText(widget)
    local indicatorConfig = Config.Indicator
    if not indicatorConfig.TextEnabled then return end
    if indicatorConfig.Text == "" then return end

    local okText, textBlock = pcall(function() return widget.InteractionObjectName end)
    if not okText or not textBlock or not textBlock:IsValid() then return end

    local okGet, currentText = pcall(function() return textBlock:GetText():ToString() end)
    if not okGet or not currentText then return end

    if currentText:match(indicatorConfig.TextPattern) then return end

    pcall(function()
        textBlock:SetText(FText(currentText .. " " .. indicatorConfig.Text))
    end)
end

-- ============================================================
-- CORE LOGIC
-- ============================================================

function DistributionPadTweaks.Init(config, log)
    Config = config
    Log = log
    Log.Debug("DistributionPadTweaks initialized")
end

-- Called from consolidated RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveBeginPlay") in main.lua
-- Only called for Deployed_DistributionPad_C (filtering done in main.lua)
function DistributionPadTweaks.OnDistPadBeginPlay(pad)
    local rangeConfig = Config.Range
    if not rangeConfig.Enabled then return end

    local multiplier = rangeConfig.Multiplier
    local defaultRadius = 1000
    local newRadius = defaultRadius * multiplier

    local okSphere, sphere = pcall(function()
        return pad.ContainerOverlapSphere
    end)

    if okSphere and sphere:IsValid() then
        pcall(function()
            sphere:SetSphereRadius(newRadius, true)
        end)
        Log.Debug("Set DistributionPad radius: %.0f -> %.0f units", defaultRadius, newRadius)
    end
end

-- Called from RegisterHook("/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C:UpdateCompatibleContainers") in main.lua
function DistributionPadTweaks.OnUpdateCompatibleContainers(Context)
    if isSyncingCache then return end
    isSyncingCache = true
    local pad = Context:get()
    SyncCacheFromPad(pad)
    isSyncingCache = false
end

-- Called from NotifyOnNewObject("/Game/Blueprints/DeployedObjects/Misc/Deployed_DistributionPad.Deployed_DistributionPad_C") in main.lua
function DistributionPadTweaks.OnNewPadSpawned(pad)
    Log.Debug("New DistributionPad spawned: %s", tostring(pad:GetAddress()))
    ExecuteWithDelay(1000, function()
        ExecuteInGameThread(function()
            if pad:IsValid() then
                pcall(function() pad:UpdateCompatibleContainers() end)
            end
        end)
    end)
end

-- Called from RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveEndPlay") in main.lua
function DistributionPadTweaks.OnReceiveEndPlay(Context)
    local actor = Context:get()
    if not actor then return end

    local addr = actor:GetAddress()
    if TrackedPads[addr] then
        PurgePadFromCache(actor)
    end
end

--[[
    OnUpdateInteractionPrompts: Per-frame hook that shows/hides the indicator.

    THIS IS WHERE THE CACHE OPTIMIZATION PAYS OFF.

    This function is called EVERY FRAME while the player is looking at something.
    Without our cache, we'd have to loop through all pads every frame to check
    if this container is in range of any of them. With the cache, we just do
    a single O(1) table lookup: DistPadCache.inventories[containerAddress].

    We also cache the last actor we checked (InteractionPromptCache) to avoid
    repeating the lookup when the player is still looking at the same container.
    This makes the common case (staring at a container) nearly free.

    Flow:
    1. Get the actor the player is looking at (HitActorParam)
    2. Fast path: if same actor as last frame, use cached result
    3. Slow path: check if actor has ContainerInventory, look up in cache
    4. If in cache, show icon/text. If not, hide.
]]
function DistributionPadTweaks.OnUpdateInteractionPrompts(Context, HitActorParam)
    local widget = Context:get()
    if not widget:IsValid() then return end

    local okHitActor, hitActor = pcall(function()
        return HitActorParam:get()
    end)

    if not okHitActor or not hitActor or not hitActor:IsValid() then
        InteractionPromptCache.lastActorAddr = nil
        InteractionPromptCache.lastActorInRange = false
        HideDistPadIcon()
        return
    end

    local actorAddr = hitActor:GetAddress()

    -- Fast path: same actor as last frame
    if actorAddr == InteractionPromptCache.lastActorAddr then
        if not InteractionPromptCache.lastActorInRange then
            HideDistPadIcon()
            return
        end
        -- Still in range - apply indicators (vanilla resets text each frame)
        AppendDistPadText(widget)
        ShowDistPadIcon(widget)
        return
    end

    -- New actor - do full check
    InteractionPromptCache.lastActorAddr = actorAddr
    InteractionPromptCache.lastActorInRange = false

    -- Check if it's a container (has ContainerInventory)
    local okInv, containerInv = pcall(function()
        return hitActor.ContainerInventory
    end)

    if not okInv or not containerInv or not containerInv:IsValid() then
        HideDistPadIcon()
        return
    end

    -- Check cache
    local invAddr = containerInv:GetAddress()
    local inRange = DistPadCache.inventories[invAddr] ~= nil

    if not inRange then
        HideDistPadIcon()
        return
    end

    InteractionPromptCache.lastActorInRange = true

    -- Apply indicators
    AppendDistPadText(widget)
    ShowDistPadIcon(widget)
end

-- Called from RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:OnRep_ConstructionModeActive") in main.lua
function DistributionPadTweaks.OnContainerConstructionComplete(Context)
    local deployable = Context:get()
    if not deployable:IsValid() then return end

    -- Only trigger when construction COMPLETES (ConstructionModeActive becomes false)
    local okActive, isActive = pcall(function() return deployable.ConstructionModeActive end)
    if not okActive or isActive then return end

    -- Filter: only care about containers
    local okIsContainer, isContainer = pcall(function()
        return deployable:IsA("/Game/Blueprints/DeployedObjects/Furniture/Deployed_Container_ParentBP.Deployed_Container_ParentBP_C")
    end)
    if not okIsContainer or not isContainer then return end

    local okClass, className = pcall(function()
        return deployable:GetClass():GetFName():ToString()
    end)

    -- Get container position for distance check
    local okContainerPos, containerPos = pcall(function()
        return deployable:K2_GetActorLocation()
    end)
    if not okContainerPos then
        Log.Debug("Container '%s' built but couldn't get position, skipping pad refresh", okClass and className or "unknown")
        return
    end

    -- Check cached pads within range (avoids FindAllOf)
    local multiplier = Config.Range.Enabled and Config.Range.Multiplier or 1.0
    local rangeSquared = (1000 * multiplier * 1.10) ^ 2  -- Base range * multiplier + 10% buffer
    local updatedCount = 0

    for _, padData in pairs(TrackedPads) do
        if padData.pad and padData.pad:IsValid() and padData.position then
            local dx = containerPos.X - padData.position.X
            local dy = containerPos.Y - padData.position.Y
            local dz = containerPos.Z - padData.position.Z
            local distSq = dx*dx + dy*dy + dz*dz

            if distSq <= rangeSquared then
                pcall(function() padData.pad:UpdateCompatibleContainers() end)
                updatedCount = updatedCount + 1
            end
        end
    end

    Log.Debug("Container '%s' construction complete, updated %d nearby pads", okClass and className or "unknown", updatedCount)

    -- Reset interaction prompt cache to force re-check on next frame
    InteractionPromptCache.lastActorAddr = nil
end

--[[
    RefreshCache: Rebuilds the entire cache from scratch.

    Called when a map loads. We can't assume the cache from the previous map
    is still valid (different map = different pads and containers), so we:
    1. Clear all cached data
    2. Find all distribution pads in the world
    3. Ask each pad to update its container list (which triggers our hooks)

    This is the ONLY place we call FindAllOf (expensive). After this initial
    population, we rely on hooks to keep the cache updated incrementally.
]]
function DistributionPadTweaks.RefreshCache()
    -- Clear all existing cache data (stale from previous map)
    DistPadCache.inventories = {}
    TrackedPads = {}

    -- Find all distribution pads currently in the world
    local allPads = FindAllOf("Deployed_DistributionPad_C")
    if not allPads then
        Log.Debug("RefreshCache: No distribution pads found")
        return
    end

    local padCount = 0

    -- Ask each pad to update its container list
    -- This will trigger our UpdateCompatibleContainers hook for each pad,
    -- which will call SyncCacheFromPad and populate our cache
    for _, pad in pairs(allPads) do
        if pad:IsValid() then
            padCount = padCount + 1
            pcall(function()
                pad:UpdateCompatibleContainers()
            end)
        end
    end

    -- Count total unique inventories for logging
    local invCount = 0
    for _ in pairs(DistPadCache.inventories) do invCount = invCount + 1 end

    Log.Debug("RefreshCache: %d pads, %d unique inventories cached", padCount, invCount)
end

--[[
    Cleanup: Resets all module state.

    Called when returning to main menu (via main.lua's LoadMapPostHook).
    Clears cached data and widget references to prevent stale state.

    Similar to LowHealthVignette.Cleanup() - ensures clean state between sessions.
]]
function DistributionPadTweaks.Cleanup()
    Log.Debug("Cleanup: Clearing DistPad cache and widget state")

    -- Clear all cache data
    DistPadCache.inventories = {}
    TrackedPads = {}

    -- Clear interaction prompt cache
    InteractionPromptCache.lastActorAddr = nil
    InteractionPromptCache.lastActorInRange = false

    -- Clear widget references (will be recreated when needed)
    DistPadIconTexture = nil
    DistPadIconWidget = nil
end

return DistributionPadTweaks
