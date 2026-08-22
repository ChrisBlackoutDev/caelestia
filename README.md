# caelestia

## ChrisBlackoutDev personal fork

This is a personal, AI-assisted fork of
[`caelestia-dots/caelestia`](https://github.com/caelestia-dots/caelestia).
It tracks the current Lua-based Hyprland configuration and Caelestia CLI
installer while retaining the custom desktop behavior used on my Arch setup.

Personal changes include:

- Firefox as the default browser (`Super + W`) and VSCodium as the editor.
- A shell configuration with a 30-minute idle lock and delayed display sleep
  and suspend.
- A current-workspace floating toggle on `Super + Alt + Space` that preserves
  window geometry.
- A top-right Quickshell AI helper with a narrow edge trigger.
- Thunar thumbnailing and removable-media defaults.
- Cursor, Steam, and OrcaSlicer launcher entries.
- Wallpaper-palette-aware wrappers for `tty-clock`, `cmatrix`, `pipes.sh`, and
  `cava`.
- Hardened Firefox and VSCodium theme integrations.

The original legacy installer and metapackage have been removed. Current
Hyprland releases use this repository's Lua configuration and the component
manifest in [`manifest.toml`](manifest.toml).

## Installation on Arch Linux

Clone the fork to the stable path used by the Caelestia updater:

```sh
git clone git@github.com:ChrisBlackoutDev/caelestia.git ~/.local/share/caelestia
```

Install an AUR helper and the Caelestia CLI, then install from this checkout:

```sh
yay -S caelestia-cli
CAELESTIA_DOTS="$HOME/.local/share/caelestia" caelestia install
```

The default components provide Hyprland, Caelestia Shell, Firefox, Foot/Fish,
Thunar, PipeWire, networking, Bluetooth, fonts, themes, clipboard tools, and
the personal configurations in this fork. Optional application components can
be selected by the installer, including Spotify, VSCodium, Equibop, Todoist,
UWSM, Zed, Neovim, and Zen.

The dots installer manages copied files rather than the old repository
symlinks, but keeping the checkout at `~/.local/share/caelestia` is recommended
for predictable updates and local development.

## Updating

Run:

```sh
caelestia update
```

Pull and reconcile this fork with `upstream/main` before accepting upstream
dotfile updates that overlap personal behavior.

## Configuration

Do not edit installed files in `~/.config/hypr` directly. Put machine-local
overrides in:

- `~/.config/caelestia/hypr-vars.lua` for default apps, styling, and keybinds.
- `~/.config/caelestia/hypr-user.lua` for monitor rules and custom Hyprland
  configuration.
- `~/.config/caelestia/shell.json` for shell behavior.
- `~/.config/caelestia/cli.json` for special-workspace application behavior.

See [`hypr/variables.lua`](hypr/variables.lua) for all variable names. For
example:

```lua
return {
  browser = "firefox",
  editor = "codium",
  windowBorderSize = 2,
}
```

## Main keybinds

- `Super`: launcher
- `Super + 1` through `0`: workspaces 1 through 10
- `Super + Alt + 1` through `0`: move the active window
- `Super + T`: Foot terminal
- `Super + W`: Firefox
- `Super + C`: VSCodium
- `Super + E`: Thunar
- `Super + Alt + Space`: tile/float all windows on the current workspace
- `Super + S`: special workspace
- `Super + M`: music workspace
- `Super + D`: communication workspace
- `Super + R`: todo workspace
- `Super + V`: clipboard history
- `Super + Period`: emoji picker
- `Super + L`: lock
- `Ctrl + Alt + Delete`: session menu
- `Ctrl + Super + Alt + R`: restart Caelestia Shell

The full default keybind list is maintained in the
[upstream README](https://github.com/caelestia-dots/caelestia#default-keybinds).

## Terminal toys

The Fish configuration wraps four terminal tools so new launches follow the
active Caelestia wallpaper palette:

- `tty-clock` starts centered and maps ANSI green to the current primary
  colour.
- `cmatrix` uses a transparent true-colour gradient renderer. Run
  `cmatrix --stock` for the upstream binary.
- `pipes.sh` temporarily remaps its ANSI colours and restores Foot's palette on
  exit.
- `cava` generates a fresh palette-derived gradient for every launch.

The wrappers read `~/.local/state/caelestia/scheme.json` and restore terminal
sequences from `~/.local/state/caelestia/sequences.txt` when appropriate.

## Login manager

The dots do not install a display manager. A suitable Arch setup is
[`greetd`](https://sr.ht/~kennylevinsen/greetd) with
[`tuigreet`](https://github.com/apognu/tuigreet), launching the Hyprland UWSM
desktop entry.

Upstream projects: [dots](https://github.com/caelestia-dots/caelestia),
[shell](https://github.com/caelestia-dots/shell), and
[CLI](https://github.com/caelestia-dots/cli).
