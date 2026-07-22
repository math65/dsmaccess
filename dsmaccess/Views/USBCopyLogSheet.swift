//
//  USBCopyLogSheet.swift
//  dsmaccess
//

import SwiftUI

struct USBCopyLogSheet: View {
    let load: (USBCopyLogFilter, Int, Int) async throws -> USBCopyLogPage

    private let pageSize = 200
    @State private var entries: [USBCopyLogEntry] = []
    @State private var totalCount = 0
    @State private var keyword = ""
    @State private var logType = USBCopyLogType.all
    @State private var usesDateRange = false
    @State private var fromDate = Date.now.addingTimeInterval(-604_800)
    @State private var toDate = Date.now
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AccessibilityFocusState private var contentFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Journal USB Copy")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding()

            Form {
                Section("Filtrer le journal") {
                    TextField("Rechercher dans le journal", text: $keyword)
                        .onSubmit { Task { await loadEntries() } }
                    Picker("Type d’événement", selection: $logType) {
                        ForEach(USBCopyLogType.allCases) { type in
                            Text(type.localizedName).tag(type)
                        }
                    }
                    Toggle("Limiter à une période", isOn: $usesDateRange)
                    if usesDateRange {
                        DatePicker("Depuis", selection: $fromDate, displayedComponents: .date)
                        DatePicker("Jusqu’à", selection: $toDate, displayedComponents: .date)
                    }
                    Button("Appliquer le filtre", systemImage: "line.3.horizontal.decrease.circle") {
                        Task { await loadEntries() }
                    }
                    .disabled(isLoading || (usesDateRange && fromDate > toDate))
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 230)

            Divider()
            if isLoading && entries.isEmpty {
                ModuleLoadingView("Chargement du journal USB Copy…")
                    .accessibilityFocused($contentFocused)
            } else if let errorMessage, entries.isEmpty {
                ModuleErrorView(message: errorMessage) { Task { await loadEntries() } }
                    .accessibilityFocused($errorFocused)
            } else if entries.isEmpty {
                EmptyModuleView(
                    title: "Aucune entrée de journal",
                    systemImage: "doc.text.magnifyingglass",
                    description: "Aucun événement ne correspond au filtre choisi."
                )
                .accessibilityFocused($contentFocused)
            } else {
                List {
                    ForEach(entries.indices, id: \.self) { index in
                        USBCopyLogRow(entry: entries[index])
                    }
                    if entries.count < totalCount {
                        Button("Charger plus d’entrées") {
                            Task { await loadEntries(reset: false) }
                        }
                        .disabled(isLoading)
                    }
                }
                .accessibilityLabel("Événements USB Copy")
                .accessibilityFocused($contentFocused)
            }

            Divider()
            HStack {
                Text("\(entries.count) entrées affichées sur \(totalCount)")
                    .foregroundStyle(.secondary)
                if isLoading && !entries.isEmpty {
                    ProgressView("Chargement du journal USB Copy…")
                        .controlSize(.small)
                }
                if let errorMessage, !entries.isEmpty {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityFocused($errorFocused)
                }
                Spacer()
                Button("Fermer", action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(minWidth: 760, minHeight: 680)
        .task {
            await loadEntries()
            guard !Task.isCancelled else { return }
            contentFocused = true
        }
    }

    private var filter: USBCopyLogFilter {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: toDate))?
            .addingTimeInterval(-1)
        return USBCopyLogFilter(
            descriptionIDs: USBCopyLogFilter.all.descriptionIDs,
            keyword: trimmedKeyword.isEmpty ? nil : trimmedKeyword,
            fromTimestamp: usesDateRange ? Int(calendar.startOfDay(for: fromDate).timeIntervalSince1970) : nil,
            toTimestamp: usesDateRange ? endOfDay.map { Int($0.timeIntervalSince1970) } : nil,
            logType: logType.rawValue
        )
    }

    private func loadEntries(reset: Bool = true) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        if reset {
            entries = []
            totalCount = 0
        }
        defer { isLoading = false }
        VoiceOver.announce(String(localized: "Chargement du journal USB Copy…"), category: .progress)
        do {
            let offset = reset ? 0 : entries.count
            let page = try await load(filter, offset, pageSize)
            guard !Task.isCancelled else { return }
            if reset {
                entries = page.logList
            } else {
                entries.append(contentsOf: page.logList)
            }
            totalCount = page.count
            VoiceOver.announce(
                String(localized: "\(page.logList.count) entrées de journal chargées"),
                category: .result
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            errorFocused = true
            VoiceOver.announce(errorMessage ?? "", category: .error, priority: .high)
        }
    }
}

private struct USBCopyLogRow: View {
    let entry: USBCopyLogEntry

    var body: some View {
        VStack(alignment: .leading) {
            Text(descriptionText)
            HStack {
                Text(logTypeName)
                Text(Date(timeIntervalSince1970: TimeInterval(entry.timestamp)), format: .dateTime)
                if let taskID = entry.taskID {
                    Text("Tâche \(taskID)")
                }
                if let error = errorText {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var logTypeName: String {
        USBCopyLogType(rawValue: entry.logType)?.localizedName ?? String(localized: "Non disponible")
    }

    private var descriptionText: String {
        let parameter = decodedParameter
        return switch entry.descriptionID {
        case 0: String(localized: "Tâche créée : \(parameter)")
        case 1: String(localized: "Tâche supprimée : \(parameter)")
        case 2: String(localized: "Tâche activée : \(parameter)")
        case 3: String(localized: "Tâche désactivée : \(parameter)")
        case 10: String(localized: "Nom de tâche modifié : \(parameter)")
        case 11: String(localized: "Réglages de tâche modifiés : \(parameter)")
        case 100: String(localized: "Tâche démarrée : \(parameter)")
        case 101: String(localized: "Tâche terminée : \(parameter)")
        case 102: String(localized: "Tâche annulée : \(parameter)")
        case 103: String(localized: "Échec de la tâche : \(parameter)")
        case 104: String(localized: "Rotation des versions : \(parameter)")
        case 105: String(localized: "Tâche terminée avec des erreurs : \(parameter)")
        case 1000: String(localized: "Erreur de fichier : \(parameter)")
        default: String(localized: "Événement USB Copy \(entry.descriptionID) : \(parameter)")
        }
    }

    private var decodedParameter: String {
        guard let raw = entry.descriptionParameter, !raw.isEmpty else {
            return String(localized: "sans détail")
        }
        guard let data = raw.data(using: .utf8) else { return raw }
        if let value = try? JSONDecoder().decode(String.self, from: data) { return value }
        if let values = try? JSONDecoder().decode([String].self, from: data) {
            return values.formatted(.list(type: .and))
        }
        return raw
    }

    private var errorText: String? {
        guard let raw = entry.error, !raw.isEmpty else { return nil }
        guard let code = Int(raw) else { return raw }
        guard code != 0 else { return nil }
        return switch code {
        case -1: String(localized: "annulation")
        case -4: String(localized: "paramètre invalide")
        case -9: String(localized: "permission refusée")
        case -10: String(localized: "erreur de fichier")
        case -11: String(localized: "fichier trop volumineux")
        case -12: String(localized: "nom de fichier incompatible")
        case -13: String(localized: "dossier démonté")
        case -14: String(localized: "reprise impossible")
        case -15: String(localized: "fichier source absent")
        case -16: String(localized: "fichier de destination existant")
        case -17: String(localized: "conflit de destination")
        case -18: String(localized: "type de destination incompatible")
        case -19: String(localized: "destination pleine")
        case -20: String(localized: "racine de destination absente")
        case -21: String(localized: "dossier parent de destination absent")
        case -22: String(localized: "racine source absente")
        case -24: String(localized: "conflit avec le dossier des versions")
        default: String(localized: "code d’erreur \(code)")
        }
    }
}
