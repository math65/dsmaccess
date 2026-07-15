//
//  FileInfoSheet.swift
//  dsmaccess
//
//  File Station inspector presented with native form controls.
//

import SwiftUI

struct FileInfoSheet: View {
    let item: FileStationItem

    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focusTitle: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: item.isdir ? "folder" : "doc")
                    .foregroundStyle(item.isdir ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focusTitle)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Informations générales") {
                    LabeledContent("Nom", value: item.name)
                    LabeledContent("Type", value: kind)
                    if let size = item.additional?.size, !item.isdir {
                        LabeledContent("Taille") {
                            Text(size, format: .byteCount(style: .file, includesActualByteCount: true))
                        }
                    }
                    LabeledContent("Emplacement", value: item.path)
                    if let realPath = item.additional?.realPath, realPath != item.path {
                        LabeledContent("Chemin réel", value: realPath)
                    }
                }

                if let time = item.additional?.time {
                    Section("Dates") {
                        dateRow("Modification", timestamp: time.mtime)
                        dateRow("Création", timestamp: time.crtime ?? time.ctime)
                        dateRow("Dernier accès", timestamp: time.atime)
                    }
                }

                if let owner = item.additional?.owner,
                   owner.user != nil || owner.group != nil {
                    Section("Propriétaire") {
                        if let user = owner.user {
                            LabeledContent("Utilisateur", value: user)
                        }
                        if let group = owner.group {
                            LabeledContent("Groupe", value: group)
                        }
                    }
                }

                if let permission = item.additional?.permission {
                    Section("Autorisations") {
                        if let posix = permission.posix {
                            LabeledContent("Mode POSIX") {
                                Text(posix, format: .number.grouping(.never))
                            }
                        }
                        if let accessList = accessList(for: permission.acl) {
                            LabeledContent("Accès", value: accessList)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel(String(localized: "Informations sur \(item.name)"))

            Divider()

            HStack {
                Spacer()
                Button("Fermer", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("Fermer les informations")
            }
            .padding()
        }
        .frame(width: 520)
        .frame(minHeight: 430)
        .onAppear {
            focusTitle = true
            VoiceOver.announce(
                String(localized: "Informations sur \(item.name)"),
                category: .navigation
            )
        }
    }

    @ViewBuilder
    private func dateRow(_ label: LocalizedStringKey, timestamp: Int?) -> some View {
        if let timestamp {
            LabeledContent(label) {
                Text(
                    Date(timeIntervalSince1970: TimeInterval(timestamp)),
                    format: Date.FormatStyle(date: .long, time: .standard)
                )
            }
        }
    }

    private var kind: String {
        if item.isdir { return String(localized: "Dossier") }
        if let type = item.additional?.type, !type.isEmpty { return type }
        let pathExtension = (item.name as NSString).pathExtension
        return pathExtension.isEmpty
            ? String(localized: "Fichier")
            : pathExtension.uppercased()
    }

    private func accessList(for acl: FileStationItem.ACLInfo?) -> String? {
        guard let acl else { return nil }
        var access = [String]()
        if acl.read == true { access.append(String(localized: "Lecture")) }
        if acl.write == true { access.append(String(localized: "Écriture")) }
        if acl.delete == true { access.append(String(localized: "Suppression")) }
        return access.isEmpty ? String(localized: "Aucun") : access.formatted(.list(type: .and))
    }
}
