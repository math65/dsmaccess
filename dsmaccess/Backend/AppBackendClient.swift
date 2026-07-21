//
//  AppBackendClient.swift
//  dsmaccess
//
//  Client HTTP du backend partagé des apps (https://mathieumartin.ovh) :
//  formulaires de contact, rapports d'erreur et annonces au lancement.
//  Contrat complet : dépôt app-backend, docs/API.md. Indépendant du réseau DSM,
//  ce client ne passe volontairement pas par DSMTransport.
//
//  Le secret Bearer n'est PAS versionné (dépôt public) : il est lu depuis
//  `AppBackendSecret.plist` (git-ignoré, embarqué automatiquement par le groupe
//  synchronisé). Sans ce fichier, le build réussit, `isConfigured` vaut `false`
//  et l'interface de contact est masquée.
//

import Foundation

final class AppBackendClient {
    enum ContactType: String, CaseIterable, Identifiable {
        // Les valeurs brutes sont les `contact_type` attendus côté serveur.
        case bug
        case suggestion
        case question
        case other

        var id: Self { self }

        var title: LocalizedStringResource {
            switch self {
            case .bug: "Signalement de problème"
            case .suggestion: "Suggestion"
            case .question: "Question"
            case .other: "Autre"
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
                String(localized: "L’envoi de messages n’est pas disponible dans cette version de l’app.")
            case .network:
                String(localized: "Impossible de joindre le serveur. Vérifiez votre connexion Internet, puis réessayez.")
            case .rateLimited:
                String(localized: "Trop de messages envoyés récemment. Réessayez dans une heure.")
            case .validation:
                String(localized: "Le message n’a pas pu être accepté. Vérifiez l’adresse e-mail et le contenu, puis réessayez.")
            case .server:
                String(localized: "Le serveur a rencontré une erreur. Réessayez plus tard.")
            }
        }
    }

    /// Une section du rapport, au format tableau ordonné du backend (`type: "kv"`).
    /// Les tableaux préservent l'ordre aux deux niveaux (sections et lignes).
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
        /// Bouton secondaire facultatif ; `label` arrive déjà localisé par le serveur.
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

    /// `secret` et `execute` sont injectables pour les tests ; par défaut le client
    /// utilise le secret embarqué et une session éphémère (sans cache ni cookies).
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

    // MARK: - Contact et rapport

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

    // MARK: - Annonces

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

    /// Signale au backend que l'annonce a réellement été affichée.
    /// L'échec est ignoré : au pire, le compteur de portée sous-estime.
    func acknowledgeAnnouncement(installID: String, announcementID: String) async {
        await sendAnnouncementEvent(path: "/api/announce/ack", installID: installID, announcementID: announcementID)
    }

    /// Signale au backend que l'utilisateur a activé le bouton lien de l'annonce.
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

    // MARK: - Plomberie

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
        // Hors 200, le serveur renvoie {ok: false, error_code: "..."} ; un corps
        // illisible est traité comme une erreur serveur.
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
