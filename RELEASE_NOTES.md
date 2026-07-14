## v1.1-beta.3 (build 4) — 2026-07-14

This beta brings two new things and fixes a connection annoyance — all straight
from your beta feedback. Thank you.

### New

- Control Panel: a new "Control Panel" section arrives, starting with "Network
  and identity". It shows your server name, local IP address, subnet mask,
  gateway, DNS servers, IPv6 and network interface in clear, accessible cards.
  This first step is read-only; renaming the server will follow.
- Package Center: you can now apply a package update, not just see that one is
  available. When an official Synology package has an update, an "Update" button
  installs it — the NAS handles the download and install. This one is brand new
  and I couldn't fully test it on my end, so please try it and tell me how it
  goes. One honest note: a few updates need the NAS to reboot to finish — the app
  tells you, but that reboot you still trigger from DSM.

### Fixes

- Sign in: the occasional "timed out" error when connecting is gone. The app now
  retries that first request automatically and silently, so a "cold" connection
  no longer fails on the first try.

Every screen keeps the VoiceOver-first approach: clear labels, a logical focus
order, and spoken announcements on load, on error, and after each action.

### Requirements

- macOS 14 (Sonoma) or later.
- A Synology NAS running DSM 7 on your local network.

### Download

[dsmaccess-1.1-beta.3.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.3/dsmaccess-1.1-beta.3.zip)
