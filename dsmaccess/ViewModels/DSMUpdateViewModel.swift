//
//  DSMUpdateViewModel.swift
//  dsmaccess
//
//  Conduite d'une mise à jour manuelle de DSM, du choix du fichier au retour du NAS.
//

import Foundation
import Observation

@MainActor
@Observable
final class DSMUpdateViewModel {
    /// Étapes de l'opération. Elles servent aussi à décider ce qui est annoncé : une
    /// installation dure une vingtaine de minutes et l'écran change seul d'état.
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
    /// Sondage du retour du NAS : 15 s entre deux essais, plafonné à 40 minutes. DSM annonce
    /// 10 à 20 minutes ; au-delà du plafond, l'app le dit au lieu d'attendre indéfiniment.
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

    /// Texte d'état, unique source de vérité pour l'affichage comme pour les annonces.
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

    /// Envoie le fichier puis demande au NAS ce qu'il en pense. S'arrête avant d'installer :
    /// la décision revient à l'utilisateur, une fois les conséquences connues.
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

    /// Lance l'installation, puis suit le NAS jusqu'à ce qu'il réponde de nouveau.
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

    /// Suit la progression tant que le NAS répond encore. Sa disparition n'est pas une erreur
    /// ici : c'est le redémarrage attendu.
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
