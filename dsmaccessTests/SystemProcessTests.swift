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

    /// Deux échelles opposées pour la même grandeur, relevées le 30/07/2026 : la charge d'un
    /// processus est déjà un pourcentage, celle d'un groupe est une fraction. Le client web de
    /// DSM la nomme d'ailleurs `cpuFraction` et la multiplie par 100. Lue telle quelle, la
    /// colonne « Processeur » des services s'écrit « 0,0 % » sur toute sa hauteur, y compris
    /// pour un service qui consomme réellement.
    @Test func readsTheGroupCPUAsAFractionAndTheProcessCPUAsAPercentage() throws {
        let groupPayload = Data(#"""
        {"slices":[
          {"cpu_time":48.4,"cpu_utilization":0.012091898428053204,"memory":2048,
           "name":"Service de bureau","name_i18n":"","process":[{}],"unit_name":"desktop.slice",
           "byte_read_per_sec":0,"byte_write_per_sec":0},
          {"cpu_time":271.21,"cpu_utilization":0.001095290251916758,"memory":1024,
           "name":"SNMP","name_i18n":"","process":[{}],"unit_name":"snmp.slice",
           "byte_read_per_sec":0,"byte_write_per_sec":0}]}
        """#.utf8)
        let processPayload = Data(#"""
        {"process":[{"command":"synorelayd","cpu":10,"mem":14420,"mem_shared":0,"pid":1,"status":"R"}]}
        """#.utf8)

        let groups = try JSONDecoder().decode(ProcessGroupPage.self, from: groupPayload).slices
        let processes = try JSONDecoder().decode(SystemProcessPage.self, from: processPayload).process

        let desktop = try #require(groups.first?.cpuPercent)
        #expect(abs(desktop - 1.2091898428053204) < 0.000_001)
        let snmp = try #require(groups.last?.cpuPercent)
        #expect(abs(snmp - 0.1095290251916758) < 0.000_001)
        // Le processus, lui, n'est pas converti : 10 vaut bien 10 %.
        #expect(processes.first?.cpuPercent == 10)
    }

    /// Les deux formes réellement observées, et elles s'excluent : soit `name` porte un nom
    /// courant et `name_i18n` est vide, soit l'inverse — et alors `name_i18n` contient une
    /// clé du catalogue DSM, pas une traduction. Affichée telle quelle, cette clé donnerait
    /// « storage_pool:raid_process » au milieu de « SNMP » et « Plex Media Server ». Faute
    /// de pouvoir la résoudre, on la rend lisible : seule sa ponctuation change.
    @Test func namesAGroupFromWhicheverFieldTheNASFilledIn() throws {
        let payload = Data(#"""
        {"slices":[
          {"cpu_time":218.77,"cpu_utilization":0,"memory":4033536,"name":"SNMP",
           "name_i18n":"","process":[{}],"unit_name":"snmp.slice",
           "byte_read_per_sec":0,"byte_write_per_sec":0},
          {"cpu_time":1,"cpu_utilization":0,"memory":2048,"name":"",
           "name_i18n":"storage_pool:raid_process","process":[{},{}],"unit_name":"raid.slice",
           "byte_read_per_sec":0,"byte_write_per_sec":0},
          {"name":"","name_i18n":"service:desktop_service","unit_name":"d.slice","process":[]},
          {"name":"Plex Media Server","name_i18n":"","unit_name":"plex.slice","process":[]}]}
        """#.utf8)

        let groups = try JSONDecoder().decode(ProcessGroupPage.self, from: payload).slices

        #expect(groups[0].displayName == "SNMP")
        #expect(groups[0].id == "snmp.slice")
        #expect(groups[0].memoryBytes == 4_033_536)
        #expect(groups[0].processCount == 1)
        #expect(groups[1].displayName == "Raid process")
        #expect(groups[1].processCount == 2)
        #expect(groups[2].displayName == "Desktop service")
        // Un nom déjà présentable n'est pas touché.
        #expect(groups[3].displayName == "Plex Media Server")
    }
}
