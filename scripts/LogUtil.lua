local LogUtil = {}

function LogUtil.CreateLogger(modName, config)
    local debugEnabled = config and config.Debug
    local loggedOnce = {}

    local function formatMessage(message, ...)
        if select("#", ...) > 0 then
            local ok, formatted = pcall(string.format, message, ...)
            if ok then return formatted end
        end
        return tostring(message)
    end

    local function doLog(level, once, message, ...)
        if level == "debug" and not debugEnabled then
            return
        end

        if once then
            local key = level .. ":" .. message
            if loggedOnce[key] then return end
            loggedOnce[key] = true
        end

        local prefix = ""
        if level == "error" then
            prefix = "ERROR: "
        elseif level == "warning" then
            prefix = "WARNING: "
        end

        local formatted = formatMessage(message, ...)
        print("[" .. modName .. "] " .. prefix .. formatted .. "\n")
    end

    local logger = {
        Debug = function(msg, ...) doLog("debug", false, msg, ...) end,
        Info = function(msg, ...) doLog("info", false, msg, ...) end,
        Warning = function(msg, ...) doLog("warning", false, msg, ...) end,
        Error = function(msg, ...) doLog("error", false, msg, ...) end,

        DebugOnce = function(msg, ...) doLog("debug", true, msg, ...) end,
        InfoOnce = function(msg, ...) doLog("info", true, msg, ...) end,
        WarningOnce = function(msg, ...) doLog("warning", true, msg, ...) end,
        ErrorOnce = function(msg, ...) doLog("error", true, msg, ...) end,
    }

    -- Backward compatible: Log("message", "level")
    setmetatable(logger, {
        __call = function(self, message, level)
            doLog(level or "info", false, message)
        end
    })

    return logger
end

return LogUtil
