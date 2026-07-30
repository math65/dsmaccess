import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMResponseIncidentTests {
    /// What the report must contain to be usable: the location and the name of the received
    /// fields. And what it must never contain: their values, since a report must not let a
    /// filename or a NAS path out.
    @Test func describesTheReceivedFieldsWithoutTheirValues() throws {
        let response = Data(
            #"{"success":true,"data":{"has_folder":true,"links":[{"id":"link-9","path":"/Photos/anniversaire.jpg","url":"https://nas.example/s/x"}]}}"#.utf8
        )

        let fields = DSMResponseIncident.fields(in: response)

        #expect(fields == [
            "racine : data, success",
            "data : has_folder, links",
            "data.links[] : id, path, url",
        ])
        let joined = fields.joined()
        #expect(!joined.contains("anniversaire"))
        #expect(!joined.contains("nas.example"))
        #expect(!joined.contains("link-9"))
    }

    @Test func describesAnEmptyPayloadAndAnUnreadableOne() {
        #expect(DSMResponseIncident.fields(in: Data(#"{"success":true,"data":{}}"#.utf8)) == [
            "racine : data, success",
            "data : aucun champ",
        ])
        #expect(DSMResponseIncident.fields(in: Data("pas du json".utf8)).isEmpty)
    }

    /// The offending field and its path are what the 2026-07-29 report was missing: without
    /// them, "the response could not be read" points to nothing to fix.
    @Test func namesTheFieldAndPathThatFailedToDecode() throws {
        struct Payload: Decodable {
            let links: [Link]
            struct Link: Decodable { let error: Int }
        }
        let malformed = Data(#"{"links":[{"id":"link-9"}]}"#.utf8)

        var summary = ""
        do {
            _ = try JSONDecoder().decode(Payload.self, from: malformed)
        } catch {
            summary = DSMResponseIncident.summary(of: error)
        }

        #expect(summary.contains("error"))
        #expect(summary.contains("links"))
    }

    /// An operation that fails in a loop must not stack up alerts, and a dismissed incident
    /// must not come back: with a screen reader, a repeated alert makes the app impossible
    /// to use.
    @Test func proposesEachFailingCallOnlyOnce() {
        let incidents = DSMResponseIncidents()
        let sharing = DSMResponseIncident(
            api: "SYNO.FileStation.Sharing",
            method: "create",
            version: "3",
            receivedFields: ["data : links"],
            failure: "champ manquant : error"
        )

        incidents.record(sharing)
        incidents.record(sharing)
        #expect(incidents.pending != nil)

        incidents.ignorePending()
        #expect(incidents.pending == nil)

        incidents.record(sharing)
        #expect(incidents.pending == nil)
    }

    @Test func handsTheAcceptedIncidentToTheFormExactlyOnce() {
        let incidents = DSMResponseIncidents()
        incidents.record(
            DSMResponseIncident(
                api: "SYNO.FileStation.List",
                method: "list",
                version: "2",
                receivedFields: ["data : files"],
                failure: "type inattendu"
            )
        )

        incidents.acceptPending()

        #expect(incidents.pending == nil)
        #expect(incidents.consumeAccepted()?.api == "SYNO.FileStation.List")
        #expect(incidents.consumeAccepted() == nil)
    }
}
