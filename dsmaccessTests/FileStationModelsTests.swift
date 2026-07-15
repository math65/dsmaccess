import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct FileStationModelsTests {
    @Test func safelyEncodesPathArrays() throws {
        let encoded = try DSMParameter.json([
            "/documents/rapport \"final\".pdf",
            "/photos/été\n2026.jpg",
        ])

        let value = try encoded.encoded(for: nil)
        let decoded = try JSONDecoder().decode([String].self, from: Data(value.utf8))
        #expect(decoded == [
            "/documents/rapport \"final\".pdf",
            "/photos/été\n2026.jpg",
        ])
    }

    @Test func decodesDetailedFileMetadata() throws {
        let data = Data(
            #"""
            {
              "name": "rapport.pdf",
              "path": "/documents/rapport.pdf",
              "isdir": false,
              "additional": {
                "size": 4096,
                "type": "application/pdf",
                "real_path": "/volume1/documents/rapport.pdf",
                "time": { "mtime": 1710000000, "atime": 1710000100, "crtime": 1700000000 },
                "owner": { "user": "mathieu", "group": "users" },
                "perm": { "posix": 644, "acl": { "read": true, "write": true, "del": false } }
              }
            }
            """#.utf8
        )

        let item = try JSONDecoder().decode(FileStationItem.self, from: data)

        #expect(item.name == "rapport.pdf")
        #expect(item.additional?.size == 4096)
        #expect(item.additional?.owner?.user == "mathieu")
        #expect(item.additional?.permission?.acl?.delete == false)
        #expect(item.additional?.realPath == "/volume1/documents/rapport.pdf")
    }
}
