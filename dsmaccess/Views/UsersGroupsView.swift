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
    @State private var userToConfigure: DSMUser?
    @State private var groupToConfigure: DSMGroup?
    @State private var operationFailure: String?
    @AccessibilityFocusState private var contentFocused: Bool

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
        _viewModel = State(initialValue: UsersGroupsViewModel(session: session))
    }

    var body: some View {
        content
            .searchable(text: $searchText, prompt: "Rechercher un compte ou un groupe")
            .toolbar { toolbar }
            .task { await load(restoresInitialFocus: true) }
            .sheet(isPresented: $showCreateUser) {
                CreateUserSheet(
                    groups: viewModel.groups,
                    passwordPolicy: viewModel.passwordPolicy
                ) { draft in
                    let outcome = await viewModel.createUser(draft)
                    // Un échec reste dans la feuille, qui conserve la saisie ; seule la
                    // réussite est annoncée ici, une fois la feuille refermée.
                    if case .success = outcome { await announce(outcome) }
                    return outcome
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupSheet { draft in
                    Task { await announce(viewModel.createGroup(draft)) }
                }
            }
            .sheet(item: $userToConfigure) { user in
                SharePermissionsSheet(holder: .user(user.name), session: session) { outcome in
                    Task { await announce(outcome) }
                }
            }
            .sheet(item: $groupToConfigure) { group in
                SharePermissionsSheet(holder: .group(group.name), session: session) { outcome in
                    Task { await announce(outcome) }
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
            .alert(
                "Erreur",
                isPresented: Binding(
                    get: { operationFailure != nil },
                    set: { if !$0 { operationFailure = nil } }
                )
            ) {
                Button("OK", role: .cancel) { }
                    .help("Fermer le message d’erreur")
            } message: {
                if let operationFailure {
                    Text(operationFailure)
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
            .accessibilityLabel("Utilisateurs")
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
                        Button("Permissions…") { groupToConfigure = group }
                            .help("Modifier les permissions de ce groupe sur les dossiers partagés")
                        Divider()
                        Button("Supprimer le groupe…", role: .destructive) { groupToDelete = group }
                            .disabled(isProtected(group))
                            .help("Supprimer ce groupe")
                    }
            }
            .accessibilityLabel("Groupes")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Menu {
                Button("Nouvel utilisateur…") { showCreateUser = true }
                    .help("Créer un nouvel utilisateur")
                Button("Nouveau groupe…") { showCreateGroup = true }
                    .help("Créer un nouveau groupe")
            } label: {
                Label("Ajouter", systemImage: "plus")
            }
            .help("Ajouter un utilisateur ou un groupe")
        }

        if selectedTab == .users, let user = selectedUser {
            ToolbarItem {
                Button {
                    userToConfigure = user
                } label: {
                    Label("Permissions", systemImage: "folder.badge.person.crop")
                }
                .help("Modifier les permissions de ce compte sur les dossiers partagés")
            }
            ToolbarItem {
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
        }

        if selectedTab == .groups, let group = selectedGroup {
            ToolbarItem {
                Button {
                    groupToConfigure = group
                } label: {
                    Label("Permissions", systemImage: "folder.badge.person.crop")
                }
                .help("Modifier les permissions de ce groupe sur les dossiers partagés")
            }
        }

        ToolbarItem {
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
                    Text(detail).font(.caption).foregroundStyle(.readableSecondary)
                }
            }
            Spacer()
            Text(user.isDisabled ? "Désactivé" : "Actif")
                .font(.caption)
                .foregroundStyle(user.isDisabled ? Color.readableSecondary : Color.readableGreen)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(userAccessibilityLabel(user))
        .accessibilityActions {
            Button("Permissions…") { userToConfigure = user }
                .help("Modifier les permissions de ce compte sur les dossiers partagés")
            if !isProtected(user), !isBusy(user) {
                Button(user.isDisabled ? "Activer" : "Désactiver") {
                    Task { await announce(viewModel.setUser(user, disabled: !user.isDisabled)) }
                }
                .help(user.isDisabled ? "Activer cet utilisateur" : "Désactiver cet utilisateur")
                Button("Supprimer l’utilisateur…", role: .destructive) {
                    userToDelete = user
                }
                .help("Supprimer cet utilisateur")
            }
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
                    .foregroundStyle(.readableSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.name), \(groupSummary(group))")
        .accessibilityActions {
            Button("Permissions…") { groupToConfigure = group }
                .help("Modifier les permissions de ce groupe sur les dossiers partagés")
            if !isProtected(group) {
                Button("Supprimer le groupe…", role: .destructive) {
                    groupToDelete = group
                }
                .help("Supprimer ce groupe")
            }
        }
    }

    @ViewBuilder
    private func userActions(_ user: DSMUser) -> some View {
        Button("Permissions…") { userToConfigure = user }
            .help("Modifier les permissions de ce compte sur les dossiers partagés")
        Divider()
        Button(user.isDisabled ? "Activer" : "Désactiver") {
            Task { await announce(viewModel.setUser(user, disabled: !user.isDisabled)) }
        }
        .disabled(isProtected(user) || isBusy(user))
        .help(user.isDisabled ? "Activer cet utilisateur" : "Désactiver cet utilisateur")
        Divider()
        Button("Supprimer l’utilisateur…", role: .destructive) { userToDelete = user }
            .disabled(isProtected(user) || isBusy(user))
            .help("Supprimer cet utilisateur")
    }

    private var filteredUsers: [DSMUser] {
        guard !searchText.isEmpty else { return viewModel.users }
        return viewModel.users.filter {
            $0.name.localizedStandardContains(searchText)
                || ($0.email?.localizedStandardContains(searchText) == true)
                || ($0.description?.localizedStandardContains(searchText) == true)
                || $0.groups.contains { $0.localizedStandardContains(searchText) }
        }
    }

    private var filteredGroups: [DSMGroup] {
        guard !searchText.isEmpty else { return viewModel.groups }
        return viewModel.groups.filter {
            $0.name.localizedStandardContains(searchText)
                || ($0.description?.localizedStandardContains(searchText) == true)
                || $0.members.contains { $0.localizedStandardContains(searchText) }
        }
    }

    private var selectedUser: DSMUser? {
        viewModel.users.first { $0.id == selectedUserID }
    }

    private var selectedGroup: DSMGroup? {
        viewModel.groups.first { $0.id == selectedGroupID }
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

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "Chargement des utilisateurs et groupes…"),
            category: .progress,
            priority: .low
        )
        await viewModel.load()
        guard !Task.isCancelled else { return }
        if restoresInitialFocus {
            await VoiceOver.restoreFocusIfCapturedByToolbar { contentFocused = true }
        }
        VoiceOver.announce(
            viewModel.summary,
            category: viewModel.errorMessage == nil ? .result : .error
        )
    }

    private func announce(_ outcome: DSMOperationOutcome) async {
        // Un échec s'affiche dans une alerte, que VoiceOver lit de lui-même ; une annonce
        // en plus ferait double narration.
        if case .failure(let message) = outcome {
            operationFailure = message
        } else {
            VoiceOver.announce(outcome, priority: .high)
        }
    }
}

private struct CreateUserSheet: View {
    let groups: [DSMGroup]
    let passwordPolicy: DSMPasswordPolicy?
    let onCreate: (DSMUserDraft) async -> DSMOperationOutcome

    @State private var name = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var description = ""
    @State private var email = ""
    @State private var selectedGroups: Set<String> = ["users"]
    @State private var revealsPassword = false
    @State private var isCreating = false
    @State private var failureMessage: String?
    @FocusState private var nameFocused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool
    @AccessibilityFocusState private var failureFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var passwordsMatch: Bool { !password.isEmpty && password == passwordConfirmation }
    private var canCreate: Bool { !trimmedName.isEmpty && passwordsMatch && !isCreating }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Compte") {
                    TextField("Nom d’utilisateur", text: $name)
                        .focused($nameFocused)
                        .accessibilityFocused($accessibilityFocused)
                        .help("Nom du nouvel utilisateur")
                    if revealsPassword {
                        TextField("Mot de passe", text: $password)
                            .help("Mot de passe du nouvel utilisateur")
                        TextField("Confirmer le mot de passe", text: $passwordConfirmation)
                            .help("Retaper le mot de passe du nouvel utilisateur")
                    } else {
                        SecureField("Mot de passe", text: $password)
                            .help("Mot de passe du nouvel utilisateur")
                        SecureField("Confirmer le mot de passe", text: $passwordConfirmation)
                            .help("Retaper le mot de passe du nouvel utilisateur")
                    }
                    Toggle("Afficher le mot de passe", isOn: $revealsPassword)
                        .help("Afficher le mot de passe en clair au lieu de le masquer")
                    HStack {
                        Button("Générer un mot de passe", action: generatePassword)
                            .help("Créer un mot de passe aléatoire conforme aux règles du NAS")
                        Button("Copier le mot de passe", action: copyPassword)
                            .disabled(password.isEmpty)
                            .help("Copier le mot de passe dans le presse-papiers")
                    }
                    if !passwordConfirmation.isEmpty && !passwordsMatch {
                        Text("Les mots de passe ne correspondent pas.")
                            .foregroundStyle(.readableRed)
                            .accessibilityLabel("Erreur : les mots de passe ne correspondent pas.")
                    }
                    if let passwordPolicy, passwordPolicy.hasRequirements {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Le NAS impose les règles suivantes :")
                            ForEach(passwordPolicy.requirements, id: \.self) { requirement in
                                Text(requirement)
                            }
                        }
                        .foregroundStyle(.readableSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    TextField("Adresse e-mail (facultative)", text: $email)
                        .help("Adresse e-mail facultative du nouvel utilisateur")
                    TextField("Description (facultative)", text: $description)
                        .help("Description facultative du nouvel utilisateur")
                }

                if !groups.isEmpty {
                    Section("Groupes") {
                        ForEach(groups) { group in
                            Toggle(group.name, isOn: groupBinding(group.name))
                                .help(String(localized: "Ajouter ou retirer l’utilisateur du groupe \(group.name)"))
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            if let failureMessage {
                Text(failureMessage)
                    .foregroundStyle(.readableRed)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityFocused($failureFocused)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            HStack {
                if isCreating {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Création en cours")
                }
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("Annuler la création de l’utilisateur")
                Button("Créer", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
                    .help("Créer l’utilisateur")
            }
            .padding()
        }
        .frame(width: 460, height: 580)
        .onAppear {
            nameFocused = true
            accessibilityFocused = true
            VoiceOver.announce(
                String(localized: "Créer un utilisateur"),
                category: .navigation
            )
        }
    }

    private func groupBinding(_ group: String) -> Binding<Bool> {
        Binding {
            selectedGroups.contains(group)
        } set: { selected in
            if selected { selectedGroups.insert(group) } else { selectedGroups.remove(group) }
        }
    }

    private func generatePassword() {
        let generated = DSMPasswordPolicy.generatedPassword(for: passwordPolicy)
        password = generated
        passwordConfirmation = generated
        // Sans affichage en clair, un mot de passe qu'on n'a pas choisi est illisible :
        // il faut pouvoir le relire avant de le transmettre.
        revealsPassword = true
        failureMessage = nil
        VoiceOver.announce(
            String(localized: "Mot de passe généré et affiché en clair."),
            category: .result
        )
    }

    private func copyPassword() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(password, forType: .string)
        VoiceOver.announce(String(localized: "Mot de passe copié."), category: .result)
    }

    private func create() {
        guard canCreate else { return }
        let draft = DSMUserDraft(
            name: trimmedName,
            password: password,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            groups: selectedGroups.sorted()
        )
        isCreating = true
        failureMessage = nil
        Task {
            let outcome = await onCreate(draft)
            isCreating = false
            switch outcome {
            case .success:
                dismiss()
            case .failure(let message):
                // La feuille reste ouverte : la saisie est conservée et corrigeable.
                failureMessage = message
                failureFocused = true
                VoiceOver.announce(message, category: .error, priority: .high)
            case .cancelled:
                break
            }
        }
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
                    .help("Nom du nouveau groupe")
            }
            LabeledField(label: "Description (facultative)") {
                TextField("Description (facultative)", text: $description)
                    .help("Description facultative du nouveau groupe")
            }
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("Annuler la création du groupe")
                Button("Créer") {
                    onCreate(DSMGroupDraft(name: trimmedName, description: description))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
                .help("Créer le groupe")
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            nameFocused = true
            accessibilityFocused = true
            VoiceOver.announce(
                String(localized: "Créer un groupe"),
                category: .navigation
            )
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
                    .help("Retaper le nom pour confirmer la suppression")
            }
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("Annuler la suppression")
                Button("Supprimer", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                .disabled(!confirmed)
                .help("Confirmer la suppression")
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            fieldFocused = true
            accessibilityFocused = true
            VoiceOver.announce(
                String(localized: "Confirmez la suppression en retapant le nom."),
                category: .navigation
            )
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
