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

    /// SF Symbol names look exactly like catalog keys and start with the same word as one of
    /// the catalog domains. There are only these two in the whole app; a new one makes this
    /// test fail, and the fix is to add it here.
    private static let symbolNames: Set<String> = [
        "network.slash",
        "sidebar.left",
    ]

    /// A key the code uses but the catalog does not hold compiles, ships, and shows the key
    /// itself on screen — `common.column.url` was read out as a column header on 2026-08-02.
    /// The other test only checks the opposite direction, that present entries are complete.
    @Test("Chaque clé citée dans le code existe au catalogue")
    func codeOnlyUsesKnownKeys() throws {
        let strings = try Self.loadCatalog()
        let domains = Set(strings.keys.filter { $0.contains(".") }.map { $0.prefix(while: { $0 != "." }) })
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("dsmaccess")

        var unknown: [String] = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        for case let url as URL in try #require(files) where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                // Accessibility identifiers are named like keys but address the UI tests, not
                // the catalog.
                guard !line.contains("accessibilityIdentifier(") else { continue }
                for literal in Self.stringLiterals(in: String(line)) {
                    guard Self.looksLikeAKey(literal),
                          domains.contains(literal.prefix(while: { $0 != "." })),
                          !Self.symbolNames.contains(literal),
                          strings[literal] == nil
                    else { continue }
                    unknown.append("\(url.lastPathComponent) : \(literal)")
                }
            }
        }

        #expect(
            unknown.isEmpty,
            "Clés absentes du catalogue : \(unknown.sorted().joined(separator: " | "))"
        )
    }

    private static func stringLiterals(in source: String) -> [String] {
        var literals: [String] = []
        var current: String?
        var escaped = false
        for character in source {
            if var literal = current {
                if escaped {
                    escaped = false
                    current = nil
                    continue
                }
                switch character {
                case "\\": escaped = true; current = literal
                case "\"": literals.append(literal); current = nil
                case "\n": current = nil
                default: literal.append(character); current = literal
                }
            } else if character == "\"" {
                current = ""
            }
        }
        return literals
    }

    private static func looksLikeAKey(_ literal: String) -> Bool {
        guard literal.contains("."), let first = literal.first, first.isLowercase else { return false }
        return literal.allSatisfy { $0.isLowercase && $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }
            && !literal.hasPrefix(".") && !literal.hasSuffix(".")
    }

    @Test("L'app se replie sur l'anglais et déclare le français")
    func bundleFallsBackToEnglish() {
        let bundle = Bundle.main
        #expect(bundle.developmentLocalization == "en")
        #expect(bundle.localizations.contains("fr"))
        #expect(bundle.localizations.contains("en"))
    }
}
