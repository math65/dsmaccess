//
//  AccessibilityAuditTests.swift
//  dsmaccessUITests
//
//  Audit d'accessibilité de chaque module sur une session NAS réelle.
//  Opt-in : la suite standard doit rester exécutable sans NAS, cet audit
//  se lance avec TEST_RUNNER_AUDIT_LIVE_NAS=1 sur une machine dont le
//  profil enregistré permet la reconnexion automatique.
//

import XCTest

final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!

    private static let modules = [
        "Votre NAS",
        "Stockage",
        "Journaux et sécurité",
        "Fichiers",
        "Dossiers partagés",
        "Utilisateurs et groupes",
        "Services de fichiers",
        "Centre de paquets",
        "Panneau de configuration",
        "Conteneurs",
    ]

    @MainActor
    func testEveryModulePassesAccessibilityAudit() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["AUDIT_LIVE_NAS"] == "1",
            "Audit sur NAS réel : lancer avec TEST_RUNNER_AUDIT_LIVE_NAS=1."
        )
        continueAfterFailure = true

        app = XCUIApplication()
        app.launch()

        let sidebar = app.outlines.firstMatch
        XCTAssertTrue(
            sidebar.waitForExistence(timeout: 25),
            "Barre latérale introuvable — la session ne s'est pas reconnectée."
        )

        var audited = 0
        for module in Self.modules {
            let row = sidebar.staticTexts[module]
            guard row.waitForExistence(timeout: 3) else { continue }
            row.click()
            Thread.sleep(forTimeInterval: 3)
            audit(screen: module)
            audited += 1

            if module == "Centre de paquets" {
                let catalog = app.radioButtons["Catalogue officiel"]
                if catalog.waitForExistence(timeout: 3) {
                    catalog.click()
                    Thread.sleep(forTimeInterval: 3)
                    audit(screen: "Centre de paquets — Catalogue officiel")
                }
            }
        }
        XCTAssertGreaterThan(audited, 0, "Aucun module audité.")
    }

    @MainActor
    private func audit(screen: String) {
        var issues: [String] = []
        var warnings = 0
        do {
            try app.performAccessibilityAudit { [self] issue in
                if isKnownFalsePositive(issue) { return true }
                if issue.compactDescription == "Contrast nearly passed" {
                    warnings += 1
                    return true
                }
                issues.append(describe(issue))
                return true
            }
        } catch {
            issues.append("audit interrompu : \(error.localizedDescription)")
        }
        if warnings > 0 {
            print("AUDIT-AVERTISSEMENTS \(screen) : \(warnings) contraste(s) limite")
        }
        if !issues.isEmpty {
            XCTFail("\(screen) — \(issues.count) problème(s) : \(issues.joined(separator: " ; "))")
        }
    }

    @MainActor
    private func describe(_ issue: XCUIAccessibilityAuditIssue) -> String {
        guard let element = issue.element else {
            return "[\(issue.compactDescription)] élément inconnu"
        }
        let frame = element.frame.integral
        var parts = ["type=\(element.elementType.rawValue)"]
        if !element.label.isEmpty { parts.append("«\(element.label)»") }
        if let value = element.value as? String, !value.isEmpty {
            parts.append("valeur «\(value.prefix(40))»")
        }
        parts.append("(\(Int(frame.origin.x));\(Int(frame.origin.y)) \(Int(frame.width))×\(Int(frame.height)))")
        return "[\(issue.compactDescription)] " + parts.joined(separator: " ")
    }

    /// Exclusions raisonnées, dans l'esprit de l'audit de l'écran de connexion :
    /// les conteneurs anonymes générés par SwiftUI/AppKit (groupes hôtes, Touch
    /// Bar fantôme, « Parent/Child mismatch » sur groupe sans nom, connu pour
    /// être instable) et les boutons de menu, que l'audit croit inactionnables
    /// alors qu'ils s'ouvrent par AXShowMenu — le geste standard de VoiceOver.
    @MainActor
    private func isKnownFalsePositive(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard let element = issue.element else { return true }

        if issue.auditType == .action,
           element.elementType == .menuButton || element.elementType == .popUpButton {
            return true
        }

        guard element.identifier.isEmpty, element.label.isEmpty else { return false }

        if issue.auditType == .sufficientElementDescription {
            return element.elementType == .group || element.elementType == .touchBar
        }
        if issue.auditType == .parentChild {
            return element.elementType == .group
        }
        return false
    }
}
