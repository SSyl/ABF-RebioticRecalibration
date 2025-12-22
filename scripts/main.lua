print("=== [QoL Tweaks] MOD LOADING ===\n")

local Config = require("../config")
local DEBUG = Config.Debug or false

local function Log(message, level)
    level = level or "info"

    if level == "debug" and not DEBUG then
        return
    end

    local prefix = ""
    if level == "error" then
        prefix = "ERROR: "
    elseif level == "warning" then
        prefix = "WARNING: "
    end

    print("[QoL Tweaks] " .. prefix .. tostring(message) .. "\n")
end

-- Cache for original button texts
local popupTextCache = {}

local function ShouldSkipDelay(popup)
    if not popup:IsValid() then return false end

    local ok, titleText = pcall(function()
        return popup.Text_Title:ToString()
    end)
    if ok and titleText then
        local title = titleText:lower()
        if title:find("lan") then
            Log("Matched by title: " .. titleText, "debug")
            return true
        end
    end

    local ok2, mainText = pcall(function()
        return popup.Text_Main:ToString()
    end)
    if ok2 and mainText then
        local main = mainText:lower()
        if main:find("local network") or main:find("lan game") then
            Log("Matched by main text (LAN)", "debug")
            return true
        end
    end

    return false
end

ExecuteWithDelay(2500, function()
    Log("Registering hooks...", "debug")

    local ok1, err1 = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:Construct", function(Context)
            local popup = Context:get()
            if not popup:IsValid() then return end

            if ShouldSkipDelay(popup) then
                Log("Marking popup for delay skip", "debug")

                local popupAddr = popup:GetAddress()

                -- Cache button text before countdown starts
                popupTextCache[popupAddr] = {}

                local ok1, yesText = pcall(function() return popup.Text_Yes end)
                local ok2, noText = pcall(function() return popup.Text_No end)

                if ok1 and yesText and yesText:IsValid() then
                    local yesTextWidget = popup.YesText
                    if yesTextWidget:IsValid() then
                        popupTextCache[popupAddr][yesTextWidget:GetAddress()] = yesText:ToString()
                        Log("Cached Yes text in Construct: " .. yesText:ToString(), "debug")
                    end
                end

                if ok2 and noText and noText:IsValid() then
                    local noTextWidget = popup.NoText
                    if noTextWidget:IsValid() then
                        popupTextCache[popupAddr][noTextWidget:GetAddress()] = noText:ToString()
                        Log("Cached No text in Construct: " .. noText:ToString(), "debug")
                    end
                end

                -- Construct is a post-callback, so this happens after construction completes
                pcall(function()
                    popup.DelayBeforeAllowingInput = 0
                    popup.CloseBlockedByDelay = false
                    popup.DelayTimeLeft = 0
                end)

                local ok, yesButton = pcall(function()
                    return popup.Button_Yes
                end)
                if ok and yesButton:IsValid() then
                    pcall(function()
                        yesButton:SetIsEnabled(true)
                    end)
                end

                local ok2, noButton = pcall(function()
                    return popup.Button_No
                end)
                if ok2 and noButton:IsValid() then
                    pcall(function()
                        noButton:SetIsEnabled(true)
                    end)
                end
            end
        end)
    end)

    if not ok1 then
        Log("Failed to register Construct hook: " .. tostring(err1), "error")
    else
        Log("Construct hook registered", "debug")
    end

    local ok2, err2 = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:CountdownInputDelay", function(Context)
            local popup = Context:get()
            if not popup:IsValid() then return end

            if ShouldSkipDelay(popup) then
                Log("Blocking countdown tick", "debug")

                pcall(function()
                    popup.DelayTimeLeft = 0
                    popup.CloseBlockedByDelay = false
                end)

                local ok, yesButton = pcall(function()
                    return popup.Button_Yes
                end)
                if ok and yesButton:IsValid() then
                    pcall(function()
                        yesButton:SetIsEnabled(true)
                    end)
                end

                local ok2, noButton = pcall(function()
                    return popup.Button_No
                end)
                if ok2 and noButton:IsValid() then
                    pcall(function()
                        noButton:SetIsEnabled(true)
                    end)
                end
            end
        end)
    end)

    if not ok2 then
        Log("Failed to register CountdownInputDelay hook: " .. tostring(err2), "error")
    else
        Log("CountdownInputDelay hook registered", "debug")
    end

    -- Strip countdown prefix like "(3) YES" -> "YES"
    local ok3, err3 = pcall(function()
        RegisterHook("/Game/Blueprints/Widgets/MenuSystem/W_MenuPopup_YesNo.W_MenuPopup_YesNo_C:UpdateButtonWithDelayTime", function(Context, TextParam, OriginalTextParam)
            local popup = Context:get()
            if not popup:IsValid() then return end

            local popupAddr = popup:GetAddress()
            local cache = popupTextCache[popupAddr]

            if cache then
                local textWidget = TextParam:get()
                if not textWidget:IsValid() then return end

                local ok, currentText = pcall(function()
                    return textWidget:GetText():ToString()
                end)

                if ok and currentText then
                    Log("Current button text: " .. currentText, "debug")

                    if currentText:find("%(") then
                        -- Strip countdown prefix: "(3) YES" -> "YES"
                        local cleanText = currentText:gsub("^%(%d+%)%s*", "")
                        Log("Cleaned text: " .. cleanText, "debug")

                        pcall(function()
                            textWidget:SetText(FText(cleanText))
                        end)
                    end
                end
            end
        end)
    end)

    if not ok3 then
        Log("Failed to register UpdateButtonWithDelayTime hook: " .. tostring(err3), "error")
    else
        Log("UpdateButtonWithDelayTime hook registered", "debug")
    end
end)

Log("Mod loaded", "debug")
