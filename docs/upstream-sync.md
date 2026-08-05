# Upstream Sync

Use this procedure when refreshing from upstream Caelestia or upstream shell. Do not assume prior chat context.

## Rules

- Check `git status --short --branch` in every repo before changing files.
- Use new refresh branches from upstream `main`.
- Do not blindly rebase or cherry-pick if upstream changed architecture.
- Keep shell fork changes and rice fork changes separate, then coordinate them through the rice PKGBUILD pin.
- Do not publish personal shell packages to the AUR.

## Shell Fork First

```sh
cd /home/kensa/.local/src/shell-fork-work
git status --short --branch
git fetch upstream main
git switch -c codex/upstream-refresh-YYYY-MM-DD upstream/main
```

Port only local fixes that upstream still lacks. Inspect upstream first; skip patches that are already superseded.

Build before packaging:

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build
```

Commit and push the shell fork refresh before updating the rice package pin.

## Shell Package Pin

Update the rice PKGBUILD:

```text
bootstrap/pkgbuilds/caelestia-shell-fork/PKGBUILD
```

Pin `source` and `GIT_REVISION` to the pushed shell fork commit. Keep `pkgver` and `provides` consistent with the shell version being packaged.

If maintaining the standalone package worktree, mirror the same PKGBUILD to:

```text
/home/kensa/.local/src/caelestia-shell-fork/PKGBUILD
```

Validate package metadata from the PKGBUILD directory:

```sh
makepkg --printsrcinfo
```

## Rice Fork

```sh
cd /home/kensa/.local/share/caelestia
git status --short --branch
git fetch upstream main
git switch -c codex/upstream-refresh-YYYY-MM-DD upstream/main
```

Port personal changes into the current upstream architecture:

- `manifest.toml` for components and local packages.
- `profiles/kensa-desktop.toml` for personal apps, services, groups, and enabled components.
- `hypr/*.lua` and `hypr/hyprland/*.lua` for Hyprland config.
- `hypr/utils/functions.lua` only when shared Lua helpers are needed.

Do not resurrect old repo-level `install.fish`, repo-level `PKGBUILD`, `.SRCINFO`, or legacy Hyprland `.conf` config as the primary architecture.

## CLI Source

Before live migration, verify `~/.config/caelestia/cli.json` points at the intended fork branch:

```json
{
    "dots": {
        "url": "https://github.com/ChrisBlackoutDev/caelestia.git",
        "branch": "codex/upstream-refresh-YYYY-MM-DD"
    }
}
```

`caelestia-cli` clones managed dots under `~/.local/state/caelestia/dots`.

## Validation And Migration

Run static validation first. Then use the bootstrap dry-run:

```sh
fish bootstrap/install.fish --profile kensa-desktop --dry-run --noconfirm
```

For live migration, use the bootstrap rather than direct `caelestia install`:

```sh
fish bootstrap/install.fish --profile kensa-desktop --noconfirm
```

The bootstrap performs a full `pacman -Syu`, checks split-package consistency, requires `hyprlock`, and only then runs `caelestia install`.

Avoid going AFK during live migration. The shell, session lock, and compositor-adjacent packages may restart while the desktop is still running.
