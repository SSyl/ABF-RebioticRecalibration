return {
    -- ############################################################
    -- GAMEPLAY QOL
    -- Features that enhance or modify gameplay mechanics
    -- ############################################################

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
    -- Vehicle Light Toggle
    -- Manual control for vehicle headlights via F key on the vehicle
    -- ============================================================
    VehicleLightToggle = {
        -- Allows you to toggle vehicle lights on/off using F key on driver's seat
        -- Works on SUV, Forklift, and Security Cart
        Enabled = true, -- [default = true]

        -- Volume for the light switch sound (0-100, 0 = disabled)
        -- Note: This is independent of in-game volume settings
        SoundVolume = 75, -- [default = 75]
    },

    -- ============================================================
    -- Flashlight Flicker Fix
    -- Disables flashlight flicker during ambient earthquakes
    -- ============================================================
    FlashlightFlickerFix = {
        -- Prevents flashlight from flickering during earthquakes while keeping camera shake/audio.
        -- Other causes of flashlight flickering (like from enemies) will still happen.
        Enabled = true, -- [default = true]
    },

    -- ============================================================
    -- Player Tracker
    -- Highlights other players with a permanent outline
    -- ============================================================
    PlayerTracker = {
        -- Shows a colored outline around other players in multiplayer
        -- Disabled by default: some may consider this cheaty since there's a trinket for it
        Enabled = false, -- [default = false]
    },

    -- ============================================================
    -- Beds Keep Spawn
    -- Tap interact button on beds to sleep without changing respawn point
    -- ============================================================
    BedsKeepSpawn = {
        -- Adds tap interaction to beds: sleep without changing respawn
        -- Long-press E remains unchanged (sleep + set respawn)
        Enabled = true, -- [default = true]

        -- Text to show in the interact prompt
        PromptText = "just sleep", -- [default = "just sleep"]
    },

    -- ============================================================
    -- Auto Jump-Crouch
    -- Automatically crouches during jumps for extra height/distance
    -- ============================================================
    AutoJumpCrouch = {
        -- Automatically crouch mid-air during jumps for extra height
        -- Disabled by default: accessibility feature for controller players or those
        -- who have difficulty with the jump-crouch timing
        Enabled = false, -- [default = false]

        -- Delay in milliseconds before crouching after jump starts
        -- Adjust if crouch feels too early or too late (0-1000ms)
        Delay = 250, -- [default = 250]

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

    -- ############################################################
    -- VISUAL TWEAKS
    -- HUD enhancements and visual customization options
    -- ############################################################

    -- ============================================================
    -- Ammo Counter
    -- Enhanced ammo display with color coding and inventory count
    -- ============================================================
    AmmoCounter = {
        -- Enable/disable the enhanced ammo counter
        Enabled = true, -- [default = true]

        -- Loaded ammo warning threshold (percentage of max capacity)
        -- When current ammo drops to or below this %, it turns yellow
        -- 0.5 = 50% of max capacity
        LoadedAmmoWarning = 0.5, -- [default = 0.5]

        -- Inventory ammo warning threshold (spare ammo count)
        -- 0 = Adaptive mode: uses weapon's max capacity as threshold
        --     (e.g., 10 rounds for 9mm Pistol, 1 arrow for Crossbow)
        -- Or set a specific number for all weapons:
        --     20 = Yellow when 20 or fewer rounds remain
        InventoryAmmoWarning = 0, -- [default = 0 (adaptive)]

        -- Display mode for ammo counter
        -- false = "Loaded | Inventory" (replaces max capacity display)
        -- true  = "Loaded | MaxCap | Inventory" (shows all three)
        ShowMaxCapacity = false, -- [default = false]

        -- Color when ammo is at good levels (RGB 0-255)
        AmmoGood = {
            R = 114,
            G = 242,
            B = 255,
        }, -- [default = { R = 114, G = 242, B = 255 } (cyan)]

        -- Color when ammo is low (RGB 0-255)
        AmmoLow = {
            R = 255,
            G = 200,
            B = 32,
        }, -- [default = { R = 255, G = 200, B = 32 } (yellow)]

        -- Color when you have no ammo (RGB 0-255)
        NoAmmo = {
            R = 249,
            G = 41,
            B = 41,
        }, -- [default = { R = 249, G = 41, B = 41 } (red)]
    },

    -- ============================================================
    -- Teleporter Tags
    -- Visual identification for Personal Teleporters synced to teleport benches
    -- ============================================================
    TeleporterTags = {
        -- Enable/disable teleporter tags
        Enabled = true, -- [default = true]

        Text = {
            -- Shows abbreviated bench name on the teleporter icon
            Enabled = true, -- [default = true]

            -- Text scale (0.1-2.0, smaller = more text fits)
            -- 0.5 = ~8-12 chars, 0.8 = ~6-8 chars, 1.0 = ~4-6 chars
            Scale = 0.8, -- [default = 0.8]

            -- Text position: "TOP", "CENTER", or "BOTTOM"
            Position = "TOP", -- [default = "TOP"]

            -- How to shorten bench names:
            --   "Simple" - Remove spaces ("Office Sector" -> "OfficeSector")
            --   "FirstLetter" - First letter of each word ("Office Sector" -> "OS")
            --   "FirstTwo" - First 2 letters of each word ("Office Sector" -> "OfSe")
            --   "FirstThree" - First 3 letters of each word ("Office Sector" -> "OffSec")
            --   "FirstWord" - First word only ("Office Sector" -> "Office")
            --   "VowelRemoval" - Remove non-leading vowels ("Office Sector" -> "OffcSctr")
            AbbreviationMode = "Simple", -- [default = "Simple"]

            -- Text color (RGB 0-255)
            -- Default is game's orange: { R = 255, G = 186, B = 40 }
            Color = {
                R = 255,
                G = 186,
                B = 40,
            }, -- [default = { R = 255, G = 186, B = 40 }]
        },

        IconColor = {
            -- Tints teleporter icon with a unique color based on bench name
            -- Each destination gets a consistent, automatically-generated color
            Enabled = false, -- [default = false]

            -- Change this number to randomize the colors from default
            -- For example, changing it from 0 to 12 will produce completely different colors
            Seed = 0, -- [default = 0]
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
    -- Menu Tweaks
    -- Quality-of-life improvements to menus and popups
    -- ============================================================
    MenuTweaks = {
        -- Skips the 3-second countdown on the popup when hosting a LAN server
        SkipLANHostingDelay = false, -- [default = false]

        -- Adds a custom button to the main menu that connects directly to a server
        CustomServerButton = {
            -- Enable/disable the custom server button
            Enabled = false, -- [default = false]

            -- Server IP address (no http:// or slashes)
            -- Examples: "192.168.1.100", "myserver.example.com"
            IP = "127.0.0.1", -- [default = "127.0.0.1"]

            -- Server port (most servers use 7777)
            Port = 7777, -- [default = 7777]

            -- Server password (leave empty if no password required)
            Password = "", -- [default = ""]

            -- Button text shown in menu
            ButtonText = "Custom Server Button", -- [default = "Custom Server Button"]

            -- Icon name from /Game/Textures/GUI/Icons/
            -- Examples: "icon_hackingdevice", "icon_keypad_white", "icon_suv_64"
            -- Leave empty for no icon
            Icon = "icon_hackingdevice", -- [default = "icon_hackingdevice"]

            -- Button text/icon color (RGB 0-255)
            TextColor = {
                R = 42,
                G = 255,
                B = 45,
            }, -- [default = { R = 42, G = 255, B = 45 }]
        },
    },

    -- ============================================================
    -- Hide Hotbar Hotkeys
    -- Removes the on-screen hotbar key hints (1,2,3,4,5,6,7,8,9,0)
    -- ============================================================
    HideHotbarHotkeys = {
        -- Hide the numeric hotkey indicators on the hotbar
        -- Disabled by default: some players rely on the visual key hints
        Enabled = false, -- [default = false]
    },

    -- ############################################################
    -- BUG FIXES
    -- Fixes for visual bugs and game issues (set and forget)
    -- ############################################################

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
        FixExistingFoodOnLoad = true, -- [default = true]
    },

    -- ============================================================
    -- Crafting Menu Fixes
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

            -- Vanilla is 512. Higher = sharper but may impact performance. 1024 shouldn't cause any performance issues.
            -- Options: 512, 1024, 2048, 4096, or 8192
            Resolution = 1024, -- [default = 1024]
        },
    },

    -- ============================================================
    -- Minigame Zone Fix
    -- Fixes visual size of success zones to match actual hitbox
    -- ============================================================
    MinigameZoneFix = {
        -- Makes the success zones true-to-size in bathroom and weightlifting minigames
        Enabled = true, -- [default = true]
    },

    -- ============================================================
    -- Corpse Gib Fix
    -- Prevents gibsplosion VFX/SFX when loading areas with previously-removed corpses
    -- ============================================================
    CorpseGibFix = {
        Enabled = true, -- [default = true]

        -- Time window (ms) to suppress gib VFX after corpse spawns.
        -- Increase if you still see gibsplosions on area load.
        Threshold = 2000, -- [default = 2000]
    },

    -- ############################################################
    -- DEBUG FLAGS
    -- Enable debug logging to UE4SS.log (causes log spam, leave off)
    -- ############################################################
    DebugFlags = {
        Main = false, -- Debug logging for main.lua (hook registration, cleanup, etc.)
        DistributionPad = false,
        VehicleLightToggle = false,
        FlashlightFlickerFix = false,
        PlayerTracker = false,
        BedsKeepSpawn = false,
        AutoJumpCrouch = false,
        AmmoCounter = false,
        TeleporterTags = false,
        LowHealthVignette = false,
        MenuTweaks = false,
        HideHotbarHotkeys = false,
        FoodDisplayFix = false,
        CraftingMenu = false,
        MinigameZoneFix = false,
        CorpseGibFix = false,
    },
}
