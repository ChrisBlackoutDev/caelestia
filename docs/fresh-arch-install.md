# Fresh Arch Install

After `archinstall`, SSH into the machine as the target user and install enough tooling to clone this fork:

```sh
sudo pacman -S --needed git fish
git clone https://github.com/ChrisBlackoutDev/caelestia.git ~/.local/share/caelestia
cd ~/.local/share/caelestia
fish bootstrap/install.fish --profile kensa-desktop --noconfirm
```

Use `--dry-run` first to inspect package, service, group, and Caelestia actions without changing the system.

The bootstrap first runs a full Arch upgrade with `sudo pacman -Syu`. This is required before any selected-package install or live Caelestia migration. Arch does not support partial upgrades; installing a named package such as `networkmanager` without upgrading its split packages can leave runtime libraries such as `libnm` behind and break networking after a restart.

After the full upgrade, the bootstrap installs pacman packages first, installs or reuses the configured AUR helper, installs AUR packages second, writes `~/.config/caelestia/cli.json`, then runs `caelestia install` with the profile's enabled components.

Before `caelestia install`, the bootstrap fails closed if known split packages are inconsistent or if `hyprlock` is missing. `hyprlock` is required as a lockscreen fallback before changing the running shell/session-lock stack.

During a live desktop migration, stay present and keep the session unlocked until the install finishes. The bootstrap uses `systemd-inhibit` where available to block system idle, sleep, and shutdown, but compositor-level idle lockers can still trigger independently.

Credentials and hardware-bound setup stay manual: log into Tailscale, Mullvad, Spotify, browsers, and printer/Bluetooth devices after the base desktop is working.
