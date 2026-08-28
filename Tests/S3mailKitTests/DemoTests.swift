// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import S3mailKit

/// The sample mailbox, opened the way the app opens it.
///
/// This is the one test that goes all the way through: Swift, the gomobile
/// bridge, the Go core, s3fake and mimeparse. If the sample stops opening,
/// nobody can review the app and nothing can be screenshotted - so it is worth
/// finding out here rather than from a rejection.
final class DemoTests: XCTestCase {

    func testTheSampleOpensAndHasMail() throws {
        let mailbox = try Mailbox.demo(language: "en")

        XCTAssertTrue(mailbox.isDemo, "the sample does not know that it is one")

        let folders = try mailbox.folders()
        XCTAssertFalse(folders.isEmpty, "no folders - the sidebar would be empty")

        let inbox = try mailbox.search("", folder: "")
        XCTAssertGreaterThanOrEqual(inbox.count, 3,
                                    "the inbox looks empty in a screenshot")
        for message in inbox {
            XCTAssertFalse(message.subject.isEmpty, "a message without a subject")
            XCTAssertFalse(message.from.isEmpty, "a message without a sender")
        }
    }

    /// There is nowhere for a sample to send to, and a button that cannot work
    /// is worse than no button.
    func testTheSampleCannotSend() throws {
        XCTAssertFalse(try Mailbox.demo(language: "en").canSend)
    }

    /// A language nobody wrote sample mail in still gets a mailbox, not an
    /// empty screen.
    func testAnUnknownLanguageStillOpens() throws {
        let mailbox = try Mailbox.demo(language: "fr")
        XCTAssertFalse(try mailbox.search("", folder: "").isEmpty)
    }
}

/// What the menu offers when what is on screen is a sample.
final class SampleSwitcherTests: XCTestCase {

    func testTheSampleHasNothingToDisconnectFrom() {
        let sample = MailboxSwitcher(entries: [], pick: { _ in },
                                     addAnother: {}, demo: true)

        XCTAssertNil(sample.disconnect,
                     "offering to unpair a sample is a lie - it is paired with nothing")
        XCTAssertFalse(sample.showsList, "one mailbox needs no list of mailboxes")
        XCTAssertTrue(sample.demo)
    }

    /// And a real mailbox keeps the way out it had.
    func testARealMailboxCanStillBeDisconnected() {
        var asked = false
        let real = MailboxSwitcher(entries: [.init(id: "b/p/", title: "ole", current: true)],
                                   pick: { _ in }, addAnother: {},
                                   disconnect: { asked = true })

        XCTAssertNotNil(real.disconnect)
        real.disconnect?()
        XCTAssertTrue(asked)
        XCTAssertFalse(real.demo)
    }
}
