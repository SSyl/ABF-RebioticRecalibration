# Rebiotic Recalibration

A UE4SS Lua mod for [Abiotic Factor](https://store.steampowered.com/app/427410/Abiotic_Factor/) that bundles quality-of-life tweaks, visual enhancements, and bug fixes into a single configurable package.

## Features

### Gameplay

| Feature | Description | Default |
|---------|-------------|---------|
| **Distribution Pad Indicators** | Shows an icon next to containers within range of a distribution pad | On |
| **Distribution Pad Range** | Increases distribution pad deposit range | Off |
| **Vehicle Light Toggle** | Adds F key interaction to toggle headlights on SUV, Forklift, Security Cart | On |
| **Flashlight Flicker Fix** | Prevents flashlight flicker during earthquakes (enemy-caused flicker unchanged) | On |
| **Beds Keep Spawn** | Tap E on beds to sleep without changing respawn point | On |
| **Player Tracker** | Permanent outline on other players (like Employee Locator trinket, but without NPC tracking) | Off |
| **Auto Jump-Crouch** | Automatically crouches mid-jump for extra height | Off |

### Visual

| Feature | Description | Default |
|---------|-------------|---------|
| **Ammo Counter** | Color-coded ammo display showing loaded + inventory count | On |
| **Teleporter Tags** | Text labels and/or color tinting on synced Personal Teleporter icons | On |
| **Low Health Vignette** | Red screen edge effect when health drops below threshold | On |
| **Hide Hotbar Hotkeys** | Hide hotbar key indicators, or show your actual keybindings | Off |
| **Menu Tweaks** | Skip LAN hosting delay. Add a custom main menu button with configurable icon, color, and text that connects directly to a server | Off |

### Bug Fixes

| Feature | Description | Default |
|---------|-------------|---------|
| **Food Display Fix** | Removes damage cracks on placed food caused by inventory decay | On |
| **Crafting Preview Fix** | Brighter, sharper 3D item preview in crafting menu | On |
| **Minigame Zone Fix** | Success zones in bathroom/weightlifting minigames match actual hitbox | On |
| **Corpse Gib Fix** | Prevents gore VFX replay when loading or teleporting into areas with destroyed corpses | On |

## Requirements

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) 3.0.1 or later
- Abiotic Factor (tested on v1.2.x)

## Installation

1. Install UE4SS if you haven't already ([installation guide](https://docs.ue4ss.com/installation-guide.html))
2. Download the latest release at [Nexus Mods](https://www.nexusmods.com/abioticfactor/mods/180)
3. Extract to `[...]Steam\steamapps\common\AbioticFactor\AbioticFactor\Binaries\Win64\`
4. Folder structure should be: `Mods\RebioticRecalibration\scripts\main.lua`

**Verify it works:** On game launch, check UE4SS.log for `[Rebiotic Recalibration] MOD LOADING`.

## Uninstallation

Delete the `Mods/RebioticRecalibration/` folder.

To temporarily disable without uninstalling, rename or delete the `enabled.txt` file in the mod folder.

## Configuration

On first run, the mod automatically generates `config.lua` in the mod folder. Edit this file to enable/disable features and adjust settings. The file is commented with descriptions and default values.

When the mod updates with new options, your existing config is automatically patched - your settings are preserved and only missing options are added.

For custom icons (Distribution Pad Indicators, Custom Server Button), see `icon-list.txt` in the mod folder for available icon names.

```lua
-- Example: Disable ammo counter, change low health threshold
AmmoCounter = {
    Enabled = false,
},

LowHealthVignette = {
    Enabled = true,
    Threshold = 0.15,  -- Trigger at 15% health instead of 25%
},
```

Changes take effect on game restart or UE4SS hot-reload.

## Multiplayer

All features work client-side in multiplayer with two caveats:

- **Food Display Fix**: If the host has it enabled, the fix applies to all players. If only a client has it enabled, the fix only applies to them.
- **Distribution Pad Range**: Host only (server-authoritative).

Not tested on dedicated servers, but those two should be the only features requiring server-side installation.

## Troubleshooting

**Mod not loading:**
- Verify `enabled.txt` exists in the mod folder
- Check UE4SS.log for errors

**Feature not working:**
- Verify it's enabled in `config.lua`
- Enable debug logging: set `DebugFlags.FeatureName = true` in config.lua
- Check UE4SS.log for `[Rebiotic Recalibration|FeatureName]` messages

**Known Issues & Workarounds:**

*Intermittent UE4SS startup crashes (~10% of launches)*

This can occur during game startup due to UE4SS injection timing and is not specific to this mod. Once in-game, it should be stable.

Workarounds:
- Restart the game
- Ensure you're on a UE4SS build compatible with your game version
- If running multiple UE4SS mods, try disabling others to isolate conflicts

When reporting issues, include: UE4SS version, game version, other installed UE4SS mods, and UE4SS.log

*Mod conflicts*

May conflict with other mods that hook the same widgets or HUD elements. If you experience issues, try disabling overlapping features in config.lua first.

## For Developers

The mod uses a module-based architecture. Each feature is a self-contained Lua file in `scripts/core/` with:
- Schema-validated configuration
- Lifecycle hooks (init, cleanup on map transition)
- Consolidated hook registration to minimize UE4SS overhead

See [docs/AddingNewFeatures.md](docs/AddingNewFeatures.md) for a guide on adding new features.

### Project Structure

```
scripts/
├── main.lua              # Entry point, module loader, lifecycle management
├── config.defaults.lua   # Default configuration (template for config.lua)
├── core/                 # Feature modules (one per feature)
│   ├── AmmoCounter.lua
│   ├── DistributionPadTweaks.lua
│   └── ...
└── utils/                # Shared utilities
    ├── HookUtil.lua      # Safe hook registration, consolidated hooks
    ├── ConfigUtil.lua    # Schema validation
    ├── ConfigMigration.lua # Auto-generates and updates config.lua
    ├── LogUtil.lua       # Logger factory
    ├── PlayerUtil.lua    # Local player caching
    └── WidgetUtil.lua    # Widget cloning
config.lua                # User configuration (auto-generated)
```
