//
//  dsmaccessUITests.swift
//  dsmaccessUITests
//
//  Vérifications du formulaire de connexion sans accès à un NAS réel.
//

import XCTest

final class dsmaccessUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = makeApplication(language: "fr", locale: "fr_FR")
        app.launch()
        XCTAssertTrue(app.staticTexts["login.title"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLoginFormSupportsKeyboardEntryAndValidatesPort() throws {
        let host = app.textFields["login.host"]
        let port = app.textFields["login.port"]
        let account = app.textFields["login.account"]
        let password = app.secureTextFields["login.password"]
        let submit = app.buttons["login.submit"]

        XCTAssertTrue(host.exists)
        XCTAssertTrue(port.exists)
        XCTAssertTrue(account.exists)
        XCTAssertTrue(password.exists)
        XCTAssertTrue(app.checkBoxes["login.https"].exists)
        XCTAssertTrue(app.checkBoxes["login.remember-password"].exists)

        host.click()
        host.typeText("nas.local")
        XCTAssertEqual(host.value as? String, "nas.local")

        account.click()
        account.typeText("tester")
        password.click()
        password.typeText("not-a-real-password")

        port.click()
        port.typeKey("a", modifierFlags: .command)
        port.typeText("0")
        XCTAssertTrue(app.staticTexts["login.port-error"].waitForExistence(timeout: 2))
        XCTAssertFalse(submit.isEnabled)

        port.typeKey("a", modifierFlags: .command)
        port.typeText("5001")
        XCTAssertFalse(app.staticTexts["login.port-error"].exists)
        XCTAssertTrue(submit.isEnabled)
    }

    @MainActor
    func testLoginScreenPassesAccessibilityAudit() throws {
        try performAccessibilityAudit()
    }

    @MainActor
    func testEnglishLoginLocalization() throws {
        app.terminate()
        app = makeApplication(language: "en", locale: "en_GB")
        app.launch()

        let title = app.staticTexts["login.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Connect to your NAS")
        XCTAssertEqual(app.buttons["login.submit"].label, "Connect")
    }

    @MainActor
    func testSettingsUsesAccessibleToolbarNavigation() throws {
        app.typeKey(",", modifierFlags: .command)

        let settingsPanes = app.descendants(matching: .any)["settings.panes"]
        let settingsToolbar = app.toolbars.firstMatch
        let announcementsPane = settingsToolbar.buttons["Annonces"]
        let sidebarPane = settingsToolbar.buttons["Barre latérale"]
        let nasPane = settingsToolbar.buttons["NAS"]

        XCTAssertTrue(settingsPanes.waitForExistence(timeout: 5))
        XCTAssertTrue(settingsToolbar.exists)
        XCTAssertTrue(announcementsPane.exists)
        XCTAssertTrue(sidebarPane.exists)
        XCTAssertTrue(nasPane.exists)

        sidebarPane.click()
        XCTAssertTrue(app.checkBoxes["Masquer automatiquement les fonctionnalités indisponibles sur le NAS connecté"].waitForExistence(timeout: 2))
        app.windows["DSM Access"].buttons["_XCUI:CloseWindow"].click()
        try performAccessibilityAudit()
    }

    private func makeApplication(language: String, locale: String) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-ApplePersistenceIgnoreState", "YES",
            "-NSQuitAlwaysKeepsWindows", "NO",
            "-lastHost", "",
            "-lastAccount", "",
            "-lastUseHTTPS", "YES",
            "-rememberPassword", "NO",
            "-queueAnnouncements", "YES",
            "-nasProfiles", "",
            "-selectedNASProfileID", ""
        ]
        return application
    }

    @MainActor
    private func performAccessibilityAudit() throws {
        try app.performAccessibilityAudit { issue in
            guard let element = issue.element,
                  element.identifier.isEmpty,
                  element.label.isEmpty else { return false }

            if issue.auditType == .sufficientElementDescription {
                // SwiftUI insère un groupe hôte anonyme autour du contenu de chaque fenêtre.
                // Ce groupe n'est pas ciblable ; ses descendants portent les libellés utiles.
                if element.elementType == .group {
                    return self.app.windows.allElementsBoundByIndex.contains { window in
                        window.frame == element.frame
                    }
                }

                // AppKit publie aussi une Touch Bar vide sur les Mac qui n'en disposent pas.
                return element.elementType == .touchBar
            }

            if issue.auditType == .parentChild, element.elementType == .group {
                // AppKit expose le glyphe interne du bouton plein écran comme un groupe distinct.
                return self.app.windows.allElementsBoundByIndex.contains { window in
                    window.frame.contains(element.frame)
                        && element.frame.maxY <= window.frame.minY + 30
                        && element.frame.width <= 16
                        && element.frame.height <= 16
                }
            }

            return false
        }
    }
}
