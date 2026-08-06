# Fresh Arch Install

This flow is for ChrisBlackoutDev's personal desktop after a normal `archinstall` run. It is usually executed over SSH from another machine, before relying on the graphical desktop.

## Flow

1. Finish `archinstall` and boot the new system.
2. SSH in as the target user, normally `kensa`.
3. Install only the tools needed to clone and run the bootstrap:

   ```sh
   sudo pacman -Syu --needed git fish
   ```

4. Clone this fork:

   ```sh
   git clone --branch codex/upstream-refresh-2026-08-05 https://github.com/ChrisBlackoutDev/caelestia.git ~/.local/share/caelestia
   cd ~/.local/share/caelestia
   ```

5. Inspect the plan without changing the system:

   ```sh
   fish bootstrap/install.fish --profile kensa-desktop --dry-run --noconfirm
   ```

6. Run the bootstrap:

   ```sh
   fish bootstrap/install.fish --profile kensa-desktop --noconfirm
   ```

## What The Bootstrap Does

- Reads `profiles/kensa-desktop.toml`.
- Runs a full Arch upgrade with `sudo pacman -Syu` before selected package installs.
- Installs official repo packages first.
- Installs or reuses the configured AUR helper.
- Installs AUR packages second.
- Writes `~/.config/caelestia/cli.json` so `caelestia-cli` points at this fork and branch.
- Runs `caelestia install` with the profile's enabled components.
- Enables configured services.
- Adds the target user to configured groups.

The full upgrade preflight is intentional. Arch does not support partial upgrades; installing a named package such as `networkmanager` without upgrading the matching `libnm` package can break networking after restart.

## Safety Notes

- Run the dry-run first.
- Do not invoke `caelestia install` directly for a fresh machine; use `bootstrap/install.fish` so the preflight checks run.
- Do not go AFK during a live desktop migration. Keep the session unlocked while shell, lock, and compositor-adjacent packages are being changed.
- The bootstrap uses `systemd-inhibit` where available, but compositor-level idle lockers may still trigger.
- Avoid live migration on an active desktop when legacy symlinks from `~/.local/share/caelestia` to `~/.config` may still exist.

## Manual Aftercare

These remain manual because they need credentials, hardware, or local judgment:

- Log into Tailscale and Mullvad.
- Log into browsers, Todoist, Zoom, GitHub Desktop, and other account-backed apps.
- Pair Bluetooth devices.
- Add printers and test printing.
- Confirm Docker group membership after logging out and back in.
- Connect serial/flight-controller hardware before changing any device-specific rules.
