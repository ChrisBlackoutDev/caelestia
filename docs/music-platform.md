# Music Platform

The upstream optional `spotify` component remains in `manifest.toml` so this fork does not unnecessarily delete an upstream capability. It is deliberately absent from `profiles/kensa-desktop.toml`, is not a default component, and has no personal special-workspace command or rule. The workstation migration therefore installs neither Spotify nor Spicetify.

Media controls continue to work with MPRIS-capable browsers and players. If a dedicated music client is selected later, add its package to the correct profile category, enable a non-default component only when managed files are needed, and keep account state out of Git.
