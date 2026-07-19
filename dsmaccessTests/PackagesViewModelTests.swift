import Testing
@testable import dsmaccess

@MainActor
struct PackagesViewModelTests {
    @Test func comparesSynologyVersionsWithoutOfferingDowngrades() {
        #expect(PackagesViewModel.isVersion("1.4.5-1", newerThan: "1.4.4-2221"))
        #expect(!PackagesViewModel.isVersion("1.4.4-2221", newerThan: "1.4.4-2221"))
        #expect(!PackagesViewModel.isVersion("1.4.3-9999", newerThan: "1.4.4-1"))
        #expect(PackagesViewModel.isVersion("1.0.0", newerThan: "1.0.0-rc2"))
        #expect(PackagesViewModel.isVersion("1.0.0-rc10", newerThan: "1.0.0-rc2"))
        #expect(!PackagesViewModel.isVersion("1.0.0-beta2", newerThan: "1.0.0"))
        #expect(
            PackagesViewModel.isVersion(
                "7.2.2-72806 Update 3",
                newerThan: "7.2.2-72806 Update 2"
            )
        )
        #expect(
            PackagesViewModel.isVersion(
                "1.0.0-100000000000000000000",
                newerThan: "1.0.0-99999999999999999999"
            )
        )
    }
}
