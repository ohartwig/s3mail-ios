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

/// The setup code and push.
///
/// The important one is the old code: setup codes get shown, photographed and
/// pasted, and one made before push existed is still a valid way into a
/// mailbox. A strict decoder would refuse it - and the refusal would name a
/// field about notifications while somebody is trying to read their mail.
final class SetupPushTests: XCTestCase {

    func testACodeFromBeforePushStillWorks() throws {
        let old = #"""
        {"bucket":"post","prefix":"mail/ole/","region":"eu-north-1",
         "from":"post@firma.de","label":"Post","accessKey":"","secret":""}
        """#
        let setup = try Setup.fromCode(old)
        XCTAssertEqual(setup.bucket, "post")
        XCTAssertTrue(setup.pushApps.isEmpty)
        XCTAssertEqual(setup.pushTopic, "")
    }

    func testTheEnvironmentsSurviveTheRoundTrip() throws {
        let code = #"""
        {"bucket":"post","prefix":"mail/ole/","region":"eu-north-1",
         "accessKey":"","secret":"",
         "pushApps":{"production":"arn:prod","development":"arn:sandbox"},
         "pushTopic":"arn:topic"}
        """#
        let setup = try Setup.fromCode(code)
        // Named, not positional: two ARNs look alike, and a device that picks
        // the wrong one gets an endpoint that receives nothing.
        XCTAssertEqual(setup.pushApps["development"], "arn:sandbox")
        XCTAssertEqual(setup.pushApps["production"], "arn:prod")
        XCTAssertEqual(setup.pushTopic, "arn:topic")
    }

    /// A bucket is still required. A code without one is not an old code, it is
    /// a wrong one.
    func testABucketIsStillRequired() {
        XCTAssertThrowsError(try Setup.fromCode(#"{"region":"eu-north-1"}"#))
    }

    /// The simulator has no provisioning profile, so it has no environment -
    /// and it cannot receive a notification anyway. An honest nil beats a guess
    /// that registers a simulator against production.
    func testWithoutAProfileThereIsNoEnvironment() {
        XCTAssertNil(PushEnvironment.current(bundle: .module))
    }

    /// The one piece of string handling on this path. A token turned into
    /// something other than lowercase hex produces a device that never receives
    /// anything and never reports an error.
    func testATokenBecomesLowercaseHex() {
        let token = Data([0x00, 0x0f, 0xa0, 0xff])
        let hex = token.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "000fa0ff")
        // What it must never be: Data.description used to give hex and now
        // prints "4 bytes".
        XCTAssertNotEqual(hex, token.description)
    }
}

/// The split between the two readers, which is the bug this file found.
///
/// The assistant's code carries no key - that is its whole point. A reader that
/// demands one refuses every real code, and the message it gives ("the code is
/// missing an access key") sends whoever reads it looking in the wrong place.
final class SetupCodeVsCompleteTests: XCTestCase {

    private let realCode = #"""
    {"bucket":"koh-findready-mail","prefix":"mail/ole/","region":"eu-north-1",
     "from":"ole@findready.ai","label":"","accessKey":"","secret":"",
     "pushApps":{},"pushTopic":""}
    """#

    func testTheAssistantsCodeIsAccepted() throws {
        let setup = try Setup.fromCode(realCode)
        XCTAssertEqual(setup.bucket, "koh-findready-mail")
        XCTAssertEqual(setup.accessKey, "", "the code must not carry a key")
    }

    func testTheSameCodeIsNotACompleteSetup() {
        // Coming out of the keychain without a key means something is broken,
        // and there the strictness is right.
        XCTAssertThrowsError(try Setup.decode(realCode))
    }

    /// Both readers still insist on a bucket: a code without one is not an
    /// incomplete code, it is a wrong one.
    func testBothInsistOnABucket() {
        let noBucket = #"{"region":"eu-north-1","accessKey":"a","secret":"b"}"#
        XCTAssertThrowsError(try Setup.fromCode(noBucket))
        XCTAssertThrowsError(try Setup.decode(noBucket))
    }
}

/// Pairing with a PIN.
///
/// The unsealing itself is Go's and is tested there. What is tested here is the
/// seam: that a real code from the wizard is recognised as needing a PIN, that
/// the wrong PIN says so, and that an opened code is actually usable.
final class PairingTests: XCTestCase {

    /// A code as the wizard writes it: an access key in the clear, no secret,
    /// and a sealed box beside it.
    private let code = #"""
    {"bucket":"koh-findready-mail","prefix":"mail/ole/","region":"eu-north-1",
     "from":"ole@findready.ai","label":"Ole",
     "accessKey":"AKIAIOSFODNN7EXAMPLE","secret":"",
     "sealed":"AAAA","salt":"BBBB","pushApps":{},"pushTopic":""}
    """#

    func testACodeWithASealedKeyAsksForAPIN() throws {
        let setup = try Setup.fromCode(code)
        XCTAssertTrue(setup.needsPIN)
        XCTAssertEqual(setup.secret, "", "the secret must not be in the code")
        XCTAssertEqual(setup.accessKey, "AKIAIOSFODNN7EXAMPLE",
                       "the key id is not secret and travels in the clear")
    }

    /// The property the whole exercise exists for: the code alone is not access.
    func testTheCodeAloneCarriesNoSecret() throws {
        let setup = try Setup.fromCode(code)
        XCTAssertTrue(setup.secret.isEmpty)
        XCTAssertFalse(setup.sealed.isEmpty)
        XCTAssertFalse(setup.salt.isEmpty)
    }

    /// An older code carries no sealed box and expects a typed key. Such codes
    /// exist on real screens; refusing them would be a worse answer than a
    /// longer form.
    func testACodeFromBeforePairingNeedsNoPIN() throws {
        let old = #"""
        {"bucket":"post","prefix":"mail/ole/","region":"eu-north-1",
         "accessKey":"","secret":""}
        """#
        XCTAssertFalse(try Setup.fromCode(old).needsPIN)
    }

    /// Garbage in the sealed box has to come back as a wrong PIN, not as a
    /// crash and not as a mailbox with an empty key that fails at the first S3
    /// request.
    func testAnUnopenableBoxIsAnError() throws {
        let setup = try Setup.fromCode(code)
        XCTAssertThrowsError(try setup.unlock(pin: "123456"))
    }

    func testAPINOfTheWrongLengthIsRefusedBeforeTheWork() throws {
        let setup = try Setup.fromCode(code)
        // Not "wrong PIN" - a length error is something the field should have
        // caught, and saying so sends the reader to the right place.
        XCTAssertThrowsError(try setup.unlock(pin: "12345"))
    }

    /// Unlocking a code that needs no PIN gives it back unchanged, so a caller
    /// need not branch.
    func testUnlockingWhatNeedsNoPINChangesNothing() throws {
        let old = try Setup.fromCode(#"{"bucket":"post","region":"eu-north-1"}"#)
        let same = try old.unlock(pin: "000000")
        XCTAssertEqual(old, same)
    }
}
