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

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Vue d’ensemble"
        case .files: "Fichiers et partage"
        case .administration: "Administration"
        }
    }
}

enum AppModule: String, CaseIterable, Identifiable {
    case systemInfo
    case storage
    case files
    case shares
    case fileServices
    case packages

    var id: Self { self }

    var section: AppModuleSection {
        switch self {
        case .systemInfo, .storage: .overview
        case .files, .shares: .files
        case .fileServices, .packages: .administration
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .systemInfo: "Votre NAS"
        case .storage: "Stockage"
        case .files: "Fichiers"
        case .shares: "Dossiers partagés"
        case .fileServices: "Services de fichiers"
        case .packages: "Centre de paquets"
        }
    }

    var systemImage: String {
        switch self {
        case .systemInfo: "server.rack"
        case .storage: "internaldrive"
        case .files: "folder"
        case .shares: "externaldrive.badge.person.crop"
        case .fileServices: "network"
        case .packages: "shippingbox"
        }
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .systemInfo: "1"
        case .storage: "2"
        case .files: "3"
        case .shares: "4"
        case .fileServices: "5"
        case .packages: "6"
        }
    }
}

extension AppModuleSection {
    var modules: [AppModule] {
        AppModule.allCases.filter { $0.section == self }
    }
}
