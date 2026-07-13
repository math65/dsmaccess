## v1.1-beta.1 (build 2) — 2026-07-13

This is a **beta** release — a preview of what's coming in 1.1. It builds on 1.0
with three new areas for managing your NAS. Feedback is welcome.

### New: Shared Folders

- See all your shared folders, with the volume each one lives on.
- Create a new shared folder, choosing its volume.
- Delete a shared folder — behind a deliberate confirmation, since this erases its contents.

### New: File Services

- Turn the file-sharing protocols on or off: SMB, NFS, FTP and rsync.
- Disabling a service asks you to confirm first, and explains what it will interrupt.

### New: Package Center

- See every installed package, its version, and whether it is running.
- Spot which packages have an update available.
- Start or stop a package.
- Uninstall a package, with an honest heads-up about what is — and isn't — removed.
- Settings: choose the automatic-update policy, show or hide beta packages, and
  turn update notifications on or off.

Every screen keeps the VoiceOver-first approach of 1.0: clear labels, a logical
focus order, and spoken announcements on load, on error, and after each action.

### Requirements

- macOS 14 (Sonoma) or later.
- A Synology NAS running DSM 7 on your local network.

### Download

[dsmaccess-1.1-beta.1.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.1/dsmaccess-1.1-beta.1.zip)
