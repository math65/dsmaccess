//
//  ReadOnlyTextView.swift
//  dsmaccess
//
//  A read-only text area that grows with its content. SwiftUI has no such control on macOS:
//  a `TextEditor` bound to a constant still takes keystrokes, and disabling it puts it out of
//  reach of both VoiceOver and the keyboard.
//

import AppKit
import SwiftUI

struct ReadOnlyTextView: NSViewRepresentable {
    let text: String
    /// What the area holds, named for VoiceOver.
    let label: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.string = text
        apply(label, to: scrollView, textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        apply(label, to: scrollView, textView)
        guard textView.string != text else { return }

        let wasAtBottom = isScrolledToBottom(scrollView)
        if text.hasPrefix(textView.string) {
            // Appending rather than replacing keeps the selection, and keeps VoiceOver where
            // the reader left it while output keeps arriving.
            let addition = String(text.dropFirst(textView.string.count))
            textView.textStorage?.append(NSAttributedString(
                string: addition,
                attributes: [.font: textView.font as Any, .foregroundColor: NSColor.textColor]
            ))
        } else {
            textView.string = text
        }
        if wasAtBottom {
            textView.scrollToEndOfDocument(nil)
        }
    }

    private func apply(_ label: String, to scrollView: NSScrollView, _ textView: NSTextView) {
        textView.setAccessibilityLabel(label)
        scrollView.setAccessibilityLabel(label)
    }

    private func isScrolledToBottom(_ scrollView: NSScrollView) -> Bool {
        let visible = scrollView.contentView.documentVisibleRect
        let height = scrollView.documentView?.bounds.height ?? 0
        return visible.maxY >= height - 4
    }
}
