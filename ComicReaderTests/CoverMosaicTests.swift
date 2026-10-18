import XCTest
@testable import ComicReader

/// The covers mosaic behind the End-of-preview card: laid out like the reel's
/// sign-off (the first column count from three whose 2:3 tiles fit the page),
/// timed so every cover is in with a hold to spare, and off by default for
/// the UI probes.
@MainActor
final class CoverMosaicTests: XCTestCase {
    private let phone = CGSize(width: 390, height: 844)

    func testADozenCoversTileInThreeColumnsOnAPhone() throws {
        let grid = try XCTUnwrap(CoverMosaic.grid(count: 12, in: phone))
        XCTAssertEqual(grid.columns, 3)
        XCTAssertEqual(grid.rows, 4)
        XCTAssertEqual(grid.capacity, 12)
        XCTAssertEqual(grid.tile.height, (grid.tile.width * 1.5).rounded(), "2:3 covers")
        // Centred, and everything inside the margins.
        let last = grid.frame(of: 11)
        XCTAssertLessThanOrEqual(last.maxX, phone.width - 24)
        XCTAssertLessThanOrEqual(last.maxY, phone.height - 24)
        XCTAssertEqual(grid.frame(of: 0).minX, phone.width - last.maxX, accuracy: 1, "centred horizontally")
    }

    func testMoreCoversTakeMoreColumnsUntilTheyFit() throws {
        let forty = try XCTUnwrap(CoverMosaic.grid(count: 40, in: phone))
        XCTAssertGreaterThan(forty.columns, 3)
        XCTAssertEqual(forty.capacity >= 40, true, "all forty fit")
        let bottom = forty.frame(of: 39)
        XCTAssertLessThanOrEqual(bottom.maxY, phone.height - 24)
    }

    func testAPageThatCannotHoldThemAllShowsTheFirstOnes() throws {
        let grid = try XCTUnwrap(CoverMosaic.grid(count: 400, in: phone))
        XCTAssertEqual(grid.columns, 8)
        XCTAssertLessThan(grid.capacity, 400)
        XCTAssertLessThanOrEqual(grid.frame(of: grid.capacity - 1).maxY, phone.height - 24)
    }

    func testNothingToLayOutIsNoGrid() {
        XCTAssertNil(CoverMosaic.grid(count: 0, in: phone))
        XCTAssertNil(CoverMosaic.grid(count: 5, in: CGSize(width: 30, height: 30)))
    }

    func testCoversPopInOneAfterAnotherAndAreAllInBeforeTheHold() {
        for count in [6, 12, 40] {
            let times = CoverMosaic.entrances(count: count)
            XCTAssertEqual(times.count, count)
            XCTAssertEqual(times.first, 0.15)
            XCTAssertEqual(times, times.sorted(), "left to right, top to bottom")
            let steps = zip(times.dropFirst(), times).map { $0 - $1 }
            for s in steps { XCTAssertGreaterThanOrEqual(s, 0.03 - 1e-9); XCTAssertLessThanOrEqual(s, 0.14 + 1e-9) }
            XCTAssertEqual(CoverMosaic.duration(count: count), times.last! + CoverMosaic.popIn + CoverMosaic.hold, accuracy: 1e-9)
            XCTAssertLessThanOrEqual(CoverMosaic.duration(count: count), 3.3, "\(count) covers: over in about three seconds")
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
