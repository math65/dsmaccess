import Foundation
import Testing
@testable import dsmaccess

@Suite(.serialized)
@MainActor
struct AppSettingsTests {
    @Test func queuesAnnouncementsByDefaultAndPersistsTheSetting() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: "queueAnnouncements")
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: "queueAnnouncements")
            } else {
                defaults.removeObject(forKey: "queueAnnouncements")
            }
        }

        defaults.removeObject(forKey: "queueAnnouncements")
        #expect(Preferences.queueAnnouncements)

        let settings = AppSettings()
        settings.queueAnnouncements = false
        #expect(!Preferences.queueAnnouncements)
    }

    @Test func reordersSidebarModulesWithinASection() {
        let previousOrder = Preferences.sidebarOrder
        defer { Preferences.sidebarOrder = previousOrder }
        Preferences.sidebarOrder = AppModule.allCases
        let settings = AppSettings()

        #expect(settings.moveSidebarModule(.storage, by: -1))

        let overview = settings.sidebarOrder.filter { $0.section == .overview }
        #expect(overview == [.storage, .systemInfo, .logsSecurity])
    }

    @Test func doesNotMoveSidebarModulesAcrossSections() {
        let previousOrder = Preferences.sidebarOrder
        defer { Preferences.sidebarOrder = previousOrder }
        Preferences.sidebarOrder = AppModule.allCases
        let settings = AppSettings()

        settings.moveSidebarModule(.systemInfo, before: .files)

        #expect(settings.sidebarOrder == AppModule.allCases)
    }

    @Test func restoresTheSelectedNASProfile() {
        let previousProfiles = Preferences.nasProfiles
        let previousSelection = Preferences.selectedNASProfileID
        let previousHost = Preferences.lastHost
        let previousPort = Preferences.lastPort
        let previousHTTPS = Preferences.lastUseHTTPS
        let previousAccount = Preferences.lastAccount
        let previousRememberPassword = Preferences.rememberPassword
        defer {
            Preferences.nasProfiles = previousProfiles
            Preferences.selectedNASProfileID = previousSelection
            Preferences.lastHost = previousHost
            Preferences.lastPort = previousPort
            Preferences.lastUseHTTPS = previousHTTPS
            Preferences.lastAccount = previousAccount
            Preferences.rememberPassword = previousRememberPassword
        }

        let profile = NASProfile(
            name: "Studio NAS",
            host: "studio-nas.local",
            port: 5_001,
            useHTTPS: true,
            account: "alex",
            remembersPassword: true
        )
        Preferences.nasProfiles = [profile]
        Preferences.selectedNASProfileID = profile.id

        let session = SessionStore()

        #expect(session.connectionProfile == profile)
        #expect(Preferences.lastHost == profile.host)
        #expect(Preferences.lastAccount == profile.account)
    }

    @Test func blankNASRequestDoesNotReuseThePreviousProfile() {
        let previousProfiles = Preferences.nasProfiles
        let previousSelection = Preferences.selectedNASProfileID
        let previousHost = Preferences.lastHost
        let previousPort = Preferences.lastPort
        let previousHTTPS = Preferences.lastUseHTTPS
        let previousAccount = Preferences.lastAccount
        let previousRememberPassword = Preferences.rememberPassword
        defer {
            Preferences.nasProfiles = previousProfiles
            Preferences.selectedNASProfileID = previousSelection
            Preferences.lastHost = previousHost
            Preferences.lastPort = previousPort
            Preferences.lastUseHTTPS = previousHTTPS
            Preferences.lastAccount = previousAccount
            Preferences.rememberPassword = previousRememberPassword
        }

        let profile = NASProfile(
            name: "NAS",
            host: "nas.local",
            port: 5_001,
            useHTTPS: true,
            account: "alex",
            remembersPassword: false
        )
        Preferences.nasProfiles = [profile]
        Preferences.selectedNASProfileID = profile.id
        let session = SessionStore()

        session.prepareNewNAS()

        #expect(session.connectionProfile == nil)
        #expect(Preferences.lastHost.isEmpty)
        #expect(Preferences.lastAccount.isEmpty)
    }
}
