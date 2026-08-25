// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import S3mailKit

/// Writing, without a bucket. What is checked here is the wire format and the
/// one rule that must not bend: a mail that went out is never reported as a
/// failure.
final class ComposeTests: XCTestCase {

    private func encoded(_ draft: Draft) throws -> [String: Any] {
        let data = try JSONEncoder().encode(draft)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTheDraftSpeaksTheCoresVocabulary() throws {
        // mailer.Draft on the Go side reads exactly these keys. A name changed
        // on one side and not the other does not fail - the field simply
        // arrives empty, and a mail goes out without its subject.
        var d = Draft()
        d.to = "anna@x.de"
        d.subject = "Hallo"
        d.body = "Text"
        d.draftKey = "mail/ole/drafts/x.eml"
        let json = try encoded(d)
        for key in ["mode", "to", "cc", "bcc", "subject", "body", "draft_key"] {
            XCTAssertNotNil(json[key], "the core expects \(key)")
        }
        XCTAssertEqual(json["draft_key"] as? String, "mail/ole/drafts/x.eml",
                       "draftKey travels as draft_key, not as draftKey")
        XCTAssertNil(json["id"], "the sheet's identity is not part of the wire format")
    }

    func testAnAttachmentTravelsAsBase64() throws {
        // Go's encoding/json reads []byte from base64 and writes it the same
        // way, so neither side has to agree on anything beyond that.
        var d = Draft()
        d.attachments = [.init(filename: "a.txt", contentType: "text/plain",
                               content: Data("hallo".utf8))]
        let json = try encoded(d)
        let list = try XCTUnwrap(json["attachments"] as? [[String: Any]])
        XCTAssertEqual(list.first?["content"] as? String, "aGFsbG8=")
        XCTAssertEqual(list.first?["content_type"] as? String, "text/plain")
    }

    func testAnEmptyDraftIsNotWorthStoring() {
        // Otherwise every window somebody opened and shut leaves an object in
        // the bucket.
        XCTAssertFalse(Draft().isWorthKeeping)
        var d = Draft()
        d.body = "   \n "
        XCTAssertFalse(d.isWorthKeeping, "whitespace is not content")
        d.body = "a"
        XCTAssertTrue(d.isWorthKeeping)
    }

    func testAReplyKeepsTheOriginalForTheCore() throws {
        let json = #"{"key":"mail/ole/inbox/a.eml","from":"Anna <anna@x.de>"}"#
        let message = try JSONDecoder().decode(Mailbox.Message.self,
                                               from: json.data(using: .utf8)!)
        let d = Draft.replying(to: message)
        XCTAssertEqual(d.mode, .reply)
        XCTAssertEqual(d.key, "mail/ole/inbox/a.eml",
                       "without the key the core cannot thread the reply")
        XCTAssertEqual(d.to, "Anna <anna@x.de>")
    }

    func testAWarningIsStillASuccess() throws {
        // The single most important line in this file. From the moment SES
        // answers, the mail is out of the house; a copy that missed sent/ is a
        // warning. Reported as a failure it reads as "not sent", and the next
        // thing that happens is the same mail going out twice.
        let json = #"{"message_id":"abc","warning":"sent_not_stored"}"#
        let result = try JSONDecoder().decode(SendResult.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(result.messageID, "abc")
        XCTAssertEqual(result.warning, .sentNotStored)
    }

    func testAnUnknownWarningDoesNotLoseTheMessageID() throws {
        // A warning this version does not know about must not turn a successful
        // send into a decoding error.
        let json = #"{"message_id":"abc","warning":"something_new"}"#
        let result = try JSONDecoder().decode(SendResult.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(result.messageID, "abc")
        XCTAssertNil(result.warning)
    }

    func testTheBridgesCodesBecomeSentences() {
        let mapped = ComposeError.from(
            NSError(domain: "go", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "send_not_permitted"]))
        XCTAssertEqual(mapped as? ComposeError, .notPermitted)
        XCTAssertNotEqual((mapped as? ComposeError)?.errorDescription, "send_not_permitted",
                          "the code reached the screen instead of the sentence")
    }

    func testAnUnknownErrorIsPassedThroughUnchanged() {
        // An unknown error said plainly is more use than a familiar one said
        // wrongly.
        let original = NSError(domain: "go", code: 1,
                               userInfo: [NSLocalizedDescriptionKey: "connection lost"])
        let mapped = ComposeError.from(original)
        XCTAssertNil(mapped as? ComposeError)
        XCTAssertEqual((mapped as NSError).localizedDescription, "connection lost")
    }
}
