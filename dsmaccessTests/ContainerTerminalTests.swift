import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct ContainerTerminalMessageTests {
    @Test func decodesTheAnswersMeasuredOnDSM74() throws {
        #expect(event(#"["enter",true]"#) == .entered(true))
        #expect(event(#"["create",true]"#) == .created(true))
        #expect(event(#"["attach",1503]"#) == .attached(code: 1503))
        #expect(event(#"["data","bonjour\r\n"]"#) == .output("bonjour\r\n"))
        #expect(event(#"["close",1501]"#) == .closed(code: 1501))
        #expect(event(#"["title","abc","sh"]"#) == .renamed(id: "abc", title: "sh"))
    }

    /// The list arrives flattened, and always opens with the container itself under its own
    /// name: that entry is its main process, not a shell opened from the app.
    @Test func readsTheFlattenedSessionList() throws {
        let decoded = event(#"["list",["web","web","abc123","sh"]]"#)

        #expect(decoded == .sessions([
            ContainerTerminalTTY(id: "web", title: "web"),
            ContainerTerminalTTY(id: "abc123", title: "sh"),
        ]))
    }

    @Test func ignoresEventsItDoesNotKnow() throws {
        #expect(ContainerTerminalSocket.event(from: .string(#"["monitor"]"#)) == nil)
        #expect(ContainerTerminalSocket.event(from: .string("not json")) == nil)
    }

    /// A refused handshake reaches URLSession as a bad server response, which tells the user
    /// nothing. Measured cause: DSM only accepts the terminal through an address it knows.
    @Test func explainsARefusedHandshakeByTheAddress() {
        let message = ContainerTerminalSocket.description(
            of: URLError(.badServerResponse),
            host: "nas.example.net"
        )

        #expect(message.contains("nas.example.net"))
        #expect(message != URLError(.badServerResponse).localizedDescription)
    }

    @Test func keepsTheSystemWordingForOtherFailures() {
        let message = ContainerTerminalSocket.description(
            of: URLError(.notConnectedToInternet),
            host: "nas.example.net"
        )

        #expect(message == URLError(.notConnectedToInternet).localizedDescription)
    }

    private func event(_ payload: String) -> ContainerTerminalEvent? {
        ContainerTerminalSocket.event(from: .string(payload))
    }
}

@MainActor
struct QuickConnectTerminalAddressTests {
    /// QuickConnect's local route encodes the address into the host, and DSM refuses the
    /// terminal there while accepting it on the plain name.
    @Test func dropsTheAddressPrefixOfALocalQuickConnectRoute() {
        let endpoint = DSMEndpoint(
            useHTTPS: true,
            host: "192-168-1-15.MATH65.direct.quickconnect.to",
            port: 20281
        )

        #expect(endpoint.quickConnectHostWithoutLocalPrefix == "MATH65.direct.quickconnect.to")
    }

    @Test func leavesEveryOtherAddressAlone() {
        let hosts = [
            "MATH65.direct.quickconnect.to",
            "cloud.example.net",
            "192.168.1.15",
            "nas.local",
            "math65.quickconnect.to",
            // A name that merely looks the part: no encoded address in front.
            "office.MATH65.direct.quickconnect.to",
        ]

        for host in hosts {
            let endpoint = DSMEndpoint(useHTTPS: true, host: host, port: 5001)
            #expect(endpoint.quickConnectHostWithoutLocalPrefix == nil, "\(host)")
        }
    }
}

@MainActor
struct TerminalPreparationTests {
    /// The preparation ends on the marker the shell prints. The shell also echoes the command
    /// that asks for it — echoing is what the command turns off — so a command containing the
    /// marker in plain sight would end the preparation before the shell had answered anything.
    @Test func writesACommandWhoseOwnEchoCannotEndThePreparation() {
        let command = ContainerTerminalViewModel.readyCommand

        #expect(!command.contains(ContainerTerminalViewModel.readyMarker))
        #expect(command.contains("stty -echo"))
    }
}

@MainActor
struct TerminalOutputBufferTests {
    @Test func stripsTheColourAndCursorSequencesOfARealShell() {
        var buffer = TerminalOutputBuffer()

        buffer.append("\u{1B}[1;34mbin\u{1B}[m    \u{1B}[1;34metc\u{1B}[m\r\n/ # \u{1B}[6n")

        #expect(buffer.text == "bin    etc\n/ # ")
    }

    /// A sequence can be cut in two by the stream: the state has to survive the chunk.
    @Test func stripsASequenceSplitAcrossTwoChunks() {
        var buffer = TerminalOutputBuffer()

        buffer.append("start\u{1B}[1")
        buffer.append(";34mend")

        #expect(buffer.text == "startend")
    }

    @Test func treatsCarriageReturnAsTheOtherHalfOfALineEnding() {
        var buffer = TerminalOutputBuffer()

        let completed = buffer.append("first\r\nsecond\r\n")

        #expect(buffer.text == "first\nsecond")
        #expect(completed == ["first", "second"])
    }

    /// On its own, a carriage return rewrites the line — a progress counter, not a new line.
    @Test func rewritesTheLineOnALoneCarriageReturn() {
        var buffer = TerminalOutputBuffer()

        buffer.append("50 %\r100 %")

        #expect(buffer.text == "100 %")
    }

    @Test func appliesBackspaces() {
        var buffer = TerminalOutputBuffer()

        buffer.append("lst\u{08}s")

        #expect(buffer.text == "lss")
    }

    @Test func dropsTheWindowTitleSequence() {
        var buffer = TerminalOutputBuffer()

        buffer.append("\u{1B}]0;root@host\u{07}prompt")

        #expect(buffer.text == "prompt")
    }

    @Test func keepsOnlyTheLastLinesSoALongSessionStaysBounded() {
        var buffer = TerminalOutputBuffer(maximumLines: 3)

        buffer.append("a\nb\nc\nd\ne\n")

        #expect(buffer.text == "c\nd\ne")
    }

    @Test func writesItsOwnLineBelowWhatTheShellLeftUnfinished() {
        var buffer = TerminalOutputBuffer()
        buffer.append("/ # ")

        buffer.appendOwnLine("Vous : ls")

        #expect(buffer.text == "/ # \nVous : ls")
    }

    @Test func opensOneBlankLineBetweenBlocksAndNeverTwo() {
        var buffer = TerminalOutputBuffer()
        buffer.append("done\n")

        buffer.startNewBlock()
        buffer.startNewBlock()

        #expect(buffer.text == "done\n")
    }

    @Test func opensNoBlankLineOnAnEmptyBuffer() {
        var buffer = TerminalOutputBuffer()

        buffer.startNewBlock()

        #expect(buffer.isEmpty)
    }

    @Test func reportsOnlyTheLinesAChunkCompleted() {
        var buffer = TerminalOutputBuffer()

        let completed = buffer.append("done\nin progress")

        #expect(completed == ["done"])
        #expect(buffer.text == "done\nin progress")
    }
}
