//
//  AppCommands.swift
//  dsmaccess
//
//  Commandes de barre des menus reliées à la fenêtre active.
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
        CommandMenu("NAS") {
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
                    .help(String(localized: "Se connecter à \(profile.displayName)"))
                }

                if !sessionActions.profiles.isEmpty {
                    Divider()
                }
                Button("Ajouter un NAS…", action: sessionActions.addNAS)
                    .help("Ajouter un NAS à DSM Access")
                Button("Renommer le NAS…", action: sessionActions.renameNAS)
                    .disabled(sessionActions.activeProfileID == nil)
                    .help("Renommer le NAS connecté")
                SettingsLink {
                    Text("Gérer les NAS…")
                }
                .help("Ouvrir les réglages des NAS enregistrés")
                Divider()
                Button("Déconnexion", role: .destructive, action: sessionActions.logout)
                    .help("Se déconnecter du NAS")
            } else {
                Button("Ajouter un NAS…") { }
                    .disabled(true)
                    .help("Connectez-vous pour ajouter un NAS")
                SettingsLink {
                    Text("Gérer les NAS…")
                }
                .help("Ouvrir les réglages des NAS enregistrés")
                Button("Déconnexion", role: .destructive) { }
                    .disabled(true)
                    .help("Aucun NAS connecté")
            }
        }

        CommandMenu("Navigation") {
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
                        .help(String(localized: "Afficher \(module.localizedTitle)"))
                    }
                }
            }
        }

        CommandMenu("Fichiers") {
            Button("Ouvrir") { fileActions?.open() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(fileActions?.hasSingleSelection != true)
                .help("Ouvrir l’élément sélectionné")
            Button("Dossier parent") { fileActions?.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(fileActions?.canGoUp != true)
                .help("Ouvrir le dossier parent")
            Button("Actualiser") { fileActions?.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(fileActions == nil)
                .help("Actualiser le dossier")

            Divider()

            Button("Nouveau dossier") { fileActions?.createFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(fileActions?.canCreateFolder != true)
                .help("Créer un nouveau dossier")
            Button("Envoyer des fichiers…") { fileActions?.upload() }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(fileActions?.canUpload != true)
                .help("Envoyer des fichiers dans ce dossier")
            Button("Télécharger…") { fileActions?.download() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(
                    fileActions?.hasSelection != true || fileActions?.canDownload != true
                )
                .help("Télécharger les éléments sélectionnés")

            Divider()

            Button("Copier") { fileActions?.copy() }
                .disabled(
                    fileActions?.hasSelection != true || fileActions?.canCopyMove != true
                )
                .help("Copier les éléments sélectionnés")
            Button("Coller") { fileActions?.paste() }
                .disabled(fileActions?.canPaste != true)
                .help("Coller ici les éléments copiés ou les fichiers du Finder")
            Button("Déplacer ici") { fileActions?.moveHere() }
                .disabled(fileActions?.canMoveHere != true)
                .help("Déplacer ici les éléments copiés, en les retirant de leur emplacement d’origine")
            Button("Renommer…") { fileActions?.rename() }
                .disabled(
                    fileActions?.hasSingleSelection != true || fileActions?.canRename != true
                )
                .help("Renommer l’élément sélectionné")

            Divider()

            Button("Compresser…") { fileActions?.compress() }
                .disabled(
                    fileActions?.hasSelection != true || fileActions?.canCompress != true
                )
                .help("Compresser les éléments sélectionnés")
            Button("Extraire") { fileActions?.extract() }
                .disabled(fileActions?.canExtract != true)
                .help("Extraire l’archive sélectionnée")
            Button("Supprimer…", role: .destructive) { fileActions?.delete() }
                .disabled(fileActions?.hasSelection != true || fileActions?.canDelete != true)
                .help("Supprimer les éléments sélectionnés")

            Divider()

            Button("Lire les informations") { fileActions?.showInfo() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(fileActions?.hasSingleSelection != true)
                .help("Lire les informations de l’élément sélectionné")
        }
    }
}
