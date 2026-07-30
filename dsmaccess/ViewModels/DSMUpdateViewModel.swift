//
//  DSMUpdateViewModel.swift
//  dsmaccess
//
//  Driving a manual DSM update, from picking the file to the NAS coming back.
//

import Foundation
import Observation

@MainActor
@Observable
final class DSMUpdateViewModel {
    /// Stages of the operation. They also decide what gets announced: an installation takes
    /// about twenty minutes and the screen changes state on its own.
    enum Stage: Equatable {
        case idle
        case uploading
        case checking
        case awaitingConfirmation
        case starting
        case installing
        case rebooting
        case backOnline
        case finished
    }

    private(set) var stage: Stage = .idle
    private(set) var selectedFile: URL?
    private(set) var preCheck: DSMUpgradePreCheck?
    private(set) var transferProgress: DSMTransferProgress?
    private(set) var installProgress: DSMUpgradeProgress?
    private(set) var currentVersion: String?
    private(set) var modelName: String?
    private(set) var isLoading = false
    var errorMessage: String?

    private let session: SessionStore
    /// Polling for the NAS's return: 15 s between attempts, capped at 40 minutes. DSM
    /// announces 10 to 20 minutes; past the cap, the app says so instead of waiting forever.
    private let onlinePollInterval: Duration = .seconds(15)
    private let onlinePollLimit = 160

    init(session: SessionStore) {
        self.session = session
    }

    var isBusy: Bool {
        switch stage {
        case .idle, .awaitingConfirmation, .finished, .backOnline: return false
        case .uploading, .checking, .starting, .installing, .rebooting: return true
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        guard let currentVersion else {
            return String(localized: "dsm_update.status.version_unknown")
        }
        return String(localized: "common.status.installed_version", defaultValue: "Installed version: \(currentVersion)")
    }

    /// Status text, the single source of truth for both display and announcements.
    var statusText: String {
        switch stage {
        case .idle:
            return selectedFile.map { String(localized: "dsm_update.status.file_ready", defaultValue: "File ready: \($0.lastPathComponent)") }
                ?? String(localized: "dsm_update.status.no_file")
        case .uploading:
            guard let fraction = transferProgress?.fractionCompleted else {
                return String(localized: "common.status.sending.description")
            }
            let pourcentage = fraction.formatted(.percent.precision(.fractionLength(0)))
            return String(localized: "dsm_update.status.uploading", defaultValue: "Sending the file to the NAS, \(pourcentage).")
        case .checking:
            return String(localized: "dsm_update.status.checking_file")
        case .awaitingConfirmation:
            return String(localized: "dsm_update.status.file_accepted")
        case .starting:
            return String(localized: "dsm_update.status.starting")
        case .installing:
            guard let pourcentage = installProgress?.percentage else {
                return String(localized: "dsm_update.status.installing")
            }
            return String(localized: "dsm_update.status.installing_progress", defaultValue: "Installation under way on the NAS, \(pourcentage) %.")
        case .rebooting:
            return String(localized: "dsm_update.status.restarting")
        case .backOnline:
            return String(localized: "dsm_update.status.nas_back")
        case .finished:
            return String(localized: "dsm_update.status.finished")
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let info = try await session.withClient { try await $0.systemInfo() }
            currentVersion = info.versionString
            modelName = info.model
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    func selectFile(_ url: URL) {
        selectedFile = url
        preCheck = nil
        errorMessage = nil
        stage = .idle
    }

    /// Sends the file then asks the NAS what it thinks of it. Stops before installing: the
    /// decision belongs to the user, once the consequences are known.
    func uploadAndCheck() async -> DSMOperationOutcome {
        guard let fileURL = selectedFile, !isBusy else { return .cancelled }
        stage = .uploading
        transferProgress = nil
        errorMessage = nil

        let accede = fileURL.startAccessingSecurityScopedResource()
        defer { if accede { fileURL.stopAccessingSecurityScopedResource() } }

        do {
            try await session.withClient { client in
                try await client.uploadDSMPatch(at: fileURL) { [weak self] progress in
                    self?.transferProgress = progress
                }
            }
            stage = .checking
            let resultat = try await session.withClient { try await $0.dsmUpgradePreCheck() }
            preCheck = resultat
            stage = .awaitingConfirmation
            return .success(String(localized: "dsm_update.status.file_checked"))
        } catch {
            stage = .idle
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let raison = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "dsm_update.upload.error", defaultValue: "Sending failed: \(raison)"))
        }
    }

    /// Starts the installation, then follows the NAS until it answers again.
    func startUpgrade() async -> DSMOperationOutcome {
        guard stage == .awaitingConfirmation else { return .cancelled }
        stage = .starting
        errorMessage = nil
        do {
            try await session.withClient { try await $0.startDSMUpgrade() }
        } catch {
            stage = .awaitingConfirmation
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let raison = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "dsm_update.install.start.error", defaultValue: "Starting failed: \(raison)"))
        }

        stage = .installing
        await followInstallation()
        stage = .rebooting
        let revenu = await waitForReturn()
        stage = revenu ? .backOnline : .rebooting
        return revenu
            ? .success(String(localized: "dsm_update.status.nas_back"))
            : .failure(String(
                localized: "dsm_update.status.restart_timeout"
            ))
    }

    /// Follows progress for as long as the NAS still answers. Its disappearance is not an
    /// error here: it is the expected restart.
    private func followInstallation() async {
        while !Task.isCancelled {
            do {
                let avancement = try await session.withClient { try await $0.dsmUpgradeProgress() }
                installProgress = avancement
                if avancement.isFinished { return }
            } catch {
                return
            }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
        }
    }

    private func waitForReturn() async -> Bool {
        for _ in 0..<onlinePollLimit {
            if Task.isCancelled { return false }
            if await session.isNASBackOnline() { return true }
            do { try await Task.sleep(for: onlinePollInterval) } catch { return false }
        }
        return false
    }
}
