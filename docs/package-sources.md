# Package Sources

`profiles/kensa-desktop.toml` is the app source of truth.

Use `packages.official.*` for Arch repo packages installed with pacman. Use `packages.aur.*` for AUR packages installed with the configured helper. Keep packages grouped by purpose so future agents can add or remove apps without guessing why they exist.

Bundled PKGBUILDs belong in `manifest.toml` with the `local:` prefix, for example `local:bootstrap/pkgbuilds/caelestia-shell-fork`. The personal shell fork package does not need an AUR package; `caelestia install` builds the bundled PKGBUILD from the managed dots clone.

Services are listed under `[services]`. User group membership is listed under `[groups]`. Risky or credential-bound setup belongs under `[manual]`, not in the bootstrap.

Caelestia components are listed under `[caelestia].enable_components`; those names must match `manifest.toml`.

Keep split-package runtime pairs explicit when a profile includes one side. For this desktop, `networkmanager` and `libnm` are both listed so selected-package installs do not advance NetworkManager while leaving its library package behind. The bootstrap also validates this pair before live migration.

`hyprlock` is part of the desktop package set and the `hypr` component. Even when Caelestia/Quickshell provides the primary lock UI, `hyprlock` must be installed before live shell/session-lock migration so Hyprland has a known lockscreen fallback available.

When changing package metadata, validate:

```sh
python - <<'PY'
import tomllib
tomllib.load(open("profiles/kensa-desktop.toml", "rb"))
tomllib.load(open("manifest.toml", "rb"))
PY
fish -n bootstrap/install.fish bootstrap/lib/profile.fish
```

Path note: `zen/native_app/manifest.json` contains `/home/kensa/.local/lib/caelestia/caelestiafox-zen` because browser native-messaging manifests require an absolute executable path. Keep this exception isolated and documented.
