// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Which of a mail's two bodies actually gets shown.
///
/// Anything sent by a machine arrives as multipart/alternative: an HTML part
/// carrying the layout, and a plain-text part as the fallback for clients that
/// cannot render it. Which one a client picks is therefore not a detail about
/// unusual mail - it is the decision that governs almost every mail that is not
/// typed by a person.
///
/// This app used to require the text part to be *empty* before it would render
/// HTML, so the fallback won every time both were present and the phone showed
/// the stripped version of what the desktop showed in full. Same mailbox, two
/// answers, and the one on the small screen was the worse one.
///
/// It lives in its own type rather than inside the view because a decision made
/// inline in a `body` builder cannot be tested, and this one is worth a test:
/// it is one `if` away from being wrong again, and being wrong is quiet.
enum MessageBody: Equatable {
    /// Render it, sandboxed - see HTMLBody for what that means.
    case html(String)
    /// Show it as text.
    case text(String)
    /// Neither part carried anything. Rare, and not an error: a mail can be
    /// nothing but attachments.
    case empty

    /// HTML when the mail brought any, the text part otherwise.
    ///
    /// The same order the desktop uses in inbox.html, and deliberately so: the
    /// two front-ends read one bucket, and a reader who moves between them
    /// should not have to learn which one shows the real mail.
    static func choose(text: String, html: String) -> MessageBody {
        if !html.isEmpty { return .html(html) }
        if !text.isEmpty { return .text(text) }
        return .empty
    }
}
