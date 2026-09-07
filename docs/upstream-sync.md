# Upstream Synchronization

This fork keeps personal behavior as a small layer over current Caelestia. Treat old refresh branches as intent references, not patch sources.

## Branch workflow

```sh
git fetch origin
git fetch upstream
git switch -c codex/upstream-refresh-YYYY-MM-DD upstream/main
```

Port personal changes file by file, preserving upstream changes in overlapping files. Keep the upstream README structure, Lua Hyprland architecture, current package names, nil-safe keybind construction, and rule syntax. Do not resurrect the removed upstream repo-level installer or obsolete Hyprland `.conf` architecture.

Personal state belongs in:

- `caelestia/hypr-vars.lua` for supported variable overrides;
- `caelestia/hypr-user.lua` for explicit monitor/input rules;
- `caelestia/shell.json` for shell settings;
- `profiles/kensa-desktop.toml` for package/service/group intent;
- small scripts, launchers, and local PKGBUILDs with clear ownership.

## Shell pin

Build and test the shell fork first. Update `_commit` and `pkgver` in `bootstrap/pkgbuilds/caelestia-shell-fork/PKGBUILD` only after the shell branch is pushed and both clean local and target-native builds pass. Regenerate `.SRCINFO`, compare it with `makepkg --printsrcinfo`, and commit both files together.

The rice branch must never point at an unpushed shell commit or a moving branch. Its package conflicts with stock `caelestia-shell` and `caelestia-shell-git`, so replacement is a deliberate gated package transaction.

## Review checklist

- Diff from the exact upstream base and from the previous personal refresh.
- Confirm monitor modes, positions, scaling, input sensitivity, cursor hotspot, idle timings, and keybindings.
- Confirm launcher commands exist or have an intentional fallback.
- Keep optional Spotify disabled unless explicitly selected; omit the AI shell panel.
- Preserve modern `pwvucontrol`, Neovim component support, and current upstream docs.
- Verify all official and AUR targets against the target machine's repositories.
- Review every local/AUR PKGBUILD in full and rebuild generated artifacts such as the VSIX.
- Run the static and package checks in [validation.md](validation.md).

Push only the new refresh branch. Do not rewrite the fork's default branch as part of candidate construction. Record exact rice and shell commit IDs in the migration controller before any remote mutation.

## Bootstrap contract

`bootstrap/install.fish` requires `--stage core` or `--stage profile`. Core is the only stage allowed to migrate the exact legacy links. Profile work accepts exactly one transaction per invocation: one `--package-group`, one cumulative `--sync-profile-components`, one named service, or one named group. The script never upgrades Arch, performs implicit recursive package cleanup, discovers arbitrary legacy links, writes unowned SDDM files or sudoers rules, or performs live noninteractive transactions. Provider conflicts such as `quickshell-git` replacing `quickshell` and `caelestia-shell-fork` replacing a stock shell package require an explicitly reviewed gated package transaction.

`--deploy-prebuilt` is the release-controller path: it skips all package
transactions, requires every selected manifest package and exact local package
version to be present, requires the managed checkout to equal the executing
candidate's full commit, then performs only hooks, file deployment, and state
recording.
