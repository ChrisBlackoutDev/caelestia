# AGENTS.md

This is ChrisBlackoutDev's personal Arch Linux, Hyprland, and Caelestia desktop bootstrap fork. Treat it as a private workstation automation repo, not as a public distro, generic dotfiles template, or AUR publishing workflow.

## First Steps

- Start in `/home/kensa/.local/share/caelestia`.
- Run `git status --short --branch` before edits.
- Also check `/home/kensa/.local/src/shell-fork-work` when a change touches shell behavior or the shell package pin.
- Do not overwrite uncommitted user work. If unrelated dirty files exist, leave them alone.
- Keep upstream refresh work separate from personal overlay work. Start refresh branches from `upstream/main`, then port local intent manually.

## Source Of Truth

- Personal desktop apps, services, groups, and enabled Caelestia components: `profiles/kensa-desktop.toml`.
- Caelestia components, component entries, and local package references: `manifest.toml`.
- Bootstrap entrypoint: `bootstrap/install.fish`.
- Profile parsing helpers: `bootstrap/lib/profile.fish`.
- Personal shell package PKGBUILD consumed by Caelestia: `bootstrap/pkgbuilds/caelestia-shell-fork/PKGBUILD`.
- Standalone local shell package worktree, if needed: `/home/kensa/.local/src/caelestia-shell-fork/PKGBUILD`.
- Shell source fork: `/home/kensa/.local/src/shell-fork-work`.
- CLI source selection: `~/.config/caelestia/cli.json`, with `dots.url` and `dots.branch`.
- CLI-managed dots clone: `~/.local/state/caelestia/dots`.

## What To Edit

- Add or remove normal desktop apps in `profiles/kensa-desktop.toml`.
- Add or remove Caelestia-managed config components in `manifest.toml`.
- Update the local shell package pin in `bootstrap/pkgbuilds/caelestia-shell-fork/PKGBUILD` after the shell fork commit changes.
- Mirror that PKGBUILD into `/home/kensa/.local/src/caelestia-shell-fork/PKGBUILD` only when maintaining the standalone package worktree.
- Update docs when workflow, package ownership, bootstrap behavior, or validation expectations change.

## What Not To Do

- Do not upload personal packages to the AUR. The shell fork is consumed locally through `local:bootstrap/pkgbuilds/caelestia-shell-fork`.
- Do not resurrect legacy upstream architecture: repo-level `install.fish`, repo-level `PKGBUILD`, `.SRCINFO`, or old Hyprland `.conf` files are not the primary path anymore.
- Do not blindly rebase or cherry-pick across upstream architecture changes. Upstream Caelestia now uses `manifest.toml`, `caelestia-cli`, and Lua Hyprland config.
- Do not hardcode `/home/kensa` unless the target format requires an absolute path, such as browser native-messaging manifests. Document each exception.
- Do not hand-edit generated metadata such as `package-lock.json`; regenerate it with the owning tool.
- Do not run live `caelestia install`, `caelestia update`, package installs, `systemctl` changes, or smoke tests during docs-only work.

## Live Migration Warnings

- Avoid live `caelestia install` or `caelestia update` when legacy symlinks or a running desktop could be disrupted. Prefer dry-run or temporary XDG validation first.
- Never run live selected-package installs as a substitute for a full Arch upgrade. The bootstrap must run `pacman -Syu` first.
- Validate split packages such as `networkmanager/libnm` before live migration.
- Keep `hyprlock` installed as part of the desktop profile before shell/session-lock migration.
- Stay present and keep the desktop unlocked during live shell/compositor-adjacent migrations.

## Validation

Docs-only changes:

```sh
git diff --check
rg -n "install\.fish|PKGBUILD|\.SRCINFO|hypr-user\.conf|hypr-vars\.conf|AUR" AGENTS.md README.md docs
```

Config or script changes:

```sh
python - <<'PY'
import tomllib
for path in ("manifest.toml", "profiles/kensa-desktop.toml"):
    tomllib.load(open(path, "rb"))
PY
find hypr -name '*.lua' -print0 | xargs -0 -r luac -p
find . -path '*/node_modules/*' -prune -o -name '*.json' -print0 | xargs -0 -r -n1 python -m json.tool >/dev/null
find . -path '*/node_modules/*' -prune -o -name '*.fish' -print0 | xargs -0 -r fish -n
find applications -name '*.desktop' -print0 | xargs -0 -r desktop-file-validate
fish bootstrap/install.fish --profile kensa-desktop --dry-run --noconfirm
```

Shell fork changes:

```sh
cd /home/kensa/.local/src/shell-fork-work
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build
```

## Git Workflow

- Use focused branches and focused commits.
- Commit clean checkpoints after validation.
- Push when the repo is ready and the user asked for the update to be published.
- Keep rice and shell commits coordinated: if shell behavior changes, push shell first, then update and commit the rice PKGBUILD pin.
