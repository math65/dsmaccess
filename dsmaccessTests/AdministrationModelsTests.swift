import Foundation
import Testing
@testable import dsmaccess

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
              "cpu_percent": "2.5%",
              "memory_usage": "67108864"
            }
            """#.utf8
        )

        let container = try JSONDecoder().decode(ContainerItem.self, from: data)

        #expect(container.isRunning)
        #expect(container.autoRestart)
        #expect(container.cpuPercent == 2.5)
        #expect(container.memoryBytes == 67_108_864)
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
              "event": "Login failed"
            }
            """#.utf8
        )

        let entry = try JSONDecoder().decode(SystemLogEntry.self, from: data)

        #expect(entry.timestamp == "1710000000")
        #expect(entry.level == "warning")
        #expect(entry.user == "alex")
        #expect(entry.message == "Login failed")
    }
}
