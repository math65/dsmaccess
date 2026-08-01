//
//  DockerImageSearchSheet.swift
//  dsmaccess
//
//  Searching the active registry for an image, picking one of its versions, and downloading
//  it. Replaces guessing a repository name and a tag by hand.
//

import SwiftUI

struct DockerImageSearchSheet: View {
    let vm: DockerRegistriesViewModel
    /// The Images tab owns the download and its progress; this sheet only chooses what to pull.
    let images: DockerImagesViewModel

    @State private var keyword = ""
    @State private var order = [KeyPathComparator(\DockerRegistrySearchResult.name)]
    @State private var selection: DockerRegistrySearchResult.ID?
    @State private var tags: [DockerImageTag] = []
    @State private var selectedTag: String?
    @State private var isLoadingTags = false
    @State private var tagErrorMessage: String?
    @State private var tagGeneration = 0
    @AccessibilityFocusState private var keywordFocused: Bool
    @AccessibilityFocusState private var resultsFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                searchField
                Divider()
                results
                Divider()
                versionBar
            }
            .navigationTitle("containers.registry.search.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.button.close", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(images.isPulling)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .task {
            await Task.yield()
            keywordFocused = true
        }
        .onDisappear { vm.clearSearch() }
    }

    // The field queries the registry on submit rather than filtering a local list, so it is a
    // text field with an explicit action and not `.searchable`.
    private var searchField: some View {
        HStack(spacing: 8) {
            TextField("containers.registry.search.field", text: $keyword)
                .textFieldStyle(.roundedBorder)
                .accessibilityHint("containers.registry.search.field.hint")
                .accessibilityFocused($keywordFocused)
                .onSubmit { Task { await search() } }
                .disabled(vm.isSearching || images.isPulling)

            Button("containers.registry.search.action") { Task { await search() } }
                .keyboardShortcut(.defaultAction)
                .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty || vm.isSearching || images.isPulling)

            if vm.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("containers.registry.search.in_progress")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var results: some View {
        if vm.results.isEmpty {
            VStack(spacing: 8) {
                Text(vm.searchSummary ?? String(localized: "containers.registry.search.prompt"))
                    .foregroundStyle(vm.searchFailed ? AnyShapeStyle(.readableRed) : AnyShapeStyle(.readableSecondary))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .accessibilityFocused($resultsFocused)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(vm.results.sorted(using: order), selection: $selection, sortOrder: $order) {
                TableColumn("common.column.name", value: \.name)
                TableColumn("containers.registry.search.column.description", value: \.descriptionText)
                TableColumn("containers.registry.search.column.downloads", value: \.sortableDownloads) { result in
                    Text(result.downloads.map { $0.formatted(.number.notation(.compactName)) } ?? "—")
                }
                TableColumn("containers.registry.search.column.stars", value: \.sortableStars) { result in
                    Text(result.starCount.map { $0.formatted() } ?? "—")
                }
                TableColumn("containers.registry.search.column.official", value: \.sortableOfficial) { result in
                    Text(result.isOfficial
                         ? String(localized: "containers.registry.search.official")
                         : "—")
                }
            }
            .accessibilityLabel("containers.registry.search.results")
            .accessibilityFocused($resultsFocused)
            .onChange(of: selection) { _, _ in
                Task { await loadTags() }
            }
        }
    }

    private var versionBar: some View {
        HStack(spacing: 8) {
            if let selectedResult {
                if isLoadingTags {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("containers.registry.tags.loading")
                    Text("containers.registry.tags.loading")
                        .font(.caption)
                        .foregroundStyle(.readableSecondary)
                } else if let tagErrorMessage {
                    Label(tagErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.readableRed)
                } else if !tags.isEmpty {
                    Picker("containers.registry.tags.version", selection: $selectedTag) {
                        ForEach(tags) { tag in
                            Text(tag.tag).tag(String?.some(tag.tag))
                        }
                    }
                    .frame(maxWidth: 260)
                    .disabled(images.isPulling)

                    Button("containers.registry.search.download") {
                        Task { await download(selectedResult) }
                    }
                    .disabled(selectedTag == nil || images.isPulling)
                    .help("containers.registry.search.download.hint")
                }
            } else {
                Text("containers.registry.search.select_prompt")
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
            }

            Spacer()

            if images.isPulling, let description = images.pullDescription {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                    .accessibilityLabel(description)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var selectedResult: DockerRegistrySearchResult? {
        vm.results.first { $0.id == selection }
    }

    private func search() async {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        selection = nil
        resetTags()
        VoiceOver.announce(
            String(localized: "containers.registry.search.in_progress"),
            category: .progress
        )
        await vm.search(keyword: trimmed)
        guard !Task.isCancelled else { return }
        if let summary = vm.searchSummary {
            VoiceOver.announce(summary, category: vm.searchFailed ? .error : .result, priority: .high)
        }
        resultsFocused = true
    }

    private func resetTags() {
        tagGeneration += 1
        tags = []
        selectedTag = nil
        tagErrorMessage = nil
        isLoadingTags = false
    }

    /// Loads the versions of the selected image. An older answer must not land on a newer
    /// selection, hence the generation check.
    private func loadTags() async {
        guard let selectedResult else {
            resetTags()
            return
        }
        resetTags()
        let generation = tagGeneration
        isLoadingTags = true
        defer { if generation == tagGeneration { isLoadingTags = false } }

        do {
            let loaded = try await vm.tags(for: selectedResult.name)
            guard generation == tagGeneration else { return }
            tags = loaded
            // “latest” is what a user wants nine times out of ten, and DSM preselects it too.
            selectedTag = loaded.first { $0.tag == "latest" }?.tag ?? loaded.first?.tag
            if loaded.isEmpty {
                tagErrorMessage = String(localized: "containers.registry.tags.none")
            }
        } catch {
            guard generation == tagGeneration, !DSMError.isCancellation(error) else { return }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            tagErrorMessage = String(
                localized: "containers.registry.tags.failed",
                defaultValue: "Could not read the versions of \(selectedResult.name): \(reason)"
            )
        }
    }

    private func download(_ result: DockerRegistrySearchResult) async {
        guard let selectedTag else { return }
        VoiceOver.announce(
            String(
                localized: "containers.registry.search.download.in_progress",
                defaultValue: "Downloading \(result.name):\(selectedTag)"
            ),
            category: .progress
        )
        let outcome = await images.pull(repository: result.name, tag: selectedTag)
        VoiceOver.announce(outcome, priority: .high)
        if case .success = outcome {
            dismiss()
        }
    }
}

extension DockerRegistrySearchResult {
    var sortableDownloads: Int64 { downloads ?? 0 }
    var sortableStars: Int { starCount ?? 0 }
    /// `TableColumn` sorts on Comparable values, which Bool is not.
    var sortableOfficial: Int { isOfficial ? 1 : 0 }
}
