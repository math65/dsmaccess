import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMPackageServiceTests {
    @Test func keepsOnlyCompleteOfficialCatalogUpdates() async throws {
        let response = Data(
            #"""
            {
              "success": true,
              "data": {
                "packages": [
                  {
                    "id": "ActiveBackup",
                    "version": "3.0.0-1",
                    "link": "https://downloads.synology.com/ActiveBackup.spk",
                    "md5": "0123456789abcdef0123456789ABCDEF",
                    "size": "2048",
                    "beta": "false",
                    "source": "syno",
                    "type": "0"
                  },
                  {
                    "id": "ActiveBackup",
                    "version": "3.0.0-1",
                    "link": "https://downloads.synology.com/ActiveBackup.spk",
                    "md5": "0123456789abcdef0123456789ABCDEF",
                    "size": "2048",
                    "beta": "false",
                    "source": "syno",
                    "type": "0"
                  },
                  {
                    "id": "ThirdParty",
                    "version": "2.0.0",
                    "link": "https://packages.example.com/ThirdParty.spk",
                    "md5": "0123456789abcdef0123456789abcdef",
                    "size": 1024,
                    "source": "other"
                  },
                  {
                    "id": "Insecure",
                    "version": "2.0.0",
                    "link": "http://downloads.synology.com/Insecure.spk",
                    "md5": "0123456789abcdef0123456789abcdef",
                    "size": 1024,
                    "source": "syno"
                  },
                  {
                    "id": "InvalidChecksum",
                    "version": "2.0.0",
                    "link": "https://downloads.synology.com/Invalid.spk",
                    "md5": "invalid",
                    "size": 1024,
                    "source": "syno"
                  }
                ]
              }
            }
            """#.utf8
        )
        let stub = DSMRequestStub(results: [.response(response), .response(response)])
        let service = makeService(stub: stub)

        let updates = try await service.availableUpdates()
        let refreshedCatalog = try await service.officialCatalog(forceRefresh: true)

        #expect(updates.count == 1)
        let update = try #require(updates["activebackup"])
        #expect(update.packageID == "ActiveBackup")
        #expect(update.version == "3.0.0-1")
        #expect(update.fileSize == 2048)
        #expect(!update.isBeta)
        #expect(update.packageType == 0)
        #expect(update.checksum == "0123456789abcdef0123456789abcdef")
        #expect(refreshedCatalog == [update])

        let requests = await stub.requests
        let cachedQuery = try query(from: requests[0])
        #expect(cachedQuery["blforcerefresh"] == "false")
        #expect(cachedQuery["blloadothers"] == "false")
        let refreshedQuery = try query(from: requests[1])
        #expect(refreshedQuery["blforcerefresh"] == "true")
        #expect(refreshedQuery["blloadothers"] == "false")
    }

    @Test func startsUpgradeOnceAndPollsUntilFinished() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"task_id":"42"}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"finished":"false"}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"finished":"true"}}"#.utf8)),
        ])
        let service = makeService(stub: stub, pollInterval: .zero, pollLimit: 2)
        let downloadURL = try #require(
            URL(string: "https://downloads.synology.com/ActiveBackup.spk")
        )
        let update = PackageUpdate(
            packageID: "ActiveBackup",
            version: "3.0.0-1",
            downloadURL: downloadURL,
            checksum: "0123456789abcdef0123456789abcdef",
            fileSize: 2048,
            isBeta: false,
            packageType: 0
        )

        var progressUpdates = [PackageOperationProgress]()
        try await service.upgrade(update) { progressUpdates.append($0) }

        let requests = await stub.requests
        #expect(requests.count == 3)
        #expect(
            progressUpdates
                == [
                    PackageOperationProgress(taskID: "42", statusChecks: 1, isFinished: false),
                    PackageOperationProgress(taskID: "42", statusChecks: 2, isFinished: true),
                ]
        )
        let startQuery = try query(from: requests[0])
        #expect(startQuery["method"] == "upgrade")
        #expect(startQuery["name"] == "ActiveBackup")
        #expect(startQuery["is_syno"] == "true")
        #expect(startQuery["url"] == update.downloadURL.absoluteString)
        #expect(startQuery["checksum"] == update.checksum)
        #expect(startQuery["filesize"] == "2048")
        #expect(startQuery["_sid"] == "session-id")

        let statusQuery = try query(from: requests[1])
        #expect(statusQuery["method"] == "status")
        #expect(statusQuery["task_id"] == "42")
        let finishedQuery = try query(from: requests[2])
        #expect(finishedQuery["method"] == "status")
        #expect(finishedQuery["task_id"] == "42")
    }

    @Test func reportsDiscoveredPackageCapabilitiesWithoutInferringMissingMutations() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"packages":[]}}"#.utf8)),
        ])
        let service = makeService(stub: stub, includesInstallation: false)

        let capabilities = service.capabilities()
        let updates = try await service.availableUpdates()

        #expect(capabilities.canBrowseCatalog)
        #expect(!capabilities.canInstallVerifiedUpdates)
        #expect(!capabilities.canControlPackages)
        #expect(!capabilities.canUninstallPackages)
        #expect(!capabilities.canManageSettings)
        #expect(capabilities.maximumVersions["SYNO.Core.Package.Server"] == 2)
        #expect(updates.isEmpty)
    }

    @Test func rejectsUnsafeUpdateMetadataBeforeSendingARequest() async throws {
        let stub = DSMRequestStub(results: [])
        let service = makeService(stub: stub)
        let downloadURL = try #require(
            URL(string: "http://downloads.synology.com/ActiveBackup.spk")
        )
        let update = PackageUpdate(
            packageID: "ActiveBackup",
            version: "3.0.0-1",
            downloadURL: downloadURL,
            checksum: "0123456789abcdef0123456789abcdef",
            fileSize: 2048,
            isBeta: false,
            packageType: 0
        )

        do {
            try await service.upgrade(update)
            Issue.record("Les métadonnées non sécurisées auraient dû être refusées.")
        } catch DSMError.invalidResponse {
        } catch {
            Issue.record("Erreur inattendue : \(error)")
        }

        #expect(await stub.requestCount == 0)
    }

    private func makeService(
        stub: DSMRequestStub,
        pollInterval: Duration = .milliseconds(1200),
        pollLimit: Int = 900,
        includesInstallation: Bool = true
    ) -> DSMPackageService {
        var capabilities = DSMCapabilities()
        var entries = [
            "SYNO.Core.Package.Server": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 2
            ),
        ]
        if includesInstallation {
            entries["SYNO.Core.Package.Installation"] = APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1
            )
        }
        capabilities.merge(entries)
        let transport = DSMTransport(
            endpoint: DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001),
            session: .shared,
            capabilities: capabilities,
            requestData: { try await stub.data(for: $0) }
        )
        transport.establishSession(
            LoginResult(sid: "session-id", did: nil, synotoken: nil)
        )
        return DSMPackageService(
            transport: transport,
            updatePollInterval: pollInterval,
            updatePollLimit: pollLimit
        )
    }

    private func query(from request: URLRequest) throws -> [String: String] {
        let url = try #require(request.url)
        let items = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }
}
