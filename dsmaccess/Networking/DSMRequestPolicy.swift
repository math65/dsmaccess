//
//  DSMRequestPolicy.swift
//  dsmaccess
//
//  Retry policy for DSM requests.
//

enum DSMRequestPolicy: Equatable, Sendable {
    case singleAttempt
    case idempotent
}
