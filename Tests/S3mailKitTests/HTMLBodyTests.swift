// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import S3mailKit

/// The document a stranger's HTML is wrapped in.
///
/// These tests are about absences, and that is on purpose: what protects the
/// reader here is not something the code does but four things it refuses to
/// allow. An absence is exactly what a later change removes without noticing.
final class HTMLBodyTests: XCTestCase {

    func testNothingLoadsThatTheMailDidNotBring() {
        let doc = HTMLBody.document(html: "<p>hallo</p>", showImages: false)
        XCTAssertTrue(doc.contains("default-src 'none'"),
                      "without default-src 'none' the mail may fetch what it likes")
        XCTAssertTrue(doc.contains("Content-Security-Policy"))
        XCTAssertTrue(doc.contains("<p>hallo</p>"), "the mail itself is missing")
    }

    /// The one that matters most in practice. A remote image is a tracking
    /// pixel: the request alone tells the sender the address is read, when, and
    /// roughly from where.
    func testRemoteImagesAreBlockedUntilAsked() {
        let blocked = HTMLBody.document(html: "<img src=\"https://tracker.example/x.gif\">",
                                        showImages: false)
        XCTAssertTrue(blocked.contains("img-src data:"),
                      "remote images are allowed - every sender gets a read receipt")
        XCTAssertFalse(blocked.contains("img-src * data:"))

        let allowed = HTMLBody.document(html: "<img src=\"https://x/y\">", showImages: true)
        XCTAssertTrue(allowed.contains("img-src * data:"),
                      "asked for images and still blocked")
    }

    /// Inline styles are allowed, because without them almost every mail looks
    /// broken. Inline scripts are not, and no CSP directive should read that
    /// way.
    func testStylesAreAllowedAndScriptsAreNot() {
        let doc = HTMLBody.document(html: "x", showImages: false)
        XCTAssertTrue(doc.contains("style-src 'unsafe-inline'"))
        XCTAssertFalse(doc.contains("script-src"),
                       "a script-src at all would be a step towards allowing one")
        XCTAssertFalse(doc.contains("unsafe-eval"))
    }

    /// A mail laid out for a desktop is wider than a phone. It may scroll
    /// sideways inside its own box; it must not take the page with it.
    func testWideMailDoesNotStretchThePage() {
        let doc = HTMLBody.document(html: "<table><tr><td>breit</td></tr></table>",
                                    showImages: false)
        XCTAssertTrue(doc.contains("max-width: 100%"))
        XCTAssertTrue(doc.contains("width=device-width"))
    }

    /// The mail goes in as it came. Nothing here sanitises it - the CSP and the
    /// missing JavaScript do the work - so a test that expected escaping would
    /// be describing a defence that is not there.
    func testTheMailIsNotRewritten() {
        let ugly = "<div class=\"x\" style=\"color:red\">&amp; ümläute <b>fett</b></div>"
        let doc = HTMLBody.document(html: ugly, showImages: false)
        XCTAssertTrue(doc.contains(ugly), "the mail was altered on the way in")
    }
}
