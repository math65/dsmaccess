import Foundation
import Testing
@testable import dsmaccess

/// Enregistre les requêtes du client backend et rejoue des réponses préparées.
@MainActor
private final class BackendRequestRecorder {
    private(set) var requests: [URLRequest] = []
    private var results: [Result<(Data, URLResponse), Error>]

    init(results: [Result<(Data, URLResponse), Error>] = []) {
        self.results = results
    }

    func execute(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !results.isEmpty else {
            return Self.response(status: 200, json: #"{"ok": true}"#, for: request)
        }
        return try results.removeFirst().get()
    }

    static func response(status: Int, json: String, for request: URLRequest) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(json.utf8), response)
    }

    static func result(status: Int, json: String) -> Result<(Data, URLResponse), Error> {
        let url = URL(string: "https://mathieumartin.ovh")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return .success((Data(json.utf8), response))
    }
}

@Suite(.serialized)
@MainActor
struct AppBackendClientTests {
    private func makeClient(recorder: BackendRequestRecorder) -> AppBackendClient {
        AppBackendClient(secret: "secret-test", execute: recorder.execute)
    }

    @Test func buildsTheContactRequest() async throws {
        let recorder = BackendRequestRecorder()
        let client = makeClient(recorder: recorder)

        try await client.sendContact(email: "personne@example.com", type: .suggestion, message: "Bonjour")

        let request = try #require(recorder.requests.first)
        #expect(request.url?.path() == "/api/feedback/contact")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["app"] as? String == "dsmaccess")
        #expect(json["contact_type"] as? String == "suggestion")
        #expect(json["email"] as? String == "personne@example.com")
        #expect(json["message"] as? String == "Bonjour")
        #expect(json["app_version"] as? String != nil)
    }

    @Test func buildsTheMultipartReportWithOrderedSections() async throws {
        let recorder = BackendRequestRecorder()
        let client = makeClient(recorder: recorder)
        let sections = [
            AppBackendClient.ReportSection(title: "Application", rows: [
                .init(label: "Version", value: "1.1"),
                .init(label: "Build", value: "42"),
            ]),
            AppBackendClient.ReportSection(title: "Système", rows: [
                .init(label: "macOS", value: "14.5"),
            ]),
        ]

        try await client.sendReport(email: "personne@example.com", summary: "Ça plante", subjectHint: "Signalement", sections: sections)

        let request = try #require(recorder.requests.first)
        #expect(request.url?.path() == "/api/feedback/report")
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))

        // Extrait la partie JSON `report` du corps multipart.
        let body = try #require(request.httpBody)
        let text = try #require(String(data: body, encoding: .utf8))
        let jsonText = try #require(text.split(separator: "\r\n\r\n").dropFirst().first?.split(separator: "\r\n").first)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any])
        #expect(json["app"] as? String == "dsmaccess")
        #expect(json["summary"] as? String == "Ça plante")
        #expect(json["subject_hint"] as? String == "Signalement")

        let decoded = try #require(json["sections"] as? [[String: Any]])
        #expect(decoded.map { $0["title"] as? String } == ["Application", "Système"])
        #expect(decoded.allSatisfy { $0["type"] as? String == "kv" })
        let firstRows = try #require(decoded.first?["rows"] as? [[String: String]])
        #expect(firstRows == [["label": "Version", "value": "1.1"], ["label": "Build", "value": "42"]])
    }

    @Test func mapsServerErrorCodes() async throws {
        let cases: [(String, AppBackendClient.BackendError)] = [
            (#"{"ok": false, "error_code": "rate_limited"}"#, .rateLimited),
            (#"{"ok": false, "error_code": "validation_error"}"#, .validation),
            (#"{"ok": false, "error_code": "invalid_json"}"#, .validation),
            (#"{"ok": false, "error_code": "boom"}"#, .server),
            ("pas du JSON", .server),
        ]
        for (payload, expected) in cases {
            let recorder = BackendRequestRecorder(results: [BackendRequestRecorder.result(status: 429, json: payload)])
            let client = makeClient(recorder: recorder)
            await #expect(throws: expected) {
                try await client.sendContact(email: "a@b.fr", type: .question, message: "?")
            }
        }
    }

    @Test func mapsTransportFailuresAndMissingSecret() async {
        let failing = BackendRequestRecorder(results: [.failure(URLError(.notConnectedToInternet))])
        await #expect(throws: AppBackendClient.BackendError.network) {
            try await self.makeClient(recorder: failing).sendContact(email: "a@b.fr", type: .other, message: "…")
        }

        let recorder = BackendRequestRecorder()
        let unconfigured = AppBackendClient(secret: nil, execute: recorder.execute)
        await #expect(throws: AppBackendClient.BackendError.notConfigured) {
            try await unconfigured.sendContact(email: "a@b.fr", type: .other, message: "…")
        }
        #expect(recorder.requests.isEmpty)
    }

    @Test func decodesAnnouncementVariants() async throws {
        let withLink = #"{"ok": true, "announcement": {"id": "a1", "title": "Titre", "body": "Corps", "style": "info", "mode": "once", "link": {"label": "En savoir plus", "url": "https://example.com"}}}"#
        let recorder = BackendRequestRecorder(results: [BackendRequestRecorder.result(status: 200, json: withLink)])
        let announcement = try #require(try await makeClient(recorder: recorder).checkAnnouncement(installID: "i", language: "fr"))
        #expect(announcement.id == "a1")
        #expect(announcement.link?.url == "https://example.com")

        let withoutLink = #"{"ok": true, "announcement": {"id": "a2", "title": "T", "body": "B", "style": "warning", "mode": "every", "link": null}}"#
        let recorder2 = BackendRequestRecorder(results: [BackendRequestRecorder.result(status: 200, json: withoutLink)])
        let second = try #require(try await makeClient(recorder: recorder2).checkAnnouncement(installID: "i", language: "fr"))
        #expect(second.link == nil)
        #expect(second.mode == "every")

        let none = BackendRequestRecorder(results: [BackendRequestRecorder.result(status: 200, json: #"{"ok": true, "announcement": null}"#)])
        #expect(try await makeClient(recorder: none).checkAnnouncement(installID: "i", language: "fr") == nil)

        let refused = BackendRequestRecorder(results: [BackendRequestRecorder.result(status: 200, json: #"{"ok": false, "announcement": null}"#)])
        await #expect(throws: AppBackendClient.BackendError.server) {
            try await self.makeClient(recorder: refused).checkAnnouncement(installID: "i", language: "fr")
        }
    }

    @Test func installIDIsStableAcrossAccesses() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "appBackendInstallID")
        defer {
            if let previous {
                defaults.set(previous, forKey: "appBackendInstallID")
            } else {
                defaults.removeObject(forKey: "appBackendInstallID")
            }
        }

        defaults.removeObject(forKey: "appBackendInstallID")
        let first = Preferences.appBackendInstallID
        #expect(UUID(uuidString: first) != nil)
        #expect(Preferences.appBackendInstallID == first)
    }
}

@Suite(.serialized)
@MainActor
struct BackendAnnouncementCoordinatorTests {
    /// Sauvegarde puis restaure les clés UserDefaults touchées par le coordinateur.
    private func withCleanDefaults(_ body: () async throws -> Void) async rethrows {
        let defaults = UserDefaults.standard
        let keys = ["appBackendInstallID", "appBackendSeenAnnouncementIDs"]
        let previous = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in previous {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        try await body()
    }

    private func announcementJSON(id: String, mode: String) -> String {
        #"{"ok": true, "announcement": {"id": "\#(id)", "title": "T", "body": "B", "style": "info", "mode": "\#(mode)", "link": null}}"#
    }

    @Test func skipsAnAlreadySeenOnceAnnouncement() async throws {
        try await withCleanDefaults {
            Preferences.seenBackendAnnouncementIDs = ["a1"]
            let recorder = BackendRequestRecorder(results: [
                BackendRequestRecorder.result(status: 200, json: announcementJSON(id: "a1", mode: "once")),
            ])
            let coordinator = BackendAnnouncementCoordinator(
                client: AppBackendClient(secret: "secret-test", execute: recorder.execute)
            )

            await coordinator.checkAtLaunch()

            #expect(coordinator.pendingAnnouncement == nil)
            // Aucun ack : l'annonce n'a pas été présentée.
            #expect(recorder.requests.map { $0.url?.path() } == ["/api/announce/check"])
        }
    }

    @Test func presentsAFreshAnnouncementAndAcknowledgesAfterDisplay() async throws {
        try await withCleanDefaults {
            let recorder = BackendRequestRecorder(results: [
                BackendRequestRecorder.result(status: 200, json: announcementJSON(id: "a2", mode: "once")),
            ])
            let coordinator = BackendAnnouncementCoordinator(
                client: AppBackendClient(secret: "secret-test", execute: recorder.execute)
            )

            await coordinator.checkAtLaunch()
            let announcement = try #require(coordinator.pendingAnnouncement)
            #expect(recorder.requests.count == 1)

            coordinator.markPresented(announcement)
            #expect(coordinator.pendingAnnouncement == nil)
            #expect(Preferences.seenBackendAnnouncementIDs == ["a2"])
        }
    }

    @Test func representsAnEveryModeAnnouncement() async throws {
        try await withCleanDefaults {
            Preferences.seenBackendAnnouncementIDs = ["a3"]
            let recorder = BackendRequestRecorder(results: [
                BackendRequestRecorder.result(status: 200, json: announcementJSON(id: "a3", mode: "every")),
            ])
            let coordinator = BackendAnnouncementCoordinator(
                client: AppBackendClient(secret: "secret-test", execute: recorder.execute)
            )

            await coordinator.checkAtLaunch()

            #expect(coordinator.pendingAnnouncement != nil)
        }
    }
}

@Suite(.serialized)
@MainActor
struct FeedbackDiagnosticsTests {
    @Test func reportNeverContainsNASIdentifyingValues() throws {
        let defaults = UserDefaults.standard
        let keys = ["lastHost", "lastAccount", "nasProfiles"]
        let previous = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in previous {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        // Valeurs sentinelles : si une future section fuit l'hôte ou le compte,
        // elles apparaîtraient dans le JSON du rapport.
        Preferences.lastHost = "nas-sentinelle.example"
        Preferences.lastAccount = "compte-sentinelle"

        let sections = FeedbackDiagnostics.sections(sessionConnected: true, profileCount: 2, settings: AppSettings())
        let json = try #require(String(data: try JSONEncoder().encode(sections), encoding: .utf8))

        #expect(!json.contains("nas-sentinelle.example"))
        #expect(!json.contains("compte-sentinelle"))
        #expect(sections.map(\.title) == ["Application", "Système", "NAS", "Réglages"])
    }
}
