--[[
============================================================================
WristwatchCustomization - Portal Reset Day Awareness
============================================================================

Features:
1. Highlight Sunday/Wednesday dots to indicate portal reset days (brighter alpha)
2. Change Daytime/Nightfall text to "RESET DAY"/"RESET PM" on eve/reset days
3. Tint watch background color (persistent and/or portal eve only)
4. Play extra beep at daybreak/nightfall on portal eve/reset days
]]

local HookUtil = require("utils/HookUtil")

local Module = {
    name = "WristwatchCustomization",
    configKey = "WristwatchCustomization",
    schema = {
        { path = "Enabled", type = "boolean", default = true },

        -- Which days portals reset (comma-separated: Sunday,Wednesday)
        { path = "PortalResetDays", type = "string", default = "Sunday,Wednesday" },

        -- Weekday dot indicators for portal reset days
        { path = "WeekDayDots.Enabled", type = "boolean", default = true },
        { path = "WeekDayDots.Alpha", type = "number", default = 0.7, min = 0.0, max = 1.0 },

        -- Text change on portal-related days
        { path = "DayNightText.Enabled", type = "boolean", default = true },
        { path = "DayNightText.Daytime", type = "string", default = "RESET DAY" },
        { path = "DayNightText.Nightfall", type = "string", default = "RESET PM" },
        { path = "DayNightText.When", type = "string", default = "Eve" },  -- "Eve" or "Reset"

        -- Background tint (persistent - always on)
        { path = "Background.Persistent.Enabled", type = "boolean", default = false },
        { path = "Background.Persistent.Color", type = "widgetColor", default = { R = 64, G = 255, B = 32 } },
        { path = "Background.Persistent.Intensity", type = "number", default = 2.0, min = 0.5, max = 5.0 },

        -- Background tint (portal days - overrides persistent)
        { path = "Background.Portal.Enabled", type = "boolean", default = false },
        { path = "Background.Portal.Color", type = "widgetColor", default = { R = 255, G = 64, B = 6 } },
        { path = "Background.Portal.Intensity", type = "number", default = 2.0, min = 0.5, max = 5.0 },
        { path = "Background.Portal.When", type = "string", default = "Eve" },  -- "Eve" or "Reset"

        -- Audio beep at daybreak/nightfall on portal-related days
        { path = "PortalResetBeep.Enabled", type = "boolean", default = true },
        { path = "PortalResetBeep.When", type = "string", default = "Eve" },  -- "Eve" or "Reset"
    },
    hookPoint = "Gameplay",
}

local Config = nil
local Log = nil

local currentDayOfWeek = -1
local initialSetupDone = false

-- Day name to index mapping
local DAY_NAME_TO_INDEX = {
    monday = 0,
    tuesday = 1,
    wednesday = 2,
    thursday = 3,
    friday = 4,
    saturday = 5,
    sunday = 6,
}

-- Weekday dot widget names
local WEEKDAY_DOT_NAMES = {
    [0] = "MondayDot",
    [1] = "TuesdayDot",
    [2] = "WednesdayDot",
    [3] = "ThursdayDot",
    [4] = "FridayDot",
    [5] = "SaturdayDot",
    [6] = "SundayDot",
}

-- Computed from config during Init
local PORTAL_RESET_DAYS = {}
local PORTAL_EVE_DAYS = {}

local function parsePortalResetDays(configString)
    local resetDays = {}
    local eveDays = {}

    for dayName in configString:gmatch("[^,]+") do
        dayName = dayName:match("^%s*(.-)%s*$"):lower()  -- trim and lowercase
        local dayIndex = DAY_NAME_TO_INDEX[dayName]
        if dayIndex then
            resetDays[dayIndex] = true
            local eveIndex = (dayIndex - 1) % 7
            eveDays[eveIndex] = true
        end
    end

    return resetDays, eveDays
end

function Module.Init(config, log)
    Config = config
    Log = log

    PORTAL_RESET_DAYS, PORTAL_EVE_DAYS = parsePortalResetDays(Config.PortalResetDays or "Sunday,Wednesday")

    Log.Info("WristwatchCustomization - %s", Config.Enabled and "Enabled" or "Disabled")
end

-- Current day dot: solid black, full alpha
local DOT_COLOR_CURRENT = {R = 0.0, G = 0.0, B = 0.0, A = 1.0}

local function applyDayDotStyling(wristwatch)
    if not Config.WeekDayDots or not Config.WeekDayDots.Enabled then return end

    local dotColorOther = {R = 0.006, G = 0.006, B = 0.006, A = Config.WeekDayDots.Alpha}

    for dayIndex, dotName in pairs(WEEKDAY_DOT_NAMES) do
        if PORTAL_RESET_DAYS[dayIndex] then
            local dot = wristwatch[dotName]
            if dot:IsValid() then
                if dayIndex == currentDayOfWeek then
                    dot:SetColorAndOpacity(DOT_COLOR_CURRENT)
                else
                    dot:SetColorAndOpacity(dotColorOther)
                end
                Log.Debug("[WeekDayDots] Set %s", dotName)
            end
        end
    end
end

local function isTextDay()
    if not Config.DayNightText or not Config.DayNightText.Enabled then return false end
    local when = (Config.DayNightText.When or "Eve"):lower()
    if when == "eve" then
        return PORTAL_EVE_DAYS[currentDayOfWeek]
    else
        return PORTAL_RESET_DAYS[currentDayOfWeek]
    end
end

local function isBeepDay()
    if not Config.PortalResetBeep or not Config.PortalResetBeep.Enabled then return false end
    local when = (Config.PortalResetBeep.When or "Eve"):lower()
    if when == "eve" then
        return PORTAL_EVE_DAYS[currentDayOfWeek]
    else
        return PORTAL_RESET_DAYS[currentDayOfWeek]
    end
end

-- Chime durations (rounded up) + small buffer
local DAYBREAK_CHIME_MS = 3700  -- daybreak.wav is 3.65s
local NIGHTFALL_CHIME_MS = 2700 -- nightfall.wav is 2.64s

-- Beep cadence timing
local BEEP = 200   -- interval between beeps (overlapping since beep is ~300ms)
local PAUSE = 300  -- pause between triples

-- Pattern: beep-beep-beep, pause, beep-beep-beep, pause, beep-beep-beep
local CADENCE = { BEEP, BEEP, BEEP, PAUSE, BEEP, BEEP, BEEP, PAUSE, BEEP, BEEP, BEEP }

local function playPortalResetBeeps(wristwatch, delayMs)
    local function playBeepOnce()
        if not wristwatch:IsValid() then return end
        wristwatch:HourlyBeep(0, 0)
    end

    local function playCadence(index)
        if not wristwatch:IsValid() then return end

        local current = CADENCE[index]

        if current == BEEP then
            playBeepOnce()
        end

        if index < #CADENCE then
            ExecuteWithDelay(current, function()
                ExecuteInGameThread(function()
                    playCadence(index + 1)
                end)
            end)
        else
            Log.Debug("[PortalResetBeep] Beep cadence complete")
        end
    end

    ExecuteWithDelay(delayMs, function()
        ExecuteInGameThread(function()
            if not wristwatch:IsValid() then return end
            Log.Debug("[PortalResetBeep] Playing beep cadence after %dms delay", delayMs)
            playCadence(1)
        end)
    end)
end

local function applyDayNightText(wristwatch, isNight, useCustomText)
    if not Config.DayNightText or not Config.DayNightText.Enabled then return end

    local textWidget = isNight and wristwatch.Night_Text or wristwatch.Daytime_Text

    if textWidget:IsValid() then
        if useCustomText then
            local textValue = isNight and Config.DayNightText.Nightfall or Config.DayNightText.Daytime
            textWidget:SetText(FText(textValue))
            Log.Debug("[DayNightText] Set %s text to '%s'", isNight and "night" or "day", textValue)
        else
            local defaultText = isNight and "NIGHTFALL" or "DAYTIME"
            textWidget:SetText(FText(defaultText))
            Log.Debug("[DayNightText] Reset %s text to default", isNight and "night" or "day")
        end
    end
end

local function applyBackgroundColor(wristwatch)
    local portalEnabled = Config.Background and Config.Background.Portal and Config.Background.Portal.Enabled
    local persistentEnabled = Config.Background and Config.Background.Persistent and Config.Background.Persistent.Enabled

    -- Check if portal background should apply
    if portalEnabled then
        local when = (Config.Background.Portal.When or "Eve"):lower()
        local isPortalDay = (when == "eve" and PORTAL_EVE_DAYS[currentDayOfWeek])
                        or (when == "reset" and PORTAL_RESET_DAYS[currentDayOfWeek])

        if isPortalDay then
            local color = Config.Background.Portal.Color
            local intensity = Config.Background.Portal.Intensity or 2.0
            wristwatch:SetColorAndOpacity({R = color.R * intensity, G = color.G * intensity, B = color.B * intensity, A = 1.0})
            Log.Debug("[Background] Set portal color (when=%s, intensity=%.1f)", when, intensity)
            return
        end
    end

    -- Fall back to persistent color
    if persistentEnabled then
        local color = Config.Background.Persistent.Color
        local intensity = Config.Background.Persistent.Intensity or 2.0
        wristwatch:SetColorAndOpacity({R = color.R * intensity, G = color.G * intensity, B = color.B * intensity, A = 1.0})
        Log.Debug("[Background] Set persistent color (intensity=%.1f)", intensity)
        return
    end

    -- Reset to default if portal is enabled but not applicable today (and no persistent)
    if portalEnabled then
        wristwatch:SetColorAndOpacity({R = 1.0, G = 1.0, B = 1.0, A = 1.0})
        Log.Debug("[Background] Reset to default")
    end
end

function Module.RegisterHooks()
    local dotsEnabled = Config.WeekDayDots and Config.WeekDayDots.Enabled
    local textEnabled = Config.DayNightText and Config.DayNightText.Enabled
    local bgPersistentEnabled = Config.Background and Config.Background.Persistent and Config.Background.Persistent.Enabled
    local bgPortalEnabled = Config.Background and Config.Background.Portal and Config.Background.Portal.Enabled
    local beepEnabled = Config.PortalResetBeep and Config.PortalResetBeep.Enabled

    -- Skip all hooks if all features disabled
    if not dotsEnabled and not textEnabled and not bgPersistentEnabled and not bgPortalEnabled and not beepEnabled then
        Log.Debug("All features disabled, skipping hook registration")
        return true
    end

    local updateDayOk = HookUtil.Register(
        "/Game/Blueprints/Widgets/W_Wristwatch.W_Wristwatch_C:UpdateDay",
        function(wristwatch, DayNumberParam)
            local ok, dayNum = pcall(function() return DayNumberParam:get() end)
            if not ok then
                Log.Error("[UpdateDay] Failed to get DayNumber: %s", tostring(dayNum))
                return
            end

            local previousDay = currentDayOfWeek
            currentDayOfWeek = dayNum % 7

            if not initialSetupDone then
                initialSetupDone = true

                -- Style portal reset day dots (always, on first load)
                applyDayDotStyling(wristwatch)

                -- Set day/night text on login (if applicable)
                if isTextDay() then
                    local dayNightManager = wristwatch.DayNightManager
                    if dayNightManager:IsValid() then
                        local isNight = dayNightManager.IsNight
                        applyDayNightText(wristwatch, isNight, true)
                    end
                end

                -- Apply background color (persistent or portal)
                applyBackgroundColor(wristwatch)
            elseif previousDay ~= currentDayOfWeek then
                -- Day changed at midnight - re-apply styling
                applyDayDotStyling(wristwatch)
                applyBackgroundColor(wristwatch)
            end
        end,
        Log
    )

    -- Only register Nightfall/Daybreak hooks if text or beep feature is enabled
    local nightfallOk = true
    local daybreakOk = true

    if textEnabled or beepEnabled then
        nightfallOk = HookUtil.Register(
            "/Game/Blueprints/Widgets/W_Wristwatch.W_Wristwatch_C:NightfallAlarm",
            function(wristwatch)
                applyDayNightText(wristwatch, true, isTextDay())
                if isBeepDay() then
                    playPortalResetBeeps(wristwatch, NIGHTFALL_CHIME_MS)
                end
            end,
            Log
        )

        daybreakOk = HookUtil.Register(
            "/Game/Blueprints/Widgets/W_Wristwatch.W_Wristwatch_C:DaybreakAlarm",
            function(wristwatch)
                applyDayNightText(wristwatch, false, isTextDay())
                if isBeepDay() then
                    playPortalResetBeeps(wristwatch, DAYBREAK_CHIME_MS)
                end
            end,
            Log
        )
    end

    Log.Debug("Hook registration: UpdateDay=%s, Nightfall=%s, Daybreak=%s",
        tostring(updateDayOk), tostring(nightfallOk), tostring(daybreakOk))

    return updateDayOk and nightfallOk and daybreakOk
end

function Module.GameplayCleanup()
    currentDayOfWeek = -1
    initialSetupDone = false
end

return Module
