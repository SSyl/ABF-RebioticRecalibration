return {
    Debug = false,

    -- ============================================================
    -- Menu Tweaks
    -- Small quality-of-life improvements to menus and popups
    -- ============================================================
    MenuTweaks = {
        -- Skips the 3-second countdown when hosting a LAN server
        SkipLANHostingDelay = true,
    },

    -- ============================================================
    -- Food Deployable Fix
    -- Fixes the visual bug where placed food shows damage cracks
    -- when the food item was partially decayed in your inventory
    -- ============================================================
    FoodDeployableFix = {
        -- Enables the fix (resets food durability to 100% when placed)
        -- This runs on the server/host and automatically applies to all players
        Enabled = true,

        -- Also fix existing food deployables when loading a save
        -- If false, only newly placed food is fixed (preserves existing saved state)
        -- If true, all food deployables are fixed on load (retroactive fix)
        FixExistingOnLoad = false,

        -- Enable this if you're playing on a server without this mod installed
        -- This will hide the cracked texture overlay for you locally
        -- Safe to leave enabled even on servers that have the mod (just unnecessary)
        ClientSideVisualOnly = false,
    },
}
