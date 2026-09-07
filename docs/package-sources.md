# Package Sources and Ownership

`profiles/kensa-desktop.toml` is the source of truth for the personal machine package set. `manifest.toml` describes packages and files required by individual Caelestia components. `bootstrap/install.fish` only orchestrates explicit stages; personal app lists do not belong in the script.

## Sources

- `packages.official.*` contains packages from enabled Arch repositories and is installed with `pacman`.
- `packages.aur.*` contains reviewed AUR targets and is installed with `yay` only after `--approve-aur` is supplied.
- `local:bootstrap/pkgbuilds/caelestia-shell-fork` builds the shell fork from the exact commit recorded in its PKGBUILD.
- `local:bootstrap/pkgbuilds/sddm-pixel-sakura` owns the personal SDDM wrapper and both `/etc/sddm.conf.d/20-caelestia-*.conf` files.

The bootstrap installs one named profile package group per transaction. This keeps browsers, productivity tools, desktop plumbing, development tools, games, system utilities, thumbnails, terminal tools, editors, apps, audio controls, shell dependencies, and display-manager assets independently retryable. Only after every package group is present does one cumulative component sync deploy the complete enabled-component set and record it coherently in Caelestia CLI state.

## Deliberate selections

- The profile uses Microsoft Visual Studio Code via `visual-studio-code-bin`; the `code` repository package is Code OSS and is not treated as equivalent.
- `pwvucontrol` replaces the older `pavucontrol` choice.
- `networkmanager` and `libnm` are both explicit so their versions cannot drift during a selected-package transaction.
- `hyprlock` is present before the shell/session-lock migration.
- Steam remains explicit and requires the target's enabled multilib repository.
- `ttf-material-symbols-variable` and `ttf-cascadia-code-nerd` come from official repositories.
- Spotify remains an upstream optional component but is disabled by the personal profile.
- The AI shell panel is omitted. Codeium settings default to disabled in VS Code.
- `betaflight-configurator-bin` is a manual follow-up because its AUR package was flagged out of date during this refresh.
- The existing Cursor AppImage remains a rollback fallback until the managed `cursor` command is verified.

## SDDM ownership

The AUR `sddm-astronaut-theme` package owns the base Astronaut assets. The local `sddm-pixel-sakura` package owns only its wrapper symlinks, metadata, and named SDDM configuration snippets. The migration must archive the target's pre-existing unowned Astronaut directory before the AUR package transaction. Never install a second unowned wrapper or edit files owned by either package.

## Privileged theme hooks

This profile installs no passwordless sudoers rule for Papirus coloring or Chromium-family managed policy. Authenticate normally if a later cosmetic operation needs privilege, and review browser-policy writes separately.

Explicit removals, recursive cleanup, the Arch upgrade, service activation, Docker membership, and `uucp` membership are deliberately outside implicit package installation. Pacman may still need to replace conflicting providers during an approved transaction—for example stock Quickshell or Caelestia shell packages—and Gate C must list and approve those exact replacements.
