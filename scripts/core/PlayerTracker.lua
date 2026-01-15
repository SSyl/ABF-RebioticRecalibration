--[[
============================================================================
PlayerTracker - Outline Other Players
============================================================================

Highlights other players with a permanent outline using the same method as
the Employee Locator trinket, but filtered to only show players. Processes
existing players on map load and hooks ReceiveBeginPlay for new spawns.

HOOKS: Abiotic_PlayerCharacter_C:ReceiveBeginPlay
PERFORMANCE: Fires on player spawn, address-cached to prevent re-processing
]]

local HookUtil = require("utils/HookUtil")
local UEHelpers = require("UEHelpers")

-- ============================================================
-- MODULE METADATA
-- ============================================================

local Module = {
    name = "PlayerTracker",
    configKey = "PlayerTracker",

    schema = {
        { path = "Enabled", type = "boolean", default = false },
    },

    hookPoint = "Gameplay",
}

-- ============================================================
-- MODULE STATE
-- ============================================================

local Config = nil
local Log = nil

local cachedLocalPlayer = nil
local cachedGameStateClass = nil

-- E_OutlineMode enum value for FriendFinder
local OUTLINE_MODE_FRIEND_FINDER = 3

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

local function GetLocalPlayer()
    if not cachedLocalPlayer or not cachedLocalPlayer:IsValid() then
        cachedLocalPlayer = UEHelpers.GetPlayer()
    end
    return cachedLocalPlayer
end

local function IsLocalPlayer(player)
    local localPlayer = GetLocalPlayer()
    if not localPlayer or not localPlayer:IsValid() then
        return false
    end

    local okPlayerAddr, playerAddr = pcall(function() return player:GetAddress() end)
    local okLocalAddr, localAddr = pcall(function() return localPlayer:GetAddress() end)

    return okPlayerAddr and okLocalAddr and playerAddr == localAddr
end

local function GetGameStateClass()
    if not cachedGameStateClass or not cachedGameStateClass:IsValid() then
        cachedGameStateClass = StaticFindObject("/Game/Blueprints/Meta/Abiotic_Survival_GameState.Abiotic_Survival_GameState_C")
    end
    return cachedGameStateClass
end

local function IsInGameplay(player)
    local okWorld, world = pcall(function() return player:GetWorld() end)
    if not okWorld or not world:IsValid() then return false end

    local okGameState, gameState = pcall(function() return world.GameState end)
    if not okGameState or not gameState:IsValid() then return false end

    local gameStateClass = GetGameStateClass()
    if not gameStateClass or not gameStateClass:IsValid() then return false end

    local okIsGameplay, isGameplay = pcall(function()
        return gameState:IsA(gameStateClass)
    end)

    return okIsGameplay and isGameplay
end

local function ApplyOutline(player)
    if not player:IsValid() then return false end

    if not IsInGameplay(player) then return false end

    if IsLocalPlayer(player) then return false end

    local okOutline, outline = pcall(function() return player.OutlineComponent end)
    if not okOutline or not outline or not outline:IsValid() then
        Log.Debug("Failed to get OutlineComponent")
        return false
    end

    local ok = pcall(function()
        outline:ToggleOutlineOverlay(
            OUTLINE_MODE_FRIEND_FINDER,
            0,
            true
        )
    end)

    if not ok then
        Log.Debug("Failed to apply outline")
        return false
    end

    return true
end

local function ProcessExistingPlayers()
    local players = FindAllOf("Abiotic_PlayerCharacter_C")
    if not players then return end

    local count = 0
    for _, player in pairs(players) do
        if ApplyOutline(player) then
            count = count + 1
        end
    end

    if count > 0 then
        Log.Debug("Processed %d existing players", count)
    end
end

-- ============================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================

function Module.Init(config, log)
    Config = config
    Log = log

    local status = Config.Enabled and "Enabled" or "Disabled"
    Log.Info("PlayerTracker - %s", status)
end

function Module.GameplayCleanup()
    cachedLocalPlayer = nil
    cachedGameStateClass = nil
    Log.Debug("PlayerTracker state cleaned up")
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================

function Module.RegisterHooks()
    local success = HookUtil.Register(
        "/Game/Blueprints/Characters/Abiotic_PlayerCharacter.Abiotic_PlayerCharacter_C:ReceiveBeginPlay",
        Module.OnPlayerBeginPlay,
        Log
    )

    if success then
        ExecuteWithDelay(1500, function()
            ExecuteInGameThread(function()
                ProcessExistingPlayers()
            end)
        end)
    end

    return success
end

-- ============================================================
-- HOOK CALLBACKS
-- ============================================================

function Module.OnPlayerBeginPlay(player)
    ApplyOutline(player)
end

return Module
