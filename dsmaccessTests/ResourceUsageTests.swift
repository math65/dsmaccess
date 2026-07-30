import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct ResourceUsageTests {
    /// Response captured on the DS920+ running DSM 7.4 on 2026-07-29, reduced to the fields
    /// the app reads. The values are the NAS's own: that is what guarantees the decoding
    /// follows the real contract and not a reconstruction.
    private let payload = Data(#"""
    {"cpu":{"15min_load":96,"1min_load":57,"5min_load":69,"device":"System",
      "other_load":4,"system_load":3,"user_load":1},
     "disk":{"disk":[{"device":"sata2","display_name":"Drive 4","read_access":55,
       "read_byte":879957,"type":"internal","utilization":14,"write_access":2,
       "write_byte":16384}],
      "total":{"device":"total","read_access":220,"read_byte":3555327,
       "utilization":13,"write_access":8,"write_byte":65536}},
     "memory":{"avail_real":144700,"real_usage":18,"swap_usage":3,"total_real":3856560},
     "network":[{"device":"total","rx":1024,"tx":2048}],
     "space":{"total":{"device":"total","read_access":208,"read_byte":3541674,
       "utilization":27,"write_access":0,"write_byte":0},
      "volume":[{"device":"dm-1","display_name":"volume1","read_access":208,
       "read_byte":3541674,"utilization":27,"write_access":0,"write_byte":0}]}}
    """#.utf8)

    /// DSM sends load averages multiplied by one hundred: its own web client divides by 100
    /// before displaying them. Taking them for percentages would show "96 %" where the
    /// machine is at a load of 0.96.
    @Test func readsLoadAveragesAsHundredthsNotPercentages() throws {
        let usage = try JSONDecoder().decode(ResourceUsage.self, from: payload)

        let cpu = try #require(usage.cpu)
        #expect(cpu.oneMinuteLoad == 0.57)
        #expect(cpu.fiveMinuteLoad == 0.69)
        #expect(cpu.fifteenMinuteLoad == 0.96)
        // The instantaneous loads, on the other hand, really are percentages.
        #expect(cpu.userLoad == 1)
        #expect(cpu.systemLoad == 3)
    }

    /// Disks and volumes share the same shape in DSM, except that the list is called `disk`
    /// on one side and `volume` on the other, and the aggregate entry is kept apart under
    /// `total`.
    @Test func readsDisksAndVolumesFromTheirTwoDifferentKeys() throws {
        let usage = try JSONDecoder().decode(ResourceUsage.self, from: payload)

        let disk = try #require(usage.disk?.devices.first)
        #expect(disk.name == "Drive 4")
        #expect(disk.type == "internal")
        #expect(disk.utilization == 14)
        #expect(disk.readBytesPerSecond == 879_957)
        #expect(usage.disk?.total?.device == "total")

        let volume = try #require(usage.space?.devices.first)
        #expect(volume.name == "volume1")
        #expect(volume.utilization == 27)
        // A volume carries no type: the field stays absent, without failing the whole decode.
        #expect(volume.type == nil)
    }

    /// Measured on the NAS: 3.68 GB of memory, 0.13 GB free, 2.89 GB of cache — and DSM
    /// reports 17 % usage. Counting the cache as used would give 96 %, contradicting the
    /// percentage displayed just above it on the same screen.
    @Test func excludesCacheFromUsedMemoryLikeDSMDoes() throws {
        let payload = Data(#"""
        {"memory":{"avail_real":144700,"buffer":10240,"cached":3024532,
          "real_usage":17,"total_real":3856560}}
        """#.utf8)

        let memory = try #require(
            try JSONDecoder().decode(ResourceUsage.self, from: payload).memory
        )
        let used = try #require(memory.usedReal)
        let total = try #require(memory.totalReal)
        let available = try #require(memory.availReal)

        #expect(used == 677_088)
        // The naive computation, cache included, would report more than five times that value.
        #expect(total - available == 3_711_860)
        // Up to rounding, we get back the percentage DSM displays itself: the two lines on
        // the screen finally measure the same thing.
        let percent = Int((Double(used) / Double(total) * 100).rounded())
        #expect(abs(percent - (memory.realUsage ?? 0)) <= 1)
    }

    /// A NAS with no exposed disk, or a DSM version that would omit these blocks, must not
    /// make the whole resources screen unreadable.
    @Test func survivesAResponseWithoutDisksOrVolumes() throws {
        let minimal = Data(#"{"cpu":{"user_load":2},"memory":{"real_usage":40}}"#.utf8)

        let usage = try JSONDecoder().decode(ResourceUsage.self, from: minimal)

        #expect(usage.cpu?.userLoad == 2)
        #expect(usage.cpu?.oneMinuteLoad == nil)
        #expect(usage.disk == nil)
        #expect(usage.space == nil)
    }
}
