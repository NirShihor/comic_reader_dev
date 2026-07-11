import SwiftUI
import UIKit

/// The page artwork, animated with a Core Animation slide when the page changes.
/// The comic's bubbles/text are baked into the image, so a page turn is just an
/// image swap — done at the CA layer so it's reliable regardless of SwiftUI's
/// animation quirks in this view. Invisible SwiftUI tap targets sit on top and
/// realign the instant the new page settles.
struct PagedImageView: UIViewRepresentable {
    let imageName: String
    let comicId: String
    let pageKey: Int     // changes on a real page turn (drives the slide)
    let forward: Bool    // turn direction

    final class Coordinator {
        weak var imageView: UIImageView?
        var lastKey: Int?
        var lastImageName: String?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    // Plain container (no intrinsic size) so SwiftUI's frame drives the size; the
    // image view is pinned to fill it and aspect-fits the artwork within.
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            iv.topAnchor.constraint(equalTo: container.topAnchor),
            iv.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        iv.image = ComicImageLoader.shared.loadImage(named: imageName, forComic: comicId)
        context.coordinator.imageView = iv
        context.coordinator.lastKey = pageKey
        context.coordinator.lastImageName = imageName
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coord = context.coordinator
        guard let iv = coord.imageView else { return }
        let newImage = ComicImageLoader.shared.loadImage(named: imageName, forComic: comicId)
        if coord.lastKey != pageKey {
            // Real page turn → slide the artwork in from the side we're heading toward.
            let t = CATransition()
            t.type = .push
            t.subtype = forward ? .fromRight : .fromLeft
            t.duration = 0.35
            t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            iv.layer.add(t, forKey: "pageTurn")
            iv.image = newImage
            coord.lastKey = pageKey
            coord.lastImageName = imageName
        } else if coord.lastImageName != imageName {
            // Same page, different bake (e.g. a practice-mode toggle) → swap, no slide.
            iv.image = newImage
            coord.lastImageName = imageName
        }
    }
}

/// Flood-fills a single speech-bubble's white interior (from its centre) to
/// produce a green "the bubble is open" highlight that matches the bubble's real
/// shape — the bubbles are baked into the page raster, so we can't recolour them
/// directly; instead we bucket-fill the blank interior (like GIMP) on the
/// empty-bubbles bake, bounded to the bubble's padded rect so a break in the
/// border can't leak into the rest of the page.
enum BubbleFill {
    static let cache = NSCache<NSString, UIImage>()
    // Tight normalized bounding box of the flood, cached alongside interiorMask's
    // image so a cache hit can still return it (used to cover a sound-effect balloon).
    static let boundsCache = NSCache<NSString, NSValue>()

    /// `maskSource` (the blank/empty-bubbles bake) defines the bubble's full
    /// interior via flood fill; within that shape we paint `color` everywhere the
    /// `inkSource` (the on-screen, with-text image) is NOT dark — so the baked
    /// text stays transparent while enclosed letter-counters (o, p, a, e) still
    /// get filled. Returns a crop-sized overlay + the normalized region it covers,
    /// or nil if it can't produce a clean fill (caller falls back to the dot).
    static func overlay(maskSource: String, inkSource: String, comicId: String,
                        bubble nb: CGRect, color: UIColor,
                        cacheKey: String) -> (image: UIImage, region: CGRect)? {
        // Padded region around the bubble, in normalized page coords. Pad by the
        // LARGER dimension on both sides: the stored geometry is the text box, but
        // the baked balloon can be much wider/taller than that (e.g. a narrow text
        // column in a wide ellipse). A too-tight crop slices through the balloon
        // so the fill runs off the crop edge and looks like a leak. This keeps the
        // whole balloon (plus tail) inside the crop; the fill still stops at the
        // bubble's own border, so a wide crop is safe.
        let pad = max(nb.width, nb.height) * 0.8
        let nx0 = max(0, nb.minX - pad), ny0 = max(0, nb.minY - pad)
        let nx1 = min(1, nb.maxX + pad), ny1 = min(1, nb.maxY + pad)
        let region = CGRect(x: nx0, y: ny0, width: nx1 - nx0, height: ny1 - ny0)

        if let cached = cache.object(forKey: cacheKey as NSString) { return (cached, region) }

        guard let maskImg = ComicImageLoader.shared.loadImage(named: maskSource, forComic: comicId),
              let maskCG = maskImg.cgImage else { return nil }
        let iw = maskCG.width, ih = maskCG.height
        guard iw > 0, ih > 0 else { return nil }

        let px0 = max(0, Int(nx0 * CGFloat(iw))), py0 = max(0, Int(ny0 * CGFloat(ih)))
        let px1 = min(iw, Int(nx1 * CGFloat(iw))), py1 = min(ih, Int(ny1 * CGFloat(ih)))
        let cw = px1 - px0, ch = py1 - py0
        let cropRect = CGRect(x: px0, y: py0, width: cw, height: ch)
        guard cw > 2, ch > 2, let maskCrop = maskCG.cropping(to: cropRect) else { return nil }

        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        func readPixels(_ crop: CGImage) -> [UInt8]? {
            var b = [UInt8](repeating: 0, count: cw * ch * 4)
            guard let c = CGContext(data: &b, width: cw, height: ch, bitsPerComponent: 8,
                                    bytesPerRow: cw * 4, space: space, bitmapInfo: info) else { return nil }
            c.draw(crop, in: CGRect(x: 0, y: 0, width: cw, height: ch))
            return b
        }
        guard let maskBuf = readPixels(maskCrop) else { return nil }

        // Ink image (the with-text bake) — same crop; nil if unavailable or a
        // different size, in which case we just fill the whole interior.
        var inkBuf: [UInt8]? = nil
        if inkSource != maskSource,
           let inkImg = ComicImageLoader.shared.loadImage(named: inkSource, forComic: comicId),
           let inkCG = inkImg.cgImage, inkCG.width == iw, inkCG.height == ih,
           let inkCrop = inkCG.cropping(to: cropRect) {
            inkBuf = readPixels(inkCrop)
        }

        func interior(_ x: Int, _ y: Int) -> Bool {
            let i = (y * cw + x) * 4
            return maskBuf[i] > 190 && maskBuf[i + 1] > 190 && maskBuf[i + 2] > 190 && maskBuf[i + 3] > 40
        }

        // Seed at the bubble centre (crop-local); spiral out to the nearest
        // interior pixel if the centre lands on ink.
        var sx = min(max(Int(nb.midX * CGFloat(iw)) - px0, 0), cw - 1)
        var sy = min(max(Int(nb.midY * CGFloat(ih)) - py0, 0), ch - 1)
        if !interior(sx, sy) {
            var found = false
            search: for d in 1...(max(cw, ch) / 2) {
                let x0 = max(0, sx - d), x1 = min(cw - 1, sx + d)
                let y0 = max(0, sy - d), y1 = min(ch - 1, sy + d)
                for yy in y0...y1 { for xx in x0...x1 where interior(xx, yy) { sx = xx; sy = yy; found = true; break search } }
            }
            if !found { return nil }
        }

        // BFS flood fill the interior shape on the mask.
        var filled = [Bool](repeating: false, count: cw * ch)
        var stack = [(Int, Int)](); stack.reserveCapacity(cw * ch / 4)
        filled[sy * cw + sx] = true; stack.append((sx, sy))
        var count = 0
        var edgePixels = 0
        while let (x, y) = stack.popLast() {
            count += 1
            if x == 0 || y == 0 || x == cw - 1 || y == ch - 1 { edgePixels += 1 }
            if x > 0, !filled[y*cw + x-1], interior(x-1, y) { filled[y*cw + x-1] = true; stack.append((x-1, y)) }
            if x < cw-1, !filled[y*cw + x+1], interior(x+1, y) { filled[y*cw + x+1] = true; stack.append((x+1, y)) }
            if y > 0, !filled[(y-1)*cw + x], interior(x, y-1) { filled[(y-1)*cw + x] = true; stack.append((x, y-1)) }
            if y < ch-1, !filled[(y+1)*cw + x], interior(x, y+1) { filled[(y+1)*cw + x] = true; stack.append((x, y+1)) }
        }
        // Reject the fill if:
        // - it runs BROADLY along the crop edge — a borderless narration (title,
        //   "continuará") that spilled onto the art. A speech-bubble tail only
        //   *nicks* the edge (a handful of pixels), so that's allowed; a spill
        //   touches a long run of it. Threshold scales with the crop size.
        // - it's much smaller than the bubble (a single letter's enclosed counter
        //   in borderless narration text), or
        // - it's a gross leak filling most of the crop.
        let total = cw * ch
        let bubbleArea = nb.width * CGFloat(iw) * nb.height * CGFloat(ih)
        let edgeLimit = max(24, min(cw, ch) / 5)
        if edgePixels > edgeLimit || count < Int(bubbleArea * 0.1) || count > Int(Double(total) * 0.9) { return nil }

        // Paint: green over the interior, but transparent where the ink image is
        // dark (the baked text) so glyphs stay readable; letter-counters (white in
        // the ink image) fall inside the shape and get filled.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let R = UInt8(max(0.0, min(255.0, r * 255))), G = UInt8(max(0.0, min(255.0, g * 255))), B = UInt8(max(0.0, min(255.0, b * 255)))
        var out = [UInt8](repeating: 0, count: cw * ch * 4)
        for p in 0..<total where filled[p] {
            let i = p * 4
            if let ink = inkBuf, ink[i] < 150, ink[i + 1] < 150, ink[i + 2] < 150 { continue } // dark = text
            out[i] = R; out[i + 1] = G; out[i + 2] = B; out[i + 3] = 255
        }
        guard let octx = CGContext(data: &out, width: cw, height: ch, bitsPerComponent: 8,
                                   bytesPerRow: cw * 4, space: space, bitmapInfo: info),
              let ocg = octx.makeImage() else { return nil }
        let img = UIImage(cgImage: ocg)
        cache.setObject(img, forKey: cacheKey as NSString)
        return (img, region)
    }

    /// Solid interior mask for a bubble: opaque (white) over the WHOLE flood-filled
    /// balloon interior, transparent elsewhere — following the balloon's real shape,
    /// NOT its padded bounding box. Used to clip the practice "reveal" so it uncovers
    /// only the tapped bubble's own balloon and can't bleed into a neighbour that
    /// happens to fall inside the padded crop rectangle. `region` is the normalized
    /// padded crop the mask image maps onto (same convention as `overlay`).
    static func interiorMask(maskSource: String, comicId: String, bubble nb: CGRect,
                             cacheKey: String) -> (image: UIImage, region: CGRect, bounds: CGRect)? {
        let pad = max(nb.width, nb.height) * 0.8
        let nx0 = max(0, nb.minX - pad), ny0 = max(0, nb.minY - pad)
        let nx1 = min(1, nb.maxX + pad), ny1 = min(1, nb.maxY + pad)
        let region = CGRect(x: nx0, y: ny0, width: nx1 - nx0, height: ny1 - ny0)

        if let cached = cache.object(forKey: cacheKey as NSString),
           let bv = boundsCache.object(forKey: cacheKey as NSString) {
            return (cached, region, bv.cgRectValue)
        }

        guard let maskImg = ComicImageLoader.shared.loadImage(named: maskSource, forComic: comicId),
              let maskCG = maskImg.cgImage else { return nil }
        let iw = maskCG.width, ih = maskCG.height
        guard iw > 0, ih > 0 else { return nil }

        let px0 = max(0, Int(nx0 * CGFloat(iw))), py0 = max(0, Int(ny0 * CGFloat(ih)))
        let px1 = min(iw, Int(nx1 * CGFloat(iw))), py1 = min(ih, Int(ny1 * CGFloat(ih)))
        let cw = px1 - px0, ch = py1 - py0
        let cropRect = CGRect(x: px0, y: py0, width: cw, height: ch)
        guard cw > 2, ch > 2, let maskCrop = maskCG.cropping(to: cropRect) else { return nil }

        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        var maskBuf = [UInt8](repeating: 0, count: cw * ch * 4)
        guard let c = CGContext(data: &maskBuf, width: cw, height: ch, bitsPerComponent: 8,
                                bytesPerRow: cw * 4, space: space, bitmapInfo: info) else { return nil }
        c.draw(maskCrop, in: CGRect(x: 0, y: 0, width: cw, height: ch))

        func interior(_ x: Int, _ y: Int) -> Bool {
            let i = (y * cw + x) * 4
            return maskBuf[i] > 190 && maskBuf[i + 1] > 190 && maskBuf[i + 2] > 190 && maskBuf[i + 3] > 40
        }

        var sx = min(max(Int(nb.midX * CGFloat(iw)) - px0, 0), cw - 1)
        var sy = min(max(Int(nb.midY * CGFloat(ih)) - py0, 0), ch - 1)
        if !interior(sx, sy) {
            var found = false
            search: for d in 1...(max(cw, ch) / 2) {
                let x0 = max(0, sx - d), x1 = min(cw - 1, sx + d)
                let y0 = max(0, sy - d), y1 = min(ch - 1, sy + d)
                for yy in y0...y1 { for xx in x0...x1 where interior(xx, yy) { sx = xx; sy = yy; found = true; break search } }
            }
            if !found { return nil }
        }

        var filled = [Bool](repeating: false, count: cw * ch)
        var stack = [(Int, Int)](); stack.reserveCapacity(cw * ch / 4)
        filled[sy * cw + sx] = true; stack.append((sx, sy))
        var count = 0
        var edgePixels = 0
        var minx = cw, miny = ch, maxx = 0, maxy = 0
        while let (x, y) = stack.popLast() {
            count += 1
            if x < minx { minx = x }; if x > maxx { maxx = x }
            if y < miny { miny = y }; if y > maxy { maxy = y }
            if x == 0 || y == 0 || x == cw - 1 || y == ch - 1 { edgePixels += 1 }
            if x > 0, !filled[y*cw + x-1], interior(x-1, y) { filled[y*cw + x-1] = true; stack.append((x-1, y)) }
            if x < cw-1, !filled[y*cw + x+1], interior(x+1, y) { filled[y*cw + x+1] = true; stack.append((x+1, y)) }
            if y > 0, !filled[(y-1)*cw + x], interior(x, y-1) { filled[(y-1)*cw + x] = true; stack.append((x, y-1)) }
            if y < ch-1, !filled[(y+1)*cw + x], interior(x, y+1) { filled[(y+1)*cw + x] = true; stack.append((x, y+1)) }
        }
        let total = cw * ch
        let bubbleArea = nb.width * CGFloat(iw) * nb.height * CGFloat(ih)
        let edgeLimit = max(24, min(cw, ch) / 5)
        if edgePixels > edgeLimit || count < Int(bubbleArea * 0.1) || count > Int(Double(total) * 0.9) { return nil }

        // Tight normalized bbox of the flooded interior (inside the balloon border).
        let bounds = CGRect(x: CGFloat(px0 + minx) / CGFloat(iw), y: CGFloat(py0 + miny) / CGFloat(ih),
                            width: CGFloat(maxx - minx) / CGFloat(iw), height: CGFloat(maxy - miny) / CGFloat(ih))

        var out = [UInt8](repeating: 0, count: cw * ch * 4)
        for p in 0..<total where filled[p] {
            let i = p * 4
            out[i] = 255; out[i + 1] = 255; out[i + 2] = 255; out[i + 3] = 255
        }
        guard let octx = CGContext(data: &out, width: cw, height: ch, bitsPerComponent: 8,
                                   bytesPerRow: cw * 4, space: space, bitmapInfo: info),
              let ocg = octx.makeImage() else { return nil }
        let img = UIImage(cgImage: ocg)
        cache.setObject(img, forKey: cacheKey as NSString)
        boundsCache.setObject(NSValue(cgRect: bounds), forKey: cacheKey as NSString)
        return (img, region, bounds)
    }
}

/// Draws a hotspot's traced outline. `points` are normalized page coordinates;
/// `box` is the hotspot's normalized bounding box. Points are mapped into the
/// shape's own frame relative to that box, so the same shape renders correctly
/// whether the frame is placed in full-page space or panel-relative space.
struct HotspotPolygon: Shape {
    let points: [CornerPoint]
    let box: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 3, box.width > 0, box.height > 0 else { return path }
        for (i, pt) in points.enumerated() {
            let x = (pt.x - box.minX) / box.width * rect.width
            let y = (pt.y - box.minY) / box.height * rect.height
            let p = CGPoint(x: x, y: y)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// Like `HotspotPolygon` but maps normalized page points directly across the
/// whole frame — used to clip a full-page image copy to the traced region.
struct HotspotPolygonFull: Shape {
    let points: [CornerPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 3 else { return path }
        for (i, pt) in points.enumerated() {
            let p = CGPoint(x: pt.x * rect.width, y: pt.y * rect.height)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

struct PageView: View {
    let comic: Comic
    let page: Page
    /// When true, this is a guided "On Screen" practice run: speaking practice
    /// through the whole comic, then listening practice through the whole comic.
    var guidedOnScreenPractice: Bool = false
    /// Called when the reader taps "Practice" at the end of the episode — the
    /// detail screen uses it to open the practice options once this view pops.
    var onRequestPractice: (() -> Void)? = nil
    /// Open this bubble's floating card on appear (e.g. opening a word's context
    /// from the Vocabulary list).
    var initialBubbleId: String? = nil
    /// Transient context views (e.g. Vocabulary) shouldn't move the saved reading
    /// position; set false to skip progress saving.
    var savesProgress: Bool = true
    /// When presented modally (e.g. from Vocabulary), show a "Done" button that
    /// dismisses, instead of the "home" button used in the normal reading flow.
    var presentedModally: Bool = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var progressManager: ReadingProgressManager

    @State private var textRevealed = false
    @State private var selectedPanel: Panel?
    @State private var selectedHotspot: Hotspot?
    @State private var currentPageIndex: Int
    @State private var navForward = true   // last page-turn direction (drives the slide)
    @State private var navigateToPage: Int?
    @State private var showingVocabulary = false
    @State private var showingSettings = false
    @State private var showEndOfEpisode = false
    @State private var showSpeakingDonePrompt = false   // guided: speaking → listening
    @State private var showOnScreenComplete = false     // guided: all done
    @State private var selectedBubbleIndex: Int?   // open bubble in the floating card
    @State private var revealedBubbleId: String?   // practice: bubble whose text is revealed onto the page
    @State private var pageImageAspect: CGFloat?   // width/height of the page artwork
    @StateObject private var help = HelpModeController()

    // First-visit callout on the cover: "Click on the text." — points at the
    // tappable cover title bubble. Once-only (or always under forceShowTooltips).
    @AppStorage("help.seen.cover-text") private var seenCoverTip = false
    @State private var showCoverTip = false
    // Swipe-to-turn hint, chained after the word-popup guidance is closed.
    @AppStorage("help.seen.page-swipe") private var seenSwipeTip = false
    @State private var showSwipeTip = false
    // "Click on a bubble." — points at the first bubble on the first story page
    // the reader swipes to. Chained after the swipe hint's action.
    // (Key renamed from page-bubble: the old flag could be burned by a cover tap
    // before the fix that only marks it seen while actually showing.)
    @AppStorage("help.seen.story-bubble") private var seenBubbleTip = false
    @State private var showBubbleTip = false
    // True while "?" is replaying the page-level tooltips — bypasses "seen" flags.
    @State private var helpReplay = false

    // Pages sorted by pageNumber for consistent navigation
    private var sortedPages: [Page] {
        comic.pages.sorted { $0.pageNumber < $1.pageNumber }
    }

    // Text-bearing bubbles on the current page, in reading order (panel order,
    // then the bubble order within each panel). These are the tap targets for the
    // per-bubble reading sheet; sound effects and image bubbles are excluded.
    private var pageTextBubbles: [Bubble] {
        // On story pages, skip borderless/transparent narration — decorative markers
        // like "continuará…" — so they aren't tappable popup bubbles you have to step
        // through before "End of Episode". EXCEPTION: the cover title is also
        // transparent/borderless, but there we WANT it tappable so it opens the popup
        // and plays its audio. It still gets no green fill — selectedBubbleDot skips
        // bgTransparent bubbles — so the cover just pops up with audio, no highlight.
        let onCover = currentPageIndex == 0
        var bubbles = currentPage.panels
            .sorted { $0.panelOrder < $1.panelOrder }
            .flatMap { $0.bubbles }
            .filter { $0.isSoundEffect != true && $0.type != .image
                      && (onCover || $0.bgTransparent != true) && !$0.sentences.isEmpty }
        // On the final page, also drop any trailing narration (e.g. a "continuará…"
        // marker that predates the bgTransparent flag) so the flow ends on the last
        // line of dialogue — no clunky extra step that doesn't highlight and lags.
        if currentPageIndex == sortedPages.count - 1 {
            while let last = bubbles.last, last.type == .narration {
                bubbles.removeLast()
            }
        }
        return bubbles
    }

    // Non-practised baked bubbles (sound effects / image bubbles). In practice mode
    // the blank base hides these, so we overlay their master content to keep them
    // looking like reading mode.
    private var pageSoundEffectBubbles: [Bubble] {
        currentPage.panels
            .flatMap { $0.bubbles }
            .filter { $0.isSoundEffect == true || $0.type == .image }
    }

    private var isPracticeMode: Bool {
        settingsManager.speakingPracticeMode || settingsManager.listeningPracticeMode
    }

    // MARK: - Cover "Click on the text." callout
    private func maybeShowCoverTip() {
        guard currentPageIndex == 0, !isPracticeMode, selectedBubbleIndex == nil else { return }
        if !HelpDebug.forceShowTooltips { guard !seenCoverTip else { return } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard currentPageIndex == 0, selectedBubbleIndex == nil else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showCoverTip = true }
        }
    }

    private func dismissCoverTip() {
        seenCoverTip = true
        if showCoverTip {
            withAnimation(.easeInOut(duration: 0.2)) { showCoverTip = false }
            if helpReplay { maybeShowSwipeTip() }   // replay: swipe hint is next
        }
    }

    // MARK: - "Swipe to the next page" hint (chained after the word-popup guidance)
    private func maybeShowSwipeTip() {
        if !HelpDebug.forceShowTooltips && !helpReplay { guard !seenSwipeTip else { return } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showSwipeTip = true }
        }
    }

    private func dismissSwipeTip() {
        seenSwipeTip = true
        if showSwipeTip {
            withAnimation(.easeInOut(duration: 0.2)) { showSwipeTip = false }
            // Last page-level step — end the "?" replay.
            if helpReplay {
                helpReplay = false
                withAnimation(.easeInOut(duration: 0.2)) { help.isActive = false }
            }
        }
    }

    // MARK: - "Click on a bubble." hint (first story page after the swipe)
    private func maybeShowBubbleTip() {
        guard currentPageIndex > 0, !isPracticeMode, selectedBubbleIndex == nil else { return }
        if !HelpDebug.forceShowTooltips { guard !seenBubbleTip else { return } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard currentPageIndex > 0, selectedBubbleIndex == nil else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showBubbleTip = true }
        }
    }

    private func dismissBubbleTip() {
        seenBubbleTip = true
        if showBubbleTip {
            withAnimation(.easeInOut(duration: 0.2)) { showBubbleTip = false }
            if helpReplay { maybeShowSwipeTip() }   // replay: swipe hint is next
        }
    }

    /// Where the open bubble's card sits (mirrors FloatingBubbleCard.anchorTop), so
    /// the help banner can be placed on the opposite edge and not cover the card.
    private var openCardAnchorTop: Bool {
        guard let idx = selectedBubbleIndex, pageTextBubbles.indices.contains(idx) else { return false }
        let bubble = pageTextBubbles[idx]
        let referenceY: Double
        if let panel = currentPage.panels.first(where: { $0.bubbles.contains(where: { $0.id == bubble.id }) }),
           panel.tapZoneHeight <= 0.75 {
            referenceY = panel.tapZoneY + panel.tapZoneHeight / 2
        } else {
            referenceY = bubble.positionY + bubble.height / 2
        }
        return referenceY >= 0.5
    }

    /// The card sits at the bottom → put the help strip at the top (and vice versa).
    private var helpBannerEdge: VerticalEdge {
        (selectedBubbleIndex != nil && !openCardAnchorTop) ? .top : .bottom
    }

    init(comic: Comic, page: Page, guidedOnScreenPractice: Bool = false, onRequestPractice: (() -> Void)? = nil,
         initialBubbleId: String? = nil, savesProgress: Bool = true, presentedModally: Bool = false) {
        self.comic = comic
        self.page = page
        self.guidedOnScreenPractice = guidedOnScreenPractice
        self.onRequestPractice = onRequestPractice
        self.initialBubbleId = initialBubbleId
        self.savesProgress = savesProgress
        self.presentedModally = presentedModally
        // Initialize currentPageIndex to the correct page in sorted order
        let sorted = comic.pages.sorted { $0.pageNumber < $1.pageNumber }
        let index = sorted.firstIndex(where: { $0.id == page.id }) ?? 0
        _currentPageIndex = State(initialValue: index)
    }

    var currentPage: Page {
        sortedPages[currentPageIndex]
    }

    // The rectangle the aspect-fit page image actually occupies inside `size`
    // (centered, with letterbox bars excluded). Used to place tap targets so they
    // line up with the artwork rather than the full container.
    private func fittedImageRect(in size: CGSize) -> CGRect {
        guard let aspect = pageImageAspect, aspect > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        if size.width / size.height > aspect {
            let h = size.height, w = h * aspect
            return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: h)
        } else {
            let w = size.width, h = w / aspect
            return CGRect(x: 0, y: (size.height - h) / 2, width: w, height: h)
        }
    }

    // A pulsing, tappable hotspot marker mapped into the fitted page-image rect.
    // Coordinates (x/y/width/height) are fractions of the full page.
    @ViewBuilder
    private func hotspotIndicator(_ hotspot: Hotspot, in rect: CGRect) -> some View {
        let w = hotspot.width * rect.width
        let h = hotspot.height * rect.height
        let centerX = rect.minX + (hotspot.x + hotspot.width / 2) * rect.width
        let centerY = rect.minY + (hotspot.y + hotspot.height / 2) * rect.height
        // "transparent" hides the frame; otherwise the chosen colour, defaulting
        // to the generator's cyan when unset.
        let frameColor = hotspot.borderColor == "transparent"
            ? Color.clear
            : Color.fromHex(hotspot.borderColor, fallback: Color(red: 0, green: 188/255, blue: 212/255))

        if (hotspot.points?.count ?? 0) >= 3 {
            // Traced hotspots: the visible cue is the floating cut-out
            // (hotspotFloatingCutout). Here we just need the tap target.
            Color.clear
                .contentShape(Rectangle())
                .frame(width: w, height: h)
                .position(x: centerX, y: centerY)
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    selectedHotspot = hotspot
                }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                let pulse = (sin(seconds * 2.5) + 1.0) / 2.0
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(frameColor, lineWidth: 1.5 + pulse * 1.5)
                        .shadow(color: frameColor.opacity(pulse * 0.8), radius: 4 + pulse * 6)
                        .opacity(0.3 + pulse * 0.7)
                        .scaleEffect(1.0 + pulse * 0.15)
                    Color.clear.contentShape(Rectangle())
                }
            }
            .frame(width: w, height: h)
            .position(x: centerX, y: centerY)
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                selectedHotspot = hotspot
            }
        }
    }

    // Traced hotspots only: a live copy of the page art, clipped to the polygon
    // and gently scaled about the shape's centre so the region appears to lift /
    // float toward the reader as it pulses. At rest (scale 1.0) it sits flush and
    // is invisible; at the pulse peak it grows and casts a shadow.
    @ViewBuilder
    private func hotspotFloatingCutout(_ hotspot: Hotspot, in rect: CGRect) -> some View {
        if let pts = hotspot.points, pts.count >= 3 {
            let cx = pts.map { $0.x }.reduce(0, +) / Double(pts.count)
            let cy = pts.map { $0.y }.reduce(0, +) / Double(pts.count)
            // Match the displayed page base: blank bake in practice (a single
            // revealed bubble is handled separately), full art otherwise.
            let imageName = isPracticeMode
                ? (currentPage.emptyBubblesImage ?? currentPage.noTextImage ?? currentPage.masterImage)
                : currentPage.masterImage
            // Border you dictate in the generator: chosen colour, transparent to
            // hide, or the generator's default cyan when unset. It rides on the
            // cut-out so it scales with the artwork.
            let borderColor: Color = hotspot.borderColor == "transparent"
                ? .clear
                : Color.fromHex(hotspot.borderColor, fallback: Color(red: 0, green: 188/255, blue: 212/255))
            // Per-hotspot peak enlargement (fraction); small default when unset.
            let enlarge = hotspot.pulseScale ?? 0.12
            // Extra brightness at the peak (default +20%) so the enlarged image
            // reads clearly, and an optional glow tint washed over it.
            let brighten = hotspot.pulseBrightness ?? 0.2
            let tint: Color? = (hotspot.pulseTint?.isEmpty == false)
                ? Color.fromHex(hotspot.pulseTint, fallback: .clear) : nil
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                // Heartbeat: two quick pulses (lub-dub), then a pause, repeating
                // each cycle. Each beat is a fast grow→shrink; the gap and long
                // pause give it the double-thump-then-rest rhythm of a heart.
                let cycle = 2.6      // full heartbeat cycle (seconds)
                let beatDur = 0.26   // one quick grow→shrink (fast)
                let gap = 0.14       // pause between the two beats
                let t = seconds.truncatingRemainder(dividingBy: cycle)
                // Local time within whichever beat is active (-1 during the pause).
                let localT: Double = t < beatDur ? t
                    : ((t >= beatDur + gap && t < 2 * beatDur + gap) ? t - beatDur - gap : -1)
                let pulse = localT >= 0 ? (1 - cos(localT / beatDur * 2 * Double.pi)) / 2 : 0.0
                ComicImage(imageName: imageName, comicId: comic.id)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(HotspotPolygonFull(points: pts))
                    .brightness(pulse * brighten)
                    .overlay {
                        if let tint {
                            HotspotPolygonFull(points: pts)
                                .fill(tint)
                                .opacity(pulse * 0.5)
                                .blendMode(.plusLighter)
                        }
                    }
                    .overlay(
                        HotspotPolygonFull(points: pts)
                            .stroke(borderColor, lineWidth: 1.5 + pulse * 1.5)
                            .opacity(0.5 + pulse * 0.5)
                    )
                    .scaleEffect(1.0 + pulse * enlarge, anchor: UnitPoint(x: cx, y: cy))
                    .shadow(color: .black.opacity(0.12 + pulse * 0.28),
                            radius: 3 + pulse * 9, y: 1 + pulse * 5)
                    .allowsHitTesting(false)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
        }
    }

    // Practice reveal: when the reader taps "Reveal" on the open popup, uncover
    // ONLY that one bubble's text (not the whole page). The page stays on the
    // blank-bubble bake; here we overlay the master (with-text) art masked to the
    // revealed bubble's box. The two bakes are pixel-identical outside the bubbles,
    // so only this bubble's text appears and the mask edges are invisible.
    @ViewBuilder
    private func revealedBubbleOverlay(in rect: CGRect) -> some View {
        if isPracticeMode, let revId = revealedBubbleId,
           let b = pageTextBubbles.first(where: { $0.id == revId }) {
            bubbleMasterClip(b, in: rect)
        }
    }

    // Sound-effect / image bubbles have no audio and aren't practised, so blanking
    // them in practice mode is wrong — they should read exactly like reading mode.
    // Overlay their master (baked) content, clipped to each one's own shape, on top
    // of the blank practice base.
    @ViewBuilder
    private func soundEffectOverlay(in rect: CGRect) -> some View {
        if isPracticeMode {
            ForEach(pageSoundEffectBubbles) { b in
                bubbleMasterClip(b, in: rect, coverBorder: true)
            }
        }
    }

    // Overlays the master (with-content) art for a single bubble, clipped to its
    // real balloon SHAPE (flood-filled interior — never the padded bounding box,
    // which can overlap neighbours). Falls back to the padded text box when there's
    // no balloon to flood (borderless narration / sound effect painted on the art).
    @ViewBuilder
    private func bubbleMasterClip(_ b: Bubble, in rect: CGRect, coverBorder: Bool = false) -> some View {
        let maskSource = currentPage.emptyBubblesImage ?? currentPage.noTextImage ?? currentPage.masterImage
        let nb = CGRect(x: b.positionX, y: b.positionY, width: b.width, height: b.height)
        // Include geometry so a moved/resized bubble invalidates the cached interior mask.
        let geo = "\(Int(b.positionX*1e4))_\(Int(b.positionY*1e4))_\(Int(b.width*1e4))_\(Int(b.height*1e4))"
        let mkey = "\(comic.id)|p\(currentPage.pageNumber)|\(b.id)|\(geo)|\(maskSource)|imask"
        let mask = BubbleFill.interiorMask(maskSource: maskSource, comicId: comic.id, bubble: nb, cacheKey: mkey)
        let master = ComicImage(imageName: currentPage.masterImage, comicId: comic.id)
            .aspectRatio(contentMode: .fit)
            .frame(width: rect.width, height: rect.height)
        if let mask, coverBorder {
            // Sound effect: the empty bake drew a full balloon (thick black border)
            // where the master has borderless art — clipping to the interior shape
            // leaves that border showing. Cover the WHOLE balloon with a rectangle over
            // the flood bounds + a margin past the border. master==empty outside the
            // balloon, so the generous rect is invisible everywhere but the effect.
            let m: CGFloat = 0.025
            let bx = mask.bounds
            master
                .mask(
                    Color.clear
                        .frame(width: rect.width, height: rect.height)
                        .overlay(
                            Rectangle()
                                .frame(width: (bx.width + 2 * m) * rect.width, height: (bx.height + 2 * m) * rect.height)
                                .position(x: bx.midX * rect.width, y: bx.midY * rect.height)
                        )
                )
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        } else if let mask {
            master
                .mask(
                    Image(uiImage: mask.image)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: mask.region.width * rect.width, height: mask.region.height * rect.height)
                        .position(x: mask.region.midX * rect.width, y: mask.region.midY * rect.height)
                )
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        } else {
            master
                .mask(
                    Color.clear
                        .frame(width: rect.width, height: rect.height)
                        .overlay(
                            Rectangle()
                                .frame(width: b.width * 1.25 * rect.width, height: b.height * 1.25 * rect.height)
                                .position(x: (b.positionX + b.width / 2) * rect.width,
                                          y: (b.positionY + b.height / 2) * rect.height)
                        )
                )
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }

    // Highlights the open bubble, linking it to the popup. Fills the bubble's
    // interior with a solid, slightly-brighter green (flood-filled to match its
    // real shape). Shows nothing when it can't fill cleanly (e.g. a borderless
    // narration such as a title or "continuará"). Static — no flashing.
    @ViewBuilder
    private func selectedBubbleDot(_ b: Bubble, in rect: CGRect) -> some View {
        // Per-comic colour (set in the generator); falls back to #61F527 green.
        let dotColor = Color.fromHex(comic.bubbleDotColor, fallback: Color(red: 0x61/255, green: 0xF5/255, blue: 0x27/255))
        // Shape from the blank bake (clean interior, reaches everywhere incl.
        // letter-counters); text/ink from whatever image is on screen so glyphs
        // stay readable. In blank practice mode both are the empty bake, so the
        // whole interior fills.
        let maskSource = currentPage.emptyBubblesImage ?? currentPage.noTextImage ?? currentPage.masterImage
        // Preserve the baked text (transparent glyphs) ONLY when this exact bubble is
        // revealed — then the revealedBubbleOverlay sits behind it showing real black
        // text. Otherwise fill the whole interior solid (blank practice bubble); using
        // the with-text image here would punch text-shaped holes onto the blank balloon
        // and read as "white text". In normal reading (not practice) always preserve.
        let inkSource = (isPracticeMode && revealedBubbleId != b.id)
            ? (currentPage.emptyBubblesImage ?? currentPage.noTextImage ?? currentPage.masterImage)
            : currentPage.masterImage
        let nb = CGRect(x: b.positionX, y: b.positionY, width: b.width, height: b.height)
        // Geometry is part of the key: the flood fill is driven by nb, so a moved or
        // resized bubble MUST invalidate the cached overlay (otherwise it returns the
        // stale fill from the old position — showing the wrong shape / a neighbour's text).
        let geo = "\(Int(b.positionX*1e4))_\(Int(b.positionY*1e4))_\(Int(b.width*1e4))_\(Int(b.height*1e4))"
        let key = "\(comic.id)|p\(currentPage.pageNumber)|\(b.id)|\(geo)|\(maskSource)|\(inkSource)|\(comic.bubbleDotColor ?? "def")"
        // Transparent/borderless narration (e.g. "continuará") has no balloon interior
        // to fill — flood-filling it would tint the text and a stray patch of art green.
        // Skip the highlight entirely for these.
        let fill = (b.bgTransparent == true) ? nil
            : BubbleFill.overlay(maskSource: maskSource, inkSource: inkSource, comicId: comic.id,
                                 bubble: nb, color: UIColor(dotColor), cacheKey: key)

        if let fill {
            // Solid green over the white interior — partial opacity so the white
            // beneath keeps it a bright green rather than a flat dark one.
            Image(uiImage: fill.image)
                .resizable()
                .frame(width: fill.region.width * rect.width, height: fill.region.height * rect.height)
                .position(x: rect.minX + fill.region.midX * rect.width,
                          y: rect.minY + fill.region.midY * rect.height)
                .opacity(0.65)
                .allowsHitTesting(false)
                // Appear instantly on touch — don't inherit the card's fade-in.
                .transition(.identity)
                .animation(nil, value: selectedBubbleIndex)
        }
        // No fill possible (e.g. borderless narration like a title or
        // "continuará") → show nothing at all.
    }

    private func loadPageAspect() {
        let name = currentPage.masterImage
        let comicId = comic.id
        Task.detached {
            let size = ComicImageLoader.shared.loadImage(named: name, forComic: comicId)?.size
            if let size, size.height > 0 {
                let aspect = size.width / size.height
                await MainActor.run { pageImageAspect = aspect }
            }
        }
    }

    private func goToNextPage() {
        guard currentPageIndex < sortedPages.count - 1 else {
            if guidedOnScreenPractice {
                handleGuidedEnd()
            } else {
                showEndOfEpisode = true
            }
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        navForward = true                       // PagedImageView slides the artwork
        currentPageIndex += 1
        textRevealed = false
    }

    // MARK: - Guided "On Screen" practice (speaking → listening)

    /// Reached the end of the comic during a guided run. After speaking practice,
    /// offer to start listening practice; after listening, thyarn
    /// KeSo LoI'We need Wi@e run is complete.
    private func handleGuidedEnd() {
        if settingsManager.speakingPracticeMode {
            showSpeakingDonePrompt = true
        } else {
            showOnScreenComplete = true
        }
    }

    private func startListeningPhase() {
        settingsManager.speakingPracticeMode = false
        settingsManager.listeningPracticeMode = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation {
            currentPageIndex = 0
            textRevealed = false
        }
    }

    private func finishGuidedPractice() {
        settingsManager.speakingPracticeMode = false
        settingsManager.listeningPracticeMode = false
        dismiss()
    }

    // End-of-episode prompt: nudges toward practice, but with an ✕ (and tap-outside)
    // to dismiss and stay on the last page. Kept out of `body` to keep it compiling.
    @ViewBuilder
    private var endOfEpisodeOverlay: some View {
        if showEndOfEpisode {
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { showEndOfEpisode = false } }

                VStack(spacing: 16) {
                    Text("End of Episode")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                    Text("You've reached the end. Ready to practice?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        showEndOfEpisode = false
                        onRequestPractice?()
                        dismiss()
                    } label: {
                        Text("Practice")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(red: 91/255, green: 91/255, blue: 214/255),
                                        in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                }
                .padding(20)
                .frame(maxWidth: 300)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation { showEndOfEpisode = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .padding(10)
                    }
                    .accessibilityLabel("Close")
                }
                .shadow(radius: 20)
                .padding(.horizontal, 40)
            }
            .transition(.opacity)
            .zIndex(3)
        }
    }

    private func goToPreviousPage() {
        guard currentPageIndex > 0 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        navForward = false                      // PagedImageView slides the artwork
        currentPageIndex -= 1
        textRevealed = false
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                // Page image. In practice modes show the empty-bubbles art (bubbles
                // visible, text blank) so they're tappable; fall back to the no-text
                // art, then the full page, for comics baked before that existed.
                // Practice always shows the blank-bubble bake; tapping Reveal overlays
                // ONLY the current bubble's text (revealedBubbleOverlay), so the rest
                // stay blank.
                let imageName = isPracticeMode
                    ? (currentPage.emptyBubblesImage ?? currentPage.noTextImage ?? currentPage.masterImage)
                    : currentPage.masterImage

                PagedImageView(imageName: imageName, comicId: comic.id,
                               pageKey: currentPageIndex, forward: navForward)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .overlay {
                        // Tap targets, mapped into the actual aspect-fit image rect
                        // (so they line up with the artwork, not the letterbox bars).
                        GeometryReader { imageGeometry in
                            let rect = fittedImageRect(in: imageGeometry.size)
                            ZStack {
                                // Practice: keep sound-effect / image bubbles baked
                                // (they aren't practised), then reveal only the open
                                // bubble's text on top.
                                soundEffectOverlay(in: rect)
                                revealedBubbleOverlay(in: rect)

                                // One tap target per text bubble. Opens the floating
                                // card — the same interaction for normal reading and
                                // for practice (the card shows practice controls when
                                // a practice mode is on).
                                ForEach(Array(pageTextBubbles.enumerated()), id: \.element.id) { i, b in
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .frame(width: b.width * rect.width + 16,
                                               height: b.height * rect.height + 16)
                                        // Anchor the "Click on the text." cover callout to the title
                                        // bubble — BEFORE .position (a positioned view fills its parent,
                                        // which would make the anchor capture the whole page instead).
                                        .calloutAnchorIf(currentPageIndex == 0 && i == 0, "cover.text")
                                        // ...and "Click on a bubble." to the first bubble on story pages.
                                        .calloutAnchorIf(currentPageIndex > 0 && i == 0, "page.bubble")
                                        .position(x: rect.minX + (b.positionX + b.width / 2) * rect.width,
                                                  y: rect.minY + (b.positionY + b.height / 2) * rect.height)
                                        .onTapGesture {
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            selectedBubbleIndex = i
                                        }
                                }

                                // Slow-flashing dot in the open bubble, linking it to
                                // the popup (bubbles are baked into the art).
                                if let sel = selectedBubbleIndex, pageTextBubbles.indices.contains(sel) {
                                    selectedBubbleDot(pageTextBubbles[sel], in: rect)
                                }

                                // Traced hotspots: the artwork inside the shape
                                // lifts/floats toward the reader as it pulses.
                                ForEach(currentPage.hotspots ?? [], id: \.id) { h in
                                    hotspotFloatingCutout(h, in: rect)
                                }

                                // Hotspots: pulsing tap markers mapped into the same
                                // fitted image rect (restored for full-page reading).
                                ForEach(currentPage.hotspots ?? [], id: \.id) { h in
                                    hotspotIndicator(h, in: rect)
                                }

                            }
                        }
                    }
                .gesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            let horizontalDistance = value.translation.width
                            if horizontalDistance > 50 {
                                // Swiped right → previous page
                                goToPreviousPage()
                            } else if horizontalDistance < -50 {
                                // Swiped left → next page
                                goToNextPage()
                            }
                        }
                )
            }

            // Help hints over the page (help mode only, while nothing is open)
            if selectedPanel == nil && selectedBubbleIndex == nil {
                VStack(spacing: 10) {
                    Spacer()
                    HelpHint(icon: "hand.tap.fill", label: "Tap a bubble or text",
                             title: "Open a speech bubble",
                             text: "Tap any speech or narration bubble to open its text, translation, grammar and audio — the page stays visible above.")
                    HelpHint(icon: "arrow.left.and.right", label: "Swipe",
                             title: "Turn the page",
                             text: "Swipe left or right anywhere on the page — or use the arrows at the top — to move between pages.",
                             animatedSwipe: true)
                }
                // Clear the bottom "Help is on" banner so the hints aren't hidden behind it.
                .padding(.bottom, 130)
            }

            // Panel view overlay — presented on top of the page instead of as a sheet
            // to avoid iOS sheet presentation scaling the underlying page view
            if let panel = selectedPanel {
                PanelView(
                    comic: comic,
                    page: currentPage,
                    panel: panel,
                    hotspots: currentPage.hotspots ?? [],
                    navigateToPage: $navigateToPage,
                    dismissPanel: {
                        // Remove the overlay without animation — an interrupted
                        // removal transition can leave the page layout stuck
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            selectedPanel = nil
                        }
                    },
                    dismissToHome: {
                        dismiss()
                    },
                    guidedOnScreenPractice: guidedOnScreenPractice,
                    onGuidedEnd: { handleGuidedEnd() }
                )
                .environmentObject(settingsManager)
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }

            // Floating, draggable card showing one bubble's content (normal reading).
            // Lives over the page so the artwork stays visible; swipe it (or tap the
            // side arrows) to step bubbles and turn pages.
            if let idx = selectedBubbleIndex, pageTextBubbles.indices.contains(idx) {
                FloatingBubbleCard(
                    comic: comic,
                    bubbles: pageTextBubbles,
                    panels: currentPage.panels,
                    index: Binding(
                        get: { selectedBubbleIndex ?? 0 },
                        set: { selectedBubbleIndex = $0; revealedBubbleId = nil }   // stepping bubbles re-hides
                    ),
                    revealedBubbleId: $revealedBubbleId,
                    onClose: { selectedBubbleIndex = nil; revealedBubbleId = nil },
                    // Past the last/first bubble, step to the next/previous page. The
                    // page change closes the card (onChange of currentPageIndex clears
                    // the selection) until the reader taps a bubble on the new page.
                    onRequestNextPage: { goToNextPage() },
                    onRequestPrevPage: { goToPreviousPage() },
                    onWordTipDismissed: { maybeShowSwipeTip() }
                )
                .environmentObject(settingsManager)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(2)
                // No first-run auto-help here — the bordered highlights + "Swipe"/
                // "Tap" chips are shown only on demand via the "?" button now.
                // Onboarding is handled by the amber callouts instead.
            }

            endOfEpisodeOverlay
        }
        .sheet(item: $selectedHotspot) { hotspot in
            HotspotView(hotspot: hotspot, comicId: comic.id)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Only show the page controls while the panel overlay is closed —
            // the panel's own toolbar items (home/Done/panel nav) render into
            // the same bar, so showing both sets duplicates the buttons
            if selectedPanel == nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        if presentedModally {
                            Text("Done")
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: "house.fill")
                                .foregroundStyle(.white)
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 14) {
                        Button {
                            goToPreviousPage()
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundStyle(currentPageIndex > 0 ? .white : .gray)
                        }
                        .disabled(currentPageIndex == 0)

                        Text("\(currentPage.pageNumber)/\(sortedPages.count)")
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()   // never truncate to "9/..."

                        Button {
                            goToNextPage()
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(currentPageIndex < sortedPages.count - 1 ? .white : .gray)
                        }
                        .disabled(currentPageIndex >= sortedPages.count - 1)
                    }
                    .fixedSize()   // size the whole indicator to its content
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { help.toggle() }
                        } label: {
                            Image(systemName: help.isActive ? "questionmark.circle.fill" : "questionmark.circle")
                                .foregroundStyle(.white)
                        }
                        Button {
                            showingVocabulary = true
                        } label: {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(.white)
                        }
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gear")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .helpTooltipLayer(bannerEdge: helpBannerEdge)
        .environmentObject(help)
        .anchoredCallout(
            targetID: "cover.text",
            text: "Click on the text.",
            icon: "hand.tap.fill",
            isPresented: showCoverTip && selectedBubbleIndex == nil && selectedPanel == nil
        ) { dismissCoverTip() }
        .anchoredCallout(
            targetID: "page.bubble",
            text: "Click on a bubble.",
            icon: "hand.tap.fill",
            isPresented: showBubbleTip && selectedBubbleIndex == nil && selectedPanel == nil
        ) { dismissBubbleTip() }
        // Swipe-to-turn hint, chained after the word-popup guidance closes. Floats
        // opposite the open card (or at the top once the card is closed).
        .overlay(alignment: openCardAnchorTop ? .bottom : .top) {
            if showSwipeTip {
                HelpIntroCallout(
                    text: "To move to the next page swipe to the left.",
                    icon: "hand.draw.fill",
                    showArrow: false
                ) { dismissSwipeTip() }
                .padding(openCardAnchorTop ? .bottom : .top, openCardAnchorTop ? 60 : 8)
                .transition(.opacity.combined(with: .move(edge: openCardAnchorTop ? .bottom : .top)))
                .zIndex(60)
            }
        }
        .onChange(of: help.isActive) { _, active in
            // "?" replays the page-level sequence (cover text / bubble → swipe).
            // With a bubble card or panel open, the card runs its own sequence.
            if active {
                guard selectedBubbleIndex == nil, selectedPanel == nil else { return }
                helpReplay = true
                withAnimation { showSwipeTip = false }
                if currentPageIndex == 0 {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showCoverTip = true }
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showBubbleTip = true }
                }
            } else {
                helpReplay = false
                withAnimation {
                    showCoverTip = false
                    showSwipeTip = false
                    showBubbleTip = false
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
        .onAppear {
            AudioManager.shared.activeComicId = comic.id   // fast, direct audio lookup
            loadPageAspect()
            maybeShowCoverTip()
            // Guided run starts in speaking practice (safety net if not already set).
            if guidedOnScreenPractice && !settingsManager.speakingPracticeMode && !settingsManager.listeningPracticeMode {
                settingsManager.speakingPracticeMode = true
            }
            // Open a specific bubble's card (e.g. from a Vocabulary word's context).
            if let initialBubbleId, let idx = pageTextBubbles.firstIndex(where: { $0.id == initialBubbleId }) {
                selectedBubbleIndex = idx
            }
            // Save progress when view appears (skipped for transient context views).
            if savesProgress {
                progressManager.saveProgress(
                    comicId: comic.id,
                    pageNumber: currentPage.pageNumber,
                    panelNumber: 0,
                    asPractice: guidedOnScreenPractice
                )
            }
        }
        .onDisappear {
            // Leaving a guided run (finished or backed out) returns the comic to
            // normal reading — don't leave a practice mode stuck on.
            if guidedOnScreenPractice {
                settingsManager.speakingPracticeMode = false
                settingsManager.listeningPracticeMode = false
            }
        }
        .onChange(of: currentPageIndex) { oldPage, newPage in
            // Close the bubble card and refresh the artwork aspect for the new page
            selectedBubbleIndex = nil
            loadPageAspect()
            // Leaving the cover hides the cover callout; returning to it re-offers it.
            if currentPageIndex == 0 { maybeShowCoverTip() }
            else if showCoverTip { withAnimation { showCoverTip = false } }
            // They turned the page — the swipe hint's action is done; next up,
            // prompt them to open a bubble, but ONLY on the first swipe from the
            // cover to the first story page.
            if showSwipeTip { dismissSwipeTip() }
            if oldPage == 0 && newPage == 1 { maybeShowBubbleTip() }
            // Save progress when page changes (skipped for transient context views).
            if savesProgress {
                progressManager.saveProgress(
                    comicId: comic.id,
                    pageNumber: currentPage.pageNumber,
                    panelNumber: 0,
                    asPractice: guidedOnScreenPractice
                )
            }
        }
        .onChange(of: selectedBubbleIndex) { _, newValue in
            // Changing which bubble is open (stepping with the card arrows, tapping a
            // different bubble, or closing) always re-hides the revealed text — the
            // reveal only ever applies to the bubble you're currently on. Single
            // source of truth so a stale reveal can't linger on the bubble you left.
            revealedBubbleId = nil
            // Opening any bubble means they got the hint — retire the tap callouts.
            // The bubble tip is only marked seen if it was actually on screen;
            // otherwise a cover-bubble tap would silently burn it before its turn.
            if newValue != nil {
                dismissCoverTip()
                if showBubbleTip { dismissBubbleTip() }
            }
            // Remember the open bubble during on-screen practice so "Continue
            // practicing" reopens the same page at the same bubble.
            if guidedOnScreenPractice, let idx = newValue, pageTextBubbles.indices.contains(idx) {
                progressManager.savePracticeBubble(comicId: comic.id, bubbleId: pageTextBubbles[idx].id)
            }
        }
        .onChange(of: navigateToPage) { _, newPageIndex in
            guard let newPageIndex = newPageIndex else { return }
            // Cross-page navigation from the panel view: close the overlay and
            // swap the page in a single transaction with animations disabled.
            // Running the overlay's removal transition and the page change as
            // concurrent animations can wedge the layout mid-flight, leaving
            // the page rendered small and unresponsive.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedPanel = nil
                currentPageIndex = newPageIndex
                textRevealed = false
            }
            navigateToPage = nil
        }
        .sheet(isPresented: $showingVocabulary) {
            NavigationStack {
                VocabularyView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                showingVocabulary = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .environmentObject(settingsManager)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                showingSettings = false
                            }
                        }
                    }
            }
        }
        .alert("Speaking practice complete", isPresented: $showSpeakingDonePrompt) {
            Button("Start listening practice") { startListeningPhase() }
            Button("Finish", role: .cancel) { finishGuidedPractice() }
        } message: {
            Text("Now go through the comic again — listen to each sentence and recall its meaning.")
        }
        .alert("Practice complete", isPresented: $showOnScreenComplete) {
            Button("Done") { finishGuidedPractice() }
        } message: {
            Text("You've finished speaking and listening practice for this comic. ¡Bien hecho!")
        }
        .background(DisableInteractivePopGesture())
    }
}

// Disables the enclosing UINavigationController's interactive pop (edge swipe-back)
// gesture while this view is on screen, restoring it when the view goes away.
// A rightward swipe (e.g. "previous panel/page") can otherwise be captured by the
// swipe-back recognizer, starting an interactive pop that gets cancelled mid-flight
// and leaves the view stuck small and unresponsive.
struct DisableInteractivePopGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController {
        private weak var navController: UINavigationController?
        private var previousState = true

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // Walk the responder chain to find the enclosing navigation controller
            var responder: UIResponder? = view
            while let current = responder {
                if let nav = current as? UINavigationController {
                    navController = nav
                    break
                }
                if let vc = current as? UIViewController, let nav = vc.navigationController {
                    navController = nav
                    break
                }
                responder = current.next
            }
            if let gesture = navController?.interactivePopGestureRecognizer {
                previousState = gesture.isEnabled
                gesture.isEnabled = false
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navController?.interactivePopGestureRecognizer?.isEnabled = previousState
        }
    }
}

// MARK: - Per-bubble content + sheet (on-page reading, one bubble at a time)

private struct BubblePracticeFeedback {
    let sentenceId: String
    let isCorrect: Bool
    let spokenText: String
    let expectedText: String
    let words: [Word]
    var noSpeech: Bool = false   // nothing was heard — not a wrong answer
}

/// A single bubble's content for the floating card. Handles normal reading
/// (tappable words, translation, grammar, audio) AND practice modes (speaking:
/// say the Spanish from the English prompt; listening: recall the meaning) — so
/// the floating card is the single surface for both, mirroring PanelView's bubble
/// card. (If kept, the cleanup is to have PanelView reuse this.)
struct BubbleContentView: View {
    let comic: Comic
    let bubble: Bubble
    @Binding var revealedBubbleId: String?   // shared with the page so revealed text also shows in the bubble
    var onWordTap: (() -> Void)? = nil       // notified when any word is tapped (clears the "Click on a word." tip)
    @EnvironmentObject var settingsManager: SettingsManager
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var whisperService = WhisperService.shared

    @State private var translationRevealed: Set<String> = []
    @State private var grammarRevealed: Set<String> = []
    private var textRevealed: Bool { revealedBubbleId == bubble.id }
    @State private var playingSentenceId: String?
    @State private var highlightedWordIndex: Int?
    @State private var recordingSentenceId: String?
    @State private var processingSentenceId: String?
    @State private var practiceFeedback: BubblePracticeFeedback?
    @State private var practiceSentence: Sentence?
    @State private var showingError = false
    @State private var errorMessage = ""

    private var isPracticeMode: Bool {
        settingsManager.speakingPracticeMode || settingsManager.listeningPracticeMode
    }

    private var playingSentence: Sentence? {
        guard let id = playingSentenceId else { return nil }
        return bubble.sentences.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let fb = practiceFeedback {
                // Test mode: the result REPLACES the popup content (stays compact)
                // rather than being appended below it, which grew the card tall and
                // made it scroll.
                feedbackCard(fb)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(bubble.sentences) { sentence in
                        VStack(alignment: .leading, spacing: 8) {
                            mainText(sentence)
                            if !isPracticeMode {
                                translationRow(sentence)
                                grammarRow(sentence)
                            }
                            audioRow(sentence)
                            revealedContent(sentence)
                            if sentence.id != bubble.sentences.last?.id { Divider() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: audioManager.currentTime) { _, _ in
            if audioManager.isSentencePlayback, let s = playingSentence {
                highlightedWordIndex = audioManager.currentWordIndex(for: s.words)
            }
        }
        .onChange(of: audioManager.isPlaying) { _, isPlaying in
            if !isPlaying { highlightedWordIndex = nil; playingSentenceId = nil }
        }
        .onChange(of: settingsManager.playbackSpeed) { _, s in
            audioManager.setPlaybackRate(Float(s))
        }
        .onChange(of: whisperService.error) { _, newError in
            if let error = newError, whisperService.transcribedText.isEmpty {
                recordingSentenceId = nil
                processingSentenceId = nil
                errorMessage = error
                showingError = true
                whisperService.error = nil
            }
        }
        .onAppear {
            audioManager.activeComicId = comic.id   // fast, direct audio lookup
            audioManager.setPlaybackRate(Float(settingsManager.playbackSpeed))
            // In listening mode, auto-play the first sentence so the learner has
            // something to recall the meaning of.
            if settingsManager.listeningPracticeMode,
               let first = bubble.sentences.first, let url = first.audioUrl, !url.isEmpty {
                playingSentenceId = first.id
                audioManager.play(url, enableHighlighting: true)
            }
        }
        .onDisappear {
            // Audio stop is handled by the card's close + the nav arrows. Doing it
            // here too would fire late while stepping bubbles and kill the freshly
            // started play (green flash → cut out). So only cancel recording here.
            whisperService.cancelRecording()
        }
        .alert("Speech Recognition Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: { Text(errorMessage) }
    }

    // MARK: Main line (prompt differs per mode)

    @ViewBuilder
    private func mainText(_ sentence: Sentence) -> some View {
        if settingsManager.speakingPracticeMode {
            Text(sentence.translation ?? "")
                .font(.title3).fontWeight(.medium)
        } else if settingsManager.listeningPracticeMode {
            Text("What is the English meaning?")
                .font(.subheadline).foregroundStyle(.secondary).italic()
        } else {
            wordsLine(sentence, highlight: true)
        }
    }

    @ViewBuilder
    private func wordsLine(_ sentence: Sentence, highlight: Bool) -> some View {
        let displayWords = sentence.words.filter { word in
            if word.manual == true { return false }
            if word.startTimeMs == nil && word.text.contains(" ") { return false }
            return true
        }
        // Use the SAME font as the practice prompt (.title3 medium) regardless of the
        // comic's small baked bubble font size, so reading mode reads just as large
        // and clear, and both scale together with Dynamic Type.
        if displayWords.isEmpty {
            Text(sentence.text).font(.title3).fontWeight(.medium)
        } else {
            FlowLayout(spacing: 2) {
                ForEach(displayWords) { word in
                    let originalIndex = sentence.words.firstIndex(where: { $0.id == word.id })
                    WordButton(
                        word: word,
                        isHighlighted: highlight && playingSentenceId == sentence.id && highlightedWordIndex == originalIndex,
                        font: .title3,
                        weight: .medium,
                        sentenceText: sentence.text,
                        sentenceTranslation: sentence.translation,
                        onTap: onWordTap
                    )
                    .explains("Tap a word",
                              "Tap any word to see its meaning and base form, hear it spoken, and save it to your vocabulary.",
                              id: "bubbleword.\(word.id)")
                }
            }
        }
    }

    // MARK: Normal-mode rows

    @ViewBuilder
    private func translationRow(_ sentence: Sentence) -> some View {
        if let translation = sentence.translation,
           let audioUrl = sentence.audioUrl, !audioUrl.isEmpty {
            if translationRevealed.contains(sentence.id) {
                Text(translation).font(.subheadline).foregroundStyle(.secondary)
            } else {
                Button {
                    withAnimation { translationRevealed.insert(sentence.id) }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Show translation", systemImage: "eye").font(.subheadline).foregroundStyle(.blue)
                }
            }
        }
    }

    @ViewBuilder
    private func grammarRow(_ sentence: Sentence) -> some View {
        if let note = sentence.grammarNote, !note.isEmpty {
            if grammarRevealed.contains(sentence.id) {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .padding(.trailing, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            withAnimation { grammarRevealed.remove(sentence.id) }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.purple.opacity(0.6))
                                .padding(6)
                        }
                        .accessibilityLabel("Close grammar note")
                    }
            } else {
                Button {
                    withAnimation { grammarRevealed.insert(sentence.id) }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Explain grammar", systemImage: "text.book.closed").font(.subheadline).foregroundStyle(.purple)
                }
            }
        }
    }

    // MARK: Audio / practice controls

    @ViewBuilder
    private func audioRow(_ sentence: Sentence) -> some View {
        if let audioUrl = sentence.audioUrl, !audioUrl.isEmpty {
            HStack(spacing: 10) {
                if settingsManager.speakingPracticeMode {
                    micButton(sentence, listening: false)
                    listenButton(sentence)
                } else if settingsManager.listeningPracticeMode {
                    micButton(sentence, listening: true)
                    listenButton(sentence)
                } else {
                    playButton(sentence, audioUrl: audioUrl)
                }
                speedMenu   // sits right next to the listen/play control
                Spacer()
            }
        }
    }

    private var speedMenu: some View {
        Menu {
            Button("0.5x") { settingsManager.playbackSpeed = 0.5 }
            Button("0.75x") { settingsManager.playbackSpeed = 0.75 }
            Button("1x") { settingsManager.playbackSpeed = 1.0 }
            Button("1.25x") { settingsManager.playbackSpeed = 1.25 }
        } label: {
            Text("\(settingsManager.playbackSpeed, specifier: "%.2g")x")
                .font(.caption).fontWeight(.medium)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(.systemGray5)).clipShape(Capsule())
        }
        .explains("Playback speed", "Tap to slow the audio down or speed it up (0.5×–1.25×).", id: "bubble.speed")
    }

    private func playButton(_ sentence: Sentence, audioUrl: String) -> some View {
        Button {
            if audioManager.isPlaying && playingSentenceId == sentence.id {
                audioManager.stop()
            } else {
                playingSentenceId = sentence.id
                audioManager.play(audioUrl, enableHighlighting: true)
            }
        } label: {
            let isThis = audioManager.isPlaying && playingSentenceId == sentence.id
            Label(isThis ? "Stop" : "Play", systemImage: isThis ? "stop.fill" : "play.fill")
                .font(.subheadline).fontWeight(.medium).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(isThis ? Color.red : Color.blue)
                .clipShape(Capsule())
        }
        .explains("Play", "Play the sentence aloud — the words highlight as they're spoken.", id: "bubble.play")
    }

    private func micButton(_ sentence: Sentence, listening: Bool) -> some View {
        let isThisRecording = recordingSentenceId == sentence.id
        return Button {
            if isThisRecording {
                if listening { stopListeningRecording(for: sentence) } else { stopRecording(for: sentence) }
            } else {
                startRecording(for: sentence)
            }
        } label: {
            let isProcessingThis = processingSentenceId == sentence.id
            Label(isThisRecording ? "Stop" : "Speak", systemImage: isThisRecording ? "stop.fill" : "mic.fill")
                .font(.subheadline).fontWeight(.medium).foregroundStyle(.white)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                // While the recording is being checked, hide the label (keeping its
                // size so the button doesn't reflow) and show a spinner over it —
                // this used to be an inline spinner that squashed the Speak button.
                .opacity(isProcessingThis ? 0 : 1)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(isThisRecording ? Color.red : Color.blue)
                .clipShape(Capsule())
                .overlay { if isProcessingThis { ProgressView().tint(.white) } }
        }
        .explains("Speak", "Record yourself saying the line, then get pronunciation feedback.", id: "bubble.speak")
        .disabled(processingSentenceId != nil || (recordingSentenceId != nil && !isThisRecording))
    }

    private func listenButton(_ sentence: Sentence) -> some View {
        let isThis = audioManager.isPlaying && playingSentenceId == sentence.id
        return Button {
            if isThis {
                audioManager.stop()
            } else {
                playingSentenceId = sentence.id
                playAudio(sentence.audioUrl)
            }
        } label: {
            Image(systemName: isThis ? "stop.fill" : "speaker.wave.2.fill")
                .frame(width: 40, height: 40)
                .background(isThis ? Color.red : Color.green)
                .clipShape(Circle())
                .foregroundStyle(.white)
        }
        .explains("Listen", "Hear the sentence spoken in Spanish.", id: "bubble.listen")
        .disabled(recordingSentenceId == sentence.id || processingSentenceId != nil)
    }

    // MARK: Revealed text (practice modes)

    @ViewBuilder
    private func revealedContent(_ sentence: Sentence) -> some View {
        if isPracticeMode {
            if textRevealed {
                if settingsManager.listeningPracticeMode, let translation = sentence.translation {
                    Text(translation).font(.subheadline).foregroundStyle(.secondary).italic()
                }
                wordsLine(sentence, highlight: false)
                Button {
                    withAnimation { revealedBubbleId = nil }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Hide", systemImage: "eye.slash").font(.subheadline).foregroundStyle(.blue)
                }
                .explains("Hide", "Hide the text again for this bubble.", id: "bubble.reveal")
            } else {
                Button {
                    withAnimation { revealedBubbleId = bubble.id }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Reveal", systemImage: "eye").font(.subheadline).foregroundStyle(.blue)
                }
                .explains("Reveal", "Show this bubble's text on the page when you're stuck. Only this bubble is revealed.", id: "bubble.reveal")
            }
        }
    }

    // MARK: Feedback

    private func feedbackCard(_ feedback: BubblePracticeFeedback) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if feedback.noSpeech {
                    Image(systemName: "mic.slash.fill").foregroundStyle(.orange)
                    Text("I didn't hear anything").fontWeight(.semibold)
                } else {
                    Image(systemName: feedback.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(feedback.isCorrect ? .green : .red)
                    Text(feedback.isCorrect ? "Correct!" : "Not quite").fontWeight(.semibold)
                }
            }
            .font(.headline)

            if feedback.noSpeech {
                Text("Tap Speak and say the line again.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                if !feedback.isCorrect {
                    Text("You said: \"\(feedback.spokenText)\"").font(.subheadline)
                }
                Text(settingsManager.listeningPracticeMode ? "Meaning: \(feedback.expectedText)" : "Expected: \(feedback.expectedText)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            HStack {
                Button { playAudio(practiceSentence?.audioUrl) } label: {
                    Label("Listen", systemImage: "speaker.wave.2.fill").font(.subheadline)
                }
                .buttonStyle(.bordered)
                Button { practiceFeedback = nil } label: {
                    Label("Try Again", systemImage: "arrow.counterclockwise").font(.subheadline)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((feedback.noSpeech ? Color.orange : (feedback.isCorrect ? Color.green : Color.red)).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Actions

    private func playAudio(_ url: String?) {
        guard let url else { return }
        audioManager.play(url, enableHighlighting: true)
    }

    private func startRecording(for sentence: Sentence) {
        practiceSentence = sentence
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await whisperService.startRecording()
            if whisperService.isRecording { recordingSentenceId = sentence.id }
        }
    }

    private func stopRecording(for sentence: Sentence) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        recordingSentenceId = nil
        processingSentenceId = sentence.id
        Task {
            let expectedText = sentence.text
            let spokenText = await whisperService.stopRecording(expectedText: expectedText)
            if let error = whisperService.error, spokenText.isEmpty {
                processingSentenceId = nil
                errorMessage = error; showingError = true; whisperService.error = nil
                return
            }
            whisperService.error = nil
            if spokenText.isEmpty {
                try? await Task.sleep(nanoseconds: 200_000_000)
                processingSentenceId = nil
                practiceFeedback = BubblePracticeFeedback(
                    sentenceId: sentence.id, isCorrect: false, spokenText: "",
                    expectedText: expectedText, words: sentence.words, noSpeech: true)
                return
            }
            let (isCorrect, _) = whisperService.compareText(spoken: spokenText, expected: expectedText)
            try? await Task.sleep(nanoseconds: 300_000_000)
            processingSentenceId = nil
            practiceFeedback = BubblePracticeFeedback(
                sentenceId: sentence.id, isCorrect: isCorrect,
                spokenText: spokenText,
                expectedText: expectedText, words: sentence.words)
            playingSentenceId = sentence.id
            playAudio(sentence.audioUrl)
        }
    }

    private func stopListeningRecording(for sentence: Sentence) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        recordingSentenceId = nil
        processingSentenceId = sentence.id
        Task {
            let expected = sentence.translation ?? ""
            let spokenText = await whisperService.stopRecording(expectedText: expected, language: "en")
            if let error = whisperService.error, spokenText.isEmpty {
                processingSentenceId = nil
                errorMessage = error; showingError = true; whisperService.error = nil
                return
            }
            whisperService.error = nil
            if spokenText.isEmpty {
                try? await Task.sleep(nanoseconds: 200_000_000)
                processingSentenceId = nil
                practiceFeedback = BubblePracticeFeedback(
                    sentenceId: sentence.id, isCorrect: false, spokenText: "",
                    expectedText: expected, words: sentence.words, noSpeech: true)
                return
            }
            let isCorrect = compareEnglishMeaning(spoken: spokenText, expected: expected)
            try? await Task.sleep(nanoseconds: 300_000_000)
            processingSentenceId = nil
            practiceFeedback = BubblePracticeFeedback(
                sentenceId: sentence.id, isCorrect: isCorrect,
                spokenText: spokenText,
                expectedText: expected, words: sentence.words)
            playingSentenceId = sentence.id
            playAudio(sentence.audioUrl)
        }
    }

    private func compareEnglishMeaning(spoken: String, expected: String) -> Bool {
        let s = normalizeEnglish(spoken), e = normalizeEnglish(expected)
        if s.isEmpty { return false }
        if s == e || s.contains(e) || e.contains(s) { return true }
        let (isMatch, score) = whisperService.compareText(spoken: s, expected: e)
        return isMatch || score >= 0.7
    }

    private func normalizeEnglish(_ text: String) -> String {
        var result = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "?", with: "")
        for prefix in ["the ", "a ", "an "] where result.hasPrefix(prefix) {
            result = String(result.dropFirst(prefix.count))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A floating, draggable card showing one bubble's content at a time, with a
/// stepper to move through the page's bubbles. Drag the header to reposition it
/// anywhere over the page; sits near the bottom by default so the artwork above
/// stays visible.
struct FloatingBubbleCard: View {
    let comic: Comic
    let bubbles: [Bubble]
    let panels: [Panel]
    @Binding var index: Int
    @Binding var revealedBubbleId: String?
    var onClose: () -> Void
    var onRequestNextPage: () -> Void = {}
    var onRequestPrevPage: () -> Void = {}
    /// Notified when the word-popup guidance is dismissed — the page uses it to
    /// chain the next onboarding hint (swipe to turn the page).
    var onWordTipDismissed: () -> Void = {}
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var help: HelpModeController

    @State private var contentHeight: CGFloat = 0

    // First-open callout: a panel overview that ends by prompting a word tap.
    @AppStorage("help.seen.bubble-panel") private var seenPanelTip = false
    @State private var showPanelTip = false
    // After the first word tap: what the word popup offers. Floats on the screen
    // edge opposite the card, clear of the system popover.
    @AppStorage("help.seen.word-detail") private var seenWordDetailTip = false
    @State private var showWordDetailTip = false
    // On the next panel open (after the "Click on a bubble." step): the arrows.
    @AppStorage("help.seen.story-bubble") private var seenBubbleTip = false
    @AppStorage("help.seen.story-arrows") private var seenArrowsTip = false
    @State private var showArrowsTip = false
    // Closing chapter: after the arrows tip, point up at the "?" icon.
    @AppStorage("help.seen.help-reminder") private var seenHelpReminderTip = false
    @State private var showHelpReminderTip = false
    // True while "?" is replaying the card's tooltips — bypasses "seen" flags.
    @State private var helpReplay = false

    private let maxContentHeight: CGFloat = 340

    private var isPracticeMode: Bool {
        settingsManager.speakingPracticeMode || settingsManager.listeningPracticeMode
    }

    var body: some View {
        card
            .frame(maxWidth: 380)
            // Anchor the panel-overview callout to the card itself (arrowless, auto-
            // placed on the card's inner edge — opposite the screen edge it hugs).
            .calloutAnchor("bubble.panel")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: anchorTop ? .top : .bottom)
            .padding(.horizontal, 12)
            .padding(.top, anchorTop ? 14 : 0)
            .padding(.bottom, anchorTop ? 0 : 30)
            .anchoredCallout(
                targetID: "bubble.panel",
                text: "Here you can see the translation, listen to the audio and, if you wish, have the grammar explained. Now click on a word.",
                icon: nil,
                showArrow: false,
                isPresented: showPanelTip
            ) { dismissPanelTip() }
            .anchoredCallout(
                targetID: "bubble.panel",
                text: "Once you have finished interacting with this bubble, you can navigate to the next one by using the arrows.",
                icon: nil,
                showArrow: false,
                isPresented: showArrowsTip
            ) { dismissArrowsTip() }
            // Walkthrough closer: an up-arrow callout under the "?" icon, placed
            // exactly like the Library's "?" intro at the start of the flow.
            .overlay(alignment: .topTrailing) {
                if showHelpReminderTip {
                    HelpIntroCallout(
                        text: "Lastly, just a reminder that you can click here at any point if you need a reminder.",
                        arrowInset: 100   // the reader's "?" sits ~129pt in from the trailing edge
                    ) { dismissHelpReminderTip() }
                    .padding(.trailing, 19)
                    .offset(y: 10)   // just below the nav bar, arrow under the "?"
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(60)
                }
            }
            // Word-popup guidance: hosted in its own window ABOVE the system word
            // popover (which draws over any in-view overlay, so a plain .overlay
            // here would be covered by it). Floats opposite the card as before.
            .onChange(of: showWordDetailTip) { _, show in
                if show {
                    let atTop = !anchorTop   // card at the bottom → tip at the top
                    CalloutOverWindow.shared.show(AnyView(
                        VStack(spacing: 0) {
                            if atTop {
                                wordDetailCallout.calloutWindowTappable()
                                Spacer(minLength: 0)
                            } else {
                                Spacer(minLength: 0)
                                wordDetailCallout.calloutWindowTappable()
                            }
                        }
                        .padding(.top, atTop ? 64 : 0)
                        .padding(.bottom, atTop ? 0 : 90)   // clear the tab bar
                        .frame(maxWidth: .infinity)
                    ))
                } else {
                    CalloutOverWindow.shared.hide()
                }
            }
            .onAppear { startCardTips() }
            .onChange(of: help.isActive) { _, active in
                // "?" while the card is open replays its sequence: panel overview →
                // word-popup guidance → arrows. Off dismisses whatever is showing.
                if active {
                    helpReplay = true
                    if showWordDetailTip { showWordDetailTip = false }
                    withAnimation { showArrowsTip = false; showHelpReminderTip = false }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showPanelTip = true }
                } else {
                    helpReplay = false
                    withAnimation { showPanelTip = false; showArrowsTip = false; showHelpReminderTip = false }
                    if showWordDetailTip { showWordDetailTip = false }
                }
            }
            // Stop audio when the whole card closes (not while stepping bubbles —
            // the card persists across steps, only the inner content is rebuilt).
            .onDisappear {
                AudioManager.shared.stop()
                if showWordDetailTip { dismissWordDetailTip() }
                // The card's replay can't continue without the card — end help.
                if helpReplay {
                    helpReplay = false
                    help.isActive = false
                }
            }
    }

    private var wordDetailCallout: some View {
        HelpIntroCallout(
            text: "You can listen and see the meaning of individual words and learn about their different forms (if they have any) by clicking More. If you want to find out more about the word - click on Explain further. You can also add words to your personal vocabulary collection. Now click me to close.",
            icon: "hand.tap.fill",
            maxWidth: 300,
            showArrow: false
        ) { dismissWordDetailTip() }
    }

    private func startCardTips() {
        guard !isPracticeMode else { return }   // the hints are for normal reading
        if HelpDebug.forceShowTooltips || !seenPanelTip {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showPanelTip = true }
            }
        } else if seenBubbleTip, !seenArrowsTip {
            // They've done the first-panel walkthrough and tapped a bubble on a
            // story page — point out the step arrows on this panel.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showArrowsTip = true }
            }
        }
    }

    private func dismissArrowsTip() {
        seenArrowsTip = true
        if showArrowsTip {
            withAnimation(.easeInOut(duration: 0.2)) { showArrowsTip = false }
            // Chain: close the walkthrough by pointing out the "?" icon.
            if HelpDebug.forceShowTooltips || helpReplay || !seenHelpReminderTip {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showHelpReminderTip = true }
                }
            }
        }
    }

    private func dismissHelpReminderTip() {
        seenHelpReminderTip = true
        if showHelpReminderTip {
            withAnimation(.easeInOut(duration: 0.2)) { showHelpReminderTip = false }
            // Very last step — end the "?" replay.
            if helpReplay {
                helpReplay = false
                withAnimation(.easeInOut(duration: 0.2)) { help.isActive = false }
            }
        }
    }

    // Dismissed by tapping it, tapping a word, or opening "?".
    private func dismissPanelTip() {
        seenPanelTip = true
        if showPanelTip {
            withAnimation(.easeInOut(duration: 0.2)) { showPanelTip = false }
            // Replay: the word-popup guidance is next in the card's sequence.
            if helpReplay {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showWordDetailTip = true }
                }
            }
        }
    }

    // A word was tapped: retire the panel tip, then explain the word popup (once).
    private func handleWordTap() {
        dismissPanelTip()
        guard !isPracticeMode else { return }
        if !HelpDebug.forceShowTooltips { guard !seenWordDetailTip else { return } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showWordDetailTip = true }
        }
    }

    private func dismissWordDetailTip() {
        seenWordDetailTip = true
        if showWordDetailTip {
            withAnimation(.easeInOut(duration: 0.2)) { showWordDetailTip = false }
            if helpReplay {
                // Replay: the arrows tip is next in the card's sequence.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showArrowsTip = true }
                }
            } else {
                onWordTipDismissed()   // chain: the page shows the swipe hint next
            }
        }
    }

    // Step to the previous bubble, or (past the first) the previous page.
    private func goPrev() {
        dismissArrowsTip()   // they used the arrows — the hint's job is done
        AudioManager.shared.stop()
        if index > 0 { withAnimation { index -= 1 } } else { onRequestPrevPage() }
    }
    // Step to the next bubble, or (past the last) the next page.
    private func goNext() {
        dismissArrowsTip()   // they used the arrows — the hint's job is done
        AudioManager.shared.stop()
        if index < bubbles.count - 1 { withAnimation { index += 1 } } else { onRequestNextPage() }
    }

    // Prominent circular step arrow, placed on the card's side at mid-height.
    private func sideArrow(next: Bool) -> some View {
        Button { next ? goNext() : goPrev() } label: {
            Image(systemName: next ? "chevron.right" : "chevron.left")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.accentColor, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
                .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .padding(next ? .trailing : .leading, 4)
        .explains(next ? "Next bubble" : "Previous bubble",
                  next ? "Move to the next bubble. On the last bubble it turns to the next page and closes this panel."
                       : "Move to the previous bubble. On the first bubble it goes back a page.",
                  id: next ? "card.next" : "card.prev")
    }

    /// Place the card on the opposite vertical region from the current bubble's
    /// panel: a bubble whose panel sits in the top half of the page → card at the
    /// bottom, and vice versa. Decided by the panel's vertical centre (not the
    /// bubble's), so a tall top panel still sends the card to the bottom even when
    /// the bubble sits low within it. Falls back to the bubble's own position when
    /// it isn't inside a sub-panel (e.g. a single full-page panel).
    private var anchorTop: Bool {
        guard bubbles.indices.contains(index) else { return false }
        let bubble = bubbles[index]
        let referenceY: Double
        if let panel = panels.first(where: { $0.bubbles.contains(where: { $0.id == bubble.id }) }),
           panel.tapZoneHeight <= 0.75 {
            referenceY = panel.tapZoneY + panel.tapZoneHeight / 2
        } else {
            referenceY = bubble.positionY + bubble.height / 2
        }
        return referenceY >= 0.5   // bubble in the bottom half → show card at the top
    }

    private var card: some View {
        VStack(spacing: 0) {
            ScrollView {
                if bubbles.indices.contains(index) {
                    BubbleContentView(comic: comic, bubble: bubbles[index], revealedBubbleId: $revealedBubbleId,
                                      onWordTap: { handleWordTap() })
                        .id(bubbles[index].id)   // reset per-bubble state when stepping
                        // Extra horizontal inset so the side step-arrows (~48pt in from
                        // each edge, at mid-height) never sit on top of the text/controls,
                        // with a bit more breathing room on the left. Extra top room for
                        // the floating close button.
                        .padding(.leading, 60)
                        .padding(.trailing, 48)
                        .padding(.top, 34)
                        .padding(.bottom, 16)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: PopupContentHeightKey.self, value: g.size.height)
                        })
                }
            }
            // Hug the content: only as tall as it needs, capped so long bubbles scroll.
            .frame(height: contentHeight > 0 ? min(contentHeight, maxContentHeight) : maxContentHeight)
            .onPreferenceChange(PopupContentHeightKey.self) { contentHeight = $0 }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        // Just a close button, floating in the top-right (no banner / no bubble count).
        .overlay(alignment: .topTrailing) {
            Button { onClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .explains("Close", "Close this panel. Tap any bubble on the page to open it again.", id: "card.close")
        }
        // Help-mode hint for the swipe gesture (only visible while help is on).
        .overlay(alignment: .top) {
            HelpHint(icon: "hand.draw",
                     label: "Swipe",
                     title: "Swipe the panel",
                     text: "Swipe left or right anywhere on the panel to move between bubbles — the same as the side arrows.",
                     animatedSwipe: true)
                .padding(.top, 6)
        }
        // Prominent step arrows on the sides, at mid-height.
        .overlay(alignment: .leading) { sideArrow(next: false) }
        .overlay(alignment: .trailing) { sideArrow(next: true) }
        // Swipe the whole card left/right to step bubbles (and turn pages at the ends),
        // same as the arrows. Simultaneous so it doesn't fight the content scroll: it
        // only acts on a clearly horizontal swipe.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height),
                          abs(v.translation.width) > 50 else { return }
                    if v.translation.width < 0 { goNext() } else { goPrev() }
                }
        )
    }

}

/// Reports the natural height of the bubble popup's content so the card can hug it.
private struct PopupContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    NavigationStack {
        PageView(comic: ComicData.allComics[0], page: ComicData.allComics[0].pages[0])
            .environmentObject(SettingsManager())
            .environmentObject(ReadingProgressManager())
    }
}
