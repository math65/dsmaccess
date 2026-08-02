//
//  FileStationFavoritesView.swift
//  dsmaccess
//
//  Accessible management of the whole set of File Station favorites.
//

import SwiftUI

struct FileStationFavoritesView: View {
    @Bindable var vm: FileBrowserViewModel
    let open: (FileStationFavorite) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var status = FileStationFavoriteStatus.all
    @State private var editingFavorite: FileStationFavorite?
    @State private var pendingRemoval: FileStationFavorite?
    @State private var confirmsBrokenCleanup = false
    @State private var isMutating = false
    @State private var selection = Set<FileStationFavorite.ID>()
    @State private var operationError: String?
    @AccessibilityFocusState private var focusHeading: Bool
    @AccessibilityFocusState private var focusStatus: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 720, height: 540)
        .task(id: status) { await load() }
        .sheet(item: $editingFavorite) { favorite in
            NameEntrySheet(
                title: "favorites.rename.action",
                fieldLabel: "favorites.rename.field.label",
                confirmLabel: "common.button.rename",
                announcement: String(localized: "favorites.rename.title", defaultValue: "Rename favorite “\(favorite.name)”"),
                initialName: favorite.name
            ) { name in
                Task { await rename(favorite, to: name) }
            }
        }
        .alert(
            "favorites.remove.confirm",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            )
        ) {
            Button("favorites.remove.button", role: .destructive) {
                if let favorite = pendingRemoval {
                    pendingRemoval = nil
                    Task { await remove(favorite) }
                }
            }
            Button("common.button.cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            if let favorite = pendingRemoval {
                Text(
                    String(
                        localized: "favorites.remove.confirm.description",
                        defaultValue: "“\(favorite.name)” will be removed from favorites. The folder and its contents will not be deleted."
                    )
                )
            }
        }
        .alert("favorites.clear_unavailable.confirm", isPresented: $confirmsBrokenCleanup) {
            Button("common.button.clear", role: .destructive) { Task { await clearBrokenFavorites() } }
            Button("common.button.cancel", role: .cancel) {}
        } message: {
            Text("favorites.clear_unavailable.confirm.description")
        }
    }

    private var header: some View {
        HStack {
            Text("favorites.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)
            Spacer()
            if vm.isLoadingManagedFavorites || isMutating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("favorites.operation.progress")
            }
            Button("common.button.close", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isMutating)
        }
        .padding()
    }

    private var controls: some View {
        HStack {
            Picker("common.button.show", selection: $status) {
                ForEach(FileStationFavoriteStatus.allCases, id: \.self) { value in
                    Text(value.localizedTitle).tag(value)
                }
            }
            .frame(maxWidth: 280)
            Spacer()
            Button("common.button.refresh", systemImage: "arrow.clockwise") { Task { await load() } }
                .disabled(vm.isLoadingManagedFavorites || isMutating)
                .help("favorites.refresh.label")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if let operationError {
            VStack(spacing: 12) {
                Text(operationError)
                    .foregroundStyle(.readableRed)
                    .multilineTextAlignment(.center)
                    .accessibilityFocused($focusStatus)
                Button("common.button.dismiss_error") { self.operationError = nil }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.isLoadingManagedFavorites && vm.managedFavorites.isEmpty {
            ModuleLoadingView("favorites.loading")
                .accessibilityFocused($focusStatus)
        } else if let error = vm.managedFavoritesError {
            VStack(spacing: 12) {
                Text(error)
                    .foregroundStyle(.readableRed)
                    .multilineTextAlignment(.center)
                Button("common.button.retry") { Task { await load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityFocused($focusStatus)
        } else if vm.managedFavorites.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: "star",
                description: Text("favorites.empty.description")
            )
            .accessibilityFocused($focusStatus)
        } else {
            // No sortable columns here: the row order is the favorite order that DSM stores,
            // and it is what the move up/down buttons act on. Sorting by name would leave
            // those buttons acting on an order the user can no longer see.
            Table(vm.managedFavorites, selection: $selection) {
                TableColumn("common.column.name") { favorite in
                    Text(favorite.name)
                }
                TableColumn("common.column.location") { favorite in
                    Text(favorite.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                TableColumn("common.column.state") { favorite in
                    Text(favorite.statusDescription)
                        .foregroundStyle(favorite.isAvailable ? .readableSecondary : .readableOrange)
                }
            }
            .accessibilityLabel("common.action.file_station_favorites")
            .contextMenu(forSelectionType: FileStationFavorite.ID.self) { ids in
                if let favorite = vm.managedFavorites.first(where: { ids.contains($0.id) }) {
                    favoriteActions(favorite)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("favorites.clear_unavailable.button", role: .destructive) {
                confirmsBrokenCleanup = true
            }
            .disabled(isMutating || vm.isLoadingManagedFavorites)
            .help("favorites.clear_unavailable.hint")
            Spacer()
            Button("common.button.close", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isMutating)
        }
        .padding()
    }

    /// Move up and move down stay in the menu even when they cannot apply, disabled rather
    /// than removed: a menu whose entries come and go leaves the user unable to learn it.
    @ViewBuilder
    private func favoriteActions(_ favorite: FileStationFavorite) -> some View {
        Button("common.button.open") {
            open(favorite)
            dismiss()
        }
        .disabled(!favorite.isAvailable || isMutating)

        Button("common.button.rename") { editingFavorite = favorite }
            .disabled(isMutating)

        Button("common.button.move_up") {
            Task { await move(favorite, by: -1) }
        }
        .disabled(!canMove(favorite, by: -1) || isMutating)

        Button("common.button.move_down") {
            Task { await move(favorite, by: 1) }
        }
        .disabled(!canMove(favorite, by: 1) || isMutating)

        Divider()

        Button("favorites.remove.button", role: .destructive) {
            pendingRemoval = favorite
        }
        .disabled(isMutating)
    }

    private var emptyTitle: LocalizedStringKey {
        switch status {
        case .all: "common.empty.favorites"
        case .valid: "favorites.available.empty"
        case .broken: "favorites.unavailable.empty"
        }
    }

    private func canMove(_ favorite: FileStationFavorite, by offset: Int) -> Bool {
        guard status == .all,
              let index = vm.managedFavorites.firstIndex(where: { $0.id == favorite.id }) else {
            return false
        }
        return vm.managedFavorites.indices.contains(index + offset)
    }

    private func load() async {
        operationError = nil
        await vm.loadManagedFavorites(status: status)
        guard !Task.isCancelled else { return }
        if let error = vm.managedFavoritesError {
            focusStatus = true
            VoiceOver.announce(error, category: .error, priority: .high)
        } else {
            focusHeading = true
            VoiceOver.announce(
                String(localized: "favorites.count", defaultValue: "Favorites: \(vm.managedFavorites.count)"),
                category: .result
            )
        }
    }

    private func rename(_ favorite: FileStationFavorite, to name: String) async {
        await mutate { await vm.renameFavorite(favorite, to: name) }
    }

    private func remove(_ favorite: FileStationFavorite) async {
        await mutate { await vm.removeFavorite(favorite) }
    }

    private func clearBrokenFavorites() async {
        await mutate { await vm.clearBrokenFavorites() }
    }

    private func move(_ favorite: FileStationFavorite, by offset: Int) async {
        await mutate { await vm.moveFavorite(favorite, by: offset) }
    }

    private func mutate(
        _ operation: @escaping @MainActor () async -> DSMOperationOutcome
    ) async {
        isMutating = true
        operationError = nil
        defer { isMutating = false }
        let outcome = await operation()
        if case .failure(let message) = outcome {
            operationError = message
            focusStatus = true
        }
        VoiceOver.announce(outcome, priority: .high)
    }
}

private extension FileStationFavoriteStatus {
    var localizedTitle: String {
        switch self {
        case .all: String(localized: "favorites.filter.all")
        case .valid: String(localized: "favorites.section.available")
        case .broken: String(localized: "favorites.section.unavailable")
        }
    }
}
