## v1.1 (build 23) — 2026-08-03

### Highlights

- The first stable release since 1.0. It gathers everything published in the
  betas since 19 July, plus external device support added today.
- Seven modules that did not exist in 1.0: Resource Monitor, Logs and Security,
  Package Center, Containers, USB Copy, External Devices, and permissions in
  Users and Groups.
- Files works with the Finder: copy in one, paste in the other, in both
  directions.

### New

- External Devices: a new Control Panel section lists the USB and eSATA drives
  connected to the NAS, with their maker, model, capacity and state, and the
  partitions of the selected one with their file system, sizes and shared
  folder.
- External Devices: eject a drive, or format it in EXT4, FAT32 or EXFAT. Both
  live in the table's context menu. Formatting asks twice, names the drive and
  says plainly that nothing can be undone.
- External Devices: an eject button appears in the toolbar as soon as something
  is plugged in, so you never have to go looking for the screen. The list
  refreshes on its own when you come back to the app, which is when a drive has
  just been connected.
- External Devices: the advanced settings are there too — forbidding the USB
  port, letting non-administrators eject, and delayed allocation for ext4.
  Forbidding the USB port asks for confirmation, since it cuts off every device
  and needs a restart.

### Changes

- The keyboard shortcuts for the last modules moved from Command-Shift to
  Command-Option. macOS keeps Command-Shift-3, 4 and 5 for screen capture and
  always wins, which left Surveillance Station, USB Copy and the Resource
  Monitor out of reach from the keyboard.

### Fixes

- A package installed while the app was running is now noticed. Until now the
  app took stock of the installed packages once, when it connected, so a module
  stayed unavailable until the next sign-in. A screen for a module that is not
  available also offers to look again.

### Known limits

- Ejecting and formatting have been tested on USB. eSATA uses the same calls,
  but no eSATA drive was available to try them on.

## v1.1-beta.21 (build 22) — 2026-08-03

### Highlights

- Container Manager is now covered in full: you can create a container, not just
  watch the ones already there.

### New

- Containers: a New container button asks for an image, a name, the ports to
  publish, the folders to mount and the environment variables, then creates it.
  A port left at 0 is chosen for you when the container starts.
- Containers: Duplicate makes a second container with the same settings. The
  copy arrives stopped, and its ports are left free so it cannot clash with the
  original.
- Containers: a Settings screen renames a container, caps its memory and decides
  whether it restarts on its own.
- Containers: a Statistics tab shows the memory in use and the bytes received
  and sent. A container that has just started says its processor share is not
  measurable yet rather than showing zero.
- Containers: Force stop kills a container that will not stop, and Reset builds
  it again from its settings. Both say what is lost before doing it.
- Containers: a container's settings can be written to a folder of the NAS.

### Changes

- Nine more lists became sortable tables, with one column per value: File
  Station favourites, tasks, virtual folders and transfers, installed packages,
  the package catalogue, shared folders, the USB Copy log and the archive
  browser. Reading a row column by column no longer means hearing it as one
  block.
- Per-row buttons moved into each table's context menu, everywhere. The Actions
  column is gone: it widened every row and stood between you and the next line.
- Shared folders show whether the recycle bin is on, which the NAS reported all
  along without the app saying so.
- Transfers name the direction in words. Until now it was an icon, so it was
  said nowhere.
- The archive browser says whether an entry is a folder or a file.
- Packages say when an operation is running, and when uninstalling needs the DSM
  assistant. Both were only hinted at.

### Fixes

- VoiceOver: forms, lists and scroll views across the app now say what they
  hold. Most of them announced only "scroll area".
- Two labels showed their internal key instead of their text.

### Download

[dsmaccess-1.1-beta.21.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.21/dsmaccess-1.1-beta.21.zip)

## v1.1-beta.20 (build 21) — 2026-07-31

### New

- Updates: you now choose whether to receive beta versions, in Settings >
  Updates. Until now the channel followed the version installed, so trying a
  beta once meant staying on the betas. Turning it off does not undo the beta
  already installed: the app stays on it until a stable version goes past it.
- Files: sending or downloading now shows the same banner as a copy — what is
  running, how much is done, the speed, the time left, and a Cancel button that
  really stops it. Until now a large upload showed a spinner in a corner, and
  the details lived in a window you had to think of opening.
- Users and groups: creating a group offers "Create and set permissions…", as
  creating a user already did. A new group could reach nothing, and nothing on
  screen said where to grant it anything.

### Fixes

- Files: dragging a folder to the Finder produces a zip archive built by the
  NAS, and downloading one does the same. That is now said, with the name of
  the archive, instead of a .zip appearing unannounced.
- Files: while the NAS packs a folder into an archive, nothing is transferred
  yet. That wait is now named rather than left as a progress bar sitting at
  zero with no explanation.
- Users and groups: creating a group with a name already taken kept the sheet
  open and says so, instead of closing and discarding what was typed.

### Download

[dsmaccess-1.1-beta.20.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.20/dsmaccess-1.1-beta.20.zip)

## v1.1-beta.19 (build 20) — 2026-07-31

### Fixes

- Files: sending a file to the NAS, or bringing one back, now plays the sound at
  the end. It only ever played for operations that stay on the NAS — copying,
  moving, deleting — which left out the transfers long enough to walk away
  from. The notification was missing on those too.
- Files: pasting or sending no longer opens a form first. The app compares the
  names with the destination and only asks when something would be replaced,
  naming it: "budget.xlsx already exists in this folder". The upload form and
  its three date pickers are gone; DSM does not ask for those either.
- Five spoken announcements were in French for everyone — editing a share link,
  advanced search, package details, creating an archive, and one more. They had
  slipped past the translation work.

### Download

[dsmaccess-1.1-beta.19.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.19/dsmaccess-1.1-beta.19.zip)

## v1.1-beta.18 (build 19) — 2026-07-30

### Fixes

- Files: pasting into an empty folder works. The keyboard shortcut did nothing
  there — the one place where pasting is the only thing left to do. The folder
  is still announced as empty when you arrive in it.
- Users and groups: creating an account no longer announces that adding it to
  its groups failed when it did not. The NAS puts every account in the "users"
  group itself and refuses any change to it, so the app no longer offers it as
  a choice; the screen says instead that every account belongs to it.
- Users and groups: when the NAS does refuse a group, the app names it and
  keeps the ones the NAS accepted. Until now the first refusal silently
  dropped every group listed after it.

### Download

[dsmaccess-1.1-beta.18.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.18/dsmaccess-1.1-beta.18.zip)

## v1.1-beta.17 (build 18) — 2026-07-30

### Highlights

- Logs and Security was rebuilt. The app was reading one log out of four —
  seven thousand entries where the NAS holds more than a hundred thousand —
  and two of its columns had always been empty.
- The Resource Monitor is complete: open files, the alerts the NAS recorded,
  and the thresholds that produce them.

### Please tell me if the wording looks wrong

Every piece of text in the app moved to a new system this week, so that the
app can one day be translated into other languages. Nothing should look
different — but if you come across a label that reads like machine code, a
sentence in the wrong language, or a word that is simply missing, please say
so. Those are mistakes on my side, not on yours, and they are quick to fix.

### New

- Logs and Security: all four logs the NAS keeps are now available, not just
  the system one. File transfers are there, with the address, the operation
  and the size, and connections have their own log.
- Logs and Security: a log can be exported to a file, as a spreadsheet or as
  a web page. The NAS writes the file itself, so what you get is exactly what
  it holds.
- Logs and Security: Security Advisor's findings about sign-ins now have
  their own tab — failed attempts, unusual sources, accounts worth a look.
- Logs and Security: two settings panes. One decides which transfers the NAS
  records; the other, how many failed sign-ins it takes before an address is
  blocked, and for how long.
- Logs and Security: the search field is in the toolbar, where it is in every
  other module, and older entries load as you go rather than stopping at the
  first page.
- Resource Monitor: an Open files tab, listing what the NAS is currently
  holding open and for whom.
- Resource Monitor: a History tab, showing the alerts the NAS recorded against
  its own thresholds.
- Resource Monitor: a Performance alarm tab. You can add, change and remove
  the thresholds the NAS watches — on the system, on a service, or on a
  volume.
- Resource Monitor: a connected session can be closed from the Connections
  tab.
- Files: a copy or a move now plays a short sound when it ends, and a
  different one if it fails. It plays when the app is in front; when it is
  not, the notification carries the result as before, never both. Settings
  has a switch to turn the sound off.

### Fixes

- Logs and Security: the block list came back with an error 103 for everyone.
  The app was asking the NAS for that list the wrong way. It works now.
- Logs and Security: the Time and User columns were empty in every log. The
  app was reading fields the NAS does not send.
- Resource Monitor: a service's processor share was shown a hundred times too
  small.
- Resource Monitor: a process can legitimately exceed 100 % — it means it is
  using more than one core. The screen now says so instead of leaving you to
  guess.
- Five labels in the Resource Monitor were showing in English to French users.

### Download

[dsmaccess-1.1-beta.17.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.17/dsmaccess-1.1-beta.17.zip)

## v1.1-beta.16 (build 17) — 2026-07-29

### Highlights

- Sign-in: the app reopens on the session it already had. Tick "Stay signed
  in" once and the next launch goes straight in — with no password to
  replay, and no approval to grant on your phone.
- A Resource Monitor of its own, with the processor, memory, network, disks
  and volumes; the services and processes running; and who is connected to
  the NAS.

### New

- Sign-in: sessions are kept between launches. Only a refusal from the NAS
  sends you back to the sign-in screen, and it says why. The saved session
  lives in the Keychain beside your password and is erased when you sign
  out.
- Sign-in: the menu now names Secure SignIn rather than describing it as
  "no password", and remembers which method you chose.
- Resource Monitor: a new entry in the sidebar, on Command Shift 5, with
  three tabs. Performance adds each disk and volume, with its own activity,
  and the load averages. Tasks lists services and the busiest processes.
  Connections shows who is connected, from where and since when.
- Resource Monitor: tasks and connections are sortable tables — click a
  column header to order by it.
- Files: a running copy now shows its speed and how long is left, or "less
  than a minute" when the end is near. Neither is ever spoken aloud; they
  sit in the progress banner for you to read when you want them.
- Files: when a long operation finishes while the app is in the background,
  a notification carries the result. macOS asks for permission the first
  time, and a switch in Settings turns it off.

### Fixes

- Memory was reported twice over and disagreed with itself: 17% in use on
  one line, 3.54 GB of 3.68 GB on the next. DSM sets disk cache aside, and
  this NAS was holding 2.89 GB of it.
- The NAS menu in the toolbar announced the name of its icon —
  "externaldrive.connected.to.line.below" — instead of what it does.

### Download

[dsmaccess-1.1-beta.16.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.16/dsmaccess-1.1-beta.16.zip)

## v1.1-beta.15 (build 16) — 2026-07-29

### Highlights

- Files: creating a share link works again. Since beta.6 it failed every time
  with "the NAS response could not be read", even though the NAS had created
  the link. If you tried during that period, those links are sitting in your
  share link list, waiting to be used or deleted.

### Fixes

- Files: a share link is created and handed back as before. The app had been
  demanding a piece of information that DSM only sends when something goes
  wrong, and threw the whole answer away when it was, correctly, absent.
- Files: on some NAS models the Files screen itself could refuse to open, for
  the same reason. It no longer depends on details your NAS may not report.
- Files: the task window follows a running task again. It used to show the
  progress it had when you opened it and never move, which made a long
  compression look stuck at one percent.
- Files: a compression that finished is no longer reported as an interrupted
  operation. The NAS drops a finished task rather than announcing it, and that
  silence was being read as a failure.

### New

- Files: pasting or moving now names the folder the items are going into,
  before you confirm. Selecting a folder in the list does not make it the
  destination — it has to be open, as in the Finder.
- Files: when creating an archive you can choose the encoding used for the
  names inside it, for archives meant to be opened on another system.
- When the app cannot make sense of an answer from your NAS, it now says so and
  offers to report it. Reporting opens the contact form, already filled in, and
  attaches the call that failed and the names of the fields your NAS sent —
  never their contents, so no file name, path or account leaves your machine.

### Download

[dsmaccess-1.1-beta.15.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.15/dsmaccess-1.1-beta.15.zip)

## v1.1-beta.14 (build 15) — 2026-07-28

### Highlights

- Sign-in: you can now open a session without typing a password at all, by
  approving the request in the Synology Secure SignIn app on your phone.
- Files: a long copy is no longer abandoned after five minutes, and leaving the
  Files screen no longer stops it.

### New

- Sign-in: an Authentication menu on the connection screen chooses between your
  password and the approval sent to your phone. With the second, the password
  field steps aside and a waiting screen tells you what to do, reading out the
  number to confirm when your NAS asks for one. The session opened this way has
  to be approved again the next time you open the app, which the screen says.
- DSM update: a new screen shows the update your NAS offers and installs it,
  with the progress announced along the way.

### Fixes

- Files: copying, moving, deleting, compressing or extracting used to be given
  up after exactly five minutes, reported as a failure, while the NAS quietly
  carried on. A copy of several hours is now followed to its end.
- Files: switching to another screen while a copy was running silently stopped
  it on the NAS. It now keeps going, and coming back to Files picks the
  progress up again -- even after quitting and reopening the app. Only the
  Cancel button stops a task.
- Files: the result of a long operation stays on screen until you dismiss it. A
  spoken announcement made while the app sits in the background is never heard,
  which left no trace of what happened.
- Files: a folder holding a file whose name was not stored in Unicode could not
  be opened at all -- one such name among three thousand made the whole folder
  unreachable. It now opens, that one name showing a replacement character, as
  DSM itself does.

### Download

[dsmaccess-1.1-beta.14.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.14/dsmaccess-1.1-beta.14.zip)

## v1.1-beta.13 (build 14) — 2026-07-28

### Highlights

- Users and groups: the groups an account belongs to can now be changed after
  the account exists, not only while creating it.

### New

- Users and groups: the permissions panel gains a Groups tab, next to shared
  folders and applications, listing every group on the NAS with the ones the
  account belongs to ticked. Changes are saved along with the rest.

### Download

[dsmaccess-1.1-beta.13.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.13/dsmaccess-1.1-beta.13.zip)

## v1.1-beta.12 (build 13) — 2026-07-28

### Highlights

- Users and groups: you can now give an account access to your shared folders
  and to the applications on your NAS, without leaving DSM Access. Creating
  someone an account and letting them actually use it is one task again.

### New

- Users and groups: a Permissions panel lists every shared folder with the
  access granted to the account, the access it inherits from its groups, and
  the four choices DSM offers. It reads as a table, one row per folder, so you
  can go through it with the arrow keys.
- Users and groups: a second tab does the same for applications. Whether
  someone may open DSM, File Station, Synology Photos or connect over SMB is
  set here. Nothing is sent to the NAS until you save, and only what you
  changed is sent.
- Users and groups: the same panel works on a group. Give the rights once to a
  group, add people to it, and each of them inherits without you repeating
  anything. This is the practical way to set up a household.
- Users and groups: the creation panel offers to open the permissions of the
  account it just created, so you do not have to find it again in the list to
  give it any access at all.

### Fixes

- Users and groups: the groups you picked when creating an account were
  silently dropped. The account was created, but it belonged to none of them.
  It now lands in the groups you chose.

### Accessibility

- Users and groups: an application already restricted to specific addresses is
  left read-only, with an explanation, rather than being quietly rewritten as
  "from anywhere".
- Users and groups: when a group is denied access to a folder, the panel says
  so on the row concerned, because that denial overrides whatever the account
  itself was given.
- Users and groups: the panel shows a single Close button until something is
  actually modified, instead of a Cancel that suggests undoing work and a
  dimmed Save that does not say why.

### Download

[dsmaccess-1.1-beta.12.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.12/dsmaccess-1.1-beta.12.zip)

## v1.1-beta.11 (build 12) — 2026-07-27

### Highlights

- Sign-in: accounts without administrator rights can sign in again. Anyone you
  created an account for on your NAS can use DSM Access, not just you.

### Fixes

- Sign-in: an account that is not an administrator was turned away with
  "Permission denied for this account", even though that same account signed
  in to DSM in a browser without any trouble.
- Users and groups: creating a user failed with nothing but an error code when
  the password did not satisfy the rules your NAS enforces. The message now
  says what happened, and the form lists those rules before you type anything.
- Users and groups: a failed creation no longer closes the panel and discards
  everything you filled in. The message appears in place, and you can correct
  the password without starting over.

### New

- Sign-in: when your NAS requires a new password before letting an account in,
  DSM Access asks for it and signs you in, instead of stopping on an error you
  could do nothing about.
- Users and groups: a button generates a password that satisfies your NAS
  rules. It is shown in plain text so you can read it back, and a second
  button copies it, so you can pass it on to the person it is meant for. The
  characters that sound and look alike are left out, so it survives being read
  aloud or written down.

### Download

[dsmaccess-1.1-beta.11.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.11/dsmaccess-1.1-beta.11.zip)

## v1.1-beta.10 (build 11) — 2026-07-25

### Highlights

- Files: copy files in the Finder, then paste them into a folder on the NAS
  with Command-V. Whole folders come along, with everything inside them.
- Files: drag an item out of the file list and drop it in the Finder to
  download it there.
- Copy and paste now behave the way they do in the Finder: Command-C copies,
  Command-V pastes a copy, and Command-Option-V moves. There is no longer a
  Cut command.

### New

- Files: Command-V sends what you copied in the Finder to the folder you are
  in. Files land in that folder; a folder is recreated on the NAS with its
  entire tree, empty subfolders included. Finder's hidden .DS_Store files are
  left out, and if an item on your Mac cannot be read, the transfer reports
  itself as incomplete rather than pretending everything went through.
- Files: an item can be dragged out of the list and dropped in the Finder.
  Nothing is downloaded until you actually drop it, and a folder arrives as a
  ZIP archive, exactly as it does with Download. Download remains the
  keyboard route and has not changed.
- Files: sending items to the NAS now accepts folders as well as files, and
  the options that appear before a transfer say how many files and how many
  folders are on their way.

### Changes

- Files: Cut is gone. Command-C copies, Command-V pastes a copy, and
  Command-Option-V moves what you copied — the choice happens when you paste,
  as in the Finder. The Files menu now offers Move Here next to Paste, and the
  confirmation states what a move will do. Moving files that come from your
  Mac is refused, with an explanation: it would mean deleting your originals.
- Updates: the app now looks for a new version at every launch. Sparkle's own
  schedule checks once a day at most, which left a tester a version behind
  whenever two builds went out on the same day. Nothing appears on screen
  unless an update is waiting, and the setting in the updates panel still
  decides whether the check happens at all.
- Updates: checking automatically is now the app's declared default instead of
  a preference written on your behalf at first launch — a preference you never
  chose, which also silenced Sparkle's own question about it. The updates panel
  remains the one place to change this.

### Requirements

- macOS 14 (Sonoma) or later.
- A Synology NAS running DSM 7 on your local network.

### Download

[dsmaccess-1.1-beta.10.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.10/dsmaccess-1.1-beta.10.zip)

## v1.1-beta.9 (build 10) — 2026-07-23

### Highlights

- New USB Copy module: set up and run your USB copy tasks entirely from the
  app — the selectors in DSM's web interface are unusable with a screen
  reader, so this was until now a job for sighted help. Contributed by
  Ashley Cox.
- Files: sending files to the NAS works again. A DSM update had quietly
  broken every upload.
- DSM Access now has its own app icon, also designed by Ashley Cox.

### New

- USB Copy: see every task with its direction, folders, and current state;
  create import and export tasks with accessible folder choosers for the
  source and destination; choose the copy mode, version rotation, file
  filters, and schedule; run, cancel, enable, disable, or delete a task; read
  the package's log; adjust its general settings. Risky operations explain
  their consequence and ask first — a mirror task warns that it deletes from
  the destination, and deleting a task names it. The module appears only when
  the USB Copy package is installed on the NAS.

### Fixes

- Files: uploading a file ended in an error ever since the NAS moved to the
  latest DSM 7.4 update, which changed how DSM expects uploads to be sent.
  Uploads now follow the same convention as DSM's own File Station and work
  again — including the choice between replacing or skipping an existing
  file.

### Requirements

- macOS 14 (Sonoma) or later.
- A Synology NAS running DSM 7 on your local network.

### Download

[dsmaccess-1.1-beta.9.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.9/dsmaccess-1.1-beta.9.zip)

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
