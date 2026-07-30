//
//  AppCommands.swift
//  dsmaccess
//
//  Menu bar commands wired to the active window.
//

import SwiftUI

struct SessionCommandActions {
    let profiles: [NASProfile]
    let activeProfileID: UUID?
    let logout: () -> Void
    let addNAS: () -> Void
    let renameNAS: () -> Void
    let selectNAS: (UUID) -> Void
}

struct FileCommandActions {
    let canGoUp: Bool
    let hasSelection: Bool
    let hasSingleSelection: Bool
    let canCreateFolder: Bool
    let canUpload: Bool
    let canDownload: Bool
    let canCopyMove: Bool
    let canRename: Bool
    let canCompress: Bool
    let canDelete: Bool
    let canPaste: Bool
    let canMoveHere: Bool
    let canExtract: Bool
    let refresh: () -> Void
    let goUp: () -> Void
    let open: () -> Void
    let createFolder: () -> Void
    let upload: () -> Void
    let download: () -> Void
    let rename: () -> Void
    let copy: () -> Void
    let paste: () -> Void
    let moveHere: () -> Void
    let compress: () -> Void
    let extract: () -> Void
    let delete: () -> Void
    let showInfo: () -> Void
}

private struct SelectedModuleKey: FocusedValueKey {
    typealias Value = Binding<AppModule>
}

private struct SessionCommandActionsKey: FocusedValueKey {
    typealias Value = SessionCommandActions
}

private struct AvailableModulesKey: FocusedValueKey {
    typealias Value = Set<AppModule>
}

private struct FileCommandActionsKey: FocusedValueKey {
    typealias Value = FileCommandActions
}

extension FocusedValues {
    var selectedModule: Binding<AppModule>? {
        get { self[SelectedModuleKey.self] }
        set { self[SelectedModuleKey.self] = newValue }
    }

    var sessionCommandActions: SessionCommandActions? {
        get { self[SessionCommandActionsKey.self] }
        set { self[SessionCommandActionsKey.self] = newValue }
    }

    var availableModules: Set<AppModule>? {
        get { self[AvailableModulesKey.self] }
        set { self[AvailableModulesKey.self] = newValue }
    }


    var fileCommandActions: FileCommandActions? {
        get { self[FileCommandActionsKey.self] }
        set { self[FileCommandActionsKey.self] = newValue }
    }
}

struct DSMCommands: Commands {
    @FocusedBinding(\.selectedModule) private var selectedModule
    @FocusedValue(\.availableModules) private var availableModules
    @FocusedValue(\.sessionCommandActions) private var sessionActions
    @FocusedValue(\.fileCommandActions) private var fileActions

    var body: some Commands {
        CommandMenu("common.label.nas") {
            if let sessionActions {
                ForEach(sessionActions.profiles) { profile in
                    Button {
                        sessionActions.selectNAS(profile.id)
                    } label: {
                        if profile.id == sessionActions.activeProfileID {
                            Label(profile.displayName, systemImage: "checkmark")
                        } else {
                            Text(profile.displayName)
                        }
                    }
                    .help(String(localized: "common.action.connect_to", defaultValue: "Connect to \(profile.displayName)"))
                }

                if !sessionActions.profiles.isEmpty {
                    Divider()
                }
                Button("common.action.add_nas", action: sessionActions.addNAS)
                    .help("common.action.add_nas.hint")
                Button("common.action.rename_nas", action: sessionActions.renameNAS)
                    .disabled(sessionActions.activeProfileID == nil)
                    .help("common.action.rename_nas.hint")
                SettingsLink {
                    Text("menu.nas.manage")
                }
                .help("menu.nas.manage.hint")
                Divider()
                Button("common.action.log_out", role: .destructive, action: sessionActions.logout)
                    .help("common.action.log_out.hint")
            } else {
                Button("common.action.add_nas") { }
                    .disabled(true)
                    .help("menu.nas.sign_in_required")
                SettingsLink {
                    Text("menu.nas.manage")
                }
                .help("menu.nas.manage.hint")
                Button("common.action.log_out", role: .destructive) { }
                    .disabled(true)
                    .help("menu.nas.none_connected")
            }
        }

        CommandMenu("menu.navigation.section") {
            ForEach(AppModuleSection.allCases) { section in
                Section(section.title) {
                    ForEach(section.modules) { module in
                        Button(module.title) {
                            selectedModule = module
                        }
                        .keyboardShortcut(
                            module.keyboardShortcut.key,
                            modifiers: module.keyboardShortcut.modifiers
                        )
                        .disabled(
                            selectedModule == nil || availableModules?.contains(module) != true
                        )
                        .help(String(localized: "menu.module.show", defaultValue: "Show \(module.localizedTitle)"))
                    }
                }
            }
        }

        CommandMenu("common.module.files") {
            Button("common.button.open") { fileActions?.open() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(fileActions?.hasSingleSelection != true)
                .help("common.button.open.hint")
            Button("common.button.parent_folder") { fileActions?.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(fileActions?.canGoUp != true)
                .help("menu.files.parent_folder")
            Button("common.button.refresh") { fileActions?.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(fileActions == nil)
                .help("menu.files.refresh_folder")

            Divider()

            Button("common.button.new_folder") { fileActions?.createFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(fileActions?.canCreateFolder != true)
                .help("common.button.new_folder.hint")
            Button("common.button.upload_files") { fileActions?.upload() }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(fileActions?.canUpload != true)
                .help("common.button.upload_files.hint")
            Button("common.button.download") { fileActions?.download() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(
                    fileActions?.hasSelection != true || fileActions?.canDownload != true
                )
                .help("common.button.download.hint")

            Divider()

            Button("common.button.copy") { fileActions?.copy() }
                .disabled(
                    fileActions?.hasSelection != true || fileActions?.canCopyMove != true
                )
                .help("common.button.copy.hint")
            Button("common.button.paste") { fileActions?.paste() }
                .disabled(fileActions?.canPaste != true)
                .help("common.button.paste.hint")
            Button("common.button.move_here") { fileActions?.moveHere() }
                .disabled(fileActions?.canMoveHere != true)
                .help("common.button.move_here.hint")
            Button("common.menu.rename") { fileActions?.rename() }
                .disabled(
                    fileActions?.hasSingleSelection != true || fileActions?.canRename != true
                )
                .help("common.button.rename.hint")

            Divider()

            Button("common.button.compress") { fileActions?.compress() }
                .disabled(
                    fileActions?.hasSelection != true || fileActions?.canCompress != true
                )
                .help("common.button.compress.hint")
            Button("common.button.extract") { fileActions?.extract() }
                .disabled(fileActions?.canExtract != true)
                .help("common.button.extract.hint")
            Button("common.menu.delete", role: .destructive) { fileActions?.delete() }
                .disabled(fileActions?.hasSelection != true || fileActions?.canDelete != true)
                .help("common.button.delete.hint")

            Divider()

            Button("common.button.get_info") { fileActions?.showInfo() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(fileActions?.hasSingleSelection != true)
                .help("common.button.get_info.hint")
        }
    }
}
