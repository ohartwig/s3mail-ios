// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import S3mailKit

/// Which body a mail shows, and why it is worth a test at all.
///
/// The bug this replaces was one `&&` long and survived a release: HTML was
/// only rendered when the text part was empty, which is the rarer half of the
/// cases. Every newsletter has both parts, so every newsletter showed its plain
/// fallback while the desktop showed the mail.
final class MessageBodyTests: XCTestCase {

    /// The normal case, and the one that used to be wrong.
    func testAMailWithBothPartsShowsTheHTML() {
        let got = MessageBody.choose(text: "Plain fallback", html: "<p>Real mail</p>")
        XCTAssertEqual(got, .html("<p>Real mail</p>"),
                       "the plain fallback won over the mail the sender wrote")
    }

    func testHTMLAloneIsShown() {
        XCTAssertEqual(MessageBody.choose(text: "", html: "<p>x</p>"), .html("<p>x</p>"))
    }

    /// Mail typed by a person usually has no HTML part at all.
    func testTextAloneIsShown() {
        XCTAssertEqual(MessageBody.choose(text: "Hello", html: ""), .text("Hello"))
    }

    /// Not an error: a mail can be nothing but attachments.
    func testNeitherPartIsNotAFailure() {
        XCTAssertEqual(MessageBody.choose(text: "", html: ""), .empty)
    }

    /// The order matches inbox.html, and that is the point rather than a
    /// coincidence: one bucket read by two front-ends should not need the
    /// reader to know which one shows the real thing.
    func testTheChoiceMatchesTheDesktop() {
        // inbox.html: `if (m.html) { ...render... } else { ...text... }`
        for (text, html) in [("t", "h"), ("", "h"), ("t", "")] {
            let got = MessageBody.choose(text: text, html: html)
            if !html.isEmpty {
                XCTAssertEqual(got, .html(html), "html present but not chosen")
            } else {
                XCTAssertEqual(got, .text(text), "no html, so the text should show")
            }
        }
    }
}
