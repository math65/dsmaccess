//
//  UsersGroupsView.swift
//  dsmaccess
//
//  Native administration of DSM local accounts and groups, each tab a sortable table: an
//  account's state, its administrator flag and its groups each keep a column of their own
//  instead of being folded into one line read as a single sentence.
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
    @State private var userOrder = [KeyPathComparator(\DSMUser.name, order: .forward)]
    @State private var groupOrder = [KeyPathComparator(\DSMGroup.name, order: .forward)]
    @State private var searchText = ""
    @State private var showCreateUser = false
    @State private var showCreateGroup = false
    @State private var userToDelete: DSMUser?
    @State private var groupToDelete: DSMGroup?
    @State private var holderToConfigure: DSMPermissionHolder?
    /// Account whose permissions will open once the creation sheet is closed: two sheets
    /// cannot follow each other without waiting for the first one to close.
    @State private var userAwaitingPermissions: String?
    @State private var groupAwaitingPermissions: String?
    @State private var operationFailure: String?
    @AccessibilityFocusState private var contentFocused: Bool

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
        _viewModel = State(initialValue: UsersGroupsViewModel(session: session))
    }

    var body: some View {
        content
            .searchable(text: $searchText, prompt: "users.search.label")
            .toolbar { toolbar }
            .task { await load(restoresInitialFocus: true) }
            .sheet(isPresented: $showCreateUser) {
                guard let name = userAwaitingPermissions else { return }
                userAwaitingPermissions = nil
                holderToConfigure = .user(name)
            } content: {
                CreateUserSheet(
                    groups: viewModel.groups,
                    passwordPolicy: viewModel.passwordPolicy,
                    onCreate: { draft in
                        let outcome = await viewModel.createUser(draft)
                        // A failure stays in the sheet, which keeps what was typed; only
                        // success is announced here, once the sheet is closed.
                        if case .success = outcome { await announce(outcome) }
                        return outcome
                    },
                    onConfigurePermissions: { userAwaitingPermissions = $0 }
                )
            }
            .sheet(isPresented: $showCreateGroup) {
                guard let name = groupAwaitingPermissions else { return }
                groupAwaitingPermissions = nil
                holderToConfigure = .group(name)
            } content: {
                CreateGroupSheet(
                    onCreate: { draft in
                        let outcome = await viewModel.createGroup(draft)
                        if case .success = outcome { await announce(outcome) }
                        return outcome
                    },
                    onConfigurePermissions: { groupAwaitingPermissions = $0 }
                )
            }
            .sheet(item: $holderToConfigure) { holder in
                SharePermissionsSheet(holder: holder, session: session) { outcome in
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
                "common.level.error",
                isPresented: Binding(
                    get: { operationFailure != nil },
                    set: { if !$0 { operationFailure = nil } }
                )
            ) {
                Button("common.button.ok", role: .cancel) { }
                    .help("users.error.dismiss.label")
            } message: {
                if let operationFailure {
                    Text(operationFailure)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.users.isEmpty && viewModel.groups.isEmpty {
            ModuleLoadingView("users.loading.label")
                .accessibilityFocused($contentFocused)
        } else if let errorMessage = viewModel.errorMessage {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($contentFocused)
        } else {
            TabView(selection: $selectedTab) {
                usersList
                    .tabItem { Label("users.section.users.title", systemImage: "person.2") }
                    .tag(Tab.users)
                groupsList
                    .tabItem { Label("common.label.groups", systemImage: "person.3") }
                    .tag(Tab.groups)
            }
            .accessibilityFocused($contentFocused)
        }
    }

    @ViewBuilder
    private var usersList: some View {
        if filteredUsers.isEmpty {
            EmptyModuleView(
                title: searchText.isEmpty ? "users.list.empty.title" : "common.empty.results",
                systemImage: "person.2",
                description: searchText.isEmpty
                    ? "users.create_user.description"
                    : "common.empty.results.description"
            )
        } else {
            Table(
                filteredUsers.sorted(using: userOrder),
                selection: $selectedUserID,
                sortOrder: $userOrder
            ) {
                TableColumn("common.column.name", value: \.name) { user in
                    Text(user.name)
                }
                TableColumn("common.column.state", value: \.sortableStatus) { user in
                    Text(user.statusDescription)
                }
                TableColumn("common.column.administrator", value: \.sortableAdministrator) { user in
                    Text(user.isAdministrator
                        ? String(localized: "common.answer.yes")
                        : String(localized: "common.answer.no"))
                }
                TableColumn("common.column.email", value: \.sortableEmail) { user in
                    Text(user.email ?? "—")
                }
                TableColumn("common.column.description", value: \.sortableDescription) { user in
                    Text(user.description ?? "—")
                }
                TableColumn("common.label.groups", value: \.sortableGroups) { user in
                    Text(user.groups.isEmpty ? "—" : user.sortableGroups)
                }
            }
            .accessibilityLabel("users.section.users.title")
            .contextMenu(forSelectionType: String.self) { ids in
                if let user = viewModel.users.first(where: { ids.contains($0.id) }) {
                    userActions(user)
                }
            }
        }
    }

    @ViewBuilder
    private var groupsList: some View {
        if filteredGroups.isEmpty {
            EmptyModuleView(
                title: searchText.isEmpty ? "common.empty.groups" : "common.empty.results",
                systemImage: "person.3",
                description: searchText.isEmpty
                    ? "users.create_group.description"
                    : "common.empty.results.description"
            )
        } else {
            Table(
                filteredGroups.sorted(using: groupOrder),
                selection: $selectedGroupID,
                sortOrder: $groupOrder
            ) {
                TableColumn("common.column.name", value: \.name) { group in
                    Text(group.name)
                }
                TableColumn("common.column.description", value: \.sortableDescription) { group in
                    Text(group.description ?? "—")
                }
                TableColumn("common.column.members", value: \.sortableMemberCount) { group in
                    Text(group.members.count, format: .number)
                }
            }
            .accessibilityLabel("common.label.groups")
            .contextMenu(forSelectionType: String.self) { ids in
                if let group = viewModel.groups.first(where: { ids.contains($0.id) }) {
                    Button("users.permissions.button") { holderToConfigure = .group(group.name) }
                    Divider()
                    Button("users.group.delete.button", role: .destructive) { groupToDelete = group }
                        .disabled(isProtected(group))
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Menu {
                Button("users.toolbar.new_user.button") { showCreateUser = true }
                    .help("users.toolbar.new_user.hint")
                Button("users.toolbar.new_group.button") { showCreateGroup = true }
                    .help("users.toolbar.new_group.hint")
            } label: {
                Label("common.button.add", systemImage: "plus")
            }
            .help("users.toolbar.add.label")
        }

        if selectedTab == .users, let user = selectedUser {
            ToolbarItem {
                Button {
                    holderToConfigure = .user(user.name)
                } label: {
                    Label("users.permissions.label", systemImage: "folder.badge.person.crop")
                }
                .help("users.user.permissions.hint")
            }
            ToolbarItem {
                Button {
                    Task { await announce(viewModel.setUser(user, disabled: !user.isDisabled)) }
                } label: {
                    Label(
                        user.isDisabled ? "users.user.enable.button" : "users.user.disable.button",
                        systemImage: user.isDisabled ? "person.badge.checkmark" : "person.slash"
                    )
                }
                .disabled(isProtected(user) || isBusy(user))
                .help(user.isDisabled ? "users.user.enable.button" : "users.user.disable.button")
            }
        }

        if selectedTab == .groups, let group = selectedGroup {
            ToolbarItem {
                Button {
                    holderToConfigure = .group(group.name)
                } label: {
                    Label("users.permissions.label", systemImage: "folder.badge.person.crop")
                }
                .help("users.group.permissions.hint")
            }
        }

        ToolbarItem {
            Button {
                Task { await load() }
            } label: {
                Label("common.button.refresh", systemImage: "arrow.clockwise")
            }
            .help("users.toolbar.refresh.label")
        }
    }

    @ViewBuilder
    private func userActions(_ user: DSMUser) -> some View {
        Button("users.permissions.button") { holderToConfigure = .user(user.name) }
            .help("users.user.permissions.hint")
        Divider()
        Button(user.isDisabled ? "common.button.enable" : "common.button.disable") {
            Task { await announce(viewModel.setUser(user, disabled: !user.isDisabled)) }
        }
        .disabled(isProtected(user) || isBusy(user))
        .help(user.isDisabled ? "users.user.enable.hint" : "users.user.disable.hint")
        Divider()
        Button("users.user.delete.button", role: .destructive) { userToDelete = user }
            .disabled(isProtected(user) || isBusy(user))
            .help("users.user.delete.hint")
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

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "users.loading.announcement"),
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
        // A failure shows up in an alert, which VoiceOver reads on its own; an extra
        // announcement would make it narrate twice.
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
    /// Moves straight on to the permissions of the account just created: without this
    /// follow-up, you have to find it again in the list to grant it any access at all, and
    /// nothing says that is possible.
    let onConfigurePermissions: (String) -> Void

    @State private var name = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var description = ""
    @State private var email = ""
    @State private var selectedGroups: Set<String> = []
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
                Section("common.column.account") {
                    TextField("users.create_user.name.label", text: $name)
                        .focused($nameFocused)
                        .accessibilityFocused($accessibilityFocused)
                        .help("users.create_user.name.hint")
                    if revealsPassword {
                        TextField("common.field.password", text: $password)
                            .help("users.create_user.password.hint")
                        TextField("users.create_user.password_confirm.label", text: $passwordConfirmation)
                            .help("users.create_user.password_confirm.hint")
                    } else {
                        SecureField("common.field.password", text: $password)
                            .help("users.create_user.password.hint")
                        SecureField("users.create_user.password_confirm.label", text: $passwordConfirmation)
                            .help("users.create_user.password_confirm.hint")
                    }
                    Toggle("users.create_user.reveal_password.label", isOn: $revealsPassword)
                        .help("users.create_user.reveal_password.hint")
                    HStack {
                        Button("users.create_user.generate_password.button", action: generatePassword)
                            .help("users.create_user.generate_password.hint")
                        Button("users.create_user.copy_password.button", action: copyPassword)
                            .disabled(password.isEmpty)
                            .help("users.create_user.copy_password.hint")
                    }
                    if !passwordConfirmation.isEmpty && !passwordsMatch {
                        Text("users.create_user.password_mismatch.error")
                            .foregroundStyle(.readableRed)
                            .accessibilityLabel("users.create_user.password_mismatch.announcement")
                    }
                    if let passwordPolicy, passwordPolicy.hasRequirements {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("users.create_user.password_rules.title")
                            ForEach(passwordPolicy.requirements, id: \.self) { requirement in
                                Text(requirement)
                            }
                        }
                        .foregroundStyle(.readableSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    TextField("users.create_user.email.label", text: $email)
                        .help("users.create_user.email.hint")
                    TextField("common.field.description_optional", text: $description)
                        .help("users.create_user.description_field.hint")
                }

                Section("common.label.groups") {
                    // The NAS assigns "users" itself and refuses to change it, so it is stated
                    // rather than offered: a switch here could never do what it promises.
                    Text("users.create_user.everyone_group.note")
                        .foregroundStyle(.readableSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(assignableGroups) { group in
                        Toggle(group.name, isOn: groupBinding(group.name))
                            .help(String(localized: "users.create_user.group_membership.hint", defaultValue: "Add the user to or remove the user from the \(group.name) group"))
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
                        .accessibilityLabel("users.create.progress.label")
                }
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("users.create_user.cancel.hint")
                Button("users.create_user.create_with_permissions.button") {
                    create(thenConfiguringPermissions: true)
                }
                .disabled(!canCreate)
                .help("users.create_user.create_with_permissions.hint")
                Button("common.button.create") { create(thenConfiguringPermissions: false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
                    .help("users.create_user.submit.button")
            }
            .padding()
        }
        .frame(width: 460, height: 580)
        .onAppear {
            nameFocused = true
            accessibilityFocused = true
            VoiceOver.announce(
                String(localized: "users.create_user.title"),
                category: .navigation
            )
        }
    }

    private var assignableGroups: [DSMGroup] {
        groups.filter { !$0.isEveryone }
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
        // Without showing it in the clear, a password you did not choose is unreadable:
        // it has to be possible to read it back before passing it on.
        revealsPassword = true
        failureMessage = nil
        VoiceOver.announce(
            String(localized: "users.create_user.password_generated.announcement"),
            category: .result
        )
    }

    private func copyPassword() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(password, forType: .string)
        VoiceOver.announce(String(localized: "users.create_user.password_copied.announcement"), category: .result)
    }

    private func create(thenConfiguringPermissions configuresPermissions: Bool) {
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
                if configuresPermissions { onConfigurePermissions(draft.name) }
                dismiss()
            case .failure(let message):
                // The sheet stays open: what was typed is kept and can be corrected.
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
    let onCreate: (DSMGroupDraft) async -> DSMOperationOutcome
    /// Moves straight on to the permissions of the group just created: a group with no access
    /// to anything is of no use, and nothing on this screen says where to grant it.
    let onConfigurePermissions: (String) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var isCreating = false
    @State private var failureMessage: String?
    @FocusState private var nameFocused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool
    @AccessibilityFocusState private var failureFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreate: Bool { !trimmedName.isEmpty && !isCreating }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("users.create_group.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            LabeledField(label: "users.create_group.name.label") {
                TextField("users.create_group.name.label", text: $name)
                    .focused($nameFocused)
                    .accessibilityFocused($accessibilityFocused)
                    .help("users.create_group.name.hint")
            }
            LabeledField(label: "common.field.description_optional") {
                TextField("common.field.description_optional", text: $description)
                    .help("users.create_group.description_field.hint")
            }
            if let failureMessage {
                Text(failureMessage)
                    .foregroundStyle(.readableRed)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityFocused($failureFocused)
            }
            HStack {
                if isCreating {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("users.create.progress.label")
                }
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("users.create_group.cancel.hint")
                Button("users.create_group.create_with_permissions.button") {
                    create(thenConfiguringPermissions: true)
                }
                .disabled(!canCreate)
                .help("users.create_group.create_with_permissions.hint")
                Button("common.button.create") { create(thenConfiguringPermissions: false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
                    .help("users.create_group.submit.button")
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            nameFocused = true
            accessibilityFocused = true
            VoiceOver.announce(
                String(localized: "users.create_group.title"),
                category: .navigation
            )
        }
    }

    private func create(thenConfiguringPermissions configuresPermissions: Bool) {
        guard canCreate else { return }
        let draft = DSMGroupDraft(name: trimmedName, description: description)
        isCreating = true
        failureMessage = nil
        Task {
            let outcome = await onCreate(draft)
            isCreating = false
            switch outcome {
            case .success:
                if configuresPermissions { onConfigurePermissions(draft.name) }
                dismiss()
            case .failure(let message):
                // The sheet stays open: a name already taken is corrected here rather than
                // retyped from scratch.
                failureMessage = message
                failureFocused = true
                VoiceOver.announce(message, category: .error, priority: .high)
            case .cancelled:
                break
            }
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
            Text(kind == .user ? "users.user.delete.confirm.title" : "users.group.delete.confirm.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(warning)
                .fixedSize(horizontal: false, vertical: true)
            LabeledField(label: "users.delete.name_field.placeholder") {
                TextField(name, text: $confirmation)
                    .focused($fieldFocused)
                    .accessibilityFocused($accessibilityFocused)
                    .help("users.delete.name_field.hint")
            }
            HStack {
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("common.button.cancel_deletion")
                Button("common.button.delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                .disabled(!confirmed)
                .help("users.delete.confirm.button")
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            fieldFocused = true
            accessibilityFocused = true
            VoiceOver.announce(
                String(localized: "users.delete.confirm.description"),
                category: .navigation
            )
        }
    }

    private var warning: String {
        switch kind {
        case .user:
            String(localized: "users.user.delete.confirm.description", defaultValue: "The “\(name)” account will be deleted. Its home folder may also become inaccessible depending on the NAS settings.")
        case .group:
            String(localized: "users.group.delete.confirm.description", defaultValue: "The “\(name)” group will be deleted. Permissions granted through this group will be removed.")
        }
    }
}
