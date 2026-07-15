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

        // LoginView place explicitement le focus clavier initial sur l'hôte.
        app.typeText("nas.local")
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
        try app.performAccessibilityAudit()
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
    func testSettingsUsesAccessibleSidebarNavigation() throws {
        app.typeKey(",", modifierFlags: .command)

        let settingsSidebar = app.descendants(matching: .any)["settings.sidebar"]
        let announcementsPane = app.descendants(matching: .any)["settings.pane.announcements"]
        let sidebarPane = app.descendants(matching: .any)["settings.pane.sidebar"]
        let nasPane = app.descendants(matching: .any)["settings.pane.nas"]

        XCTAssertTrue(settingsSidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(announcementsPane.exists)
        XCTAssertTrue(sidebarPane.exists)
        XCTAssertTrue(nasPane.exists)

        sidebarPane.click()
        XCTAssertTrue(app.checkBoxes["Masquer automatiquement les fonctionnalités indisponibles sur le NAS connecté"].waitForExistence(timeout: 2))
        try app.performAccessibilityAudit()
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
}
