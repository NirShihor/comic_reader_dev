import SwiftUI
import UIKit

/// The covers mosaic that plays once at the end of the free preview, before
/// the End-of-preview card: a violet page on which comic covers pop in, left
/// to right, top to bottom, until the whole page is tiled (the reels'
/// sign-off treatment), hold for two seconds, and give way to the card.
///
/// Every published comic's cover comes first, in catalogue order; the
/// unpublished ones fill the page out, and if that's still short the covers
/// go round again. They're fetched when a preview opens (URLCache answers at
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
    static let hold: TimeInterval = 2.0
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

    /// Edge to edge: about three covers across a phone (more on a wider
    /// page), 2:3 tiles, and as many rows as it takes to cover the page —
    /// the last row runs off the bottom edge rather than leave a strip bare.
    static func grid(in size: CGSize, gap: CGFloat = 8) -> Grid? {
        guard size.width > 0, size.height > 0 else { return nil }
        let columns = max(3, Int((size.width / 130).rounded()))
        let w = floor((size.width - CGFloat(columns - 1) * gap) / CGFloat(columns))
        let h = (w * 1.5).rounded()
        guard w > 0 else { return nil }
        let rows = max(1, Int(ceil((size.height + gap) / (h + gap))))
        let gridW = CGFloat(columns) * w + CGFloat(columns - 1) * gap
        let gridH = CGFloat(rows) * h + CGFloat(rows - 1) * gap
        return Grid(columns: columns, rows: rows, tile: CGSize(width: w, height: h),
                    origin: CGPoint(x: ((size.width - gridW) / 2).rounded(), y: ((size.height - gridH) / 2).rounded()),
                    gap: gap)
    }

    /// The cover for each cell: the list in order, then round again until
    /// every cell has one.
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

/// The mosaic itself. Calls `onFinished` when the hold is over — or at once
/// on a tap, for anyone who'd rather get on to the card.
struct CoverMosaicView: View {
    let covers: [UIImage]
    let onFinished: () -> Void

    @State private var shown: Set<Int> = []
    @State private var captionShown = false
    @State private var finished = false
    @State private var cells = 0   // how many tiles this page takes, once laid out

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                CoverMosaic.violet
                if let grid = CoverMosaic.grid(in: geo.size) {
                    ForEach(Array(CoverMosaic.fill(covers, cells: grid.capacity).enumerated()), id: \.offset) { index, cover in
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                        .opacity(captionShown ? 1 : 0)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .onAppear { play(cells: CoverMosaic.grid(in: geo.size)?.capacity ?? 0) }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Every Comigo comic")
        .accessibilityIdentifier("Cover mosaic")
    }

    private func play(cells: Int) {
        guard self.cells == 0 else { return }   // laid out once
        self.cells = cells
        let times = CoverMosaic.entrances(count: cells)
        for (index, at) in times.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                withAnimation(.easeOut(duration: CoverMosaic.popIn)) { _ = shown.insert(index) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (times.last ?? 0)) {
            withAnimation(.easeOut(duration: 0.3)) { captionShown = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + CoverMosaic.duration(count: cells)) { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }
}
