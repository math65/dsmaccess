//
//  DownloadTask.swift
//  dsmaccess
//
//  Modèles de Download Station. Les tailles et états restent tolérants entre versions.
//

import Foundation

struct DownloadTask: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let type: String?
    let username: String?
    let size: Int64
    let status: String
    let additional: Additional?

    struct Additional: nonisolated Decodable, Hashable, Sendable {
        let detail: Detail?
        let transfer: Transfer?
    }

    struct Detail: nonisolated Decodable, Hashable, Sendable {
        let destination: String?
        let uri: String?
        let createTime: Int64?
        let completedTime: Int64?

        enum CodingKeys: String, CodingKey {
            case destination, uri
            case createTime = "create_time"
            case completedTime = "completed_time"
        }

        nonisolated init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            destination = values.flexString(.destination)
            uri = values.flexString(.uri)
            createTime = values.flexInt64(.createTime)
            completedTime = values.flexInt64(.completedTime)
        }
    }

    struct Transfer: nonisolated Decodable, Hashable, Sendable {
        let downloaded: Int64
        let uploaded: Int64
        let downloadSpeed: Int64
        let uploadSpeed: Int64

        enum CodingKeys: String, CodingKey {
            case downloaded = "size_downloaded"
            case uploaded = "size_uploaded"
            case downloadSpeed = "speed_download"
            case uploadSpeed = "speed_upload"
        }

        nonisolated init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            downloaded = values.flexInt64(.downloaded) ?? 0
            uploaded = values.flexInt64(.uploaded) ?? 0
            downloadSpeed = values.flexInt64(.downloadSpeed) ?? 0
            uploadSpeed = values.flexInt64(.uploadSpeed) ?? 0
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, type, username, size, status, additional
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.requiredFlexString(.id)
        title = values.flexString(.title) ?? String(localized: "download.task.unnamed")
        type = values.flexString(.type)
        username = values.flexString(.username)
        size = values.flexInt64(.size) ?? 0
        status = values.flexString(.status) ?? "unknown"
        additional = try? values.decode(Additional.self, forKey: .additional)
    }

    var downloaded: Int64 { additional?.transfer?.downloaded ?? 0 }
    var downloadSpeed: Int64 { additional?.transfer?.downloadSpeed ?? 0 }
    var uploadSpeed: Int64 { additional?.transfer?.uploadSpeed ?? 0 }
    var progress: Double? {
        guard size > 0 else { return nil }
        return min(max(Double(downloaded) / Double(size), 0), 1)
    }

    var canPause: Bool { ["downloading", "waiting", "finishing", "seeding"].contains(status) }
    var canResume: Bool { ["paused", "error"].contains(status) }
}

struct DownloadTaskList: nonisolated Decodable, Sendable {
    let tasks: [DownloadTask]

    enum CodingKeys: String, CodingKey { case tasks }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try values.decodeIfPresent([DownloadTask].self, forKey: .tasks) ?? []
    }
}

struct DownloadStatistic: nonisolated Decodable, Sendable {
    let downloadSpeed: Int64
    let uploadSpeed: Int64

    enum CodingKeys: String, CodingKey {
        case downloadSpeed = "speed_download"
        case uploadSpeed = "speed_upload"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        downloadSpeed = values.flexInt64(.downloadSpeed) ?? 0
        uploadSpeed = values.flexInt64(.uploadSpeed) ?? 0
    }
}
