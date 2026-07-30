import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct ResourceMonitorLogTests {
    /// Le client web lit cette colonne avec « Y/n/j G:i:s » : mois, jour et heure ne sont pas
    /// complétés à deux chiffres. Un format rigide en « aaaa/MM/jj HH:mm:ss » rejetterait la
    /// moitié des horodatages et la colonne Date afficherait un tiret.
    @Test func readsATimestampWhoseComponentsAreNotPadded() throws {
        let payload = Data(#"""
        {"logs":[
          {"time":"2026/7/30 9:05:12","level":"Warning","event":"Utilisation du processeur supérieure à 80 %"},
          {"time":"2026/12/03 14:30:07","level":"Critical","event":"Utilisation de la mémoire supérieure à 90 %"}],
         "total":2}
        """#.utf8)

        let page = try JSONDecoder().decode(ResourceMonitorLogPage.self, from: payload)

        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 30
        components.hour = 9
        components.minute = 5
        components.second = 12
        #expect(page.entries.first?.recordedAt == Calendar.current.date(from: components))
        // La forme complétée reste lue : DSM emploie le même parseur pour les deux.
        #expect(page.entries.last?.recordedAt != nil)
    }

    /// Les niveaux arrivent en anglais et c'est le client qui traduit. Une valeur inconnue est
    /// conservée telle quelle plutôt que rangée d'office dans un niveau existant, qui
    /// afficherait une gravité que le NAS n'a pas envoyée.
    @Test func mapsTheThreeLevelsDSMSendsAndKeepsTheRest() throws {
        let payload = Data(#"""
        {"logs":[
          {"time":"2026/7/30 9:00:00","level":"Information","event":"a"},
          {"time":"2026/7/30 9:00:01","level":"Warning","event":"b"},
          {"time":"2026/7/30 9:00:02","level":"Critical","event":"c"},
          {"time":"2026/7/30 9:00:03","level":"Emergency","event":"d"}],
         "total":4}
        """#.utf8)

        let levels = try JSONDecoder().decode(ResourceMonitorLogPage.self, from: payload)
            .entries.map(\.level)

        #expect(levels == [.information, .warning, .critical, .other("emergency")])
    }

    /// La colonne Niveau se trie par gravité : classer « Critique » avant « Information »
    /// parce que C précède I n'aurait aucun sens à la lecture.
    @Test func sortsLevelsBySeverityAndNotAlphabetically() {
        let levels: [ResourceMonitorLogEntry.Level] = [.critical, .information, .warning]

        #expect(levels.sorted { $0.severity < $1.severity } == [.information, .warning, .critical])
    }

    /// Le NAS n'attribue aucun identifiant, et deux alertes identiques peuvent tomber dans la
    /// même seconde. Sans identité distincte, le tableau confondrait les lignes.
    @Test func distinguishesTwoIdenticalAlertsInTheSameSecond() throws {
        let payload = Data(#"""
        {"logs":[
          {"time":"2026/7/30 9:00:00","level":"Warning","event":"Charge du volume 1"},
          {"time":"2026/7/30 9:00:00","level":"Warning","event":"Charge du volume 1"}],
         "total":2}
        """#.utf8)

        let entries = try JSONDecoder().decode(ResourceMonitorLogPage.self, from: payload).entries

        #expect(entries.count == 2)
        #expect(entries[0].id != entries[1].id)
    }

    /// Le cas courant sur ce NAS : l'enregistrement est actif mais aucune règle d'alarme n'est
    /// définie, donc aucun seuil ne peut être franchi. La réponse est vide sans être en erreur.
    @Test func survivesAnEmptyJournal() throws {
        let page = try JSONDecoder().decode(
            ResourceMonitorLogPage.self, from: Data(#"{"logs":[],"total":0}"#.utf8)
        )

        #expect(page.entries.isEmpty)
        #expect(page.total == 0)
    }

    /// Le seul réglage que DSM expose. Il décide si le journal se remplit : le lire à faux
    /// quand il est vrai ferait présenter un NAS qui enregistre comme un NAS qui n'enregistre
    /// pas, et inversement.
    @Test func readsTheHistoryRecordingSetting() throws {
        let enabled = try JSONDecoder().decode(
            ResourceMonitorSetting.self, from: Data(#"{"enable_history":true}"#.utf8)
        )
        let disabled = try JSONDecoder().decode(
            ResourceMonitorSetting.self, from: Data(#"{"enable_history":false}"#.utf8)
        )

        #expect(enabled.historyEnabled)
        #expect(!disabled.historyEnabled)
    }

    /// Un réglage absent de la réponse n'est pas un réglage désactivé. Le décodage échoue
    /// plutôt que de laisser l'écran affirmer que l'enregistrement est coupé.
    @Test func refusesAResponseWithoutTheSetting() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ResourceMonitorSetting.self, from: Data(#"{}"#.utf8))
        }
    }
}
