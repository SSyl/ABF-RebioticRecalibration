--[[
============================================================================
BedsKeepSpawn - Sleep on Beds Without Changing Respawn Point
============================================================================

Adds tap-E interaction to beds that allows sleeping without setting the bed
as your respawn point. Long-press E remains unchanged (sleep + set respawn).

Only affects "real" beds (CanBeUsedAsSpawn == true), not cots/couches.

HOOKS:
- AbioticDeployed_Furniture_ParentBP_C:CanInteractWith_A (enable tap-E prompt for beds)
- AbioticDeployed_Furniture_ParentBP_C:InteractWith_A (handle tap-E sleep)

MECHANISM:
Temporarily sets CanBeUsedAsSpawn=false before calling LongInteractWith_A,
then restores it. This prevents SetNewBedOwner from assigning the respawn point.
]]

local HookUtil = require("utils/HookUtil")

-- ============================================================
-- MODULE METADATA
-- ============================================================

local Module = {
    name = "BedsKeepSpawn",
    configKey = "BedsKeepSpawn",
    serverSupport = true,  -- Interaction hooks need server authority

    schema = {
        { path = "Enabled", type = "boolean", default = true },
        { path = "PromptText", type = "string",  default = "just sleep", min = 1, max = 21, trim=true },
    },

    hookPoint = "Gameplay",
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

-- Cache for bed class (for IsA checks)
local bedParentClass = CreateInvalidObject()
local bedParentClassPath = "/Game/Blueprints/DeployedObjects/Furniture/Deployed_Furniture_Bed_ParentBP.Deployed_Furniture_Bed_ParentBP_C"

-- Caches to avoid per-frame spam
local CanInteractCache = {}  -- bedAddr -> true (already enabled)
local PromptCache = { lastActorAddr = nil, isBed = false }
local TextBlockCache = { widgetAddr = nil, textBlock = nil }

-- ============================================================
-- HELPERS
-- ============================================================

local function GetBedParentClass()
    if bedParentClass:IsValid() then
        return bedParentClass
    end

    bedParentClass = StaticFindObject(bedParentClassPath)
    if bedParentClass:IsValid() then
        Log.Debug("Cached bed parent class")
        return bedParentClass
    end

    return nil
end

local function IsBedWithSpawn(obj)
    -- Check if object is a bed (inherits from Deployed_Furniture_Bed_ParentBP_C)
    local bedClass = GetBedParentClass()
    if not bedClass then
        return false
    end

    if not obj:IsA(bedClass) then
        return false
    end

    -- Check if this bed can be used as spawn (real bed, not cot/couch)
    return obj.CanBeUsedAsSpawn == true
end

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("BedsKeepSpawn - %s", status)
end

function Module.GameplayCleanup()
    Log.Debug("Cleaning up BedsKeepSpawn state")
    bedParentClass = CreateInvalidObject()
    CanInteractCache = {}
    PromptCache = { lastActorAddr = nil, isBed = false }
    TextBlockCache = { widgetAddr = nil, textBlock = nil }
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function Module.RegisterHooks(isDedicatedServer)
    Log.Debug("RegisterHooks called (isDedicatedServer=%s)", tostring(isDedicatedServer))

    -- Hook CanInteractWith_A to enable tap-E prompt for beds
    local canInteractSuccess = HookUtil.Register(
        "/Game/Blueprints/DeployedObjects/Furniture/AbioticDeployed_Furniture_ParentBP.AbioticDeployed_Furniture_ParentBP_C:CanInteractWith_A",
        function(furniture, HitComponentParam, SuccessParam, OptionalCrosshairIconParam, OptionalTextLinesParam)
            Module.OnCanInteractA(furniture, HitComponentParam, SuccessParam)
        end,
        Log
    )

    -- Hook InteractWith_A to handle tap-E action
    local interactSuccess = HookUtil.Register(
        "/Game/Blueprints/DeployedObjects/Furniture/AbioticDeployed_Furniture_ParentBP.AbioticDeployed_Furniture_ParentBP_C:InteractWith_A",
        function(furniture, InteractingCharacterParam, ComponentUsedParam)
            Module.OnInteractA(furniture, InteractingCharacterParam, ComponentUsedParam)
        end,
        Log
    )

    -- Hook interaction prompt to change tap-E text for beds (client-only)
    local promptSuccess = true
    if not isDedicatedServer then
        promptSuccess = HookUtil.RegisterABFInteractionPromptUpdate(
            Module.OnUpdateInteractionPrompts,
            Log
        )
    end

    return canInteractSuccess and interactSuccess and promptSuccess
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnCanInteractA(furniture, HitComponentParam, SuccessParam)
    if not IsBedWithSpawn(furniture) then
        return
    end

    local bedAddr = furniture:GetAddress()

    -- Already enabled for this bed instance, just set and return
    if bedAddr and CanInteractCache[bedAddr] then
        SuccessParam:set(true)
        return
    end

    Log.Debug("OnCanInteractA: Bed detected, enabling tap-E prompt")
    SuccessParam:set(true)

    if bedAddr then
        CanInteractCache[bedAddr] = true
    end
end

function Module.OnUpdateInteractionPrompts(widget, HitActorParam)
    local okHitActor, hitActor = pcall(function() return HitActorParam:get() end)
    if not okHitActor or not hitActor:IsValid() then
        PromptCache.lastActorAddr = nil
        PromptCache.isBed = false
        return
    end

    local actorAddr = hitActor:GetAddress()
    if not actorAddr then
        PromptCache.lastActorAddr = nil
        PromptCache.isBed = false
        return
    end

    -- Check if we're still looking at the same actor
    if actorAddr == PromptCache.lastActorAddr then
        if not PromptCache.isBed then return end
    else
        PromptCache.lastActorAddr = actorAddr
        PromptCache.isBed = false

        if not IsBedWithSpawn(hitActor) then
            return
        end

        PromptCache.isBed = true
    end

    -- Get or cache the text block
    local widgetAddr = widget:GetAddress()
    if not widgetAddr then return end

    if widgetAddr ~= TextBlockCache.widgetAddr then
        local tb = widget.PressInteractSuffix
        if tb and tb:IsValid() then
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

    textBlock:SetText(FText(Config.PromptText))
end

function Module.OnInteractA(furniture, InteractingCharacterParam, ComponentUsedParam)
    if not IsBedWithSpawn(furniture) then
        return
    end

    local okChar, character = pcall(function() return InteractingCharacterParam:get() end)
    if not okChar or not character:IsValid() then
        Log.Debug("OnInteractA: Failed to get interacting character")
        return
    end

    Log.Debug("Tap-E sleep (no respawn)")

    -- Temporarily disable spawn capability so SetNewBedOwner skips respawn assignment
    furniture.CanBeUsedAsSpawn = false

    -- Trigger the normal sleep flow
    furniture:LongInteractWith_A(character)

    -- Restore spawn capability
    furniture.CanBeUsedAsSpawn = true

end

return Module
