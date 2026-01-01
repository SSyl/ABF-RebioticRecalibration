local DistributionPadTweaks = {}

-- Module state (set during Init)
local Config = nil
local Log = nil

-- ============================================================
-- CACHE STATE
-- ============================================================

-- Cache: inventory addresses that are in ANY pad's range (reference counted)
local DistPadCache = {
    inventories = {},      -- [inventoryAddress] = count (number of pads covering this inventory)
}

-- Track which pads we've registered, so we can purge on EndPlay
local TrackedPadAddresses = {}  -- [padAddress] = {inventoryAddresses...}

-- Guard against re-entry during cache sync
local isSyncingCache = false

-- Cache: remember last actor we processed to avoid repeated lookups
local InteractionPromptCache = {
    lastActorAddr = nil,
    lastActorInRange = false,
}

-- Cached icon texture and widget for DistPad indicator
local DistPadIconTexture = nil
local DistPadIconWidget = nil

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

local function SyncCacheFromPad(pad)
    if not pad or not pad:IsValid() then return end

    local padAddr = pad:GetAddress()
    local oldInventories = TrackedPadAddresses[padAddr] or {}

    -- Decrement ref count for old inventories
    for _, invAddr in ipairs(oldInventories) do
        local count = DistPadCache.inventories[invAddr]
        if count and count > 1 then
            DistPadCache.inventories[invAddr] = count - 1
        else
            DistPadCache.inventories[invAddr] = nil
        end
    end

    -- Read current inventories from pad
    local newInventories = {}
    local okInvs, inventories = pcall(function()
        return pad.AdditionalInventories
    end)

    if okInvs and inventories then
        local invCount = #inventories
        for i = 1, invCount do
            local inv = inventories[i]
            if inv:IsValid() then
                local addr = inv:GetAddress()
                local currentCount = DistPadCache.inventories[addr] or 0
                DistPadCache.inventories[addr] = currentCount + 1
                table.insert(newInventories, addr)
            end
        end
        Log.Debug("SyncCacheFromPad: %d inventories from pad %s", #newInventories, tostring(padAddr))
    end

    TrackedPadAddresses[padAddr] = newInventories
end

local function PurgePadFromCache(pad)
    if not pad then return end

    local padAddr = pad:GetAddress()
    local inventories = TrackedPadAddresses[padAddr] or {}

    -- Decrement ref count for each inventory this pad covered
    for _, invAddr in ipairs(inventories) do
        local count = DistPadCache.inventories[invAddr]
        if count and count > 1 then
            DistPadCache.inventories[invAddr] = count - 1
        else
            DistPadCache.inventories[invAddr] = nil
        end
    end

    TrackedPadAddresses[padAddr] = nil
    Log.Debug("PurgePadFromCache: removed pad %s", tostring(padAddr))
end

-- Clone widget using Template parameter to copy all properties
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

-- Create or get the DistPad icon widget (cloned from RadioactiveIcon)
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
    if TrackedPadAddresses[addr] then
        PurgePadFromCache(actor)
    end
end

-- Called from RegisterHook("/Game/Blueprints/Widgets/W_PlayerHUD_InteractionPrompt.W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts") in main.lua
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
    Log.Debug("Container '%s' construction complete, refreshing all pads...", okClass and className or "unknown")

    local allPads = FindAllOf("Deployed_DistributionPad_C")
    if allPads then
        for _, pad in pairs(allPads) do
            if pad:IsValid() then
                pcall(function() pad:UpdateCompatibleContainers() end)
            end
        end
    end

    -- Reset interaction prompt cache to force re-check on next frame
    InteractionPromptCache.lastActorAddr = nil
end

-- Called from main.lua inside RegisterLoadMapPostHook to refresh cache after map loads
function DistributionPadTweaks.RefreshCache()
    DistPadCache.inventories = {}
    TrackedPadAddresses = {}

    local allPads = FindAllOf("Deployed_DistributionPad_C")
    if not allPads then
        Log.Debug("RefreshCache: No distribution pads found")
        return
    end

    local padCount = 0

    for _, pad in pairs(allPads) do
        if pad:IsValid() then
            padCount = padCount + 1
            pcall(function()
                pad:UpdateCompatibleContainers()
            end)
        end
    end

    -- Count total inventories
    local invCount = 0
    for _ in pairs(DistPadCache.inventories) do invCount = invCount + 1 end

    Log.Debug("RefreshCache: %d pads, %d inventories cached", padCount, invCount)
end

return DistributionPadTweaks
