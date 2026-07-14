//
//  DownloadStationView.swift
//  dsmaccess
//
//  Gestion native des tâches Download Station.
//

import SwiftUI

struct DownloadStationView: View {
    @State private var viewModel: DownloadStationViewModel
    @State private var selection: Set<String> = []
    @State private var searchText = ""
    @State private var showCreateSheet = false
    @State private var showDeleteConfirmation = false
    @State private var autoRefresh = true
    @AccessibilityFocusState private var contentFocused: Bool

    init(session: SessionStore) {
        _viewModel = State(initialValue: DownloadStationViewModel(session: session))
    }

    var body: some View {
        content
            .navigationTitle("Download Station")
            .searchable(text: $searchText, prompt: "Rechercher un téléchargement")
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { statusBar }
            .task { await load() }
            .task(id: autoRefresh) { await refreshPeriodically() }
            .sheet(isPresented: $showCreateSheet) {
                CreateDownloadSheet { uri, destination in
                    Task { await announce(viewModel.create(uri: uri, destination: destination)) }
                }
            }
            .confirmationDialog(
                "Supprimer les téléchargements sélectionnés ?",
                isPresented: $showDeleteConfirmation
            ) {
                Button("Supprimer", role: .destructive) {
                    Task { await deleteSelection(forceComplete: false) }
                }
                Button("Supprimer et marquer comme terminés", role: .destructive) {
                    Task { await deleteSelection(forceComplete: true) }
                }
                Button("Annuler", role: .cancel) { }
            } message: {
                Text("Les tâches seront retirées de Download Station. Les fichiers déjà téléchargés seront conservés.")
            }
            .onChange(of: viewModel.tasks) {
                selection.formIntersection(Set(viewModel.tasks.map(\.id)))
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.tasks.isEmpty {
            ModuleLoadingView("Chargement des téléchargements…")
                .accessibilityFocused($contentFocused)
        } else if let errorMessage = viewModel.errorMessage {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($contentFocused)
        } else if filteredTasks.isEmpty {
            EmptyModuleView(
                title: searchText.isEmpty ? "Aucun téléchargement" : "Aucun résultat",
                systemImage: "arrow.down.circle",
                description: searchText.isEmpty
                    ? "Ajoutez une adresse pour démarrer un téléchargement."
                    : "Modifiez votre recherche et réessayez."
            )
            .accessibilityFocused($contentFocused)
        } else {
            List(filteredTasks, selection: $selection) { task in
                taskRow(task)
                    .tag(task.id)
                    .contextMenu { taskActions(task) }
            }
            .accessibilityLabel("Téléchargements")
            .accessibilityFocused($contentFocused)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                showCreateSheet = true
            } label: {
                Label("Ajouter un téléchargement", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .help("Ajouter un téléchargement")

            Button {
                Task { await pauseSelection() }
            } label: {
                Label("Mettre en pause", systemImage: "pause")
            }
            .disabled(!selectionCanPause || selectionIsBusy)
            .help("Mettre les téléchargements sélectionnés en pause")

            Button {
                Task { await resumeSelection() }
            } label: {
                Label("Reprendre", systemImage: "play")
            }
            .disabled(!selectionCanResume || selectionIsBusy)
            .help("Reprendre les téléchargements sélectionnés")

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
            .disabled(selection.isEmpty || selectionIsBusy)
            .help("Supprimer les téléchargements sélectionnés")

            Menu {
                Toggle("Actualisation automatique", isOn: $autoRefresh)
            } label: {
                Label("Options d’actualisation", systemImage: "ellipsis.circle")
            }
            .help("Options d’actualisation")

            Button {
                Task { await load() }
            } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            .help("Actualiser les téléchargements")
        }
    }

    private func taskRow(_ task: DownloadTask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: task.status))
                .foregroundStyle(color(for: task.status))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(task.title).fontWeight(.medium)
                    Spacer()
                    Text(statusText(task.status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let progress = task.progress {
                    ProgressView(value: progress)
                        .accessibilityLabel("Progression de \(task.title)")
                        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
                }
                HStack {
                    Text(sizeSummary(task))
                    Spacer()
                    if task.downloadSpeed > 0 {
                        Label(speed(task.downloadSpeed), systemImage: "arrow.down")
                    }
                    if task.uploadSpeed > 0 {
                        Label(speed(task.uploadSpeed), systemImage: "arrow.up")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(taskAccessibilityLabel(task))
        .accessibilityAction(named: "Mettre en pause") {
            guard task.canPause else { return }
            Task { await pause(ids: [task.id]) }
        }
        .accessibilityAction(named: "Reprendre") {
            guard task.canResume else { return }
            Task { await resume(ids: [task.id]) }
        }
    }

    @ViewBuilder
    private func taskActions(_ task: DownloadTask) -> some View {
        if task.canPause {
            Button("Mettre en pause") { Task { await pause(ids: [task.id]) } }
        }
        if task.canResume {
            Button("Reprendre") { Task { await resume(ids: [task.id]) } }
        }
        Divider()
        Button("Supprimer…", role: .destructive) {
            selection = [task.id]
            showDeleteConfirmation = true
        }
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text(viewModel.summary)
            Spacer()
            if let statistic = viewModel.statistic {
                Label(speed(statistic.downloadSpeed), systemImage: "arrow.down")
                    .accessibilityLabel("Débit descendant : \(speed(statistic.downloadSpeed))")
                Label(speed(statistic.uploadSpeed), systemImage: "arrow.up")
                    .accessibilityLabel("Débit montant : \(speed(statistic.uploadSpeed))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    private var filteredTasks: [DownloadTask] {
        guard !searchText.isEmpty else { return viewModel.tasks }
        return viewModel.tasks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.status.localizedCaseInsensitiveContains(searchText)
                || ($0.additional?.detail?.destination?.localizedCaseInsensitiveContains(searchText) == true)
        }
    }

    private var selectedTasks: [DownloadTask] {
        viewModel.tasks.filter { selection.contains($0.id) }
    }

    private var selectionCanPause: Bool { selectedTasks.contains(where: \.canPause) }
    private var selectionCanResume: Bool { selectedTasks.contains(where: \.canResume) }
    private var selectionIsBusy: Bool { !viewModel.busyIDs.isDisjoint(with: selection) }

    private func load() async {
        contentFocused = true
        await viewModel.load()
        guard !Task.isCancelled else { return }
        contentFocused = true
        VoiceOver.announce(viewModel.summary)
    }

    private func refreshPeriodically() async {
        guard autoRefresh else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, autoRefresh else { return }
            await viewModel.load(silently: true)
        }
    }

    private func pauseSelection() async {
        await pause(ids: Set(selectedTasks.filter(\.canPause).map(\.id)))
    }

    private func resumeSelection() async {
        await resume(ids: Set(selectedTasks.filter(\.canResume).map(\.id)))
    }

    private func pause(ids: Set<String>) async {
        await announce(viewModel.pause(ids: ids))
    }

    private func resume(ids: Set<String>) async {
        await announce(viewModel.resume(ids: ids))
    }

    private func deleteSelection(forceComplete: Bool) async {
        let ids = selection
        selection.removeAll()
        await announce(viewModel.delete(ids: ids, forceComplete: forceComplete))
    }

    private func announce(_ message: String) async {
        VoiceOver.announce(message, priority: .high)
    }

    private func sizeSummary(_ task: DownloadTask) -> String {
        let downloaded = task.downloaded.formatted(.byteCount(style: .file))
        guard task.size > 0 else { return downloaded }
        return String(localized: "\(downloaded) sur \(task.size.formatted(.byteCount(style: .file)))")
    }

    private func speed(_ bytesPerSecond: Int64) -> String {
        String(localized: "\(bytesPerSecond.formatted(.byteCount(style: .file))) par seconde")
    }

    private func taskAccessibilityLabel(_ task: DownloadTask) -> String {
        var parts = [task.title, statusText(task.status), sizeSummary(task)]
        if task.downloadSpeed > 0 { parts.append(String(localized: "réception \(speed(task.downloadSpeed))")) }
        if task.uploadSpeed > 0 { parts.append(String(localized: "envoi \(speed(task.uploadSpeed))")) }
        return parts.formatted(.list(type: .and))
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "waiting": String(localized: "En attente")
        case "downloading": String(localized: "Téléchargement")
        case "paused": String(localized: "En pause")
        case "finishing": String(localized: "Finalisation")
        case "finished": String(localized: "Terminé")
        case "hash_checking": String(localized: "Vérification")
        case "seeding": String(localized: "Partage")
        case "filehosting_waiting": String(localized: "En attente de l’hébergeur")
        case "extracting": String(localized: "Extraction")
        case "error": String(localized: "Erreur")
        default: String(localized: "État inconnu")
        }
    }

    private func icon(for status: String) -> String {
        switch status {
        case "downloading", "finishing": "arrow.down.circle.fill"
        case "seeding": "arrow.up.circle.fill"
        case "finished": "checkmark.circle.fill"
        case "paused": "pause.circle.fill"
        case "error": "exclamationmark.triangle.fill"
        default: "clock"
        }
    }

    private func color(for status: String) -> Color {
        switch status {
        case "finished": .green
        case "error": .red
        case "paused": .secondary
        default: .accentColor
        }
    }
}

private struct CreateDownloadSheet: View {
    let onCreate: (_ uri: String, _ destination: String?) -> Void

    @State private var uri = ""
    @State private var destination = ""
    @FocusState private var uriFocused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmedURI: String { uri.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ajouter un téléchargement")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            LabeledField(label: "Adresse du fichier") {
                TextField("https://exemple.com/fichier", text: $uri)
                    .focused($uriFocused)
                    .accessibilityFocused($accessibilityFocused)
                    .onSubmit(create)
            }
            LabeledField(label: "Dossier de destination (facultatif)") {
                TextField("downloads", text: $destination)
            }
            Text("Laissez le dossier vide pour utiliser la destination par défaut de Download Station.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Ajouter", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedURI.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            uriFocused = true
            accessibilityFocused = true
            VoiceOver.announce(String(localized: "Ajouter un téléchargement"))
        }
    }

    private func create() {
        guard !trimmedURI.isEmpty else { return }
        let destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        onCreate(trimmedURI, destination.isEmpty ? nil : destination)
        dismiss()
    }
}
