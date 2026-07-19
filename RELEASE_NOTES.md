## v1.1-beta.4 (build 5) — 2026-07-19

This is a large update. DSM Access has been rebuilt around native macOS — a
standard sidebar, toolbars, and a real Settings window — with full keyboard and
VoiceOver support throughout. It also adds several new areas you can manage,
stronger certificate security, and a set of fixes.

### New areas

- File Station, rebuilt: multiple selection, copy, cut and paste, uploads and
  downloads, folder creation, search, and share links with optional passwords and
  expiry dates. A details panel shows size, type, owner, permissions, and paths.
- Users and Groups.
- Download Station.
- Virtual Machine Manager.
- Container Manager, including each container's logs.
- Surveillance Station, including camera snapshots.
- Logs and Security.
- Multiple NAS: save several servers and switch between them.

### A more native app

- A standard sidebar groups everything into Overview, Files and Sharing,
  Administration, and Applications, with a keyboard shortcut for each module.
- A native Settings window (Command-comma) lets you choose which announcements you
  hear and show, hide, or reorder the modules in the sidebar.
- Common actions now live in the toolbar and the menu bar, with standard shortcuts.

### Security

- DSM Access now checks your NAS certificate. A self-signed certificate is
  accepted only after you approve its fingerprint once; the choice is remembered
  for that server, and you are asked again if the certificate later changes. This
  replaces the earlier behaviour that accepted any certificate — which matters if
  your NAS is reachable from outside your home.

### Accessibility

- VoiceOver labels, focus, and spoken feedback across every screen and every
  state: loading, empty, error, and success.
- Announcements are queued, so quick status updates are read one after another
  instead of cutting each other off.

### Fixes

- Container details open reliably again and show processor use, memory, and the
  start time.
- Container logs load correctly.
- System logs show their full message on every line.
- In Files, right-clicking several selected items keeps the whole selection, and
  the window title now follows the folder you are in.

### Thanks

- This release is in large part the work of Ashley Cox. The native rebuild, the
  new modules, and the certificate security are hers, and the difference they make
  is hard to overstate. Thank you, Ashley.

### Requirements

- macOS 14 (Sonoma) or later.
- A Synology NAS running DSM 7 on your local network.

### Download

[dsmaccess-1.1-beta.4.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.4/dsmaccess-1.1-beta.4.zip)
