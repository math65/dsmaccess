//
//  OperationNotifier.swift
//  dsmaccess
//
//  Signal de fin d'une opération longue, par un canal choisi selon l'endroit où se trouve
//  l'utilisateur.
//
//  En arrière-plan : une annonce VoiceOver n'est jamais entendue et le bandeau de résultat
//  n'est vu qu'en revenant — quelqu'un qui lance une copie de vingt minutes et va faire autre
//  chose n'apprend rien. La notification système est le seul canal qui le rejoigne.
//
//  Au premier plan : l'annonce VoiceOver dit déjà tout, mais rien ne se fait entendre si
//  l'attention est ailleurs sur l'écran. Un son court la double — sans notification, dont la
//  bannière serait relue par VoiceOver et ferait entendre deux fois la même chose.
//

import AppKit
import UserNotifications

enum OperationNotifier {
    /// Son de fin d'opération. `Glass` fait partie des quatorze sons publics de macOS,
    /// chargeables par leur nom : rien n'est embarqué dans l'app. Les sons à trois notes de
    /// `ToneLibrary` et ceux de Mail sont des ressources privées d'Apple — ni redistribuables,
    /// ni à un chemin sur lequel compter.
    private static let successSoundName = "Glass"
    private static let failureSoundName = "Basso"
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

    /// Signale la fin d'une opération par le canal qui convient à l'endroit où se trouve
    /// l'utilisateur : un son devant l'écran, une notification s'il est ailleurs. Jamais les
    /// deux — la bannière serait relue par VoiceOver après l'annonce.
    ///
    /// Le son double l'annonce, il ne la remplace pas : rien n'est dit par le son seul.
    @MainActor
    static func signalCompletion(title: String, body: String, succeeded: Bool) async {
        if NSApp.isActive {
            playCompletionSound(succeeded: succeeded)
        } else {
            await postIfInBackground(title: title, body: body)
        }
    }

    /// `NSSound` sait charger un son système par son nom. Un nom inconnu — sur un macOS qui
    /// aurait retiré celui-ci — rend `nil` et ne fait rien, ce qui est la bonne issue : le son
    /// n'est qu'un renfort de l'annonce.
    @MainActor
    static func playCompletionSound(succeeded: Bool) {
        guard Preferences.playsCompletionSound else { return }
        NSSound(named: succeeded ? successSoundName : failureSoundName)?.play()
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
