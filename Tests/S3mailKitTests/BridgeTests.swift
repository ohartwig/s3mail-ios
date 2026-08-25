// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import S3mailKit

/// The spike from IOS.md, as a test that keeps proving itself.
///
/// It runs on the simulator and asserts that Swift gets out of the Go core
/// exactly what the desktop gets. The two messages are copies from the Go
/// corpus, and they are the ugly ones on purpose: a subject in three character
/// sets, and Outlook's multipart/related inside multipart/alternative. If the
/// bridge ever loses bytes or mangles an encoding, these are where it shows.
final class BridgeTests: XCTestCase {

    private func corpus(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "eml"))
        return try Data(contentsOf: url)
    }

    /// The smallest possible proof: Swift calls Go, Go answers.
    func testTheBridgeAnswers() {
        XCTAssertEqual(Core.version, "s3mail-core/spike")
    }

    /// Three encoded words, three character sets, one line. A parser that
    /// decodes only the first produces a subject that looks almost right - and
    /// a bridge that loses UTF-8 on the way out produces the same symptom.
    func testASubjectInThreeCharsets() throws {
        let summary = try Core.parse(try corpus("20-mixed-charset-subject"))
        XCTAssertEqual(summary.subject, "Grüße aus München und Zürich")
        XCTAssertEqual(summary.from, "Anna <anna@example.de>")
    }

    /// What Outlook actually sends. The HTML part sits two levels down; finding
    /// it is the parser's job, and it is the job that must never exist twice.
    func testOutlookNesting() throws {
        let summary = try Core.parse(try corpus("21-outlook-related"))
        XCTAssertTrue(summary.hasHTML, "the nested HTML part was not found")
        XCTAssertTrue(summary.preview.contains("Grüße"),
                      "the iso-8859-1 text did not survive the bridge: \(summary.preview)")
    }

    /// Nothing may fall over on a message that is cut in half - during indexing
    /// that is the normal case, because only the first 64 KB are fetched.
    func testATruncatedMessageDoesNotCrash() throws {
        let raw = try corpus("21-outlook-related")
        for cut in [raw.count / 2, 64, 1, 0] {
            _ = try? Core.parse(raw.prefix(cut))
        }
    }
}
