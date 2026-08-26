// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The question after a send that nobody saw finish.
///
/// iOS ends apps that are in the background at the wrong moment, without asking
/// and without warning - so a send interrupted halfway is not an edge case
/// here, it is Tuesday. store/sending.go writes down the attempt before it
/// happens; what it cannot do is know how it ended.
///
/// The core closes every case it can decide on its own: a copy in sent/ means
/// the mail went out. What arrives here is only what nobody but the person can
/// answer, and it must be asked rather than guessed. Guessing "sent" loses a
/// mail. Guessing "not sent" sends it twice. Both are worse than a question.
struct PendingSendsView: ViewModifier {
    let mailbox: Mailbox
    @State private var open: [PendingSend] = []

    func body(content: Content) -> some View {
        content
            .task { await ask() }
            .alert(t("pending.title"), isPresented: .constant(!open.isEmpty),
                   presenting: open.first) { pending in
                Button(t("pending.yes")) { answer(pending, sent: true) }
                Button(t("pending.no")) { answer(pending, sent: false) }
            } message: { pending in
                // The subject and recipient are in the question on purpose: the
                // person has to look this up in their own sent mail, and they
                // cannot do that from "a message".
                Text(t("pending.body") + "\n\n" + pending.subject + "\n" + pending.to)
            }
    }

    private func ask() async {
        // Off the main thread: this lists the drafts folder, and on a slow
        // connection the first screen would otherwise sit still.
        //
        // The mailbox is read here, on the main actor, and handed over as a
        // value. Reaching for `self.mailbox` from inside the detached task
        // would read a main-actor property from somewhere else - a warning
        // today and an error under Swift 6.
        let mailbox = self.mailbox
        open = (try? await Task.detached { try mailbox.pendingSends() }.value) ?? []
    }

    private func answer(_ pending: PendingSend, sent: Bool) {
        // Dropped from the list first, so the alert closes even if the write
        // fails. A question that will not go away is worse than one that has to
        // be asked again on the next start - and it will be, because the marker
        // is still there.
        open.removeAll { $0.id == pending.id }
        let mailbox = self.mailbox
        let key = pending.id
        Task.detached { try? mailbox.resolve(pending: key, sent: sent) }
    }
}

public extension View {
    /// Ask about unfinished sends when this view appears. Belongs on whatever
    /// the app shows first.
    func askingAboutUnfinishedSends(_ mailbox: Mailbox) -> some View {
        modifier(PendingSendsView(mailbox: mailbox))
    }
}
