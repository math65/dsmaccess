//
//  USBCopyViewModel.swift
//  dsmaccess
//
//  État et orchestration des opérations USB Copy.
//

import Foundation
import Observation

@MainActor
@Observable
final class USBCopyViewModel {
    private(set) var tasks: [USBCopyTask] = []
    private(set) var availableShares: [SharedFolder] = []
    private(set) var isLoading = false
    private(set) var busyTaskIDs: Set<Int> = []
    var errorMessage: String?

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load(silently: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if !silently { isLoading = true }
        errorMessage = nil
        defer {
            if generation == loadGeneration { isLoading = false }
        }

        do {
            let result = try await session.withClient { client in
                let tasks = try await client.listUSBCopyTasks().sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                let shares = try await client.usbCopyAvailableShares()
                return (tasks, shares)
            }
            guard generation == loadGeneration else { return }
            tasks = result.0
            availableShares = result.1
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = reason(for: error)
        }
    }

    func details(taskID: Int) async throws -> USBCopyTaskDetails {
        try await session.withClient { client in
            let task = try await client.usbCopyTask(id: taskID)
            async let filter = client.usbCopyFilter(taskID: taskID)
            async let trigger = client.usbCopyTrigger(for: task)
            let (loadedFilter, loadedTrigger) = try await (filter, trigger)
            return USBCopyTaskDetails(
                task: task,
                filter: loadedFilter,
                trigger: loadedTrigger
            )
        }
    }

    func create(_ task: USBCopyTaskCreation) async -> DSMOperationOutcome {
        do {
            _ = try await session.withClient { try await $0.createUSBCopyTask(task) }
            await load()
            return .success(String(localized: "Tâche USB Copy créée : \(task.name)"))
        } catch {
            return failure(error, action: String(localized: "création de la tâche"))
        }
    }

    func save(_ settings: USBCopyTaskSettings) async -> DSMOperationOutcome {
        let enablesDefaultTask = tasks.first(where: { $0.id == settings.id }).map {
            $0.isDefaultTask == true && $0.canEnable
                && $0.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
        let saveOutcome = await perform(taskID: settings.id, action: String(localized: "modification de la tâche")) {
            try await $0.setUSBCopyTaskSettings(settings)
            return String(localized: "Tâche USB Copy modifiée : \(settings.name)")
        }
        guard enablesDefaultTask, case .success = saveOutcome,
              let task = tasks.first(where: { $0.id == settings.id }) else {
            return saveOutcome
        }

        let enableOutcome = await enable(task)
        return switch enableOutcome {
        case .success:
            .success(String(localized: "Tâche enregistrée et activée : \(settings.name)"))
        case .failure(let message):
            .failure(String(localized: "Le dossier a été enregistré, mais la tâche n’a pas pu être activée. \(message)"))
        case .cancelled:
            .failure(String(localized: "Le dossier a été enregistré, mais l’activation de la tâche a été annulée."))
        }
    }

    func save(_ trigger: USBCopyTrigger, task: USBCopyTask) async -> DSMOperationOutcome {
        await perform(taskID: task.id, action: String(localized: "modification du déclenchement")) {
            try await $0.setUSBCopyTrigger(trigger, taskID: task.id)
            return String(localized: "Déclenchement modifié pour \(task.name)")
        }
    }

    func save(_ filter: USBCopyFilter, task: USBCopyTask) async -> DSMOperationOutcome {
        await perform(taskID: task.id, action: String(localized: "modification du filtre")) {
            try await $0.setUSBCopyFilter(filter, taskID: task.id)
            return String(localized: "Filtre modifié pour \(task.name)")
        }
    }

    func run(_ task: USBCopyTask) async -> DSMOperationOutcome {
        await perform(taskID: task.id, action: String(localized: "démarrage de la tâche")) {
            try await $0.runUSBCopyTask(id: task.id)
            return String(localized: "Tâche démarrée : \(task.name)")
        }
    }

    func cancel(_ task: USBCopyTask) async -> DSMOperationOutcome {
        await perform(taskID: task.id, action: String(localized: "annulation de la tâche")) {
            try await $0.cancelUSBCopyTask(id: task.id)
            return String(localized: "Annulation demandée : \(task.name)")
        }
    }

    func enable(_ task: USBCopyTask) async -> DSMOperationOutcome {
        await perform(taskID: task.id, action: String(localized: "activation de la tâche")) {
            try await $0.enableUSBCopyTask(id: task.id)
            return String(localized: "Tâche activée : \(task.name)")
        }
    }

    func disable(_ task: USBCopyTask) async -> DSMOperationOutcome {
        await perform(taskID: task.id, action: String(localized: "désactivation de la tâche")) {
            try await $0.disableUSBCopyTask(id: task.id)
            return String(localized: "Tâche désactivée : \(task.name)")
        }
    }

    func delete(_ task: USBCopyTask) async -> DSMOperationOutcome {
        await perform(taskID: task.id, action: String(localized: "suppression de la tâche")) {
            try await $0.deleteUSBCopyTask(id: task.id)
            return String(localized: "Tâche supprimée : \(task.name)")
        }
    }

    func globalSettings() async throws -> USBCopyGlobalSettings {
        try await session.withClient { try await $0.usbCopyGlobalSettings() }
    }

    func repositoryVolumePaths() async throws -> [String] {
        try await session.withClient { try await $0.usbCopyAvailableVolumePaths() }
    }

    func folders(in path: String) async throws -> [FileStationItem] {
        try await session.withClient { client in
            try await client.list(folderPath: path)
                .filter(\.isdir)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func saveGlobalSettings(_ settings: USBCopyGlobalSettings) async -> DSMOperationOutcome {
        guard (5...100_000).contains(settings.logRotateCount) else {
            return .failure(String(localized: "Le nombre de journaux doit être compris entre 5 et 100 000."))
        }
        do {
            try await session.withClient { try await $0.setUSBCopyGlobalSettings(settings) }
            return .success(String(localized: "Réglages généraux USB Copy enregistrés"))
        } catch {
            return failure(error, action: String(localized: "enregistrement des réglages généraux"))
        }
    }

    func logs(
        filter: USBCopyLogFilter,
        offset: Int = 0,
        limit: Int = 200
    ) async throws -> USBCopyLogPage {
        try await session.withClient {
            try await $0.usbCopyLogs(offset: offset, limit: limit, filter: filter)
        }
    }

    var localShares: [SharedFolder] {
        availableShares.filter {
            $0.externalDeviceType != "USB" && $0.externalDeviceType != "SDCARD"
        }
    }

    var externalShares: [SharedFolder] {
        availableShares.filter {
            $0.externalDeviceType == "USB" || $0.externalDeviceType == "SDCARD"
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        let activeCount = tasks.count(where: \.isActive)
        return String(localized: "\(tasks.count) tâches USB Copy, \(activeCount) actives")
    }

    private func perform(
        taskID: Int,
        action: String,
        operation: (DSMClientProtocol) async throws -> String
    ) async -> DSMOperationOutcome {
        guard !busyTaskIDs.contains(taskID) else { return .cancelled }
        busyTaskIDs.insert(taskID)
        defer { busyTaskIDs.remove(taskID) }
        do {
            let message = try await session.withClient(operation)
            await load(silently: true)
            return .success(message)
        } catch {
            await load(silently: true)
            return failure(error, action: action)
        }
    }

    private func failure(_ error: Error, action: String) -> DSMOperationOutcome {
        guard !DSMError.isCancellation(error) else { return .cancelled }
        return .failure(String(localized: "Échec de \(action) : \(reason(for: error))"))
    }

    private func reason(for error: Error) -> String {
        if case let DSMError.apiError(code) = error {
            switch code {
            case 401: return String(localized: "USB Copy a signalé une erreur interne.")
            case 402: return String(localized: "Un réglage envoyé à USB Copy est invalide.")
            case 403: return String(localized: "Ce périphérique USB est déjà utilisé par une autre tâche.")
            case 404: return String(localized: "Le dépôt USB Copy n’est pas configuré.")
            case 405: return String(localized: "USB Copy est en cours d’initialisation.")
            case 406: return String(localized: "USB Copy est en cours de mise à niveau.")
            case 407: return String(localized: "Le dépôt USB Copy est en cours de déplacement.")
            case 408: return String(localized: "Le volume choisi pour USB Copy est invalide.")
            case 409: return String(localized: "Le volume ne dispose pas d’assez d’espace.")
            case 410: return String(localized: "La destination est déjà utilisée par une autre tâche.")
            case 411: return String(localized: "USB Copy ne reconnaît pas ce périphérique.")
            case 413: return String(localized: "Le dossier de destination n’existe pas.")
            case 414: return String(localized: "Le chemin choisi n’est pas valide.")
            case 415: return String(localized: "La mise à niveau de USB Copy a échoué.")
            case 416: return String(localized: "Le dossier partagé n’existe pas.")
            case 417: return String(localized: "Le dossier partagé n’est pas monté.")
            case 418: return String(localized: "Le dossier partagé n’est pas disponible.")
            case 419: return String(localized: "Le dossier source n’existe pas.")
            case 420: return String(localized: "Le volume est verrouillé.")
            default: break
            }
        }
        return (error as? DSMError)?.errorDescription ?? error.localizedDescription
    }
}

struct USBCopyTaskDetails: Sendable {
    let task: USBCopyTask
    let filter: USBCopyFilter
    let trigger: USBCopyTrigger
}
