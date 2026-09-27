import XCTest

/// Scripted walk-through of ONE speech bubble for the "how a bubble works"
/// marketing reel: EN EL SENDERO (EL REY NEGRO, episode 2), story page 1, the
/// bottom-right bubble "¿Qué está pasando aquí?". Same handshake as
/// DemoRecording (ready / go / events.json / done in the runner's Documents/demo).
///
/// The narration is mixed in afterwards from the marks in events.json, so the
/// pauses here only need to leave room for each spoken line.
final class BubbleReel: XCTestCase {
    var app: XCUIApplication!
    var syncDir: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("demo").path
    }
    var probe: Bool { ProcessInfo.processInfo.environment["DEMO_PROBE"] == "1" }
    var t0 = Date()
    var events: [[String: Any]] = []
    let pageAspect: CGFloat = 1024.0 / 1536.0
    let collectionTitle = "EL REY NEGRO"
    let comicTitle = "EN EL SENDERO"
    let pageLabel = "Page 2"
    /// "¿Qué está pasando aquí?" — normalised box from the generator (x, y, w, h).
    let bubble = CGRect(x: 0.7128, y: 0.7252, width: 0.2, height: 0.1425)

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        var args = ["-hasLaunchedBefore", "YES", "-demo.hideCues", "YES", "-creatorMessage.seen", "YES", "-demo.unlimited", "YES"]
        for k in ["library-title", "choose-collection", "comic-cockpit", "cover-text", "page-swipe", "story-bubble",
                  "hotspot-info", "bubble-panel", "word-detail", "story-arrows", "help-reminder",
                  "collection-download", "collection-open-after-download"] {
            args += ["-help.seen.\(k)", "YES"]
        }
        app.launchArguments = args
    }

    // MARK: helpers (as in DemoRecording)

    func snap(_ name: String) {
        guard probe else { return }
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "\(syncDir)/\(name).png"))
        try? app.debugDescription.write(toFile: "\(syncDir)/\(name).txt", atomically: true, encoding: .utf8)
    }
    func mark(_ what: String) { events.append(["t": Date().timeIntervalSince(t0), "what": what]) }
    func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }
    func waitTap(_ el: XCUIElement, _ label: String, timeout: Double = 8, pre: String? = nil) {
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "missing: \(label)")
        if let pre {
            var w = 0.0
            while app.buttons["Stop"].exists && w < 4 { pause(0.1); w += 0.1 }
            mark("pre " + pre)
        }
        el.tap()
    }
    func pageRect() -> CGRect {
        var frame = app.windows.firstMatch.frame
        frame.origin.y += 15
        let scale = min(frame.width / pageAspect, frame.height)
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
        let byName = app.buttons["Volume High"]
        if byName.waitForExistence(timeout: 3) { return byName.firstMatch }
        return app.popovers.buttons.firstMatch
    }
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
    /// Frames of the things the post-processing crops around, in points.
    func geometry() -> [String: Any] {
        let win = app.windows.firstMatch.frame
        var g: [String: Any] = ["window": [win.minX, win.minY, win.width, win.height]]
        let r = pageRect()
        g["page"] = [r.minX, r.minY, r.width, r.height]
        g["bubble"] = [r.minX + bubble.minX * r.width, r.minY + bubble.minY * r.height, bubble.width * r.width, bubble.height * r.height]
        let play = app.buttons["Play"].firstMatch
        if play.exists { g["play"] = [play.frame.minX, play.frame.minY, play.frame.width, play.frame.height] }
        let xs = app.buttons.matching(identifier: "xmark.circle.fill").allElementsBoundByIndex
        if let x = xs.first { g["cardClose"] = [x.frame.minX, x.frame.minY, x.frame.width, x.frame.height] }
        let word = app.buttons["pasando"].firstMatch
        if word.exists { g["word"] = [word.frame.minX, word.frame.minY, word.frame.width, word.frame.height] }
        return g
    }

    // MARK: the script

    func testBubbleReel() throws {
        try? FileManager.default.createDirectory(atPath: syncDir, withIntermediateDirectories: true)
        for f in ["ready", "go", "done", "events.json", "geometry.json"] { try? FileManager.default.removeItem(atPath: "\(syncDir)/\(f)") }
        app.launch()

        let cta = app.buttons["Get started"].exists ? app.buttons["Get started"] : app.buttons["Continue learning"]
        waitTap(cta, "landing CTA")
        snap("01-library")
        let coll = app.staticTexts[collectionTitle]
        if coll.waitForExistence(timeout: 8) { coll.firstMatch.tap() }
        snap("02-collection")
        // The collection screen: our episode is the only downloaded one, so its Open button is the first.
        let open = app.buttons["Open"].firstMatch
        if open.waitForExistence(timeout: 8) { open.tap() } else { waitTap(app.staticTexts[comicTitle].firstMatch, "comic row") }
        snap("03-detail")
        let thumb = app.staticTexts[pageLabel]
        var tries = 0
        while !(thumb.exists && thumb.isHittable) && tries < 8 { app.swipeUp(); tries += 1; pause(0.4) }
        if !thumb.exists { snap("03b-nothumb") }
        XCTAssertTrue(thumb.exists, "\(pageLabel) thumbnail")
        thumb.tap()
        pause(1.5)
        snap("04-page")

        // Warm up off camera: open the bubble, play, close.
        tapBubble(bubble); pause(0.8)
        waitTap(app.buttons["Play"].firstMatch, "warm-up Play"); pause(2.6)
        // Geometry while the card is open (bubble box, card's Play/close, the word chip).
        let geo = geometry()
        if let d = try? JSONSerialization.data(withJSONObject: geo, options: [.prettyPrinted]) { try? d.write(to: URL(fileURLWithPath: "\(syncDir)/geometry.json")) }
        snap("05-warm-card")
        closeCard(); pause(1.0)

        FileManager.default.createFile(atPath: "\(syncDir)/ready", contents: nil)
        var waited = 0.0
        while !FileManager.default.fileExists(atPath: "\(syncDir)/go") && waited < 60 { pause(0.1); waited += 0.1 }
        t0 = Date()
        mark("start")
        pause(1.0)                                                       // full page, 1s

        tapBubble(bubble); mark("tap bubble")                            // bubble turns green, card opens
        pause(3.6); snap("06-card")                                      // room for "Tap any speech bubble" + "Play the line…"
        waitTap(app.buttons["Play"].firstMatch, "Play", pre: "play"); mark("play")
        pause(2.4)                                                       // the Spanish line (1.84s) + a beat
        waitTap(app.buttons["Show translation"].firstMatch, "Show translation"); mark("translation")
        pause(1.0); snap("07-translation")
        waitTap(app.buttons["Explain grammar"].firstMatch, "Explain grammar"); mark("grammar")
        pause(2.2); snap("08-grammar")                                   // the note, read out then held
        waitTap(app.buttons["Close grammar note"].firstMatch, "Close grammar note"); mark("close grammar")
        pause(0.3)
        waitTap(app.buttons["pasando"].firstMatch, "word pasando"); mark("tap pasando")
        pause(0.3); snap("09-word")
        waitTap(wordPlayButton(), "word play", pre: "play pasando"); mark("play pasando")
        pause(2.0)                                                       // rest of "Tap any word…"
        waitTap(app.buttons["More"].firstMatch, "More"); mark("more")
        pause(1.6); snap("10-more")                                      // "More shows every form…" + 1.5s
        waitTap(app.buttons["Done"].firstMatch, "Done (forms)"); mark("close more")
        pause(0.5)
        waitTap(app.buttons["pasando"].firstMatch, "word pasando again"); mark("tap pasando again")
        pause(0.4)
        waitTap(app.buttons["Explain further"].firstMatch, "Explain further"); mark("explain")
        pause(2.6); snap("11-explain")                                   // covered by the supplied image in post
        waitTap(app.buttons["Done"].firstMatch, "Done (explain)"); mark("close explain")
        pause(0.5)
        closeCard(); mark("close card")
        pause(2.2); snap("12-end")
        mark("end")
        pause(3.0)                                                       // the recorder drops its last seconds: keep rolling past the end

        let data = try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted])
        try data.write(to: URL(fileURLWithPath: "\(syncDir)/events.json"))
        FileManager.default.createFile(atPath: "\(syncDir)/done", contents: nil)
    }
}
