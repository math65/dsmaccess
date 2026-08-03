//
//  AppModule.swift
//  dsmaccess
//
//  Navigation principale de l'application.
//

import SwiftUI

enum AppModuleSection: String, CaseIterable, Identifiable {
    case overview
    case files
    case administration
    case applications

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "modules.overview.title"
        case .files: "modules.section.files_sharing"
        case .administration: "modules.section.administration"
        case .applications: "common.label.applications"
        }
    }
}

struct AppModuleShortcut {
    let key: KeyEquivalent
    let modifiers: EventModifiers
}

enum AppModule: String, CaseIterable, Identifiable, Codable, Sendable {
    case systemInfo
    case resourceMonitor
    case storage
    case logsSecurity
    case files
    case shares
    case downloads
    case usbCopy
    case hyperBackup
    case usersGroups
    case fileServices
    case packages
    case controlPanel
    case containers
    case virtualMachines
    case surveillance

    var id: Self { self }

    var section: AppModuleSection {
        switch self {
        case .systemInfo, .resourceMonitor, .storage, .logsSecurity: .overview
        case .files, .shares, .downloads: .files
        case .usersGroups, .fileServices, .packages, .controlPanel: .administration
        case .containers, .virtualMachines, .surveillance, .usbCopy, .hyperBackup: .applications
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .systemInfo: "modules.section.your_nas"
        case .resourceMonitor: "modules.resource_monitor.title"
        case .storage: "common.module.storage"
        case .logsSecurity: "modules.logs_security.title"
        case .files: "common.module.files"
        case .shares: "common.module.shared_folders"
        case .downloads: "modules.download_station.title"
        case .usbCopy: "modules.usb_copy.title"
        case .hyperBackup: "modules.hyper_backup.title"
        case .usersGroups: "modules.users_groups.title"
        case .fileServices: "common.module.file_services"
        case .packages: "common.module.package_center"
        case .controlPanel: "common.module.control_panel"
        case .containers: "common.module.containers"
        case .virtualMachines: "common.module.virtual_machines"
        case .surveillance: "modules.surveillance_station.title"
        }
    }

    var localizedTitle: String {
        switch self {
        case .systemInfo: String(localized: "modules.section.your_nas")
        case .resourceMonitor: String(localized: "modules.resource_monitor.title")
        case .storage: String(localized: "common.module.storage")
        case .logsSecurity: String(localized: "modules.logs_security.title")
        case .files: String(localized: "common.module.files")
        case .shares: String(localized: "common.module.shared_folders")
        case .downloads: String(localized: "modules.download_station.title")
        case .usbCopy: String(localized: "modules.usb_copy.title")
        case .hyperBackup: String(localized: "modules.hyper_backup.title")
        case .usersGroups: String(localized: "modules.users_groups.title")
        case .fileServices: String(localized: "common.module.file_services")
        case .packages: String(localized: "common.module.package_center")
        case .controlPanel: String(localized: "common.module.control_panel")
        case .containers: String(localized: "common.module.containers")
        case .virtualMachines: String(localized: "common.module.virtual_machines")
        case .surveillance: String(localized: "modules.surveillance_station.title")
        }
    }

    var systemImage: String {
        switch self {
        case .systemInfo: "server.rack"
        case .resourceMonitor: "gauge.with.dots.needle.bottom.50percent"
        case .storage: "internaldrive"
        case .logsSecurity: "lock.shield"
        case .files: "folder"
        case .shares: "externaldrive.badge.person.crop"
        case .downloads: "arrow.down.circle"
        case .usbCopy: "externaldrive.badge.arrowtriangle.2.circlepath"
        case .hyperBackup: "arrow.triangle.2.circlepath"
        case .usersGroups: "person.2"
        case .fileServices: "network"
        case .packages: "shippingbox"
        case .controlPanel: "gearshape"
        case .containers: "shippingbox.fill"
        case .virtualMachines: "desktopcomputer"
        case .surveillance: "video"
        }
    }

    var keyboardShortcut: AppModuleShortcut {
        switch self {
        case .systemInfo: AppModuleShortcut(key: "1", modifiers: .command)
        case .storage: AppModuleShortcut(key: "2", modifiers: .command)
        case .logsSecurity: AppModuleShortcut(key: "3", modifiers: .command)
        case .files: AppModuleShortcut(key: "4", modifiers: .command)
        case .shares: AppModuleShortcut(key: "5", modifiers: .command)
        case .downloads: AppModuleShortcut(key: "6", modifiers: .command)
        case .usersGroups: AppModuleShortcut(key: "7", modifiers: .command)
        case .fileServices: AppModuleShortcut(key: "8", modifiers: .command)
        case .packages: AppModuleShortcut(key: "9", modifiers: .command)
        case .controlPanel: AppModuleShortcut(key: "0", modifiers: .command)
        // Option rather than Shift for the second set: macOS reserves Command-Shift-3, 4 and 5
        // for screen capture, and the system shortcut always wins, which left three modules
        // unreachable from the keyboard.
        case .containers: AppModuleShortcut(key: "1", modifiers: [.command, .option])
        case .virtualMachines: AppModuleShortcut(key: "2", modifiers: [.command, .option])
        case .surveillance: AppModuleShortcut(key: "3", modifiers: [.command, .option])
        case .usbCopy: AppModuleShortcut(key: "4", modifiers: [.command, .option])
        case .resourceMonitor: AppModuleShortcut(key: "5", modifiers: [.command, .option])
        case .hyperBackup: AppModuleShortcut(key: "6", modifiers: [.command, .option])
        }
    }

    func isAvailable(in capabilities: DSMCapabilities) -> Bool {
        switch self {
        case .systemInfo:
            capabilities.supports("SYNO.DSM.Info")
        case .resourceMonitor:
            capabilities.supports("SYNO.Core.System.Utilization")
        case .storage:
            capabilities.supports("SYNO.Storage.CGI.Storage")
        case .files:
            capabilities.supports("SYNO.FileStation.List")
        case .shares:
            capabilities.supports("SYNO.Core.Share")
        case .fileServices:
            FileService.allCases.contains { capabilities.supports($0.api) }
        case .packages:
            capabilities.supports("SYNO.Core.Package")
        case .controlPanel:
            capabilities.supports("SYNO.Core.Network")
        case .logsSecurity:
            capabilities.supports("SYNO.Core.SyslogClient.Log")
                || capabilities.supports(prefix: "SYNO.Core.Security")
                || capabilities.supports(prefix: "SYNO.Core.SmartBlock")
        case .downloads:
            capabilities.supports("SYNO.DownloadStation.Task")
        case .usbCopy:
            capabilities.supports("SYNO.USBCopy")
        case .hyperBackup:
            capabilities.supports("SYNO.Backup.Task")
        case .usersGroups:
            capabilities.supports("SYNO.Core.User") && capabilities.supports("SYNO.Core.Group")
        case .containers:
            capabilities.supports("SYNO.Docker.Container")
        case .virtualMachines:
            capabilities.supports("SYNO.Virtualization.API.Guest")
                && capabilities.supports("SYNO.Virtualization.API.Guest.Action")
        case .surveillance:
            capabilities.supports("SYNO.SurveillanceStation.Camera")
        }
    }

    var unavailableHelp: LocalizedStringKey {
        switch self {
        case .downloads: "modules.download_station.unavailable"
        case .usbCopy: "modules.usb_copy.unavailable"
        case .hyperBackup: "modules.hyper_backup.unavailable"
        case .containers: "modules.container_manager.unavailable"
        case .virtualMachines: "modules.virtual_machine_manager.unavailable"
        case .surveillance: "modules.surveillance_station.unavailable"
        case .usersGroups: "modules.users_groups.unavailable"
        case .logsSecurity: "modules.logs_security.unavailable"
        case .resourceMonitor: "modules.resource_monitor.unavailable"
        default: "modules.unavailable.generic"
        }
    }
}

extension AppModuleSection {
    var modules: [AppModule] {
        AppModule.allCases.filter { $0.section == self }
    }
}
