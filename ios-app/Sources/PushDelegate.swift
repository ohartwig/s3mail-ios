// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import S3mailKit
import SwiftUI
import UserNotifications

/// The app's end of push.
///
/// What arrives says nothing - no sender, no subject, only "look". The app
/// fetches and decides for itself what, if anything, to put on the screen. The
/// reason is in koh-infra's mail/push.tf: a notification that carried the
/// subject would hand every subject line to Apple's servers, for a mail client
/// whose whole point is that the mail stays in a bucket its owner controls.
///
/// The price is honest: iOS may delay, coalesce or drop a silent notification
/// when it wants to save power. Pull to refresh is the answer to "I want it
/// now", and it always was.
final class PushDelegate: NSObject, UIApplicationDelegate {

    /// Set once the mailbox exists. Push is only worth asking about after
    /// setup: a permission prompt on the very first screen, before anybody has
    /// seen a single mail, is the prompt people refuse.
    static weak var mailbox: Mailbox?
    /// Called when a notification wakes the app, so the list refreshes.
    static var onWake: (() async -> Void)?

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        guard let mailbox = Self.mailbox else { return }
        // Off the main thread: this is two AWS calls, and the token arrives
        // while the first screen is being drawn.
        Task.detached {
            do {
                try mailbox.registerForPush(token: token)
            } catch {
                // Not shown to anybody. Push is a convenience; a mailbox that
                // works but cannot be woken is a working mailbox, and a dialog
                // about SNS at launch helps nobody. The next launch tries
                // again - registration is idempotent by design.
                NSLog("s3mail: push registration failed: \(error.localizedDescription)")
            }
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Happens on the simulator every time, and on a device whose profile
        // lacks the push entitlement. Both are worth a log line and nothing
        // more.
        NSLog("s3mail: no device token: \(error.localizedDescription)")
    }

    /// A silent notification: fetch, then tell iOS whether anything came of it.
    ///
    /// The completion handler has to be called, and reasonably soon - iOS
    /// measures how long this takes and how often it was worth it, and hands
    /// out fewer wake-ups to an app that dawdles or always answers .noData.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification info: [AnyHashable: Any],
                     fetchCompletionHandler done: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let mailbox = Self.mailbox else { return done(.noData) }
        Task.detached {
            do {
                let result = try mailbox.refresh()
                await Self.onWake?()
                done(result.new > 0 ? .newData : .noData)
            } catch {
                done(.failed)
            }
        }
    }
}

extension Mailbox {
    /// Asks for permission and, if given, for a device token.
    ///
    /// Asked after the mailbox is set up and not before: a permission prompt on
    /// the first screen, before anybody has seen a mail, is the one people
    /// refuse - and iOS only ever asks once.
    ///
    /// Silent notifications need no permission at all; the permission is for
    /// what the app puts on screen afterwards. Registration is what matters,
    /// and it happens either way.
    func askForPush() async {
        guard canPush else { return }
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}
