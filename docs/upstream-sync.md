# Upstream Sync

Shell fork refresh:

```sh
cd ~/.local/src/shell-fork-work
git status --short --branch
git fetch upstream main
git switch -c codex/upstream-refresh-YYYY-MM-DD upstream/main
```

Port only local fixes that upstream still lacks, then build:

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build
```

Update `bootstrap/pkgbuilds/caelestia-shell-fork/PKGBUILD` in the rice repo to pin the pushed shell fork commit. Mirror the same PKGBUILD into `~/.local/src/caelestia-shell-fork/PKGBUILD` if you want a standalone local package worktree. Validate with `makepkg --printsrcinfo`, then build/install the package.

Rice fork refresh:

```sh
cd ~/.local/share/caelestia
git status --short --branch
git fetch upstream main
git switch -c codex/upstream-refresh-YYYY-MM-DD upstream/main
```

Port personal changes into the current Lua and manifest architecture. Do not bring back legacy `.conf` Hyprland files or `install.fish` as the main installer.

Before live migration, check `~/.config/caelestia/cli.json` points at the intended fork branch:

```json
{
    "dots": {
        "url": "https://github.com/ChrisBlackoutDev/caelestia.git",
        "branch": "codex/upstream-refresh-YYYY-MM-DD"
    }
}
```

Then run the bootstrap from the refreshed rice fork rather than invoking `caelestia install` directly:

```sh
fish bootstrap/install.fish --profile kensa-desktop --dry-run --noconfirm
fish bootstrap/install.fish --profile kensa-desktop --noconfirm
```

The live bootstrap performs a full `pacman -Syu` before selected package installs, checks split-package consistency, requires `hyprlock`, and only then runs `caelestia install`. Avoid going AFK during this step; shell, lock, and compositor-adjacent packages may be restarted while the desktop is still running.
