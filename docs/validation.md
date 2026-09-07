# Validation

Use the smallest non-mutating checks while constructing a candidate. Live installs, system upgrades, service changes, group changes, and graphical reloads belong behind migration gates.

## Repository checks

```sh
git diff --check
for script in bootstrap/install.fish bootstrap/lib/*.fish bootstrap/tests/*.fish fish/functions/*.fish hypr/scripts/*.fish; do
  fish --no-execute "$script" || exit 1
done
fish bootstrap/tests/legacy-links.fish
fish bootstrap/tests/cutover-config.fish
fish bootstrap/tests/system-preflight.fish
bash -n firefox/init_firefox.sh firefox/tests/init-firefox.sh
bash firefox/tests/init-firefox.sh
python bootstrap/tests/apply-prebuilt.py
python -m py_compile bootstrap/apply-prebuilt.py bootstrap/tests/apply-prebuilt.py
python -c 'import json; json.load(open("caelestia/shell.json")); json.load(open("vscode/settings.json"))'
python -c 'import tomllib; tomllib.load(open("manifest.toml", "rb")); tomllib.load(open("profiles/kensa-desktop.toml", "rb"))'
luac -p caelestia/hypr-vars.lua caelestia/hypr-user.lua hypr/hyprland.lua
desktop-file-validate applications/*.desktop
```

Prove that unsafe bootstrap invocations are rejected:

```sh
fish bootstrap/install.fish --dry-run
fish bootstrap/install.fish --stage profile --dry-run
fish bootstrap/install.fish --stage profile --package-group official.browsers --package-group official.games --dry-run
fish bootstrap/install.fish --stage profile --package-group official.browsers --sync-profile-components --dry-run
fish bootstrap/install.fish --stage profile --enable-service sddm --approve-group docker --dry-run
fish bootstrap/install.fish --stage core --migrate-legacy-links --dry-run
fish bootstrap/install.fish --stage profile --package-group official.browsers --deploy-prebuilt --dry-run
```

Then inspect successful dry-runs for the fixed core, each package group, the one cumulative `--sync-profile-components --approve-aur` action, each named service, and each named group. Dry-run output must contain no executed `sudo`, package helper, config write, link move, `systemctl`, or `usermod` action. The legacy-link tests inject a mid-move failure, simulate restart discovery, preserve partial replacements during rollback, reject a wrong target, and reject reuse after a completion marker; the cutover-config tests cover existing, new, and unsafe CLI config rollback paths.

## Local package metadata

For each directory below, review the complete PKGBUILD and compare tracked metadata with generated metadata:

```sh
makepkg --verifysource
makepkg --printsrcinfo | diff -u .SRCINFO -
```

- `bootstrap/pkgbuilds/caelestia-shell-fork`
- `bootstrap/pkgbuilds/sddm-pixel-sakura`
- `packages/caelestia-firefox-theme`

Build packages in an isolated work directory. Confirm the shell package embeds the exact pinned commit, runs CTest, uses `RelWithDebInfo` for Arch split-debug support, and stages only expected paths. Confirm the SDDM package owns only the wrapper, metadata, and two named configuration snippets.

## VS Code integration

Use a maintained Node.js 22 LTS environment for this locked build toolchain. The pinned `@vscode/vsce` 3.2.1 dependency is not compatible with Arch's Node 26 runtime; Node 22 matches the extension's Node 20 type baseline and is the validated packaging environment.

```sh
cd vscode/caelestia-vscode-integration
npm ci
npm run vscode:prepublish
npx vsce package --out caelestia-vscode-integration-1.2.1.vsix
```

Inspect the VSIX manifest and confirm its built JavaScript contains the scheme-update error handler. Do not commit `node_modules` or build-only output.

## Target preflight

On the target, require a fully updated system before selected-package installation:

```sh
pacman -Qu
pacman -Q networkmanager libnm gcc gcc-libs libgcc libstdc++ lib32-gcc-libs
```

The pending-upgrade list must be empty; pacman's status 1 with empty output is
the valid no-upgrades result. NetworkManager must match `libnm`, and installed
GCC runtime packages must match. Also verify free space, package locks, boot
artifacts, network/SSH continuity, the recovery path, and current package
ownership. `bootstrap/tests/system-preflight.fish` covers empty status 1,
status 1 with diagnostic output, unexpected query failure, pending output, and
a runtime-cohort mismatch.
`bootstrap/tests/apply-prebuilt.py` covers exact local-package metadata,
missing-package rejection, and the required CLI release.

For a release-style migration, build and review every local/AUR archive before
installation, then use `bootstrap/install.fish --deploy-prebuilt`. This mode
does not execute a package transaction: `bootstrap/apply-prebuilt.py` requires
all manifest packages and exact local-package versions to be explicitly
installed, checks the managed clone is clean at the expected branch tip, and
only then deploys configuration plus the CLI-compatible managed-dots state.
Artifact byte identity remains a controller precondition because package
metadata cannot distinguish two builds with the same name and version. The
controller must write an in-progress marker before invocation; failures outside
the allowlisted legacy roots use the documented forward-fix retry from the same
artifact and source locks rather than a broad configuration rollback.

## Post-install acceptance

Verify package ownership and versions, `qs -c caelestia` source resolution, shell startup, Nexus panes, thumbnail generation, both monitors, launcher interrupt behavior, keybindings, lock/DPMS/suspend, portals, notifications, clipboard, screenshots, PipeWire, Bluetooth, printing, VPNs, Docker, SDDM, Steam, Cursor, OrcaSlicer, Todoist, Zen, office/document tools, and the deterministic Thunar `foot -D %f` terminal action.

After reboot, repeat critical checks from a local graphical session and an independent SSH session. Keep the old repositories, Cursor AppImage, and migration backups until the final verification gate is explicitly accepted.
