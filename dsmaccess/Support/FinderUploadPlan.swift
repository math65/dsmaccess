//
//  FinderUploadPlan.swift
//  dsmaccess
//
//  Local expansion of a Finder selection into an upload plan: files with their
//  relative folder, and the folder tree to recreate on the NAS.
//

import Foundation

/// File Station's upload API handles one file at a time: a folder pasted or
/// picked in the Finder is therefore expanded on the Mac side before uploading.
struct FinderUploadPlan: Equatable, Sendable {
    struct File: Equatable, Sendable {
        let source: URL
        /// Folder path relative to the destination ("Vacances/2024"), or `nil`
        /// for a file uploaded directly into the destination.
        let relativeFolder: String?

        func destinationFolder(under parent: String) -> String {
            relativeFolder.map { "\(parent)/\($0)" } ?? parent
        }
    }

    var files: [File] = []
    /// Every folder in the tree, empty ones included, as relative paths.
    var folders: [String] = []
    /// Items the local enumeration could not read: the upload must not pass over
    /// them in silence.
    var unreadableItems = 0

    func folderCreations(under parent: String) -> [FileStationFolderCreation] {
        folders.map { relative in
            var components = relative.split(separator: "/").map(String.init)
            let name = components.removeLast()
            let parentPath = ([parent] + components).joined(separator: "/")
            return FileStationFolderCreation(parentPath: parentPath, name: name)
        }
    }

    /// The enumeration reads the disk: it stays off the MainActor.
    @concurrent
    static func make(from urls: [URL]) async -> FinderUploadPlan {
        var plan = FinderUploadPlan()
        let fileManager = FileManager.default
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                plan.unreadableItems += 1
                continue
            }
            if isDirectory.boolValue {
                plan.add(directory: url, fileManager: fileManager)
            } else {
                plan.files.append(File(source: url, relativeFolder: nil))
            }
        }
        plan.files.sort {
            ($0.relativeFolder ?? "", $0.source.lastPathComponent)
                < ($1.relativeFolder ?? "", $1.source.lastPathComponent)
        }
        plan.folders.sort()
        return plan
    }

    private mutating func add(directory url: URL, fileManager: FileManager) {
        let root = url.lastPathComponent
        folders.append(root)
        var unreadable = 0
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: { _, _ in
                unreadable += 1
                return true
            }
        ) else {
            unreadableItems += 1
            return
        }
        let basePath = url.path + "/"
        for case let descendant as URL in enumerator {
            // Finder metadata with no value on the NAS.
            if descendant.lastPathComponent == ".DS_Store" { continue }
            guard descendant.path.hasPrefix(basePath) else {
                unreadable += 1
                continue
            }
            let relative = root + "/" + descendant.path.dropFirst(basePath.count)
            if (try? descendant.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                folders.append(relative)
            } else {
                let parent = relative.split(separator: "/").dropLast().joined(separator: "/")
                files.append(File(source: descendant, relativeFolder: parent))
            }
        }
        unreadableItems += unreadable
    }
}
