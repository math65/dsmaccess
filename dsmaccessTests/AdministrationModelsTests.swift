import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct AdministrationModelsTests {
    @Test func decodesAccountValuesAcrossDSMTypes() throws {
        let data = Data(
            #"""
            {
              "name": "alex",
              "desc": "Compte local",
              "uid": "1031",
              "expired": "normal",
              "groups": ["users", "administrators"],
              "is_admin": 1
            }
            """#.utf8
        )

        let user = try JSONDecoder().decode(DSMUser.self, from: data)

        #expect(user.name == "alex")
        #expect(user.uid == 1031)
        #expect(user.isAdministrator)
        #expect(!user.isDisabled)
    }

    @Test func decodesDownloadTransferNumbersFromStrings() throws {
        let data = Data(
            #"""
            {
              "id": "dbid_1",
              "title": "archive.zip",
              "size": "1000",
              "status": "downloading",
              "additional": {
                "transfer": {
                  "size_downloaded": "250",
                  "size_uploaded": 12,
                  "speed_download": "2048",
                  "speed_upload": 0
                }
              }
            }
            """#.utf8
        )

        let task = try JSONDecoder().decode(DownloadTask.self, from: data)

        #expect(task.size == 1_000)
        #expect(task.downloaded == 250)
        #expect(task.progress == 0.25)
        #expect(task.downloadSpeed == 2_048)
        #expect(task.canPause)
    }

    @Test func decodesVirtualMachineInventory() throws {
        let data = Data(
            #"""
            {
              "guest_id": "vm-12",
              "guest_name": "Serveur de test",
              "status": "running",
              "vcpu_num": "4",
              "memory": 8192,
              "autorun": 1,
              "vdisks": [{"vdisk_id": "disk-1", "size": "10737418240"}],
              "vnics": [{"vnic_id": "nic-1", "mac": "00:11:22:33:44:55"}]
            }
            """#.utf8
        )

        let guest = try JSONDecoder().decode(VirtualMachine.self, from: data)

        #expect(guest.id == "vm-12")
        #expect(guest.isRunning)
        #expect(guest.vCPUCount == 4)
        #expect(guest.virtualDisks.first?.size == 10_737_418_240)
        #expect(guest.networkInterfaces.count == 1)
    }

    @Test func decodesContainerResourceValues() throws {
        let data = Data(
            #"""
            {
              "id": "sha256:1234",
              "name": "web",
              "image": "nginx:latest",
              "status": "running",
              "enable_auto_restart": "true",
              "cpu": "2.5%",
              "memory": "67108864",
              "started": 1718702062,
              "up_time": "90061"
            }
            """#.utf8
        )

        let container = try JSONDecoder().decode(ContainerItem.self, from: data)

        #expect(container.isRunning)
        #expect(container.autoRestart)
        #expect(container.cpuPercent == 2.5)
        #expect(container.memoryBytes == 67_108_864)
        #expect(container.startedAt == "1718702062")
        #expect(container.uptimeSeconds == 90_061)
    }

    @Test func decodesContainerStartTimeFromDSM74State() throws {
        let data = Data(
            #"""
            {
              "id": "container-id",
              "name": "web",
              "status": "running",
              "started": null,
              "up_time": null,
              "State": {
                "StartedAt": "2026-06-18T09:14:22.123456789Z"
              }
            }
            """#.utf8
        )

        let container = try JSONDecoder().decode(ContainerItem.self, from: data)

        #expect(container.startedAt == "2026-06-18T09:14:22.123456789Z")
        #expect(container.uptimeSeconds == nil)
    }

    @Test func decodesSurveillanceCameraStream() throws {
        let data = Data(
            #"""
            {
              "id": 144,
              "name": "Entrée",
              "enabled": true,
              "status": 1,
              "ip": "192.168.1.20",
              "vendor": "ONVIF",
              "model": "Generic_ONVIF",
              "stream1": {"resolution": "1920x1080", "fps": "25"}
            }
            """#.utf8
        )

        let camera = try JSONDecoder().decode(SurveillanceCamera.self, from: data)

        #expect(camera.id == "144")
        #expect(camera.isAvailable)
        #expect(camera.resolution == "1920x1080")
        #expect(camera.framesPerSecond == 25)
    }

    @Test func decodesSystemLogAliases() throws {
        let data = Data(
            #"""
            {
              "time": 1710000000,
              "priority": "warning",
              "type": "connection",
              "who": "alex",
              "from": "192.168.1.30",
              "descr": "Login failed"
            }
            """#.utf8
        )

        let entry = try JSONDecoder().decode(SystemLogEntry.self, from: data)

        #expect(entry.timestamp == "1710000000")
        #expect(entry.level == "warning")
        #expect(entry.user == "alex")
        #expect(entry.message == "Login failed")
    }

    @Test func rejectsItemsWithoutOperationalIdentifiers() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(DownloadTask.self, from: Data(#"{"title":"x"}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(VirtualMachine.self, from: Data(#"{"guest_name":"x"}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SurveillanceCamera.self, from: Data(#"{"name":"x"}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ContainerItem.self, from: Data(#"{"id":"x"}"#.utf8))
        }
    }

    @Test func rejectsMalformedCollectionsInsteadOfReportingEmptyState() {
        let malformed = Data(#"{"items":"not-an-array"}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SystemLogList.self, from: malformed)
        }
    }

    @Test func givesDuplicateLogEntriesDistinctIdentities() throws {
        let systemLogs = try JSONDecoder().decode(
            SystemLogList.self,
            from: Data(#"{"logs":[{"time":1,"message":"same"},{"time":1,"message":"same"}]}"#.utf8)
        )
        #expect(Set(systemLogs.logs.map(\.id)).count == 2)

        let containerLogs = try JSONDecoder().decode(
            ContainerLogList.self,
            from: Data(#"{"logs":[{"time":1,"log":"same"},{"time":1,"log":"same"}]}"#.utf8)
        )
        #expect(Set(containerLogs.logs.map(\.id)).count == 2)
    }

    @Test func handlesNumericValuesOutsideIntegerRange() throws {
        let oversizedInteger = Data(
            #"{"enable_autoupdate":true,"autoupdateall":false,"autoupdateimportant":true,"enable_dsm":true,"enable_email":false,"default_vol":"volume1","trust_level":1e300,"update_channel":"stable"}"#.utf8
        )
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(PackageSettings.self, from: oversizedInteger)
        }

        let oversizedTransfer = Data(
            #"{"id":"task","title":"Archive","size":1e300,"status":"waiting"}"#.utf8
        )
        let task = try JSONDecoder().decode(DownloadTask.self, from: oversizedTransfer)
        #expect(task.size == 0)
    }

    @Test func requiresCompletePackageSettingsBeforeMutation() throws {
        let complete = Data(
            #"{"enable_autoupdate":true,"autoupdateall":false,"autoupdateimportant":true,"enable_dsm":1,"enable_email":"false","default_vol":"volume1","trust_level":"2","update_channel":"stable"}"#.utf8
        )
        var settings = try JSONDecoder().decode(PackageSettings.self, from: complete)
        settings.setAutoUpdateMode(.latest)

        #expect(settings.autoUpdateMode == .latest)
        #expect(settings.defaultVol == "volume1")
        #expect(settings.trustLevel == 2)
        #expect(settings.enableDsm)
        #expect(!settings.enableEmail)

        let incomplete = Data(
            #"{"enable_autoupdate":true,"autoupdateall":false,"autoupdateimportant":true,"enable_dsm":true,"enable_email":false,"default_vol":"volume1","update_channel":false}"#.utf8
        )
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(PackageSettings.self, from: incomplete)
        }
    }

    @Test func interpretsPackageControlAndRepairMetadataExactly() throws {
        let stopped = try JSONDecoder().decode(
            PackageInfo.self,
            from: Data(
                #"{"id":"HyperBackup","name":"Hyper Backup","version":"4.1","additional":{"status":"stopped","startable":true,"ctl_uninstall":true,"is_uninstall_pages":true}}"#.utf8
            )
        )
        let broken = try JSONDecoder().decode(
            PackageInfo.self,
            from: Data(
                #"{"id":"Drive","additional":{"status":"broken","startable":false,"ctl_uninstall":false}}"#.utf8
            )
        )
        let unknownStatus = try JSONDecoder().decode(
            PackageInfo.self,
            from: Data(#"{"id":"Example","additional":{"status":"no_error"}}"#.utf8)
        )

        #expect(stopped.isStopped)
        #expect(!stopped.isRunning)
        #expect(stopped.canStartStop)
        #expect(stopped.canUninstall)
        #expect(stopped.hasUninstallOptions)
        #expect(!stopped.requiresAttention)
        #expect(broken.requiresAttention)
        #expect(broken.statusText == String(localized: "Réparation requise"))
        #expect(!broken.isStopped)
        #expect(!broken.canStartStop)
        #expect(!broken.canUninstall)
        #expect(!unknownStatus.requiresAttention)
        let rawUnknownStatus = "no_error"
        #expect(
            unknownStatus.statusText
                == String(localized: "État DSM : \(rawUnknownStatus)")
        )
    }

    @Test func sharedFolderIdentityIsStable() throws {
        let folder = try JSONDecoder().decode(
            SharedFolder.self,
            from: Data(#"{"name":"documents","vol_path":"/volume1"}"#.utf8)
        )
        #expect(folder.id == "documents")
        #expect(folder.id == folder.id)
    }

    @Test func rejectsInvalidStorageMetrics() throws {
        #expect(usagePercent(usedBytes: "50", totalBytes: "100") == 50)
        #expect(usagePercent(usedBytes: "101", totalBytes: "100") == nil)
        #expect(usagePercent(usedBytes: "9223372036854775807", totalBytes: "1") == nil)

        let volume = try JSONDecoder().decode(
            Volume.self,
            from: Data(
                #"{"id":"volume_1","size":{"total_inode":"1","free_inode":"-9223372036854775808"}}"#.utf8
            )
        )
        #expect(volume.inodePercent == nil)
    }
}
