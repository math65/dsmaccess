## v1.1-beta.8 (build 9) — 2026-07-23

### Highlights

- The app now shows up in English when your Mac's language is neither French
  nor English — nothing to configure.
- Package Center: the switch between installed packages and the official
  catalog is now part of the screen itself, where VoiceOver finds it naturally.

### Fixes

- Package Center: the Installed / Official catalog switch lived in the window
  toolbar, an area VoiceOver treats separately without ever hinting that a
  choice exists there. The switch now sits at the top of the screen, in normal
  reading order, announced as a proper two-option choice.
- Package Center: with an account that has no administrator rights, the catalog
  tab showed a misleading "no matching packages" message. It now explains that
  DSM only provides the catalog to administrator accounts.
- Language: on a Mac set to a language the app doesn't ship (Hungarian, for
  example), the app appeared in French. It now appears in English, and picking
  a language for the app in System Settings works as expected.
- VoiceOver: the main lists now introduce themselves — "Files and folders",
  "Shared folders", "Users", "Groups", "File services", "Installed packages",
  "Pools, volumes, and disks" — instead of announcing an anonymous table. Rows
  in Shared Folders also announce their nature properly.
- VoiceOver: the Package Center switch no longer announces its name twice.
- Legibility: status and detail text across the app — package states, versions,
  disk health, log details, the summaries at the bottom of a screen — is now
  noticeably darker and meets the recommended contrast for small text, in both
  light and dark mode. A welcome change with low vision.

### Requirements

- macOS 14 (Sonoma) or later.
- A Synology NAS running DSM 7 on your local network.

### Download

[dsmaccess-1.1-beta.8.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.8/dsmaccess-1.1-beta.8.zip)

## v1.1-beta.7 (build 8) — 2026-07-22

### Highlights

- Installing a package file (.spk) now works: it used to fail every time with
  a NAS error (code 101).
- The app now checks for its own updates at launch, and a new settings pane
  can install them automatically, with no dialog to answer.

### New

- Settings > Updates: checking at launch is now on by default (you can turn it
  off), and a "Download and install automatically" option installs the new
  version when the app quits — no more answering a dialog for every update.
  The pane also shows the installed version and a check-now button.

### Fixes

- Packages: installing or updating a package from an .spk file you downloaded
  yourself now goes through, instead of failing right away with a NAS error
  (code 101). The app now talks to the Package Center exactly the way DSM
  itself does, verified on DSM 7.4.

### Requirements

- macOS 14 (Sonoma) or later.
- A Synology NAS running DSM 7 on your local network.

### Download

[dsmaccess-1.1-beta.7.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.7/dsmaccess-1.1-beta.7.zip)

## v1.1-beta.6 (build 7) — 2026-07-21

### Highlights

- Connect with QuickConnect: enter your QuickConnect ID instead of an address
  and port, and the app finds the best route to your NAS by itself.
- The Package Center becomes a full module: browse the official Synology catalog
  and install, update, repair or uninstall packages without leaving the app —
  and package installs now work reliably on DSM 7.4.
- Files gains the features that were still missing: detailed file information,
  advanced search, favorites, share link management, archive browsing and
  transfer progress.
- Creating users works again on DSM 7.4, and group members are counted
  correctly.

### New

- Sign in with QuickConnect: pick "QuickConnect" on the sign-in screen, enter
  your QuickConnect ID and your usual DSM account. The app prefers a direct,
  verified route to your NAS and only falls back to the Synology relay when
  needed — always over HTTPS. Note that QuickConnect has no official public
  interface, so Synology may change this service without notice.
- Packages: browse the official catalog, install a package with one action, or
  install a package file (.spk) you downloaded yourself. Updates, repairs and
  uninstalls are handled from the same list, with clear confirmations before
  anything runs.
- Packages: manage package sources and Package Center settings from the app.
- Files: see full details for any file or folder, search with advanced criteria
  (name, type, size, dates, owner), and manage your favorites.
- Files: create and manage share links, including passwords and expiry dates.
- Files: look inside an archive and extract only the items you need.
- Files: uploads and downloads now show their progress, and copy or move
  operations ask you before overwriting anything.
- A contact form in the Help menu lets you write to the developer directly from
  the app; occasional announcements may appear at launch.

### Fixes

- Accounts: creating a user on DSM 7.4 no longer fails with a permission error,
  group member counts are correct, and when something does go wrong the app now
  tells you instead of failing silently.
- Packages: installing or updating a package on DSM 7.4 no longer fails with a
  NAS error.
- VoiceOver: opening Files no longer announces "Empty folder" while the content
  is still loading — you now hear the real item count straight away.
- VoiceOver: if your session expires and the app reconnects automatically, a
  notice now explains that the operation in progress was interrupted, instead
  of returning you to the overview without a word.

### Thanks

- Thanks to Ashley Cox for the QuickConnect, File Station and Package Center
  work at the heart of this release.

### Requirements

- macOS 14 (Sonoma) or later.
- A Synology NAS running DSM 7 on your local network.

### Download

[dsmaccess-1.1-beta.6.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.6/dsmaccess-1.1-beta.6.zip)

## v1.1-beta.5 (build 6) — 2026-07-19

### Highlights

- Fixes a sign-in problem introduced in beta.4: approving your NAS certificate
  now works, instead of the trust prompt coming back again and again.

### Fixes

- When macOS does not recognise your NAS certificate, approving it once now signs
  you in on the first try, and the choice is remembered for that server. In
  beta.4 the approval did not take, so the trust prompt kept reappearing and left
  you stuck on the sign-in screen.

### Thanks

- Thanks to Ashley Cox, who tracked this down and fixed it.

### Requirements

- macOS 14 (Sonoma) or later.
- A Synology NAS running DSM 7 on your local network.

### Download

[dsmaccess-1.1-beta.5.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.5/dsmaccess-1.1-beta.5.zip)
