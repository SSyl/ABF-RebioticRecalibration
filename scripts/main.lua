print("=== [QoL Tweaks] MOD LOADING ===\n")

local LogUtil = require("LogUtil")
local ConfigUtil = require("ConfigUtil")

local UserConfig = require("../config")
local Config = ConfigUtil.ValidateConfig(UserConfig)
local Log = LogUtil.CreateLogger("QoL Tweaks", Config)

-- ============================================================
-- FEATURE: Skip LAN Hosting Delay
-- ============================================================

local function GetPopupTitle(popup)
    local ok, titleText = pcall(function()
        return popup.Text_Title:GetText():ToString()
    end)
    return ok and titleText or nil
end

local function EnablePopupButtons(popup)
    local okYes, yesButton = pcall(function()
        return popup.Button_Yes
    end)
    if okYes and yesButton:IsValid() then
        pcall(function()
            yesButton:SetIsEnabled(true)
        end)
    end

    local okNo, noButton = pcall(function()
        return popup.Button_No
    end)
    if okNo and noButton:IsValid() then
        pcall(function()
            noButton:SetIsEnabled(true)
        end)
    end
end

local function ShouldSkipDelay(popup)
    if not popup:IsValid() then return false end

    local title = GetPopupTitle(popup)
    if title == "Hosting a LAN Server" then
        Log("Matched LAN hosting popup", "debug")
        return true
    end

    return false
end

local function RegisterLANPopupFix()
    if not Config.MenuTweaks.SkipLANHostingDelay then
        Log("LAN popup fix disabled", "debug")
        return
    end

    local okConstruct, errConstruct = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:Construct", function(Context)
            local popup = Context:get()
            if not popup:IsValid() then return end

            if ShouldSkipDelay(popup) then
                Log("Marking popup for delay skip", "debug")

                pcall(function()
                    popup.DelayBeforeAllowingInput = 0
                    popup.CloseBlockedByDelay = false
                    popup.DelayTimeLeft = 0
                end)

                EnablePopupButtons(popup)
            end
        end)
    end)

    if not okConstruct then
        Log("Failed to register Construct hook: " .. tostring(errConstruct), "error")
    else
        Log("LAN popup Construct hook registered", "debug")
    end

    local okCountdown, errCountdown = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:CountdownInputDelay", function(Context)
            local popup = Context:get()
            if not popup:IsValid() then return end

            if ShouldSkipDelay(popup) then
                Log("Blocking countdown tick", "debug")

                pcall(function()
                    popup.DelayTimeLeft = 0
                    popup.CloseBlockedByDelay = false
                end)

                EnablePopupButtons(popup)
            end
        end)
    end)

    if not okCountdown then
        Log("Failed to register CountdownInputDelay hook: " .. tostring(errCountdown), "error")
    else
        Log("LAN popup CountdownInputDelay hook registered", "debug")
    end
end

-- ============================================================
-- FEATURE: Fix Food Deployable Broken Texture
-- ============================================================

local function ResetDeployedDurability(deployable)
    if not deployable:IsValid() then return false end

    local okMax, maxDur = pcall(function()
        return deployable.MaxDurability
    end)
    if not okMax or maxDur == nil then
        Log("Failed to get MaxDurability", "debug")
        return false
    end

    local okCurrent, currentDur = pcall(function()
        return deployable.CurrentDurability
    end)

    if okCurrent and currentDur == maxDur then
        Log("Deployable already at max durability", "debug")
        return false
    end

    Log("Resetting durability from " .. tostring(currentDur) .. " to " .. tostring(maxDur), "debug")

    -- Fix both the ChangeableData (source) and CurrentDurability (deployed property)
    pcall(function()
        local changeableData = deployable.ChangeableData
        if changeableData then
            local maxItemDur = changeableData.MaxItemDurability_6_F5D5F0D64D4D6050CCCDE4869785012B
            if maxItemDur then
                changeableData.CurrentItemDurability_4_24B4D0E64E496B43FB8D3CA2B9D161C8 = maxItemDur
                Log("Fixed ChangeableData.CurrentItemDurability to " .. tostring(maxItemDur), "debug")
            end
        end
    end)

    pcall(function()
        deployable.CurrentDurability = maxDur
    end)

    return true
end

local function RegisterFoodDeployableFix()
    local foodConfig = Config.FoodDeployableFix
    if not foodConfig.Enabled then
        Log("Food deployable fix disabled", "debug")
        return
    end

    local clientVisualOnly = foodConfig.ClientSideVisualOnly
    local fixExistingOnLoad = foodConfig.FixExistingOnLoad

    local ok, err = pcall(function()
        RegisterHook("/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveBeginPlay", function(Context)
            local deployable = Context:get()
            if not deployable:IsValid() then return end

            local okClass, className = pcall(function()
                return deployable:GetClass():GetFName():ToString()
            end)
            if not okClass or not className:match("^Deployed_Food_") then return end

            Log(">>> Food deployable ReceiveBeginPlay: " .. className, "debug")

            -- Check authority (server/host has authority, clients don't)
            local okAuth, hasAuthority = pcall(function()
                return deployable:HasAuthority()
            end)

            if okAuth and hasAuthority then
                local okLoading, isLoading = pcall(function()
                    return deployable.IsCurrentlyLoadingFromSave
                end)

                if okLoading and isLoading and not fixExistingOnLoad then
                    Log("Skipping - loading from save (FixExistingOnLoad disabled)", "debug")
                    return
                end

                if ResetDeployedDurability(deployable) then
                    Log("Successfully reset durability", "debug")
                end
            elseif clientVisualOnly then
                -- Locally set durability to hide cracks (won't persist or replicate)
                Log("Client visual-only mode: hiding broken texture locally", "debug")
                pcall(function()
                    deployable.CurrentDurability = deployable.MaxDurability
                end)
            end
        end)
    end)

    if not ok then
        Log("Failed to register food deployable fix: " .. tostring(err), "error")
    else
        Log("Food deployable fix registered", "debug")
    end
end

-- ============================================================
-- INITIALIZATION
-- ============================================================

ExecuteWithDelay(2500, function()
    Log("Registering hooks...", "debug")

    RegisterLANPopupFix()
    RegisterFoodDeployableFix()

    Log("Hook registration complete", "debug")
end)

Log("Mod loaded", "debug")
