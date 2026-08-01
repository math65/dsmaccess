//
//  ReadableColors.swift
//  dsmaccess
//
//  Text colors with guaranteed contrast. The system greys and state colors
//  fail the AA threshold (4.5:1) at the small text sizes the app uses for
//  statuses and subtitles; these variants keep the visual hierarchy and the
//  semantics while staying readable for low-vision users, in both
//  appearances.
//

import AppKit
import SwiftUI

extension ShapeStyle where Self == Color {
    /// Replaces `.secondary` for text that carries information.
    static var readableSecondary: Color { Color.primary.opacity(0.8) }

    static var readableGreen: Color { .readable(.systemGreen) }
    static var readableOrange: Color { .readable(.systemOrange) }
    static var readableRed: Color { .readable(.systemRed) }
}

/// Reproduces the label/value layout of lists while guaranteeing contrast on
/// both sides, the system style rendering the label too light.
struct ReadableLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline) {
            configuration.label
            Spacer()
            configuration.content
                .foregroundStyle(.readableSecondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

extension LabeledContentStyle where Self == ReadableLabeledContentStyle {
    static var readable: ReadableLabeledContentStyle { ReadableLabeledContentStyle() }
}

private extension Color {
    /// The light-mode fraction is measured, not chosen: at 0.35 green reached
    /// only 3.93:1 and orange 4.07:1 against a table's alternating row colour,
    /// below the 4.5:1 AA threshold. `ReadableStylesTests` holds the measurement.
    static let lightBlendFraction: CGFloat = 0.45
    static let darkBlendFraction: CGFloat = 0.25

    static func readable(_ base: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let blend: NSColor? =
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? base.blended(withFraction: darkBlendFraction, of: .white)
                    : base.blended(withFraction: lightBlendFraction, of: .black)
            return blend ?? base
        })
    }
}
