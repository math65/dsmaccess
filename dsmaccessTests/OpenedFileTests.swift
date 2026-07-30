import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct OpenedFileTests {
    /// Shape observed on the DS920+ under DSM 7.4 on 2026/07/30. The NAS's real paths do not
    /// appear here: only the shape of the response is reproduced.
    @Test func readsOpenedFilesAsTheNASSendsThem() throws {
        let payload = Data(#"""
        {"OpenedFiles":[
          {"filename":"journal.log","hidden":0,"host":"-","path":"AppData/service/journal.log",
           "pid":"23037","service":"Service local","user":"-"},
          {"filename":"rapport.docx","hidden":0,"host":"10.0.0.2","path":"Documents/rapport.docx",
           "pid":"14002","service":"SMB","user":"testeur"}],
         "total":2}
        """#.utf8)

        let page = try JSONDecoder().decode(OpenedFilePage.self, from: payload)

        #expect(page.total == 2)
        #expect(page.files.count == 2)
        let network = try #require(page.files.last)
        #expect(network.displayName == "rapport.docx")
        #expect(network.folder == "Documents")
        #expect(network.service == "SMB")
        #expect(network.account == "testeur")
        #expect(network.host == "10.0.0.2")
        #expect(network.processID == "14002")
    }

    /// DSM writes "-" and not an empty string when the value does not apply: a service of the
    /// NAS itself has neither an account nor an originating machine. Displayed as is, that dash
    /// would look like data returned by the NAS.
    @Test func readsADashAsAnAbsentAccountAndHost() throws {
        let payload = Data(#"""
        {"OpenedFiles":[{"filename":"base.db","host":"-","path":"AppData/base.db",
          "pid":"19896","service":"Service local","user":"-"}],"total":1}
        """#.utf8)

        let file = try #require(
            try JSONDecoder().decode(OpenedFilePage.self, from: payload).files.first
        )

        #expect(file.account == nil)
        #expect(file.host == nil)
        // The rest of the row survives: the file stays listed with its service.
        #expect(file.service == "Service local")
        #expect(file.displayName == "base.db")
    }

    /// `path` is relative to the share and ends with the file name. The folder is derived from
    /// it so the name is not repeated in two neighbouring columns; a path without a folder must
    /// not produce an empty string, which would read as a value.
    @Test func derivesTheFolderWithoutRepeatingTheFileName() throws {
        let payload = Data(#"""
        {"OpenedFiles":[
          {"filename":"a.txt","path":"a.txt","pid":"1","service":"SMB","user":"testeur","host":"10.0.0.2"},
          {"filename":"b.txt","path":"Partage/Sous dossier/b.txt","pid":"2","service":"SMB","user":"testeur","host":"10.0.0.2"}],
         "total":2}
        """#.utf8)

        let files = try JSONDecoder().decode(OpenedFilePage.self, from: payload).files

        #expect(files[0].folder == nil)
        #expect(files[1].folder == "Partage/Sous dossier")
    }

    /// A single process often holds several files, and a single path can be opened by several
    /// processes. Without both in the key, distinct rows would be conflated in the table.
    @Test func distinguishesFilesHeldByTheSameProcess() throws {
        let payload = Data(#"""
        {"OpenedFiles":[
          {"filename":"un.log","path":"App/un.log","pid":"19896","service":"S","user":"-","host":"-"},
          {"filename":"deux.log","path":"App/deux.log","pid":"19896","service":"S","user":"-","host":"-"}],
         "total":2}
        """#.utf8)

        let files = try JSONDecoder().decode(OpenedFilePage.self, from: payload).files

        #expect(files[0].id != files[1].id)
    }

    /// An idle NAS returns no file at all. A missing key must not make decoding fail: the
    /// screen has an empty state to present.
    @Test func survivesAResponseWithoutAnyOpenedFile() throws {
        let page = try JSONDecoder().decode(
            OpenedFilePage.self, from: Data(#"{"total":0}"#.utf8)
        )

        #expect(page.files.isEmpty)
        #expect(page.total == 0)
    }
}
