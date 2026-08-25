// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import S3mailKit

/// The counterpart to i18n_test.go in the core.
///
/// A missing translation does not fail loudly: NSLocalizedString hands back the
/// key, so the screen reads "compose.send_refused" and everything keeps
/// working. That is the failure mode this test exists for - it is invisible
/// until somebody sets their phone to Spanish.
final class CatalogueTests: XCTestCase {

    private func strings(_ language: String) throws -> [String: String] {
        let url = try XCTUnwrap(
            Catalogue.bundle.url(forResource: "Localizable", withExtension: "strings",
                                 subdirectory: nil, localization: language),
            "the catalogue for \(language) is not in the bundle")
        let dict = try XCTUnwrap(
            NSDictionary(contentsOf: url) as? [String: String],
            "the catalogue for \(language) is not a string table")
        return dict
    }

    func testEveryLanguageCarriesEveryKey() throws {
        var tables: [String: [String: String]] = [:]
        for language in Catalogue.languages {
            tables[language] = try strings(language)
        }
        let all = Set(tables.values.flatMap(\.keys))
        XCTAssertFalse(all.isEmpty, "no keys at all - the catalogue did not ship")

        for (language, table) in tables {
            let missing = all.subtracting(table.keys).sorted()
            XCTAssertTrue(missing.isEmpty,
                          "\(language) is missing: \(missing.joined(separator: ", "))")
        }
    }

    func testThePlaceholdersMatch() throws {
        // A sentence that lost its %@ silently drops what it was supposed to
        // name; one that gained a second reads a random word off the stack.
        func placeholders(_ s: String) -> Int {
            s.components(separatedBy: "%@").count - 1
        }
        let reference = try strings("en")
        for language in Catalogue.languages where language != "en" {
            let table = try strings(language)
            for (key, text) in reference {
                guard let other = table[key] else { continue }
                XCTAssertEqual(placeholders(other), placeholders(text),
                               "\(key) in \(language) has a different number of placeholders")
            }
        }
    }

    func testTheFolderKeysAreTheOnesTheCoreSends() throws {
        // core/folder.go hands out these six and no others. A key renamed there
        // and not here shows up as "folder.sent" in the sidebar.
        let table = try strings("en")
        for key in ["folder.inbox", "folder.drafts", "folder.sent",
                    "folder.archive", "folder.spam", "folder.trash"] {
            XCTAssertNotNil(table[key], "\(key) is missing - the sidebar would show the key")
        }
    }

    func testAFolderSomebodyMadeKeepsItsName() {
        // Not in the catalogue, so the lookup answers with what it was given.
        // That fallback is the feature: user folders are not translated.
        var folder = try? JSONDecoder().decode(
            Mailbox.Folder.self,
            from: #"{"name":"Rechnungen","label":"Rechnungen","icon":"","count":3,"unread":0}"#
                .data(using: .utf8)!)
        XCTAssertEqual(folder?.title, "Rechnungen")
        folder = try? JSONDecoder().decode(
            Mailbox.Folder.self,
            from: #"{"name":"sent","label":"folder.sent","icon":"","count":1,"unread":0}"#
                .data(using: .utf8)!)
        XCTAssertNotEqual(folder?.title, "folder.sent",
                          "a system folder must not show its key")
    }

    func testEveryErrorCodeHasASentence() throws {
        // The bridge names a case and Swift says it. A code without a sentence
        // reaches the screen as the code.
        let table = try strings("en")
        let codes: [ComposeError] = [.noRecipient, .noSender, .tooLarge,
                                     .notPermitted, .refused, .badDraft]
        for code in codes {
            XCTAssertNotNil(table["compose.\(code.rawValue)"],
                            "no sentence for \(code.rawValue)")
        }
        for warning: SendResult.Warning in [.notRecorded, .sentNotStored, .draftNotRemoved] {
            XCTAssertNotNil(table["compose.\(warning.rawValue)"],
                            "no sentence for \(warning.rawValue)")
        }
    }
}
