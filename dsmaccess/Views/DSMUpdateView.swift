//
//  DSMUpdateView.swift
//  dsmaccess
//
//  Mise à jour manuelle de DSM depuis un fichier .pat.
//

import SwiftUI
import UniformTypeIdentifiers

struct DSMUpdateView: View {
    @State private var viewModel: DSMUpdateViewModel
    @State private var showsFileImporter = false
    @State private var showsConfirmation = false
    @State private var operationTask: Task<Void, Never>?
    @AccessibilityFocusState private var focusContent: Bool
    @AccessibilityFocusState private var focusWarning: Bool

    init(session: SessionStore) {
        _viewModel = State(initialValue: DSMUpdateViewModel(session: session))
    }

    var body: some View {
        content
            .navigationTitle("Mise à jour de DSM")
            .toolbar {
                ToolbarItem {
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        Label("Actualiser", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isBusy)
                    .help("Relire la version installée sur le NAS")
                }
            }
            .fileImporter(
                isPresented: $showsFileImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                handleSelection(result)
            }
            .sheet(isPresented: $showsConfirmation) {
                DSMUpdateConfirmationSheet(
                    currentVersion: viewModel.currentVersion,
                    fileName: viewModel.selectedFile?.lastPathComponent ?? "",
                    preCheck: viewModel.preCheck
                ) {
                    startUpgrade()
                }
            }
            .task { await load() }
            .onDisappear { operationTask?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ModuleLoadingView("Lecture de la version installée…")
                .accessibilityFocused($focusContent)
        } else if let errorMessage = viewModel.errorMessage {
            ModuleErrorView(message: errorMessage) {
                Task { await load() }
            }
            .accessibilityFocused($focusContent)
        } else {
            Form {
                Section {
                    Text("Cette fonction est une première version, publiée sans avoir pu être essayée sur un NAS qui attendait une mise à jour. Vérifiez que vous disposez d’une sauvegarde et signalez ce que vous observez.")
                        .font(.callout)
                        .foregroundStyle(.readableOrange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityFocused($focusContent)
                }

                Section("NAS") {
                    LabeledContent("Modèle") { Text(viewModel.modelName ?? "—") }
                    LabeledContent("Version installée") { Text(viewModel.currentVersion ?? "—") }
                        .labeledContentStyle(.readable)
                }

                Section("Fichier de mise à jour") {
                    Text(viewModel.statusText)
                        .foregroundStyle(.readableSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Choisir un fichier .pat…") { showsFileImporter = true }
                        .disabled(viewModel.isBusy)
                        .help("Choisir le fichier de mise à jour téléchargé depuis Synology")
                    if viewModel.selectedFile != nil {
                        Button("Envoyer au NAS et vérifier") { uploadAndCheck() }
                            .disabled(viewModel.isBusy || viewModel.stage == .awaitingConfirmation)
                            .help("Envoyer le fichier puis demander au NAS ce qu’il en pense")
                    }
                }

                if viewModel.stage == .uploading, let fraction = viewModel.transferProgress?.fractionCompleted {
                    Section("Envoi") {
                        ProgressView(value: fraction)
                            .accessibilityLabel("Envoi du fichier au NAS")
                            .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
                    }
                }

                if let preCheck = viewModel.preCheck {
                    Section("Ce que le NAS annonce") {
                        Text(warningText(for: preCheck))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityFocused($focusWarning)
                        Button("Installer et redémarrer le NAS…") { showsConfirmation = true }
                            .disabled(viewModel.isBusy)
                            .help("Lire les conséquences puis lancer l’installation")
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    /// Le contenu du contrôle préalable n'a pas pu être mesuré sur un vrai NAS : quand DSM
    /// répond dans une forme inconnue, l'écran le dit au lieu de laisser croire qu'il n'y a
    /// aucune conséquence.
    private func warningText(_ preCheck: DSMUpgradePreCheck) -> String { warningText(for: preCheck) }

    private func warningText(for preCheck: DSMUpgradePreCheck) -> String {
        guard preCheck.isUnderstood else {
            return String(
                localized: "Le NAS a accepté le fichier, mais l’app n’a pas su lire le détail de sa réponse. Ouvrez DSM pour vérifier les conséquences avant d’installer."
            )
        }
        guard !preCheck.unsupportedPackages.isEmpty else {
            return String(localized: "Le NAS n’annonce aucun paquet abandonné par cette mise à jour.")
        }
        let liste = preCheck.unsupportedPackages.formatted(.list(type: .and))
        return String(localized: "Ces paquets ne seront plus pris en charge après la mise à jour : \(liste).")
    }

    private func load() async {
        VoiceOver.announce(
            String(localized: "Lecture de la version installée…"),
            category: .progress,
            priority: .low
        )
        await viewModel.load()
        guard !Task.isCancelled else { return }
        await VoiceOver.restoreFocusIfCapturedByToolbar { focusContent = true }
        VoiceOver.announce(
            viewModel.summary,
            category: viewModel.errorMessage == nil ? .result : .error
        )
    }

    private func handleSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.pathExtension.caseInsensitiveCompare("pat") == .orderedSame else {
                viewModel.errorMessage = String(
                    localized: "Ce fichier n’est pas une mise à jour DSM. Choisissez un fichier .pat."
                )
                VoiceOver.announce(viewModel.errorMessage ?? "", category: .error, priority: .high)
                return
            }
            viewModel.selectFile(url)
            VoiceOver.announce(viewModel.statusText, category: .result)
        case .failure(let error):
            guard (error as? CocoaError)?.code != .userCancelled else { return }
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func uploadAndCheck() {
        guard operationTask == nil else { return }
        VoiceOver.announce(
            String(localized: "Envoi du fichier au NAS."),
            category: .progress,
            priority: .high
        )
        operationTask = Task {
            let outcome = await viewModel.uploadAndCheck()
            operationTask = nil
            VoiceOver.announce(outcome, priority: .high)
            if case .success = outcome { focusWarning = true }
        }
    }

    private func startUpgrade() {
        guard operationTask == nil else { return }
        VoiceOver.announce(
            String(localized: "Installation lancée. Le NAS va redémarrer."),
            category: .progress,
            priority: .high
        )
        operationTask = Task {
            let outcome = await viewModel.startUpgrade()
            operationTask = nil
            VoiceOver.announce(outcome, priority: .high)
        }
    }
}

/// Dernier point d'arrêt avant une opération qui coupe le NAS pendant une vingtaine de
/// minutes : les conséquences sont énoncées, et la case doit être cochée pour continuer.
private struct DSMUpdateConfirmationSheet: View {
    let currentVersion: String?
    let fileName: String
    let preCheck: DSMUpgradePreCheck?
    let onConfirm: () -> Void

    @State private var hasUnderstood = false
    @AccessibilityFocusState private var focusTitle: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Installer cette mise à jour ?")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusTitle)

            Text(consequences)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("J’ai pris connaissance des conséquences", isOn: $hasUnderstood)
                .help("À cocher pour pouvoir lancer l’installation")

            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("Ne pas installer cette mise à jour")
                Button("Installer et redémarrer") {
                    onConfirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasUnderstood)
                .help("Lancer l’installation et redémarrer le NAS")
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            focusTitle = true
            VoiceOver.announce(
                String(localized: "Installer cette mise à jour ?"),
                category: .navigation
            )
        }
    }

    private var consequences: String {
        let version = currentVersion ?? String(localized: "inconnue")
        let paquets = preCheck?.unsupportedPackages ?? []
        if paquets.isEmpty {
            return String(
                localized: "Le NAS passera de la version \(version) à celle du fichier \(fileName). L’installation dure 10 à 20 minutes, pendant lesquelles le NAS est inutilisable et tous ses services s’arrêtent. Il n’est pas possible de revenir à la version précédente."
            )
        }
        let liste = paquets.formatted(.list(type: .and))
        return String(
            localized: "Le NAS passera de la version \(version) à celle du fichier \(fileName). Ces paquets ne seront plus pris en charge : \(liste). L’installation dure 10 à 20 minutes, pendant lesquelles le NAS est inutilisable et tous ses services s’arrêtent. Il n’est pas possible de revenir à la version précédente."
        )
    }
}
