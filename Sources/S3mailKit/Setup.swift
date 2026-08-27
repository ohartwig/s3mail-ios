// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import Foundation
import S3mailCore

/// What a phone needs to know to be a mailbox, and how it learns it.
///
/// Not by typing. The desktop wizard already works out bucket, prefix and
/// sender from the IAM policy of the access - asking a person to retype that on
/// a phone would undo the one thing s3mail's setup is proud of. So the wizard
/// shows a QR code and the phone reads it.
///
/// The credentials in it are **not** the ones the desktop uses. One IAM user per
/// device, same narrow policy: then a lost phone is a click in the IAM console
/// and nothing else. The desktop cannot create that user itself - its own access
/// may read its policy and nothing more - so the wizard hands out the policy to
/// paste and the human makes the user. That is a step more, and it buys the
/// ability to revoke one device without touching the others.
public struct Setup: Codable, Equatable {
    public let bucket: String
    public let prefix: String
    public let region: String
    /// The verified SES sender. Empty means this device may only read.
    public let from: String
    /// What the mailbox is called in the switcher. Empty is allowed.
    public let label: String
    public let accessKey: String
    public let secret: String

    /// Where this device registers for push, keyed by Apple's environment
    /// names. Empty for a mailbox set up before push existed.
    ///
    /// Not secret: an ARN names a resource, it does not open it, and what the
    /// device may do with it is decided by the IAM policy of its key.
    public let pushApps: [String: String]
    public let pushTopic: String

    /// The secret access key, sealed with the PIN the desktop showed beside the
    /// code. Empty for a code from before pairing worked this way.
    ///
    /// This is why a photograph of the screen is not the device's access: the
    /// key travels in the code, the PIN does not.
    public let sealed: String
    public let salt: String

    public init(bucket: String, prefix: String, region: String,
                from: String = "", label: String = "",
                accessKey: String, secret: String,
                pushApps: [String: String] = [:], pushTopic: String = "",
                sealed: String = "", salt: String = "") {
        self.bucket = bucket
        self.prefix = prefix
        self.region = region
        self.from = from
        self.label = label
        self.accessKey = accessKey
        self.secret = secret
        self.pushApps = pushApps
        self.pushTopic = pushTopic
        self.sealed = sealed
        self.salt = salt
    }

    enum CodingKeys: String, CodingKey {
        case bucket, prefix, region, from, label, accessKey, secret
        case pushApps, pushTopic, sealed, salt
    }

    /// Written out because a code without the push fields has to keep working.
    ///
    /// Setup codes are shown, photographed and pasted; one made before push
    /// existed is still a valid way into a mailbox. A synthesised decoder would
    /// refuse it - and the refusal would name a field about notifications while
    /// somebody is trying to read their mail.
    ///
    /// Bucket and region stay required: without them there is no mailbox to
    /// open, and a code missing those is not an old code but a wrong one.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bucket = try c.decode(String.self, forKey: .bucket)
        region = try c.decode(String.self, forKey: .region)
        prefix = try c.decodeIfPresent(String.self, forKey: .prefix) ?? ""
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        accessKey = try c.decodeIfPresent(String.self, forKey: .accessKey) ?? ""
        secret = try c.decodeIfPresent(String.self, forKey: .secret) ?? ""
        pushApps = try c.decodeIfPresent([String: String].self, forKey: .pushApps) ?? [:]
        pushTopic = try c.decodeIfPresent(String.self, forKey: .pushTopic) ?? ""
        sealed = try c.decodeIfPresent(String.self, forKey: .sealed) ?? ""
        salt = try c.decodeIfPresent(String.self, forKey: .salt) ?? ""
    }

    /// The identity of a mailbox, the same way the desktop derives it: bucket
    /// and prefix, not the position in a list. Somebody who reorders their
    /// mailboxes must not lose their state.
    public var id: String { "\(bucket)/\(prefix)" }

    /// What to call this mailbox on screen.
    ///
    /// The label if the desktop sent one, otherwise the address it sends as,
    /// otherwise the prefix. Never the bucket on its own: several mailboxes
    /// usually share one, and a switcher that lists the same word twice is
    /// worse than no switcher.
    public var title: String {
        if !label.isEmpty { return label }
        if !from.isEmpty { return from }
        let trimmed = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        return trimmed.isEmpty ? bucket : trimmed
    }

    /// Whether this code needs a PIN to finish. A code from the current wizard
    /// carries a sealed key; an older one carried none and expected the key to
    /// be typed.
    public var needsPIN: Bool { !sealed.isEmpty && !salt.isEmpty }

    /// The same mailbox with the key filled in, once the PIN has opened it.
    public func unsealed(secret: String) -> Setup {
        Setup(bucket: bucket, prefix: prefix, region: region, from: from,
              label: label, accessKey: accessKey, secret: secret,
              pushApps: pushApps, pushTopic: pushTopic)
    }

    public enum Problem: LocalizedError, Equatable {
        case notJSON
        case missing(String)
        case prefixNotAFolder(String)

        public var errorDescription: String? {
            switch self {
            case .notJSON:
                return t("setup.notAMailbox")
            case .missing(let field):
                return String(format: t("setup.missingField"), field)
            case .prefixNotAFolder(let prefix):
                return String(format: t("setup.prefixNotAFolder"), prefix)
            }
        }
    }

    /// Reads what a QR code carried - **without** the key.
    ///
    /// The code holds no access key on purpose: that is the whole reason a
    /// photograph of the screen, a screenshot in a chat or a shoulder in a cafe
    /// hand nobody access. The key is typed in afterwards, and only then is the
    /// setup complete.
    ///
    /// So this checks what the code can be expected to carry and nothing more.
    /// Demanding a key here refuses every real code the assistant produces -
    /// which is exactly what it did until a test asked it to read one.
    public static func fromCode(_ text: String) throws -> Setup {
        try read(text, needsKey: false)
    }

    /// Reads a code and, if it carries a sealed key, opens it with the PIN.
    ///
    /// One call rather than two, because the two belong together: a code with a
    /// sealed key is not usable until the PIN has been applied, and a caller
    /// that forgot the second step would build a mailbox with no key and find
    /// out at the first S3 request.
    public static func fromCode(_ text: String, pin: String) throws -> Setup {
        let scanned = try read(text, needsKey: false)
        let opened = try scanned.unlock(pin: pin)
        // Now it has to be complete: an opened code with no key means the PIN
        // was right and the box was empty, which is a broken code and not a
        // typo.
        guard !opened.accessKey.isEmpty, !opened.secret.isEmpty else {
            throw PairingError.damaged
        }
        return opened
    }

    /// Reads a complete setup - with the key. For a mailbox coming back out of
    /// the keychain, where a missing key means something is broken.
    ///
    /// Deliberately strict: a half-read setup produces a mailbox that fails
    /// later, somewhere else, with an error about S3. Better to refuse here,
    /// where the cause is still visible.
    public static func decode(_ text: String) throws -> Setup {
        try read(text, needsKey: true)
    }

    private static func read(_ text: String, needsKey: Bool) throws -> Setup {
        guard let data = text.data(using: .utf8),
              let setup = try? JSONDecoder().decode(Setup.self, from: data) else {
            throw Problem.notJSON
        }
        var required = [("a bucket", setup.bucket), ("a region", setup.region)]
        if needsKey {
            required += [("an access key", setup.accessKey), ("a secret", setup.secret)]
        }
        for (name, value) in required
        where value.trimmingCharacters(in: .whitespaces).isEmpty {
            throw Problem.missing(name)
        }
        // A prefix without a slash is the classic S3 mistake: "mail" also
        // matches "mailbox-old/", and the mailbox would quietly contain
        // somebody else's messages.
        if !setup.prefix.isEmpty && !setup.prefix.hasSuffix("/") {
            throw Problem.prefixNotAFolder(setup.prefix)
        }
        return setup
    }

    public func encode() throws -> String {
        let blob = try JSONEncoder().encode(self)
        return String(decoding: blob, as: UTF8.self)
    }
}

public extension Setup {

    /// Opens the sealed key with the PIN.
    ///
    /// The work happens in the Go core - one implementation of PBKDF2 and
    /// AES-GCM, tested in one place. A second one here would drift, and the day
    /// it drifted the symptom would be a code that pairs on one build and not
    /// on another.
    ///
    /// It takes about a second, deliberately: that second is what stands
    /// between a photograph of the code and the key inside it.
    func unlock(pin: String) throws -> Setup {
        guard needsPIN else { return self }
        var err: NSError?
        let secret = MobileUnsealSecret(sealed, salt, pin, &err)
        if let err { throw PairingError.from(err) }
        guard !secret.isEmpty else { throw PairingError.wrongPIN }
        return unsealed(secret: secret)
    }
}

public enum PairingError: String, Error, LocalizedError {
    case wrongPIN = "wrong_pin"
    case damaged = "code_damaged"

    public var errorDescription: String? {
        NSLocalizedString("pairing.\(rawValue)", bundle: .module,
                          comment: "why a setup code could not be opened")
    }

    static func from(_ error: Error) -> Error {
        PairingError(rawValue: (error as NSError).localizedDescription) ?? error
    }
}
