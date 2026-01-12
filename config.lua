return {
    -- ============================================================
    -- Menu Tweaks
    -- Small quality-of-life improvements to menus and popups
    -- ============================================================
    MenuTweaks = {
        -- Skips the 3-second countdown when hosting a LAN server
        SkipLANHostingDelay = true, -- [default = true]
    },

    -- ============================================================
    -- Food Display Fix
    -- Fixes the visual bug where placed food shows damage cracks
    -- when the food was partially decayed in your inventory.
    -- ============================================================
    FoodDisplayFix = {
        -- If you're hosting: applies to all players in the lobby.
        -- If you're a client: applies visually to yourself only.
        Enabled = true, -- [default = true]

        -- When enabled, retroactively fixes existing placed food when loading a save
        -- If false, only newly placed food is fixed
        FixExistingFoodOnLoad = true, -- [default = false]
    },

    -- ============================================================
    -- Crafting Menu
    -- Fixes for the 3D item preview in the crafting menu
    -- ============================================================
    CraftingMenu = {
        Brightness = {
            -- Fixes the dark 3D item preview in the crafting menu
            Enabled = true, -- [default = true]

            -- How bright the preview should be (vanilla = 4)
            LightIntensity = 10.0, -- [default = 10]
        },

        Resolution = {
            -- The vanilla preview is blurry because it renders at low resolution
            Enabled = true, -- [default = true]

            -- Vanilla is 512. Higher = sharper but may impact performance. 1024 shouldn't cause any performance issues on anything but the lowest-end systems.
            -- Options: 512, 1024, 2048, 4096, or 8192
            Resolution = 1024, -- [default = 1024]
        },
    },

    -- ============================================================
    -- Distribution Pad
    -- Adds indicators to containers in range and optionally increases pad range
    -- ============================================================
    DistributionPad = {
        Indicator = {
            -- Adds an icon or text indicator next to containers names in range of a distribution pad
            Enabled = true, -- [default = true]

            -- Refresh indicators when you finish building a container
            -- Without this, new containers won't show indicators until someone walks on a pad
            -- May increase world load time on lower-end systems or with a ridiculous amount of pads
            RefreshOnBuiltContainer = true, -- [default = true]

            -- Show an icon next to the container name
            IconEnabled = true, -- [default = true]

            -- Which icon to use (see docs/icon-list.txt for full list)
            -- Suggested: hackingdevice, allrecipes, container, wristwatch_compass_n, radialwheel
            Icon = "hackingdevice", -- [default = "hackingdevice"]

            -- Icon color (RGB 0-255) [default = { R = 114, G = 242, B = 255 }]
            IconColor = {
                R = 114,
                G = 242,
                B = 255,
            },

            -- Icon size in pixels [default = 24]
            IconSize = 24,

            -- Adjust icon position relative to container name
            -- Example: { Horizontal = 10, Vertical = -5 } moves icon 10px right and 5px down
            IconOffset = {
                Horizontal = 0, -- [default = 0]
                Vertical = 0,   -- [default = 0]
            },

            -- Add text to the container name when looking at it
            TextEnabled = false, -- [default = false]

            -- Text to append (e.g., "[DistPad]", "[D]", " *")
            Text = "[DistPad]", -- [default = "[DistPad]"]
        },

        Range = {
            -- Increases the range the distribution pad will deposit items into
            -- Some players may consider this a cheat, so it's disabled by default
            Enabled = false, -- [default = false]

            -- 1.0 = normal, 1.25 = 25% farther, 2.0 = twice as far
            Multiplier = 1.5, -- [default = 1.5]
        },
    },

    -- ============================================================
    -- Low Health Vignette
    -- Adds a red vignette overlay when health drops below a threshold
    -- ============================================================
    LowHealthVignette = {
        -- Enable/disable the low health vignette effect
        Enabled = true, -- [default = true]

        -- Health percentage threshold (0.0 - 1.0) to trigger vignette
        -- 0.25 = vignette appears when health drops below 25%
        Threshold = 0.25, -- [default = 0.25]

        -- Vignette color (RGB 0-255, A 0.0-1.0)
        Color = {
            R = 128,
            G = 0,
            B = 0,
            A = 0.3,
        }, -- [default = { R = 128, G = 0, B = 0, A = 0.3 }]

        -- Slow pulsing effect for the vignette
        PulseEnabled = true, -- [default = true]
    },

    -- ============================================================
    -- Flashlight Flicker
    -- Disables flashlight flicker during ambient earthquakes
    -- ============================================================
    FlashlightFlicker = {
        -- Prevents flashlight from flickering during earthquakes while keeping camera shake/audio.
        -- Other causes of flashlight flickering (like from enemies) will still happen.
        Enabled = true, -- [default = true]
    },

    -- ============================================================
    -- Auto Jump-Crouch
    -- Automatically crouches during jumps for extra height/distance
    -- ============================================================
    AutoJumpCrouch = {
        -- Automatically crouch mid-air during jumps for extra height
        Enabled = false, -- [default = false]

        -- Delay in milliseconds before crouching after jump starts
        -- Adjust if crouch feels too early or too late (0-1000ms)
        Delay = 150, -- [default = 150]

        -- Stop sprinting when mid-jump
        -- Useful if you have toggle-sprint enabled (otherwise sprint+jump prevents crouch)
        -- Note: Stopping sprint mid air doesn't slow you down. It just stops you from crouching.
        ClearSprintOnJump = true, -- [default = true]

        -- When true: only crouch if jump button is HELD after delay (hold to crouch)
        -- When false: only crouch if jump button is NOT held after delay (tap to crouch)
        RequireJumpHeld = true, -- [default = true]

        -- Disable auto-uncrouch on landing (manage crouch manually)
        -- Mod automatically uncrouches when you land. Set this to true to stay crouched after landing.
        DisableAutoUncrouch = false, -- [default = false]
    },

    -- ============================================================
    -- Vehicle Lights
    -- Manual control for vehicle headlights via F key on driver seat
    -- ============================================================
    VehicleLights = {
        -- Allows you to toggle vehicle lights on/off using F key on driver's seat
        -- Works on SUV, Forklift, and Security Cart (Sleigh has no lights)
        Enabled = true, -- [default = true]
    },

    -- ============================================================
    -- Hide Hotbar Hotkeys
    -- Removes the on-screen hotbar key hints (1,2,3,4,5,6,7,8,9,0)
    -- ============================================================
    HideHotbarHotkeys = {
        -- Hide the numeric hotkey indicators on the hotbar
        Enabled = false, -- [default = false]
    },

    -- ============================================================
    -- Minigame Bar Fix
    -- Fixes visual size of success zones to match actual hitbox
    -- ============================================================
    MinigameBarFix = {
        -- Makes the success zones true-to-size in bathroom and weightlifting minigames
        Enabled = true, -- [default = true]
    },

    -- ============================================================
    -- Corpse Gib Fix
    -- Prevents gibsplosion effect when loading areas with previously-removed corpses
    -- ============================================================
    CorpseGibFix = {
        Enabled = true, -- [default = true]

        -- Time window (ms) to suppress gib VFX after corpse spawns.
        -- Save-load gibs happen ~260-290ms after spawn. Increase if clients with
        -- slow connections still see gibsplosions on area load.
        Threshold = 500, -- [default = 500]
    },

    -- ============================================================
    -- Debug Flags
    -- Enable debug logging to UE4SS.log (causes log spam, leave off)
    -- ============================================================
    DebugFlags = {
        Misc = false, -- Debug logging for main.lua (hook registration, cleanup, etc.)
        MenuTweaks = false,
        FoodDisplayFix = false,
        CraftingMenu = false,
        DistributionPad = false,
        LowHealthVignette = false,
        FlashlightFlicker = false,
        AutoJumpCrouch = false,
        VehicleLights = false,
        HideHotbarHotkeys = false,
        MinigameBarFix = false,
        CorpseGibFix = false,
    },
}
