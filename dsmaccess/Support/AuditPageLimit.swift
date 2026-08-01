//
//  AuditPageLimit.swift
//  dsmaccess
//
//  Cap applied to list page sizes while the accessibility audit drives the app.
//

import Foundation

/// Returns `standard` in normal use. The opt-in accessibility audit interrogates
/// every element of a screen over one IPC round-trip each: a 1000-row log page
/// turns one screen into minutes of audit and starves the app's own network
/// requests until they time out. The audit launches the app with
/// DSMACCESS_AUDIT_PAGE_LIMIT set to keep pages small; the issues an audit can
/// find repeat on every row, so a short page finds the same ones.
func auditCappedPageLimit(_ standard: Int) -> Int {
    guard let raw = ProcessInfo.processInfo.environment["DSMACCESS_AUDIT_PAGE_LIMIT"],
          let cap = Int(raw), cap > 0 else { return standard }
    return min(standard, cap)
}
