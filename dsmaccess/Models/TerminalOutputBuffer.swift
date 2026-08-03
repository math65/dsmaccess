//
//  TerminalOutputBuffer.swift
//  dsmaccess
//
//  Turns the raw stream of a container shell into text that reads line by line. What arrives
//  is meant for a terminal emulator: colour and cursor escapes, carriage returns that rewrite
//  the line in place, backspaces. Read aloud as is, it is unusable.
//

import Foundation

nonisolated struct TerminalOutputBuffer {
    /// Beyond this, the oldest lines are dropped: a session that prints for long enough would
    /// otherwise grow until the window stops answering.
    private let maximumLines: Int
    private var lines: [String] = []
    private var currentLine = ""
    private var mode = Mode.text
    /// A carriage return only rewrites the line when something follows it; on its own before a
    /// line feed it is just the other half of a CRLF.
    private var awaitingCarriageReturn = false

    init(maximumLines: Int = 2000) {
        self.maximumLines = maximumLines
    }

    /// Everything received so far, oldest line first.
    var text: String {
        guard !currentLine.isEmpty else { return lines.joined(separator: "\n") }
        return (lines + [currentLine]).joined(separator: "\n")
    }

    var isEmpty: Bool { lines.isEmpty && currentLine.isEmpty }

    /// Adds a chunk of the stream and returns the lines it completed, which is what is worth
    /// announcing: the line still being written is likely to be rewritten.
    @discardableResult
    mutating func append(_ chunk: String) -> [String] {
        var completed: [String] = []
        // Scalar by scalar, not character by character: Swift reads a CRLF as one character,
        // and the two halves of a line ending mean different things here.
        for scalar in chunk.unicodeScalars {
            switch mode {
            case .text:
                appendInText(scalar, completing: &completed)
            case .escape:
                switch scalar {
                case "[": mode = .csi
                case "]": mode = .osc
                default: mode = .text
                }
            case .csi:
                // The sequence runs until its final byte, which is what carries its meaning.
                if (0x40...0x7E).contains(scalar.value) {
                    mode = .text
                }
            case .osc:
                if scalar == "\u{1B}" {
                    mode = .oscEscape
                } else if scalar == "\u{07}" {
                    mode = .text
                }
            case .oscEscape:
                mode = scalar == "\\" ? .text : .osc
            }
        }
        return completed
    }

    mutating func removeAll() {
        lines.removeAll()
        currentLine = ""
        mode = .text
        awaitingCarriageReturn = false
    }

    private mutating func appendInText(
        _ scalar: Unicode.Scalar,
        completing completed: inout [String]
    ) {
        if awaitingCarriageReturn {
            awaitingCarriageReturn = false
            if scalar != "\n" {
                currentLine = ""
            }
        }

        switch scalar {
        case "\u{1B}":
            mode = .escape
        case "\r":
            awaitingCarriageReturn = true
        case "\n":
            completed.append(currentLine)
            lines.append(currentLine)
            currentLine = ""
            if lines.count > maximumLines {
                lines.removeFirst(lines.count - maximumLines)
            }
        case "\u{08}":
            if !currentLine.isEmpty { currentLine.removeLast() }
        case "\u{07}", "\0":
            break
        default:
            currentLine.unicodeScalars.append(scalar)
        }
    }

    private enum Mode {
        case text
        /// After an escape, waiting for what kind of sequence follows.
        case escape
        /// Cursor and colour sequences, `ESC [ … final byte`.
        case csi
        /// Window title and the like, `ESC ] … BEL` or `ESC ] … ESC \`.
        case osc
        case oscEscape
    }
}
