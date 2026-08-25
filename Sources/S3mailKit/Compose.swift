// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// What somebody has written, on its way to the core.
///
/// The field names are the core's, not this file's: `mailer.Draft` on the Go
/// side reads exactly these keys, and the desktop's compose window sends the
/// same shape. One vocabulary for a mail being written, and neither end has to
/// translate.
public struct Draft: Codable, Equatable, Identifiable {

    /// Where this draft came from - and therefore what the core does with the
    /// original: quote it, attach it, or nothing at all.
    public enum Mode: String, Codable {
        case new, reply, forward
    }

    public var mode: Mode = .new
    /// The message being replied to or forwarded. Empty for a new mail.
    public var key: String = ""
    /// Empty means the mailbox's own sender address. The phone rarely sets it.
    public var from: String = ""
    public var to: String = ""
    public var cc: String = ""
    public var bcc: String = ""
    public var subject: String = ""
    public var body: String = ""
    /// The draft this replaces. Set by `save()` so the next save overwrites
    /// rather than leaving a trail of half-written mails in the folder.
    public var draftKey: String = ""
    public var attachments: [Attachment] = []

    public struct Attachment: Codable, Equatable, Identifiable {
        public let filename: String
        public let contentType: String
        /// Base64 on the wire in both directions - that is what Go's
        /// encoding/json does with []byte, so neither side has to say so.
        public let content: Data
        public var id: String { filename }

        public init(filename: String, contentType: String, content: Data) {
            self.filename = filename
            self.contentType = contentType
            self.content = content
        }

        enum CodingKeys: String, CodingKey {
            case filename, content
            case contentType = "content_type"
        }
    }

    enum CodingKeys: String, CodingKey {
        case mode, key, from, to, cc, bcc, subject, body, attachments
        case draftKey = "draft_key"
    }

    /// Identity for the sheet that presents it. Not part of the wire format -
    /// the core never sees it, and two drafts of the same mail are two windows.
    public let id = UUID()

    public init() {}

    /// A reply, with the quoting left to the core. The subject prefix and the
    /// threading headers are its job too - this only says which message and
    /// which way.
    public static func replying(to message: Mailbox.Message, all: Bool = false) -> Draft {
        var d = Draft()
        d.mode = .reply
        d.key = message.key
        d.to = message.from
        return d
    }

    public static func forwarding(_ message: Mailbox.Message) -> Draft {
        var d = Draft()
        d.mode = .forward
        d.key = message.key
        return d
    }

    /// Whether this is worth storing. An empty draft saved on every keystroke
    /// would put an object in the bucket for a window somebody opened and shut.
    public var isWorthKeeping: Bool {
        !(to.isEmpty && cc.isEmpty && bcc.isEmpty
          && subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && attachments.isEmpty)
    }
}

/// What the core answers when something could not be done.
///
/// The bridge sends a code, never a sentence: a Go library inside an app has no
/// business holding text in one language while the system is set to another.
/// The sentences are here, and they come from the app's own catalogue.
public enum ComposeError: String, Error, LocalizedError {
    case noRecipient = "no_recipient"
    case noSender = "no_sender"
    case tooLarge = "too_large"
    /// The device's key may read the bucket but not send. That is the wizard's
    /// default, and it is the right one for a phone that only reads.
    case notPermitted = "send_not_permitted"
    case refused = "send_refused"
    case badDraft = "bad_draft"

    public var errorDescription: String? {
        NSLocalizedString("compose.\(rawValue)", bundle: .module,
                          comment: "why a mail could not be sent")
    }

    /// Anything the bridge did not name stays an NSError and is shown as it
    /// came. An unknown error said plainly is more use than a familiar one said
    /// wrongly.
    static func from(_ error: Error) -> Error {
        ComposeError(rawValue: (error as NSError).localizedDescription) ?? error
    }
}

/// What happened after SES took the message.
///
/// `warning` is the part that matters: from the moment SES answers, the mail is
/// out of the house, and a copy that did not reach sent/ must never be reported
/// as a failure to send. Somebody reading "failed" sends it again.
public struct SendResult: Decodable, Equatable {
    public let messageID: String
    public let warning: Warning?

    public enum Warning: String, Decodable {
        case notRecorded = "send_not_recorded"
        case sentNotStored = "sent_not_stored"
        case draftNotRemoved = "draft_not_removed"

        public var text: String {
            NSLocalizedString("compose.\(rawValue)", bundle: .module,
                              comment: "the mail went out, but something after it did not")
        }
    }

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case warning
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messageID = try c.decodeIfPresent(String.self, forKey: .messageID) ?? ""
        warning = try? c.decodeIfPresent(Warning.self, forKey: .warning)
    }
}

/// A send that started and whose end nobody witnessed.
///
/// The app asks about these on every start. It has to ask rather than decide:
/// guessing "sent" loses a mail, guessing "not sent" sends it twice, and only
/// the person can look in their own sent folder and say which it was.
public struct PendingSend: Decodable, Identifiable, Equatable {
    public let key: String
    public let to: String
    public let subject: String
    public let started: String
    public var id: String { key }

    enum CodingKeys: String, CodingKey { case key, to, subject, started }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        to = try c.decodeIfPresent(String.self, forKey: .to) ?? ""
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        started = try c.decodeIfPresent(String.self, forKey: .started) ?? ""
    }
}

/// The text catalogue, reachable from outside for the test that checks it.
///
/// The desktop has i18n_test.go: every language carries every key, and the
/// placeholders match. Without that, a language falls behind silently - the
/// missing sentence is simply the key, and nobody sees it until somebody
/// switches their phone to Spanish.
public enum Catalogue {
    public static let bundle = Bundle.module
    public static let languages = ["de", "en", "es"]
}
