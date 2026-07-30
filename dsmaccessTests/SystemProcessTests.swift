import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct SystemProcessTests {
    /// Shapes captured on the DS920+ running DSM 7.4 on 29/07/2026. No account or machine
    /// names appear here: only the shape of the response is taken from the NAS.
    @Test func readsProcessesWithTheirMemoryInKibibytes() throws {
        let payload = Data(#"""
        {"process":[
          {"command":"openvpn","cpu":75,"mem":1444,"mem_shared":408,"pid":25115,"status":"R"},
          {"command":"synorelayd","cpu":5,"mem":10456,"mem_shared":8704,"pid":17769,"status":"R"}]}
        """#.utf8)

        let page = try JSONDecoder().decode(SystemProcessPage.self, from: payload)

        let first = try #require(page.process.first)
        #expect(first.name == "openvpn")
        #expect(first.cpuPercent == 75)
        #expect(first.memoryKiB == 1444)
        #expect(first.pid == 25115)
        #expect(first.status == "R")
        #expect(page.process.count == 2)
    }

    /// DSM writes neither zero nor `null` for a group it does not measure: it sends the
    /// string "-". Two groups out of twenty-one were in that case. Decoded as zero, it would
    /// make a missing measurement look like an idle service.
    @Test func readsADashAsAMissingMeasurementNotAsZero() throws {
        let payload = Data(#"""
        {"slices":[
          {"byte_read_per_sec":0,"byte_write_per_sec":0,"cpu_time":"-","cpu_utilization":"-",
           "memory":"-","name":"Sans mesure","name_i18n":"","process":[],"unit_name":"none.slice"}]}
        """#.utf8)

        let group = try #require(
            try JSONDecoder().decode(ProcessGroupPage.self, from: payload).slices.first
        )

        #expect(group.cpuPercent == nil)
        #expect(group.cpuTime == nil)
        #expect(group.memoryBytes == nil)
        // The rest of the row survives: one unmeasured field must not take the group down.
        #expect(group.displayName == "Sans mesure")
        #expect(group.readBytesPerSecond == 0)
    }

    /// Two opposite scales for the same quantity, captured on 30/07/2026: a process load is
    /// already a percentage, a group load is a fraction. DSM's own web client even names it
    /// `cpuFraction` and multiplies it by 100. Read as is, the "CPU" column of the services
    /// reads "0.0 %" all the way down, including for a service that really is consuming.
    @Test func readsTheGroupCPUAsAFractionAndTheProcessCPUAsAPercentage() throws {
        let groupPayload = Data(#"""
        {"slices":[
          {"cpu_time":48.4,"cpu_utilization":0.012091898428053204,"memory":2048,
           "name":"Service de bureau","name_i18n":"","process":[{}],"unit_name":"desktop.slice",
           "byte_read_per_sec":0,"byte_write_per_sec":0},
          {"cpu_time":271.21,"cpu_utilization":0.001095290251916758,"memory":1024,
           "name":"SNMP","name_i18n":"","process":[{}],"unit_name":"snmp.slice",
           "byte_read_per_sec":0,"byte_write_per_sec":0}]}
        """#.utf8)
        let processPayload = Data(#"""
        {"process":[{"command":"synorelayd","cpu":10,"mem":14420,"mem_shared":0,"pid":1,"status":"R"}]}
        """#.utf8)

        let groups = try JSONDecoder().decode(ProcessGroupPage.self, from: groupPayload).slices
        let processes = try JSONDecoder().decode(SystemProcessPage.self, from: processPayload).process

        let desktop = try #require(groups.first?.cpuPercent)
        #expect(abs(desktop - 1.2091898428053204) < 0.000_001)
        let snmp = try #require(groups.last?.cpuPercent)
        #expect(abs(snmp - 0.1095290251916758) < 0.000_001)
        // The process value, on the other hand, is not converted: 10 really means 10 %.
        #expect(processes.first?.cpuPercent == 10)
    }

    /// The two forms actually observed, and they exclude each other: either `name` carries a
    /// plain name and `name_i18n` is empty, or the reverse — and then `name_i18n` holds a DSM
    /// catalog key, not a translation. Displayed as is, that key would show
    /// "storage_pool:raid_process" among "SNMP" and "Plex Media Server". Since it cannot be
    /// resolved, it is made readable: only its punctuation changes.
    @Test func namesAGroupFromWhicheverFieldTheNASFilledIn() throws {
        let payload = Data(#"""
        {"slices":[
          {"cpu_time":218.77,"cpu_utilization":0,"memory":4033536,"name":"SNMP",
           "name_i18n":"","process":[{}],"unit_name":"snmp.slice",
           "byte_read_per_sec":0,"byte_write_per_sec":0},
          {"cpu_time":1,"cpu_utilization":0,"memory":2048,"name":"",
           "name_i18n":"storage_pool:raid_process","process":[{},{}],"unit_name":"raid.slice",
           "byte_read_per_sec":0,"byte_write_per_sec":0},
          {"name":"","name_i18n":"service:desktop_service","unit_name":"d.slice","process":[]},
          {"name":"Plex Media Server","name_i18n":"","unit_name":"plex.slice","process":[]}]}
        """#.utf8)

        let groups = try JSONDecoder().decode(ProcessGroupPage.self, from: payload).slices

        #expect(groups[0].displayName == "SNMP")
        #expect(groups[0].id == "snmp.slice")
        #expect(groups[0].memoryBytes == 4_033_536)
        #expect(groups[0].processCount == 1)
        #expect(groups[1].displayName == "Raid process")
        #expect(groups[1].processCount == 2)
        #expect(groups[2].displayName == "Desktop service")
        // A name that is already presentable is left untouched.
        #expect(groups[3].displayName == "Plex Media Server")
    }
}
