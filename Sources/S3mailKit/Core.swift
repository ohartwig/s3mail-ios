// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import Foundation
import S3mailCore

/// The Swift side of the bridge to the Go core.
///
/// Everything below this file is the code the desktop program runs and must not
/// be rewritten - `mimeparse` above all, which is where the ugly cases live.
/// Everything above it is Swift and may be rewritten freely.
///
/// The bridge speaks JSON because gomobile can only carry strings, numbers,
/// bytes and errors. Decoding here rather than shaping the Go API around that
/// limit keeps the limit out of the core.
public enum Core {

    /// Which core is inside. The smallest possible proof that the bridge works.
    public static var version: String { MobileVersion() }

    /// One message as the mailbox sees it: sender, subject, preview, the names
    /// of its attachments, what SES said about spam and about the sender.
    public struct Summary: Decodable {
        public let from: String
        public let to: String
        public let subject: String
        public let date: String
        public let preview: String
        public let hasHTML: Bool
        public let spam: String

        enum CodingKeys: String, CodingKey {
            case from, to, subject, date, preview, spam
            case hasHTML = "has_html"
        }
    }

    /// Parses a raw message with the same parser the desktop uses.
    public static func parse(_ raw: Data) throws -> Summary {
        var err: NSError?
        let json = MobileParseMessage(raw, &err)
        if let err { throw err }
        guard let blob = json.data(using: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try JSONDecoder().decode(Summary.self, from: blob)
    }
}
