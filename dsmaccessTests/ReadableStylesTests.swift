//
//  ReadableStylesTests.swift
//  dsmaccessTests
//
//  The readable* styles exist to clear the WCAG AA threshold where the system
//  colors do not. Nothing in the app fails visibly when they stop clearing it,
//  so the ratio is measured here.
//

import AppKit
import SwiftUI
import Testing

@testable import dsmaccess

@MainActor
struct ReadableStylesTests {
    /// AA for text below 18 pt, which is every size these styles are used at.
    private static let threshold = 4.5

    private static func luminance(_ color: NSColor) -> Double {
        guard let c = color.usingColorSpace(.sRGB) else { return 0 }
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.redComponent)
            + 0.7152 * channel(c.greenComponent)
            + 0.0722 * channel(c.blueComponent)
    }

    /// Flattens a translucent foreground over its background first: that is what
    /// reaches the screen, and `readableSecondary` is translucent by construction.
    private static func contrast(_ foreground: NSColor, on background: NSColor) -> Double {
        let opaque = background.blended(
            withFraction: foreground.alphaComponent,
            of: foreground.withAlphaComponent(1)
        ) ?? foreground
        let high = max(luminance(opaque), luminance(background))
        let low = min(luminance(opaque), luminance(background))
        return (high + 0.05) / (low + 0.05)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func readableStylesClearTheAAThreshold(appearance name: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: name))
        let styles: [(String, Color)] = [
            ("readableSecondary", .readableSecondary),
            ("readableGreen", .readableGreen),
            ("readableOrange", .readableOrange),
            ("readableRed", .readableRed),
        ]

        appearance.performAsCurrentDrawingAppearance {
            for (name, style) in styles {
                for background in [NSColor.windowBackgroundColor, .controlBackgroundColor] {
                    let ratio = Self.contrast(NSColor(style), on: background)
                    #expect(
                        ratio >= Self.threshold,
                        "\(name) : \(ratio.formatted(.number.precision(.fractionLength(2)))):1"
                    )
                }
            }
        }
    }
}
