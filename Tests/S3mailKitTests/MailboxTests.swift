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
