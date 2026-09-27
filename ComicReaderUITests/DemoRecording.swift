import XCTest

/// Scripted walk-through of the reading flow, used to record marketing clips
/// on the Simulator (`xcrun simctl io booted recordVideo` runs alongside).
///
/// Handshake with the recording shell script via files in DEMO_SYNC_DIR
/// (a host path — Simulator processes can see the Mac's filesystem):
///   ready  ← written by the test when the page is on screen
///   go     → written by the shell once recording has started
///   events.json ← tap timestamps (seconds since `go`) for audio muxing
///   done   ← written by the test at the end
final class DemoRecording: XCTestCase {
    var app: XCUIApplication!
    // The runner's own Documents folder — the host reads it via
    // `xcrun simctl get_app_container booted com.comicreader.app.uitests.xctrunner data`.
    var syncDir: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("demo").path
    }
    // Pass `TEST_RUNNER_DEMO_PROBE=1` to xcodebuild to get per-step screenshots + hierarchy dumps.
    var probe: Bool { ProcessInfo.processInfo.environment["DEMO_PROBE"] == "1" }
    // `TEST_RUNNER_DEMO_SIMPLE=1`: only bubble → Play → Show translation; no word taps, no forms sheet.
    var simple: Bool { ProcessInfo.processInfo.environment["DEMO_SIMPLE"] == "1" || minimal }
    // `TEST_RUNNER_DEMO_MINIMAL=1`: like simple, and no Show translation taps either.
    var minimal: Bool { ProcessInfo.processInfo.environment["DEMO_MINIMAL"] == "1" }
    var t0 = Date()
    var events: [[String: Any]] = []

    // Which comic/page to demo — override with TEST_RUNNER_DEMO_* env vars
    // (defaults: page 8 of LA BIBLIOTECA). Art is 1024x1536 for all comics.
    let pageAspect: CGFloat = 1024.0 / 1536.0
    var env: [String: String] { ProcessInfo.processInfo.environment }
    var collectionTitle: String { env["DEMO_COLLECTION"] ?? "LOS NIÑOS EN LAS SOMBRAS" }
    var comicTitle: String { env["DEMO_COMIC"] ?? "LA BIBLIOTECA" }
    var pageLabel: String { "Page " + (env["DEMO_PAGE"] ?? "8") }
    /// First bubble to open: normalised box "x,y,w,h" from comic.json.
    var bubbleNoEsSeguro: CGRect {
        let v = (env["DEMO_BUBBLE1"] ?? "0.0775,0.1936,0.2,0.1").split(separator: ",").compactMap { Double($0) }
        return v.count == 4 ? CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) : CGRect(x: 0.0775, y: 0.1936, width: 0.2, height: 0.1)
    }
    /// Arrow steps from the first bubble to the last one (default 2: one bubble in between).
    var stepsToLast: Int { Int(env["DEMO_STEPS"] ?? "2") ?? 2 }
    /// `TEST_RUNNER_DEMO_SINGLE=1`: the page has only one bubble to show — play it, close, turn the page.
    var single: Bool { env["DEMO_SINGLE"] == "1" }
    /// `TEST_RUNNER_DEMO_ALL=1`: play every bubble in turn (arrow-stepping DEMO_STEPS times), then turn the page.
    var playAll: Bool { env["DEMO_ALL"] == "1" }
    /// `TEST_RUNNER_DEMO_WAITS="2.0,3.4,..."`: seconds to wait after each stepped bubble's Play (audio length + a beat).
    var playWaits: [Double] { (env["DEMO_WAITS"] ?? "").split(separator: ",").compactMap { Double($0) } }
    let bubbleAqui = CGRect(x: 0.4025, y: 0.8792, width: 0.2, height: 0.1)

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Silence every first-run tooltip / cue so the recording is clean.
        var args = ["-hasLaunchedBefore", "YES", "-demo.hideCues", "YES", "-creatorMessage.seen", "YES",
                    "-spanishLevel", "beginner"]
        for k in ["library-title", "choose-collection", "comic-cockpit", "cover-text", "page-swipe", "story-bubble",
                  "hotspot-info", "bubble-panel", "word-detail", "story-arrows", "help-reminder",
                  "collection-download", "collection-open-after-download"] {
            args += ["-help.seen.\(k)", "YES"]
        }
        app.launchArguments = args
    }

    // MARK: helpers

    func snap(_ name: String) {
        guard probe else { return }
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "\(syncDir)/\(name).png"))
        try? app.debugDescription.write(toFile: "\(syncDir)/\(name).txt", atomically: true, encoding: .utf8)
    }
    func mark(_ what: String) { events.append(["t": Date().timeIntervalSince(t0), "what": what]) }
    func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }
    /// `pre` stamps the moment just before the tap is sent: XCUITest's tap() only
    /// returns once the app is idle again, which can be a second late while the
    /// app is animating (word highlights during playback), so post-tap marks
    /// are unreliable for audio alignment.
    func waitTap(_ el: XCUIElement, _ label: String, timeout: Double = 8, pre: String? = nil) {
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "missing: \(label)")
        if let pre {
            // Never turn a Play into a Stop: wait until nothing is playing.
            var w = 0.0
            while app.buttons["Stop"].exists && w < 4 { pause(0.1); w += 0.1 }
            mark("pre " + pre)
        }
        el.tap()
    }
    /// The rect the aspect-fit page art occupies on screen (whole window minus
    /// nothing — PagedImageView fills its GeometryReader, so we use the biggest
    /// image element's frame, falling back to the window).
    func pageRect() -> CGRect {
        // The UIImageView is not in the accessibility tree; measured on the
        // iPhone 17 Pro (402x874pt): art fills the width and its centre sits
        // ~15pt below the window centre (toolbar above, tab bar below).
        var frame = app.windows.firstMatch.frame
        frame.origin.y += 15
        let scale = min(frame.width / pageAspect, frame.height) // fitted height
        let h = scale, w = scale * pageAspect
        return CGRect(x: frame.midX - w / 2, y: frame.midY - h / 2, width: w, height: h)
    }
    func tapBubble(_ b: CGRect) {
        let r = pageRect()
        let x = r.minX + (b.midX) * r.width, y = r.minY + (b.midY) * r.height
        let win = app.windows.firstMatch
        let v = CGVector(dx: x / win.frame.width, dy: y / win.frame.height)
        win.coordinate(withNormalizedOffset: v).tap()
    }
    func wordPlayButton() -> XCUIElement {
        // The word popover's top-right speaker has no label; SwiftUI exposes SF
        // Symbol-only buttons by symbol name.
        let byName = app.buttons["Volume High"]   // SF Symbol speaker.wave.2.fill
        if byName.waitForExistence(timeout: 3) { return byName.firstMatch }
        return app.popovers.buttons.firstMatch
    }
    /// Close the floating bubble card; verified by its Play button going away.
    func closeCard() {
        for attempt in 0..<3 {
            let xs = app.buttons.matching(identifier: "xmark.circle.fill").allElementsBoundByIndex
            if let x = xs.first(where: { $0.isHittable }) ?? xs.first { x.tap() }
            else if app.buttons["Close"].exists { app.buttons["Close"].firstMatch.tap() }
            var w = 0.0
            while app.buttons["Play"].exists && w < 1.0 { pause(0.1); w += 0.1 }
            if !app.buttons["Play"].exists { return }
            snap("close-retry-\(attempt)")
        }
    }

    // MARK: the script

    func testDemoScript() throws {
        try? FileManager.default.createDirectory(atPath: syncDir, withIntermediateDirectories: true)
        for f in ["ready", "go", "done", "events.json"] { try? FileManager.default.removeItem(atPath: "\(syncDir)/\(f)") }
        app.launch()

        // Landing → Library
        let cta = app.buttons["Get started"].exists ? app.buttons["Get started"] : app.buttons["Continue learning"]
        waitTap(cta, "landing CTA")
        snap("01-library")
        // Library → collection → comic
        let coll = app.staticTexts[collectionTitle]
        if coll.waitForExistence(timeout: 5) { coll.firstMatch.tap() }
        // Collection screen: the downloaded episode's "Open" button.
        let open = app.buttons["Open"].firstMatch
        if open.waitForExistence(timeout: 5) { open.tap() } else { waitTap(app.staticTexts[comicTitle].firstMatch, "comic row") }
        snap("02-detail")
        // Detail → Page 8 thumbnail (scroll the detail screen down until it shows)
        let thumb = app.staticTexts[pageLabel]
        var tries = 0
        while !(thumb.exists && thumb.isHittable) && tries < 8 { app.swipeUp(); tries += 1; pause(0.4) }
        if !thumb.exists { snap("02b-nothumb") }
        XCTAssertTrue(thumb.exists, "Page 8 thumbnail")
        thumb.tap()
        pause(1.5)
        snap("03-page")

        // Warm up the audio engine before recording: the very first playback of
        // a session starts ~1s late on the Simulator and the first word highlights
        // are skipped. Open the bubble, play, close — all off camera.
        tapBubble(bubbleNoEsSeguro); pause(0.8)
        waitTap(app.buttons["Play"].firstMatch, "warm-up Play"); pause(3.0)
        closeCard(); pause(1.0)

        // Handshake: page on screen → let the shell start recording.
        FileManager.default.createFile(atPath: "\(syncDir)/ready", contents: nil)
        var waited = 0.0
        while !FileManager.default.fileExists(atPath: "\(syncDir)/go") && waited < 60 { pause(0.1); waited += 0.1 }
        t0 = Date()
        mark("start")
        pause(0.5)                                                   // 1. full page

        tapBubble(bubbleNoEsSeguro); mark("tap bubble 1")            // 2.
        pause(0.9); snap("04-card1")
        waitTap(app.buttons["Play"].firstMatch, "Play", pre: "play s1"); mark("play s1")   // 3. (2.0s clip)
        pause(4.8)                                                   // room for a spoken cue after the line
        if !minimal {
            waitTap(app.buttons["Show translation"].firstMatch, "Show translation"); mark("translation 1")  // 4.
            pause(3.8)                                               // room for the translation to be read out
        }
        if !simple {
            waitTap(app.buttons["seguro."].firstMatch, "word seguro"); mark("tap seguro")   // 5.
            pause(0.9); snap("05-word1")
            waitTap(wordPlayButton(), "word play", pre: "play seguro"); mark("play seguro")   // 6. (1.44s)
            pause(1.9)
            // Dismiss the popover (tap outside).
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
            pause(0.5)
        }
        // Step to the bottom bubble with the card's own "next" arrow — the bubble
        // itself sits under the open card, and stepping makes the card slide up.
        if playAll {
            for k in 0..<stepsToLast {
                let next = app.buttons.matching(NSPredicate(format: "identifier == 'chevron.right' AND label == 'Forward'"))
                let cardNext = next.allElementsBoundByIndex.max(by: { $0.frame.minY < $1.frame.minY })!
                cardNext.tap(); mark("step \(k + 2)")
                pause(0.9); snap("card-\(k + 2)")
                waitTap(app.buttons["Play"].firstMatch, "Play \(k + 2)", pre: "play b\(k + 2)"); mark("play b\(k + 2)")
                pause(k < playWaits.count ? playWaits[k] : 3.2)
            }
        }
        for k in 0..<((single || playAll) ? 0 : stepsToLast) {
            let next = app.buttons.matching(NSPredicate(format: "identifier == 'chevron.right' AND label == 'Forward'"))
            let cardNext = next.allElementsBoundByIndex.max(by: { $0.frame.minY < $1.frame.minY })!   // the lower one is on the card
            cardNext.tap()
            if k == stepsToLast - 1 { mark("tap bubble 3") }         // 7. last bubble: card slides up
            else { mark(k == 0 ? "step bubble 2" : "step bubble 2." + String(k)); pause(0.7) }
        }
        if !single && !playAll {
            pause(0.9); snap("06-card2")
            waitTap(app.buttons["Play"].firstMatch, "Play 2", pre: "play s3"); mark("play s3")  // 8. (2.4s)
            pause(2.8)
        }
        if !minimal {
            waitTap(app.buttons["Show translation"].firstMatch, "Show translation 2"); mark("translation 2")  // 9.
            pause(3.8)
        }
        if !simple {
            waitTap(app.buttons["lugar?"].firstMatch, "word lugar"); mark("tap lugar")   // 10.
            pause(0.9); snap("07-word2")
            waitTap(wordPlayButton(), "word play 2", pre: "play lugar"); mark("play lugar")  // 11. (1.04s)
            pause(1.5)
            waitTap(app.buttons["More"].firstMatch, "More"); mark("more")  // 12.
            pause(1.4); snap("08-more")
            waitTap(app.buttons["Done"].firstMatch, "Done"); mark("done sheet")  // 13.
            pause(1.2)                                                   // let the sheet finish dismissing
        }
        snap("08b-before-close")
        closeCard(); mark("close card 2")                            // 14.
        snap("08c-after-close")
        pause(0.6)
        mark("next page")                                            // 15. finger drag, like on the phone
        let win = app.windows.firstMatch
        let from = win.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.55))
        let to = win.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.55))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: XCUIGestureVelocity(600), thenHoldForDuration: 0.05)
        pause(2.5); snap("09-next")                                  // keep recording well past the slide
        mark("end")

        let data = try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted])
        try data.write(to: URL(fileURLWithPath: "\(syncDir)/events.json"))
        FileManager.default.createFile(atPath: "\(syncDir)/done", contents: nil)
    }

}
