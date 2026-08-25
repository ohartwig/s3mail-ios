// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import Foundation
import S3mailCore

/// Reaching S3 from the phone.
///
/// The second question of the spike, after "does it compile": does a call
/// actually go through? TLS, DNS, the app sandbox and the SDK's own credential
/// machinery all have to agree, and none of that is settled by compiling.
public extension Core {

    struct Listing: Decodable {
        public let count: Int
        public let keys: [String]
    }

    /// Credentials are handed in, not looked up. There is no `~/.aws` on a
    /// phone; the app keeps its key in the keychain, and which key that is - one
    /// IAM user per device - is decided in IOS.md.
    static func list(accessKey: String, secret: String, region: String,
                     bucket: String, prefix: String, limit: Int = 5) throws -> Listing {
        var err: NSError?
        let json = MobileListKeys(accessKey, secret, region, bucket, prefix, limit, &err)
        if let err { throw err }
        guard let blob = json.data(using: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try JSONDecoder().decode(Listing.self, from: blob)
    }
}
