--[[
============================================================================
PlayerUtil - Local Player Caching and Identification
============================================================================

Provides cached access to the local player pawn and utilities for checking
if an actor is the local player. Reduces duplicate caching logic across modules.

USAGE:
    local PlayerUtil = require("utils/PlayerUtil")

    -- Get local player (cached)
    local player = PlayerUtil.Get()
    if player then ... end

    -- Check if actor is local player
    if PlayerUtil.IsLocal(someActor) then ... end

    -- Reset cache (call from GameplayCleanup)
    PlayerUtil.Reset()
]]

local UEHelpers = require("UEHelpers")

local PlayerUtil = {}

local cachedPlayer = CreateInvalidObject()

--- Resets the cached player reference. Call from GameplayCleanup.
function PlayerUtil.Reset()
    cachedPlayer = CreateInvalidObject()
end

--- Gets the local player pawn, caching the result.
--- @return AAbiotic_PlayerCharacter_C|nil The local player, or nil if not available
function PlayerUtil.Get()
    if not cachedPlayer:IsValid() then
        cachedPlayer = UEHelpers.GetPlayer()
    end
    return cachedPlayer:IsValid() and cachedPlayer or nil
end

--- Checks if the given actor is the local player.
--- @param actor AActor The actor to check
--- @return boolean True if the actor is the local player
function PlayerUtil.IsLocal(actor)
    if not actor:IsValid() then return false end
    local player = PlayerUtil.Get()
    if not player then return false end
    return actor:GetAddress() == player:GetAddress()
end

--- Gets the local player only if the given actor matches.
--- Useful for hooks that fire for all players but you only want to process local.
--- @param actor AActor The actor to check
--- @return AAbiotic_PlayerCharacter_C|nil The local player if actor matches, nil otherwise
function PlayerUtil.GetIfLocal(actor)
    if not actor:IsValid() then return nil end
    local player = PlayerUtil.Get()
    if not player then return nil end
    if actor:GetAddress() ~= player:GetAddress() then return nil end
    return player
end

return PlayerUtil
