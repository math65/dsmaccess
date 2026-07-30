//
//  PackageInstallTask.swift
//  dsmaccess
//
//  Identifier of an installation tracked by Package Center.
//

import Foundation

struct PackageInstallTask: nonisolated Decodable, Sendable {
    let taskID: String

    private enum CodingKeys: String, CodingKey {
        case taskID = "taskid"
        case alternateTaskID = "task_id"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let taskID = container.flexString(.taskID)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !taskID.isEmpty {
            self.taskID = taskID
        } else {
            let alternateTaskID = try container.requiredFlexString(.alternateTaskID)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !alternateTaskID.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .alternateTaskID,
                    in: container,
                    debugDescription: "Package installation task identifier is empty."
                )
            }
            taskID = alternateTaskID
        }
    }
}
