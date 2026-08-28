// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// The App Store screenshots, taken by a test rather than by hand.
///
/// Not because it is clever, but because screenshots go stale silently: the app
/// changes, the pictures on the product page do not, and nobody notices until a
/// reviewer does. A test that walks the app produces them again on demand, and
/// fails loudly when the way through it has moved.
///
/// Everything happens in the sample mailbox — which is also why the sample
/// exists. Nobody should photograph real correspondence to show what a mail
/// client looks like.
final class Screenshots: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // German, because the store listing is German first and the sample mail
        // follows the device language. The launch argument is the only way to
        // pin it: a simulator inherits whatever the last run left behind.
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
    }

    func testWalkTheSampleMailbox() {
        // 1 — the first screen, and the way in without an account.
        // A minute, and that is not padding: on a simulator that was just
        // erased the first launch includes installing the app, and fifteen
        // seconds is not enough. A screenshot run that fails on timing looks
        // exactly like one that fails on a missing button.
        let sample = app.buttons["Beispiel ansehen"]
        XCTAssertTrue(sample.waitForExistence(timeout: 60),
                      "the way into the sample is gone - a reviewer cannot use the app")
        shot("01-einrichten")
        sample.tap()

        // 2 — folders, with the unread counts that make a mailbox look alive.
        guard let inbox = waitForLabel("Posteingang") else {
            shot("02-fehlgeschlagen")
            return XCTFail("no folder list")
        }
        shot("02-ordner")
        inbox.tap()

        // 3 — the message list.
        guard let newsletter = waitForLabel("Ofen lohnt") else {
            shot("03-fehlgeschlagen")
            return XCTFail("no message list")
        }
        shot("03-liste")
        newsletter.tap()

        // 4 — HTML mail in the sandboxed view, remote image blocked.
        //
        // "Bohnentopf" and not "Wochenküche" or "Zwiebeln", and the reason is
        // the whole history of this test. The sender is called "Die
        // Wochenküche", so that word proves only that a header drew. And a list
        // row carries the *whole* preview in its accessibility label, not the
        // truncated line on screen — so "Zwiebeln" matched the row somebody had
        // not even opened yet, and the test went green over a screenshot of the
        // list.
        //
        // "Bohnentopf" sits in the table, far past where any preview stops. It
        // exists only if the document itself is on screen.
        XCTAssertNotNil(waitForLabel("Bohnentopf"), "the mail body never appeared")
        Thread.sleep(forTimeInterval: 1.0)
        shot("04-nachricht")
    }

    /// Waits for the first element carrying this text, whatever kind it is.
    ///
    /// Polled rather than asked once: the queries are evaluated the moment they
    /// are built, and right after a tap nothing exists yet. Asking once and
    /// then waiting on whichever query happened to be returned made the walk
    /// flaky - it passed, then it did not, with nothing changed between.
    ///
    /// By label and not by the subscript: `app.staticTexts["Posteingang"]`
    /// matches an accessibility *identifier*, and a SwiftUI list row has none —
    /// its text sits inside a cell. The button on the first screen worked only
    /// because buttons carry their title as an identifier too.
    private func waitForLabel(_ text: String, timeout: TimeInterval = 25) -> XCUIElement? {
        let match = NSPredicate(format: "label CONTAINS[c] %@", text)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for query in [app.cells, app.buttons, app.staticTexts] {
                let found = query.matching(match).firstMatch
                if found.exists && found.isHittable { return found }
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return nil
    }

    /// One screenshot, kept whatever the test does afterwards.
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
