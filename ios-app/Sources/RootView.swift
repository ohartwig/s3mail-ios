// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import S3mailKit

/// Mailbox, sample or scanner, and the ways between them.
struct RootView: View {
    @Bindable var device: Device
    @State private var addingAnother = false
    /// Held here and not in Device: the sample is not something this device
    /// owns. Nothing about it reaches the keychain, and closing it leaves no
    /// trace.
    @State private var sample: Mailbox?

    var body: some View {
        Group {
            if let mailbox = device.mailbox {
                MailboxView(mailbox: mailbox, switcher: switcher)
                    // Rebuilt when the mailbox changes, and that is the point:
                    // MailboxView keeps its model in @State, which SwiftUI
                    // creates once per identity. Without this, switching would
                    // change the title and keep showing the other mailbox's
                    // mail.
                    .id(device.current?.id)
                    .task(id: device.current?.id) {
                        // After setup, not before: a permission prompt on the
                        // first screen is the one people refuse, and iOS asks
                        // only once.
                        PushDelegate.mailbox = mailbox
                        PushDelegate.accounts = device.accounts
                        await mailbox.askForPush()
                    }
            } else if let sample {
                // No push, no keychain, no pairing. A sample that asked for
                // notification permission would be asking on behalf of mail
                // that does not exist.
                MailboxView(mailbox: sample, switcher: sampleSwitcher)
                    .id("sample")
            } else {
                SetupView(device: device, onDemo: openSample)
            }
        }
        // Over the mailbox rather than in place of it: adding a second mailbox
        // should not look like losing the first.
        .sheet(isPresented: $addingAnother) {
            SetupView(device: device)
        }
        // On the mailbox itself and not on how many there are: pairing the same
        // mailbox again is the common case - it is what a fresh setup code
        // produces - and it leaves the count where it was. Setup is Equatable,
        // so a new key counts as a change and the scanner closes either way.
        .onChange(of: device.current) { _, _ in addingAnother = false }
    }

    private func openSample() {
        // A sample that fails to open is worth no dialog: the button simply
        // does nothing and the scanner stays, which is where somebody without a
        // mailbox belongs anyway.
        sample = try? Mailbox.demo()
    }

    private var switcher: MailboxSwitcher {
        MailboxSwitcher(
            entries: device.accounts.map {
                .init(id: $0.id, title: $0.title, current: $0.id == device.current?.id)
            },
            pick: { device.switchTo(id: $0) },
            addAnother: { addingAnother = true },
            disconnect: { device.forget() })
    }

    /// What the sample offers: one way out, and it leads to setting up a real
    /// mailbox. No list - there is one - and nothing to disconnect from.
    private var sampleSwitcher: MailboxSwitcher {
        MailboxSwitcher(entries: [], pick: { _ in },
                        addAnother: { sample = nil },
                        demo: true)
    }
}
