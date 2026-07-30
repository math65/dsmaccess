import Foundation
import Testing

/// The app's language fallback rests on two invariants that are easy to break silently:
/// the development language must stay English (a system that is neither French nor English
/// gets English), and every catalog key must carry an explicit French entry, otherwise the
/// string leaks out in English to French-speaking users (French is no longer served by key
/// fallback now that an fr.lproj exists).
struct LocalizationCatalogTests {
    private static func loadCatalog() throws -> [String: [String: Any]] {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("dsmaccess/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try #require(root["strings"] as? [String: [String: Any]])
    }

    private static func stringUnit(
        _ entry: [String: Any], language: String
    ) -> [String: Any]? {
        let localizations = entry["localizations"] as? [String: Any]
        let localization = localizations?[language] as? [String: Any]
        return localization?["stringUnit"] as? [String: Any]
    }

    @Test("Chaque clé traduisible a des entrées française et anglaise complètes")
    func catalogCoversFrenchAndEnglish() throws {
        let strings = try Self.loadCatalog()
        var missing: [String] = []
        for (key, entry) in strings {
            if entry["shouldTranslate"] as? Bool == false { continue }
            for language in ["fr", "en"] {
                guard let unit = Self.stringUnit(entry, language: language),
                      unit["state"] as? String == "translated",
                      let value = unit["value"] as? String,
                      !value.isEmpty
                else {
                    missing.append("\(language) : \(key)")
                    continue
                }
            }
        }
        #expect(
            missing.isEmpty,
            "Entrées absentes ou non traduites : \(missing.sorted().joined(separator: " | "))"
        )
    }

    @Test("L'app se replie sur l'anglais et déclare le français")
    func bundleFallsBackToEnglish() {
        let bundle = Bundle.main
        #expect(bundle.developmentLocalization == "en")
        #expect(bundle.localizations.contains("fr"))
        #expect(bundle.localizations.contains("en"))
    }
}
