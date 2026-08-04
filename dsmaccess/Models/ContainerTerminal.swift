//
//  ContainerTerminal.swift
//  dsmaccess
//
//  Values of Container Manager's terminal service. It is the one part of the module that
//  does not speak the `entry.cgi` API: it keeps a WebSocket open on `/docker/ws` and
//  exchanges JSON arrays whose first element names the event.
//

import Foundation

/// Which side of the terminal service a socket talks to. The role is fixed when entering a
/// container and cannot be changed afterwards. Measured on DSM 7.4: only a monitor socket is
/// told which sessions exist, and a session opened from a terminal socket is unusable — it
/// appears in no list, `attach` refuses it with `attachFailed`, and `delete` never removes it.
enum ContainerTerminalRole: String, Sendable {
    case monitor
    case terminal
}

/// A shell session running inside a container. The container itself always holds the first
/// entry, under its own name: that one is its main process, not a shell opened from here.
struct ContainerTerminalTTY: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
}

/// What the terminal service reports on a socket.
enum ContainerTerminalEvent: Sendable, Equatable {
    /// Answer to `enter`: false when the container refuses the session.
    case entered(Bool)
    /// Full list of the sessions of the container, sent again after every change.
    case sessions([ContainerTerminalTTY])
    /// Answer to `create`. True only means the session was registered: a command that does
    /// not exist in the image is only found out when attaching to it.
    case created(Bool)
    case attached(code: Int)
    case output(String)
    case renamed(id: String, title: String)
    /// The session ended on the NAS side; the socket closes right after.
    case closed(code: Int)
    case failed(String)
    /// The NAS turned the handshake down before authenticating anything, which it does when
    /// the address it was reached by is not one it knows as its own.
    case addressRefused(String)
}

/// Terminal service outcomes, read from the package's own error table and measured against
/// the NAS. They travel in `attach` answers and in `close` events, never in an API envelope.
nonisolated enum ContainerTerminalCode {
    /// Another client holds the session; attaching again with `force` takes it over.
    static let clientAttach = 1500
    /// The command behind the session ended — a normal exit, or an image without that shell.
    static let execEnded = 1501
    static let unknown = 1502
    static let attachSucceeded = 1503
    static let attachedElsewhere = 1504
    /// The session cannot be attached to. A session opened by a terminal socket ends here.
    static let attachFailed = 1505
}
