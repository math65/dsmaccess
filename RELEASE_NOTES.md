## v1.1-beta.3 (build 4) — 2026-07-14

This beta adds accessible network identity and package update controls, and
improves recovery from transient timeouts.

### New

- Control Panel: the new read-only "Network and identity" overview shows the
  server name, local IP address, subnet mask, gateway, DNS servers, IPv6 address,
  and network interface.
- Package Center: official Synology package updates can now be confirmed and
  installed from the app. The NAS downloads, installs, and restarts the package.
  If an update requires a NAS restart, complete it from DSM.

### Fixes

- Connections and read requests recover from a transient timeout with one
  automatic retry. Administrative actions are never retried automatically.

Both additions include explicit VoiceOver labels, focused loading and error
states, and spoken progress and result announcements.

### Requirements

- macOS 14 (Sonoma) or later.
- A Synology NAS running DSM 7 on your local network.

### Download

[dsmaccess-1.1-beta.3.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.3/dsmaccess-1.1-beta.3.zip)
