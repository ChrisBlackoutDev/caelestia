# Fresh Arch Install

After `archinstall`, SSH into the machine as the target user and install enough tooling to clone this fork:

```sh
sudo pacman -S --needed git fish
git clone https://github.com/ChrisBlackoutDev/caelestia.git ~/.local/share/caelestia
cd ~/.local/share/caelestia
fish bootstrap/install.fish --profile kensa-desktop --noconfirm
```

Use `--dry-run` first to inspect package, service, group, and Caelestia actions without changing the system.

The bootstrap installs pacman packages first, installs or reuses the configured AUR helper, installs AUR packages second, writes `~/.config/caelestia/cli.json`, then runs `caelestia install` with the profile's enabled components.

Credentials and hardware-bound setup stay manual: log into Tailscale, Mullvad, Spotify, browsers, and printer/Bluetooth devices after the base desktop is working.
