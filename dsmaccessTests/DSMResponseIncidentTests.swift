import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMResponseIncidentTests {
    /// Ce que le signalement doit contenir pour être exploitable : l'emplacement et le
    /// nom des champs reçus. Et ce qu'il ne doit jamais contenir : leurs valeurs, un
    /// rapport ne devant faire sortir ni nom de fichier ni chemin du NAS.
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

    /// Le champ fautif et son chemin sont ce qui a manqué au signalement du 29/07/2026 :
    /// sans eux, « la réponse n'a pas pu être lue » n'indique rien à corriger.
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

    /// Une opération qui échoue en boucle ne doit pas empiler les alertes, et un
    /// incident écarté ne doit plus revenir : au lecteur d'écran, une alerte répétée
    /// rend l'app impossible à utiliser.
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
