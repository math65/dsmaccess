//
//  DSMTransport.swift
//  dsmaccess
//
//  Shared HTTP transport: route discovery, versioning, session and decoding.
//

import Foundation

@MainActor
final class DSMTransport {
    typealias RequestData = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias DownloadFile = @Sendable (URL) async throws -> (URL, URLResponse)
    typealias UploadFile = @Sendable (URLRequest, URL) async throws -> (Data, URLResponse)

    private static let infoAPI = DSMAPI("SYNO.API.Info", preferredVersion: 1)
    /// Stable bootstrap point; every other route comes out of this discovery.
    private static let discoveryPath = "query.cgi"

    let endpoint: DSMEndpoint
    private let session: URLSession
    private let trustDelegate: ServerTrustDelegate?
    private let requestData: RequestData
    private let downloadFile: DownloadFile
    private let uploadFile: UploadFile
    private let hasInjectedDownloadFile: Bool
    private let hasInjectedUploadFile: Bool

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
        downloadFile = { try await session.download(from: $0) }
        uploadFile = { try await session.upload(for: $0, fromFile: $1) }
        hasInjectedDownloadFile = false
        hasInjectedUploadFile = false
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
        downloadFile = { try await session.download(from: $0) }
        uploadFile = { try await session.upload(for: $0, fromFile: $1) }
        hasInjectedDownloadFile = false
        hasInjectedUploadFile = false
    }

    init(
        endpoint: DSMEndpoint,
        session: URLSession,
        capabilities: DSMCapabilities,
        requestData: @escaping RequestData,
        downloadFile: DownloadFile? = nil,
        uploadFile: UploadFile? = nil
    ) {
        self.endpoint = endpoint
        self.session = session
        trustDelegate = nil
        self.capabilities = capabilities
        self.requestData = requestData
        self.downloadFile = downloadFile ?? { try await session.download(from: $0) }
        self.uploadFile = uploadFile ?? { try await session.upload(for: $0, fromFile: $1) }
        hasInjectedDownloadFile = downloadFile != nil
        hasInjectedUploadFile = uploadFile != nil
    }

    convenience init(endpoint: DSMEndpoint, session: URLSession) {
        self.init(endpoint: endpoint, session: session, capabilities: DSMCapabilities())
    }

    func establishSession(_ result: LoginResult) {
        adoptSession(sid: result.sid, synoToken: result.synotoken)
    }

    /// Reinstates a session opened during a previous launch. The transport stays the only
    /// holder of the SID: nothing else in the app handles it.
    func adoptSession(sid: String, synoToken: String?) {
        sessionID = sid
        self.synoToken = synoToken
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
        timeoutInterval: TimeInterval? = nil,
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
            requestPolicy: requestPolicy,
            timeoutInterval: timeoutInterval
        )
    }

    /// Runs an idempotent read, with a second attempt after a timeout.
    func read<Value: Decodable & Sendable>(
        api: DSMAPI,
        method: String,
        parameters: [String: DSMParameter] = [:],
        authenticated: Bool = true,
        httpMethod: DSMHTTPMethod = .get,
        timeoutInterval: TimeInterval? = nil,
        as type: Value.Type
    ) async throws -> Value {
        try await value(
            api: api,
            method: method,
            parameters: parameters,
            authenticated: authenticated,
            httpMethod: httpMethod,
            requestPolicy: .idempotent,
            timeoutInterval: timeoutInterval,
            as: type
        )
    }

    /// Runs a request that returns a value, without any automatic retry.
    func value<Value: Decodable & Sendable>(
        api: DSMAPI,
        method: String,
        parameters: [String: DSMParameter] = [:],
        authenticated: Bool = true,
        httpMethod: DSMHTTPMethod = .get,
        requestPolicy: DSMRequestPolicy = .singleAttempt,
        timeoutInterval: TimeInterval? = nil,
        as type: Value.Type
    ) async throws -> Value {
        let response = try await response(
            api: api,
            method: method,
            parameters: parameters,
            authenticated: authenticated,
            httpMethod: httpMethod,
            requestPolicy: requestPolicy,
            timeoutInterval: timeoutInterval,
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
        authenticated: Bool = true,
        httpMethod: DSMHTTPMethod = .get,
        timeoutInterval: TimeInterval? = nil
    ) async throws {
        let response = try await response(
            api: api,
            method: method,
            parameters: parameters,
            authenticated: authenticated,
            httpMethod: httpMethod,
            timeoutInterval: timeoutInterval,
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

    /// Opens a WebSocket outside the `/webapi` tree: Container Manager's terminal service is
    /// served straight from `/docker/ws`. DSM's own client authenticates it with the session
    /// cookie its browser already holds, so the task carries the SID the same way — and the
    /// SID still leaves nothing else in the app to hold.
    ///
    /// The `Origin` header is not decoration: measured on DSM 7.4, the service refuses the
    /// handshake outright without it, and refuses it too when the address it names is not one
    /// the NAS knows as its own — a QuickConnect name is refused where the declared domain is
    /// accepted, same session, same request.
    func webSocketTask(path: String, host: String? = nil) throws -> URLSessionWebSocketTask {
        guard let sessionID else {
            throw DSMError.sessionExpired
        }
        // Lowercased, as a browser writes it: DSM compares the origin it is given to the
        // addresses it knows without folding the case, so `MY-NAS…` is not `my-nas…` to it.
        let host = (host ?? endpoint.host).lowercased()
        var components = URLComponents()
        components.scheme = endpoint.useHTTPS ? "wss" : "ws"
        components.host = host
        components.port = endpoint.port
        components.path = path
        guard let url = components.url else {
            throw DSMError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.setValue("id=\(sessionID)", forHTTPHeaderField: "Cookie")
        request.setValue(
            "\(endpoint.scheme)://\(host):\(endpoint.port)",
            forHTTPHeaderField: "Origin"
        )
        return session.webSocketTask(with: request)
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
            return try await downloadFile(url)
        } catch let error as URLError {
            throw mappedNetworkError(error)
        }
    }

    func download(
        from url: URL,
        timeoutInterval: TimeInterval? = nil,
        progress: @escaping DSMTransferProgressHandler
    ) async throws -> (URL, URLResponse) {
        if hasInjectedDownloadFile {
            let result = try await download(from: url)
            let size = try await MultipartBodyFile.fileSize(at: result.0)
            progress(DSMTransferProgress(completedBytes: size, totalBytes: size))
            return result
        }
        let delegate = DSMTransferDelegate(progress: progress)
        // The request's own value overrides the session's 20-second idle limit in both
        // directions (measured on macOS 26): this is the one place a caller can wait
        // longer for a server that prepares before sending its first byte.
        var request = URLRequest(url: url)
        if let timeoutInterval { request.timeoutInterval = timeoutInterval }
        do {
            let result = try await session.download(
                for: request,
                delegate: delegate
            )
            let size = try await MultipartBodyFile.fileSize(at: result.0)
            progress(DSMTransferProgress(completedBytes: size, totalBytes: size))
            return result
        } catch let error as URLError {
            throw mappedNetworkError(error)
        }
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, URLResponse) {
        do {
            return try await uploadFile(request, fileURL)
        } catch let error as URLError {
            throw mappedNetworkError(error)
        }
    }

    func upload(
        for request: URLRequest,
        fromFile fileURL: URL,
        progress: @escaping DSMTransferProgressHandler
    ) async throws -> (Data, URLResponse) {
        if hasInjectedUploadFile {
            let result = try await upload(for: request, fromFile: fileURL)
            let size = try await MultipartBodyFile.fileSize(at: fileURL)
            progress(DSMTransferProgress(completedBytes: size, totalBytes: size))
            return result
        }
        let delegate = DSMTransferDelegate(progress: progress)
        do {
            let result = try await session.upload(
                for: request,
                fromFile: fileURL,
                delegate: delegate
            )
            let size = try await MultipartBodyFile.fileSize(at: fileURL)
            progress(DSMTransferProgress(completedBytes: size, totalBytes: size))
            return result
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
        requestPolicy: DSMRequestPolicy,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> DSMResponse<Value> {
        let request = try makeRequest(
            path: path,
            parameters: parameters,
            httpMethod: httpMethod,
            timeoutInterval: timeoutInterval
        )
        do {
            return try await sendOnce(request, parameters: parameters)
        } catch let error as URLError
            where requestPolicy == .idempotent && error.code == .timedOut {
            try await Task.sleep(for: .milliseconds(500))
            do {
                return try await sendOnce(request, parameters: parameters)
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
        httpMethod: DSMHTTPMethod,
        timeoutInterval: TimeInterval?
    ) throws -> URLRequest {
        switch httpMethod {
        case .get:
            var request = URLRequest(url: try makeURL(path: path, parameters: parameters))
            if let timeoutInterval { request.timeoutInterval = timeoutInterval }
            return request
        case .post:
            var request = URLRequest(url: try makeURL(path: path, parameters: [:]))
            if let timeoutInterval { request.timeoutInterval = timeoutInterval }
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
        _ request: URLRequest,
        parameters: [String: String]
    ) async throws -> DSMResponse<Value> {
        let (data, response) = try await requestData(request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DSMError.invalidResponse
        }
        do {
            return try await Self.decodeResponse(Value.self, from: data)
        } catch DSMError.decoding(let detail) {
            // The only place that knows both the call sent and the response received:
            // without this trace, a user report does not say what to fix.
            DSMResponseIncidents.shared.record(
                DSMResponseIncident(
                    api: parameters["api"] ?? "inconnue",
                    method: parameters["method"] ?? "inconnue",
                    version: parameters["version"] ?? "inconnue",
                    receivedFields: DSMResponseIncident.fields(in: data),
                    failure: detail ?? "réponse illisible"
                )
            )
            throw DSMError.decoding(detail: detail)
        }
    }

    @concurrent
    static func decodeResponse<Value: Decodable & Sendable>(
        _ type: Value.Type,
        from data: Data
    ) async throws -> sending DSMResponse<Value> {
        do {
            return try JSONDecoder().decode(DSMResponse<Value>.self, from: data)
        } catch {
            guard let repaired = Self.replacingInvalidUTF8(in: data) else {
                throw DSMError.decoding(detail: DSMResponseIncident.summary(of: error))
            }
            do {
                return try JSONDecoder().decode(DSMResponse<Value>.self, from: repaired)
            } catch {
                throw DSMError.decoding(detail: DSMResponseIncident.summary(of: error))
            }
        }
    }

    /// A single file whose name stayed latin-1 encoded on the volume is enough to make the
    /// whole response unreadable: `JSONDecoder` requires valid UTF-8, where browsers replace
    /// the offending byte and display the rest. This fallback makes the same choice — better
    /// a replacement character in a name than an unreachable folder. Returns `nil` when the
    /// data is already valid, so as not to mask another error.
    nonisolated static func replacingInvalidUTF8(in data: Data) -> Data? {
        guard String(data: data, encoding: .utf8) == nil else { return nil }
        return Data(String(decoding: data, as: UTF8.self).utf8)
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
        if let body,
           let detail = body.errors?.first,
           let detailCode = detail.code {
            let item = detail.path ?? detail.name ?? detail.id
            // A detail that names no item and only repeats the envelope's code carries
            // nothing the code alone does not: keeping it would hide a code this mapping
            // knows how to translate behind an anonymous item failure.
            if item != nil || detailCode != body.code {
                return .itemOperationFailed(code: body.code, item: item, itemCode: detailCode)
            }
        }
        return switch body?.code {
        case 105: .permissionDenied
        case 106, 107, 119: .sessionExpired
        case let code?: .apiError(code: code)
        case nil: .invalidResponse
        }
    }
}
