//
//  PackageSettings.swift
//  dsmaccess
//
//  Response of SYNO.Core.Package.Setting (method=get): global Package Center preferences.
//  UNDOCUMENTED API, measured on DSM 7.4 by intercepting the Package Center web client.
//  Confirmed quirk: `update_channel` is a boolean when read but is written as a string
//  ("stable"/"beta").
//
//  `get` returns autoupdateall, autoupdateimportant, enable_autoupdate, enable_dsm,
//  enable_email, mailset, show_disable_autoupdate, trust_level, update_channel,
//  volume_count, volume_list and volume_status. It does *not* return `default_vol`, which
//  belongs to SYNO.Core.Package.Setting.Volume — requiring it here made the whole screen
//  fail to load. The web client's `set` sends only the six fields modelled below, so
//  nothing else has to be read back in order to be preserved.
//

import Foundation

struct PackageSettings: nonisolated Decodable, Equatable, Sendable {
    var enableAutoupdate: Bool
    var autoupdateAll: Bool
    var autoupdateImportant: Bool
    var enableDsm: Bool
    var enableEmail: Bool
    /// Beta channel: true = beta versions shown. Sent as "beta"/"stable" on write.
    var updateChannelBeta: Bool

    enum CodingKeys: String, CodingKey {
        case enableAutoupdate = "enable_autoupdate"
        case autoupdateAll = "autoupdateall"
        case autoupdateImportant = "autoupdateimportant"
        case enableDsm = "enable_dsm"
        case enableEmail = "enable_email"
        case updateChannelBeta = "update_channel"
    }

    init(
        enableAutoupdate: Bool,
        autoupdateAll: Bool,
        autoupdateImportant: Bool,
        enableDsm: Bool,
        enableEmail: Bool,
        updateChannelBeta: Bool
    ) {
        self.enableAutoupdate = enableAutoupdate
        self.autoupdateAll = autoupdateAll
        self.autoupdateImportant = autoupdateImportant
        self.enableDsm = enableDsm
        self.enableEmail = enableEmail
        self.updateChannelBeta = updateChannelBeta
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enableAutoupdate = try c.requiredFlexBool(.enableAutoupdate)
        autoupdateAll = try c.requiredFlexBool(.autoupdateAll)
        autoupdateImportant = try c.requiredFlexBool(.autoupdateImportant)
        enableDsm = try c.requiredFlexBool(.enableDsm)
        enableEmail = try c.requiredFlexBool(.enableEmail)
        // update_channel: boolean when read, but a string ("beta"/"stable") is tolerated.
        if let b = try? c.decode(Bool.self, forKey: .updateChannelBeta) {
            updateChannelBeta = b
        } else if let s = try? c.decode(String.self, forKey: .updateChannelBeta) {
            updateChannelBeta = s.lowercased() == "beta"
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .updateChannelBeta,
                in: c,
                debugDescription: "Required package update channel is missing or malformed."
            )
        }
    }
}

/// Automatic update strategy, derived from the API's three raw fields. DSM offers four,
/// measured by saving each one and reading back what the web client sent.
enum AutoUpdateMode: CaseIterable, Identifiable, Sendable {
    case off        // disabled
    case important  // important versions (security), every package
    case latest     // latest versions, every package
    case custom     // per-package lists, sent as `packages` and `packages_important`
    var id: Self { self }
}

/// What a single package does about updates, as DSM's own per-package menu offers it.
enum PackageAutoUpdateChoice: CaseIterable, Identifiable, Sendable {
    case none
    case important
    case all

    var id: Self { self }

    var name: String {
        switch self {
        case .none: String(localized: "packages.auto_update.none")
        case .important: String(localized: "packages.settings.update_scope.important")
        case .all: String(localized: "packages.settings.update_scope.latest")
        }
    }
}

/// The two per-package lists the custom strategy sends. DSM does not return them from `get`:
/// the current state of a package is read from its own `autoupdate` fields.
struct PackageAutoUpdateSelection: Equatable, Sendable {
    var allVersions: [String]
    var importantVersions: [String]

    init(allVersions: [String] = [], importantVersions: [String] = []) {
        self.allVersions = allVersions
        self.importantVersions = importantVersions
    }
}

extension PackageSettings {
    /// Current mode. Custom is what remains once automatic updates are on and neither
    /// "everything" flag is: that is exactly the shape DSM saves for a per-package strategy.
    var autoUpdateMode: AutoUpdateMode {
        guard enableAutoupdate else { return .off }
        if autoupdateAll { return .latest }
        if autoupdateImportant { return .important }
        return .custom
    }

    /// Applies a mode to the three raw fields.
    mutating func setAutoUpdateMode(_ mode: AutoUpdateMode) {
        switch mode {
        case .off:
            enableAutoupdate = false
        case .important:
            enableAutoupdate = true
            autoupdateAll = false
            autoupdateImportant = true
        case .latest:
            enableAutoupdate = true
            autoupdateAll = true
            autoupdateImportant = true
        case .custom:
            enableAutoupdate = true
            autoupdateAll = false
            autoupdateImportant = false
        }
    }
}
