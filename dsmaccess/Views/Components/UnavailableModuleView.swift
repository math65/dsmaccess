//
//  UnavailableModuleView.swift
//  dsmaccess
//

import SwiftUI

struct UnavailableModuleView: View {
    let module: AppModule
    let session: SessionStore

    @State private var isChecking = false
    @State private var checkOutcome: String?
    @AccessibilityFocusState private var focusesOutcome: Bool

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: "module.unavailable.title", defaultValue: "\(module.localizedTitle) unavailable"),
                systemImage: module.systemImage
            )
        } description: {
            VStack(spacing: 12) {
                Text(module.unavailableHelp)
                if isChecking {
                    ProgressView("module.unavailable.checking.progress")
                        .controlSize(.small)
                } else if let checkOutcome {
                    Text(checkOutcome)
                        .accessibilityFocused($focusesOutcome)
                }
            }
        } actions: {
            Button("module.unavailable.check_again.button") {
                Task { await checkAgain() }
            }
            .disabled(isChecking)
            .help("module.unavailable.check_again.hint")
            SettingsLink {
                Text("module.unavailable.edit_sidebar.button")
            }
            .help("module.unavailable.edit_sidebar.hint")
        }
        .task {
            VoiceOver.announce(
                String(localized: "module.unavailable.description", defaultValue: "\(module.localizedTitle) is not available on this NAS"),
                category: .navigation
            )
        }
    }

    /// Reads the published APIs again, for the case where the package was installed or started
    /// after the session opened. On success this view is replaced by the module itself, so the
    /// announcement is posted here, while the screen is still the one the user is standing on.
    private func checkAgain() async {
        guard !isChecking else { return }
        isChecking = true
        checkOutcome = nil
        VoiceOver.announce(
            String(localized: "module.unavailable.checking.progress"),
            category: .progress
        )
        defer { isChecking = false }
        do {
            try await session.refreshCapabilities()
            guard !module.isAvailable(in: session.capabilities) else {
                VoiceOver.announce(
                    String(localized: "module.unavailable.now_available.status", defaultValue: "\(module.localizedTitle) is now available"),
                    category: .result
                )
                return
            }
            report(
                String(localized: "module.unavailable.unchanged.status", defaultValue: "No change: \(module.localizedTitle) is still unavailable."),
                category: .result
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            report(
                String(localized: "module.unavailable.check_failed.error", defaultValue: "Could not check the installed packages: \(reason)"),
                category: .error
            )
        }
    }

    private func report(_ message: String, category: AnnouncementCategory) {
        checkOutcome = message
        VoiceOver.announce(message, category: category)
        focusesOutcome = true
    }
}
