// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import S3mailKit

/// What the switcher offers, without a screen to look at.
final class MailboxSwitcherTests: XCTestCase {

    private func switcher(_ entries: [MailboxSwitcher.Entry]) -> MailboxSwitcher {
        MailboxSwitcher(entries: entries, pick: { _ in }, addAnother: {}, disconnect: {})
    }

    /// One mailbox needs no list of mailboxes: it would be the title bar
    /// repeated. The way to add a second stays regardless - it is how the
    /// second one ever arrives.
    func testOneMailboxNeedsNoList() {
        let one = switcher([.init(id: "b/mail/ole/", title: "ole", current: true)])
        XCTAssertFalse(one.showsList)
    }

    func testTwoMailboxesDo() {
        let two = switcher([
            .init(id: "b/mail/ole/", title: "ole", current: true),
            .init(id: "b/mail/work/", title: "Arbeit", current: false),
        ])
        XCTAssertTrue(two.showsList)
    }
}

/// What a mailbox is called when there are several of them.
final class SetupTitleTests: XCTestCase {

    private func setup(label: String = "", from: String = "",
                       prefix: String = "mail/ole/", bucket: String = "koh-post") -> Setup {
        Setup(bucket: bucket, prefix: prefix, region: "eu-north-1",
              from: from, label: label, accessKey: "AKIA", secret: "x")
    }

    func testTheLabelWinsWhenThereIsOne() {
        XCTAssertEqual(setup(label: "Privat", from: "ole@example.org").title, "Privat")
    }

    func testOtherwiseTheAddressItSendsAs() {
        XCTAssertEqual(setup(from: "ole@example.org").title, "ole@example.org")
    }

    /// The prefix without its slash. Not the bucket: several mailboxes usually
    /// share one, and a switcher listing the same word twice is worse than no
    /// switcher at all.
    func testOtherwiseThePrefix() {
        XCTAssertEqual(setup().title, "mail/ole")
    }

    func testTheBucketIsTheLastResort() {
        XCTAssertEqual(setup(prefix: "").title, "koh-post")
    }
}
