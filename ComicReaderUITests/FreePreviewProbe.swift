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
        // First, once a launch, the covers mosaic: the page tiles with covers,
        // holds, and gives way to the End-of-preview card.
        let mosaic = app.otherElements["Cover mosaic"]
        let card = app.staticTexts["End of the free preview"]
        XCTAssertTrue(mosaic.waitForExistence(timeout: 5), "the covers mosaic first; counter \(counter.label)")
        XCTAssertFalse(card.exists, "no card while the mosaic plays")
        let mosaicEnd = Date().addingTimeInterval(10)
        while mosaic.exists, Date() < mosaicEnd { Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertFalse(mosaic.exists, "the mosaic is over")
        // The End-of-preview card: practise these pages, or unlock the rest.
        XCTAssertTrue(card.waitForExistence(timeout: 5), "end-of-preview card after the mosaic; counter \(counter.label)")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'The story goes on for 8 more pages'")).firstMatch.exists, "says the story goes on")
        XCTAssertTrue(app.buttons["Practice sample pages"].exists, "the practice option")
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

        // 8. "Practice sample pages" from the card lands on the practice options;
        // practice in the preview: its own pages only; Key phrases locked.
        swipeLeft()
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        app.buttons["Practice sample pages"].tap()
        XCTAssertTrue(app.staticTexts["Practice"].firstMatch.waitForExistence(timeout: 10), "practice options after the card")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Practicing the first 3 sample pages'")).firstMatch.waitForExistence(timeout: 5), "the preview practice note in the popup")
        // Read & speak from the card starts on the cover, not the page they left.
        // Two "Read & speak" cards exist (the inline section under the popup's
        // scrim, and the popup's own); the popup's is the last in the tree.
        XCTAssertTrue(app.staticTexts["Read & speak"].firstMatch.waitForExistence(timeout: 5))
        let readSpeak = app.staticTexts.matching(identifier: "Read & speak").allElementsBoundByIndex.last!
        readSpeak.tap()
        if !counter.waitForExistence(timeout: 10) {
            print("PROBE after Read & speak: texts \(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(20)) buttons \(app.buttons.allElementsBoundByIndex.map(\.label).prefix(15))")
        }
        XCTAssertTrue(counter.exists, "guided run opens")
        Thread.sleep(forTimeInterval: 1.0)
        print("PROBE read&speak opened on \(counter.label)")
        XCTAssertTrue(counter.label.hasPrefix("1/"), "Read & speak from the card starts on the cover, got \(counter.label)")
        app.buttons["Home"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.0)
        if app.buttons["Close"].firstMatch.exists { app.buttons["Close"].firstMatch.tap(); Thread.sleep(forTimeInterval: 1.0) }
        // The home's own Practice section, after plain reading up to page 4:
        // Read & speak still starts on the cover (not the saved reading page).
        // After a guided run the primary button is "Continue practicing"; read instead.
        let readAgain = app.staticTexts["Continue reading instead"].firstMatch.exists ? app.staticTexts["Continue reading instead"].firstMatch : cont
        XCTAssertTrue(readAgain.waitForExistence(timeout: 5), "a way back into reading")
        readAgain.tap()                              // read again: the saved page is 4
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)
        app.buttons["Home"].firstMatch.tap()
        let inlineReadSpeak = app.staticTexts["Read & speak"].firstMatch
        for _ in 0..<8 where !inlineReadSpeak.exists { app.swipeUp(); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertTrue(inlineReadSpeak.waitForExistence(timeout: 5), "inline Read & speak card")
        inlineReadSpeak.tap()
        XCTAssertTrue(counter.waitForExistence(timeout: 10), "guided run from the home")
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(counter.label.hasPrefix("1/"), "Read & speak from the home starts on the cover, got \(counter.label)")
        app.buttons["Home"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.0)
        let note = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Practicing the first 3 sample pages'")).firstMatch
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

    /// Device check: from the End-of-preview card, "Practice sample pages" must
    /// leave the reader and land on the comic home's practice options.
    func testPracticeSamplePagesLeavesTheReader() throws {
        let app = XCUIApplication()
        var args = ["-demo.hideCues", "YES", "-creatorMessage.seen", "YES", "-spanishLevel", "beginner", "-preview.coverMosaic", "NO"]
        for k in ["library-title", "choose-collection", "comic-cockpit", "cover-text", "page-swipe", "story-bubble",
                  "hotspot-info", "bubble-panel", "word-detail", "story-arrows", "help-reminder",
                  "collection-download", "collection-open-after-download"] {
            args += ["-help.seen.\(k)", "YES"]
        }
        app.launchArguments = args
        app.launch()
        let getStarted = app.buttons["Get started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 15), "landing CTA")
        getStarted.tap()
        let collection = app.staticTexts["EL REY NEGRO"].firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 20), "collection in the library")
        collection.tap()
        let downloads = app.buttons.matching(NSPredicate(format: "label == 'Download'"))
        XCTAssertTrue(downloads.firstMatch.waitForExistence(timeout: 20), "Download buttons")
        let download = downloads.count > 1 ? downloads.element(boundBy: 1) : downloads.firstMatch
        download.tap()
        let start = app.staticTexts["Start reading"].firstMatch
        let counter = app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]+/[0-9]+$'")).firstMatch
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline, !counter.exists, !start.exists { Thread.sleep(forTimeInterval: 1.0) }
        if !counter.waitForExistence(timeout: 5), start.waitForExistence(timeout: 5), start.exists { start.tap() }
        XCTAssertTrue(counter.waitForExistence(timeout: 20), "page counter")
        func swipeLeft() { app.swipeLeft(); Thread.sleep(forTimeInterval: 1.5) }
        func turn(to expected: Int) {
            for _ in 0..<3 where !counter.label.hasPrefix("\(expected)/") { swipeLeft() }
            XCTAssertTrue(counter.label.hasPrefix("\(expected)/"), "expected page \(expected), got \(counter.label)")
        }
        for expected in 2...4 { turn(to: expected) }
        swipeLeft()
        let card = app.staticTexts["End of the free preview"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "end-of-preview card; counter \(counter.label)")
        let practice = app.buttons["Practice sample pages"]
        XCTAssertTrue(practice.exists, "the practice option")
        practice.tap()
        let popup = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Practicing the first 3 sample pages'")).firstMatch
        let landed = popup.waitForExistence(timeout: 8)
        print("PROBE after tap: card=\(card.exists) counter=\(counter.exists ? counter.label : "gone") popup=\(landed) texts=\(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(16)) buttons=\(app.buttons.allElementsBoundByIndex.map(\.label).prefix(12))")
        XCTAssertTrue(landed, "practice options after the card")
        XCTAssertFalse(counter.exists, "the reader has gone")
    }

    /// Same, as a genuine first run: the amber first-run tips are live and get
    /// tapped away as they appear, like a new user would.
    func testPracticeSamplePagesLeavesTheReaderWithFirstRunTips() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-creatorMessage.seen", "YES", "-spanishLevel", "beginner", "-preview.coverMosaic", "NO"]
        app.launch()
        let known: Set<String> = ["Get started", "Download", "Library", "Vocabulary", "Notebook", "Settings", "Back", "Close", "Home",
                                  "Practice sample pages", "Bin", "questionmark.circle", "Help", "Exit help"]
        // Tap away any amber tip (a long-labelled button that isn't a control).
        func clearTips() {
            for _ in 0..<4 {
                // Tips read as sentences ("Now choose a collection."); cards and controls don't.
                let tip = app.buttons.matching(NSPredicate(format: "(label ENDSWITH '.' OR label ENDSWITH '!') AND NOT (label CONTAINS ',') AND NOT (label BEGINSWITH 'Start your') AND NOT (label BEGINSWITH 'Unlock with')")).firstMatch
                if tip.exists, !known.contains(tip.label), tip.isHittable {
                    print("PROBE tip: \(tip.label)")
                    tip.tap(); Thread.sleep(forTimeInterval: 0.8); continue
                }
                let close = app.buttons["Close"].firstMatch
                if close.exists, close.isHittable {
                    print("PROBE help tooltip closed")
                    close.tap(); Thread.sleep(forTimeInterval: 0.8); continue
                }
                return
            }
        }
        func dump(_ where_: String) {
            print("PROBE \(where_): texts=\(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(14)) buttons=\(app.buttons.allElementsBoundByIndex.map(\.label).prefix(14))")
        }
        let getStarted = app.buttons["Get started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 15), "landing CTA")
        getStarted.tap()
        clearTips()
        let collection = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'EL REY NEGRO'")).firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 20), "collection in the library")
        collection.tap()
        clearTips()
        let downloads = app.buttons.matching(NSPredicate(format: "label == 'Download'"))
        for _ in 0..<3 where !downloads.firstMatch.waitForExistence(timeout: 8) {
            dump("no Download yet"); clearTips()
            if collection.exists, collection.isHittable { collection.tap() }
        }
        XCTAssertTrue(downloads.firstMatch.waitForExistence(timeout: 20), "Download buttons")
        let download = downloads.count > 1 ? downloads.element(boundBy: 1) : downloads.firstMatch
        download.tap()
        let start = app.staticTexts["Start reading"].firstMatch
        let counter = app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]+/[0-9]+$'")).firstMatch
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline, !counter.exists, !start.exists { clearTips(); Thread.sleep(forTimeInterval: 1.0) }
        for _ in 0..<6 where !counter.exists {
            clearTips()
            if start.exists, start.isHittable { start.tap() }
            _ = counter.waitForExistence(timeout: 4)
        }
        XCTAssertTrue(counter.waitForExistence(timeout: 20), "page counter; texts \(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(12))")
        func swipeLeft() { clearTips(); app.swipeLeft(); Thread.sleep(forTimeInterval: 1.5) }
        func turn(to expected: Int) {
            for _ in 0..<4 where !counter.label.hasPrefix("\(expected)/") { swipeLeft() }
            XCTAssertTrue(counter.label.hasPrefix("\(expected)/"), "expected page \(expected), got \(counter.label)")
        }
        for expected in 2...4 { turn(to: expected) }
        let card = app.staticTexts["End of the free preview"]
        for _ in 0..<3 where !card.exists { swipeLeft() }
        XCTAssertTrue(card.waitForExistence(timeout: 10), "end-of-preview card; counter \(counter.label)")
        let practice = app.buttons["Practice sample pages"]
        XCTAssertTrue(practice.exists, "the practice option")
        practice.tap()
        let popup = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Practicing the first 3 sample pages'")).firstMatch
        let landed = popup.waitForExistence(timeout: 8)
        print("PROBE after tap (tips live): card=\(card.exists) counter=\(counter.exists ? counter.label : "gone") popup=\(landed) texts=\(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(16)) buttons=\(app.buttons.allElementsBoundByIndex.map(\.label).prefix(12))")
        XCTAssertTrue(landed, "practice options after the card")
        XCTAssertFalse(counter.exists, "the reader has gone")
    }
}
