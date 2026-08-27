// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The mailboxes this device holds, and what may be done with them.
///
/// Handed to MailboxView rather than reached for, because which mailboxes exist
/// is the app's business: the keychain and the stored identities live one layer
/// up, and a view that went looking for them would be a second place that knows
/// how they are stored.
///
/// A value type and not a view, so the menu can be checked in a test without a
/// screen: what a switcher offers is a decision, and decisions are worth
/// pinning down. Whether it is drawn as a menu or something else is not.
public struct MailboxSwitcher {
    public struct Entry: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let current: Bool

        public init(id: String, title: String, current: Bool) {
            self.id = id
            self.title = title
            self.current = current
        }
    }

    public let entries: [Entry]
    public let pick: (String) -> Void
    public let addAnother: () -> Void
    public let disconnect: () -> Void

    public init(entries: [Entry],
                pick: @escaping (String) -> Void,
                addAnother: @escaping () -> Void,
                disconnect: @escaping () -> Void) {
        self.entries = entries
        self.pick = pick
        self.addAnother = addAnother
        self.disconnect = disconnect
    }

    /// Whether the list of mailboxes is worth showing at all.
    ///
    /// With one mailbox the list is the title bar repeated, so the menu holds
    /// only what can be done. The entry to add another stays either way - it is
    /// how the second one ever arrives.
    public var showsList: Bool { entries.count > 1 }
}
