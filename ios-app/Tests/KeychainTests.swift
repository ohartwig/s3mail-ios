// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import XCTest
import S3mailKit
@testable import s3mail

/// The keychain, for real.
///
/// These tests used to sit in the package's own bundle and skip themselves: a
/// SwiftPM test bundle has no host app, and without one the simulator refuses
/// keychain access with errSecMissingEntitlement (-34018). A skipped test is
/// not a passing test, and what it was guarding is not small - a keychain that
/// silently stores nothing is the defect somebody finds when their phone has
/// forgotten a mailbox on a train.
///
/// So they moved here, into a bundle the app hosts. Nothing skips any more.
final class KeychainTests: XCTestCase {

    private let sample = Setup(bucket: "koh-post", prefix: "mail/test/",
                               region: "eu-north-1", accessKey: "AKIATEST",
                               secret: "geheim")

    override func setUp() {
        super.setUp()
        try? Keychain.forget(id: sample.id)
    }

    override func tearDown() {
        try? Keychain.forget(id: sample.id)
        super.tearDown()
    }

    func testWhatGoesInComesBack() throws {
        try Keychain.save(sample)
        XCTAssertEqual(try Keychain.load(id: sample.id), sample)
    }

    /// A phone nobody has set up yet is not an error.
    func testAnUnknownMailboxIsNil() throws {
        // The value first, the assertion second: XCTAssertNil takes an
        // autoclosure and catches what it throws, so an error would never reach
        // the report - it would be a failure with no explanation.
        let nothing = try Keychain.load(id: "does-not-exist/")
        XCTAssertNil(nothing)
    }

    /// Saving twice replaces, and does not fail and does not double: somebody
    /// who scans the code again after rotating a key expects the new one to win.
    func testSavingTwiceReplaces() throws {
        try Keychain.save(sample)
        try Keychain.save(Setup(bucket: sample.bucket, prefix: sample.prefix,
                                region: sample.region, accessKey: "AKIANEW",
                                secret: "also new"))
        XCTAssertEqual(try Keychain.load(id: sample.id)?.accessKey, "AKIANEW")
    }

    /// Forgetting something that is not there is not an error either - it is
    /// the state we wanted.
    func testForgettingTwiceIsFine() throws {
        try Keychain.save(sample)
        try Keychain.forget(id: sample.id)
        try Keychain.forget(id: sample.id)
        let gone = try Keychain.load(id: sample.id)
        XCTAssertNil(gone)
    }

    func testTheSecretIsNotInUserDefaults() throws {
        // The split this whole design rests on: the mailbox's identity is not a
        // secret and sits in UserDefaults; the key is and does not. A secret in
        // UserDefaults would be readable out of an unencrypted backup.
        try Keychain.save(sample)
        let dump = UserDefaults.standard.dictionaryRepresentation()
            .description
        XCTAssertFalse(dump.contains("geheim"), "the secret reached UserDefaults")
        XCTAssertFalse(dump.contains("AKIATEST"), "the access key reached UserDefaults")
    }
}

/// What the device remembers between launches.
final class DeviceTests: XCTestCase {

    private let sample = Setup(bucket: "koh-post", prefix: "mail/device/",
                               region: "eu-north-1", from: "ole@example.invalid",
                               accessKey: "AKIATEST", secret: "geheim")

    override func tearDown() {
        try? Keychain.forget(id: sample.id)
        UserDefaults.standard.removeObject(forKey: "mailbox.id")
        super.tearDown()
    }

    func testAnAdoptedMailboxSurvivesARestart() throws {
        let first = Device()
        XCTAssertFalse(first.isSetUp, "a fresh device is not set up")
        first.adopt(sample)
        XCTAssertNil(first.problem)
        XCTAssertTrue(first.isSetUp)

        // A second Device is what the next launch builds.
        let next = Device()
        XCTAssertTrue(next.isSetUp, "the mailbox did not survive a restart")
        XCTAssertEqual(next.setup?.bucket, sample.bucket)
    }

    func testForgettingLeavesNothingBehind() throws {
        let device = Device()
        device.adopt(sample)
        device.forget()
        XCTAssertFalse(device.isSetUp)
        XCTAssertNil(try Keychain.load(id: sample.id))
        XCTAssertNil(UserDefaults.standard.string(forKey: "mailbox.id"))
        XCTAssertFalse(Device().isSetUp, "the next launch found it again")
    }

    func testAnIdentityWithoutAKeyIsDropped() throws {
        // What a restore from backup produces: keychain items marked as this
        // one is do not travel, so the identity is there and the key is gone.
        // Left alone, the app would show an empty mailbox it cannot explain.
        let device = Device()
        device.adopt(sample)
        try Keychain.forget(id: sample.id)

        let next = Device()
        XCTAssertFalse(next.isSetUp)
        XCTAssertNil(UserDefaults.standard.string(forKey: "mailbox.id"),
                     "the orphaned identity was kept")
    }
}
