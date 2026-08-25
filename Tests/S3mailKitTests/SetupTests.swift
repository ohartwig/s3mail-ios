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
/// A SwiftPM test bundle has no host app, and without one the simulator refuses
/// keychain access with errSecMissingEntitlement (-34018). The code is fine;
/// the place it runs in has no keychain to talk to.
///
/// The skip is narrow on purpose: **only** -34018, and every other status still
/// fails the test. A skip that swallowed all keychain errors would turn a real
/// defect into a green run - and a keychain that silently does not store
/// anything is the kind of defect somebody finds when their phone forgets a
/// mailbox on the train.
///
/// This is unverified until the app exists to host it. That is written in the
/// README too, next to the Windows DPAPI path, which is compile-checked only
/// for the same sort of reason.
final class KeychainTests: XCTestCase {

    private let sample = Setup(bucket: "koh-post", prefix: "mail/test/",
                               region: "eu-north-1", accessKey: "AKIATEST",
                               secret: "geheim")

    /// errSecMissingEntitlement, and nothing else, is the environment talking.
    private func skipIfNoKeychain(_ error: Error) throws {
        if case Keychain.Failure.status(-34018) = error {
            throw XCTSkip("no keychain in a test bundle without a host app (-34018)")
        }
        throw error
    }

    private func run(_ body: () throws -> Void) throws {
        do { try body() } catch { try skipIfNoKeychain(error) }
    }

    override func tearDown() {
        try? Keychain.forget(id: sample.id)
        super.tearDown()
    }

    func testWhatGoesInComesBack() throws {
        try run {
            try Keychain.save(sample)
            XCTAssertEqual(try Keychain.load(id: sample.id), sample)
        }
    }

    /// A phone nobody has set up yet is not an error.
    func testAnUnknownMailboxIsNil() throws {
        // The value first, the assertion second: XCTAssertNil takes an
        // autoclosure and catches what it throws, so a keychain error would
        // never reach the skip above - it would just be a failure with no
        // explanation.
        try run {
            let nothing = try Keychain.load(id: "gibt-es-nicht/")
            XCTAssertNil(nothing)
        }
    }

    /// Saving twice must replace, not fail and not double: somebody who scans
    /// the code again after rotating a key expects the new one to win.
    func testSavingTwiceReplaces() throws {
        try run {
            try Keychain.save(sample)
            try Keychain.save(Setup(bucket: sample.bucket, prefix: sample.prefix,
                                    region: sample.region, accessKey: "AKIANEU",
                                    secret: "auch neu"))
            XCTAssertEqual(try Keychain.load(id: sample.id)?.accessKey, "AKIANEU")
        }
    }

    /// Forgetting something that is not there is not an error either - it is
    /// the state we wanted.
    func testForgettingTwiceIsFine() throws {
        try run {
            try Keychain.save(sample)
            try Keychain.forget(id: sample.id)
            try Keychain.forget(id: sample.id) // twice is not an error
            let gone = try Keychain.load(id: sample.id)
            XCTAssertNil(gone)
        }
    }
}
