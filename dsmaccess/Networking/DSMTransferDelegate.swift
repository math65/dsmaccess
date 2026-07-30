//
//  DSMTransferDelegate.swift
//  dsmaccess
//
//  Relay of URLSession progress to the interface's MainActor state.
//

import Foundation

final class DSMTransferDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: DSMTransferProgressHandler

    init(progress: @escaping DSMTransferProgressHandler) {
        self.progress = progress
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        report(completed: totalBytesSent, total: totalBytesExpectedToSend)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        report(completed: totalBytesWritten, total: totalBytesExpectedToWrite)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}

    nonisolated private func report(completed: Int64, total: Int64) {
        let update = DSMTransferProgress(
            completedBytes: completed,
            totalBytes: total > 0 ? total : nil
        )
        Task { @MainActor [progress] in
            progress(update)
        }
    }
}
