// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import S3mailKit

/// How a phone learns what mailbox it is, and where it keeps that.
final class SetupTests: XCTestCase {

    private let sample = Setup(bucket: "koh-post", prefix: "mail/ole/",
                               region: "eu-north-1", from: "post@firma.de",
                               label: "Post", accessKey: "AKIABEISPIEL",
                               secret: "geheim")

    func testAQRPayloadSurvivesTheRoundTrip() throws {
        let back = try Setup.decode(try sample.encode())
        XCTAssertEqual(back, sample)
    }

    /// The classic S3 mistake, and the reason to refuse it here rather than
    /// later: a prefix without a slash also matches the start of another name.
    /// "mail" catches "mailbox-old/" too, and the mailbox would quietly contain
    /// somebody else's messages.
    func testAPrefixWithoutASlashIsRefused() {
        let bad = Setup(bucket: "b", prefix: "mail", region: "eu-north-1",
                        accessKey: "AKIA", secret: "s")
        XCTAssertThrowsError(try Setup.decode(try bad.encode())) { error in
            XCTAssertEqual(error as? Setup.Problem, .prefixNotAFolder("mail"))
        }
    }

    /// An empty prefix is a whole bucket, and that is a legitimate choice.
    func testAnEmptyPrefixIsFine() throws {
        let whole = Setup(bucket: "b", prefix: "", region: "eu-north-1",
                          accessKey: "AKIA", secret: "s")
        XCTAssertNoThrow(try Setup.decode(try whole.encode()))
    }

    /// A half-read code has to fail here, where the cause is still visible -
    /// not three screens later with an error about S3.
    func testAHalfReadCodeIsRefused() {
        XCTAssertThrowsError(try Setup.decode("nicht mal JSON"))
        let missing = #"{"bucket":"","prefix":"mail/","region":"eu-north-1","from":"","label":"","accessKey":"A","secret":"s"}"#
        XCTAssertThrowsError(try Setup.decode(missing)) { error in
            XCTAssertEqual(error as? Setup.Problem, .missing("a bucket"))
        }
    }

    /// The identity comes from bucket and prefix, like on the desktop - not
    /// from a position in a list. Somebody who reorders their mailboxes must
    /// not lose the state that belongs to them.
    func testTheIdentityIsBucketAndPrefix() {
        XCTAssertEqual(sample.id, "koh-post/mail/ole/")
    }
}

/// The keychain, with the same attributes a device gets.
///
/// These skip, and the reason is worth writing down rather than working around.
