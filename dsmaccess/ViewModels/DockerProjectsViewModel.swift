//
//  DockerProjectsViewModel.swift
//  dsmaccess
//
//  Compose projects: state, docker-compose actions and their streamed output.
//

import Foundation
import Observation

@MainActor
@Observable
final class DockerProjectsViewModel {
    /// Outcome of a compose action, kept for display: DSM's own client shows this output in a
    /// terminal window. The text is the only trace of what docker-compose did.
    struct ActionReport: Identifiable {
        let id = UUID()
        let projectName: String
        let actionLabel: String
        let result: DockerStreamResult
    }

    private(set) var projects: [DockerProject] = []
    private(set) var isLoading = false
    private(set) var busyProjectIDs: Set<String> = []
    var errorMessage: String?
    var actionReport: ActionReport?

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load(silently: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = !silently
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }

        do {
            let result = try await session.withClient { try await $0.listDockerProjects() }.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            guard generation == loadGeneration else { return }
            projects = result
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    func perform(_ action: DockerProjectAction, on project: DockerProject) async -> DSMOperationOutcome {
        busyProjectIDs.insert(project.id)
        defer { busyProjectIDs.remove(project.id) }

        do {
            let result = try await session.withClient {
                try await $0.performDockerProjectAction(action, projectID: project.id)
            }
            await load(silently: true)
            actionReport = ActionReport(
                projectName: project.name,
                actionLabel: Self.label(for: action),
                result: result
            )
            if result.succeeded {
                return .success(successMessage(for: action, project: project))
            }
            // A build that dies before compose finishes ends without an Exit Code line.
            if let exitCode = result.exitCode {
                return .failure(String(
                    localized: "containers.project.action.failed_with_code",
                    defaultValue: "\(Self.label(for: action)) failed for \(project.name), exit code \(exitCode)"
                ))
            }
            return .failure(String(
                localized: "containers.project.action.failed",
                defaultValue: "\(Self.label(for: action)) failed for \(project.name)"
            ))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.failed_for_item", defaultValue: "Failed for \(project.name): \(reason)"))
        }
    }

    func delete(_ project: DockerProject) async -> DSMOperationOutcome {
        busyProjectIDs.insert(project.id)
        defer { busyProjectIDs.remove(project.id) }

        do {
            try await session.withClient { try await $0.deleteDockerProject(id: project.id) }
            await load(silently: true)
            return .success(String(
                localized: "containers.project.delete.success",
                defaultValue: "Project deleted: \(project.name)"
            ))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.failed_for_item", defaultValue: "Failed for \(project.name): \(reason)"))
        }
    }

    /// Fetches the compose file, absent from the list payload.
    func projectDetails(id: String) async throws -> DockerProject {
        try await session.withClient { try await $0.dockerProject(id: id) }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        let running = projects.filter(\.isRunning).count
        return String(
            localized: "containers.project.summary.count",
            defaultValue: "\(projects.count) projects, \(running) running"
        )
    }

    static func label(for action: DockerProjectAction) -> String {
        switch action {
        case .start: String(localized: "common.button.start")
        case .stop: String(localized: "common.button.stop")
        case .restart: String(localized: "containers.action.restart")
        case .build: String(localized: "containers.project.action.build")
        case .clean: String(localized: "containers.project.action.clean")
        }
    }

    private func successMessage(for action: DockerProjectAction, project: DockerProject) -> String {
        switch action {
        case .start:
            String(localized: "containers.project.action.start.success", defaultValue: "Project started: \(project.name)")
        case .stop:
            String(localized: "containers.project.action.stop.success", defaultValue: "Project stopped: \(project.name)")
        case .restart:
            String(localized: "containers.project.action.restart.success", defaultValue: "Project restarted: \(project.name)")
        case .build:
            String(localized: "containers.project.action.build.success", defaultValue: "Project rebuilt: \(project.name)")
        case .clean:
            String(localized: "containers.project.action.clean.success", defaultValue: "Project cleaned: \(project.name)")
        }
    }
}
