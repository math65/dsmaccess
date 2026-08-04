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

    /// Real shape of an entry, captured on DSM 7.4. Decoding is limited to the six fields the
    /// NAS sends: the extra aliases it carried for a while matched nothing and left the
    /// columns empty.
    @Test func decodesASystemLogEntryAsTheNASSendsIt() throws {
        let data = Data(
            #"""
            {
              "time": "2026/07/30 11:32:32",
              "level": "warn",
              "logtype": "Système",
              "orginalLogType": "system",
              "who": "testeur",
              "descr": "Echec de connexion"
            }
            """#.utf8
        )

        let entry = try JSONDecoder().decode(SystemLogEntry.self, from: data)

        #expect(entry.level == .warning)
        #expect(entry.technicalCategory == "system")
        #expect(entry.translatedCategory == "Système")
        #expect(entry.account == "testeur")
        #expect(entry.message == "Echec de connexion")
        #expect(entry.recordedAt != nil)
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
            try JSONDecoder().decode(SystemLogPage.self, from: malformed)
        }
    }

    @Test func givesDuplicateLogEntriesDistinctIdentities() throws {
        let systemLogs = try JSONDecoder().decode(
            SystemLogPage.self,
            from: Data(#"""
            {"items":[{"time":"2026/07/30 11:00:00","descr":"same"},
                      {"time":"2026/07/30 11:00:00","descr":"same"}]}
            """#.utf8)
        )
        #expect(Set(systemLogs.entries.map(\.id)).count == 2)

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

    /// DSM names the recycle-bin fields `enable_recycle_bin` and `recycle_bin_admin_only`, and
    /// omits them entirely on a folder that never had a recycle bin. Reading the wrong key left
    /// the column empty on every folder, whatever the NAS answered.
    @Test func decodesSharedFolderSettingsAsDSMNamesThem() throws {
        let configured = try JSONDecoder().decode(
            SharedFolder.self,
            from: Data(
                #"""
                {
                  "name": "documents",
                  "vol_path": "/volume1",
                  "enable_recycle_bin": true,
                  "recycle_bin_admin_only": true,
                  "hidden": true,
                  "hide_unreadable": true,
                  "encryption": 2
                }
                """#.utf8
            )
        )
        let bare = try JSONDecoder().decode(
            SharedFolder.self,
            from: Data(#"{"name":"scratch","vol_path":"/volume1","encryption":0}"#.utf8)
        )
        let locked = try JSONDecoder().decode(
            SharedFolder.self,
            from: Data(#"{"name":"vault","vol_path":"/volume1","encryption":1}"#.utf8)
        )

        #expect(configured.recycleBinEnabled == true)
        #expect(configured.recycleBinAdminOnly == true)
        #expect(configured.hidden == true)
        #expect(configured.hidesUnreadableItems == true)
        #expect(configured.encryptionState == .mounted)
        #expect(configured.recycleBinDescription == String(localized: "common.answer.yes"))

        #expect(bare.recycleBinEnabled == nil)
        #expect(bare.encryptionState == .none)
        // An absent flag is what DSM sends for a folder whose recycle bin was never switched
        // on, so it has to read as "no" rather than as an unknown value.
        #expect(bare.recycleBinDescription == String(localized: "common.answer.no"))

        #expect(locked.encryptionState == .locked)
        #expect(locked.encryptionState.isEncrypted)
        #expect(locked.sortableEncryption == 1)
    }

    /// `create` answers 502 and drops the request when `encryption` carries the boolean false,
    /// so a folder without a key must not mention encryption at all.
    @Test func encodesShareCreationWithoutEncryptionUnlessKeyed() throws {
        let plain = SharedFolderCreation(
            name: "documents",
            volumePath: "/volume1",
            description: "Team files",
            recycleBinEnabled: true,
            recycleBinAdminOnly: false,
            hidden: true,
            hidesUnreadableItems: true
        )
        let encrypted = SharedFolderCreation(
            name: "vault",
            volumePath: "/volume1",
            encryptionKey: "correct horse"
        )

        let plainFields = try encodedFields(plain)
        let encryptedFields = try encodedFields(encrypted)

        #expect(plainFields["enable_recycle_bin"] as? Bool == true)
        #expect(plainFields["recycle_bin_admin_only"] as? Bool == false)
        #expect(plainFields["hidden"] as? Bool == true)
        #expect(plainFields["hide_unreadable"] as? Bool == true)
        #expect(plainFields["desc"] as? String == "Team files")
        #expect(plainFields["encryption"] == nil)
        #expect(plainFields["enc_passwd"] == nil)

        #expect(encryptedFields["encryption"] as? Bool == true)
        #expect(encryptedFields["enc_passwd"] as? String == "correct horse")
    }

    /// `set` answers 403 without both `name` and `vol_path`, and applies only the fields it is
    /// given — sending the untouched ones would restate settings the user never opened.
    @Test func encodesShareChangesAsASparseUpdate() throws {
        var recycleBinOnly = SharedFolderChanges(name: "documents", volumePath: "/volume1")
        recycleBinOnly.recycleBinEnabled = false

        var encrypting = SharedFolderChanges(name: "vault", volumePath: "/volume1")
        encrypting.encryption = .encrypt(key: "correct horse")

        var decrypting = SharedFolderChanges(name: "vault", volumePath: "/volume1")
        decrypting.encryption = .decrypt(key: "correct horse")

        let sparse = try encodedFields(recycleBinOnly)
        let encryptingFields = try encodedFields(encrypting)
        let decryptingFields = try encodedFields(decrypting)

        #expect(sparse["name"] as? String == "documents")
        #expect(sparse["vol_path"] as? String == "/volume1")
        #expect(sparse["enable_recycle_bin"] as? Bool == false)
        #expect(sparse["desc"] == nil)
        #expect(sparse["hidden"] == nil)
        #expect(sparse["encryption"] == nil)

        #expect(encryptingFields["encryption"] as? Bool == true)
        #expect(encryptingFields["enc_passwd"] as? String == "correct horse")
        #expect(decryptingFields["encryption"] as? Bool == false)
        #expect(decryptingFields["enc_passwd"] as? String == "correct horse")

        #expect(SharedFolderChanges(name: "documents", volumePath: "/volume1").isEmpty)
        #expect(!recycleBinOnly.isEmpty)
        #expect(!encrypting.isEmpty)
    }

    /// Several settings are written under one name and read back under another: the quota goes
    /// out as `share_quota` and comes back as `quota_value`, and the three restrictions travel
    /// inside `advanceperm` but are answered as plain fields.
    @Test func handlesTheAsymmetryBetweenReadingAndWritingShareSettings() throws {
        let folder = try JSONDecoder().decode(
            SharedFolder.self,
            from: Data(
                #"""
                {
                  "name": "documents",
                  "vol_path": "/volume1",
                  "quota_value": 5120,
                  "enable_share_compress": true,
                  "enable_share_cow": true,
                  "disable_list": true,
                  "disable_modify": false,
                  "disable_download": true
                }
                """#.utf8
            )
        )

        var changes = SharedFolderChanges(name: "documents", volumePath: "/volume1")
        changes.quotaMegabytes = 2048
        changes.compressionEnabled = false
        changes.advancedPermissions = .init(
            disablesListing: false,
            disablesModification: true,
            disablesDownload: false
        )
        let written = try encodedFields(changes)

        #expect(folder.quotaMegabytes == 5120)
        #expect(folder.compressionEnabled == true)
        #expect(folder.checksumEnabled == true)
        #expect(folder.disablesListing == true)
        #expect(folder.disablesModification == false)
        #expect(folder.disablesDownload == true)

        #expect(written["share_quota"] as? Int == 2048)
        #expect(written["quota_value"] == nil)
        #expect(written["enable_share_compress"] as? Bool == false)
        let advanced = try #require(written["advanceperm"] as? [String: Any])
        #expect(advanced["disable_list"] as? Bool == false)
        #expect(advanced["disable_modify"] as? Bool == true)
        #expect(advanced["disable_download"] as? Bool == false)
        #expect(written["disable_list"] == nil)
    }

    /// While DSM is still checking the folder it reports no percentage at all, and the answer
    /// also repeats the request — encryption key included — which is why only two values are
    /// decoded out of it.
    @Test func readsConversionProgressWhileItIsStillChecking() throws {
        let checking = try JSONDecoder().decode(
            ShareConversionStatus.self,
            from: Data(#"{"finish":false,"data":{"status":"checking"}}"#.utf8)
        )
        let running = try JSONDecoder().decode(
            ShareConversionStatus.self,
            from: Data(#"{"finish":false,"data":{"percent":42,"status":"processing"}}"#.utf8)
        )
        let done = try JSONDecoder().decode(
            ShareConversionStatus.self,
            from: Data(#"{"finish":true,"data":{"percent":100,"status":"success"}}"#.utf8)
        )
        let started = try JSONDecoder().decode(
            ShareUpdateResult.self,
            from: Data(#"{"name":"documents","task_id":"@administrators/sharemove1"}"#.utf8)
        )
        let plain = try JSONDecoder().decode(
            ShareUpdateResult.self,
            from: Data(#"{"name":"documents"}"#.utf8)
        )

        #expect(!checking.finished)
        #expect(checking.percent == 0)
        #expect(running.percent == 42)
        #expect(done.finished)
        #expect(started.taskID == "@administrators/sharemove1")
        // No task means nothing to follow: only encryption changes start one.
        #expect(plain.taskID == nil)
    }

    /// Read from a folder, DSM answers the same rows under `items` rather than `shares`.
    @Test func decodesTheAccountsReachingASharedFolder() throws {
        let list = try JSONDecoder().decode(
            DSMShareAccountPermissionList.self,
            from: Data(
                #"""
                {
                  "total": 2,
                  "items": [
                    {"name": "alex", "is_readonly": true, "is_writable": false, "is_deny": false, "inherit": "rw"},
                    {"name": "sam", "is_readonly": false, "is_writable": false, "is_deny": true, "inherit": "-"}
                  ]
                }
                """#.utf8
            )
        )

        #expect(list.total == 2)
        #expect(list.items.count == 2)
        #expect(list.items[0].granted == .readOnly)
        #expect(list.items[0].inherited == .readWrite)
        // NA > RW > RO: the group right wins over the account's own read-only.
        #expect(list.items[0].effective == .readWrite)
        #expect(list.items[1].granted == .noAccess)
        #expect(list.items[1].inherited == nil)
    }

    /// The NAS encrypts a folder with whatever key it is handed, including an empty one, and
    /// then never unlocks it again. These rules are the only thing standing in the way.
    @Test func rejectsEncryptionKeysTheNASWouldHaveAccepted() throws {
        #expect(ShareEncryptionKey.problem(key: "", confirmation: "") != nil)
        #expect(ShareEncryptionKey.problem(key: "abc", confirmation: "abc") != nil)
        #expect(ShareEncryptionKey.problem(key: "correct horse", confirmation: "correct hors") != nil)
        #expect(ShareEncryptionKey.problem(key: "correct horse", confirmation: "correct horse") == nil)
    }

    private func encodedFields(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
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

    @Test func generatesPasswordsThatSatisfyTheNASRules() throws {
        let policy = try JSONDecoder().decode(
            DSMPasswordPolicy.self,
            from: Data(
                #"{"strong_password":{"min_length":20,"min_length_enable":true,"mixed_case":true,"included_numeric_char":true,"included_special_char":true}}"#.utf8
            )
        )
        // The draw is random: it is the invariants that are checked, over enough samples for
        // a missing class to show up.
        for _ in 0..<50 {
            let password = DSMPasswordPolicy.generatedPassword(for: policy)
            #expect(password.count == 20)
            #expect(password.contains { $0.isLowercase })
            #expect(password.contains { $0.isUppercase })
            #expect(password.contains { $0.isNumber })
            #expect(password.contains { !$0.isLetter && !$0.isNumber })
            // Characters excluded because they get confused when read out and dictated.
            #expect(!password.contains { "l1IO0".contains($0) })
        }
    }

    @Test func generatesASolidPasswordWithoutAnyKnownPolicy() {
        let password = DSMPasswordPolicy.generatedPassword(for: nil)

        #expect(password.count == 16)
        #expect(password.contains { $0.isLowercase })
        #expect(password.contains { $0.isUppercase })
        #expect(password.contains { $0.isNumber })
    }
}
