local FoodFix = {}

-- Module state (set during Init)
local Config = nil
local Log = nil

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

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
