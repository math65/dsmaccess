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
        let community = Data(
            #"""
            {
              "success": true,
              "data": {
                "packages": [
                  {
                    "id": "Adminer",
                    "version": "4.8.1-1",
                    "dname": "Adminer",
                    "desc": "Database management in a single file.",
                    "maintainer": "Piwi",
                    "link": "https://packages.synocommunity.com/Adminer.spk",
                    "md5": "0123456789abcdef0123456789abcdef",
                    "size": 481280,
                    "source": "others"
                  }
                ]
              }
            }
            """#.utf8
        )
        let stub = DSMRequestStub(results: [.response(response), .response(community)])
        let service = makeService(stub: stub)

        let catalog = try await service.catalog(forceRefresh: true)

        // The third-party entry carries neither type nor category, and DSM answers for it in
        // a second listing; both used to be discarded outright.
        #expect(catalog.packages.count == 2)
        let update = try #require(catalog.packages.first { $0.packageID == "ActiveBackup" })
        #expect(update.version == "3.0.0-1")
        #expect(update.fileSize == 2048)
        #expect(!update.isBeta)
        #expect(update.packageType == 0)
        #expect(update.origin == .synology)
        #expect(update.checksum == "0123456789abcdef0123456789abcdef")

        let thirdParty = try #require(catalog.packages.first { $0.packageID == "Adminer" })
        #expect(thirdParty.origin == .community)
        #expect(thirdParty.displayName == "Adminer")
        #expect(thirdParty.maintainer == "Piwi")
        #expect(thirdParty.packageType == 0)
        #expect(catalog.communityFailure == nil)

        let requests = await stub.requests
        #expect(requests.count == 2)
        let synologyQuery = try parameters(from: requests[0])
        #expect(synologyQuery["blforcerefresh"] == "true")
        #expect(synologyQuery["blloadothers"] == "false")
        let communityQuery = try parameters(from: requests[1])
        #expect(communityQuery["blforcerefresh"] == "true")
        #expect(communityQuery["blloadothers"] == "true")
    }

    /// A package source that cannot be reached must not empty the catalogue, and must not be
    /// swallowed either: DSM keeps its own listing and marks the community store as failed.
    @Test func keepsTheSynologyCatalogWhenAPackageSourceFails() async throws {
        let synology = Data(
            #"""
            {
              "success": true,
              "data": {
                "categories": [{"id": "utilities", "dname": "Utilitaires"}],
                "beta_packages": [
                  {
                    "id": "DSMAgent",
                    "version": "1.0.0-1",
                    "dname": "DSM Agent",
                    "link": "https://downloads.synology.com/DSMAgent.spk",
                    "md5": "0123456789abcdef0123456789abcdef",
                    "size": 4096,
                    "beta": true,
                    "source": "syno",
                    "type": 0
                  }
                ],
                "packages": [
                  {
                    "id": "PDFViewer",
                    "version": "1.3.1-1233",
                    "dname": "Visionneuse de PDF",
                    "desc": "Affiche des fichiers PDF.",
                    "maintainer": "Synology Inc.",
                    "category": ["utilities"],
                    "changelog": "Correction de sécurité.",
                    "link": "https://downloads.synology.com/PDFViewer.spk",
                    "md5": "0123456789abcdef0123456789abcdef",
                    "size": 768989,
                    "beta": false,
                    "source": "syno",
                    "type": 0
                  }
                ]
              }
            }
            """#.utf8
        )
        let stub = DSMRequestStub(results: [
            .response(synology),
            .response(Data(#"{"success":false,"error":{"code":407}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        let catalog = try await service.catalog()

        #expect(catalog.packages.count == 2)
        #expect(catalog.categories == [PackageCategory(id: "utilities", name: "Utilitaires")])
        #expect(catalog.communityFailure != nil)

        let viewer = try #require(catalog.packages.first { $0.packageID == "PDFViewer" })
        #expect(viewer.displayName == "Visionneuse de PDF")
        #expect(viewer.maintainer == "Synology Inc.")
        #expect(viewer.categories == ["utilities"])
        #expect(viewer.changelog == "Correction de sécurité.")

        // Beta packages arrive in their own array and used to be dropped entirely.
        let beta = try #require(catalog.packages.first { $0.packageID == "DSMAgent" })
        #expect(beta.isBeta)
        #expect(beta.origin == .synology)
    }

    /// DSM checks for a licence agreement before every catalogue installation. The app cannot
    /// display one, so a package that has one must stop before anything is downloaded rather
    /// than be installed on terms the user never saw.
    @Test func stopsBeforeInstallingAPackageThatCarriesALicenceAgreement() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"has_eula":true}}"#.utf8)),
        ])
        let service = makeService(stub: stub, includesEula: true)
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

        await #expect(throws: (any Error).self) {
            try await service.install(update, runsAfterInstall: true) { _ in }
        }

        let requests = await stub.requests
        #expect(requests.count == 2)
        let eula = try parameters(from: requests[1])
        #expect(eula["api"] == "SYNO.Core.Package.Eula")
        #expect(eula["method"] == "check")
        #expect(eula["package"] == "ActiveBackup")
    }

    /// The service is built without the EULA API here, which is also what proves the check is
    /// skipped rather than invented on a NAS that does not publish it: the request count stays
    /// exactly what DSM sends.
    @Test(arguments: [false, true])
    func completesTheDSM74CatalogInstallationPipeline(isUpgrade: Bool) async throws {
        let operationMethod = isUpgrade ? "upgrade" : "install"
        let installationStatus = isUpgrade ? "installed" : "non_installed"
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true}"#.utf8)),
            .response(Data(
                #"{"success":true,"data":{"broken_pkgs":[],"conflicted_pkgs":[],"non_exist_pkgs":[],"paused_pkgs":[],"replaced_pkgs":[],"queue":[{"pkg":"ActiveBackup","operation":"install","version":"3.0.0-1","beta":false}]}}"#.utf8
            )),
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"taskid":"download-42"}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"finished":"false"}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"finished":"true","success":true}}"#.utf8)),
            .response(Data(
                #"{"success":true,"data":{"filename":"/var/packages/@download/ActiveBackup.spk","id":"ActiveBackup","name":"Active Backup","version":"3.0.0-1","status":"\#(installationStatus)","install_type":"","install_on_cold_storage":false,"break_pkgs":{},"replace_pkgs":null}}"#.utf8
            )),
            .response(Data(
                #"{"success":true,"data":{"has_fail":false,"result":[{"api":"SYNO.Core.Package.Installation","method":"check","version":2,"success":true,"data":{}},{"api":"SYNO.Core.Package.Installation","method":"\#(operationMethod)","version":1,"success":true,"data":{"packageName":"ActiveBackup","worker_message":[]}},{"api":"SYNO.Core.Package","method":"get","version":1,"success":true,"data":{}}]}}"#.utf8
            )),
            .response(Data(#"{"success":true}"#.utf8)),
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
        if isUpgrade {
            try await service.upgrade(update) { progressUpdates.append($0) }
        } else {
            try await service.install(update, runsAfterInstall: true) {
                progressUpdates.append($0)
            }
        }

        let requests = await stub.requests
        #expect(requests.count == 9)
        #expect(
            progressUpdates
                == [
                    PackageOperationProgress(
                        taskID: "download-42",
                        statusChecks: 1,
                        isFinished: false
                    ),
                    PackageOperationProgress(
                        taskID: "download-42",
                        statusChecks: 2,
                        isFinished: true
                    ),
                ]
        )
        let feasibility = try parameters(from: requests[0])
        #expect(feasibility["method"] == "feasibility_check")
        #expect(feasibility["version"] == "1")
        #expect(feasibility["type"] == "install_check")
        #expect(try stringArray(from: feasibility["packages"]) == ["ActiveBackup"])

        let queue = try parameters(from: requests[1])
        #expect(queue["method"] == "get_queue")
        let queuedPackages = try objectArray(from: queue["pkgs"])
        #expect(queuedPackages.count == 1)
        #expect(queuedPackages[0]["pkg"] as? String == "ActiveBackup")
        #expect(queuedPackages[0]["operation"] as? String == "install")

        let check = try parameters(from: requests[2])
        #expect(check["method"] == "check")
        #expect(check["version"] == "2")
        #expect(check["blupgrade"] == String(isUpgrade))
        #expect(check["blCheckDep"] == "false")

        let startQuery = try parameters(from: requests[3])
        #expect(startQuery["method"] == operationMethod)
        #expect(startQuery["name"] == "ActiveBackup")
        #expect(startQuery["is_syno"] == "true")
        #expect(startQuery["beta"] == "false")
        #expect(startQuery["url"] == update.downloadURL.absoluteString)
        #expect(startQuery["checksum"] == update.checksum)
        #expect(startQuery["filesize"] == "2048")
        #expect(startQuery["operation"] == operationMethod)
        #expect(startQuery["_sid"] == "session-id")
        // DSM 7.4-90075 answers 119 to these mutations sent as POST: the whole flow stays GET.
        #expect(requests[3].httpMethod == "GET")

        let statusQuery = try parameters(from: requests[4])
        #expect(statusQuery["method"] == "status")
        #expect(statusQuery["task_id"] == "download-42")
        let finishedQuery = try parameters(from: requests[5])
        #expect(finishedQuery["method"] == "status")
        #expect(finishedQuery["task_id"] == "download-42")

        let downloadCheck = try parameters(from: requests[6])
        #expect(downloadCheck["api"] == "SYNO.Core.Package.Installation.Download")
        #expect(downloadCheck["method"] == "check")
        #expect(downloadCheck["taskid"] == "@SYNOPKG_DOWNLOAD_ActiveBackup")

        let compoundRequest = try parameters(from: requests[7])
        #expect(requests[7].httpMethod == "GET")
        #expect(compoundRequest["api"] == "SYNO.Entry.Request")
        #expect(compoundRequest["method"] == "request")
        #expect(compoundRequest["mode"] == "sequential")
        #expect(compoundRequest["stop_when_error"] == "true")
        let compound = try objectArray(from: compoundRequest["compound"])
        #expect(compound.count == 3)
        #expect(compound[0]["method"] as? String == "check")
        #expect(compound[1]["method"] as? String == operationMethod)
        #expect(compound[1]["path"] as? String == "/var/packages/@download/ActiveBackup.spk")
        #expect(compound[1]["force"] as? Bool == true)
        // DSM expects the string "{}"; a JSON object is refused with code 120.
        #expect(compound[1]["extra_values"] as? String == "{}")
        #expect(compound[2]["method"] as? String == "get")

        let cleanup = try parameters(from: requests[8])
        #expect(requests[8].httpMethod == "GET")
        #expect(cleanup["method"] == "delete")
        #expect(cleanup["path"] == "/var/packages/@download/ActiveBackup.spk")
    }

    @Test func acceptsAQueueEntryWithoutOperationField() async throws {
        // DSM 7.4-90075 returns get_queue entries reduced to pkg/beta/volume.
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true}"#.utf8)),
            .response(Data(
                #"{"success":true,"data":{"broken_pkgs":[],"conflicted_pkgs":[],"non_exist_pkgs":[],"paused_pkgs":[],"replaced_pkgs":[],"queue":[{"pkg":"ActiveBackup","beta":false,"volume":""}]}}"#.utf8
            )),
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"taskid":"download-42"}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"finished":"true","success":true}}"#.utf8)),
            .response(Data(
                #"{"success":true,"data":{"filename":"/var/packages/@download/ActiveBackup.spk","id":"ActiveBackup","name":"Active Backup","version":"3.0.0-1","status":"non_installed","install_type":"","install_on_cold_storage":false,"break_pkgs":{},"replace_pkgs":null}}"#.utf8
            )),
            .response(Data(
                #"{"success":true,"data":{"has_fail":false,"result":[{"api":"SYNO.Core.Package.Installation","method":"check","version":2,"success":true,"data":{}},{"api":"SYNO.Core.Package.Installation","method":"install","version":1,"success":true,"data":{"packageName":"ActiveBackup","worker_message":[]}},{"api":"SYNO.Core.Package","method":"get","version":1,"success":true,"data":{}}]}}"#.utf8
            )),
            .response(Data(#"{"success":true}"#.utf8)),
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

        try await service.install(update, runsAfterInstall: true) { _ in }

        #expect(await stub.requestCount == 8)
    }

    @Test func uploadsAndInstallsAManualSPKWithoutImplicitWizardChoices() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"task_id":"upload-7","filename":"Perl.spk","id":"Perl","name":"Perl","version":"5.34.1-0301","status":"non_installed","install_type":"","install_on_cold_storage":false,"break_pkgs":{},"replace_pkgs":null,"licence":"","install_pages":null}}"#.utf8
            )),
            .response(Data(#"{"success":true}"#.utf8)),
            .response(Data(
                #"{"success":true,"data":{"has_fail":false,"result":[{"success":true},{"success":true},{"success":true}]}}"#.utf8
            )),
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub)
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "dsmaccess-manual-package-\(UUID().uuidString).spk")
        try Data("test-spk-contents".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var transferProgress = [DSMTransferProgress]()
        let installedName = try await service.installManualPackage(at: fileURL) {
            transferProgress.append($0)
        }

        #expect(installedName == "Perl")
        #expect(transferProgress.last?.completedBytes ?? 0 > 0)
        let requests = await stub.requests
        #expect(requests.count == 4)
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].value(forHTTPHeaderField: "Content-Type")?.hasPrefix(
            "multipart/form-data; boundary="
        ) == true)
        // DSM 7.4 requires api/method/version in the upload URL query, not in the body.
        let uploadURL = try #require(requests[0].url)
        let uploadQuery = try #require(
            URLComponents(url: uploadURL, resolvingAgainstBaseURL: false)?.queryItems
        )
        #expect(uploadQuery.contains(URLQueryItem(name: "api", value: "SYNO.Core.Package.Installation")))
        #expect(uploadQuery.contains(URLQueryItem(name: "method", value: "upload")))
        #expect(uploadQuery.contains { $0.name == "version" })
        let uploadedBody = try #require(await stub.uploadedBodies.first)
        let uploadedText = try #require(String(data: uploadedBody, encoding: .utf8))
        #expect(uploadedText.contains("name=\"additional\""))
        #expect(uploadedText.contains("name=\"file\""))
        #expect(uploadedText.contains("test-spk-contents"))
        #expect(!uploadedText.contains("name=\"api\""))
        #expect(!uploadedText.contains("name=\"method\""))

        let feasibility = try parameters(from: requests[1])
        #expect(feasibility["method"] == "feasibility_check")
        #expect(try stringArray(from: feasibility["packages"]) == ["Perl"])

        let compoundRequest = try parameters(from: requests[2])
        let compound = try objectArray(from: compoundRequest["compound"])
        #expect(compound[0]["blCheckDep"] as? Bool == true)
        #expect(compound[1]["method"] as? String == "install")
        #expect(compound[1]["task_id"] as? String == "upload-7")
        #expect(compound[1]["check_codesign"] as? Bool == false)
        #expect(compound[1]["force"] as? Bool == false)

        let cleanup = try parameters(from: requests[3])
        #expect(cleanup["method"] == "clean")
        #expect(cleanup["task_id"] == "upload-7")
    }

    @Test func cleansAnUploadWithoutInstallingWhenDSMReturnsACustomWizard() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"task_id":"upload-8","id":"WizardPackage","name":"Wizard Package","status":"non_installed","licence":{"title":"Terms"},"install_pages":[{"step":"configuration"}]}}"#.utf8
            )),
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub)
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "dsmaccess-wizard-package-\(UUID().uuidString).spk")
        try Data("test-spk-contents".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try await service.installManualPackage(at: fileURL)
            Issue.record("Un paquet exigeant un assistant DSM aurait dû être refusé.")
        } catch DSMError.packageCenter(let message) {
            #expect(message.contains("Wizard Package"))
        } catch {
            Issue.record("Erreur inattendue : \(error)")
        }

        let requests = await stub.requests
        #expect(requests.count == 2)
        let cleanup = try parameters(from: requests[1])
        #expect(cleanup["method"] == "clean")
        #expect(cleanup["task_id"] == "upload-8")
    }

    @Test func managesHTTPSPackageSourcesUsingTheVerifiedFeedContract() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"items":[{"name":"Community","feed":"https://packages.example.com"}]}}"#.utf8
            )),
            .response(Data(#"{"success":true}"#.utf8)),
            .response(Data(#"{"success":true}"#.utf8)),
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        let sources = try await service.packageSources()
        try await service.addPackageSource(
            PackageSource(name: "Backup", feed: "https://backup.example.com")
        )
        try await service.updatePackageSource(
            PackageSource(name: "Community packages", feed: "https://packages.example.com/v2"),
            originalFeed: "https://packages.example.com"
        )
        try await service.deletePackageSources(feeds: ["https://backup.example.com"])

        #expect(sources == [PackageSource(name: "Community", feed: "https://packages.example.com")])
        let requests = await stub.requests
        #expect(requests.count == 4)
        let add = try parameters(from: requests[1])
        #expect(add["method"] == "add")
        let addEntry = try object(from: add["list"])
        #expect(addEntry["name"] as? String == "Backup")
        #expect(addEntry["feed"] as? String == "https://backup.example.com")

        let update = try parameters(from: requests[2])
        #expect(update["method"] == "set")
        let updateEntry = try object(from: update["list"])
        #expect(updateEntry["orifeed"] as? String == "https://packages.example.com")
        #expect(updateEntry["feed"] as? String == "https://packages.example.com/v2")

        let deletion = try parameters(from: requests[3])
        #expect(deletion["method"] == "delete")
        #expect(try stringArray(from: deletion["list"]) == ["https://backup.example.com"])
    }

    @Test func sendsDirectPackageMutationsOnceUsingGET() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true}"#.utf8)),
            .response(Data(#"{"success":true}"#.utf8)),
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub, includesDirectMutations: true)
        let settings = try JSONDecoder().decode(
            PackageSettings.self,
            from: Data(
                #"{"enable_autoupdate":true,"autoupdateall":false,"autoupdateimportant":true,"enable_dsm":true,"enable_email":false,"update_channel":false}"#.utf8
            )
        )

        try await service.setRunning(true, packageID: "Perl")
        try await service.uninstall(
            packageID: "Perl",
            dsmApps: "SYNO.SDS.Perl.Application SYNO.SDS.Perl.MainWindow"
        )
        try await service.setSettings(settings)

        let requests = await stub.requests
        #expect(requests.count == 3)
        #expect(requests.allSatisfy { $0.httpMethod == "GET" })

        let control = try parameters(from: requests[0])
        #expect(control["method"] == "start")
        #expect(control["id"] == "Perl")

        // DSM removes the desktop entries only when it is handed the identifiers back.
        let uninstall = try parameters(from: requests[1])
        #expect(uninstall["method"] == "uninstall")
        #expect(uninstall["id"] == "Perl")
        #expect(uninstall["dsm_apps"] == "SYNO.SDS.Perl.Application SYNO.SDS.Perl.MainWindow")

        // The web client sends these six fields and no others.
        let setting = try parameters(from: requests[2])
        #expect(setting["method"] == "set")
        #expect(setting["update_channel"] == "stable")
        #expect(setting["enable_autoupdate"] == "true")
        #expect(setting["autoupdateall"] == "false")
        #expect(setting["autoupdateimportant"] == "true")
        #expect(setting["enable_dsm"] == "true")
        #expect(setting["enable_email"] == "false")
        #expect(setting["default_vol"] == nil)
        #expect(setting["trust_level"] == nil)
    }

    @Test func reportsDiscoveredPackageCapabilitiesWithoutInferringMissingMutations() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"packages":[]}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"packages":[]}}"#.utf8)),
        ])
        let service = makeService(stub: stub, includesInstallation: false)

        let capabilities = service.capabilities()
        let catalog = try await service.catalog()

        #expect(capabilities.canBrowseCatalog)
        #expect(!capabilities.canInstallCatalogPackages)
        #expect(!capabilities.canInstallManualPackages)
        #expect(!capabilities.canInstallVerifiedUpdates)
        #expect(!capabilities.canRepairPackages)
        #expect(!capabilities.canControlPackages)
        #expect(!capabilities.canUninstallPackages)
        #expect(!capabilities.canManageSettings)
        #expect(capabilities.maximumVersions["SYNO.Core.Package.Server"] == 2)
        #expect(catalog.packages.isEmpty)
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
        includesInstallation: Bool = true,
        includesDirectMutations: Bool = false,
        includesEula: Bool = false
    ) -> DSMPackageService {
        var capabilities = DSMCapabilities()
        var entries = [
            "SYNO.Core.Package": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 2
            ),
            "SYNO.Core.Package.Server": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 2
            ),
        ]
        if includesEula {
            entries["SYNO.Core.Package.Eula"] = APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 2
            )
        }
        if includesInstallation {
            entries["SYNO.Core.Package.Installation"] = APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 2
            )
            entries["SYNO.Core.Package.Installation.Download"] = APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1
            )
            entries["SYNO.Entry.Request"] = APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1
            )
            entries["SYNO.Core.Package.Feed"] = APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1
            )
        }
        if includesDirectMutations {
            entries["SYNO.Core.Package.Control"] = APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1
            )
            entries["SYNO.Core.Package.Uninstallation"] = APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1
            )
            entries["SYNO.Core.Package.Setting"] = APIInfoEntry(
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
            requestData: { try await stub.data(for: $0) },
            uploadFile: { try await stub.upload(for: $0, fromFile: $1) }
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

    private func parameters(from request: URLRequest) throws -> [String: String] {
        let url = try #require(request.url)
        var items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let body = request.httpBody,
           let encodedBody = String(data: body, encoding: .utf8) {
            var components = URLComponents()
            components.percentEncodedQuery = encodedBody
            items.append(contentsOf: components.queryItems ?? [])
        }
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }

    private func objectArray(from value: String?) throws -> [[String: Any]] {
        let value = try #require(value)
        return try #require(
            JSONSerialization.jsonObject(with: Data(value.utf8)) as? [[String: Any]]
        )
    }

    private func object(from value: String?) throws -> [String: Any] {
        let value = try #require(value)
        return try #require(
            JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any]
        )
    }

    private func stringArray(from value: String?) throws -> [String] {
        let value = try #require(value)
        return try JSONDecoder().decode([String].self, from: Data(value.utf8))
    }
}
