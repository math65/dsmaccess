//
//  ContainerTerminalSheet.swift
//  dsmaccess
//
//  A shell inside a container, as two fields: the output above, read-only, and the command
//  line below. DSM shows a terminal emulator here, which a screen reader cannot follow.
//

import SwiftUI

struct ContainerTerminalSheet: View {
    @State private var vm: ContainerTerminalViewModel
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var inputFocused: Bool
    @AccessibilityFocusState private var commandFocused: Bool
    @FocusState private var keyboardFocus: Field?

    private enum Field: Hashable {
        case command
        case input
    }

    init(session: SessionStore, containerName: String) {
        _vm = State(initialValue: ContainerTerminalViewModel(
            session: session,
            containerName: containerName
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                sessionBar
                Divider()
                ReadOnlyTextView(
                    text: outputText,
                    label: String(
                        localized: "containers.terminal.output.label",
                        defaultValue: "Output of the session in \(vm.containerName)"
                    )
                )
                .frame(minHeight: 240)
                Divider()
                inputBar
            }
            .navigationTitle(String(
                localized: "containers.terminal.title_named",
                defaultValue: "Terminal: \(vm.containerName)"
            ))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.status.done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .help("containers.terminal.close.hint")
                }
            }
        }
        .frame(minWidth: 640, minHeight: 460)
        .task { await vm.open() }
        .onChange(of: vm.phase) { _, phase in
            // Opening a session takes several exchanges with the NAS, so the move has to follow
            // the phase rather than the call that starts it. And once the session is over the
            // input field is disabled, which takes it out of the keyboard order: leaving
            // VoiceOver on it would leave it on nothing.
            switch phase {
            case .running:
                keyboardFocus = .input
                inputFocused = true
            case .ended:
                keyboardFocus = .command
                commandFocused = true
            case .idle, .opening:
                break
            }
        }
        .onDisappear {
            Task { await vm.close() }
        }
    }

    /// The output area never stays blank: an empty one would read as “no output” when the
    /// session is only being opened, or already over. A failure is not repeated here — it is
    /// written under the input field, and hearing it three times helps nobody.
    private var outputText: String {
        if !vm.output.isEmpty { return vm.output }
        switch vm.phase {
        case .opening:
            return String(localized: "containers.terminal.opening_placeholder")
        case .idle:
            return String(localized: "containers.terminal.idle_placeholder")
        case .ended(let reason):
            return vm.errorMessage == nil
                ? reason
                : String(localized: "containers.terminal.idle_placeholder")
        case .running:
            return String(localized: "containers.terminal.no_output_yet")
        }
    }

    private var sessionBar: some View {
        HStack(spacing: 8) {
            // The shell can only be chosen before the session runs. Showing the field greyed
            // out for the rest of the time leaves a control that answers nothing in the
            // keyboard order; the shell in use is worth stating, not editing.
            if isChoosingShell {
                TextField("containers.terminal.command", text: $vm.command)
                    .frame(maxWidth: 220)
                    .focused($keyboardFocus, equals: .command)
                    .accessibilityFocused($commandFocused)
                    .help("containers.terminal.command.hint")
            } else {
                Text(String(
                    localized: "containers.terminal.shell_in_use",
                    defaultValue: "Shell: \(vm.command)"
                ))
                .font(.callout)
                .foregroundStyle(.readableSecondary)
            }

            if vm.isRunning {
                Button("containers.terminal.end_session", role: .destructive) {
                    Task { await vm.close() }
                }
                .help("containers.terminal.end_session.hint")
            } else {
                Button("containers.terminal.open_session") {
                    Task { await vm.open() }
                }
                .disabled(vm.phase == .opening || vm.command.isEmpty)
                .help("containers.terminal.open_session.hint")
            }

            if vm.phase == .opening {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("containers.terminal.opening_progress")
            }

            Spacer()

            Text(statusText)
                .font(.callout)
                .foregroundStyle(vm.isRunning ? Color.readableGreen : Color.readableSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("containers.terminal.input", text: $vm.input)
                    .font(.system(.body, design: .monospaced))
                    .focused($keyboardFocus, equals: .input)
                    .accessibilityFocused($inputFocused)
                    .disabled(!vm.canSend)
                    .onSubmit { Task { await vm.send() } }
                    .help("containers.terminal.input.hint")

                // No default-action shortcut: Return already reaches the field's own submit,
                // and having both would send the line twice.
                Button("containers.terminal.send") {
                    Task { await vm.send() }
                }
                .disabled(!vm.canSend)
                .help("containers.terminal.send.hint")

                Button("containers.terminal.interrupt") {
                    Task { await vm.interrupt() }
                }
                .disabled(!vm.canSend)
                .help("containers.terminal.interrupt.hint")
            }

            if let errorMessage = vm.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.readableRed)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// The shell is only up for choice while no session holds it.
    private var isChoosingShell: Bool {
        switch vm.phase {
        case .idle, .ended: true
        case .opening, .running: false
        }
    }

    /// A status is a couple of words, so a failure shows as one here and is spelled out under
    /// the input field.
    private var statusText: String {
        switch vm.phase {
        case .idle: String(localized: "containers.terminal.status.idle")
        case .opening: String(localized: "containers.terminal.status.opening")
        case .running: String(localized: "containers.terminal.status.running")
        case .ended(let reason):
            vm.errorMessage == nil ? reason : String(localized: "containers.terminal.status.failed")
        }
    }
}
