//
//  NASConnection.swift
//  dsmaccess
//
//  Sessions open on the NAS (SYNO.Core.CurrentConnection get), as the resource monitor's
//  Connections tab presents them.
//
//  Two warnings observed on DSM 7.4 on 2026/07/29:
//  — `descr` is "DiskStation Manager" for both the app and the web client; only the source
//    address tells them apart.
//  — `time` and `first_login_time` contradict each other from one entry to the next. DSM
//    shows `time` in its "Time" column: that is the one that is authoritative here.
//

import Foundation

struct NASConnectionPage: nonisolated Decodable, Sendable {
    let items: [NASConnection]
}

struct NASConnection: nonisolated Decodable, Sendable, Identifiable {
    let account: String?
    let address: String?
    /// Protocol displayed by DSM: "HTTP/HTTPS", "SMB3"…
    let type: String?
    /// Resource or application involved, depending on the protocol.
    let descriptionText: String?
    /// Raw NAS timestamp, in "yyyy/MM/dd HH:mm:ss" format.
    let rawTime: String?
    let isCurrent: Bool
    let canBeKicked: Bool
    /// Identifier of the process holding the session. It is 1 for every web session, so it
    /// identifies nothing on its own, but `kick_connection` requires it for the other
    /// protocols.
    let processID: Int?
    /// Device token. Filled in for web sessions, empty for the others.
    let deviceID: String?
    /// Client that opened the session, as the NAS saw it. Often empty.
    let userAgent: String?
    /// Location inferred by DSM. Empty on local access.
    let location: String?
    /// The device was marked as trusted during a two-step verification.
    let isTrustedDevice: Bool
    /// The session was opened with a two-step verification.
    let usesTwoFactor: Bool

    /// The NAS does not assign a session identifier. `did` is part of the key because several
    /// web sessions of the same account often share account, address, protocol and timestamp:
    /// without it they would be indistinguishable and selection would hit the wrong one.
    var id: String {
        [account, address, type, rawTime, deviceID].compactMap { $0 }.joined(separator: "|")
    }

    /// Non-optional sort keys: a missing value sorts first rather than preventing its column
    /// from being sorted at all.
    var sortableAccount: String { account ?? "" }
    var sortableAddress: String { address ?? "" }
    var sortableType: String { type ?? "" }
    var sortableDescription: String { descriptionText ?? "" }
    var sortableDate: Date { openedAt ?? .distantPast }
    var sortableUserAgent: String { userAgent ?? "" }
    var sortableLocation: String { location ?? "" }
    /// Sorted as text: `Bool` is not `Comparable`, and the column must be sortable like the
    /// others.
    var sortableTwoFactor: String { usesTwoFactor ? "1" : "0" }

    /// Timestamp rendered in the Mac's language and time zone. Since DSM does not state the
    /// time zone of its value, it is read as local — correct as long as the NAS and the Mac
    /// share the same one, which is the common case. The raw string is kept as a fallback
    /// rather than displaying nothing.
    var openedAt: Date? {
        guard let rawTime else { return nil }
        return Self.nasFormatter.date(from: rawTime)
    }

    private static let nasFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()

    /// What `kick_connection` expects in order to find the session to cut. DSM does not
    /// identify it by a unique key: it re-identifies it through a quadruplet, and that
    /// quadruplet differs by protocol. `nil` when a required value is missing — better not to
    /// offer the disconnect than to target a session at random.
    enum KickReference: Sendable, Equatable {
        case web(deviceID: String, account: String, resource: String, address: String)
        case service(processID: Int, type: String, account: String, address: String)
    }

    /// Exact value DSM puts in `type` for its web sessions. Observed on DSM 7.4: it is a
    /// single string, slash included, not two separate protocols.
    static let webSessionType = "HTTP/HTTPS"

    var isWebSession: Bool { type == Self.webSessionType }

    var kickReference: KickReference? {
        guard canBeKicked, let account, let address else { return nil }
        if isWebSession {
            // `descr` and `did` go out as they are: DSM compares values, and a missing one
            // counts as an empty string, just as in its own client.
            return .web(
                deviceID: deviceID ?? "",
                account: account,
                resource: descriptionText ?? "",
                address: address
            )
        }
        guard let processID, let type else { return nil }
        return .service(processID: processID, type: type, account: account, address: address)
    }

    enum CodingKeys: String, CodingKey {
        case who, from, type, descr, time, pid, did, location
        case userAgent = "user_agent"
        case isCurrent = "is_current_connected"
        case canBeKicked = "can_be_kicked"
        case isTrustedDevice = "is_otp_trusted"
        case usesTwoFactor = "is_amfa"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        account = c.flexString(.who)
        address = c.flexString(.from)
        type = c.flexString(.type)
        descriptionText = c.flexString(.descr)
        rawTime = c.flexString(.time)
        isCurrent = c.flexBool(.isCurrent) ?? false
        canBeKicked = c.flexBool(.canBeKicked) ?? false
        processID = c.flexInt(.pid)
        deviceID = c.flexString(.did)
        // These three fields most often come back empty on local access: an empty value
        // counts as absence, so the display can simply say nothing.
        userAgent = c.flexString(.userAgent).flatMap { $0.isEmpty ? nil : $0 }
        location = c.flexString(.location).flatMap { $0.isEmpty ? nil : $0 }
        isTrustedDevice = c.flexBool(.isTrustedDevice) ?? false
        usesTwoFactor = c.flexBool(.usesTwoFactor) ?? false
    }
}
