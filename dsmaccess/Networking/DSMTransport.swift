//
//  DSMTransport.swift
//  dsmaccess
//
//  Transport HTTP commun : découverte des routes, versionnement, session et décodage.
//

import Foundation

@MainActor
final class DSMTransport {
    typealias RequestData = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let infoAPI = DSMAPI("SYNO.API.Info", preferredVersion: 1)
    /// Point d'amorçage stable ; toutes les autres routes proviennent de cette découverte.
    private static let discoveryPath = "query.cgi"

    let endpoint: DSMEndpoint
    private let session: URLSession
    private let trustDelegate: ServerTrustDelegate?
    private let requestData: RequestData

    private(set) var capabilities = DSMCapabilities()
    private var sessionID: String?
    private var synoToken: String?

    init(endpoint: DSMEndpoint) {
        self.endpoint = endpoint
        let delegate = endpoint.useHTTPS ? ServerTrustDelegate(endpoint: endpoint) : nil
        trustDelegate = delegate

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.session = session
        requestData = { try await session.data(for: $0) }
    }

    init(
        endpoint: DSMEndpoint,
        session: URLSession,
        capabilities: DSMCapabilities
    ) {
        self.endpoint = endpoint
        self.session = session
        trustDelegate = nil
        self.capabilities = capabilities
        requestData = { try await session.data(for: $0) }
    }

    init(
        endpoint: DSMEndpoint,
        session: URLSession,
        capabilities: DSMCapabilities,
        requestData: @escaping RequestData
    ) {
        self.endpoint = endpoint
        self.session = session
        trustDelegate = nil
        self.capabilities = capabilities
        self.requestData = requestData
    }

    convenience init(endpoint: DSMEndpoint, session: URLSession) {
        self.init(endpoint: endpoint, session: session, capabilities: DSMCapabilities())
    }

    func establishSession(_ result: LoginResult) {
        sessionID = result.sid
        synoToken = result.synotoken
    }

    func clearSession() {
        sessionID = nil
        synoToken = nil
    }

    func approveServerCertificate(fingerprint: String) -> Bool {
        trustDelegate?.approve(fingerprint: fingerprint) == true
    }

    @discardableResult
    func discover(_ names: [String]) async throws -> [String: APIInfoEntry] {
        let requestedNames = names.isEmpty ? [Self.infoAPI.name] : names
        let parameters = [
            "api": Self.infoAPI.name,
            "version": "1",
            "method": "query",
            "query": requestedNames.joined(separator: ","),
        ]
        let response: DSMResponse<[String: APIInfoEntry]> = try await send(
            path: Self.discoveryPath,
            parameters: parameters,
            requestPolicy: .idempotent
        )
        guard response.success, let data = response.data else {
            throw error(from: response.error)
        }
        capabilities.merge(data)
        return data
    }

    @discardableResult
    func discoverAll() async throws -> DSMCapabilities {
        let parameters = [
            "api": Self.infoAPI.name,
            "version": "1",
            "method": "query",
            "query": "all",
        ]
        let response: DSMResponse<[String: APIInfoEntry]> = try await send(
            path: Self.discoveryPath,
            parameters: parameters,
            requestPolicy: .idempotent
        )
        guard response.success, let data = response.data else {
            throw error(from: response.error)
        }
        capabilities.merge(data)
        return capabilities
    }

    func response<Value: Decodable & Sendable>(
        api: DSMAPI,
        method: String,
        parameters: [String: DSMParameter] = [:],
        authenticated: Bool = true,
        httpMethod: DSMHTTPMethod = .get,
        requestPolicy: DSMRequestPolicy = .singleAttempt,
        as type: Value.Type
    ) async throws -> DSMResponse<Value> {
        let resolved = try await resolve(api)
        let query = try encodedParameters(
            resolved: resolved,
            method: method,
            parameters: parameters,
            authenticated: authenticated
        )
        return try await send(
            path: resolved.path,
            parameters: query,
            httpMethod: httpMethod,
            requestPolicy: requestPolicy
        )
    }

    /// Exécute une lecture idempotente, avec une seconde tentative après un timeout.
    func read<Value: Decodable & Sendable>(
        api: DSMAPI,
        method: String,
        parameters: [String: DSMParameter] = [:],
        authenticated: Bool = true,
        httpMethod: DSMHTTPMethod = .get,
        as type: Value.Type
    ) async throws -> Value {
        try await value(
            api: api,
            method: method,
            parameters: parameters,
            authenticated: authenticated,
            httpMethod: httpMethod,
            requestPolicy: .idempotent,
            as: type
        )
    }

    /// Exécute une requête qui renvoie une valeur sans nouvelle tentative automatique.
    func value<Value: Decodable & Sendable>(
        api: DSMAPI,
        method: String,
        parameters: [String: DSMParameter] = [:],
        authenticated: Bool = true,
        httpMethod: DSMHTTPMethod = .get,
        requestPolicy: DSMRequestPolicy = .singleAttempt,
        as type: Value.Type
    ) async throws -> Value {
        let response = try await response(
            api: api,
            method: method,
            parameters: parameters,
            authenticated: authenticated,
            httpMethod: httpMethod,
            requestPolicy: requestPolicy,
            as: type
        )
        guard response.success, let data = response.data else {
            throw error(from: response.error)
        }
        return data
    }

    func perform(
        api: DSMAPI,
        method: String,
        parameters: [String: DSMParameter] = [:],
        authenticated: Bool = true
    ) async throws {
        let response = try await response(
            api: api,
            method: method,
            parameters: parameters,
            authenticated: authenticated,
            as: EmptyData.self
        )
        guard response.success else {
            throw error(from: response.error)
        }
    }

    func resolvedAPI(_ api: DSMAPI) async throws -> ResolvedDSMAPI {
        try await resolve(api)
    }

    func makeURL(path: String, parameters: [String: String]) throws -> URL {
        var components = URLComponents()
        components.scheme = endpoint.scheme
        components.host = endpoint.host
        components.port = endpoint.port
        components.path = "/webapi/\(path)"
        if !parameters.isEmpty {
            components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw DSMError.invalidEndpoint
        }
        return url
    }

    func makeURL(
        api: DSMAPI,
        method: String,
        parameters: [String: DSMParameter] = [:],
        authenticated: Bool = true
    ) async throws -> URL {
        let resolved = try await resolve(api)
        let encoded = try encodedParameters(
            resolved: resolved,
            method: method,
            parameters: parameters,
            authenticated: authenticated
        )
        return try makeURL(path: resolved.path, parameters: encoded)
    }

    func multipartRoute(
        api: DSMAPI,
        method: String,
        parameters: [String: DSMParameter] = [:],
        authenticated: Bool = true
    ) async throws -> (url: URL, fields: [String: String]) {
        let resolved = try await resolve(api)
        let fields = try encodedParameters(
            resolved: resolved,
            method: method,
            parameters: parameters,
            authenticated: authenticated
        )
        return (try makeURL(path: resolved.path, parameters: [:]), fields)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await requestData(request)
        } catch let error as URLError {
            throw mappedNetworkError(error)
        }
    }

    func download(from url: URL) async throws -> (URL, URLResponse) {
        do {
            return try await session.download(from: url)
        } catch let error as URLError {
            throw mappedNetworkError(error)
        }
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.upload(for: request, fromFile: fileURL)
        } catch let error as URLError {
            throw mappedNetworkError(error)
        }
    }

    private func resolve(_ api: DSMAPI) async throws -> ResolvedDSMAPI {
        if capabilities.entry(for: api.name) == nil {
            _ = try await discover([api.name])
        }
        return try capabilities.resolve(api)
    }

    private func appendAuthentication(to parameters: inout [String: String]) throws {
        guard let sessionID else {
            throw DSMError.sessionExpired
        }
        parameters["_sid"] = sessionID
        if let synoToken, !synoToken.isEmpty {
            parameters["SynoToken"] = synoToken
        }
    }

    private func encodedParameters(
        resolved: ResolvedDSMAPI,
        method: String,
        parameters: [String: DSMParameter],
        authenticated: Bool
    ) throws -> [String: String] {
        var encoded = try parameters.mapValues { try $0.encoded(for: resolved.requestFormat) }
        encoded["api"] = resolved.name
        encoded["version"] = String(resolved.version)
        encoded["method"] = method
        if authenticated {
            try appendAuthentication(to: &encoded)
        }
        return encoded
    }

    private func send<Value: Decodable & Sendable>(
        path: String,
        parameters: [String: String],
        httpMethod: DSMHTTPMethod = .get,
        requestPolicy: DSMRequestPolicy
    ) async throws -> DSMResponse<Value> {
        let request = try makeRequest(
            path: path,
            parameters: parameters,
            httpMethod: httpMethod
        )
        do {
            return try await sendOnce(request)
        } catch let error as URLError
            where requestPolicy == .idempotent && error.code == .timedOut {
            try await Task.sleep(for: .milliseconds(500))
            do {
                return try await sendOnce(request)
            } catch let retryError as URLError {
                throw mappedNetworkError(retryError)
            }
        } catch let error as URLError {
            throw mappedNetworkError(error)
        }
    }

    private func makeRequest(
        path: String,
        parameters: [String: String],
        httpMethod: DSMHTTPMethod
    ) throws -> URLRequest {
        switch httpMethod {
        case .get:
            return URLRequest(url: try makeURL(path: path, parameters: parameters))
        case .post:
            var request = URLRequest(url: try makeURL(path: path, parameters: [:]))
            var body = URLComponents()
            body.queryItems = parameters
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let encodedBody = body.percentEncodedQuery?.data(using: .utf8) else {
                throw DSMError.invalidResponse
            }
            request.httpMethod = httpMethod.rawValue
            request.httpBody = encodedBody
            request.setValue(
                "application/x-www-form-urlencoded; charset=utf-8",
                forHTTPHeaderField: "Content-Type"
            )
            return request
        }
    }

    private func sendOnce<Value: Decodable & Sendable>(
        _ request: URLRequest
    ) async throws -> DSMResponse<Value> {
        let (data, response) = try await requestData(request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DSMError.invalidResponse
        }
        return try await Self.decodeResponse(Value.self, from: data)
    }

    @concurrent
    static func decodeResponse<Value: Decodable & Sendable>(
        _ type: Value.Type,
        from data: Data
    ) async throws -> sending DSMResponse<Value> {
        do {
            return try JSONDecoder().decode(DSMResponse<Value>.self, from: data)
        } catch {
            throw DSMError.decoding
        }
    }

    private func mappedNetworkError(_ error: URLError) -> DSMError {
        if let fingerprint = trustDelegate?.consumeRejectedFingerprint() {
            return .untrustedCertificate(fingerprint: fingerprint)
        }
        return error.code == .cancelled
            ? .cancelled
            : .network(error.localizedDescription)
    }

    func error(from body: DSMErrorBody?) -> DSMError {
        switch body?.code {
        case 105: .permissionDenied
        case 106, 107, 119: .sessionExpired
        case let code?: .apiError(code: code)
        case nil: .invalidResponse
        }
    }
}
