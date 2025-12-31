return {
    -- Global debug flag (default for all features)
    Debug = false,

    -- Per-feature debug overrides
    -- nil = use global Debug setting
    -- true/false = override global setting for this feature
    DebugFlags = {
        MenuTweaks = nil,
        FoodDeployableFix = nil,
        CraftingPreview = nil,
        DistributionPad = true,  -- Currently debugging this feature
    },

    -- ============================================================
    -- Menu Tweaks
    -- Small quality-of-life improvements to menus and popups
    -- ============================================================
    MenuTweaks = {
        -- Skips the 3-second countdown when hosting a LAN server
        -- [Default = true]
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
        -- [Default = true]
        Enabled = true,

        -- Also fix existing food deployables when loading a save
        -- If false, only newly placed food is fixed (preserves existing saved state)
        -- If true, all food deployables are fixed on load (retroactive fix)
        -- [Default = true]
        FixExistingOnLoad = true,

        -- Enable this if you're playing on a server without this mod installed
        -- This will hide the cracked texture overlay for you locally
        -- Safe to leave enabled even on servers that have the mod (just unnecessary)
        -- [Default = false]
        ClientSideVisualOnly = false,
    },

    -- ============================================================
    -- Crafting Preview Brightness
    -- Fixes the dark 3D item preview in the crafting menu
    -- ============================================================
    CraftingPreviewBrightness = {
        -- Enables the brightness fix for crafting menu item previews
        -- [Default = true]
        Enabled = true,

        -- Vanilla itensity is 4, mod default is 10, so this will make it 2.5x brighter
        -- Note: The back will still be darker, as it's always half as intense as the front
        -- [Default = 10]
        LightIntensity = 10.0,
    },

    -- ============================================================
    -- Crafting Preview Resolution
    -- Increases the resolution of the 3D item preview in the crafting menu
    -- The vanilla game renders at 512x512 and displays it much larger, causing blur
    -- ============================================================
    CraftingPreviewResolution = {
        -- Enables the resolution fix for crafting menu item previews
        -- [Default = true]
        Enabled = true,

        -- Resolution for the 3D preview (square aspect ratio)
        -- Vanilla is 512x512. Higher values = sharper but more VRAM usage
        -- Values are automatically rounded to nearest power of 2 (512, 1024, 2048, 4096, 8192)
        -- Maximum is 8192 to prevent excessive VRAM usage
        -- [Default = 1024]
        Resolution = 1024,
    },

    -- ============================================================
    -- Distribution Pad Distance
    -- Increases the range at which the distribution pad detects containers
    -- Vanilla range is 1000 units (approx 10 meters)
    -- ============================================================
    DistributionPadDistance = {
        -- Enables the distance increase
        -- NOTE: Some players may consider this a cheat rather than QoL, so it's disabled by default
        -- [Default = false]
        Enabled = false,

        -- Distance multiplier (1.0 = vanilla 1000 units, 1.25 = 1250 units, 2.0 = 2000 units, etc.)
        -- Higher values let the pad find containers from farther away
        -- [Default = 1.25]
        DistanceMultiplier = 1.25,
    },

    -- ============================================================
    -- Distribution Pad Container Indicator
    -- Shows which containers are within distribution pad range
    -- ============================================================
    DistributionPadIndicator = {
        -- Enables the indicator feature entirely
        -- [Default = true]
        Enabled = true,

        -- When you finish building a container, immediately check if it's near any distribution pad
        -- Without this, newly built containers won't show the indicator until someone
        -- walks on a nearby pad
        -- May cause a brief hitch if you have many distribution pads in your base
        -- [Default = false]
        RefreshOnContainerDeploy = true,

        -- Text indicator options
        -- Appends text to container name when looking at it
        -- [Default = true]
        TextEnabled = true,

        -- Text to append to container name (e.g., "[DistPad]", "[D]", " *")
        -- [Default = "[DistPad]"]
        Text = "[DistPad]",

        -- Icon indicator options
        -- Shows an icon next to the container name
        -- [Default = true]
        IconEnabled = true,

        -- Icon to display (from /Game/Textures/GUI/Icons/)
        -- [Default = "icon_hackingdevice"]
        Icon = "icon_hackingdevice",

        -- Icon color (RGB values 0-255)
        -- Default is the game's UI cyan color
        -- [Default = { R = 114, G = 242, B = 255 }]
        IconColor = {
            R = 114,
            G = 242,
            B = 255,
        },
    },
}
