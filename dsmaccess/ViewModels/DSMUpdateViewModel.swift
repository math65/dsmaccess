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
            return String(localized: "Version du NAS inconnue.")
        }
        return String(localized: "Version installée : \(currentVersion)")
    }

    /// Texte d'état, unique source de vérité pour l'affichage comme pour les annonces.
    var statusText: String {
        switch stage {
        case .idle:
            return selectedFile.map { String(localized: "Fichier prêt : \($0.lastPathComponent)") }
                ?? String(localized: "Aucun fichier de mise à jour sélectionné.")
        case .uploading:
            guard let fraction = transferProgress?.fractionCompleted else {
                return String(localized: "Envoi du fichier au NAS.")
            }
            let pourcentage = fraction.formatted(.percent.precision(.fractionLength(0)))
            return String(localized: "Envoi du fichier au NAS, \(pourcentage).")
        case .checking:
            return String(localized: "Le NAS vérifie le fichier de mise à jour.")
        case .awaitingConfirmation:
            return String(localized: "Le fichier est accepté. Confirmez pour installer.")
        case .starting:
            return String(localized: "Démarrage de l’installation.")
        case .installing:
            guard let pourcentage = installProgress?.percentage else {
                return String(localized: "Installation en cours sur le NAS.")
            }
            return String(localized: "Installation en cours sur le NAS, \(pourcentage) %.")
        case .rebooting:
            return String(localized: "Le NAS redémarre. Cela prend 10 à 20 minutes.")
        case .backOnline:
            return String(localized: "Le NAS répond à nouveau. Reconnectez-vous pour vérifier la version.")
        case .finished:
            return String(localized: "Mise à jour terminée.")
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
            return .success(String(localized: "Fichier envoyé et vérifié par le NAS."))
        } catch {
            stage = .idle
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let raison = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "Échec de l’envoi : \(raison)"))
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
            return .failure(String(localized: "Échec du lancement : \(raison)"))
        }

        stage = .installing
        await followInstallation()
        stage = .rebooting
        let revenu = await waitForReturn()
        stage = revenu ? .backOnline : .rebooting
        return revenu
            ? .success(String(localized: "Le NAS répond à nouveau. Reconnectez-vous pour vérifier la version."))
            : .failure(String(
                localized: "Le NAS n’a pas répondu dans le temps prévu. Vérifiez-le directement avant de relancer quoi que ce soit."
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
