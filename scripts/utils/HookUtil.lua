--[[
============================================================================
HookUtil - Safe Hook Registration Helpers
============================================================================

Wrappers around UE4SS RegisterHook that handle Context:get() extraction,
IsValid() validation, pcall wrapping, and error logging.

API:
- Register(path, callback, log) - Single Blueprint/native hook
- Register({hooks}, log) - Multiple hooks
- RegisterNative(path, preCallback, postCallback, log) - Native C++ (typically /Script/Engine) with PRE/POST timing
- RegisterABFDeployedReceiveBeginPlay(pattern, callback, log) - Consolidated ReceiveBeginPlay
]]

local HookUtil = {}

-- ============================================================
-- POLYMORPHIC HOOK REGISTRATION
-- ============================================================

--- Registers a single hook with automatic Context extraction and validation
--- @param blueprintPath string Full UFunction path
--- @param callback function Handler that receives validated UObject and any additional params
--- @param log table Logger instance (must have Error method)
--- @return boolean True if registration succeeded
local function RegisterSingle(blueprintPath, callback, log)
    local ok, err = pcall(function()
        RegisterHook(blueprintPath, function(Context, ...)
            local obj = Context:get()
            if not obj or not obj:IsValid() then
                return
            end
            -- Pass validated object and any additional hook parameters
            callback(obj, ...)
        end)
    end)

    if not ok then
        log.Error("Failed to register hook '%s': %s", blueprintPath, tostring(err))
        return false
    end

    return true
end

--- Registers multiple hooks at once
--- @param hooks table Array of {path, callback} tables
--- @param log table Logger instance
--- @return boolean True if ALL hooks registered successfully
local function RegisterMultiple(hooks, log)
    local allSuccess = true

    for _, hook in ipairs(hooks) do
        local success = RegisterSingle(hook.path, hook.callback, log)
        allSuccess = allSuccess and success
    end

    return allSuccess
end

--- Polymorphic hook registration - handles single or multiple hooks
--- For Blueprint functions and simple native hooks where timing doesn't matter.
--- For native C++ functions where PRE/POST timing matters, use RegisterNative() instead.
--- @param pathOrTable string|table Either a Blueprint path (single) or array of {path, callback} (multiple)
--- @param callbackOrLog function|table Either callback (single) or logger (multiple)
--- @param log table|nil Logger (single) or nil (multiple - log is 2nd param)
--- @return boolean True if registration succeeded
function HookUtil.Register(pathOrTable, callbackOrLog, log)
    -- Detect single vs multiple based on first parameter type
    if type(pathOrTable) == "string" then
        -- Single hook: Register(path, callback, log)
        return RegisterSingle(pathOrTable, callbackOrLog, log)
    elseif type(pathOrTable) == "table" then
        -- Multiple hooks: Register({...}, log)
        return RegisterMultiple(pathOrTable, callbackOrLog)
    else
        error("HookUtil.Register: first parameter must be string (path) or table (hooks array)")
    end
end

-- ============================================================
-- NATIVE C++ FUNCTION HOOKS (PRE/POST CONTROL)
-- ============================================================

--- Registers hooks for native C++ functions with explicit PRE/POST timing control
--- Use for native engine functions (usually /Script/Engine paths) where execution timing matters.
---
--- PRE-HOOK: Executes BEFORE the native function (can modify parameters)
--- POST-HOOK: Executes AFTER the native function (can read return values)
---
--- @param path string Full UFunction path (usually /Script/Engine.ClassName:FunctionName)
--- @param preCallback function|nil PRE-HOOK callback (or nil if not needed)
--- @param postCallback function|nil POST-HOOK callback (or nil if not needed)
--- @param log table Logger instance (must have Error method)
--- @return boolean True if registration succeeded
---
--- Examples:
---   PRE-HOOK only:  RegisterNative("/Script/Engine.Character:Jump", OnJump, nil, Log)
---   POST-HOOK only: RegisterNative("/Script/Engine.Character:Jump", nil, OnJump, Log)
---   Both hooks:     RegisterNative("/Script/Engine.Character:Jump", OnJumpPre, OnJumpPost, Log)
function HookUtil.RegisterNative(path, preCallback, postCallback, log)
    if not preCallback and not postCallback then
        log.Error("RegisterNative '%s': At least one of preCallback or postCallback must be provided", path)
        return false
    end

    -- Wrap callbacks with Context extraction and validation
    local wrappedPre = nil
    local wrappedPost = nil

    if preCallback then
        wrappedPre = function(Context, ...)
            local obj = Context:get()
            if not obj or not obj:IsValid() then return end
            preCallback(obj, ...)
        end
    end

    if postCallback then
        wrappedPost = function(Context, ...)
            local obj = Context:get()
            if not obj or not obj:IsValid() then return end
            postCallback(obj, ...)
        end
    end

    local ok, err = pcall(function()
        RegisterHook(path, wrappedPre or function() end, wrappedPost or function() end)
    end)

    if not ok then
        log.Error("Failed to register native hook '%s': %s", path, tostring(err))
        return false
    end

    return true
end

-- ============================================================
-- CONSOLIDATED HOOKS
-- ============================================================

-- Registry for AbioticDeployed_ParentBP:ReceiveBeginPlay
local deployedReceiveBeginPlayRegistry = {}
local deployedReceiveBeginPlayRegistered = false

--- Registers a handler for AbioticDeployed_ParentBP:ReceiveBeginPlay with className filtering
--- Multiple modules can register to the same hook - internally consolidates to single UE4SS hook
--- @param classMatchPattern string Pattern to match against className (e.g., "^Deployed_Food_" or "Deployed_DistributionPad_C")
--- @param callback function Handler that receives validated UObject
--- @param log table Logger instance
--- @return boolean True if registration succeeded
function HookUtil.RegisterABFDeployedReceiveBeginPlay(classMatchPattern, callback, log)
    -- Add pattern+callback to registry (all modules append here)
    table.insert(deployedReceiveBeginPlayRegistry, {
        pattern = classMatchPattern,
        callback = callback
    })

    -- Register actual hook only once (first call registers, subsequent calls just append to registry)
    if not deployedReceiveBeginPlayRegistered then
        local ok, err = pcall(function()
            RegisterHook(
                "/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveBeginPlay",
                function(Context)
                    local obj = Context:get()
                    if not obj or not obj:IsValid() then return end

                    local okClass, className = pcall(function()
                        return obj:GetClass():GetFName():ToString()
                    end)
                    if not okClass or not className then return end

                    -- Check all registered patterns
                    for _, entry in ipairs(deployedReceiveBeginPlayRegistry) do
                        -- Support both pattern matching and exact string match
                        local matches = className:match(entry.pattern) or className == entry.pattern

                        if matches then
                            entry.callback(obj)
                        end
                    end
                end
            )
        end)

        if not ok then
            log.Error("Failed to register AbioticDeployed_ParentBP:ReceiveBeginPlay hook: %s", tostring(err))
            return false
        end

        deployedReceiveBeginPlayRegistered = true
    end

    return true
end

return HookUtil
