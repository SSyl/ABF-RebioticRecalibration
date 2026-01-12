--[[
============================================================================
FoodFix - Fix Visual Damage Cracks on Placed Food
============================================================================

Fixes visual bug where placed food shows damage cracks matching its decay %.
Game incorrectly copies inventory decay to deployed durability. On ReceiveBeginPlay,
resets CurrentDurability and ChangeableData to max values (full health = no cracks).

Multiplayer: Host applies full fix, clients apply visual-only fix.
Load from save: Polls IsCurrentlyLoadingFromSave before applying fix (if config enabled).

HOOKS: AbioticDeployed_ParentBP_C:ReceiveBeginPlay (^Deployed_Food_)
PERFORMANCE: Fires on food placement/load, not per-frame
]]

local HookUtil = require("utils/HookUtil")

-- ============================================================
-- MODULE METADATA
-- ============================================================

local Module = {
    name = "FoodFix",
    configKey = "FoodDisplayFix",

    schema = {
        { path = "Enabled", type = "boolean", default = true },
        { path = "FixExistingFoodOnLoad", type = "boolean", default = false },
    },

    hookPoint = "PreInit",
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

local function ResetDeployedDurability(deployable)
    if not deployable or not deployable:IsValid() then return false end

    local okMax, maxDur = pcall(function() return deployable.MaxDurability end)
    if not okMax or maxDur == nil then
        Log.Debug("Failed to get MaxDurability")
        return false
    end

    Log.Debug("Resetting durability to %s", tostring(maxDur))

    pcall(function()
        local changeableData = deployable.ChangeableData
        if not changeableData then return end
        local maxItemDur = changeableData.MaxItemDurability_6_F5D5F0D64D4D6050CCCDE4869785012B
        if not maxItemDur then return end
        changeableData.CurrentItemDurability_4_24B4D0E64E496B43FB8D3CA2B9D161C8 = maxItemDur
    end)

    pcall(function() deployable.CurrentDurability = maxDur end)
    return true
end

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("FoodFix - %s", status)
end

function Module.RegisterHooks()
    return HookUtil.RegisterABFDeployedReceiveBeginPlay(
        "^Deployed_Food_",
        Module.OnBeginPlay,
        Log
    )
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnBeginPlay(deployable)
    local okClass, className = pcall(function() return deployable:GetClass():GetFName():ToString() end)
    Log.Debug("Food deployable ReceiveBeginPlay: %s", okClass and className or "unknown")

    local okAuth, hasAuthority = pcall(function() return deployable:HasAuthority() end)
    if not okAuth then
        Log.Debug("Failed to check authority, skipping fix")
        return
    end

    if not hasAuthority then
        Log.Debug("Client: applying visual-only fix locally")
        pcall(function() deployable.CurrentDurability = deployable.MaxDurability end)
        return
    end

    local okLoading, isLoading = pcall(function() return deployable.IsCurrentlyLoadingFromSave end)
    if okLoading and isLoading and not Config.FixExistingFoodOnLoad then
        Log.Debug("Skipping - IsCurrentlyLoadingFromSave=true and FixExistingFoodOnLoad disabled")
        return
    end

    if okLoading and isLoading then
        local function WaitForLoad(attempts)
            if attempts > 20 then return end
            ExecuteWithDelay(100, function()
                ExecuteInGameThread(function()
                    if not deployable:IsValid() then return end
                    local _, stillLoading = pcall(function() return deployable.IsCurrentlyLoadingFromSave end)
                    if stillLoading then
                        WaitForLoad(attempts + 1)
                    else
                        ResetDeployedDurability(deployable)
                    end
                end)
            end)
        end
        WaitForLoad(0)
        return
    end

    ResetDeployedDurability(deployable)
end

return Module
