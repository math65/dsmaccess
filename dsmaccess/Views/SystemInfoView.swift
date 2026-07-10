//
//  SystemInfoView.swift
//  dsmaccess
//
//  Écran de contenu du MVP : affiche les infos système du NAS pour prouver que la
//  session fonctionne. Les paires libellé/valeur sont regroupées pour VoiceOver.
//

import SwiftUI

struct SystemInfoView: View {
    let session: SessionStore
    @State private var vm: SystemInfoViewModel
    @AccessibilityFocusState private var focusTitle: Bool

    init(session: SessionStore) {
        self.session = session
        _vm = State(initialValue: SystemInfoViewModel(session: session))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Votre NAS")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focusTitle)

                content

                Divider()

                ResourceMonitorView(session: session)
            }
            .padding(28)
            .frame(maxWidth: 500, alignment: .leading)
        }
        .task {
            focusTitle = true
            await vm.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Chargement des informations…")
                    .foregroundStyle(.secondary)
            }
        } else if let error = vm.errorMessage {
            VStack(alignment: .leading, spacing: 12) {
                Text(error)
                    .foregroundStyle(.red)
                Button("Réessayer") {
                    Task { await vm.load() }
                }
            }
        } else if let info = vm.info {
            VStack(alignment: .leading, spacing: 10) {
                row("Modèle", info.model)
                row("Numéro de série", info.serial)
                row("Version DSM", info.versionString)
                row("Mémoire vive", vm.ramText)
                row("Temps de fonctionnement", vm.uptimeText)
                row("Température", vm.temperatureText)
            }
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        // .combine fait lire à VoiceOver le libellé (localisé) puis la valeur en un seul geste.
        .accessibilityElement(children: .combine)
    }
}
