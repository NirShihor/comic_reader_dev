import XCTest

/// Diagnostic end-to-end run of the free preview on a fresh install (needs
/// the StoreKit configuration on the scheme's Test action and the network):
/// Get started → library → download the first episode → read → the turn past
/// the fourth story page opens the one subscription invitation at once →
/// Not now → still on the last free page → the practice modes are still there.
final class FreePreviewProbe: XCTestCase {
    func testFreshInstallPreviewMeetsTheInvitationOnPageFive() throws {
        let app = XCUIApplication()
        var args = ["-demo.hideCues", "YES", "-creatorMessage.seen", "YES", "-spanishLevel", "beginner"]
        for k in ["library-title", "choose-collection", "comic-cockpit", "cover-text", "page-swipe", "story-bubble",
                  "hotspot-info", "bubble-panel", "word-detail", "story-arrows", "help-reminder",
                  "collection-download", "collection-open-after-download"] {
            args += ["-help.seen.\(k)", "YES"]
        }
        app.launchArguments = args
        // A fresh simulator meets the App Store sandbox's "Sign in to Apple
        // Account" alert on the first StoreKit call: cancel it, now and whenever
        // it comes back, so the run goes on signed out (products still load).
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        func cancelSandboxSignIn() {
            for host in [app, springboard] {
                let cancel = host.alerts.buttons["Cancel"].firstMatch
                if cancel.waitForExistence(timeout: 1.5) { print("PROBE sandbox sign-in cancelled"); cancel.tap(); Thread.sleep(forTimeInterval: 0.5) }
            }
            // The alert can also leave the app behind the home screen: bring it back.
            if app.state != .runningForeground { print("PROBE app re-activated"); app.activate(); Thread.sleep(forTimeInterval: 1.0) }
        }
        /// Wait for `element`, cancelling the sandbox alert whenever it interrupts.
        func waitSettled(_ element: XCUIElement, _ timeout: TimeInterval) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if element.waitForExistence(timeout: 3) { return true }
                cancelSandboxSignIn()
            }
            return element.exists
        }
        addUIInterruptionMonitor(withDescription: "App Store sandbox sign-in") { alert in
            guard alert.buttons["Cancel"].exists else { return false }
            alert.buttons["Cancel"].tap()
            return true
        }
        cancelSandboxSignIn()
        app.launch()

        // 1. Landing: no trial button, "Get started" is the way in.
        let getStarted = app.buttons["Get started"]
        XCTAssertTrue(waitSettled(getStarted, 40), "landing CTA; texts \(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(8)) buttons \(app.buttons.allElementsBoundByIndex.map(\.label).prefix(8))")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start your'")).firstMatch.exists, "no trial offer on the landing screen")
        getStarted.tap()

        // 2. Library → first collection → first episode card → Download.
        let collection = app.staticTexts["EL REY NEGRO"].firstMatch
        XCTAssertTrue(waitSettled(collection, 60), "collection in the library (the catalogue is fetched on a fresh install)")
        collection.tap()
        // Episode 2: under legacy rules (what a simulator that can't reach the
        // sandbox falls back to) episode 1 is free in full, so it never previews.
        let downloads = app.buttons.matching(NSPredicate(format: "label == 'Download'"))
        XCTAssertTrue(waitSettled(downloads.firstMatch, 30), "Download buttons on the episode cards")
        let download = downloads.count > 1 ? downloads.element(boundBy: 1) : downloads.firstMatch
        download.tap()

        // 3. The comic opens by itself — onto its home screen, then (the first-run
        // tips being marked seen) straight into the reader.
        let start = app.staticTexts["Start reading"].firstMatch
        let counter = app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]+/[0-9]+$'")).firstMatch
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline, !counter.exists, !start.exists { cancelSandboxSignIn(); Thread.sleep(forTimeInterval: 1.0) }
        // The home screen hands over to the reader by itself a moment later;
        // whichever is up now, end in the reader.
        if !counter.waitForExistence(timeout: 5), start.waitForExistence(timeout: 5) {
            if start.exists { start.tap() }
        }

        // 4. Turn pages: cover → 2 → 3 → 4 read; the turn to 5 opens the
        // invitation at once — no covers mosaic, no card before it.
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
        let heading = app.staticTexts["Want to know what happens next?"]
        let mosaic = app.otherElements["Cover mosaic"]
        let oldCard = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'End of the'")).firstMatch
        let continueReading = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Continue reading'")).firstMatch
        let notNow = app.buttons["Not now"]
        func expectInvitation(_ why: String) {
            XCTAssertTrue(heading.waitForExistence(timeout: 4), "\(why): the invitation, straight away; counter \(counter.label)")
            XCTAssertFalse(mosaic.exists, "\(why): no covers mosaic")
            XCTAssertFalse(oldCard.exists, "\(why): no end-of-preview card")
            XCTAssertFalse(app.buttons["Practice sample pages"].exists, "\(why): no competing action on the invitation")
            XCTAssertTrue(continueReading.waitForExistence(timeout: 10), "\(why): the primary button")
            XCTAssertTrue(notNow.exists, "\(why): Not now")
        }
        app.swipeLeft()
        expectInvitation("first attempt")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Cancel anytime.'")).firstMatch.waitForExistence(timeout: 5),
                      "the price line; texts: \(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(12))")
        print("PROBE invitation: texts=\(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(14)) buttons=\(app.buttons.allElementsBoundByIndex.map(\.label).prefix(10))")
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/claude-501/invitation-\(UIDevice.current.name.replacingOccurrences(of: " ", with: "-")).png"))

        // 5. Not now: still on page 4, back works, and the next attempt asks
        // the same way — nothing replays, nothing else appears.
        notNow.tap()
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertFalse(heading.exists, "invitation closed")
        XCTAssertTrue(counter.label.hasPrefix("4/"), "stays on the last free page, got \(counter.label)")
        app.swipeRight(); Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(counter.label.hasPrefix("3/"), "can go back, got \(counter.label)")
        turn(to: 4)
        app.swipeLeft()
        expectInvitation("second attempt")
        notNow.tap()
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(counter.label.hasPrefix("4/"), "still on the last free page, got \(counter.label)")

        // 6. Comic home: a locked thumbnail opens the reader on the last free
        // page with the invitation; the saved position never passed page 4.
        app.buttons["Home"].firstMatch.tap()
        // Read to page 4, the home's button says "Continue reading", not "Start reading".
        XCTAssertTrue(app.staticTexts["Continue reading"].firstMatch.waitForExistence(timeout: 10), "the comic home")
        let page7 = app.staticTexts["Page 7"].firstMatch
        for _ in 0..<8 where !page7.exists { app.swipeUp(); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertTrue(page7.waitForExistence(timeout: 5), "thumbnail grid")
        page7.tap()
        expectInvitation("locked thumbnail")
        XCTAssertTrue(counter.label.hasPrefix("4/"), "…over the last free page, got \(counter.label)")
        notNow.tap()
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
        XCTAssertFalse(heading.exists, "no invitation when the saved page is itself free")

        // 7. The free practice modes are still there, on the comic home:
        // practice in the preview is its own pages only; Key phrases locked.
        app.buttons["Home"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.0)
        let note = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Practicing the first 3 sample pages'")).firstMatch
        for _ in 0..<8 where !note.exists { app.swipeUp(); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertTrue(note.waitForExistence(timeout: 5), "the preview practice note")
        let inlineReadSpeak = app.staticTexts["Read & speak"].firstMatch
        XCTAssertTrue(inlineReadSpeak.waitForExistence(timeout: 5), "inline Read & speak card")
        inlineReadSpeak.tap()
        XCTAssertTrue(counter.waitForExistence(timeout: 10), "guided run from the home")
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(counter.label.hasPrefix("1/"), "Read & speak from the home starts on the cover, got \(counter.label)")
        app.buttons["Home"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.0)
        for _ in 0..<8 where !note.exists { app.swipeUp(); Thread.sleep(forTimeInterval: 0.6) }
        let keyPhrases = app.staticTexts["Key phrases"].firstMatch
        if keyPhrases.exists {
            keyPhrases.tap()
            let locked = app.staticTexts.matching(NSPredicate(format: "label == 'Keep the story going' OR label BEGINSWITH 'Try Comigo free'")).firstMatch
            XCTAssertTrue(locked.waitForExistence(timeout: 10), "Key phrases: the full subscription paywall")
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

        // 8. ("Continue reading" → Apple's sheet, cancelling it, and carrying on
        // to page 5 after a purchase are verified on a device run from Xcode:
        // under `xcodebuild test` the simulator reaches the App Store sandbox,
        // not the local StoreKit configuration, and asks to sign in.)
    }

    /// Simulator only: the comic home while the rest of the comic is still
    /// downloading (its progress bar), then the collection once it's in.
    func testDownloadProgressScreenshots() throws {
        let app = XCUIApplication()
        var args = ["-demo.hideCues", "YES", "-creatorMessage.seen", "YES", "-spanishLevel", "beginner"]
        for k in ["library-title", "choose-collection", "comic-cockpit", "cover-text", "page-swipe", "story-bubble",
                  "hotspot-info", "bubble-panel", "word-detail", "story-arrows", "help-reminder",
                  "collection-download", "collection-open-after-download"] {
            args += ["-help.seen.\(k)", "YES"]
        }
        app.launchArguments = args
        app.launch()
        app.buttons["Get started"].tap()
        let collection = app.staticTexts["EL REY NEGRO"].firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 20)); collection.tap()
        let downloads = app.buttons.matching(NSPredicate(format: "label == 'Download'"))
        XCTAssertTrue(downloads.firstMatch.waitForExistence(timeout: 20))
        (downloads.count > 1 ? downloads.element(boundBy: 1) : downloads.firstMatch).tap()
        let start = app.staticTexts["Start reading"].firstMatch
        let counter = app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]+/[0-9]+$'")).firstMatch
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline, !counter.exists, !start.exists { Thread.sleep(forTimeInterval: 0.2) }
        if !counter.waitForExistence(timeout: 5), start.waitForExistence(timeout: 5), start.exists { start.tap() }
        XCTAssertTrue(counter.waitForExistence(timeout: 20))
        app.buttons["Home"].firstMatch.tap()
        let bar = app.otherElements["Download progress"]
        print("PROBE comic home: bar=\(bar.waitForExistence(timeout: 3)) texts=\(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(20))")
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/claude-501/dl-home-0.png"))
        Thread.sleep(forTimeInterval: 1.5)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/claude-501/dl-home-1.png"))
        app.navigationBars.buttons.firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.0)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/claude-501/dl-collection-0.png"))
        let reading = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Reading · page'")).firstMatch
        _ = reading.waitForExistence(timeout: 120)
        Thread.sleep(forTimeInterval: 1.0)
        print("PROBE collection: texts=\(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(24))")
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/claude-501/dl-collection-1.png"))
    }
}
