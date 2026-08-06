//
//  OperationNotifier.swift
//  dsmaccess
//
//  Signal for the end of a long operation, over a channel chosen according to where the user
//  is.
//
//  In the background: a VoiceOver announcement is never heard and the result banner is only
//  seen on coming back — someone who starts a twenty-minute copy and goes off to do something
//  else learns nothing. The system notification is the only channel that reaches them.
//
//  In the foreground: the VoiceOver announcement already says everything, but nothing is heard
//  if attention is elsewhere on screen. A short sound doubles it — with no notification, whose
//  banner would be read out again by VoiceOver and make the same thing heard twice.
//

import AppKit
import UserNotifications

enum OperationNotifier {
    /// End-of-operation sound. `Glass` is one of the fourteen public macOS sounds, loadable
    /// by name: nothing is bundled in the app. The three-note sounds of `ToneLibrary` and
    /// those of Mail are private Apple resources — neither redistributable, nor at a path to
    /// count on.
    private static let successSoundName = "Glass"
    private static let failureSoundName = "Basso"
    /// Requested the first time a long operation is started, not at app launch: cold, the
    /// user cannot know what they will be notified about, and a macOS refusal is final.
    /// Never asks again for a decision already made.
    @MainActor
    static func prepare() async {
        guard Preferences.notifiesFinishedOperations else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else {
            return
        }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Signals the end of an operation from its outcome: success and failure each go out
    /// over the usual channel, a cancellation stays silent like everywhere else.
    @MainActor
    static func signalCompletion(of outcome: DSMOperationOutcome, title: String) async {
        switch outcome {
        case .success(let message):
            await signalCompletion(title: title, body: message, succeeded: true)
        case .failure(let message):
            await signalCompletion(title: title, body: message, succeeded: false)
        case .cancelled:
            break
        }
    }

    /// Signals the end of an operation over the channel that suits where the user is: a sound
    /// in front of the screen, a notification if they are elsewhere. Never both — the banner
    /// would be read out again by VoiceOver after the announcement.
    ///
    /// The sound doubles the announcement, it does not replace it: nothing is said by the
    /// sound alone.
    @MainActor
    static func signalCompletion(title: String, body: String, succeeded: Bool) async {
        if NSApp.isActive {
            playCompletionSound(succeeded: succeeded)
        } else {
            await postIfInBackground(title: title, body: body)
        }
    }

    /// `NSSound` can load a system sound by name. An unknown name — on a macOS that would
    /// have removed this one — returns `nil` and does nothing, which is the right outcome:
    /// the sound is only a reinforcement of the announcement.
    @MainActor
    static func playCompletionSound(succeeded: Bool) {
        guard Preferences.playsCompletionSound else { return }
        NSSound(named: succeeded ? successSoundName : failureSoundName)?.play()
    }

    /// Notifies only if the app is not in the foreground: in front of the screen, the
    /// VoiceOver announcement and the result banner already say everything, and a
    /// notification on top would only be a repetition to listen to twice.
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
        // Nil trigger: the task is already finished, the notification goes out now.
        try? await center.add(
            UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
        )
    }
}
