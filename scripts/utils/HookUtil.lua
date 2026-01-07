--[[
============================================================================
HookUtil - Safe Hook Registration Helpers
============================================================================

PURPOSE:
Provides simplified wrappers around UE4SS RegisterHook to eliminate
boilerplate for:
- pcall wrapping
- Context:get() extraction
- IsValid() validation
- Error logging

USAGE:

Single hook:
```lua
HookUtil.Register(
    "/Game/BP.BP_C:Function",
    function(obj)
        -- obj is already validated, no need for IsValid() check
        obj:DoSomething()
    end,
    Log
)
```

Multiple hooks:
```lua
HookUtil.Register({
    {path = "/Game/BP.BP_C:Func1", callback = Module.OnFunc1},
    {path = "/Game/BP.BP_C:Func2", callback = Module.OnFunc2},
}, Log)
```

Consolidated hook (AbioticDeployed_ParentBP ReceiveBeginPlay):
```lua
HookUtil.RegisterABFDeployedReceiveBeginPlay(
    "^Deployed_Food_",  -- Pattern or exact match
    FoodFix.OnBeginPlay,
    Log
)
```
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
