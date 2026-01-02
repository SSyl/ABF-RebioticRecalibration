--[[
============================================================================
FoodFix - Fix Visual Damage Cracks on Placed Food
============================================================================

PURPOSE:
When you place partially-decayed food from your inventory, the placed food
item shows visual damage cracks (the same cracks that appear on damaged
deployables). This is a visual bug - the food isn't actually damaged.

THE BUG:
Food items have two durability values:
1. Item durability (decay level when in inventory)
2. Deployed durability (physical damage when placed)

When placing food, the game incorrectly copies the inventory decay value
to the deployed durability, causing visual cracks.

HOW WE FIX IT:
On ReceiveBeginPlay for food deployables, we reset CurrentDurability to
MaxDurability (full health = no cracks). We also fix ChangeableData if present.

HOST vs CLIENT:
- Host: Full fix (has authority over the deployable)
- Client: Visual-only fix (just sets local CurrentDurability)

LOADING FROM SAVE:
The FixExistingOnLoad config controls whether we fix food that was placed
in a previous session. If enabled, we poll until IsCurrentlyLoadingFromSave
becomes false before applying the fix.

HOOKS (registered in main.lua via consolidated ReceiveBeginPlay hook):
- AbioticDeployed_ParentBP_C:ReceiveBeginPlay → OnBeginPlay()
  (only called for classes matching "Deployed_Food_*")

PERFORMANCE:
Only fires when food is placed or loaded - not per-frame.
]]

local FoodFix = {}

-- Module state (set during Init)
local Config = nil
local Log = nil

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

-- Resets a deployed food item's durability to max (removes visual cracks)
local function ResetDeployedDurability(deployable)
    if not deployable:IsValid() then return false end

    local okMax, maxDur = pcall(function()
        return deployable.MaxDurability
    end)
    if not okMax or maxDur == nil then
        Log.Debug("Failed to get MaxDurability")
        return false
    end

    local okCurrent, currentDur = pcall(function()
        return deployable.CurrentDurability
    end)

    if okCurrent and currentDur == maxDur then
        Log.Debug("Deployable already at max durability")
        return false
    end

    Log.Debug("Resetting durability from %s to %s", tostring(currentDur), tostring(maxDur))

    pcall(function()
        local changeableData = deployable.ChangeableData
        if changeableData then
            local maxItemDur = changeableData.MaxItemDurability_6_F5D5F0D64D4D6050CCCDE4869785012B
            if maxItemDur then
                changeableData.CurrentItemDurability_4_24B4D0E64E496B43FB8D3CA2B9D161C8 = maxItemDur
                Log.Debug("Fixed ChangeableData.CurrentItemDurability to %s", tostring(maxItemDur))
            end
        end
    end)

    pcall(function()
        deployable.CurrentDurability = maxDur
    end)

    return true
end

-- ============================================================
-- CORE LOGIC
-- ============================================================

function FoodFix.Init(config, log)
    Config = config
    Log = log
    Log.Debug("FoodFix initialized")
end

-- Called from consolidated RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveBeginPlay") in main.lua
-- Only called for Deployed_Food_* classes (filtering done in main.lua)
function FoodFix.OnBeginPlay(deployable)
    local okClass, className = pcall(function()
        return deployable:GetClass():GetFName():ToString()
    end)
    Log.Debug("Food deployable ReceiveBeginPlay: %s", okClass and className or "unknown")

    local okAuth, hasAuthority = pcall(function()
        return deployable:HasAuthority()
    end)

    if not okAuth then
        Log.Debug("Failed to check authority, skipping fix")
        return
    end

    if hasAuthority then
        local okLoading, isLoading = pcall(function()
            return deployable.IsCurrentlyLoadingFromSave
        end)

        if okLoading and isLoading then
            if not Config.FixExistingOnLoad then
                Log.Debug("Skipping - loading from save (FixExistingOnLoad disabled)")
                return
            end

            -- Poll until save loading completes
            local function WaitForLoad(attempts)
                if attempts > 20 then return end
                ExecuteWithDelay(100, function()
                    ExecuteInGameThread(function()
                        if not deployable:IsValid() then return end
                        local _, stillLoading = pcall(function()
                            return deployable.IsCurrentlyLoadingFromSave
                        end)
                        if stillLoading then
                            WaitForLoad(attempts + 1)
                        else
                            ResetDeployedDurability(deployable)
                        end
                    end)
                end)
            end
            WaitForLoad(0)
        else
            ResetDeployedDurability(deployable)
        end
    else
        Log.Debug("Client: applying visual-only fix locally")
        pcall(function()
            deployable.CurrentDurability = deployable.MaxDurability
        end)
    end
end

return FoodFix
