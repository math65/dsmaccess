//
//  SystemInfoView.swift
//  dsmaccess
//
//  General information and resources of the NAS.
//

import SwiftUI

struct SystemInfoView: View {
    @State private var vm: SystemInfoViewModel
    @AccessibilityFocusState private var focusContent: Bool

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
        _vm = State(initialValue: SystemInfoViewModel(session: session))
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.info == nil {
                ModuleLoadingView("common.status.loading_information")
                    .accessibilityFocused($focusContent)
            } else if let error = vm.errorMessage, vm.info == nil {
                ModuleErrorView(message: error) {
                    Task { await load() }
                }
                .accessibilityFocused($focusContent)
            } else if let info = vm.info {
                Form {
                    Section("common.label.system") {
                        LabeledContent("common.label.model", value: info.model)
                        LabeledContent("system_info.serial_number.label", value: info.serial)
                        LabeledContent("system_info.dsm_version.label", value: info.versionString)
                        LabeledContent("system_info.memory.label", value: vm.ramText)
                        LabeledContent("common.label.uptime", value: vm.uptimeText)
                        LabeledContent("common.column.temperature", value: vm.temperatureText)
                    }
                }
                .formStyle(.grouped)
                .accessibilityFocused($focusContent)
            } else {
                ModuleLoadingView("common.status.loading_information")
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await load() }
                } label: {
                    Label("common.button.refresh", systemImage: "arrow.clockwise")
                }
                .help("system_info.refresh.action")
            }
        }
        .task { await load(restoresInitialFocus: true) }
    }

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "common.status.loading_information"),
            category: .progress,
            priority: .low
        )
        await vm.load()
        guard !Task.isCancelled else { return }
        if let modelName = vm.info?.model {
            session.updateActiveProfileDefaultName(to: modelName)
        }
        if restoresInitialFocus {
            await VoiceOver.restoreFocusIfCapturedByToolbar { focusContent = true }
        }
        VoiceOver.announce(
            vm.summary,
            category: vm.errorMessage == nil ? .result : .error
        )
    }
}
