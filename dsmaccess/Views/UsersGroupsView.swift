//
//  UsersGroupsView.swift
//  dsmaccess
//
//  Administration native des comptes locaux et groupes DSM.
//

import SwiftUI

struct UsersGroupsView: View {
    private enum Tab: Hashable {
        case users
        case groups
    }

    @State private var viewModel: UsersGroupsViewModel
    @State private var selectedTab = Tab.users
    @State private var selectedUserID: String?
    @State private var selectedGroupID: String?
    @State private var searchText = ""
    @State private var showCreateUser = false
    @State private var showCreateGroup = false
    @State private var userToDelete: DSMUser?
    @State private var groupToDelete: DSMGroup?
    @AccessibilityFocusState private var contentFocused: Bool

    init(session: SessionStore) {
        _viewModel = State(initialValue: UsersGroupsViewModel(session: session))
    }

    var body: some View {
        content
            .navigationTitle("Utilisateurs et groupes")
            .searchable(text: $searchText, prompt: "Rechercher un compte ou un groupe")
            .toolbar { toolbar }
            .task { await load() }
            .sheet(isPresented: $showCreateUser) {
                CreateUserSheet(groups: viewModel.groups) { draft in
                    Task { await announce(viewModel.createUser(draft)) }
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupSheet { draft in
                    Task { await announce(viewModel.createGroup(draft)) }
                }
            }
            .sheet(item: $userToDelete) { user in
                AccountDeletionSheet(name: user.name, kind: .user) {
                    Task { await announce(viewModel.deleteUser(user)) }
                }
            }
            .sheet(item: $groupToDelete) { group in
                AccountDeletionSheet(name: group.name, kind: .group) {
                    Task { await announce(viewModel.deleteGroup(group)) }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.users.isEmpty && viewModel.groups.isEmpty {
            ModuleLoadingView("Chargement des comptes…")
                .accessibilityFocused($contentFocused)
        } else if let errorMessage = viewModel.errorMessage {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($contentFocused)
        } else {
            TabView(selection: $selectedTab) {
                usersList
                    .tabItem { Label("Utilisateurs", systemImage: "person.2") }
                    .tag(Tab.users)
                groupsList
                    .tabItem { Label("Groupes", systemImage: "person.3") }
                    .tag(Tab.groups)
            }
            .accessibilityFocused($contentFocused)
        }
    }

    @ViewBuilder
    private var usersList: some View {
        if filteredUsers.isEmpty {
            EmptyModuleView(
                title: searchText.isEmpty ? "Aucun utilisateur" : "Aucun résultat",
                systemImage: "person.2",
                description: searchText.isEmpty
                    ? "Créez un utilisateur local pour lui donner accès au NAS."
                    : "Modifiez votre recherche et réessayez."
            )
        } else {
            List(filteredUsers, selection: $selectedUserID) { user in
                userRow(user)
                    .tag(user.id)
                    .contextMenu { userActions(user) }
            }
        }
    }

    @ViewBuilder
    private var groupsList: some View {
        if filteredGroups.isEmpty {
            EmptyModuleView(
                title: searchText.isEmpty ? "Aucun groupe" : "Aucun résultat",
                systemImage: "person.3",
                description: searchText.isEmpty
                    ? "Créez un groupe pour gérer les autorisations de plusieurs utilisateurs."
                    : "Modifiez votre recherche et réessayez."
            )
        } else {
            List(filteredGroups, selection: $selectedGroupID) { group in
                groupRow(group)
                    .tag(group.id)
                    .contextMenu {
                        Button("Supprimer le groupe…", role: .destructive) { groupToDelete = group }
                            .disabled(isProtected(group))
                    }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Button("Nouvel utilisateur…") { showCreateUser = true }
                Button("Nouveau groupe…") { showCreateGroup = true }
            } label: {
                Label("Ajouter", systemImage: "plus")
            }
            .help("Ajouter un utilisateur ou un groupe")

            if selectedTab == .users, let user = selectedUser {
                Button {
                    Task { await announce(viewModel.setUser(user, disabled: !user.isDisabled)) }
                } label: {
                    Label(
                        user.isDisabled ? "Activer l’utilisateur" : "Désactiver l’utilisateur",
                        systemImage: user.isDisabled ? "person.badge.checkmark" : "person.slash"
                    )
                }
                .disabled(isProtected(user) || isBusy(user))
                .help(user.isDisabled ? "Activer l’utilisateur" : "Désactiver l’utilisateur")
            }

            Button {
                Task { await load() }
            } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            .help("Actualiser les utilisateurs et groupes")
        }
    }

    private func userRow(_ user: DSMUser) -> some View {
        HStack(spacing: 12) {
            Image(systemName: user.isAdministrator ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                .foregroundStyle(user.isDisabled ? .secondary : .primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name).fontWeight(.medium)
                if let detail = userDetail(user) {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(user.isDisabled ? "Désactivé" : "Actif")
                .font(.caption)
                .foregroundStyle(user.isDisabled ? Color.secondary : Color.green)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(userAccessibilityLabel(user))
        .accessibilityAction(named: user.isDisabled ? "Activer" : "Désactiver") {
            guard !isProtected(user), !isBusy(user) else { return }
            Task { await announce(viewModel.setUser(user, disabled: !user.isDisabled)) }
        }
    }

    private func groupRow(_ group: DSMGroup) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).fontWeight(.medium)
                Text(groupSummary(group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.name), \(groupSummary(group))")
    }

    @ViewBuilder
    private func userActions(_ user: DSMUser) -> some View {
        Button(user.isDisabled ? "Activer" : "Désactiver") {
            Task { await announce(viewModel.setUser(user, disabled: !user.isDisabled)) }
        }
        .disabled(isProtected(user) || isBusy(user))
        Divider()
        Button("Supprimer l’utilisateur…", role: .destructive) { userToDelete = user }
            .disabled(isProtected(user) || isBusy(user))
    }

    private var filteredUsers: [DSMUser] {
        guard !searchText.isEmpty else { return viewModel.users }
        return viewModel.users.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.email?.localizedCaseInsensitiveContains(searchText) == true)
                || ($0.description?.localizedCaseInsensitiveContains(searchText) == true)
                || $0.groups.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var filteredGroups: [DSMGroup] {
        guard !searchText.isEmpty else { return viewModel.groups }
        return viewModel.groups.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.description?.localizedCaseInsensitiveContains(searchText) == true)
                || $0.members.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var selectedUser: DSMUser? {
        viewModel.users.first { $0.id == selectedUserID }
    }

    private func isProtected(_ user: DSMUser) -> Bool {
        ["admin", "guest"].contains(user.name.lowercased())
    }

    private func isProtected(_ group: DSMGroup) -> Bool {
        ["administrators", "users"].contains(group.name.lowercased())
    }

    private func isBusy(_ user: DSMUser) -> Bool {
        viewModel.busyItems.contains("user:\(user.name)")
    }

    private func userDetail(_ user: DSMUser) -> String? {
        if let email = user.email, !email.isEmpty { return email }
        if let description = user.description, !description.isEmpty { return description }
        if !user.groups.isEmpty { return user.groups.formatted(.list(type: .and)) }
        return nil
    }

    private func userAccessibilityLabel(_ user: DSMUser) -> String {
        var parts = [user.name, user.isDisabled ? String(localized: "désactivé") : String(localized: "actif")]
        if user.isAdministrator { parts.append(String(localized: "administrateur")) }
        if let detail = userDetail(user) { parts.append(detail) }
        return parts.formatted(.list(type: .and))
    }

    private func groupSummary(_ group: DSMGroup) -> String {
        var parts: [String] = []
        if let description = group.description, !description.isEmpty { parts.append(description) }
        parts.append(String(localized: "\(group.members.count) membres"))
        return parts.joined(separator: ", ")
    }

    private func load() async {
        contentFocused = true
        await viewModel.load()
        guard !Task.isCancelled else { return }
        contentFocused = true
        VoiceOver.announce(viewModel.summary)
    }

    private func announce(_ message: String) async {
        VoiceOver.announce(message, priority: .high)
    }
}

private struct CreateUserSheet: View {
    let groups: [DSMGroup]
    let onCreate: (DSMUserDraft) -> Void

    @State private var name = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var description = ""
    @State private var email = ""
    @State private var selectedGroups: Set<String> = ["users"]
    @FocusState private var nameFocused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var passwordsMatch: Bool { !password.isEmpty && password == passwordConfirmation }
    private var canCreate: Bool { !trimmedName.isEmpty && passwordsMatch }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Compte") {
                    TextField("Nom d’utilisateur", text: $name)
                        .focused($nameFocused)
                        .accessibilityFocused($accessibilityFocused)
                    SecureField("Mot de passe", text: $password)
                    SecureField("Confirmer le mot de passe", text: $passwordConfirmation)
                    if !passwordConfirmation.isEmpty && !passwordsMatch {
                        Text("Les mots de passe ne correspondent pas.")
                            .foregroundStyle(.red)
                            .accessibilityLabel("Erreur : les mots de passe ne correspondent pas.")
                    }
                    TextField("Adresse e-mail (facultative)", text: $email)
                    TextField("Description (facultative)", text: $description)
                }

                if !groups.isEmpty {
                    Section("Groupes") {
                        ForEach(groups) { group in
                            Toggle(group.name, isOn: groupBinding(group.name))
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Créer", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
            .padding()
        }
        .frame(width: 460, height: 520)
        .onAppear {
            nameFocused = true
            accessibilityFocused = true
            VoiceOver.announce(String(localized: "Créer un utilisateur"))
        }
    }

    private func groupBinding(_ group: String) -> Binding<Bool> {
        Binding {
            selectedGroups.contains(group)
        } set: { selected in
            if selected { selectedGroups.insert(group) } else { selectedGroups.remove(group) }
        }
    }

    private func create() {
        guard canCreate else { return }
        onCreate(
            DSMUserDraft(
                name: trimmedName,
                password: password,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                groups: selectedGroups.sorted()
            )
        )
        dismiss()
    }
}

private struct CreateGroupSheet: View {
    let onCreate: (DSMGroupDraft) -> Void

    @State private var name = ""
    @State private var description = ""
    @FocusState private var nameFocused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Créer un groupe")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            LabeledField(label: "Nom du groupe") {
                TextField("Nom du groupe", text: $name)
                    .focused($nameFocused)
                    .accessibilityFocused($accessibilityFocused)
            }
            LabeledField(label: "Description (facultative)") {
                TextField("Description (facultative)", text: $description)
            }
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Créer") {
                    onCreate(DSMGroupDraft(name: trimmedName, description: description))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            nameFocused = true
            accessibilityFocused = true
            VoiceOver.announce(String(localized: "Créer un groupe"))
        }
    }
}

private struct AccountDeletionSheet: View {
    enum Kind { case user, group }

    let name: String
    let kind: Kind
    let onDelete: () -> Void

    @State private var confirmation = ""
    @FocusState private var fieldFocused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var confirmed: Bool {
        confirmation.trimmingCharacters(in: .whitespacesAndNewlines) == name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(kind == .user ? "Supprimer cet utilisateur ?" : "Supprimer ce groupe ?")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(warning)
                .fixedSize(horizontal: false, vertical: true)
            LabeledField(label: "Retapez le nom pour confirmer") {
                TextField(name, text: $confirmation)
                    .focused($fieldFocused)
                    .accessibilityFocused($accessibilityFocused)
            }
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Supprimer", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                .disabled(!confirmed)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            fieldFocused = true
            accessibilityFocused = true
            VoiceOver.announce(String(localized: "Confirmez la suppression en retapant le nom."))
        }
    }

    private var warning: String {
        switch kind {
        case .user:
            String(localized: "Le compte « \(name) » sera supprimé. Son dossier personnel peut également devenir inaccessible selon les réglages du NAS.")
        case .group:
            String(localized: "Le groupe « \(name) » sera supprimé. Les autorisations accordées par ce groupe seront retirées.")
        }
    }
}
