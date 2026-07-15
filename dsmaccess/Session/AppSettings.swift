//
//  AppSettings.swift
//  dsmaccess
//
//  Préférences observables partagées par la barre latérale et la fenêtre Réglages.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    var enabledAnnouncementCategories: Set<AnnouncementCategory> {
        didSet { Preferences.enabledAnnouncementCategories = enabledAnnouncementCategories }
    }

    var queueAnnouncements: Bool {
        didSet { Preferences.queueAnnouncements = queueAnnouncements }
    }

    private(set) var sidebarOrder: [AppModule] {
        didSet { Preferences.sidebarOrder = sidebarOrder }
    }

    var enabledSidebarModules: Set<AppModule> {
        didSet { Preferences.enabledSidebarModules = enabledSidebarModules }
    }

    var automaticallyHideUnavailableModules: Bool {
        didSet {
            Preferences.automaticallyHideUnavailableModules = automaticallyHideUnavailableModules
        }
    }

    init() {
        enabledAnnouncementCategories = Preferences.enabledAnnouncementCategories
        queueAnnouncements = Preferences.queueAnnouncements
        sidebarOrder = Preferences.sidebarOrder
        enabledSidebarModules = Preferences.enabledSidebarModules
        automaticallyHideUnavailableModules = Preferences.automaticallyHideUnavailableModules
    }

    func moveSidebarModule(_ module: AppModule, before destination: AppModule) {
        guard module != destination,
              module.section == destination.section,
              let sourceIndex = sidebarOrder.firstIndex(of: module),
              let destinationIndex = sidebarOrder.firstIndex(of: destination) else { return }
        var reordered = sidebarOrder
        let moved = reordered.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        reordered.insert(moved, at: insertionIndex)
        sidebarOrder = reordered
    }

    @discardableResult
    func moveSidebarModule(_ module: AppModule, by offset: Int) -> Bool {
        let sectionModules = sidebarOrder.filter { $0.section == module.section }
        guard let sectionIndex = sectionModules.firstIndex(of: module) else { return false }
        let destinationSectionIndex = sectionIndex + offset
        guard sectionModules.indices.contains(destinationSectionIndex),
              let sourceIndex = sidebarOrder.firstIndex(of: module),
              let destinationIndex = sidebarOrder.firstIndex(
                of: sectionModules[destinationSectionIndex]
              ) else { return false }
        sidebarOrder.swapAt(sourceIndex, destinationIndex)
        return true
    }
}
