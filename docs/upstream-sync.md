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

Update `~/.local/src/caelestia-shell-fork/PKGBUILD` to pin the pushed shell fork commit. Validate with `makepkg --printsrcinfo`, then build/install the package.

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
