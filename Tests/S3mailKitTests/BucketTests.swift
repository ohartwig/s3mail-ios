// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import S3mailKit

/// Does a real S3 call go through from a simulator?
///
/// Skipped unless credentials are handed in through the environment - so this
/// stays a test anybody can run, and nobody's key ends up in the repository.
///
/// The prefix is not decoration. `xcodebuild` does not hand its environment to
/// the test process in the simulator; only variables named `TEST_RUNNER_*`
/// arrive there, and they arrive with the prefix stripped. Without it the test
/// skips - and a skipped test still leaves the summary saying "passed", with
/// the word "skipped" one line above where nobody reads it. That is exactly the
/// silent green this project spends so much effort avoiding elsewhere.
///
///     TEST_RUNNER_S3MAIL_KEY=... TEST_RUNNER_S3MAIL_SECRET=... \
///     TEST_RUNNER_S3MAIL_REGION=eu-north-1 TEST_RUNNER_S3MAIL_BUCKET=... \
///     TEST_RUNNER_S3MAIL_PREFIX=mail/ \
///     xcodebuild test -scheme S3mailKit -destination '...'
final class BucketTests: XCTestCase {

    func testAListingComesBackFromS3() throws {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["S3MAIL_KEY"], let secret = env["S3MAIL_SECRET"],
              let region = env["S3MAIL_REGION"], let bucket = env["S3MAIL_BUCKET"] else {
            throw XCTSkip("no credentials in the environment - see the comment above")
        }
        let listing = try Core.list(accessKey: key, secret: secret, region: region,
                                    bucket: bucket, prefix: env["S3MAIL_PREFIX"] ?? "",
                                    limit: 5)
        XCTAssertGreaterThan(listing.count, 0, "the bucket answered, but with nothing in it")
        XCTAssertFalse(listing.keys.isEmpty)
    }

    /// Wrong credentials have to arrive as an error, not as an empty listing.
    /// An app that shows an empty mailbox instead of "no access" sends somebody
    /// looking for mail that is there.
    func testWrongCredentialsFail() {
        XCTAssertThrowsError(try Core.list(accessKey: "AKIAFALSCH", secret: "auch-falsch",
                                           region: "eu-north-1", bucket: "gibt-es-nicht-xyz",
                                           prefix: "", limit: 1))
    }
}
