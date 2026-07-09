//
//  FileTableView.swift
//  dsmaccess
//
//  Navigateur File Station en AppKit (NSTableView) exposé à SwiftUI via NSViewRepresentable.
//  On descend en AppKit UNIQUEMENT pour cette liste : NSTableView donne la navigation
//  clavier native (flèches) et l'accessibilité VoiceOver de première classe que la List
//  SwiftUI ne fournit pas correctement sur macOS. Clavier façon Finder :
//    · ↑ / ↓          : parcourir (natif)
//    · Cmd-↓ / Entrée  : activer (dossier → ouvrir, fichier → télécharger)
//    · Cmd-↑           : remonter au dossier parent
//    · VO-Espace       : activer la ligne (accessibilityPerformPress)
//  Actions par ligne (menu contextuel clic droit + VO-Maj-M + actions VoiceOver) : Télécharger,
//  et — à l'intérieur d'un partage seulement (`canWrite`) — Renommer et Supprimer.
//

import AppKit
import SwiftUI

struct FileTableView: NSViewRepresentable {
    var items: [FileStationItem]
    /// Actions d'écriture disponibles (faux à la racine des partages).
    var canWrite: Bool
    var onActivate: (FileStationItem) -> Void   // Entrée / VO-Espace / double-clic
    var onDownload: (FileStationItem) -> Void    // menu contextuel / action VoiceOver
    var onRename: (FileStationItem) -> Void
    var onDelete: (FileStationItem) -> Void
    var onGoUp: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = KeyboardTableView()
        table.headerView = nil
        table.rowHeight = 28
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.style = .inset
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)

        table.onActivate = { [weak table] in
            guard let table, table.selectedRow >= 0 else { return }
            context.coordinator.activateRow(table.selectedRow)
        }
        table.onGoUp = { context.coordinator.parent.onGoUp() }
        table.onContextDownload = { row in context.coordinator.downloadRow(row) }
        table.onContextRename = { row in context.coordinator.renameRow(row) }
        table.onContextDelete = { row in context.coordinator.deleteRow(row) }
        table.canWrite = canWrite

        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.tableDoubleClicked(_:))
        context.coordinator.tableView = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let table = nsView.documentView as? KeyboardTableView else { return }
        table.canWrite = canWrite
        table.reloadData()
        if !items.isEmpty && (table.selectedRow < 0 || table.selectedRow >= items.count) {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            table.scrollRowToVisible(0)
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FileTableView
        weak var tableView: NSTableView?

        init(_ parent: FileTableView) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.items.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.items.indices.contains(row) else { return nil }
            let item = parent.items[row]
            let id = NSUserInterfaceItemIdentifier("FileCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? FileCellView) ?? FileCellView(identifier: id)
            cell.configure(with: item)
            cell.canWrite = parent.canWrite
            cell.onPress = { [weak self] in self?.activate(item) }
            cell.onDownload = { [weak self] in self?.download(item) }
            cell.onRename = { [weak self] in self?.rename(item) }
            cell.onDelete = { [weak self] in self?.delete(item) }
            return cell
        }

        func activateRow(_ row: Int) {
            guard parent.items.indices.contains(row) else { return }
            activate(parent.items[row])
        }
        func downloadRow(_ row: Int) {
            guard parent.items.indices.contains(row) else { return }
            download(parent.items[row])
        }
        func renameRow(_ row: Int) {
            guard parent.items.indices.contains(row) else { return }
            rename(parent.items[row])
        }
        func deleteRow(_ row: Int) {
            guard parent.items.indices.contains(row) else { return }
            delete(parent.items[row])
        }

        /// Activation : dossier → ouvrir, fichier → télécharger (décidé par la coquille SwiftUI).
        private func activate(_ item: FileStationItem) { parent.onActivate(item) }
        /// Téléchargement explicite (marche aussi pour un dossier → ZIP).
        private func download(_ item: FileStationItem) { parent.onDownload(item) }
        private func rename(_ item: FileStationItem) { parent.onRename(item) }
        private func delete(_ item: FileStationItem) { parent.onDelete(item) }

        @objc func tableDoubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            if row >= 0 { activateRow(row) }
        }
    }
}

/// NSMenuItem qui exécute une closure (NSMenuItem ne connaît nativement que target/action).
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) non supporté") }
    @objc private func fire() { handler() }
}

/// Menu contextuel d'un élément, PARTAGÉ entre le clic droit (souris → `menu(for:)`) et
/// VO-Maj-M (VoiceOver → `accessibilityPerformShowMenu()`). Point unique où ajouter les
/// futures actions. Renommer / Supprimer n'apparaissent qu'à l'intérieur d'un partage.
private func makeFileContextMenu(canWrite: Bool,
                                 download: @escaping () -> Void,
                                 rename: @escaping () -> Void,
                                 delete: @escaping () -> Void) -> NSMenu {
    let menu = NSMenu()
    menu.addItem(ClosureMenuItem(title: String(localized: "Télécharger"), handler: download))
    if canWrite {
        menu.addItem(NSMenuItem.separator())
        menu.addItem(ClosureMenuItem(title: String(localized: "Renommer"), handler: rename))
        menu.addItem(ClosureMenuItem(title: String(localized: "Supprimer"), handler: delete))
    }
    return menu
}

/// NSTableView qui mappe les touches façon Finder et fournit le menu contextuel partagé.
final class KeyboardTableView: NSTableView {
    var onActivate: (() -> Void)?
    var onGoUp: (() -> Void)?
    var onContextDownload: ((Int) -> Void)?
    var onContextRename: ((Int) -> Void)?
    var onContextDelete: ((Int) -> Void)?
    var canWrite = false

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 125 where command:      // Cmd-↓ : ouvrir / activer (façon Finder)
            onActivate?()
        case 126 where command:      // Cmd-↑ : remonter (aussi géré par le bouton, pour les dossiers vides)
            onGoUp?()
        case 36, 76:                 // Entrée : renommer l'élément sélectionné (façon Finder)
            if canWrite, selectedRow >= 0 { onContextRename?(selectedRow) } else { super.keyDown(with: event) }
        case 51 where command:       // Cmd-Suppr : supprimer l'élément sélectionné (façon Finder)
            if canWrite, selectedRow >= 0 { onContextDelete?(selectedRow) } else { super.keyDown(with: event) }
        default:
            super.keyDown(with: event)   // ↑ ↓ (navigation) et le reste : comportement natif
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else { return nil }
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return makeFileContextMenu(
            canWrite: canWrite,
            download: { [weak self] in self?.onContextDownload?(row) },
            rename: { [weak self] in self?.onContextRename?(row) },
            delete: { [weak self] in self?.onContextDelete?(row) }
        )
    }
}

/// Cellule : icône + nom + détail (taille · date), avec un libellé VoiceOver unifié, l'action
/// « presser » (VO-Espace → activer) et les actions VoiceOver (Télécharger, + Renommer/Supprimer
/// quand `canWrite`).
final class FileCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    var onPress: (() -> Void)?
    var onDownload: (() -> Void)?
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?
    var canWrite = false

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) non supporté") }

    private func setup() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        nameField.translatesAutoresizingMaskIntoConstraints = false
        detailField.translatesAutoresizingMaskIntoConstraints = false

        nameField.lineBreakMode = .byTruncatingTail
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailField.textColor = .secondaryLabelColor
        detailField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailField.alignment = .right
        detailField.setContentCompressionResistancePriority(.required, for: .horizontal)
        detailField.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(iconView)
        addSubview(nameField)
        addSubview(detailField)
        imageView = iconView
        textField = nameField

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),

            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),

            detailField.leadingAnchor.constraint(greaterThanOrEqualTo: nameField.trailingAnchor, constant: 8),
            detailField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            detailField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(with item: FileStationItem) {
        iconView.image = NSImage(systemSymbolName: item.isdir ? "folder" : "doc", accessibilityDescription: nil)
        iconView.contentTintColor = item.isdir ? .controlAccentColor : .secondaryLabelColor
        nameField.stringValue = item.name
        detailField.stringValue = item.detailText ?? ""
        setAccessibilityLabel(item.accessibilityLabel)
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions: [NSAccessibilityCustomAction] = []
        if let onDownload {
            actions.append(NSAccessibilityCustomAction(name: String(localized: "Télécharger")) {
                onDownload(); return true
            })
        }
        if canWrite {
            if let onRename {
                actions.append(NSAccessibilityCustomAction(name: String(localized: "Renommer")) {
                    onRename(); return true
                })
            }
            if let onDelete {
                actions.append(NSAccessibilityCustomAction(name: String(localized: "Supprimer")) {
                    onDelete(); return true
                })
            }
        }
        return actions.isEmpty ? nil : actions
    }

    /// Menu contextuel VoiceOver : VO-Maj-M appelle CETTE méthode (et non le `menu(for:)`
    /// de la souris), il faut donc présenter le menu nous-mêmes pour qu'il soit atteignable.
    override func accessibilityPerformShowMenu() -> Bool {
        guard onDownload != nil else { return false }
        let menu = makeFileContextMenu(
            canWrite: canWrite,
            download: { [weak self] in self?.onDownload?() },
            rename: { [weak self] in self?.onRename?() },
            delete: { [weak self] in self?.onDelete?() }
        )
        menu.popUp(positioning: nil, at: NSPoint(x: bounds.minX, y: bounds.maxY), in: self)
        return true
    }
}
