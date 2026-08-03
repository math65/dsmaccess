import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct ExternalStorageTests {
    /// The payload DSM returns for `list` with `additional: ["all"]`, captured on a DS920+
    /// running DSM 7.4 with a two-partition USB key attached.
    private static let listPayload = """
    {
      "devices": [
        {
          "dev_id": "usb1",
          "dev_title": "USB Disk 1",
          "dev_type": "usbDisk",
          "formatable": true,
          "producer": "Some Maker",
          "product": "Some Model",
          "progress": "",
          "status": "normal",
          "total_size_mb": 7377,
          "partitions": [
            {
              "dev_fstype": "vfat",
              "filesystem": "FAT32",
              "name_id": "usb1p1",
              "partition_title": "USB Disk 1 Partition 1",
              "share_name": "usbshare1-1",
              "status": "normal",
              "total_size_mb": 197,
              "used_size_mb": 0
            },
            {
              "dev_fstype": "vfat",
              "filesystem": "FAT32",
              "name_id": "usb1p2",
              "partition_title": "USB Disk 1 Partition 2",
              "share_name": "usbshare1-2",
              "status": "normal",
              "total_size_mb": 7162,
              "used_size_mb": 4
            }
          ]
        }
      ]
    }
    """

    @Test func decodesADeviceWithItsPartitions() throws {
        let list = try JSONDecoder().decode(
            ExternalStorageDeviceList.self,
            from: Data(Self.listPayload.utf8)
        )

        let device = try #require(list.devices.first)
        #expect(device.devID == "usb1")
        #expect(device.displayName == "USB Disk 1")
        #expect(device.producer == "Some Maker")
        #expect(device.totalSizeMB == 7377)
        #expect(device.isFormattable)
        #expect(!device.isFormatting)
        #expect(device.partitions.count == 2)

        let partition = try #require(device.partitions.first)
        #expect(partition.nameID == "usb1p1")
        #expect(partition.shareName == "usbshare1-1")
        #expect(partition.filesystem == "FAT32")
        #expect(partition.usedSizeMB == 0)
        #expect(partition.totalSizeMB == 197)
    }

    /// While DSM formats, the device keeps its partition but empties `filesystem` and
    /// `share_name`. Carrying those through as empty strings would put blank values in the
    /// table instead of the "unknown" dash.
    @Test func treatsTheEmptyFieldsOfAFormattingDeviceAsAbsent() throws {
        let payload = """
        {
          "devices": [
            {
              "dev_id": "usb1",
              "dev_title": "USB Disk 1",
              "status": "formating",
              "formatable": true,
              "partitions": [
                {
                  "name_id": "usb1p1",
                  "partition_title": "USB Disk 1 Partition 1",
                  "share_name": "",
                  "filesystem": "",
                  "status": "normal",
                  "total_size_mb": 7373
                }
              ]
            }
          ]
        }
        """

        let list = try JSONDecoder().decode(
            ExternalStorageDeviceList.self,
            from: Data(payload.utf8)
        )
        let device = try #require(list.devices.first)

        #expect(device.isFormatting)
        #expect(device.partitions.first?.shareName == nil)
        #expect(device.partitions.first?.filesystem == nil)
        #expect(device.partitions.first?.usedSizeMB == nil)
    }

    /// Synology spells the in-progress status with a single "t". Correcting it to "formatting"
    /// would make the app miss every running format.
    @Test func recognisesSynologysSpellingOfTheFormattingStatus() throws {
        let payload = """
        { "devices": [ { "dev_id": "usb1", "status": "formating" } ] }
        """
        let list = try JSONDecoder().decode(
            ExternalStorageDeviceList.self,
            from: Data(payload.utf8)
        )

        #expect(list.devices.first?.isFormatting == true)
    }

    /// The tokens DSM sends for the file systems, measured by formatting a real key three
    /// times. FAT32 travels as "fat": sending "fat32" is refused.
    @Test func sendsTheFileSystemTokensDSMExpects() {
        #expect(ExternalStorageFileSystem.fat.rawValue == "fat")
        #expect(ExternalStorageFileSystem.exfat.rawValue == "exfat")
        #expect(ExternalStorageFileSystem.ext4.rawValue == "ext4")
        #expect(ExternalStorageFileSystem.fat.title == "FAT32")
    }

    @Test func namesBothStorageAPIs() {
        #expect(ExternalStorageConnection.usb.apiName == "SYNO.Core.ExternalDevice.Storage.USB")
        #expect(ExternalStorageConnection.esata.apiName == "SYNO.Core.ExternalDevice.Storage.eSATA")
    }

    @Test func decodesTheSharedSettings() throws {
        let payload = """
        {
          "delalloc": false,
          "forbid_usb": true,
          "needReboot": true,
          "non_admin_eject": true,
          "setting": false,
          "support_exfat_mkfs": "yes"
        }
        """

        let settings = try JSONDecoder().decode(
            ExternalStorageSettings.self,
            from: Data(payload.utf8)
        )

        #expect(settings.forbidsUSB)
        #expect(settings.allowsNonAdminEject)
        #expect(!settings.usesDelayedAllocation)
        #expect(settings.needsReboot)
    }

    /// A device without partitions is what DSM returns for an unformatted drive; it must decode
    /// rather than fail, since that is precisely the drive the user wants to format.
    @Test func decodesADeviceWithoutPartitions() throws {
        let payload = """
        { "devices": [ { "dev_id": "usb1", "dev_title": "USB Disk 1", "status": "normal" } ] }
        """

        let list = try JSONDecoder().decode(
            ExternalStorageDeviceList.self,
            from: Data(payload.utf8)
        )
        let device = try #require(list.devices.first)

        #expect(device.partitions.isEmpty)
        #expect(!device.isFormattable)
    }
}
