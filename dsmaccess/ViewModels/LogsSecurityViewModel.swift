//
//  LogsSecurityViewModel.swift
//  dsmaccess
//
//  État des journaux DSM et de la liste de blocage.
//

import Foundation
import Observation

@MainActor
@Observable
final class LogsSecurityViewModel {
    private(set) var logs: [SystemLogEntry] = []
    private(set) var blockedAddresses: [BlockedAddress] = []
    private(set) var isLoading = false
    private(set) var busyAddresses: Set<String> = []
    var errorMessage: String?
    var blockedAddressesError: String?

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        blockedAddressesError = nil
        defer { isLoading = false }

        do {
            try await session.withClient { client in
                if session.capabilities.supports("SYNO.Core.SyslogClient.Log") {
                    logs = try await client.listSystemLogs()
                } else {
                    logs = []
                }

                do {
                    blockedAddresses = try await client.listBlockedAddresses().sorted {
                        $0.address.localizedStandardCompare($1.address) == .orderedAscending
                    }
                } catch let error as DSMError where isOptionalBlockListError(error) {
                    blockedAddresses = []
                } catch DSMError.sessionExpired {
                    throw DSMError.sessionExpired
                } catch {
                    blockedAddresses = []
                    blockedAddressesError = (error as? DSMError)?.errorDescription ?? error.localizedDescription
                }
            }
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    func unblock(_ blockedAddress: BlockedAddress) async -> String {
        busyAddresses.insert(blockedAddress.address)
        defer { busyAddresses.remove(blockedAddress.address) }

        do {
            try await session.withClient { try await $0.unblockAddress(blockedAddress.address) }
            blockedAddresses.removeAll { $0.id == blockedAddress.id }
            return String(localized: "Adresse débloquée : \(blockedAddress.address)")
        } catch {
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return String(localized: "Échec du déblocage : \(reason)")
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "\(logs.count) entrées de journal, \(blockedAddresses.count) adresses bloquées")
    }

    private func isOptionalBlockListError(_ error: DSMError) -> Bool {
        switch error {
        case .unsupportedAPI, .unsupportedAPIVersion: true
        default: false
        }
    }
}
