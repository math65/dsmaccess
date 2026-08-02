import Foundation
import Testing
@testable import dsmaccess

/// The users and groups tabs sort on these keys. A key that came back optional would leave its
/// column unsortable, and one that disagreed with the column's text would order the rows by
/// something the screen never shows.
@MainActor
struct DSMAccountSortingTests {
    /// DSM marks a disabled account through `expired`, not through a boolean. The state column
    /// sorts on the wording, so the two states have to come out as two distinct words.
    @Test func sortsAccountsOnTheStateItDisplays() throws {
        let active = try user(#"{"name":"testeur","expired":"normal"}"#)
        let disabled = try user(#"{"name":"ancien","expired":"now"}"#)

        #expect(active.statusDescription == active.sortableStatus)
        #expect(active.sortableStatus != disabled.sortableStatus)
        #expect(!active.sortableStatus.isEmpty)
    }

    /// An administrator must group with the other administrators rather than fall wherever the
    /// translation of "yes" happens to land in the alphabet.
    @Test func groupsAdministratorsTogether() throws {
        let admin = try user(#"{"name":"testeur","is_admin":true}"#)
        let regular = try user(#"{"name":"invite","is_admin":false}"#)

        #expect(admin.sortableAdministrator > regular.sortableAdministrator)
    }

    /// The e-mail, the description and the groups are all optional on DSM's side. Absent, they
    /// must sort as an empty string rather than keep their column from being sorted at all.
    @Test func sortsAnAccountThatCarriesNoOptionalField() throws {
        let bare = try user(#"{"name":"testeur"}"#)

        #expect(bare.sortableEmail.isEmpty)
        #expect(bare.sortableDescription.isEmpty)
        #expect(bare.sortableGroups.isEmpty)
    }

    /// The members column shows a count and sorts on it: sorting the joined names would put
    /// ten members before two.
    @Test func sortsGroupsOnTheirMemberCount() throws {
        let payload = #"{"name":"equipe","users":["a","b","c"]}"#
        let group = try JSONDecoder().decode(DSMGroup.self, from: Data(payload.utf8))

        #expect(group.sortableMemberCount == 3)
        #expect(group.sortableDescription.isEmpty)
    }

    private func user(_ json: String) throws -> DSMUser {
        try JSONDecoder().decode(DSMUser.self, from: Data(json.utf8))
    }
}
