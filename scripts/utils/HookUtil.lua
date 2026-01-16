--[[
============================================================================
HookUtil - Safe Hook Registration Helpers
============================================================================

Wrappers around UE4SS RegisterHook that handle Context:get() extraction,
IsValid() validation, pcall wrapping, and error logging.

API:
- Register(path, callback, log, options) - Single Blueprint/native hook
- Register({hooks}, log) - Multiple hooks
- RegisterNative(path, preCallback, postCallback, log) - Native C++ (typically /Script/Engine) with PRE/POST timing
- ResetWarmup() - Reset warmup state (call on gameplay end)

Consolidated Hooks (share single UE4SS hook across multiple modules):
- RegisterABFDeployedBeginPlay(classPath, fallbackClassPattern, callback, log) - AbioticDeployed_ParentBP:ReceiveBeginPlay (IsA filter with pattern fallback)
- RegisterABFPlayerCharacterBeginPlay(callback, log) - Abiotic_PlayerCharacter_C:ReceiveBeginPlay
- RegisterABFInventorySlotUpdateUI(callback, log) - W_InventoryItemSlot_C:UpdateSlot_UI (warmup+cache)
- RegisterABFInteractionPromptUpdate(callback, log) - W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts (warmup)

Options for Register():
- warmup: boolean - If true, delays callback execution for 2s after first fire
                    (prevents crashes from accessing partially-initialized widgets on load)
- runPostWarmup: boolean - If true (requires warmup=true), caches calls during warmup
                           and fires them once warmup completes
]]

local LogUtil = require("utils/LogUtil")

local HookUtil = {}
local Log = LogUtil.CreateLogger("HookUtil", true)  -- TODO: wire up to config debug flag

-- ============================================================
-- WARMUP STATE (crash prevention for per-frame hooks)
-- ============================================================

local WARMUP_DELAY_MS = 2000

local warmupStarted = false
local warmupComplete = false
local warmupCallCache = {}  -- Cached calls for runPostWarmup hooks

-- Deployed BeginPlay class cache (declared here so ResetWarmup can access)
local deployedClassCache = {}  -- classPath -> UClass
local deployedAllClassesCached = false  -- true when all registered classes are cached

--- Resets warmup and class cache state - call from main.lua on main menu return
function HookUtil.ResetWarmup()
    warmupStarted = false
    warmupComplete = false
    warmupCallCache = {}
    deployedClassCache = {}
    deployedAllClassesCached = false
end

-- ============================================================
-- POLYMORPHIC HOOK REGISTRATION
-- ============================================================

--- Registers a single hook with automatic Context extraction and validation
--- @param blueprintPath string Full UFunction path
--- @param callback function Handler that receives validated UObject and any additional params
--- @param log table Logger instance (must have Error method)
--- @param options table|nil Optional settings: { warmup = bool, runPostWarmup = bool }
--- @return boolean True if registration succeeded
local function RegisterSingle(blueprintPath, callback, log, options)
    local needsWarmup = options and options.warmup
    local runPostWarmup = options and options.runPostWarmup

    local ok, err = pcall(function()
        RegisterHook(blueprintPath, function(Context, ...)
            -- Warmup gate FIRST - bail out before touching Context to avoid memory access violations
            if needsWarmup and not warmupComplete then
                -- First call starts warmup timer
                if not warmupStarted then
                    warmupStarted = true
                    ExecuteWithDelay(WARMUP_DELAY_MS, function()
                        warmupComplete = true
                        -- Fire cached calls after warmup
                        for _, cached in ipairs(warmupCallCache) do
                            ExecuteInGameThread(function()
                                if cached.obj:IsValid() then
                                    cached.callback(cached.obj, table.unpack(cached.args))
                                end
                            end)
                        end
                        warmupCallCache = {}
                    end)
                end

                -- Cache call if runPostWarmup is enabled
                if runPostWarmup then
                    local obj = Context:get()
                    if obj:IsValid() then
                        table.insert(warmupCallCache, {
                            callback = callback,
                            obj = obj,
                            args = {...}
                        })
                    end
                end
                return
            end

            local obj = Context:get()
            if not obj:IsValid() then return end
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
--- @param options table|nil Options for single hook: { warmupMs = number }
--- @return boolean True if registration succeeded
function HookUtil.Register(pathOrTable, callbackOrLog, log, options)
    -- Detect single vs multiple based on first parameter type
    if type(pathOrTable) == "string" then
        -- Single hook: Register(path, callback, log, options)
        return RegisterSingle(pathOrTable, callbackOrLog, log, options)
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
            if not obj:IsValid() then return end
            preCallback(obj, ...)
        end
    end

    if postCallback then
        wrappedPost = function(Context, ...)
            local obj = Context:get()
            if not obj:IsValid() then return end
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

-- Registry for Abiotic_PlayerCharacter_C:ReceiveBeginPlay
local playerCharacterReceiveBeginPlayRegistry = {}
local playerCharacterReceiveBeginPlayRegistered = false

-- Registry for W_InventoryItemSlot_C:UpdateSlot_UI
local inventorySlotUpdateUIRegistry = {}
local inventorySlotUpdateUIRegistered = false

-- Registry for W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts
local interactionPromptUpdateRegistry = {}
local interactionPromptUpdateRegistered = false

--- Registers a handler for AbioticDeployed_ParentBP:ReceiveBeginPlay with IsA() class filtering
--- Multiple modules can register to the same hook - internally consolidates to single UE4SS hook
--- Uses fallback pattern matching until class is resolved via StaticFindObject, then fast-paths to IsA()
--- @param classPath string Full Blueprint class path for IsA() check (e.g., "/Game/Blueprints/DeployedObjects/Furniture/Deployed_Food_Pie_ParentBP.Deployed_Food_Pie_ParentBP_C")
--- @param fallbackClassPattern string Pattern for string matching before class resolves (e.g., "^Deployed_Food_" or "Deployed_DistributionPad_C")
--- @param callback function Handler that receives validated UObject
--- @param log table Logger instance
--- @return boolean True if registration succeeded
function HookUtil.RegisterABFDeployedBeginPlay(classPath, fallbackClassPattern, callback, log)
    table.insert(deployedReceiveBeginPlayRegistry, {
        classPath = classPath,
        fallbackClassPattern = fallbackClassPattern,
        callback = callback,
        log = log
    })

    -- Register actual hook only once (first call registers, subsequent calls just append to registry)
    if not deployedReceiveBeginPlayRegistered then
        local ok, err = pcall(function()
            RegisterHook(
                "/Game/Blueprints/DeployedObjects/AbioticDeployed_ParentBP.AbioticDeployed_ParentBP_C:ReceiveBeginPlay",
                function(Context)
                    local obj = Context:get()
                    if not obj:IsValid() then return end

                    -- Fast path: all classes cached, just do IsA checks
                    if deployedAllClassesCached then
                        for _, entry in ipairs(deployedReceiveBeginPlayRegistry) do
                            local cachedClass = deployedClassCache[entry.classPath]

                            if cachedClass:IsValid() then
                                if obj:IsA(cachedClass) then
                                    entry.callback(obj)
                                end
                            else
                                -- Cached class became invalid, try to re-resolve
                                local newClass = StaticFindObject(entry.classPath)
                                if newClass:IsValid() then
                                    deployedClassCache[entry.classPath] = newClass
                                    if obj:IsA(newClass) then
                                        entry.callback(obj)
                                    end
                                else
                                    -- Failed to re-resolve, fall back to slow path
                                    Log.Debug("[DeployedBeginPlay] Cached class invalid, re-resolve failed, reverting to slow path: %s", entry.classPath)
                                    deployedClassCache[entry.classPath] = nil
                                    deployedAllClassesCached = false
                                end
                            end
                        end
                        return -- Exit callback after fast path
                    end

                    -- Slow path: pattern match first, only StaticFindObject when we see a matching object
                    local className = obj:GetClass():GetFName():ToString()
                    local allCached = true

                    for _, entry in ipairs(deployedReceiveBeginPlayRegistry) do
                        local cachedClass = deployedClassCache[entry.classPath]

                        if cachedClass then
                            -- Already cached, use IsA
                            if cachedClass:IsValid() then
                                if obj:IsA(cachedClass) then
                                    entry.callback(obj)
                                end
                            else
                                -- Cached class became invalid, clear it
                                deployedClassCache[entry.classPath] = nil
                                allCached = false
                            end
                        else
                            -- Not cached yet, use pattern matching
                            allCached = false
                            local patternMatches = className:match(entry.fallbackClassPattern)
                            if patternMatches then
                                -- Pattern matched - class must be loaded, cache it now
                                local foundClass = StaticFindObject(entry.classPath)
                                if foundClass:IsValid() then
                                    deployedClassCache[entry.classPath] = foundClass
                                    if obj:IsA(foundClass) then
                                        entry.callback(obj)
                                    end
                                else
                                    -- Pattern matched but StaticFindObject failed - classPath might be wrong
                                    Log.Error("[DeployedBeginPlay] Pattern matched but StaticFindObject failed: %s (pattern: %s)", entry.classPath, entry.fallbackClassPattern)
                                    entry.callback(obj)
                                end
                            end
                        end
                    end

                    if allCached then
                        deployedAllClassesCached = true
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

--- Registers a handler for Abiotic_PlayerCharacter_C:ReceiveBeginPlay
--- Multiple modules can register to the same hook - internally consolidates to single UE4SS hook
--- @param callback function Handler that receives validated character UObject
--- @param log table Logger instance
--- @return boolean True if registration succeeded
function HookUtil.RegisterABFPlayerCharacterBeginPlay(callback, log)
    table.insert(playerCharacterReceiveBeginPlayRegistry, callback)

    if not playerCharacterReceiveBeginPlayRegistered then
        local ok, err = pcall(function()
            RegisterHook(
                "/Game/Blueprints/Characters/Abiotic_PlayerCharacter.Abiotic_PlayerCharacter_C:ReceiveBeginPlay",
                function(Context)
                    local character = Context:get()
                    if not character:IsValid() then return end

                    for _, registeredCallback in ipairs(playerCharacterReceiveBeginPlayRegistry) do
                        registeredCallback(character)
                    end
                end
            )
        end)

        if not ok then
            log.Error("Failed to register Abiotic_PlayerCharacter_C:ReceiveBeginPlay hook: %s", tostring(err))
            return false
        end

        playerCharacterReceiveBeginPlayRegistered = true
    end

    return true
end

--- Registers a handler for W_InventoryItemSlot_C:UpdateSlot_UI
--- Multiple modules can register to the same hook - internally consolidates to single UE4SS hook
--- NOTE: This hook has warmup+runPostWarmup built-in (2s delay, caches calls during warmup)
--- @param callback function Handler that receives validated slot widget UObject
--- @param log table Logger instance
--- @return boolean True if registration succeeded
function HookUtil.RegisterABFInventorySlotUpdateUI(callback, log)
    table.insert(inventorySlotUpdateUIRegistry, callback)

    if not inventorySlotUpdateUIRegistered then
        local ok, err = pcall(function()
            RegisterHook(
                "/Game/Blueprints/Widgets/Inventory/W_InventoryItemSlot.W_InventoryItemSlot_C:UpdateSlot_UI",
                function(Context)
                    -- Warmup gate - uses global warmup state
                    if not warmupComplete then
                        if not warmupStarted then
                            warmupStarted = true
                            ExecuteWithDelay(WARMUP_DELAY_MS, function()
                                warmupComplete = true
                                for _, cached in ipairs(warmupCallCache) do
                                    ExecuteInGameThread(function()
                                        if cached.obj:IsValid() then
                                            cached.callback(cached.obj)
                                        end
                                    end)
                                end
                                warmupCallCache = {}
                            end)
                        end

                        -- Cache calls for all registered callbacks (runPostWarmup behavior)
                        local slot = Context:get()
                        if slot:IsValid() then
                            for _, registeredCallback in ipairs(inventorySlotUpdateUIRegistry) do
                                table.insert(warmupCallCache, {
                                    callback = registeredCallback,
                                    obj = slot
                                })
                            end
                        end
                        return
                    end

                    local slot = Context:get()
                    if not slot:IsValid() then return end

                    for _, registeredCallback in ipairs(inventorySlotUpdateUIRegistry) do
                        registeredCallback(slot)
                    end
                end
            )
        end)

        if not ok then
            log.Error("Failed to register W_InventoryItemSlot_C:UpdateSlot_UI hook: %s", tostring(err))
            return false
        end

        inventorySlotUpdateUIRegistered = true
    end

    return true
end

--- Registers a handler for W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts
--- Multiple modules can register to the same hook - internally consolidates to single UE4SS hook
--- NOTE: This hook has warmup built-in (2s delay, no caching)
--- @param callback function Handler that receives (widget, HitActorParam)
--- @param log table Logger instance
--- @return boolean True if registration succeeded
function HookUtil.RegisterABFInteractionPromptUpdate(callback, log)
    table.insert(interactionPromptUpdateRegistry, callback)

    if not interactionPromptUpdateRegistered then
        local ok, err = pcall(function()
            RegisterHook(
                "/Game/Blueprints/Widgets/W_PlayerHUD_InteractionPrompt.W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts",
                function(Context, ShowPressInteract, ShowHoldInteract, ShowPressPackage, ShowHoldPackage,
                         ObjectUnderConstruction, ConstructionPercent, RequiresPower, Radioactive,
                         ShowDescription, ExtraNoteLines, HitActorParam, HitComponentParam, RequiresPlug)
                    -- Warmup gate - uses global warmup state (no caching for per-frame hooks)
                    if not warmupComplete then
                        if not warmupStarted then
                            warmupStarted = true
                            ExecuteWithDelay(WARMUP_DELAY_MS, function()
                                warmupComplete = true
                            end)
                        end
                        return
                    end

                    local widget = Context:get()
                    if not widget:IsValid() then return end

                    for _, registeredCallback in ipairs(interactionPromptUpdateRegistry) do
                        registeredCallback(widget, HitActorParam)
                    end
                end
            )
        end)

        if not ok then
            log.Error("Failed to register W_PlayerHUD_InteractionPrompt_C:UpdateInteractionPrompts hook: %s", tostring(err))
            return false
        end

        interactionPromptUpdateRegistered = true
    end

    return true
end

return HookUtil
