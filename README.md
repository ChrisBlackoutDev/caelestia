# ChrisBlackoutDev Caelestia Desktop Fork

This is ChrisBlackoutDev's personal Arch Linux, Hyprland, and Caelestia desktop bootstrap fork. It tracks upstream Caelestia while carrying personal workstation packages, launchers, Hyprland Lua config, shell integration, and fresh-install automation.

This repo is not an AUR publishing workflow. Personal packages, including the shell fork package, are consumed locally through the Caelestia manifest.

## Fresh Arch Bootstrap

After `archinstall`, SSH into the new machine as the target user:

```sh
sudo pacman -Syu --needed git fish
git clone --branch codex/upstream-refresh-2026-08-05 https://github.com/ChrisBlackoutDev/caelestia.git ~/.local/share/caelestia
cd ~/.local/share/caelestia
fish bootstrap/install.fish --profile kensa-desktop --dry-run --noconfirm
fish bootstrap/install.fish --profile kensa-desktop --noconfirm
```

The bootstrap reads `profiles/kensa-desktop.toml`, performs a full `pacman -Syu` preflight, installs official packages, installs AUR packages with the configured helper, writes `~/.config/caelestia/cli.json`, then runs `caelestia install` for the enabled components.

## Important Paths

- App/service source of truth: `profiles/kensa-desktop.toml`
- Caelestia components and local packages: `manifest.toml`
- Bootstrap entrypoint: `bootstrap/install.fish`
- Personal shell fork: `/home/kensa/.local/src/shell-fork-work`
- Local shell package PKGBUILD: `bootstrap/pkgbuilds/caelestia-shell-fork/PKGBUILD`
- CLI-managed dots clone: `~/.local/state/caelestia/dots`

## Docs

- Fresh install flow: `docs/fresh-arch-install.md`
- Package ownership and app changes: `docs/package-sources.md`
- Music platform notes: `docs/music-platform.md`
- Upstream refresh procedure: `docs/upstream-sync.md`
- Validation and smoke-test checklist: `docs/validation.md`
- Future-agent rules: `AGENTS.md`

## Upstream

This fork is based on [caelestia-dots/caelestia](https://github.com/caelestia-dots/caelestia). Upstream has moved to `manifest.toml`, `caelestia-cli`, and Lua Hyprland config; do not bring back the old repo-level installer or `.conf` Hyprland layout.
