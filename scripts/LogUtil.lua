local LogUtil = {}

function LogUtil.CreateLogger(modName, config)
    local debugEnabled = config and config.Debug

    return function(message, level)
        level = level or "info"

        if level == "debug" and not debugEnabled then
            return
        end

        local prefix = ""
        if level == "error" then
            prefix = "ERROR: "
        elseif level == "warning" then
            prefix = "WARNING: "
        end

        print("[" .. modName .. "] " .. prefix .. tostring(message) .. "\n")
    end
end

return LogUtil
