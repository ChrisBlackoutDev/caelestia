# Music Platform

Spotify has intentionally been removed from this personal desktop profile. Do not add `spotify`, `spicetify-cli`, or `spicetify-marketplace-bin` back unless the user explicitly asks for Spotify again.

Caelestia itself does not require Spotify for the desktop to work. The old Spotify integration was only:

- an optional `spotify` component in `manifest.toml`;
- AUR packages in `profiles/kensa-desktop.toml`;
- a Spicetify theme under `spicetify/`;
- a default special-workspace launcher entry in `hypr/utils/functions.lua`.

When migrating to another music platform, update these places instead:

- Add the app package to `profiles/kensa-desktop.toml`.
- Add a Caelestia component in `manifest.toml` only if the app needs managed config files or hooks.
- Add a special-workspace entry under `music` in `hypr/utils/functions.lua` if it should open or move like the old Spotify workspace.
- Prefer MPRIS-compatible players so Caelestia media controls continue to work through standard desktop media interfaces.
- Keep login tokens, account setup, music libraries, and service credentials out of the repo.
