//
//  dsmaccessUITests.swift
//  dsmaccessUITests
//
//  Checks on the login form without access to a real NAS.
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

        replaceText(in: host, with: "nas.local")
        XCTAssertEqual(host.value as? String, "nas.local")

        replaceText(in: account, with: "tester")
        password.click()
        password.typeKey("a", modifierFlags: .command)
        password.typeText("not-a-real-password")

        replaceText(in: port, with: "0")
        XCTAssertTrue(app.staticTexts["login.port-error"].waitForExistence(timeout: 2))
        XCTAssertFalse(submit.isEnabled)

        replaceText(in: port, with: "5001")
        XCTAssertEqual(port.value as? String, "5001")
        XCTAssertTrue(app.staticTexts["login.port-error"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(submit.isEnabled)
    }

    @MainActor
    func testLoginScreenPassesAccessibilityAudit() throws {
        try performAccessibilityAudit()
    }

    @MainActor
    func testQuickConnectFormSupportsKeyboardEntryAndAccessibility() throws {
        let connectionMethod = app.segmentedControls["login.connection-method"]
        XCTAssertTrue(connectionMethod.exists)
        connectionMethod.buttons["QuickConnect"].click()

        let quickConnectID = app.textFields["login.quickconnect-id"]
        let account = app.textFields["login.account"]
        let password = app.secureTextFields["login.password"]
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(quickConnectID.waitForExistence(timeout: 2))
        XCTAssertFalse(app.textFields["login.host"].exists)
        XCTAssertFalse(app.textFields["login.port"].exists)

        replaceText(in: quickConnectID, with: "my.nas")
        XCTAssertTrue(app.staticTexts["login.quickconnect-error"].waitForExistence(timeout: 2))

        replaceText(in: quickConnectID, with: "My-NAS")
        replaceText(in: account, with: "tester")
        password.click()
        password.typeText("not-a-real-password")

        XCTAssertTrue(app.staticTexts["login.quickconnect-error"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(submit.isEnabled)
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
    private func replaceText(in element: XCUIElement, with text: String) {
        element.click()
        element.typeKey("a", modifierFlags: .command)
        for character in text {
            element.typeKey(String(character), modifierFlags: [])
        }
    }

    @MainActor
    private func performAccessibilityAudit() throws {
        try app.performAccessibilityAudit { issue in
            guard let element = issue.element,
                  element.identifier.isEmpty,
                  element.label.isEmpty else { return false }

            if issue.auditType == .sufficientElementDescription {
                // SwiftUI inserts an anonymous host group around the content of every window.
                // That group cannot be targeted; its descendants carry the useful labels.
                if element.elementType == .group {
                    return self.app.windows.allElementsBoundByIndex.contains { window in
                        window.frame == element.frame
                    }
                }

                // AppKit also publishes an empty Touch Bar on Macs that do not have one.
                return element.elementType == .touchBar
            }

            if issue.auditType == .parentChild, element.elementType == .group {
                // AppKit exposes the inner glyph of the full-screen button as a separate group.
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
