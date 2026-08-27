//
//  TableValueText.swift
//  dsmaccess
//
//  A table cell value, or the dash that stands in for an absent one.
//

import SwiftUI

/// The dash is shown and never spoken. Read out on every row that lacks the value, it is pure
/// noise — "em dash" said aloud between two real values — and an absent value is better heard
/// as silence. The cell keeps its dash on screen, where it reads as a column that has no value
/// here rather than as one whose value failed to load.
struct TableValueText: View {
    /// The Finder's own placeholder, kept for every table of the app so that a cell without a
    /// value looks the same everywhere.
    static let absentValue = "--"

    private let value: String?

    init(_ value: String?) {
        self.value = value
    }

    var body: some View {
        if let value, !value.isEmpty {
            Text(value)
        } else {
            Text(verbatim: Self.absentValue)
                .accessibilityHidden(true)
        }
    }
}
