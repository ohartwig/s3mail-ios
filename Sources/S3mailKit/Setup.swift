// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import Foundation

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

    public init(bucket: String, prefix: String, region: String,
                from: String = "", label: String = "",
                accessKey: String, secret: String) {
        self.bucket = bucket
        self.prefix = prefix
        self.region = region
        self.from = from
        self.label = label
        self.accessKey = accessKey
        self.secret = secret
    }

    /// The identity of a mailbox, the same way the desktop derives it: bucket
    /// and prefix, not the position in a list. Somebody who reorders their
    /// mailboxes must not lose their state.
    public var id: String { "\(bucket)/\(prefix)" }

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

    /// Reads what a QR code carried.
    ///
    /// Deliberately strict: a half-read code produces a mailbox that fails
    /// later, somewhere else, with an error about S3. Better to refuse here,
    /// where the cause is still visible.
    public static func decode(_ text: String) throws -> Setup {
        guard let data = text.data(using: .utf8),
              let setup = try? JSONDecoder().decode(Setup.self, from: data) else {
            throw Problem.notJSON
        }
        for (name, value) in [("a bucket", setup.bucket), ("a region", setup.region),
                              ("an access key", setup.accessKey), ("a secret", setup.secret)]
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
