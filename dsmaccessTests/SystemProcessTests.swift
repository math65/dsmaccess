import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct SystemProcessTests {
    /// Formes relevées sur le DS920+ en DSM 7.4 le 29/07/2026. Les noms de comptes et de
    /// machines n'y figurent pas : seule la forme de la réponse est reprise du NAS.
    @Test func readsProcessesWithTheirMemoryInKibibytes() throws {
        let payload = Data(#"""
        {"process":[
          {"command":"openvpn","cpu":75,"mem":1444,"mem_shared":408,"pid":25115,"status":"R"},
          {"command":"synorelayd","cpu":5,"mem":10456,"mem_shared":8704,"pid":17769,"status":"R"}]}
        """#.utf8)

        let page = try JSONDecoder().decode(SystemProcessPage.self, from: payload)

        let first = try #require(page.process.first)
        #expect(first.name == "openvpn")
        #expect(first.cpuPercent == 75)
        #expect(first.memoryKiB == 1444)
        #expect(first.pid == 25115)
        #expect(first.status == "R")
        #expect(page.process.count == 2)
    }

    /// DSM n'écrit ni zéro ni `null` pour un groupe qu'il ne mesure pas : il envoie la
    /// chaîne « - ». Deux groupes sur vingt et un étaient dans ce cas. Décodée en zéro,
    /// elle ferait passer une absence de mesure pour un service au repos.
    @Test func readsADashAsAMissingMeasurementNotAsZero() throws {
        let payload = Data(#"""
        {"slices":[
          {"byte_read_per_sec":0,"byte_write_per_sec":0,"cpu_time":"-","cpu_utilization":"-",
           "memory":"-","name":"Sans mesure","name_i18n":"","process":[],"unit_name":"none.slice"}]}
        """#.utf8)

        let group = try #require(
            try JSONDecoder().decode(ProcessGroupPage.self, from: payload).slices.first
        )

        #expect(group.cpuPercent == nil)
        #expect(group.cpuTime == nil)
        #expect(group.memoryBytes == nil)
        // Le reste de la ligne survit : un champ non mesuré ne doit pas emporter le groupe.
        #expect(group.displayName == "Sans mesure")
        #expect(group.readBytesPerSecond == 0)
    }

    /// `name_i18n` est vide sur la moitié des groupes du NAS : sans repli, la moitié de la
    /// liste s'afficherait sans nom.
    @Test func fallsBackToTheRawNameWhenNoTranslationIsGiven() throws {
        let payload = Data(#"""
        {"slices":[
          {"cpu_time":218.77,"cpu_utilization":0,"memory":4033536,"name":"SNMP",
           "name_i18n":"","process":[{}],"unit_name":"snmp.slice",
           "byte_read_per_sec":0,"byte_write_per_sec":0},
          {"cpu_time":12.5,"cpu_utilization":1.5,"memory":41231872,"name":"PlexMediaServer",
           "name_i18n":"Plex Media Server","process":[{},{}],"unit_name":"plex.slice",
           "byte_read_per_sec":1024,"byte_write_per_sec":2048}]}
        """#.utf8)

        let groups = try JSONDecoder().decode(ProcessGroupPage.self, from: payload).slices

        #expect(groups[0].displayName == "SNMP")
        #expect(groups[0].memoryBytes == 4_033_536)
        #expect(groups[0].processCount == 1)
        // Quand DSM traduit, c'est sa traduction qui prime sur le nom technique.
        #expect(groups[1].displayName == "Plex Media Server")
        #expect(groups[1].processCount == 2)
        #expect(groups[1].cpuPercent == 1.5)
    }
}
