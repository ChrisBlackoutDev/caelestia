# Validation

Run static validation before installing live dots:

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

For shell changes, build the shell fork first, then validate package metadata:

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build
makepkg --printsrcinfo
```

Manual smoke tests after live install:

- Shell starts and can restart.
- Launcher opens and modifier-only launcher behavior does not self-trigger during mouse/window shortcuts.
- Special workspaces open, move configured apps, and hide correctly.
- `Super+Alt+Space` toggles the current workspace between tiled and floating behavior.
- Lock, idle lock, DPMS off, and suspend-then-hibernate timings behave as expected.
- Screenshots, screen recording, clipboard history, and emoji picker work.
- Terminal toys launch: `tty-clock`, `cmatrix`, `pipes.sh`, and `cava`.
- Browser, editor, file manager, thumbnails, audio, Bluetooth, printing, VPN, Docker, and desktop entries all work.
