# Package Sources

`profiles/kensa-desktop.toml` is the source of truth for the personal desktop package set. `manifest.toml` is the source of truth for Caelestia components and files that `caelestia-cli` should install.

## Responsibilities

- `profiles/kensa-desktop.toml`: apps, system services, user groups, manual setup notes, configured AUR helper, and enabled Caelestia components.
- `manifest.toml`: component definitions, component package dependencies, copied config entries, local package references, and component hooks.
- `bootstrap/install.fish`: orchestration only. Do not hardcode personal app lists here.

## Package Types

- Official repo packages live under `packages.official.*` in the profile and are installed with pacman.
- AUR packages live under `packages.aur.*` in the profile and are installed with the configured helper, currently `paru`.
- Local package entries belong in `manifest.toml` with the `local:` prefix.

The personal shell fork is intentionally local:

```toml
packages = ["caelestia-cli", "local:bootstrap/pkgbuilds/caelestia-shell-fork"]
```

Do not publish `caelestia-shell-fork` to the AUR for this workflow. The local PKGBUILD pins a commit from `https://github.com/ChrisBlackoutDev/shell-fork`, and `caelestia install` builds it from the managed dots clone.

Spotify has intentionally been removed from this setup. See `docs/music-platform.md` before adding music app packages or theming hooks.

## Display Manager Packages

The personal display manager setup is SDDM with Keyitdev's Astronaut theme family. Keep this split across the profile sections:

- Official packages: `sddm`, `qt6-5compat`, `qt6-declarative`, `qt6-multimedia-ffmpeg`, `qt6-svg`, and `qt6-virtualkeyboard`.
- AUR package: `sddm-astronaut-theme`.
- Service: `sddm` under `[services].enable`.
- Config: `[display_manager.sddm]` with `theme = "pixel-sakura"`, `source_theme = "sddm-astronaut-theme"`, `config_file = "Themes/pixel_sakura.conf"`, and `input_method = "qtvirtualkeyboard"`.

The bootstrap writes `/etc/sddm.conf.d/theme.conf` and `/etc/sddm.conf.d/virtualkbd.conf` from the profile. If the AUR package only installs the base `sddm-astronaut-theme` directory, the bootstrap creates a small `pixel-sakura` wrapper theme that points at package-managed Astronaut assets and selects `Themes/pixel_sakura.conf`. Do not hand-edit package-owned files in `/usr/share/sddm/themes/sddm-astronaut-theme`; package, profile, or document theme changes instead.

## Adding Or Removing An App

1. Decide whether the package is official repo, AUR, or local.
2. Edit `profiles/kensa-desktop.toml` for normal apps and services.
3. Edit `manifest.toml` only when Caelestia should manage a component, config entry, local package, or component-specific hook.
4. Keep services under `[services]`, groups under `[groups]`, and credential/hardware work under `[manual]`.
5. Validate TOML and run a bootstrap dry-run before live changes.

## Split Packages And Runtime Pairs

Keep split-package runtime pairs explicit when a profile includes one side. For this desktop, `networkmanager` and `libnm` are both listed so selected-package installs do not advance NetworkManager while leaving its library package behind. The bootstrap also validates this pair before live migration.

`hyprlock` is part of the desktop package set and the `hypr` component. Even when Caelestia/Quickshell provides the primary lock UI, `hyprlock` must be installed before live shell/session-lock migration so Hyprland has a known lockscreen fallback available.

Keep provider choices explicit when unattended pacman installs would otherwise pick the first provider. `tesseract-data-eng` is listed so OCR dependencies get English data instead of an arbitrary language package, and `tinyxxd` is listed so packages needing `xxd` do not pull in the larger `gvim` package by default.

Known accidental provider packages belong in `[packages.cleanup]`, not in ad hoc install notes. Use `remove_before_install` for packages that conflict with preferred providers, and `remove_after_install` when the preferred replacement must be installed first to keep dependencies satisfied. This lets reruns converge from an earlier partial/default-provider state.

Some AUR packages used here are source builds, not binary downloads. `quickshell-git` and AppImage integration dependencies can compile for a long time on older desktops; treat steady compiler output as progress, not a hang. If source build time becomes too painful, prefer swapping the package source in the profile to a trustworthy binary package rather than adding one-off install commands to the bootstrap.

## Hardcoded Paths

Avoid hardcoded `/home/kensa` paths unless the target format requires an absolute executable path. Browser native-messaging manifests are the known exception; keep those paths isolated and documented.
