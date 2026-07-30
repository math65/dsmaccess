//
//  AppBackendClient.swift
//  dsmaccess
//
//  HTTP client for the shared app backend (https://mathieumartin.ovh):
//  contact forms, error reports and launch announcements.
//  Full contract: app-backend repository, docs/API.md. Independent of the DSM
//  network, this client deliberately does not go through DSMTransport.
//
//  The Bearer secret is NOT versioned (public repository): it is read from
//  `AppBackendSecret.plist` (git-ignored, bundled automatically by the
//  synchronized group). Without that file the build succeeds, `isConfigured` is
//  `false` and the contact interface is hidden.
//

import Foundation

final class AppBackendClient {
    enum ContactType: String, CaseIterable, Identifiable {
        // The raw values are the `contact_type` values the server expects.
        case bug
        case suggestion
        case question
        case other

        var id: Self { self }

        var title: LocalizedStringResource {
            switch self {
            case .bug: "feedback.kind.problem"
            case .suggestion: "feedback.kind.suggestion"
            case .question: "feedback.kind.question"
            case .other: "feedback.kind.other"
            }
        }
    }

    enum BackendError: Error, Equatable {
        case notConfigured
        case network
        case rateLimited
        case validation
        case server

        var localizedMessage: String {
            switch self {
            case .notConfigured:
                String(localized: "common.error.messaging_unavailable")
            case .network:
                String(localized: "feedback.send.unreachable.error")
            case .rateLimited:
                String(localized: "feedback.send.rate_limited.error")
            case .validation:
                String(localized: "feedback.send.rejected.error")
            case .server:
                String(localized: "feedback.send.server.error")
            }
        }
    }

    /// A report section, in the backend's ordered table format (`type: "kv"`).
    /// Arrays preserve order at both levels (sections and rows).
    struct ReportSection: Encodable {
        struct Row: Encodable {
            let label: String
            let value: String
        }

        let title: String
        let rows: [Row]
        private let type = "kv"

        private enum CodingKeys: String, CodingKey {
            case title, type, rows
        }
    }

    struct Announcement: Decodable, Identifiable {
        let id: String
        let title: String
        let body: String
        let style: String
        let mode: String
        /// Optional secondary button; `label` arrives already localized by the server.
        let link: Link?

        struct Link: Decodable {
            let label: String
            let url: String
        }
    }

    static let appID = "dsmaccess"

    private static let baseURL = URL(string: "https://mathieumartin.ovh")!

    private static let bundledSecret: String? = {
        guard let url = Bundle.main.url(forResource: "AppBackendSecret", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let secret = plist["BearerSecret"] as? String,
              !secret.isEmpty else {
            return nil
        }
        return secret
    }()

    static var isConfigured: Bool {
        bundledSecret != nil
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "inconnue"
    }

    private let secret: String?
    private let execute: (URLRequest) async throws -> (Data, URLResponse)

    /// `secret` and `execute` are injectable for tests; by default the client uses
    /// the bundled secret and an ephemeral session (no cache, no cookies).
    init(secret: String? = AppBackendClient.bundledSecret,
         execute: ((URLRequest) async throws -> (Data, URLResponse))? = nil) {
        self.secret = secret
        if let execute {
            self.execute = execute
        } else {
            let session = URLSession(configuration: .ephemeral)
            self.execute = { try await session.data(for: $0) }
        }
    }

    // MARK: - Contact and report

    func sendContact(email: String, type: ContactType, message: String) async throws {
        struct Body: Encodable {
            let app: String
            let email: String
            let contactType: String
            let message: String
            let appVersion: String

            private enum CodingKeys: String, CodingKey {
                case app, email, message
                case contactType = "contact_type"
                case appVersion = "app_version"
            }
        }
        let body = Body(
            app: Self.appID,
            email: email,
            contactType: type.rawValue,
            message: message,
            appVersion: Self.appVersion
        )
        var request = try makeRequest(path: "/api/feedback/contact")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(body)
        try await perform(request)
    }

    func sendReport(email: String, summary: String, subjectHint: String, sections: [ReportSection]) async throws {
        struct Body: Encodable {
            let app: String
            let email: String
            let summary: String
            let subjectHint: String
            let sections: [ReportSection]

            private enum CodingKeys: String, CodingKey {
                case app, email, summary, sections
                case subjectHint = "subject_hint"
            }
        }
        let body = Body(
            app: Self.appID,
            email: email,
            summary: summary,
            subjectHint: subjectHint,
            sections: sections
        )
        let boundary = "dsmaccess-" + UUID().uuidString
        var request = try makeRequest(path: "/api/feedback/report")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(boundary: boundary, reportJSON: try encode(body))
        try await perform(request)
    }

    // MARK: - Announcements

    func checkAnnouncement(installID: String, language: String) async throws -> Announcement? {
        struct Body: Encodable {
            let app: String
            let installID: String
            let lang: String

            private enum CodingKeys: String, CodingKey {
                case app, lang
                case installID = "install_id"
            }
        }
        struct Response: Decodable {
            let ok: Bool
            let announcement: Announcement?
        }
        var request = try makeRequest(path: "/api/announce/check")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(Body(app: Self.appID, installID: installID, lang: language))

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await execute(request)
        } catch {
            throw BackendError.network
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data),
              decoded.ok else {
            throw BackendError.server
        }
        return decoded.announcement
    }

    /// Tells the backend that the announcement was actually displayed.
    /// Failure is ignored: at worst, the reach counter underestimates.
    func acknowledgeAnnouncement(installID: String, announcementID: String) async {
        await sendAnnouncementEvent(path: "/api/announce/ack", installID: installID, announcementID: announcementID)
    }

    /// Tells the backend that the user activated the announcement's link button.
    func reportAnnouncementClick(installID: String, announcementID: String) async {
        await sendAnnouncementEvent(path: "/api/announce/click", installID: installID, announcementID: announcementID)
    }

    private func sendAnnouncementEvent(path: String, installID: String, announcementID: String) async {
        struct Body: Encodable {
            let app: String
            let installID: String
            let id: String

            private enum CodingKeys: String, CodingKey {
                case app, id
                case installID = "install_id"
            }
        }
        guard var request = try? makeRequest(path: path),
              let data = try? encode(Body(app: Self.appID, installID: installID, id: announcementID)) else {
            return
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        _ = try? await execute(request)
    }

    // MARK: - Plumbing

    private struct APIResponse: Decodable {
        let ok: Bool
        let errorCode: String?

        private enum CodingKeys: String, CodingKey {
            case ok
            case errorCode = "error_code"
        }
    }

    private func makeRequest(path: String) throws -> URLRequest {
        guard let secret else {
            throw BackendError.notConfigured
        }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func encode(_ body: some Encodable) throws -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw BackendError.validation
        }
    }

    private func perform(_ request: URLRequest) async throws {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await execute(request)
        } catch {
            throw BackendError.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.network
        }
        guard http.statusCode != 200 else {
            return
        }
        // Outside 200, the server returns {ok: false, error_code: "..."}; an
        // unreadable body is treated as a server error.
        let decoded = try? JSONDecoder().decode(APIResponse.self, from: data)
        switch decoded?.errorCode {
        case "rate_limited":
            throw BackendError.rateLimited
        case "validation_error", "invalid_json":
            throw BackendError.validation
        default:
            throw BackendError.server
        }
    }

    private func multipartBody(boundary: String, reportJSON: Data) -> Data {
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"report\"\r\n")
        append("Content-Type: application/json\r\n\r\n")
        body.append(reportJSON)
        append("\r\n")
        append("--\(boundary)--\r\n")
        return body
    }
}
