import XCTest

/// Diagnostic end-to-end run of the free preview on a fresh install (needs
/// the StoreKit configuration on the scheme's Test action and the network):
/// Get started → library → download the first episode → read → the fourth
/// story page meets the paywall → close → still on the last free page.
final class FreePreviewProbe: XCTestCase {
    func testFreshInstallPreviewMeetsThePaywallOnPageFive() throws {
        let app = XCUIApplication()
        var args = ["-demo.hideCues", "YES", "-creatorMessage.seen", "YES", "-spanishLevel", "beginner"]
        for k in ["library-title", "choose-collection", "comic-cockpit", "cover-text", "page-swipe", "story-bubble",
                  "hotspot-info", "bubble-panel", "word-detail", "story-arrows", "help-reminder",
                  "collection-download", "collection-open-after-download"] {
            args += ["-help.seen.\(k)", "YES"]
        }
        app.launchArguments = args
        app.launch()

        // 1. Landing: no trial button, "Get started" is the way in.
        let getStarted = app.buttons["Get started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 15), "landing CTA")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start your'")).firstMatch.exists, "no trial offer on the landing screen")
        getStarted.tap()

        // 2. Library → first collection → first episode card → Download.
        let collection = app.staticTexts["EL REY NEGRO"].firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 20), "collection in the library")
        collection.tap()
        // Episode 2: under legacy rules (what a simulator that can't reach the
        // sandbox falls back to) episode 1 is free in full, so it never previews.
        let downloads = app.buttons.matching(NSPredicate(format: "label == 'Download'"))
        XCTAssertTrue(downloads.firstMatch.waitForExistence(timeout: 20), "Download buttons on the episode cards")
        XCTAssertTrue(app.staticTexts["3 pages free"].firstMatch.waitForExistence(timeout: 5), "'3 pages free' on a card")
        let download = downloads.count > 1 ? downloads.element(boundBy: 1) : downloads.firstMatch
        download.tap()

        // 3. The comic opens by itself — onto its home screen, then (the first-run
        // tips being marked seen) straight into the reader.
        let start = app.staticTexts["Start reading"].firstMatch
        let counter = app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]+/[0-9]+$'")).firstMatch
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline, !counter.exists, !start.exists { Thread.sleep(forTimeInterval: 1.0) }
        // The home screen hands over to the reader by itself a moment later;
        // whichever is up now, end in the reader.
        if !counter.waitForExistence(timeout: 5), start.waitForExistence(timeout: 5) {
            XCTAssertTrue(app.staticTexts["· 3 pages free"].firstMatch.exists, "'3 pages free' on the comic home")
            if start.exists { start.tap() }
        }

        // 4. Turn pages: cover → 2 → 3 → 4 read; the turn to 5 meets the paywall.
        XCTAssertTrue(counter.waitForExistence(timeout: 20), "page counter")
        XCTAssertTrue(counter.label.hasPrefix("1/"), "opens on the cover, got \(counter.label)")
        func swipeLeft() { app.swipeLeft(); Thread.sleep(forTimeInterval: 1.5) }
        // A swipe can be swallowed while a page is still loading: turn until
        // the counter shows the page, never more than a couple of tries each.
        func turn(to expected: Int) {
            for _ in 0..<3 where !counter.label.hasPrefix("\(expected)/") { swipeLeft() }
            XCTAssertTrue(counter.label.hasPrefix("\(expected)/"), "expected page \(expected), got \(counter.label)")
        }
        for expected in 2...4 { turn(to: expected) }
        swipeLeft()
        // The End-of-preview card: practise these pages, or unlock the rest.
        let card = app.staticTexts["End of the free preview"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "end-of-preview card; counter \(counter.label)")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'The story goes on for 8 more pages'")).firstMatch.exists, "says the story goes on")
        XCTAssertTrue(app.buttons["Practise these pages"].exists, "the practice option")
        let unlock = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start your' OR label BEGINSWITH 'Unlock with'")).firstMatch
        XCTAssertTrue(unlock.exists, "the unlock option")
        unlock.tap()
        let heading = app.staticTexts["Want to know what happens next?"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "preview paywall from the card")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'free trial' OR label CONTAINS 'Subscribe'")).firstMatch.exists, "the subscription offer")

        // 5. Close: still on page 4, and back works.
        app.buttons["Close"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertFalse(heading.exists, "paywall closed")
        XCTAssertFalse(card.exists, "card closed too")
        XCTAssertTrue(counter.label.hasPrefix("4/"), "stays on the last free page, got \(counter.label)")
        app.swipeRight(); Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(counter.label.hasPrefix("3/"), "can go back, got \(counter.label)")
        turn(to: 4)
        swipeLeft()
        XCTAssertTrue(card.waitForExistence(timeout: 10), "asks again on the next attempt")
        app.buttons["Close"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.0)

        // 6. Comic home: a locked thumbnail opens the reader on the last free
        // page with the paywall; the saved position never passed page 4.
        app.buttons["Home"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["· 3 pages free"].firstMatch.waitForExistence(timeout: 10), "'3 pages free' on the comic home")
        let page7 = app.staticTexts["Page 7"].firstMatch
        for _ in 0..<8 where !page7.exists { app.swipeUp(); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertTrue(page7.waitForExistence(timeout: 5), "thumbnail grid")
        page7.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 10), "locked thumbnail: the end-of-preview card")
        XCTAssertTrue(counter.label.hasPrefix("4/"), "…over the last free page, got \(counter.label)")
        app.buttons["Close"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.0)
        app.buttons["Home"].firstMatch.tap()
        let cont = app.staticTexts["Continue reading"].firstMatch
        XCTAssertTrue(cont.waitForExistence(timeout: 10), "Continue reading")
        Thread.sleep(forTimeInterval: 1.0)   // let the pop settle before tapping
        cont.tap()
        if !counter.waitForExistence(timeout: 6), cont.exists { cont.tap() }
        XCTAssertTrue(counter.waitForExistence(timeout: 10), "reader after Continue reading")
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(counter.label.hasPrefix("4/"), "resumes on the last free page, got \(counter.label)")
        XCTAssertFalse(card.exists, "no card when the saved page is itself free")

        // 7. The paywall says the story goes on and what the offer opens.
        swipeLeft()
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        unlock.tap()
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'That\\'s the end of the free preview — the story goes on for 8 more pages.'")).firstMatch.exists,
                      "the preview line; texts: \(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(12))")
        XCTAssertTrue(app.staticTexts["The rest of this comic and all its practice modes"].exists, "the rest-of-comic row")
        app.buttons["Close"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.0)

        // 8. "Practise these pages" from the card lands on the practice options;
        // practice in the preview: its own pages only; Key phrases locked.
        swipeLeft()
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        app.buttons["Practise these pages"].tap()
        XCTAssertTrue(app.staticTexts["Practice"].firstMatch.waitForExistence(timeout: 10), "practice options after the card")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Practising the first 3 pages'")).firstMatch.waitForExistence(timeout: 5), "the preview practice note in the popup")
        app.buttons["Close"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.0)
        let note = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Practising the first 3 pages'")).firstMatch
        for _ in 0..<8 where !note.exists { app.swipeUp(); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertTrue(note.waitForExistence(timeout: 5), "the preview practice note")
        let keyPhrases = app.staticTexts["Key phrases"].firstMatch
        if keyPhrases.exists {
            keyPhrases.tap()
            let locked = app.staticTexts.matching(NSPredicate(format: "label == 'Keep the story going' OR label BEGINSWITH 'Try Comigo free'")).firstMatch
            XCTAssertTrue(locked.waitForExistence(timeout: 10), "Key phrases: the subscription paywall")
            app.buttons["Close"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
        let listenSpeak = app.staticTexts["Listen & speak"].firstMatch
        XCTAssertTrue(listenSpeak.waitForExistence(timeout: 5), "Listen & speak card")
        listenSpeak.tap()
        let esEs = app.buttons["Spanish → Spanish & English"].firstMatch
        XCTAssertTrue(esEs.waitForExistence(timeout: 10), "the Listen & speak chooser")
        esEs.tap()
        let count = app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]+ sentences$'")).firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 15), "the Listen & speak intro")
        let n = Int(count.label.split(separator: " ").first ?? "") ?? 0
        XCTAssertTrue(n > 0 && n <= 23, "the preview's sentences only (EN EL SENDERO: 17 of 56), got \(count.label)")

        // 9. (Subscribing and carrying on to page 5 is verified on a device run
        // from Xcode: under `xcodebuild test` the simulator reaches the App Store
        // sandbox, not the local StoreKit configuration, and asks to sign in.)
    }
}
