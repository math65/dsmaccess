//
//  ModuleStatusViews.swift
//  dsmaccess
//
//  Standardized module states: loading, error and empty content.
//

import SwiftUI

struct ModuleLoadingView: View {
    let message: LocalizedStringKey

    init(_ message: LocalizedStringKey = "common.status.loading") {
        self.message = message
    }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct ModuleErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("module.error.title", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("common.button.retry", action: retry)
                .help("module.error.retry.button")
        }
    }
}

struct EmptyModuleView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        }
    }
}
