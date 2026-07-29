//
//  OperationNotifier.swift
//  dsmaccess
//
//  Notification système à la fin d'une opération longue. Une annonce VoiceOver émise
//  pendant que l'app est en arrière-plan n'est jamais entendue, et le bandeau de résultat
//  n'est vu qu'en revenant : quelqu'un qui lance une copie de vingt minutes et va faire
//  autre chose n'apprend rien. La notification est le seul canal qui le rejoigne.
//

import AppKit
import UserNotifications

enum OperationNotifier {
    /// Demandée au premier lancement d'une opération longue, pas au démarrage de l'app :
    /// à froid, l'utilisateur ne peut pas savoir ce qui lui sera notifié, et un refus
    /// macOS est définitif. Ne redemande jamais une décision déjà prise.
    @MainActor
    static func prepare() async {
        guard Preferences.notifiesFinishedOperations else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else {
            return
        }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Notifie seulement si l'app n'est pas au premier plan : devant l'écran, l'annonce
    /// VoiceOver et le bandeau de résultat disent déjà tout, et une notification par-dessus
    /// ne serait qu'une répétition à écouter deux fois.
    @MainActor
    static func postIfInBackground(title: String, body: String) async {
        guard Preferences.notifiesFinishedOperations, !NSApp.isActive else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Déclencheur nul : la tâche est déjà terminée, la notification part maintenant.
        try? await center.add(
            UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
        )
    }
}
