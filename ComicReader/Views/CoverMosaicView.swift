import SwiftUI
import UIKit

/// The covers mosaic that plays once at the end of the free preview, before
/// the End-of-preview card: the reels' sign-off — a violet screen on which
/// every comic's cover pops in, left to right, top to bottom, as the largest
/// 2:3 tiles that fit them all; a two-second hold; then the card.
///
/// Every published comic's cover comes first, in catalogue order, then the
/// unpublished ones — each once; only a page with more cells than covers
/// sees one again. They're fetched when a preview opens (URLCache answers at
/// once for the ones the Library has shown). The mosaic plays at most once
/// per launch, never under Reduce Motion, never without enough covers, and
/// never when `preview.coverMosaic` is NO (the UI probes).
@MainActor
enum CoverMosaic {
    /// Fewer distinct covers than this wouldn't make a mosaic; the card comes straight up.
    static let minimumCovers = 6
    static let crossfade: TimeInterval = 0.35
    /// The pop-in and the hold once the last cover is in.
    static let popIn: TimeInterval = 0.18
    static let hold: TimeInterval = 3.0
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
        /// The cells on the page — every one gets a cover.
        var capacity: Int { columns * rows }

        func frame(of index: Int) -> CGRect {
            CGRect(x: origin.x + CGFloat(index % columns) * (tile.width + gap),
                   y: origin.y + CGFloat(index / columns) * (tile.height + gap),
                   width: tile.width, height: tile.height)
        }
    }

    /// As the reel lays it out: inside the margin, from three columns up,
    /// the first column count whose 2:3 tiles fit every cover on the screen.
    /// Past eight columns the screen is full and the last covers are left out.
    static func grid(count: Int, in size: CGSize, margin: CGFloat = 16, gap: CGFloat = 5) -> Grid? {
        guard count > 0, size.width > 2 * margin, size.height > 2 * margin else { return nil }
        let innerW = size.width - 2 * margin, innerH = size.height - 2 * margin
        var chosen: (cols: Int, rows: Int, w: CGFloat, h: CGFloat)?
        for cols in 3...8 {
            let w = floor((innerW - CGFloat(cols - 1) * gap) / CGFloat(cols))
            let h = (w * 1.5).rounded()
            let rows = Int(ceil(Double(count) / Double(cols)))
            if CGFloat(rows) * h + CGFloat(rows - 1) * gap <= innerH { chosen = (cols, rows, w, h); break }
            if cols == 8 {
                let fit = max(1, Int(floor((innerH + gap) / (h + gap))))
                chosen = (cols, min(rows, fit), w, h)
            }
        }
        guard let c = chosen, c.w > 0 else { return nil }
        let gridW = CGFloat(c.cols) * c.w + CGFloat(c.cols - 1) * gap
        let gridH = CGFloat(c.rows) * c.h + CGFloat(c.rows - 1) * gap
        return Grid(columns: c.cols, rows: c.rows, tile: CGSize(width: c.w, height: c.h),
                    origin: CGPoint(x: ((size.width - gridW) / 2).rounded(), y: ((size.height - gridH) / 2).rounded()),
                    gap: gap)
    }

    /// The cover for each cell: the list in order — and only if the last row
    /// still has empty cells, round again.
    static func fill<T>(_ covers: [T], cells: Int) -> [T] {
        guard !covers.isEmpty, cells > 0 else { return [] }
        return (0..<cells).map { covers[$0 % covers.count] }
    }

    /// When each cover pops in: the first at 0.15 s, then a steady step chosen
    /// so the page is tiled in about `tiling` seconds — never slower than
    /// 0.14 s a cover, never faster than 0.03 s.
    static func entrances(count: Int, tiling: TimeInterval = 2.0) -> [TimeInterval] {
        guard count > 0 else { return [] }
        let step = min(0.14, max(0.03, tiling / Double(count)))
        return (0..<count).map { 0.15 + Double($0) * step }
    }

    /// The whole run, from the first cover to the hand-back.
    static func duration(count: Int) -> TimeInterval {
        (entrances(count: count).last ?? 0) + popIn + hold
    }

    /// What /api/reader/covers lists: every comic's cover, published first.
    struct Listing: Decodable { let covers: [Entry] }
    struct Entry: Decodable, Equatable {
        let id: String
        let published: Bool
        let coverThumbnailUrl: String
    }

    /// The cover paths to tile, in order: the server's listing (published in
    /// catalogue order, then unpublished to fill the page); failing that, the
    /// published catalogue the Library already holds.
    static func coverPaths(listing: [Entry]?, catalog: [StoreComic]) -> [String] {
        if let listing, !listing.isEmpty { return listing.map(\.coverThumbnailUrl).filter { !$0.isEmpty } }
        return catalog
            .sorted { ($0.order ?? Int.max, $0.id) < ($1.order ?? Int.max, $1.id) }
            .map(\.coverThumbnailUrl).filter { !$0.isEmpty }
    }

    static func fetchListing(baseURL: String = Secrets.serverBaseURL) async -> [Entry]? {
        guard let url = URL(string: baseURL + "/api/reader/covers"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let listing = try? JSONDecoder().decode(Listing.self, from: data) else { return nil }
        return listing.covers
    }

    /// The covers as small images, in tiling order. Ones the Library has
    /// already shown come from the URL cache; the rest are fetched. Missing
    /// or failed covers are simply left out.
    static func loadCovers(catalog: [StoreComic], baseURL: String = Secrets.serverBaseURL, limit: Int = 60) async -> [UIImage] {
        let paths = coverPaths(listing: await fetchListing(baseURL: baseURL), catalog: catalog).prefix(limit)
        let urls: [URL] = paths.compactMap { URL(string: baseURL + $0) }
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

/// The mosaic itself, presented full screen over the reader (bars and all).
/// It fades itself in and out — the cover is presented and dismissed without
/// the system slide — and calls `onFinished` once faded out after the hold,
/// or after a tap, for anyone who'd rather get on to the card.
struct CoverMosaicView: View {
    let covers: [UIImage]
    let onFinished: () -> Void

    @State private var visible = false
    @State private var shown: Set<Int> = []
    @State private var captionShown = false
    @State private var started = false   // the run begins once, from a real layout
    @State private var finished = false

    var body: some View {
        GeometryReader { geo in
            let grid = CoverMosaic.grid(count: covers.count, in: geo.size)
            ZStack(alignment: .topLeading) {
                CoverMosaic.violet.ignoresSafeArea()
                if let grid {
                    ForEach(Array(CoverMosaic.fill(covers, cells: grid.capacity).enumerated()), id: \.offset) { index, cover in
                        let f = grid.frame(of: index)
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFill()
                            .frame(width: f.width, height: f.height)
                            .clipShape(RoundedRectangle(cornerRadius: max(4, f.width * 0.09), style: .continuous))
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                        .opacity(captionShown ? 1 : 0)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { play(cells: grid?.capacity ?? 0) }
            .onChange(of: geo.size) { _, size in play(cells: CoverMosaic.grid(count: covers.count, in: size)?.capacity ?? 0) }
        }
        .opacity(visible ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Every Comigo comic")
        .accessibilityIdentifier("Cover mosaic")
        .onAppear { withAnimation(.easeInOut(duration: CoverMosaic.crossfade)) { visible = true } }
    }

    private func play(cells: Int) {
        // A first layout pass can be zero-sized: wait for the real one, then
        // run exactly once — a second start would end the run early.
        guard !started, cells > 0 else { return }
        started = true
        let times = CoverMosaic.entrances(count: cells)
        for (index, at) in times.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + CoverMosaic.crossfade + at) {
                withAnimation(.easeOut(duration: CoverMosaic.popIn)) { _ = shown.insert(index) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + CoverMosaic.crossfade + (times.last ?? 0)) {
            withAnimation(.easeOut(duration: 0.3)) { captionShown = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + CoverMosaic.crossfade + CoverMosaic.duration(count: cells)) { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeInOut(duration: CoverMosaic.crossfade)) { visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + CoverMosaic.crossfade) { onFinished() }
    }
}
