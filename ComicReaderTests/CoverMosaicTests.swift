import XCTest
@testable import ComicReader

/// The covers mosaic before the End-of-preview card: the reel's layout (from
/// three columns up, the first count whose 2:3 tiles fit every cover inside
/// the margin), every cover once (published first), timed so the lot is in
/// within about two seconds before the hold, and off for the UI probes that
/// don't want it.
@MainActor
final class CoverMosaicTests: XCTestCase {
    private let phone = CGSize(width: 390, height: 844)

    /// The reel's layout on a phone screen (below the status bar and above
    /// the home indicator): thirty covers go five across in six rows.
    func testThirtyCoversTileFiveAcrossOnAPhone() throws {
        let screen = CGSize(width: 390, height: 763)
        let grid = try XCTUnwrap(CoverMosaic.grid(count: 30, in: screen))
        XCTAssertEqual(grid.columns, 5)
        XCTAssertEqual(grid.rows, 6)
        XCTAssertEqual(grid.capacity, 30)
        XCTAssertEqual(grid.tile.height, (grid.tile.width * 1.5).rounded(), "2:3 covers")
        // Inside the margin, centred.
        XCTAssertGreaterThanOrEqual(grid.frame(of: 0).minX, 16)
        XCTAssertGreaterThanOrEqual(grid.frame(of: 0).minY, 16)
        let last = grid.frame(of: 29)
        XCTAssertLessThanOrEqual(last.maxX, screen.width - 16)
        XCTAssertLessThanOrEqual(last.maxY, screen.height - 16)
        XCTAssertEqual(grid.frame(of: 0).minX, screen.width - last.maxX, accuracy: 1, "centred horizontally")
        XCTAssertEqual(grid.frame(of: 0).minY, screen.height - last.maxY, accuracy: 1, "centred vertically")
    }

    func testFewerCoversGetBiggerTiles() throws {
        let screen = CGSize(width: 390, height: 763)
        let dozen = try XCTUnwrap(CoverMosaic.grid(count: 12, in: screen))
        XCTAssertEqual(dozen.columns, 3)
        XCTAssertEqual(dozen.rows, 4)
        let thirty = try XCTUnwrap(CoverMosaic.grid(count: 30, in: screen))
        XCTAssertGreaterThan(dozen.tile.width, thirty.tile.width)
    }

    func testAScreenThatCannotHoldThemAllShowsTheFirstOnes() throws {
        let grid = try XCTUnwrap(CoverMosaic.grid(count: 400, in: phone))
        XCTAssertEqual(grid.columns, 8)
        XCTAssertLessThan(grid.capacity, 400)
        XCTAssertLessThanOrEqual(grid.frame(of: grid.capacity - 1).maxY, phone.height - 16)
    }

    func testAWiderScreenStillFitsInsideItsMargin() throws {
        let pad = try XCTUnwrap(CoverMosaic.grid(count: 30, in: CGSize(width: 820, height: 1180)))
        XCTAssertLessThanOrEqual(pad.frame(of: 29).maxX, 820 - 16)
        XCTAssertLessThanOrEqual(pad.frame(of: 29).maxY, 1180 - 16)
    }

    func testEveryCellGetsACoverGoingRoundAgainWhenShort() {
        XCTAssertEqual(CoverMosaic.fill(["a", "b", "c"], cells: 7), ["a", "b", "c", "a", "b", "c", "a"])
        XCTAssertEqual(CoverMosaic.fill(["a", "b", "c"], cells: 2), ["a", "b"])
        XCTAssertEqual(CoverMosaic.fill([String](), cells: 5), [])
        XCTAssertEqual(CoverMosaic.fill(["a"], cells: 0), [])
    }

    func testNothingToLayOutIsNoGrid() {
        XCTAssertNil(CoverMosaic.grid(count: 0, in: phone))
        XCTAssertNil(CoverMosaic.grid(count: 5, in: CGSize(width: 30, height: 30)))
    }

    func testTheServerListingLeadsPublishedFirstAndTheCatalogueIsTheFallback() {
        let listing = [
            CoverMosaic.Entry(id: "p", published: true, coverThumbnailUrl: "/api/reader/cover-thumbnail/p"),
            CoverMosaic.Entry(id: "u", published: false, coverThumbnailUrl: "/api/reader/cover-thumbnail/u"),
            CoverMosaic.Entry(id: "none", published: false, coverThumbnailUrl: ""),
        ]
        let catalog = [
            StoreComic(id: "b", title: "B", description: "", coverThumbnailUrl: "/api/reader/cover-thumbnail/b", level: "", totalPages: 1, estimatedMinutes: 1, language: "es", fileSizeMB: 1, version: "1", downloadUrl: "", order: 2),
            StoreComic(id: "a", title: "A", description: "", coverThumbnailUrl: "/api/reader/cover-thumbnail/a", level: "", totalPages: 1, estimatedMinutes: 1, language: "es", fileSizeMB: 1, version: "1", downloadUrl: "", order: 1),
            StoreComic(id: "bare", title: "Bare", description: "", coverThumbnailUrl: "", level: "", totalPages: 1, estimatedMinutes: 1, language: "es", fileSizeMB: 1, version: "1", downloadUrl: ""),
        ]
        XCTAssertEqual(CoverMosaic.coverPaths(listing: listing, catalog: catalog),
                       ["/api/reader/cover-thumbnail/p", "/api/reader/cover-thumbnail/u"], "the listing, unpublished after published, no empty paths")
        XCTAssertEqual(CoverMosaic.coverPaths(listing: nil, catalog: catalog),
                       ["/api/reader/cover-thumbnail/a", "/api/reader/cover-thumbnail/b"], "no listing (older server): the published catalogue in order")
        XCTAssertEqual(CoverMosaic.coverPaths(listing: [], catalog: catalog).count, 2, "an empty listing counts as none")
    }

    func testTheListingDecodesWhatTheServerSends() throws {
        let json = #"{"covers":[{"id":"x","published":true,"coverThumbnailUrl":"/api/reader/cover-thumbnail/x"}]}"#
        let listing = try JSONDecoder().decode(CoverMosaic.Listing.self, from: Data(json.utf8))
        XCTAssertEqual(listing.covers, [CoverMosaic.Entry(id: "x", published: true, coverThumbnailUrl: "/api/reader/cover-thumbnail/x")])
    }

    func testCoversPopInOneAfterAnotherAndAreAllInBeforeTheHold() {
        for count in [6, 15, 40] {
            let times = CoverMosaic.entrances(count: count)
            XCTAssertEqual(times.count, count)
            XCTAssertEqual(times.first, 0.15)
            XCTAssertEqual(times, times.sorted(), "left to right, top to bottom")
            let steps = zip(times.dropFirst(), times).map { $0 - $1 }
            for s in steps { XCTAssertGreaterThanOrEqual(s, 0.03 - 1e-9); XCTAssertLessThanOrEqual(s, 0.14 + 1e-9) }
            XCTAssertEqual(CoverMosaic.duration(count: count), times.last! + CoverMosaic.popIn + CoverMosaic.hold, accuracy: 1e-9)
            XCTAssertLessThanOrEqual(CoverMosaic.duration(count: count), 4.3, "\(count) covers: tiled in about two seconds, then the two-second hold")
        }
        XCTAssertEqual(CoverMosaic.entrances(count: 0), [])
    }

    func testOnByDefaultAndOffForTheProbes() {
        let d = UserDefaults(suiteName: "CoverMosaicTests.\(UUID().uuidString)")!
        XCTAssertTrue(CoverMosaic.isEnabled(defaults: d))
        d.set(false, forKey: "preview.coverMosaic")   // what `-preview.coverMosaic NO` does
        XCTAssertFalse(CoverMosaic.isEnabled(defaults: d))
        d.set(true, forKey: "preview.coverMosaic")
        XCTAssertTrue(CoverMosaic.isEnabled(defaults: d))
    }

    func testCoversComeInCatalogueOrderAndSkipWhatIsMissing() async {
        // No server in a unit test: URLs that can't be fetched are left out,
        // and an empty cover path never becomes a request.
        let comics = [
            StoreComic(id: "b", title: "B", description: "", coverThumbnailUrl: "/nope/b.png", level: "", totalPages: 1, estimatedMinutes: 1, language: "es", fileSizeMB: 1, version: "1", bundleVersion: nil, downloadUrl: "", collectionId: nil, collectionTitle: nil, collectionTitleEn: nil, episodeNumber: nil, collectionDescription: nil, collectionCoverThumbnailUrl: nil, order: 2),
            StoreComic(id: "a", title: "A", description: "", coverThumbnailUrl: "", level: "", totalPages: 1, estimatedMinutes: 1, language: "es", fileSizeMB: 1, version: "1", bundleVersion: nil, downloadUrl: "", collectionId: nil, collectionTitle: nil, collectionTitleEn: nil, episodeNumber: nil, collectionDescription: nil, collectionCoverThumbnailUrl: nil, order: 1),
        ]
        let covers = await CoverMosaic.loadCovers(catalog: comics, baseURL: "http://127.0.0.1:1")
        XCTAssertEqual(covers.count, 0)
    }
}
