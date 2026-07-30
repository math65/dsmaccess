//
//  PerformanceAlarmRule.swift
//  dsmaccess
//
//  Performance alarm rules (SYNO.ResourceMonitor.EventRule). A rule states the threshold at
//  which the NAS must record an alert in its history: without a rule, that log stays empty
//  no matter what happens.
//
//  Contract proven against DSM 7.4 on 2026-07-30, by creating then deleting real rules.
//  Four quirks, three of which DSM's web client made hard to guess:
//  — The identifier is a **composite string** the NAS builds:
//    "type_service_resource_severity". Changing any one of those fields therefore changes the
//    rule's identity, and two rules sharing that quadruple collide (error 6106).
//  — The target goes out in a **single parameter, `service`**, whatever the type.
//  — `type` and `resource` are **integers**, and the meaning of a resource code depends on the
//    type: `4` is memory as a percentage for the system, in megabytes for a service.
//  — `severity` only knows two values, where the log displays three.
//

import Foundation

struct PerformanceAlarmRule: nonisolated Decodable, Sendable, Identifiable {
    /// String composed by the NAS: "type_service_resource_severity".
    let id: String
    let isEnabled: Bool
    let severity: Severity
    let kind: Kind
    let resource: Resource
    let threshold: Int
    /// Target as the NAS received it: a service's unit name, a volume path, or the "general"
    /// constant of a system rule.
    let target: String
    /// Label the NAS attaches to the target. Often readable, sometimes a key from its own
    /// catalogue — see `displayTarget`.
    let targetLabel: String?

    /// What the rule watches. The NAS sends an integer; an unexpected value would be a DSM
    /// evolution and stays readable rather than being rejected.
    enum Kind: Int, nonisolated Sendable, CaseIterable, Identifiable {
        case system = 0
        case service = 1
        case iSCSI = 2
        case volume = 3
        case internalUse = 4

        var id: Int { rawValue }

        /// Types the app knows how to compose. iSCSI and internal use stay readable and
        /// deletable, but are not offered at creation: the first could not be proven for lack
        /// of a LUN, the second is reserved for Synology.
        static let editable: [Kind] = [.system, .service, .volume]

        var isEditable: Bool { Self.editable.contains(self) }

        /// Value the NAS expects as target for the types that let no target be chosen.
        /// Verified: a saved system rule does carry "general".
        var fixedTarget: String? {
            switch self {
            case .system: "general"
            case .internalUse: "internal_use"
            case .service, .iSCSI, .volume: nil
            }
        }
    }

    enum Severity: Int, nonisolated Sendable, CaseIterable, Identifiable {
        case warning = 0
        case critical = 1

        var id: Int { rawValue }
    }

    /// Watched quantity. The same code does not designate the same thing from one type to the
    /// next: it only takes on meaning together with the rule's type.
    enum Resource: Int, nonisolated Sendable {
        case processorUsage = 0
        case loadAverageOneMinute = 1
        case loadAverageFiveMinutes = 2
        case loadAverageFifteenMinutes = 3
        case memory = 4
        case diskActivity = 5
        case networkLatency = 6
        case ioLatency = 7
        case rootPartition = 8
        case temporaryDirectory = 9
        case coredumpCount = 10
        case graphicsUsage = 11
    }

    /// Unit displayed next to the threshold. DSM derives it from the type / resource pair and
    /// never lets it be entered.
    enum Unit: nonisolated Sendable {
        case percent
        case megabytes
        case megabytesPerSecond
        case milliseconds
        /// A load average or a count has no unit.
        case none
    }

    /// A watchable quantity, with what DSM accepts as a threshold. The bounds come from the
    /// web client: a threshold outside them is refused by the NAS.
    struct Measure: nonisolated Sendable, Identifiable {
        let resource: Resource
        let unit: Unit
        let defaultThreshold: Int
        let range: ClosedRange<Int>

        var id: Int { resource.rawValue }
    }

    /// Quantities offered for a type, in the order DSM presents them. The GPU is only offered
    /// on a NAS that has one; it therefore does not appear here, for lack of being able to
    /// verify the `support_nvidia_gpu` flag on a model that has one.
    static func measures(for kind: Kind) -> [Measure] {
        switch kind {
        case .system:
            [
                Measure(resource: .processorUsage, unit: .percent, defaultThreshold: 80, range: 60...99),
                Measure(resource: .loadAverageOneMinute, unit: .none, defaultThreshold: 10, range: 1...1000),
                Measure(resource: .loadAverageFiveMinutes, unit: .none, defaultThreshold: 10, range: 1...1000),
                Measure(resource: .loadAverageFifteenMinutes, unit: .none, defaultThreshold: 10, range: 1...1000),
                Measure(resource: .memory, unit: .percent, defaultThreshold: 80, range: 1...99),
            ]
        case .service:
            [
                Measure(resource: .processorUsage, unit: .percent, defaultThreshold: 80, range: 60...99),
                Measure(resource: .memory, unit: .megabytes, defaultThreshold: 10, range: 1...524_288),
                Measure(resource: .diskActivity, unit: .megabytesPerSecond, defaultThreshold: 10, range: 1...65_536),
            ]
        case .volume:
            [Measure(resource: .diskActivity, unit: .percent, defaultThreshold: 80, range: 1...99)]
        case .iSCSI:
            [
                Measure(resource: .networkLatency, unit: .milliseconds, defaultThreshold: 100, range: 10...60_000),
                Measure(resource: .ioLatency, unit: .milliseconds, defaultThreshold: 100, range: 10...60_000),
            ]
        case .internalUse:
            [
                Measure(resource: .rootPartition, unit: .percent, defaultThreshold: 80, range: 1...99),
                Measure(resource: .temporaryDirectory, unit: .percent, defaultThreshold: 80, range: 1...99),
                Measure(resource: .coredumpCount, unit: .none, defaultThreshold: 0, range: 0...99),
            ]
        }
    }

    /// The quantity as DSM describes it for this pair, or `nil` if the NAS sent a combination
    /// the web client does not offer.
    var measure: Measure? {
        Self.measures(for: kind).first { $0.resource == resource }
    }

    /// Target as it deserves to be read. The NAS returns sometimes a label ("SNMP"), sometimes
    /// a key from its own catalogue ("firewall:firewall_service_opt_ssh") that its web client
    /// resolves and that we cannot resolve; the unit name, for its part, always stays
    /// meaningful. A system rule has no target: "general" is a DSM constant, not something the
    /// user would recognise.
    var displayTarget: String? {
        guard kind != .system, kind != .internalUse else { return nil }
        if let targetLabel, !targetLabel.isEmpty, !targetLabel.contains(":") {
            return targetLabel
        }
        // The systemd unit name carries a suffix that teaches nothing when read:
        // "sshd.slice" reads as "sshd".
        let unit = target.hasSuffix(Self.sliceSuffix)
            ? String(target.dropLast(Self.sliceSuffix.count))
            : target
        return ProcessGroup.readable(unit)
    }

    private static let sliceSuffix = ".slice"

    /// Non-optional sort keys: a missing value sorts first rather than preventing its column
    /// from being sorted at all.
    var sortableTarget: String { displayTarget ?? "" }
    var sortableKind: Int { kind.rawValue }
    var sortableSeverity: Int { severity.rawValue }
    /// Sorted as a number: `Bool` is not `Comparable`.
    var sortableEnabled: Int { isEnabled ? 1 : 0 }

    enum CodingKeys: String, CodingKey {
        case id, enable, severity, name, service, resource, threshold, type
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Without an identifier the rule can neither be toggled nor deleted: better that
        // decoding fails than displaying a row on which no action will work.
        id = try c.requiredFlexString(.id)
        isEnabled = c.flexBool(.enable) ?? false
        severity = Severity(rawValue: c.flexInt(.severity) ?? 0) ?? .warning
        kind = Kind(rawValue: c.flexInt(.type) ?? 0) ?? .system
        resource = Resource(rawValue: c.flexInt(.resource) ?? 0) ?? .processorUsage
        threshold = c.flexInt(.threshold) ?? 0
        target = c.flexString(.service) ?? ""
        targetLabel = c.flexString(.name)
    }
}

struct PerformanceAlarmRulePage: nonisolated Decodable, Sendable {
    let rules: [PerformanceAlarmRule]
    let total: Int?
    /// The NAS allows internal-use rules, reserved for Synology.
    let supportsInternalUse: Bool

    enum CodingKeys: String, CodingKey {
        case rules, total
        case supportsInternalUse = "support_internal"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = try c.decodeIfPresent([PerformanceAlarmRule].self, forKey: .rules) ?? []
        total = c.flexInt(.total)
        supportsInternalUse = c.flexBool(.supportsInternalUse) ?? false
    }
}

/// What `set` sends to create or modify a rule. Without `id`, DSM creates; with it, DSM
/// replaces. `enable` goes out in both cases: verified, the NAS demands it on modification
/// too, contrary to what its own form suggests.
struct PerformanceAlarmRuleDraft: nonisolated Sendable, Equatable {
    /// Identifier of the rule being modified, `nil` for a creation.
    var ruleID: String?
    var kind: PerformanceAlarmRule.Kind
    var resource: PerformanceAlarmRule.Resource
    var threshold: Int
    var severity: PerformanceAlarmRule.Severity
    var isEnabled: Bool
    /// Chosen service or volume. Empty for a type whose value DSM sets itself.
    var target: String

    var isCreation: Bool { ruleID == nil }

    /// The target as `set` expects it: the type's constant when it imposes one.
    var resolvedTarget: String { kind.fixedTarget ?? target }

    init(
        ruleID: String? = nil,
        kind: PerformanceAlarmRule.Kind = .system,
        resource: PerformanceAlarmRule.Resource = .processorUsage,
        threshold: Int = 80,
        severity: PerformanceAlarmRule.Severity = .warning,
        isEnabled: Bool = true,
        target: String = ""
    ) {
        self.ruleID = ruleID
        self.kind = kind
        self.resource = resource
        self.threshold = threshold
        self.severity = severity
        self.isEnabled = isEnabled
        self.target = target
    }

    /// Takes over an existing rule in order to modify it.
    init(editing rule: PerformanceAlarmRule) {
        self.init(
            ruleID: rule.id,
            kind: rule.kind,
            resource: rule.resource,
            threshold: rule.threshold,
            severity: rule.severity,
            isEnabled: rule.isEnabled,
            target: rule.target
        )
    }
}
