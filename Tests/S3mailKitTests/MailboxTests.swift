// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import S3mailKit

/// The mailbox from the phone's side, against a real bucket.
///
/// Environment-gated like BucketTests, and for the same reason - see the
/// comment there about `TEST_RUNNER_`, which is the difference between this
/// running and this quietly not running.
final class MailboxTests: XCTestCase {

    private func mailbox() throws -> Mailbox {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["S3MAIL_KEY"], let secret = env["S3MAIL_SECRET"],
              let region = env["S3MAIL_REGION"], let bucket = env["S3MAIL_BUCKET"] else {
            throw XCTSkip("no credentials in the environment")
        }
        return try Mailbox(setup: Setup(bucket: bucket, prefix: env["S3MAIL_PREFIX"] ?? "",
                                        region: region, accessKey: key, secret: secret))
    }

    /// The whole of step 3 in one test: index the bucket, list what is in it,
    /// open one message. Everything below this line is the same code the
    /// desktop runs.
    func testAMailboxCanBeIndexedListedAndRead() throws {
        let mb = try mailbox()

        let refreshed = try mb.refresh()
        XCTAssertGreaterThan(refreshed.checked, 0, "the bucket answered, but with nothing in it")

        let folders = try mb.folders()
        XCTAssertFalse(folders.isEmpty, "a mailbox always has at least an inbox")

        let messages = try mb.search("", folder: "*", limit: 5)
        guard let first = messages.first else {
            throw XCTSkip("the mailbox is empty - nothing to read")
        }
        let full = try mb.read(key: first.key)
        XCTAssertFalse(full.from.isEmpty, "a message without a sender did not come from a mailbox")
        // Subject and sender have to match what the list showed - if they do
        // not, the list and the message view are reading different things.
        XCTAssertEqual(full.subject, first.subject)
    }

    /// The index survives being closed and opened again - otherwise every start
    /// would cost a full pass over the headers, on a phone, on mobile data.
    func testTheIndexOutlivesTheProcess() throws {
        let mb = try mailbox()
        _ = try mb.refresh()
        let before = try mb.search("", folder: "*", limit: 500).count
        guard before > 0 else { throw XCTSkip("the mailbox is empty") }

        let again = try mailbox()  // fresh handle, same cache directory
        let after = try again.search("", folder: "*", limit: 500).count
        XCTAssertEqual(after, before, "the index was not read back from disk")
    }

    /// Searching on the phone is the same search line as on the desktop. If
    /// this ever needs its own parser, something has gone wrong.
    func testTheSearchLineWorksTheSameWay() throws {
        let mb = try mailbox()
        _ = try mb.refresh()
        let all = try mb.search("", folder: "*", limit: 500)
        guard let sample = all.first else { throw XCTSkip("the mailbox is empty") }

        // "Anna Müller <anna@x.de>" -> "anna@x.de". The display name varies
        // between two messages from the same person; the address does not.
        let address = sample.from
            .split(separator: "<").last?
            .replacingOccurrences(of: ">", with: "")
            .trimmingCharacters(in: .whitespaces) ?? sample.from
        let bySender = try mb.search("from:\(address)", folder: "*", limit: 500)
        XCTAssertFalse(bySender.isEmpty,
                       "a from: search found nothing for \(address), which is in the mailbox")
    }
}

/// Decoding on its own, without a bucket. These run everywhere, and they are
/// the ones that would have caught the bug they were written for: the core
/// omits `auth_failed` when it is false, and a strict decoder threw on every
/// ordinary message - so the mailbox stayed empty and the error named a field
/// nobody displays.
final class MessageDecodingTests: XCTestCase {

    func testAMessageWithoutTheAuthFlagDecodes() throws {
        let json = """
        [{"key":"mail/ole/inbox/a.eml","from":"Anna <anna@x.de>","subject":"Hallo",
          "date":"2026-08-01T10:00:00Z","snippet":"...","read":false,"star":false,
          "spam":false,"has_attachment":false}]
        """.data(using: .utf8)!
        let msgs = try JSONDecoder().decode([Mailbox.Message].self, from: json)
        XCTAssertEqual(msgs.count, 1)
        XCTAssertFalse(msgs[0].authFailed, "a missing flag is not a set flag")
        XCTAssertEqual(msgs[0].subject, "Hallo")
    }

    func testTheAuthFlagIsReadWhenItIsThere() throws {
        let json = """
        [{"key":"k","auth_failed":true}]
        """.data(using: .utf8)!
        let msgs = try JSONDecoder().decode([Mailbox.Message].self, from: json)
        XCTAssertTrue(msgs[0].authFailed)
        XCTAssertEqual(msgs[0].from, "", "a missing string is empty, not an error")
    }

    func testAMessageWithoutAKeyIsAnError() {
        let json = #"[{"subject":"nowhere"}]"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode([Mailbox.Message].self, from: json),
                             "the key identifies the message; without it there is nothing to open")
    }

    func testAMailWithNoTextPartAndNoAttachmentsDecodes() throws {
        let json = #"{"subject":"only html","html":"<p>hi</p>"}"#.data(using: .utf8)!
        let full = try JSONDecoder().decode(Mailbox.Full.self, from: json)
        XCTAssertEqual(full.text, "")
        XCTAssertTrue(full.attachments.isEmpty)
    }
}

/// Writing, against a real bucket.
///
/// Storing a draft is a real write into a real mailbox, and every one of these
/// cleans up after itself. Sending is deliberately not here: a test that puts
/// mail in somebody's inbox on every run is a test people switch off.
final class ComposeAgainstTheBucketTests: XCTestCase {

    /// Unlike the reading tests, this one needs a sender address.
    ///
    /// Not a shortcoming of the test: a draft is a real MIME message and a MIME
    /// message has a From header. That is also why the app shows no compose
    /// button on a device whose setup carries no sender - `Mailbox.canSend` is
    /// false, and a button that fails when tapped is worse than no button.
    ///
    /// The address is never used to send here. Nothing in this file hands
    /// anything to SES.
    private func mailbox() throws -> Mailbox {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["S3MAIL_KEY"], let secret = env["S3MAIL_SECRET"],
              let region = env["S3MAIL_REGION"], let bucket = env["S3MAIL_BUCKET"] else {
            throw XCTSkip("no credentials in the environment")
        }
        let from = env["S3MAIL_FROM"] ?? "drafts@example.invalid"
        return try Mailbox(setup: Setup(bucket: bucket, prefix: env["S3MAIL_PREFIX"] ?? "",
                                        region: region, from: from,
                                        accessKey: key, secret: secret))
    }

    func testWithoutASenderNothingCanBeWritten() throws {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["S3MAIL_KEY"], let secret = env["S3MAIL_SECRET"],
              let region = env["S3MAIL_REGION"], let bucket = env["S3MAIL_BUCKET"] else {
            throw XCTSkip("no credentials in the environment")
        }
        let mb = try Mailbox(setup: Setup(bucket: bucket, prefix: env["S3MAIL_PREFIX"] ?? "",
                                          region: region, accessKey: key, secret: secret))
        XCTAssertFalse(mb.canSend, "no sender address, so no compose button")
        var draft = Draft()
        draft.to = "nobody@example.invalid"
        draft.body = "x"
        XCTAssertThrowsError(try mb.save(draft)) { error in
            XCTAssertEqual((error as NSError).localizedDescription, "no_sender")
        }
    }

    func testADraftIsAMessageInTheBucket() throws {
        let mb = try mailbox()
        var draft = Draft()
        draft.to = "nobody@example.invalid"
        draft.subject = "s3mail-ios draft test \(UUID().uuidString.prefix(8))"
        draft.body = "Written by a test. If this is in your drafts, the test did not finish."

        let key = try mb.save(draft)
        XCTAssertFalse(key.isEmpty)
        // The point of drafts living in the bucket: nothing app-local was
        // written, so the desk sees this too.
        XCTAssertTrue(key.contains("/drafts/"), "a draft belongs in the drafts folder, got \(key)")

        defer { try? mb.dropDraft(key: key) }

        _ = try mb.refresh()
        let drafts = try mb.search("", folder: "drafts", limit: 200)
        XCTAssertTrue(drafts.contains { $0.subject == draft.subject },
                      "the draft was stored but does not show in the folder")

        let full = try mb.read(key: key)
        XCTAssertEqual(full.subject, draft.subject)
        XCTAssertTrue(full.text.contains("Written by a test"))
    }

    func testSavingTwiceLeavesOneDraft() throws {
        // The name comes from the Message-ID, so an autosave every few seconds
        // must not leave a trail of half-written mails in the folder.
        let mb = try mailbox()
        var draft = Draft()
        draft.to = "nobody@example.invalid"
        draft.subject = "s3mail-ios autosave test \(UUID().uuidString.prefix(8))"
        draft.body = "one"

        let first = try mb.save(draft)
        draft.draftKey = first
        draft.body = "two"
        let second = try mb.save(draft)
        defer {
            try? mb.dropDraft(key: second)
            if first != second { try? mb.dropDraft(key: first) }
        }

        _ = try mb.refresh()
        let mine = try mb.search("", folder: "drafts", limit: 200)
            .filter { $0.subject == draft.subject }
        XCTAssertEqual(mine.count, 1, "autosaving left \(mine.count) drafts behind")
        XCTAssertTrue(try mb.read(key: second).text.contains("two"),
                      "the newer text did not win")
    }

    func testNothingIsPendingOnAQuietMailbox() throws {
        // RecoverSends closes what it can decide by itself. What it returns is
        // only what a person has to answer - and on a mailbox nobody was
        // sending from, that is nothing.
        let mb = try mailbox()
        XCTAssertEqual(try mb.pendingSends().count, 0)
    }
}

/// The date on a row.
///
/// Written because the first attempt was wrong in a way that shows nothing:
/// ISO8601DateFormatter's `.withFractionalSeconds` *requires* fractional
/// seconds rather than allowing them, and the core writes Go's time.RFC3339,
/// which has none. One formatter with the flag would have shown no date on
/// every message in the mailbox, and no error anywhere.
final class MessageDateTests: XCTestCase {

    private func message(date: String) throws -> Mailbox.Message {
        let json = #"{"key":"k","date":"\#(date)"}"#
        return try JSONDecoder().decode(Mailbox.Message.self, from: json.data(using: .utf8)!)
    }

    /// What the core actually writes.
    func testTheFormTheCoreWritesParses() throws {
        let m = try message(date: "2026-08-26T14:32:07Z")
        XCTAssertNotNil(m.when, "the ordinary RFC 3339 form did not parse")
    }

    /// And what S3 sometimes hands back.
    func testFractionalSecondsAlsoParse() throws {
        let m = try message(date: "2026-08-26T14:32:07.123Z")
        XCTAssertNotNil(m.when, "fractional seconds did not parse")
    }

    /// A message with no usable date must show none rather than 1970.
    func testNonsenseIsNilAndNotTheEpoch() throws {
        for bad in ["", "gestern", "2026-08-26"] {
            XCTAssertNil(try message(date: bad).when, "\(bad) produced a date")
        }
    }
}
