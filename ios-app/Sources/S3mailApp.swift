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
/// The mailboxes' identities - bucket and prefix - sit in UserDefaults, and the
/// access keys do not: the keychain holds those, and only those. The split is
/// deliberate. A bucket name is not a secret and putting it behind Face ID buys
/// nothing; a secret access key in UserDefaults would be readable out of an
/// unencrypted backup.
///
/// There can be several. The desktop has carried a list of accounts since it
/// had more than one, and a phone that holds exactly one was the odd one out:
/// somebody with a work mailbox and a private one had to decide which of them
/// their phone was for.
@Observable
final class Device {
    /// The identities, in the order they were paired.
    private static let listKey = "mailbox.ids"
    /// Which of them is on screen. Remembered so a launch comes back to the
    /// mailbox somebody was last reading, not to whichever was paired first.
    private static let currentKey = "mailbox.current"
    /// What the single-mailbox era wrote. Read once, turned into a list of one,
    /// then removed. It has to keep working: it is on real phones.
    private static let legacyKey = "mailbox.id"

    private(set) var accounts: [Setup] = []
    private(set) var current: Setup?
    private(set) var mailbox: Mailbox?
    var problem: String?

    init() { reload() }

    var isSetUp: Bool { mailbox != nil }

    func reload() {
        adoptSingleMailboxLayout()

        var found: [Setup] = []
        for id in UserDefaults.standard.stringArray(forKey: Self.listKey) ?? [] {
            do {
                // An identity whose key is gone: somebody restored this device
                // from a backup, which does not carry keychain items marked as
                // these are. Dropping it beats an empty mailbox the app cannot
                // explain - the same reasoning as before, now per mailbox.
                if let setup = try Keychain.load(id: id) { found.append(setup) }
            } catch {
                problem = error.localizedDescription
            }
        }
        accounts = found
        rememberList()

        let wanted = UserDefaults.standard.string(forKey: Self.currentKey)
        show(found.first { $0.id == wanted } ?? found.first)
    }

    /// Turns what the single-mailbox era wrote into a list of one.
    ///
    /// Runs once and leaves nothing behind, so a downgrade is the only thing
    /// that loses the pairing - and a downgrade would not have read the list
    /// anyway.
    private func adoptSingleMailboxLayout() {
        let defaults = UserDefaults.standard
        guard let only = defaults.string(forKey: Self.legacyKey) else { return }
        if defaults.stringArray(forKey: Self.listKey) == nil {
            defaults.set([only], forKey: Self.listKey)
            defaults.set(only, forKey: Self.currentKey)
        }
        defaults.removeObject(forKey: Self.legacyKey)
    }

    /// Takes a freshly scanned mailbox, or replaces one that was paired again.
    func adopt(_ setup: Setup) {
        do {
            try Keychain.save(setup)
            if accounts.contains(where: { $0.id == setup.id }) {
                // Paired again, usually because the desktop handed out a new
                // key. Same mailbox, so it keeps its place in the list.
                accounts = accounts.map { $0.id == setup.id ? setup : $0 }
            } else {
                accounts.append(setup)
            }
            rememberList()
            show(setup)
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Puts another of the paired mailboxes on screen.
    func switchTo(id: String) {
        guard let setup = accounts.first(where: { $0.id == id }), setup.id != current?.id else {
            return
        }
        show(setup)
    }

    /// Takes the mailbox on screen off this device. The bucket is untouched -
    /// this is one device forgetting, not a mailbox being deleted, and the
    /// difference has to be visible in what it does.
    ///
    /// What is left of the list moves up. Forgetting the last one lands on the
    /// scanner, which is where somebody with nothing paired belongs.
    func forget() {
        guard let going = current else { return }
        try? Keychain.forget(id: going.id)
        accounts.removeAll { $0.id == going.id }
        rememberList()
        show(accounts.first)
    }

    private func rememberList() {
        UserDefaults.standard.set(accounts.map(\.id), forKey: Self.listKey)
    }

    private func show(_ setup: Setup?) {
        current = setup
        guard let setup else {
            mailbox = nil
            UserDefaults.standard.removeObject(forKey: Self.currentKey)
            return
        }
        do {
            mailbox = try Mailbox(setup: setup)
            UserDefaults.standard.set(setup.id, forKey: Self.currentKey)
            problem = nil
        } catch {
            mailbox = nil
            problem = error.localizedDescription
        }
    }
}
