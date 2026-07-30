import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct PerformanceAlarmRuleTests {
    /// Charge utile telle que le DS920+ l'a renvoyée le 30/07/2026, après création de vraies
    /// règles. L'identifiant est une chaîne composite fabriquée par le NAS, et la cible arrive
    /// en double : sa valeur brute dans `service`, son libellé dans `name`.
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
        // `support_internal` arrive en nombre et non en booléen.
        #expect(!page.supportsInternalUse)

        let system = try #require(page.rules.first)
        #expect(system.id == "0_general_4_0")
        #expect(system.kind == .system)
        #expect(system.resource == .memory)
        #expect(system.severity == .warning)
        #expect(system.threshold == 1)
        // « general » est une constante du formulaire de DSM, pas une cible à montrer.
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

    /// Vérifié sur le NAS : `sshd.slice` ressort avec `name` valant une clé du catalogue DSM,
    /// que son client web résout et que nous ne pouvons pas résoudre. Affichée telle quelle,
    /// la règle se lirait « firewall:firewall_service_opt_ssh ».
    @Test func neverShowsADSMCatalogKeyAsATargetName() throws {
        let payload = Data(#"""
        {"rules":[{"enable":true,"hash":"","id":"1_sshd.slice_0_0",
          "name":"firewall:firewall_service_opt_ssh","resource":0,"service":"sshd.slice",
          "severity":0,"threshold":80,"type":1}],"support_internal":0,"total":1}
        """#.utf8)

        let rule = try #require(
            try JSONDecoder().decode(PerformanceAlarmRulePage.self, from: payload).rules.first
        )

        // Le nom d'unité reste parlant, une fois débarrassé de son suffixe systemd.
        #expect(rule.displayTarget == "sshd")
    }

    /// Sans identifiant, une règle ne peut être ni basculée ni supprimée : mieux vaut refuser
    /// la ligne que l'afficher avec des commandes qui échoueront.
    @Test func refusesARuleWithoutAnIdentifier() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                PerformanceAlarmRulePage.self,
                from: Data(#"{"rules":[{"enable":true,"type":0,"resource":0}],"total":1}"#.utf8)
            )
        }
    }

    /// Le même code de ressource ne désigne pas la même grandeur selon le type : `4` est un
    /// pourcentage de mémoire pour le système et un nombre de mégaoctets pour un service,
    /// `5` un débit pour un service et un pourcentage pour un volume.
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

    /// iSCSI et l'usage interne restent lisibles — une règle existante ne doit pas disparaître
    /// de la liste — mais ne sont pas proposés à la composition, faute d'avoir pu les éprouver.
    @Test func offersOnlyTheKindsItCanCompose() {
        #expect(PerformanceAlarmRule.Kind.editable == [.system, .service, .volume])
        #expect(!PerformanceAlarmRule.Kind.iSCSI.isEditable)
        #expect(!PerformanceAlarmRule.Kind.internalUse.isEditable)
        // Leur catalogue reste connu, pour décrire une règle que le NAS renverrait.
        #expect(!PerformanceAlarmRule.measures(for: .iSCSI).isEmpty)
    }

    /// DSM impose lui-même la cible de certains types : une règle système porte « general ».
    @Test func fillsTheTargetDSMImposes() {
        let system = PerformanceAlarmRuleDraft(kind: .system, target: "ignoré")
        let service = PerformanceAlarmRuleDraft(kind: .service, target: "snmp.slice")

        #expect(system.resolvedTarget == "general")
        #expect(service.resolvedTarget == "snmp.slice")
    }

    /// Modifier une règle reprend son identifiant : sans lui, le NAS créerait un doublon et
    /// refuserait, le quadruplet étant déjà pris.
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
