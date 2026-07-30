//
//  DSMOperationOutcome.swift
//  dsmaccess
//
//  Result of a user action sent to the NAS.
//

import Foundation

enum DSMOperationOutcome: Equatable, Sendable {
    case success(String)
    case failure(String)
    case cancelled
}
