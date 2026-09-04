//
//  QuickConnectResolver.swift
//  dsmaccess
//
//  Unauthenticated resolution of a QuickConnect ID into an HTTPS DSM route.
//

import CryptoKit
import Foundation

nonisolated struct QuickConnectRoute: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case smartDNS
        case relay
    }

    let endpoint: DSMEndpoint
    let kind: Kind
}

nonisolated enum QuickConnectError: Error, LocalizedError, Equatable {
    case invalidID
    case unknownID
    case nasUnavailable
    case serviceUnavailable
    case relayDisabled
    case secureRouteUnavailable
    case invalidResponse
    case server(code: Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidID:
            String(localized: "common.error.invalid_quickconnect_id")
        case .unknownID:
            String(localized: "quickconnect.error.id_not_found")
        case .nasUnavailable:
            String(localized: "quickconnect.error.nas_offline")
        case .serviceUnavailable:
            String(localized: "quickconnect.error.dsm_access_disabled")
        case .relayDisabled:
            String(localized: "quickconnect.error.relay_disabled")
        case .secureRouteUnavailable:
            String(localized: "quickconnect.error.no_https_route")
        case .invalidResponse:
            String(localized: "quickconnect.error.unverified_response")
        case .server(let code):
            String(localized: "quickconnect.error.refused", defaultValue: "QuickConnect refused the connection (code \(code.errorCodeText)).")
        case .network(let detail):
            String(localized: "quickconnect.error.unreachable", defaultValue: "Could not reach QuickConnect: \(detail)")
        }
    }
}

nonisolated struct QuickConnectResolver: Sendable {
    typealias RequestData = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let globalControlURL = URL(string: "https://global.quickconnect.to/Serv.php")!
    private static let defaultPingPath = "/webman/pingpong.cgi?action=cors&quickconnect=true"

    private let requestData: RequestData

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        requestData = { try await session.data(for: $0) }
    }

    init(requestData: @escaping RequestData) {
        self.requestData = requestData
    }

    func resolve(id proposedID: String) async throws -> QuickConnectRoute {
        let id = proposedID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValid(id: id) else {
            throw QuickConnectError.invalidID
        }

        let initialResponses = try await control(
            command: .getServerInfo,
            serverID: id,
            at: Self.globalControlURL
        )
        let initial = try validatedResponse(in: initialResponses)

        if let direct = try await firstReachableSmartDNSRoute(from: initial) {
            return direct
        }

        guard let environment = initial.environment,
              let controlURL = Self.controlURL(for: environment.controlHost) else {
            throw QuickConnectError.invalidResponse
        }
        let tunnelResponses = try await control(
            command: .requestTunnel,
            serverID: id,
            at: controlURL
        )
        let tunnel = try validatedResponse(in: tunnelResponses)
        // The relay host name comes from the response (`relay_dn`) when it is present; the
        // historical `alias.region.quickconnect.*` form remains the fallback. The internal
        // identifier (`server.serverID`, numeric) must never be used to build the host.
        guard let service = tunnel.service,
              let relayIP = service.relayIP,
              !relayIP.isEmpty,
              let relayPort = service.relayPort,
              (1...65_535).contains(relayPort),
              let tunnelEnvironment = tunnel.environment,
              let relayHost = service.relayDN.flatMap({
                  Self.isQuickConnectHost($0) ? $0 : nil
              }) ?? Self.relayHost(
                  serverID: id,
                  region: tunnelEnvironment.relayRegion,
                  controlHost: tunnelEnvironment.controlHost
              ) else {
            throw QuickConnectError.secureRouteUnavailable
        }

        let endpoint = DSMEndpoint(useHTTPS: true, host: relayHost, port: 443)
        guard try await verifies(endpoint: endpoint, response: tunnel) else {
            throw QuickConnectError.secureRouteUnavailable
        }
        return QuickConnectRoute(endpoint: endpoint, kind: .relay)
    }

    static func isValid(id: String) -> Bool {
        guard (1...63).contains(id.unicodeScalars.count),
              let first = id.unicodeScalars.first,
              first.isASCII,
              CharacterSet.letters.contains(first),
              let last = id.unicodeScalars.last,
              last.isASCII,
              CharacterSet.alphanumerics.contains(last) else {
            return false
        }
        return id.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-")
        }
    }

    private func control(
        command: QuickConnectControlCommand.Command,
        serverID: String,
        at url: URL
    ) async throws -> [QuickConnectControlResponse] {
        let payload = [
            QuickConnectControlCommand(
                command: command,
                stopWhenError: false,
                stopWhenSuccess: command == .requestTunnel,
                serverID: serverID
            ),
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)
        request.timeoutInterval = command == .requestTunnel ? 30 : 10
        // The web portal sends this JSON array with this historical Content-Type.
        request.setValue(
            "application/x-www-form-urlencoded; charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw QuickConnectError.invalidResponse
        }
        do {
            return try JSONDecoder().decode([QuickConnectControlResponse].self, from: data)
        } catch {
            throw QuickConnectError.invalidResponse
        }
    }

    private func validatedResponse(
        in responses: [QuickConnectControlResponse]
    ) throws -> QuickConnectControlResponse {
        // `server.serverID` is an internal numeric identifier, not the requested alias: the
        // link with the alias comes from the request itself, then from the pingpong check
        // (ezid = md5 of that internal identifier) on the selected route.
        if let response = responses.first(where: {
            $0.errno == 0
                && $0.server != nil
                && $0.service != nil
                && $0.environment != nil
        }) {
            return response
        }
        guard let response = responses.first else {
            throw QuickConnectError.invalidResponse
        }
        guard response.errno != 0 else {
            throw QuickConnectError.invalidResponse
        }
        if response.errno == 19 {
            throw QuickConnectError.relayDisabled
        }
        switch response.suberrno {
        case 0: throw QuickConnectError.nasUnavailable
        case 1: throw QuickConnectError.unknownID
        case 3: throw QuickConnectError.serviceUnavailable
        default: throw QuickConnectError.server(code: response.errno)
        }
    }

    private func firstReachableSmartDNSRoute(
        from response: QuickConnectControlResponse
    ) async throws -> QuickConnectRoute? {
        guard let service = response.service,
              let smartDNS = response.smartDNS else {
            return nil
        }
        let ports = Self.ports(for: service)
        var seenHosts = Set<String>()
        let hosts = (smartDNS.lan + smartDNS.lanIPv6 + [smartDNS.host].compactMap { $0 })
            .filter(Self.isQuickConnectHost)
            .filter { seenHosts.insert($0.lowercased()).inserted }
            .prefix(8)

        for host in hosts {
            for port in ports {
                try Task.checkCancellation()
                let endpoint = DSMEndpoint(useHTTPS: true, host: host, port: port)
                if try await verifies(endpoint: endpoint, response: response) {
                    return QuickConnectRoute(endpoint: endpoint, kind: .smartDNS)
                }
            }
        }
        return nil
    }

    private func verifies(
        endpoint: DSMEndpoint,
        response: QuickConnectControlResponse
    ) async throws -> Bool {
        // The internal identifier returned by QuickConnect is numeric: it does not follow the
        // shape rules of an alias, only those of a DNS label.
        guard let serverID = response.server?.serverID,
              Self.isDNSLabel(serverID),
              let url = Self.pingURL(endpoint: endpoint, response: response) else {
            throw QuickConnectError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, urlResponse) = try await requestData(request)
            guard let httpResponse = urlResponse as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  Self.hasSameOrigin(httpResponse.url, as: endpoint),
                  let ping = try? JSONDecoder().decode(QuickConnectPingResponse.self, from: data) else {
                return false
            }
            // pingpong ties the route to the requested ID without exposing DSM credentials.
            return ping.ezid.caseInsensitiveCompare(Self.md5(serverID)) == .orderedSame
        } catch {
            if DSMError.isCancellation(error) { throw error }
            return false
        }
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await requestData(request)
        } catch {
            if DSMError.isCancellation(error) { throw error }
            throw QuickConnectError.network(error.localizedDescription)
        }
    }

    private static func ports(for service: QuickConnectControlResponse.Service) -> [Int] {
        [service.port, service.externalPort]
            .filter { (1...65_535).contains($0) }
            .reduce(into: []) { ports, port in
                if !ports.contains(port) { ports.append(port) }
            }
    }

    private static func controlURL(for host: String) -> URL? {
        guard isQuickConnectHost(host) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/Serv.php"
        return components.url
    }

    private static func relayHost(
        serverID: String?,
        region: String,
        controlHost: String
    ) -> String? {
        guard let serverID,
              isValid(id: serverID),
              isDNSLabel(region) else { return nil }
        let suffix: String
        if controlHost.lowercased().hasSuffix(".quickconnect.to") {
            suffix = "to"
        } else if controlHost.lowercased().hasSuffix(".quickconnect.cn") {
            suffix = "cn"
        } else {
            return nil
        }
        return "\(serverID).\(region).quickconnect.\(suffix)"
    }

    private static func pingURL(
        endpoint: DSMEndpoint,
        response: QuickConnectControlResponse
    ) -> URL? {
        let rawPath = response.server?.pingpongPath ?? defaultPingPath
        guard rawPath.hasPrefix("/"),
              let pathComponents = URLComponents(string: rawPath),
              pathComponents.scheme == nil,
              pathComponents.host == nil else {
            return nil
        }
        var components = URLComponents()
        components.scheme = endpoint.scheme
        components.host = endpoint.host
        components.port = endpoint.port
        components.path = pathComponents.path
        components.queryItems = pathComponents.queryItems
        return components.url
    }

    private static func hasSameOrigin(_ url: URL?, as endpoint: DSMEndpoint) -> Bool {
        guard let url,
              url.scheme?.caseInsensitiveCompare(endpoint.scheme) == .orderedSame,
              url.host?.caseInsensitiveCompare(endpoint.host) == .orderedSame else {
            return false
        }
        let effectivePort = url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
        return effectivePort == endpoint.port
    }

    private static func isQuickConnectHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return normalized.hasSuffix(".quickconnect.to")
            || normalized.hasSuffix(".quickconnect.cn")
    }

    private static func isDNSLabel(_ value: String) -> Bool {
        guard (1...63).contains(value.unicodeScalars.count),
              let first = value.unicodeScalars.first,
              let last = value.unicodeScalars.last,
              first.isASCII,
              last.isASCII,
              first != "-",
              last != "-" else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-")
        }
    }

    private static func md5(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8))
            .map { byte in
                let hexadecimal = String(byte, radix: 16)
                return byte < 16 ? "0\(hexadecimal)" : hexadecimal
            }
            .joined()
    }
}
