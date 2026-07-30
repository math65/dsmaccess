//
//  DSMUpgrade.swift
//  dsmaccess
//
//  Manual DSM update from a .pat file (SYNO.Core.Upgrade).
//

import Foundation

/// What DSM says about the received file before installing anything.
///
/// The flow was captured on DSM 7.4 by watching the web client, but the exact shape of the
/// responses could not be measured. Decoding therefore accepts several spellings and treats
/// no field as mandatory: an unexpected response must leave the screen usable, not interrupt
/// the operation.
struct DSMUpgradePreCheck: nonisolated Decodable, Equatable, Sendable {
    /// Packages DSM will stop supporting after the update.
    let unsupportedPackages: [String]
    /// True when DSM answered in a shape the app knows how to read. When false, the screen
    /// sends the user to DSM rather than claiming there is no consequence.
    let isUnderstood: Bool

    enum CodingKeys: String, CodingKey {
        case unsupportedPackages = "unsupported_packages"
        case removePackages = "remove_packages"
        case breakPackages = "break_pkgs"
        case packages
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var noms: [String] = []
        var reconnu = false
        for key in [CodingKeys.unsupportedPackages, .removePackages, .breakPackages, .packages] {
            guard let listed = Self.names(in: values, forKey: key) else { continue }
            reconnu = true
            noms.append(contentsOf: listed)
        }
        unsupportedPackages = Array(Set(noms)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        isUnderstood = reconnu
    }

    init(unsupportedPackages: [String], isUnderstood: Bool) {
        self.unsupportedPackages = unsupportedPackages
        self.isUnderstood = isUnderstood
    }

    /// DSM writes this kind of list sometimes as strings, sometimes as named objects.
    private static func names(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [String]? {
        if let plain = try? container.decode([String].self, forKey: key) {
            return plain.filter { !$0.isEmpty }
        }
        if let objects = try? container.decode([NamedPackage].self, forKey: key) {
            return objects.compactMap(\.resolvedName)
        }
        return nil
    }

    private struct NamedPackage: nonisolated Decodable {
        let resolvedName: String?

        enum CodingKeys: String, CodingKey {
            case name
            case displayName = "display_name"
            case packageID = "package"
        }

        nonisolated init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            resolvedName = values.flexString(.displayName)
                ?? values.flexString(.name)
                ?? values.flexString(.packageID)
        }
    }
}

/// Progress returned by `SYNO.Core.Upgrade` during installation. No field is guaranteed: the
/// screen makes do with what it gets and does not invent progress.
struct DSMUpgradeProgress: nonisolated Decodable, Equatable, Sendable {
    let percentage: Int?
    let isFinished: Bool

    enum CodingKeys: String, CodingKey {
        case progress
        case percent
        case status
        case finished
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let brut = values.flexInt(.progress) ?? values.flexInt(.percent)
        percentage = brut.map { min(max($0, 0), 100) }
        let status = values.flexString(.status)?.lowercased()
        isFinished = values.flexBool(.finished)
            ?? (status.map { ["done", "finished", "complete", "completed"].contains($0) } ?? false)
    }

    init(percentage: Int?, isFinished: Bool) {
        self.percentage = percentage
        self.isFinished = isFinished
    }
}

/// Response of `/webman/pingpong.cgi`, the signal DSM itself uses to know whether the NAS has
/// finished booting.
///
/// ⚠️ Measured on 2026-07-28: `boot_done` turns `true` while the DSM interface still shows
/// several more minutes of restarting. It says the host is answering, not that the update is
/// finished — only a successful reconnection proves that.
struct DSMBootState: nonisolated Decodable, Equatable, Sendable {
    let isBootDone: Bool

    enum CodingKeys: String, CodingKey {
        case bootDone = "boot_done"
        case success
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isBootDone = values.flexBool(.bootDone) ?? false
    }

    init(isBootDone: Bool) {
        self.isBootDone = isBootDone
    }
}
