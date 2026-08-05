# AGENTS.md

This is ChrisBlackoutDev's personal Arch Linux, Hyprland, and Caelestia desktop bootstrap fork.

Guidelines for future Codex agents:

- Check `git status` before edits and do not overwrite uncommitted user work.
- Keep upstream Caelestia refreshes separate from personal overlay changes. Start refreshes from `upstream/main`, then port local intent intentionally.
- Preserve the current Caelestia architecture: use `manifest.toml` for components and dependencies; do not resurrect `install.fish` as the primary installer.
- Use `profiles/kensa-desktop.toml` as the source of truth for desktop applications, services, groups, and Caelestia install components.
- Keep the shell fork and rice fork coordinated. The rice manifest should use `caelestia-shell-fork` when the shell fork is the intended shell package.
- Never run live `caelestia install` or selected pacman package installs as a substitute for a full Arch upgrade. The bootstrap must run `pacman -Syu` first and validate split packages such as `networkmanager/libnm`.
- Keep `hyprlock` installed as part of the desktop profile before shell/session-lock migration.
- Do not hand-edit generated metadata such as `package-lock.json`; regenerate it with the owning tool.
- Do not hardcode `/home/kensa` unless the target format requires an absolute path, such as browser native-messaging manifests. Document any unavoidable hardcoded path.
- Test TOML, JSON, Lua, fish, and desktop files before finishing.
- Avoid live `caelestia install` or `caelestia update` when legacy symlinks or a running desktop could be disrupted. Prefer dry-run/temp-XDG validation first.
