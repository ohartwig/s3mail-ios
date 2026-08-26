// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import S3mailKit

/// The app. Almost nothing lives here.
///
/// Everything that decides anything is in S3mailKit, and below that in the same
/// Go code the desktop runs. What is left at this level is the one question an
/// app has to answer that a library cannot: is this device set up yet, and for
/// which mailbox.
@main
struct S3mailApp: App {
    // UIApplicationDelegate and not the SwiftUI lifecycle alone: the device
    // token arrives through a delegate callback, and there is no SwiftUI
    // equivalent for it.
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    @State private var device = Device()

    var body: some Scene {
        WindowGroup {
            RootView(device: device)
        }
    }
}

/// What this device knows about itself.
///
/// The mailbox's identity - bucket and prefix - sits in UserDefaults, and the
/// access key does not: the keychain holds that, and only that. The split is
/// deliberate. A bucket name is not a secret and putting it behind Face ID buys
/// nothing; a secret access key in UserDefaults would be readable out of an
/// unencrypted backup.
@Observable
final class Device {
    private static let key = "mailbox.id"

    private(set) var setup: Setup?
    private(set) var mailbox: Mailbox?
    var problem: String?

    init() { reload() }

    var isSetUp: Bool { mailbox != nil }

    func reload() {
        guard let id = UserDefaults.standard.string(forKey: Self.key) else { return }
        do {
            guard let setup = try Keychain.load(id: id) else {
                // The identity is known and the key is gone: somebody restored
                // this device from a backup, which does not carry keychain
                // items marked as this one is. Forget the identity too, or the
                // app shows an empty mailbox it cannot explain.
                UserDefaults.standard.removeObject(forKey: Self.key)
                return
            }
            adopt(setup)
        } catch {
            problem = error.localizedDescription
        }
    }

    func adopt(_ setup: Setup) {
        do {
            try Keychain.save(setup)
            UserDefaults.standard.set(setup.id, forKey: Self.key)
            self.setup = setup
            self.mailbox = try Mailbox(setup: setup)
            self.problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Takes the mailbox off this device. The bucket is untouched - this is one
    /// device forgetting, not a mailbox being deleted, and the difference has
    /// to be visible in what it does.
    func forget() {
        if let setup { try? Keychain.forget(id: setup.id) }
        UserDefaults.standard.removeObject(forKey: Self.key)
        setup = nil
        mailbox = nil
    }
}
