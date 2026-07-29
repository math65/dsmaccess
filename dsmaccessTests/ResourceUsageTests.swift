import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct ResourceUsageTests {
    /// Réponse relevée sur le DS920+ en DSM 7.4 le 29/07/2026, réduite aux champs que
    /// l'app lit. Les valeurs sont celles du NAS : c'est ce qui garantit que le décodage
    /// suit le contrat réel et non une reconstitution.
    private let payload = Data(#"""
    {"cpu":{"15min_load":96,"1min_load":57,"5min_load":69,"device":"System",
      "other_load":4,"system_load":3,"user_load":1},
     "disk":{"disk":[{"device":"sata2","display_name":"Drive 4","read_access":55,
       "read_byte":879957,"type":"internal","utilization":14,"write_access":2,
       "write_byte":16384}],
      "total":{"device":"total","read_access":220,"read_byte":3555327,
       "utilization":13,"write_access":8,"write_byte":65536}},
     "memory":{"avail_real":144700,"real_usage":18,"swap_usage":3,"total_real":3856560},
     "network":[{"device":"total","rx":1024,"tx":2048}],
     "space":{"total":{"device":"total","read_access":208,"read_byte":3541674,
       "utilization":27,"write_access":0,"write_byte":0},
      "volume":[{"device":"dm-1","display_name":"volume1","read_access":208,
       "read_byte":3541674,"utilization":27,"write_access":0,"write_byte":0}]}}
    """#.utf8)

    /// DSM transmet les moyennes de charge multipliées par cent : son propre client web
    /// divise par 100 avant affichage. Les prendre pour des pourcentages afficherait
    /// « 96 % » là où la machine est à 0,96 de charge.
    @Test func readsLoadAveragesAsHundredthsNotPercentages() throws {
        let usage = try JSONDecoder().decode(ResourceUsage.self, from: payload)

        let cpu = try #require(usage.cpu)
        #expect(cpu.oneMinuteLoad == 0.57)
        #expect(cpu.fiveMinuteLoad == 0.69)
        #expect(cpu.fifteenMinuteLoad == 0.96)
        // Les charges instantanées, elles, sont bien des pourcentages.
        #expect(cpu.userLoad == 1)
        #expect(cpu.systemLoad == 3)
    }

    /// Disques et volumes partagent la même forme chez DSM, à ceci près que la liste
    /// s'appelle `disk` d'un côté et `volume` de l'autre, et que l'entrée cumulée est
    /// rangée à part sous `total`.
    @Test func readsDisksAndVolumesFromTheirTwoDifferentKeys() throws {
        let usage = try JSONDecoder().decode(ResourceUsage.self, from: payload)

        let disk = try #require(usage.disk?.devices.first)
        #expect(disk.name == "Drive 4")
        #expect(disk.type == "internal")
        #expect(disk.utilization == 14)
        #expect(disk.readBytesPerSecond == 879_957)
        #expect(usage.disk?.total?.device == "total")

        let volume = try #require(usage.space?.devices.first)
        #expect(volume.name == "volume1")
        #expect(volume.utilization == 27)
        // Un volume ne porte pas de type : le champ reste absent, sans faire échouer le tout.
        #expect(volume.type == nil)
    }

    /// Un NAS sans disque exposé, ou une version de DSM qui omettrait ces blocs, ne doit
    /// pas rendre tout l'écran des ressources illisible.
    @Test func survivesAResponseWithoutDisksOrVolumes() throws {
        let minimal = Data(#"{"cpu":{"user_load":2},"memory":{"real_usage":40}}"#.utf8)

        let usage = try JSONDecoder().decode(ResourceUsage.self, from: minimal)

        #expect(usage.cpu?.userLoad == 2)
        #expect(usage.cpu?.oneMinuteLoad == nil)
        #expect(usage.disk == nil)
        #expect(usage.space == nil)
    }
}
