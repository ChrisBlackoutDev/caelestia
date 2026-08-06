# Validation

Use the smallest validation set that matches the change. Do not run live installs, package installs, service changes, or VM tests during docs-only work.

## Docs-Only Changes

```sh
git diff --check
rg -n "TODO|FIXME|install\\.fish|PKGBUILD|\\.SRCINFO|hypr-user\\.conf|hypr-vars\\.conf|AUR" AGENTS.md README.md docs
```

Read the grep results as a stale-reference check, not as an automatic failure. Some references are intentional when documenting what not to do.

Do not run these for docs-only work:

```sh
caelestia install
caelestia update
sudo pacman -Syu
sudo pacman -S ...
systemctl enable --now ...
```

## Config Or Bootstrap Changes

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

Before live migration on a real Arch system:

```sh
pacman -Q networkmanager libnm
pacman -Q hyprlock
pacman -Q sddm sddm-astronaut-theme qt6-virtualkeyboard qt6-multimedia-ffmpeg
test -d /usr/share/sddm/themes/pixel-sakura
systemctl is-enabled sddm
test -d /lib/modules/$(uname -r)
sudo -v
```

`networkmanager` and `libnm` must report the same version. If they do not, run a full system upgrade before touching the live Caelestia install.

The SDDM checks confirm that the graphical login manager is installed, the configured Astronaut theme variant exists, and SDDM is enabled for next boot. If a live graphical target is available, also check `systemctl status sddm --no-pager` after the bootstrap.

If `/lib/modules/$(uname -r)` is missing after a full upgrade, reboot before validating Docker, GPU, bridge networking, or other module-backed services.

For SSH installs, make sure sudo can authenticate in that session before starting the live bootstrap. Use `ssh -tt` for live installs; an askpass helper is enough for bootstrap-owned sudo calls, but not for `caelestia-cli`'s internal sudo calls.

## Shell Fork Changes

From `/home/kensa/.local/src/shell-fork-work`:

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build
```

After updating the rice PKGBUILD pin, validate package metadata from the PKGBUILD directory:

```sh
makepkg --printsrcinfo
```

## Manual Runtime Smoke Checks

These are reference checks after a live install. Do not execute them during docs-only work.

- Shell starts and can restart.
- Launcher opens and modifier-only launcher behavior does not self-trigger during mouse/window shortcuts.
- Special workspaces open, move configured apps, and hide correctly.
- `Super+Alt+Space` toggles the current workspace between tiled and floating behavior.
- Lock, idle lock, DPMS off, and suspend-then-hibernate timings behave as expected.
- Locking still works after the shell is restarted, and Hyprland does not show the session-lock rescue screen.
- Screenshots, screen recording, clipboard history, and emoji picker work.
- Terminal toys launch: `tty-clock`, `cmatrix`, `pipes.sh`, and `cava`.
- SDDM appears at boot with the Pixel Sakura Astronaut theme and accepts password login.
- Browser, editor, file manager, thumbnails, audio, Bluetooth, printing, VPN, Docker, and desktop entries all work.
