// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import S3mailKit

/// Where the cache lives, and what iOS is told about it.
///
/// Application Support is in every iCloud and Finder backup. Until 1.2.11 the
/// mail cache sat there with nothing said about it, so a backup without a
/// password carried the last opened messages in clear text (AUD-008-F01). The
/// directory is now excluded from backup - and the flag has to survive a second
/// call, because it is set on the directory, not remembered anywhere.
final class CacheDirectoryTests: XCTestCase {

    private let sample = Setup(bucket: "koh-post", prefix: "mail/test/",
                               region: "eu-north-1", accessKey: "AKIATEST",
                               secret: "geheim")

    private func excluded(_ url: URL) throws -> Bool? {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
    }

    func testTheMailboxesDirectoryStaysOutOfBackups() throws {
        let dir = try Mailbox.cacheDirectory(for: sample)
        let mailboxes = dir.deletingLastPathComponent()
        XCTAssertEqual(mailboxes.lastPathComponent, "mailboxes")
        XCTAssertEqual(try excluded(mailboxes), true, "the cache would travel in every backup")

        // The second call finds the directory in place and must not leave it
        // with the flag gone.
        _ = try Mailbox.cacheDirectory(for: sample)
        XCTAssertEqual(try excluded(mailboxes), true, "the flag did not survive an existing directory")
    }

    func testTheDirectoryIsUnderApplicationSupport() throws {
        let dir = try Mailbox.cacheDirectory(for: sample)
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil, create: false)
        XCTAssertTrue(dir.path.hasPrefix(support.path), "\(dir.path) is not under Application Support")
    }
}
