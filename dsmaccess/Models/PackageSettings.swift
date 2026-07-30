//
//  PackageSettings.swift
//  dsmaccess
//
//  Response of SYNO.Core.Package.Setting (method=get): global Package Center preferences.
//  UNDOCUMENTED API. Confirmed quirk: `update_channel` is a boolean when read but is written
//  as a string ("stable"/"beta"). All the fields are kept (even those not exposed in the UI,
//  such as default_vol/trust_level) in order to *preserve* them on write: the API's `set`
//  expects the complete object.
//

import Foundation

struct PackageSettings: nonisolated Decodable, Equatable, Sendable {
    var enableAutoupdate: Bool
    var autoupdateAll: Bool
    var autoupdateImportant: Bool
    var enableDsm: Bool
    var enableEmail: Bool
    var defaultVol: String
    var trustLevel: Int
    /// Beta channel: true = beta versions shown. Sent as "beta"/"stable" on write.
    var updateChannelBeta: Bool

    enum CodingKeys: String, CodingKey {
        case enableAutoupdate = "enable_autoupdate"
        case autoupdateAll = "autoupdateall"
        case autoupdateImportant = "autoupdateimportant"
        case enableDsm = "enable_dsm"
        case enableEmail = "enable_email"
        case defaultVol = "default_vol"
        case trustLevel = "trust_level"
        case updateChannelBeta = "update_channel"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enableAutoupdate = try c.requiredFlexBool(.enableAutoupdate)
        autoupdateAll = try c.requiredFlexBool(.autoupdateAll)
        autoupdateImportant = try c.requiredFlexBool(.autoupdateImportant)
        enableDsm = try c.requiredFlexBool(.enableDsm)
        enableEmail = try c.requiredFlexBool(.enableEmail)
        defaultVol = try c.requiredFlexString(.defaultVol)
        trustLevel = try c.requiredFlexInt(.trustLevel)
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

/// Automatic update strategy, derived from the API's three raw fields.
enum AutoUpdateMode: CaseIterable, Identifiable, Sendable {
    case off        // disabled
    case important  // important versions (security)
    case latest     // latest versions
    var id: Self { self }
}

extension PackageSettings {
    /// Current mode, computed from enable_autoupdate + autoupdateall.
    var autoUpdateMode: AutoUpdateMode {
        guard enableAutoupdate else { return .off }
        return autoupdateAll ? .latest : .important
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
        }
    }
}
