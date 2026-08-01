//
//  LabeledField.swift
//  dsmaccess
//
//  Text field with a visible label above it. The decorative label is hidden from
//  VoiceOver (the field itself carries the accessibility label), to avoid it being
//  read twice.
//

import SwiftUI

struct LabeledField<Content: View>: View {
    // LocalizedStringKey so that the label (displayed AND used as the accessibility
    // label) is translated automatically through the String Catalog.
    let label: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.readableSecondary)
                .accessibilityHidden(true)
            content
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(label)
        }
    }
}
