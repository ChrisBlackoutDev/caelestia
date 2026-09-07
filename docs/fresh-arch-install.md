# Fresh Arch Install

This procedure is for the `kensa-desktop` profile after a normal Arch installation. Run it from a local console or an SSH session with a pseudo-terminal. Live package work remains interactive.

## 1. Update the operating system separately

Arch does not support partial upgrades. Refresh the whole system before using the profile bootstrap, and reboot if the kernel, boot chain, graphics stack, or core libraries changed.

```sh
sudo pacman -Syu
sudo reboot
```

After reconnecting, install only the checkout prerequisites:

```sh
sudo pacman -S --needed git fish
git clone --branch codex/upstream-refresh-2026-09-07 \
  https://github.com/ChrisBlackoutDev/caelestia.git \
  ~/src/caelestia
cd ~/src/caelestia
```

## 2. Validate and install the core

Review both local PKGBUILDs and all AUR targets first. Dry-run output is safe to capture because it does not install packages, modify config, enable services, or change groups.

```sh
fish bootstrap/install.fish --stage core --dry-run
fish bootstrap/install.fish --stage core --approve-aur
```

The core stage installs the build prerequisites, shell/CLI runtime, lockscreen fallback, and core Caelestia components. It does not run `pacman -Syu`, issue an explicit removal or recursive cleanup, configure SDDM, enable services, install sudoers rules, or add groups. On an existing workstation, pacman can still propose replacing a conflicting stock provider; accept only the exact replacement set approved at the migration gate.

For migration from the old fork rather than a fresh machine, keep the checksummed Phase 2 backup immutable. Create a separate empty cutover journal beneath the target user's home, then pass that work directory with the exact link migration flags:

```sh
fish bootstrap/install.fish --stage core --approve-aur \
  --migrate-legacy-links \
  --legacy-link-journal /home/kensa/caelestia-migration-2026-09-07/work/legacy-link-journal
```

The journal must already exist beneath the target user's home, must not be a symlink, and must be owned by that user. It is retry state, not a backup: saved links, an expected-link manifest, and any recoverably quarantined partial replacements remain there for inspection. Only the 11 target-specific links with exact expected targets are moved. Unexpected regular files or link targets stop the first run. An interrupted retry recognizes exact saved links, and any failed rollback moves partial managed replacements into a timestamped recovery tree before restoring the legacy links. Successful replacement validation writes `COMPLETED`; the bootstrap refuses to reuse that journal for another cutover.

## 3. Install profile package batches

Install and verify one category at a time. AUR examples require explicit approval after complete PKGBUILD review.

```sh
fish bootstrap/install.fish --stage profile --package-group official.browsers
fish bootstrap/install.fish --stage profile --package-group official.productivity
fish bootstrap/install.fish --stage profile --package-group aur.editors --approve-aur
```

List every available category with:

```sh
fish -c 'source bootstrap/lib/profile.fish; profile_package_groups profiles/kensa-desktop.toml'
```

Install every category returned by that command, including both terminal-toy groups. After all package batches succeed, perform one cumulative sync of the profile's complete component set:

```sh
fish bootstrap/install.fish --stage profile --sync-profile-components --approve-aur
```

The sync refuses to run while any declared profile package is missing. Supplying the complete component list in one operation prevents Caelestia CLI state from forgetting an earlier optional component.

## 4. Finish privileged actions explicitly

Service and group actions are individually named and validated against the profile:

```sh
fish bootstrap/install.fish --stage profile --enable-service sddm
fish bootstrap/install.fish --stage profile --enable-service docker
fish bootstrap/install.fish --stage profile --approve-group docker
```

Only add `uucp` after connected serial hardware proves it is necessary. Log out and back in after any group change. The profile installs no passwordless theme or browser-policy sudoers rule; authenticate normally for any later privileged cosmetic action.

For a migration, run the candidate from a separate controller/staging checkout while the recognized old fork remains at `~/.local/share/caelestia`. A fresh installation should use a normal source path such as `~/src/caelestia`; the Caelestia CLI owns its managed checkout beneath `~/.local/state/caelestia`.

Do not use live `--noconfirm`; the bootstrap accepts it only for dry-run command rendering. Follow [validation.md](validation.md) before relying on the graphical login or deleting any recovery material.
