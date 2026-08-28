// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import XCTest
import S3mailKit
@testable import s3mail

/// Several mailboxes on one phone.
///
/// The desktop has carried a list of accounts for a while; the phone held one,
/// so somebody with a work mailbox and a private one had to pick which of them
/// their phone was for. What is worth testing here is not the list - it is the
/// step from the old layout to it, because that step runs exactly once on a
/// phone that already has a mailbox on it, and getting it wrong looks like the
/// mailbox is gone.
final class AccountsTests: XCTestCase {

    private let work = Setup(bucket: "koh-post", prefix: "mail/work/",
                             region: "eu-north-1", from: "work@example.org",
                             accessKey: "AKIAWORK", secret: "geheim")
    private let home = Setup(bucket: "koh-post", prefix: "mail/home/",
                             region: "eu-north-1", label: "Privat",
                             accessKey: "AKIAHOME", secret: "geheim")

    private func wipe() {
        for id in [work.id, home.id] { try? Keychain.forget(id: id) }
        for key in ["mailbox.ids", "mailbox.current", "mailbox.id"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func setUp() { super.setUp(); wipe() }
    override func tearDown() { wipe(); super.tearDown() }

    /// The step that runs on a phone somebody already uses.
    ///
    /// The single-mailbox era wrote one identity under "mailbox.id". If that is
    /// not turned into a list, the next launch finds an empty list, shows the
    /// scanner, and the mailbox looks lost - while its key sits untouched in the
    /// keychain.
    func testAPhoneFromBeforeKeepsItsMailbox() throws {
        try Keychain.save(work)
        UserDefaults.standard.set(work.id, forKey: "mailbox.id")

        let device = Device()

        XCTAssertEqual(device.accounts.map(\.id), [work.id],
                       "the mailbox from the single-mailbox layout was not carried over")
        XCTAssertEqual(device.current?.id, work.id)
        XCTAssertNil(UserDefaults.standard.string(forKey: "mailbox.id"),
                     "the old key is still there - it would be read again next launch")
    }

    /// And the step is not repeated over a list that already exists, which is
    /// how a second mailbox would be quietly dropped.
    func testTheOldKeyDoesNotOverwriteAList() throws {
        try Keychain.save(work)
        try Keychain.save(home)
        UserDefaults.standard.set([work.id, home.id], forKey: "mailbox.ids")
        UserDefaults.standard.set(home.id, forKey: "mailbox.current")
        UserDefaults.standard.set(work.id, forKey: "mailbox.id")

        let device = Device()

        XCTAssertEqual(Set(device.accounts.map(\.id)), Set([work.id, home.id]))
        XCTAssertEqual(device.current?.id, home.id, "the remembered mailbox was not the one shown")
    }

    func testASecondMailboxJoinsTheFirst() throws {
        let device = Device()
        device.adopt(work)
        device.adopt(home)

        XCTAssertEqual(device.accounts.map(\.id), [work.id, home.id])
        XCTAssertEqual(device.current?.id, home.id, "the mailbox just added is not the one shown")
        XCTAssertEqual(Device().accounts.count, 2, "the next launch found only some of them")
    }

    /// Pairing the same mailbox again is the common case, not an edge one: it
    /// is what a fresh setup code on the desktop produces. It must replace the
    /// key, not add a second entry for the same mailbox.
    func testPairingTheSameMailboxAgainReplacesIt() throws {
        let device = Device()
        device.adopt(work)
        device.adopt(Setup(bucket: work.bucket, prefix: work.prefix, region: work.region,
                           from: work.from, accessKey: "AKIANEU", secret: "neu"))

        XCTAssertEqual(device.accounts.count, 1, "the same mailbox is in the list twice")
        XCTAssertEqual(try Keychain.load(id: work.id)?.accessKey, "AKIANEU",
                       "the old key survived - the phone would keep using a revoked one")
    }

    func testForgettingOneLeavesTheOther() throws {
        let device = Device()
        device.adopt(work)
        device.adopt(home)
        device.forget()

        XCTAssertEqual(device.accounts.map(\.id), [work.id])
        XCTAssertEqual(device.current?.id, work.id, "nothing moved up after forgetting")
        XCTAssertTrue(device.isSetUp, "a phone with a mailbox left was sent back to the scanner")
        XCTAssertNil(try Keychain.load(id: home.id))
    }

    func testForgettingTheLastOneLandsOnTheScanner() throws {
        let device = Device()
        device.adopt(work)
        device.forget()

        XCTAssertTrue(device.accounts.isEmpty)
        XCTAssertFalse(device.isSetUp)
    }

    /// An identity whose key did not travel - a restore from backup. Dropping it
    /// beats showing an empty mailbox nobody can explain, and the mailboxes
    /// beside it must survive that.
    func testAMailboxWithoutItsKeyIsDroppedAndTheRestStay() throws {
        try Keychain.save(work)
        UserDefaults.standard.set([work.id, home.id], forKey: "mailbox.ids")

        let device = Device()

        XCTAssertEqual(device.accounts.map(\.id), [work.id])
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: "mailbox.ids"), [work.id],
                       "the identity without a key stayed in the list and is read again next launch")
    }
}

/// The sample has to open inside the app, not only in the package tests.
///
/// It is the same call, and it still earns its own test: the app target builds
/// against the framework the app ships, with the app's bundle and the device's
/// language. A screenshot run once failed here and looked like a tap that had
/// missed - the button did nothing, and nothing said why.
final class SampleOpensInTheAppTests: XCTestCase {

    func testTheSampleOpensWithTheDeviceLanguage() throws {
        let mailbox = try Mailbox.demo()
        XCTAssertTrue(mailbox.isDemo)
        XCTAssertFalse(try mailbox.search("", folder: "").isEmpty,
                       "the sample opened but has no mail in it")
    }

    /// And with an explicit language, the way the walk-through runs it.
    func testTheSampleOpensInGerman() throws {
        let mailbox = try Mailbox.demo(language: "de")
        let inbox = try mailbox.search("", folder: "")
        XCTAssertTrue(inbox.contains { $0.subject.contains("Beispiel-Postfach") },
                      "the German sample is not the German one")
    }
}

/// The sample lives on Device, so opening it is a state change that can be
/// tested without a simulator walking through the app.
///
/// That matters more than it looks: the same step used to be a view method
/// passed on as a closure, and when it stopped working there was nothing to
/// ask. The button did nothing, the screen did not move, and no test could
/// tell whether the tap or the state was at fault.
final class ShowSampleTests: XCTestCase {

    func testShowingTheSampleGivesAMailbox() {
        let device = Device()
        XCTAssertNil(device.sample)

        device.showSample()

        XCTAssertNotNil(device.sample, "opening the sample did nothing: \(device.problem ?? "no error either")")
        XCTAssertNil(device.problem)
        XCTAssertTrue(device.sample?.isDemo == true)
    }

    func testClosingItLeavesNothing() {
        let device = Device()
        device.showSample()
        device.closeSample()

        XCTAssertNil(device.sample)
        XCTAssertNil(UserDefaults.standard.string(forKey: "mailbox.current"),
                     "the sample left an identity behind - it owns none")
    }
}
