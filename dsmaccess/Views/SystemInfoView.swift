//
//  SystemInfoView.swift
//  dsmaccess
//
//  Informations générales et ressources du NAS.
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
                ModuleLoadingView("Chargement des informations…")
                    .accessibilityFocused($focusContent)
            } else if let error = vm.errorMessage, vm.info == nil {
                ModuleErrorView(message: error) {
                    Task { await load() }
                }
                .accessibilityFocused($focusContent)
            } else if let info = vm.info {
                Form {
                    Section("Système") {
                        LabeledContent("Modèle", value: info.model)
                        LabeledContent("Numéro de série", value: info.serial)
                        LabeledContent("Version DSM", value: info.versionString)
                        LabeledContent("Mémoire vive", value: vm.ramText)
                        LabeledContent("Temps de fonctionnement", value: vm.uptimeText)
                        LabeledContent("Température", value: vm.temperatureText)
                    }

                    ResourceMonitorView(session: session)
                }
                .formStyle(.grouped)
                .accessibilityFocused($focusContent)
            }
        }
        .navigationTitle("Votre NAS")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await load() }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .help("Actualiser les informations du NAS")
            }
        }
        .task { await load() }
    }

    private func load() async {
        focusContent = true
        await vm.load()
        guard !Task.isCancelled else { return }
        focusContent = true
    }
}
