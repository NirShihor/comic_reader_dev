import SwiftUI
import UIKit

/// The covers mosaic that plays once behind the End-of-preview card: the card
/// has a beat to itself, then gives way to a violet page on which every
/// published comic's cover pops in, left to right, top to bottom (the same
/// treatment as the reels' sign-off), holds, and hands back to the card.
///
/// It needs the covers in hand — they're fetched when a preview opens
/// (URLCache answers at once for the ones the Library has shown) — and plays
/// at most once per launch, never under Reduce Motion, and never when
/// `preview.coverMosaic` is NO (the UI probes).
@MainActor
enum CoverMosaic {
    /// Fewer covers than this wouldn't make a mosaic; the card stays put.
    static let minimumCovers = 6
    /// The card alone before the mosaic takes over.
    static let cardBeat: TimeInterval = 2.0
    static let crossfade: TimeInterval = 0.35
    /// The pop-in and the hold once the last cover is in.
    static let popIn: TimeInterval = 0.18
    static let hold: TimeInterval = 1.0
    static let violet = Color(red: 0x6E/255, green: 0x40/255, blue: 0xF0/255)

    static var playedThisLaunch = false

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "preview.coverMosaic") == nil || defaults.bool(forKey: "preview.coverMosaic")
    }

    struct Grid: Equatable {
        let columns: Int
        let rows: Int
        let tile: CGSize
        let origin: CGPoint
        let gap: CGFloat
        /// How many covers the page holds; the mosaic shows the first `capacity`.
        var capacity: Int { columns * rows }

        func frame(of index: Int) -> CGRect {
            CGRect(x: origin.x + CGFloat(index % columns) * (tile.width + gap),
                   y: origin.y + CGFloat(index / columns) * (tile.height + gap),
                   width: tile.width, height: tile.height)
        }
    }

    /// As the reel lays it out: from three columns up, the first count whose
    /// 2:3 tiles fit every cover on the page; past eight columns the page is
    /// full and the last covers are left out.
    static func grid(count: Int, in size: CGSize, margin: CGFloat = 24, gap: CGFloat = 10) -> Grid? {
        guard count > 0, size.width > 2 * margin, size.height > 2 * margin else { return nil }
        let innerW = size.width - 2 * margin, innerH = size.height - 2 * margin
        var chosen: (cols: Int, rows: Int, w: CGFloat, h: CGFloat)?
        for cols in 3...8 {
            let w = floor((innerW - CGFloat(cols - 1) * gap) / CGFloat(cols))
            let h = (w * 1.5).rounded()
            let rows = Int(ceil(Double(count) / Double(cols)))
            if CGFloat(rows) * h + CGFloat(rows - 1) * gap <= innerH { chosen = (cols, rows, w, h); break }
            // Eight columns and still too tall: keep the rows that fit.
            if cols == 8 {
                let fit = max(1, Int(floor((innerH + gap) / (h + gap))))
                chosen = (cols, min(rows, fit), w, h)
            }
        }
        guard let c = chosen else { return nil }
        let gridW = CGFloat(c.cols) * c.w + CGFloat(c.cols - 1) * gap
        let gridH = CGFloat(c.rows) * c.h + CGFloat(c.rows - 1) * gap
        return Grid(columns: c.cols, rows: c.rows, tile: CGSize(width: c.w, height: c.h),
                    origin: CGPoint(x: ((size.width - gridW) / 2).rounded(), y: ((size.height - gridH) / 2).rounded()),
                    gap: gap)
    }

    /// When each cover pops in: the first at 0.15 s, then a steady step chosen
    /// so the last is in by about `total` less the hold — never slower than
    /// 0.14 s a cover, never faster than 0.03 s.
    static func entrances(count: Int, total: TimeInterval = 3.0) -> [TimeInterval] {
        guard count > 0 else { return [] }
        let step = min(0.14, max(0.03, (total - hold - popIn) / Double(count)))
        return (0..<count).map { 0.15 + Double($0) * step }
    }

    /// The whole run, from the first cover to the hand-back.
    static func duration(count: Int) -> TimeInterval {
        (entrances(count: count).last ?? 0) + popIn + hold
    }

    /// Every published cover, in catalogue order, as small images. Covers the
    /// Library has already shown come from the URL cache; the rest are fetched.
    /// Missing or failed covers are simply left out.
    static func loadCovers(catalog: [StoreComic], baseURL: String = Secrets.serverBaseURL, limit: Int = 48) async -> [UIImage] {
        let ordered = catalog
            .sorted { ($0.order ?? Int.max, $0.id) < ($1.order ?? Int.max, $1.id) }
            .prefix(limit)
        let urls: [URL] = ordered.compactMap { comic in
            guard !comic.coverThumbnailUrl.isEmpty else { return nil }
            return URL(string: baseURL + comic.coverThumbnailUrl)
        }
        return await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (i, url) in urls.enumerated() {
                group.addTask {
                    let data = try? await URLSession.shared.data(from: url).0
                    return (i, data.flatMap(UIImage.init(data:)))
                }
            }
            var found: [(Int, UIImage)] = []
            for await (i, image) in group { if let image { found.append((i, image)) } }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}

/// The mosaic itself. Calls `onFinished` when the hold is over — or at once
/// on a tap, for anyone who'd rather get back to the card.
struct CoverMosaicView: View {
    let covers: [UIImage]
    let onFinished: () -> Void

    @State private var shown: Set<Int> = []
    @State private var captionShown = false
    @State private var finished = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                CoverMosaic.violet
                if let grid = CoverMosaic.grid(count: covers.count, in: geo.size) {
                    ForEach(Array(covers.prefix(grid.capacity).enumerated()), id: \.offset) { index, cover in
                        let f = grid.frame(of: index)
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFill()
                            .frame(width: f.width, height: f.height)
                            .clipShape(RoundedRectangle(cornerRadius: max(6, f.width * 0.09), style: .continuous))
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                            .scaleEffect(shown.contains(index) ? 1 : 0.5)
                            .opacity(shown.contains(index) ? 1 : 0)
                            .position(x: f.midX, y: f.midY)
                    }
                }
                VStack {
                    Spacer()
                    Text("Every comic, every page — with Comigo Unlimited")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                        .opacity(captionShown ? 1 : 0)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Every Comigo comic")
        .accessibilityIdentifier("Cover mosaic")
        .onAppear(perform: play)
    }

    private func play() {
        let times = CoverMosaic.entrances(count: covers.count)
        for (index, at) in times.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                withAnimation(.easeOut(duration: CoverMosaic.popIn)) { _ = shown.insert(index) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (times.last ?? 0)) {
            withAnimation(.easeOut(duration: 0.3)) { captionShown = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + CoverMosaic.duration(count: covers.count)) { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }
}
