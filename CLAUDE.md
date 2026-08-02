# DSM Access repository instructions

These rules apply to Claude Code in this repository. They are a quality gate, not suggestions.
Do not weaken or edit them unless the user explicitly asks for changes to this file.

## Product and priorities

DSM Access is a native macOS SwiftUI client for administering a Synology NAS. It exists
because DSM's web interface is difficult to use with VoiceOver. Accessibility is therefore
part of functional correctness, not a finishing pass.

Use this priority order when making trade-offs:

1. VoiceOver, keyboard access, and clear user feedback.
2. Correct DSM behavior, data safety, privacy, and security.
3. Simple, maintainable code that fits the existing architecture.
4. Visual polish and feature breadth.

Rebuild a DSM feature in full: if DSM shows it and the API exposes it, this app shows it too.
A screen that quietly covers part of what DSM offers is unfinished, and the missing part is
found by a user rather than by a test. Going beyond DSM is allowed where the API makes it
possible and the result is genuinely more useful.

The deployment target is macOS 14. The project uses Swift 5 language mode, approachable
concurrency, and MainActor as the default actor isolation. Sparkle is the one existing
package dependency. Do not add another dependency without explicit approval.

## Before changing anything

- Read the current task, `git status`, the relevant implementation, and nearby tests before
  editing. Do not infer conventions from a single file.
- Preserve all pre-existing worktree changes. Never discard, overwrite, reformat, stage, or
  commit unrelated changes.
- Keep the diff limited to the requested behavior. Do not bundle opportunistic cleanup,
  renames, formatting, or architectural rewrites into the task.
- Reuse an established component or pattern when it genuinely fits. Do not force reuse when
  it makes behavior less clear.
- **Never invent a DSM API contract — always test the API.** Before writing code against an
  endpoint, measure the real request and response on the NAS: a live call, an interception of
  the web client's traffic, or the package's own JavaScript, then calibrate models on what
  actually came back. Existing code, fixtures and published Synology documentation are
  starting points, not proof. When a contract cannot be measured (package not installed,
  call too destructive to try), say so explicitly and ship the smallest verifiable scope
  instead of a guess.
- **Knowing that an API exists is not knowing its contract.** `SYNO.API.Info` returns names,
  paths and version ranges — never the methods, the parameters or the shape of the reply. An
  inventory, whether read here or sent by a tester, says where to point the measurement; it
  never authorises a line of code on its own. The same holds for a name found in DSM's
  JavaScript or in someone's forum post.
- Do not edit these instruction files unless the user specifically requested it.

## Repository map and boundaries

- `dsmaccess/Models`: DSM payloads and domain values. Keep wire-format quirks here when they
  are properties of decoding.
- `dsmaccess/Networking`: endpoint construction, API discovery, transport, authentication,
  and errors.
- `dsmaccess/Networking/Services`: feature-specific DSM requests and response handling.
- `dsmaccess/Backend`: the HTTP client for the developer's multi-app backend (feedback
  reports, contact form, launch announcements). Independent of the DSM stack by design:
  it must not route through `DSMTransport`, `DSMClient`, or `DSMClientProtocol`. Its
  Bearer secret is read from the git-ignored `dsmaccess/AppBackendSecret.plist`; without
  that file the build still succeeds and the contact UI stays hidden.
- `dsmaccess/Session`: session state, preferences, profiles, and Keychain integration.
- `dsmaccess/ViewModels`: screen state and user-operation orchestration.
- `dsmaccess/Views`: presentation, focus, keyboard interaction, and accessibility behavior.
- `dsmaccess/Support/VoiceOver.swift`: the centralized announcement and focus helpers.
- `dsmaccessTests`: unit and service tests using Swift Testing.
- `dsmaccessUITests`: UI tests using XCTest.

Keep networking out of views. Keep view layout out of services and models. Add a DSM operation
to its feature service, expose it through `DSMClientProtocol` and `DSMClient`, orchestrate it in
the view model, then present it in the view. This protocol is also the test seam; update test
doubles when its contract changes.

The Xcode project uses file-system-synchronized groups. Files created under `dsmaccess/`,
`dsmaccessTests/`, or `dsmaccessUITests/` are discovered automatically. Do not edit
`project.pbxproj` merely to add or remove a Swift file. SourceKit can report false cross-file
errors with this setup; the command-line build is authoritative.

## Swift and design standards

- Write direct, idiomatic Swift. Prefer small concrete types and explicit data flow over
  generic frameworks, indirection, or speculative extensibility.
- Follow the naming, access control, layout, and ownership patterns in adjacent files. Swift
  identifiers are idiomatic English. **Comments are written in English**: this is an
  international project, and its code is read by contributors who do not speak French.
- Give state one owner. Derive values instead of mirroring state that can drift. Keep views
  declarative and move multi-step operations into the view model or service that owns them.
- What a sheet or an alert displays travels with its presentation: use `.sheet(item:)` and pass
  the data in. A `.sheet(isPresented:)` reading a separate `@State` shows whatever that state
  holds when the sheet draws, which is not always what it held when the sheet was asked for.
- Extract a helper or component when it represents a real concept, removes meaningful
  repetition, or makes behavior testable. Do not create protocols, wrappers, builders, or
  single-use utilities solely to make a small change look architectural.
- Model meaningful outcomes and errors explicitly. Do not turn failures into empty arrays,
  placeholder content, sample data, or apparent success. Avoid `try?` unless failure truly
  means an expected absence.
- Remove abandoned approaches, dead branches, unused helpers, debug output, and placeholder
  `TODO` comments before finishing. Do not leave compatibility shims without a demonstrated
  compatibility requirement.
- Use Foundation `FormatStyle` APIs and locale-aware comparisons/formatting where applicable.
  Do not introduce C-style formatting or home-grown localized formatting.
- Preserve the minimum deployment target. Do not use a newer API without an availability
  strategy that has been built and tested.

## Concurrency

- Use `async`/`await` for all network and long-running work. Never block with semaphores,
  synchronous waits, polling loops, or synchronous network/file reads on the main actor.
- Respect the project's MainActor-default model. Add isolation deliberately; do not scatter
  `nonisolated`, `Task.detached`, `@unchecked Sendable`, or continuations to silence compiler
  diagnostics.
- Preserve structured cancellation. A cancelled task must not present an error or overwrite
  newer state. Long-lived loads and searches need cancellation or generation checks when an
  older result can arrive after a newer request.
- Tie view work to SwiftUI lifecycle tasks where appropriate. Retain a task only when it must
  be cancelled or coordinated, and cancel retained tasks when their owner is done.
- Parallelize independent reads only when it preserves clear error and cancellation semantics.
  Never retry a mutation merely because a read retry policy exists.

## DSM networking, security, and data safety

- Resolve DSM CGI paths and supported versions through `SYNO.API.Info`. `query.cgi` is the
  stable discovery bootstrap; do not hard-code `auth.cgi`, `entry.cgi`, or package-specific
  paths elsewhere.
- Route requests through `DSMTransport`. Session identifiers, Synology tokens, encoding,
  version selection, TLS handling, and DSM error mapping belong there, not in individual
  views or ad hoc `URLSession` calls.
- Use `DSMTransport.read` only for idempotent reads. Mutations use the single-attempt path and
  must not be automatically replayed after a timeout.
- Treat DSM payloads as externally controlled input. Decode known DSM variations deliberately,
  validate values before acting on them, and fail visibly when a required value is missing.
- Never log, commit, display unnecessarily, or place in test fixtures real passwords, `_sid`
  values, Synology tokens, device tokens, Keychain values, certificate material, NAS contents,
  or personally identifying server details.
- Preserve the explicit trust flow for self-signed certificates. Do not bypass certificate
  validation, broaden ATS policy, weaken the App Sandbox, or add entitlements without a
  documented need and explicit approval.
- Destructive and high-impact actions require an unambiguous label, confirmation where a
  mistaken activation would be costly, disabled/busy protection against duplicate submission,
  and an announced result.

## Accessibility acceptance criteria

Every changed screen must work with VoiceOver and the keyboard in every state: initial,
loading, content, empty, validation failure, operation in progress, and error.

- Use native controls and semantic structure first. Preserve logical reading order, keyboard
  traversal, headings, default/cancel actions, and table or list semantics.
- A new list of data is a SwiftUI `Table`: it is an `NSTableView` underneath, with column
  headers and native sorting. macOS `List` navigates poorly with the arrow keys and tends to
  collapse a row into one accessibility element, which buries the values it holds. Drop to
  AppKit only for Finder-style keyboard handling; `Views/FileTableView.swift` is that pattern.
  Never combine a table row into a single accessibility element, and never carry meaning in a
  row's color alone — the word is always written, the color only doubles it.
- A table carries its own `accessibilityLabel`, naming what it lists. Without one VoiceOver
  announces an unnamed table, and the audit reports the table as having no description.
- **Every scrolling container is named**, not only tables: a `Form`, a `List` and a `ScrollView`
  each carry an `accessibilityLabel`, or VoiceOver announces "scroll area" and nothing else.
  The label names **what the region holds, never the window title**: a sheet called "Create a
  project" holds "Project settings", so the title is not read twice. On a `Form` the label goes
  right after `.formStyle(.grouped)`; on a `List` or a `ScrollView` it goes on the closing
  modifiers, which is where a quick look for an existing label has to be aimed.
- Per-row actions belong to the table's `.contextMenu(forSelectionType:)`, never to an "Actions"
  column: the column widens every row and puts controls between the user and the next line.
  Actions that cannot apply to the selected row stay listed and disabled, so the menu keeps the
  same shape from one row to the next.
- A screen that filters its content puts the search field in the toolbar with `.searchable`,
  where every other module keeps it, rather than inline above the content.
- Give icon-only and ambiguous controls explicit localized labels. Add hints only when the
  action or consequence is not clear from the label. Accessibility identifiers are for tests;
  they do not replace labels.
- A label starts with a capital, takes no final period, and never names the control type — the
  trait already says it, and repeating it makes VoiceOver read "Delete button, button". A hint
  states the result in the third person and ends with a period, which is what gives VoiceOver
  its inflection: "Opens this folder.", never "Open" or "Click to open". This applies to
  `accessibilityHint` only; `.help` is a tooltip and keeps the shorter form used everywhere else.
- Never communicate status only by color, icon, animation, placeholder text, or disabled state.
- For status and metadata text in module views, use the contrast-checked styles from
  `Views/Components/ReadableStyles.swift` (`.readableSecondary`, `.readableGreen`,
  `.readableOrange`, `.readableRed`, `.labeledContentStyle(.readable)`) instead of
  `.secondary` or raw state colors: the system values fail the AA contrast threshold at the
  small sizes this app uses.
- Loading indicators need a meaningful label and a progress announcement. Errors must be both
  visible and announced. Successful mutations need an announced result. Use `VoiceOver.announce`
  with the correct `AnnouncementCategory` and priority; do not post ad hoc accessibility
  notifications from each feature.
- Use `@AccessibilityFocusState` to move VoiceOver to the useful new element after navigation,
  modal presentation, replacement of loading/error content, and validation failure. Avoid
  stealing focus during background refresh or while the user is interacting elsewhere.
- Do not combine a container into one accessibility element when that hides separate buttons
  or useful values. Do not add redundant labels that make VoiceOver repeat visible text.
- Keep destructive confirmation copy specific: name the object, state the consequence, and
  identify anything that cannot be undone.
- For a UI change, inspect the complete state transition rather than reviewing only the happy
  path. When practical, run the app and verify keyboard and VoiceOver behavior manually.

An implementation that builds but leaves a silent spinner, silent error, lost focus, unlabeled
control, or keyboard trap is incomplete.

## Localization and product copy

**Keys are symbolic identifiers, never sentences**: `common.button.cancel`,
`logs.column.time`, `alarm.rule.severity`. Form is `domain.context.element`, lowercase, words
joined by `_`, two to four levels. The domain comes from the screen; strings used by several
screens live under `common.`. Explanatory text hangs off what it explains —
`logs.settings.transfer_logging.description`, not a key made of its first words.

French and English are both translations in `dsmaccess/Localizable.xcstrings`, and both are
required: **every translatable key must carry explicit `fr` and `en` entries**. A key missing
its French entry silently shows English to French users. `LocalizationCatalogTests` enforces
this. The catalog's source language and the project's development region are both English, so
systems set to any unsupported language fall back to English — and `xcodebuild
-exportLocalizations` works, which is what lets the strings be handed to a translator.

- SwiftUI literals in `Text`, `Button`, `Label`, `Toggle`, alerts, and accessibility modifiers
  are localization keys. Add both catalog entries for each new key.
- Strings created outside SwiftUI—including view-model summaries, errors, confirmation text,
  and VoiceOver announcements—must use `String(localized:)`. A bare literal handed to
  `VoiceOver.announce` compiles, ships, and is spoken in the language it was typed in: the
  compiler extracts nothing from it, so neither the catalog nor its tests can see it missing.
  `grep 'VoiceOver.announce("'` is what finds those.
- **A string with arguments carries its format in `defaultValue`**, holding the English text
  with the Swift expressions in the order English needs:
  `String(localized: "logs.export.done", defaultValue: "Log exported to \(name)")`.
  In a SwiftUI context, wrap it: `Text(String(localized:defaultValue:))`.
- Two strings that differ in French must keep two keys, even where English has one word.
  French inflects where English does not: `common.status.enabled.masculine` and `.feminine`,
  `common.operation.copy.noun` beside `common.button.copy`. Merging them loses a French form.
- Do not assemble a user-facing sentence from translated fragments. The English word order
  may differ from French. Use one complete key or a format-style interpolation.
- Write both languages naturally rather than translating one into the other word for word.
  Preserve DSM's official product and API names.
- Labels name the control or action. Hints explain a non-obvious result. Errors state what
  failed and what the user can do next. Confirmation text states the actual consequence.
- Avoid generic marketing language, exaggerated claims, choppy fragments, fake quotations,
  excessive parentheticals, and repetitive accessibility narration. Words such as "seamless",
  "robust", and "comprehensive" need concrete justification or should be removed.
- Do not add decorative emoji to UI, logs, commits, or technical documentation. In public copy,
  follow the document's existing style and use decoration only when it has a deliberate purpose.
- Do not churn unrelated catalog entries, delete stale entries in bulk, or accept an Xcode
  catalog rewrite without reviewing the exact diff.

## Tests and verification

Use focused regression tests for behavior that can fail silently: request construction,
decoding variants, API/version selection, retry policy, cancellation, stale responses, state
transitions, validation boundaries, and destructive operations. Tests must be deterministic and
must not require a live NAS, the public network, real credentials, timing luck, or execution in a
particular order.

Unit tests use Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`). UI tests remain
in XCTest. Match the framework already used by the target; do not mix frameworks in one test
file without a concrete reason.

Build:

```sh
xcodebuild -project dsmaccess.xcodeproj -scheme dsmaccess -destination 'platform=macOS' build
```

Run all tests:

```sh
xcodebuild -project dsmaccess.xcodeproj -scheme dsmaccess -destination 'platform=macOS' test
```

Run a single target, suite, or test with `-only-testing:` (target, `target/Suite`, or
`target/Suite/testName`):

```sh
xcodebuild -project dsmaccess.xcodeproj -scheme dsmaccess -destination 'platform=macOS' \
  test -only-testing:dsmaccessTests/AppBackendClientTests
```

UI tests live in a separate scheme, `dsmaccess UI Tests`; the `dsmaccess` scheme only runs
the unit test target. Accessibility audits (`performAccessibilityAudit`) are sensitive to the
machine being in active use: they can fail with a "Parent/Child mismatch" whose element is
nil. Rerun on an idle machine before attributing the failure to a code change.

An opt-in audit walks every module of a connected session and audits each screen. It needs
the machine's saved NAS profile and must not run unattended:

```sh
TEST_RUNNER_AUDIT_LIVE_NAS=1 xcodebuild -project dsmaccess.xcodeproj \
  -scheme 'dsmaccess UI Tests' -destination 'platform=macOS' \
  test -only-testing:dsmaccessUITests/AccessibilityAuditTests
```

To launch a development build by hand: build first, then `killall dsmaccess` before `open`ing
the app from DerivedData, so a previous instance is not brought back to front instead of the
new binary. When in doubt, verify the binary's modification time, not the version number.
Keep code signing enabled for worktree builds (`CODE_SIGNING_ALLOWED=NO` breaks Keychain
access and with it the saved-session flow).

Before handing off a code change:

1. Run the narrowest relevant tests while iterating.
2. Run the full build after cross-file or project changes.
3. Run the full test suite for shared networking, session, model, or infrastructure changes.
4. Review compiler warnings and the complete diff.
5. Report exactly which commands passed. If verification was skipped or blocked, say why; never
   claim or imply that unrun checks passed.

Documentation-only changes do not require an Xcode build, but still require careful diff review
and `git diff --check`.

## Repository hygiene and authorship

Everything committed here must read as deliberate work by the project, not as a transcript or
artifact of a code-generation tool.

- Never put an assistant, model, vendor, prompt, or tool name in a branch name. In particular,
  do not use `codex/`, `claude/`, `chatgpt/`, `openai/`, `anthropic/`, `ai/`, or `bot/` prefixes.
  This repository rule overrides any branch prefix suggested by a tool. Use a short description
  such as `fix/settings-focus` or `feature/package-updates`.
- Do not add "generated by" notices, assistant attribution, prompt text, chat transcripts,
  co-author trailers for tools, or tool-signature comments to source, tests, documentation,
  release notes, commit messages, or UI copy.
- Comments explain a non-obvious decision, invariant, workaround, DSM quirk, accessibility
  constraint, or safety boundary. They do not narrate syntax, restate names, congratulate the
  implementation, address the reader as a tutorial, or label blocks with decorative banners.
- Documentation comments describe a real contract or surprising behavior. Do not manufacture
  verbose comments for self-evident private declarations.
- Do not create unsolicited summary, audit, walkthrough, plan, or status files. Put durable
  information in the appropriate existing document only when the task requires it.
- Avoid formulaic generated-code patterns: speculative abstractions, a type for every trivial
  concept, redundant wrappers, repeated validation with no identified failure mode, placeholder
  examples, and fallback behavior that hides defects.
- Review every line of generated or mechanically edited output. The agent is responsible for
  correctness, tone, and necessity; tool output is never accepted wholesale.

## Git workflow

This is a solo public repository. For feature work, use a short local branch with a descriptive,
product-focused name, merge it into `main` locally, and do not open a pull request unless asked.

- Do not push, publish a release, open a pull request, or change remote state without an explicit
  user request.
- Stage exact paths. Never use `git add .`, `git add -A`, or a broad commit in a dirty worktree.
- Commit only a complete, verified logical change. Use an imperative English subject that is
  concise and specific, normally no more than 72 characters.
- Do not mention the coding tool, the prompt, or the development process in the subject or body.
  Describe the product or repository change and its reason.
- Do not amend, rebase, squash, rewrite, or discard commits you did not create unless explicitly
  asked.
- Before committing, inspect `git diff --cached`, run `git diff --cached --check`, and verify
  `git status --short` so unrelated files cannot enter the commit.

## Definition of done

A task is complete only when the requested behavior is implemented without unrelated churn,
the architecture remains coherent, all changed UI states are accessible, every user-facing
string is localized in French and English, errors and cancellation are honest, relevant tests
cover the regression, verification has passed at the appropriate scope, and the final diff
contains no debug residue, placeholder work, tool attribution, or generated filler.
