import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct PerformanceAlarmRuleTests {
    /// Payload exactly as the DS920+ returned it on 2026-07-30, after creating real rules. The
    /// identifier is a composite string built by the NAS, and the target arrives twice: its raw
    /// value in `service`, its label in `name`.
    @Test func readsRulesAsTheNASSendsThem() throws {
        let payload = Data(#"""
        {"rules":[
          {"enable":true,"hash":"","id":"0_general_4_0","name":"general","resource":4,
           "service":"general","severity":0,"threshold":1,"type":0},
          {"enable":true,"hash":"","id":"1_snmp.slice_0_1","name":"SNMP","resource":0,
           "service":"snmp.slice","severity":1,"threshold":80,"type":1},
          {"enable":false,"hash":"","id":"3_/volume1_5_0","name":"/volume1","resource":5,
           "service":"/volume1","severity":0,"threshold":80,"type":3}],
         "support_internal":0,"total":3}
        """#.utf8)

        let page = try JSONDecoder().decode(PerformanceAlarmRulePage.self, from: payload)

        #expect(page.total == 3)
        // `support_internal` arrives as a number, not a boolean.
        #expect(!page.supportsInternalUse)

        let system = try #require(page.rules.first)
        #expect(system.id == "0_general_4_0")
        #expect(system.kind == .system)
        #expect(system.resource == .memory)
        #expect(system.severity == .warning)
        #expect(system.threshold == 1)
        // "general" is a constant of DSM's own form, not a target to show.
        #expect(system.displayTarget == nil)

        let service = page.rules[1]
        #expect(service.kind == .service)
        #expect(service.severity == .critical)
        #expect(service.target == "snmp.slice")
        #expect(service.displayTarget == "SNMP")

        let volume = page.rules[2]
        #expect(volume.kind == .volume)
        #expect(!volume.isEnabled)
        #expect(volume.displayTarget == "/volume1")
    }

    /// Verified on the NAS: `sshd.slice` comes back with `name` holding a DSM catalog key,
    /// which its web client resolves and we cannot. Shown as-is, the rule would read
    /// "firewall:firewall_service_opt_ssh".
    @Test func neverShowsADSMCatalogKeyAsATargetName() throws {
        let payload = Data(#"""
        {"rules":[{"enable":true,"hash":"","id":"1_sshd.slice_0_0",
          "name":"firewall:firewall_service_opt_ssh","resource":0,"service":"sshd.slice",
          "severity":0,"threshold":80,"type":1}],"support_internal":0,"total":1}
        """#.utf8)

        let rule = try #require(
            try JSONDecoder().decode(PerformanceAlarmRulePage.self, from: payload).rules.first
        )

        // The unit name is still meaningful once stripped of its systemd suffix.
        #expect(rule.displayTarget == "sshd")
    }

    /// Without an identifier, a rule can neither be toggled nor deleted: better to reject the
    /// row than to display it with commands that will fail.
    @Test func refusesARuleWithoutAnIdentifier() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                PerformanceAlarmRulePage.self,
                from: Data(#"{"rules":[{"enable":true,"type":0,"resource":0}],"total":1}"#.utf8)
            )
        }
    }

    /// The same resource code does not denote the same quantity depending on the kind: `4` is
    /// a memory percentage for the system and a number of megabytes for a service, `5` is a
    /// throughput for a service and a percentage for a volume.
    @Test func readsTheSameResourceCodeDifferentlyPerKind() throws {
        let systemMemory = try #require(
            PerformanceAlarmRule.measures(for: .system).first { $0.resource == .memory }
        )
        let serviceMemory = try #require(
            PerformanceAlarmRule.measures(for: .service).first { $0.resource == .memory }
        )
        let serviceDisk = try #require(
            PerformanceAlarmRule.measures(for: .service).first { $0.resource == .diskActivity }
        )
        let volumeDisk = try #require(
            PerformanceAlarmRule.measures(for: .volume).first { $0.resource == .diskActivity }
        )

        #expect(systemMemory.unit == .percent)
        #expect(systemMemory.range == 1...99)
        #expect(serviceMemory.unit == .megabytes)
        #expect(serviceMemory.range == 1...524_288)
        #expect(serviceDisk.unit == .megabytesPerSecond)
        #expect(volumeDisk.unit == .percent)
    }

    /// iSCSI and internal use stay readable — an existing rule must not vanish from the list —
    /// but are not offered when composing one, for lack of having been able to test them.
    @Test func offersOnlyTheKindsItCanCompose() {
        #expect(PerformanceAlarmRule.Kind.editable == [.system, .service, .volume])
        #expect(!PerformanceAlarmRule.Kind.iSCSI.isEditable)
        #expect(!PerformanceAlarmRule.Kind.internalUse.isEditable)
        // Their catalog stays known, so a rule the NAS returns can still be described.
        #expect(!PerformanceAlarmRule.measures(for: .iSCSI).isEmpty)
    }

    /// DSM imposes the target for some kinds itself: a system rule carries "general".
    @Test func fillsTheTargetDSMImposes() {
        let system = PerformanceAlarmRuleDraft(kind: .system, target: "ignoré")
        let service = PerformanceAlarmRuleDraft(kind: .service, target: "snmp.slice")

        #expect(system.resolvedTarget == "general")
        #expect(service.resolvedTarget == "snmp.slice")
    }

    /// Editing a rule carries its identifier over: without it, the NAS would create a
    /// duplicate and refuse, the quadruplet being already taken.
    @Test func carriesTheIdentifierWhenEditing() throws {
        let payload = Data(#"""
        {"rules":[{"enable":true,"id":"1_snmp.slice_0_1","name":"SNMP","resource":0,
          "service":"snmp.slice","severity":1,"threshold":80,"type":1}],"total":1}
        """#.utf8)
        let rule = try #require(
            try JSONDecoder().decode(PerformanceAlarmRulePage.self, from: payload).rules.first
        )

        let draft = PerformanceAlarmRuleDraft(editing: rule)

        #expect(!draft.isCreation)
        #expect(draft.ruleID == "1_snmp.slice_0_1")
        #expect(draft.target == "snmp.slice")
        #expect(draft.severity == .critical)
    }
}
