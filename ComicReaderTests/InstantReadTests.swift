import XCTest
import SwiftUI
@testable import ComicReader

// Step 3 of instant reading: page-based download priority from comic.json,
// and a reader that treats files which haven't arrived as "not yet" —
// placeholder, request, swap in when they land — never as failure. Partial
// comics stay invisible to the normal library/open path throughout.
@MainActor
final class InstantReadTests: XCTestCase {
    private var root: URL!
    private var comics: URL!
    private var reader: BundleRangeReader!
    private var availability: ComicAssetAvailability!
    private var loader: ComicImageLoader!
    private var savedFillLoader: ComicImageLoader!

    override func setUp() async throws {
        try await super.setUp()
        RangeStub.reset()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("irt-\(UUID().uuidString)", isDirectory: true)
        comics = root.appendingPathComponent("Comics", isDirectory: true)
        try FileManager.default.createDirectory(at: comics, withIntermediateDirectories: true)
        reader = BundleRangeReader(configuration: RangeStub.configuration())
        availability = ComicAssetAvailability()
        loader = ComicImageLoader(comicsDirectory: comics)
        savedFillLoader = BubbleFill.loader
        BubbleFill.loader = loader
    }

    override func tearDown() async throws {
        BubbleFill.loader = savedFillLoader
        try? FileManager.default.removeItem(at: root)
        RangeStub.reset()
        try await super.tearDown()
    }

    // MARK: A synthetic comic whose audio is named after an OLD title

    /// Three story pages (cover + 2) and one practice page. Every audio clip
    /// is named `viejo_titulo_*` while the comic's slug is `demo`: a plan that
    /// derived names from the slug would ask for files that don't exist.
    private let demoJSON = """
    {"id":"comic-demo","title":"Demo","description":"","coverImage":"demo_cover","coverLandscape":"demo_cover_landscape",
     "collectionCoverImage":"collection_cover","collectionId":"col","collectionTitle":"Col","episodeNumber":1,
     "level":"beginner","totalPages":3,"estimatedMinutes":1,"language":"en","targetLanguage":"es","version":"1.0",
     "keyPhrases":[{"id":"kp1","es":"Muy bien","en":"Very good","practicePageId":"pp-1"}],
     "pages":[
      {"id":"pg-cover","pageNumber":1,"masterImage":"demo_cover","panels":[
        {"id":"pn-cover","artworkImage":"demo_cover","panelOrder":1,"tapZone":{"x":0,"y":0,"width":1,"height":1},"bubbles":[
          {"id":"b-cover","type":"narration","position":{"x":0.1,"y":0.1,"width":0.8,"height":0.2},"sentences":[
            {"id":"s-cover","text":"La llegada","audioUrl":"viejo_titulo_p0_s1_b1_t1","translationAudioUrl":"viejo_titulo_p0_s1_b1_t1_en",
             "words":[{"id":"w-la","text":"La","meaning":"The","wordAudioUrl":"words/la"}]}]}]}]},
      {"id":"pg-1","pageNumber":2,"masterImage":"demo_p1","noTextImage":"demo_p1_no_text","emptyBubblesImage":"demo_p1_empty_bubbles","panels":[
        {"id":"pn-1","artworkImage":"demo_p1_s1","noTextImage":"demo_p1_s1_no_text","panelOrder":1,"tapZone":{"x":0,"y":0,"width":1,"height":1},"bubbles":[
          {"id":"b-1","type":"speech","position":{"x":0.1,"y":0.1,"width":0.5,"height":0.2},"sentences":[
            {"id":"s-1","text":"Una noche","audioUrl":"viejo_titulo_p1_s1_b1_t1","translationAudioUrl":"viejo_titulo_p1_s1_b1_t1_en",
             "alternativeAudioUrls":["viejo_titulo_p1_s1_b1_alt"],
             "words":[{"id":"w-una","text":"Una","meaning":"A","wordAudioUrl":"words/una","baseFormAudioUrl":"words/uno",
                       "forms":[{"label":"Plural","text":"unas","audioUrl":"words/unas"}]}]}]},
          {"id":"b-2","type":"image","imageUrl":"demo_p1_b2_img","position":{"x":0.6,"y":0.6,"width":0.3,"height":0.2},"sentences":[]}]}],
       "hotspots":[{"id":"h-1","x":0.5,"y":0.5,"width":0.2,"height":0.2,"slides":[
          {"id":"hs-1","text":"Un reloj","translation":"A clock","imageUrl":"demo_p1_h1","audioUrl":"viejo_titulo_h1","translationAudioUrl":"viejo_titulo_h1_en"}]}]},
      {"id":"pg-2","pageNumber":3,"masterImage":"demo_p2","panels":[
        {"id":"pn-2","artworkImage":"demo_p2_s1","panelOrder":1,"tapZone":{"x":0,"y":0,"width":1,"height":1},"bubbles":[
          {"id":"b-3","type":"speech","position":{"x":0.1,"y":0.1,"width":0.5,"height":0.2},"sentences":[
            {"id":"s-3","text":"Adiós","audioUrl":"viejo_titulo_p2_s1_b1_t1","words":[]}]}]}]}],
     "practicePages":[
      {"id":"pp-1","pageNumber":1001,"masterImage":"demo_p1001","emptyBubblesImage":"demo_p1001_empty_bubbles","keyPhraseId":"kp1","panels":[
        {"id":"pn-pp","artworkImage":"demo_p1001_s1","panelOrder":1,"tapZone":{"x":0,"y":0,"width":1,"height":1},"bubbles":[
          {"id":"b-pp","type":"speech","position":{"x":0.1,"y":0.1,"width":0.5,"height":0.2},"sentences":[
            {"id":"s-pp","text":"Muy bien","audioUrl":"viejo_titulo_p1001_s1_b1_t1","words":[]}]}]}]}]}
    """

    private let demoImages = ["collection_cover", "demo_cover", "demo_cover_landscape", "demo_p1", "demo_p1001", "demo_p1001_empty_bubbles",
                              "demo_p1001_s1", "demo_p1_b2_img", "demo_p1_empty_bubbles", "demo_p1_h1", "demo_p1_no_text", "demo_p1_s1",
                              "demo_p1_s1_no_text", "demo_p2", "demo_p2_s1", "demo_unused"]
    private let demoAudio = ["viejo_titulo_h1", "viejo_titulo_h1_en", "viejo_titulo_p0_s1_b1_t1", "viejo_titulo_p0_s1_b1_t1_en",
                             "viejo_titulo_p1001_s1_b1_t1", "viejo_titulo_p1_s1_b1_alt", "viejo_titulo_p1_s1_b1_t1", "viejo_titulo_p1_s1_b1_t1_en",
                             "viejo_titulo_p2_s1_b1_t1"]
    private let demoWords = ["la", "una", "unas", "uno"]

    /// The demo comic's bundle, laid out like production (audio → words →
    /// comic.json → images, alphabetical within each), ~3 KB per file.
    private func demoZip() -> Data {
        var z = TestZip()
        func blob(_ seed: String) -> Data {
            var d = Data(seed.utf8)
            var x: UInt32 = 2_463_534_242
            for b in seed.utf8 { x = (x ^ UInt32(b)) &* 16_777_619 }
            while d.count < 3000 { x = x &* 1_664_525 &+ 1_013_904_223; d.append(UInt8(truncatingIfNeeded: x >> 24)) }
            return d
        }
        z.entries.append(("audio/", Data()))
        for a in demoAudio { z.entries.append(("audio/\(a).mp3", blob(a))) }
        z.entries.append(("audio/words/", Data()))
        for w in demoWords { z.entries.append(("audio/words/\(w).mp3", blob("w-\(w)"))) }
        z.entries.append(("comic.json", Data(demoJSON.utf8)))
        z.entries.append(("images/", Data()))
        for i in demoImages.sorted() { z.entries.append(("images/\(i).jpg", blob(i))) }
        return z.build()
    }

    private var demoComic: Comic {
        try! JSONDecoder().decode(ComicJSON.self, from: Data(demoJSON.utf8)).toComic(basePath: comics)
    }

    private var demoEntryNames: Set<String> {
        Set(demoAudio.map { "audio/\($0).mp3" } + demoWords.map { "audio/words/\($0).mp3" } + demoImages.map { "images/\($0).jpg" } + ["comic.json"])
    }

    // MARK: Helpers

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: InstantReadTests.self).url(forResource: name, withExtension: "zip", subdirectory: "Fixtures")
                                ?? Bundle(for: InstantReadTests.self).url(forResource: name, withExtension: "zip"))
        return try Data(contentsOf: url)
    }

    private func serve(_ id: String, _ data: Data, version: String? = "v1") {
        RangeStub.lock.withLock { RangeStub.objects[id] = .init(data: data, version: version) }
    }
    private func route(_ id: String) -> URL { URL(string: "\(RangeStub.base)/api/reader/comics/\(id)/bundle")! }

    private func downloader(_ comicId: String, internalId: String, config: ProgressiveDownloader.Configuration = .init(),
                            onLanded: ProgressiveDownloader.LandedHandler? = nil) -> ProgressiveDownloader {
        ProgressiveDownloader(comicId: comicId, bundleRoute: route(internalId), downloadUrl: "/api/reader/comics/\(internalId)",
                              fileSizeMB: 1, comicsDirectory: comics, reader: reader, configuration: config,
                              onProgress: { _ in }, onLanded: onLanded)
    }

    /// Unzip with today's extractor straight into the comics folder (a comic
    /// downloaded before this work) — or elsewhere, as a reference.
    @discardableResult
    private func extract(_ zip: Data, into dir: URL) throws -> URL {
        let z = root.appendingPathComponent("z-\(UUID().uuidString).zip")
        try zip.write(to: z)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try ZIPExtractor.extract(zipFileURL: z, to: dir)
        return dir
    }

    private func tree(_ dir: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey])!
        for case let f as URL in e where (try f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            out[String(f.path.dropFirst(dir.path.count + 1))] = try Data(contentsOf: f)
        }
        return out
    }

    private func store(storage: LocalComicStorage? = nil,
                       config: ProgressiveDownloader.Configuration = .init(retryDelay: 0.01)) -> (ComicStoreService, LocalComicStorage) {
        let st = storage ?? LocalComicStorage(comicsDirectory: comics)
        let s = ComicStoreService(localStorage: st, baseURL: RangeStub.base, defaults: UserDefaults(suiteName: "irt.\(UUID().uuidString)")!,
                                  rangeReader: reader, progressiveConfiguration: config, availability: availability)
        return (s, st)
    }

    private func storeComic(_ id: String, internalId: String) -> StoreComic {
        StoreComic(id: id, title: id, description: "", coverThumbnailUrl: "", level: "beginner", totalPages: 3, estimatedMinutes: 1,
                   language: "es", fileSizeMB: 1, version: "1.0", bundleVersion: "v1", downloadUrl: "/api/reader/comics/\(internalId)")
    }

    private func waitUntil(timeout: TimeInterval = 10, _ cond: @escaping @MainActor () -> Bool) async throws {
        let start = Date()
        while !cond() {
            if Date().timeIntervalSince(start) > timeout { throw XCTSkip("timed out waiting") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// The order entries were fetched in, from the recorded range requests.
    private func fetchOrder(_ manifest: ZipManifest) -> [String] {
        let spans = manifest.spans()
        var order: [String] = []
        for r in RangeStub.ranges where r.start != nil {
            for e in manifest.entriesByOffset where e.isExtracted {
                let s = spans[e]!
                if r.start! <= s.lowerBound && r.end >= s.upperBound - 1 { order.append(e.name) }
            }
        }
        return order
    }

    /// Write a partial marker for a complete folder (what a download that
    /// hasn't finished looks like — every file here, marker still on).
    private func markPartial(_ id: String, internalId: String) async throws {
        let m = try await reader.readManifest(try await reader.resolve(bundleRoute: route(internalId)).url)
        let marker = PartialDownloadMarker(comicId: id, downloadUrl: "/api/reader/comics/\(internalId)", bundleVersion: "v1",
                                           fileSizeMB: 1, startedAt: Date(), manifest: m)
        try JSONEncoder().encode(marker).write(to: LocalComicStorage.partialMarkerURL(in: comics.appendingPathComponent(id)))
    }

    /// A partial folder holding comic.json (and the marker) only.
    private func partialFolder(_ id: String, from ref: URL, subfolders: [String] = []) throws -> URL {
        let folder = comics.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for sub in subfolders { try FileManager.default.createDirectory(at: folder.appendingPathComponent(sub), withIntermediateDirectories: true) }
        try FileManager.default.copyItem(at: ref.appendingPathComponent("comic.json"), to: folder.appendingPathComponent("comic.json"))
        try Data("{}".utf8).write(to: LocalComicStorage.partialMarkerURL(in: folder))
        return folder
    }

    /// A page image in UIKit, as PageView drives it.
    private func pageContainer(_ imageName: String, comicId: String, stamp: Int = 0, offline: Bool = false) -> PagedImageContainer {
        let c = PagedImageContainer(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        c.loader = loader
        c.show(imageName: imageName, comicId: comicId, pageKey: 0, forward: true, offline: offline, assetStamp: stamp)
        return c
    }

    private func audioManager(for comicId: String) -> AudioManager {
        let a = AudioManager()
        a.comicsDirectory = comics
        a.availability = availability
        a.activeComicId = comicId
        return a
    }

    /// Records what the reader asks a download for.
    private final class Requests: @unchecked Sendable {
        let lock = NSLock()
        var focused: [Int] = []
        var requested: [String] = []
        var handle: ComicAssetAvailability.DownloadHandle {
            .init(focus: { [self] i in lock.withLock { focused.append(i) } },
                  request: { [self] n in lock.withLock { requested += n } })
        }
    }

    // MARK: 1 comic.json → per-page asset map

    func testComicJSONLandingBuildsThePerPageAssetMapFromItsOwnNames() async throws {
        serve("comic-demo", demoZip())
        let d = downloader("comic-demo", internalId: "comic-demo", config: .init(concurrency: 1, maxChunkBytes: 6_000))
        try await d.run()
        let built = await d.currentPlan
        let plan = try XCTUnwrap(built, "the plan exists once comic.json has landed")
        let decodedId = await d.decodedComicId
        XCTAssertEqual(decodedId, "comic-demo")
        XCTAssertEqual(plan, ComicAssetPlan(comic: demoComic, entryNames: demoEntryNames), "built from comic.json and the bundle's directory")

        XCTAssertEqual(plan.pages.map(\.pageNumber), [1, 2, 3], "story pages in reading order; the practice page isn't one")
        let cover = plan.pages[0], p1 = plan.pages[1], p2 = plan.pages[2]
        XCTAssertEqual(cover.display, ["images/demo_cover.jpg"])
        XCTAssertEqual(cover.audio, ["audio/viejo_titulo_p0_s1_b1_t1.mp3"])
        XCTAssertEqual(cover.interaction, ["audio/viejo_titulo_p0_s1_b1_t1_en.mp3", "audio/words/la.mp3"],
                       "the panel art IS the cover image — not listed twice")
        XCTAssertEqual(p1.display, ["images/demo_p1.jpg"])
        XCTAssertEqual(p1.audio, ["audio/viejo_titulo_p1_s1_b1_t1.mp3"])
        XCTAssertEqual(Set(p1.interaction), ["images/demo_p1_empty_bubbles.jpg", "images/demo_p1_no_text.jpg",
                                             "images/demo_p1_s1.jpg", "images/demo_p1_s1_no_text.jpg", "images/demo_p1_b2_img.jpg",
                                             "audio/viejo_titulo_p1_s1_b1_t1_en.mp3", "audio/viejo_titulo_p1_s1_b1_alt.mp3",
                                             "audio/words/una.mp3", "audio/words/uno.mp3", "audio/words/unas.mp3",
                                             "images/demo_p1_h1.jpg", "audio/viejo_titulo_h1.mp3", "audio/viejo_titulo_h1_en.mp3"],
                       "blank bakes, panel art, bubble image, translation/alternative/word audio, hotspot slide image + audio")
        XCTAssertEqual(p2.display, ["images/demo_p2.jpg"]); XCTAssertEqual(p2.audio, ["audio/viejo_titulo_p2_s1_b1_t1.mp3"])
        XCTAssertEqual(p2.interaction, ["images/demo_p2_s1.jpg"])
        XCTAssertEqual(plan.comicWide, ["images/demo_cover_landscape.jpg", "images/collection_cover.jpg"])
        XCTAssertEqual(Set(plan.practice), ["images/demo_p1001.jpg", "images/demo_p1001_empty_bubbles.jpg", "images/demo_p1001_s1.jpg",
                                            "audio/viejo_titulo_p1001_s1_b1_t1.mp3"])
        let planned = Set(plan.pages.flatMap(\.all) + plan.comicWide + plan.practice)
        XCTAssertFalse(planned.contains("images/demo_unused.jpg"), "a file nothing refers to isn't planned (fetched last, with no priority)")
        XCTAssertFalse(planned.contains { $0.contains("demo_p0") || $0.contains("demo_p1_s1_b1") }, "nothing is derived from the slug")
        XCTAssertEqual(try tree(comics.appendingPathComponent("comic-demo")).count, demoEntryNames.count, "and everything still lands")
    }

    // MARK: 2 First page first

    func testTheFirstPageDisplayImageThenItsAudioComeRightAfterComicJSON() async throws {
        let zip = demoZip()
        serve("comic-demo", zip)
        let d = downloader("comic-demo", internalId: "comic-demo", config: .init(concurrency: 1, maxChunkBytes: 6_000))
        try await d.run()
        let m = try await reader.readManifest(try await reader.resolve(bundleRoute: route("comic-demo")).url)
        let order = fetchOrder(m)
        XCTAssertEqual(Array(order.prefix(3)), ["comic.json", "images/demo_cover.jpg", "audio/viejo_titulo_p0_s1_b1_t1.mp3"],
                       "comic.json, the first page's image, its Spanish audio — before anything else")
        func at(_ n: String) -> Int { order.firstIndex(of: n) ?? Int.max }
        let coverRest = ["audio/viejo_titulo_p0_s1_b1_t1_en.mp3", "audio/words/la.mp3"]
        for n in coverRest { XCTAssertLessThan(at(n), at("images/demo_p1.jpg"), "\(n): the first page's interactions before the next page's image") }
        XCTAssertLessThan(at("images/demo_p1.jpg"), at("audio/viejo_titulo_p1_s1_b1_t1.mp3"))
        XCTAssertLessThan(at("audio/viejo_titulo_p1_s1_b1_t1.mp3"), at("images/demo_p1_empty_bubbles.jpg"), "next page: image, audio, then the rest")
        let p1 = ComicAssetPlan(comic: demoComic, entryNames: demoEntryNames).pages[1]
        for n in p1.all { XCTAssertLessThan(at(n), at("images/demo_p2.jpg"), "\(n): all of page 2 before page 3") }
        for n in ["images/demo_p2.jpg", "audio/viejo_titulo_p2_s1_b1_t1.mp3", "images/demo_p2_s1.jpg"] {
            XCTAssertLessThan(at(n), at("images/demo_cover_landscape.jpg"), "\(n): story pages before the comic-wide covers")
        }
        for n in ["images/demo_p1001.jpg", "audio/viejo_titulo_p1001_s1_b1_t1.mp3"] {
            XCTAssertGreaterThan(at(n), at("images/collection_cover.jpg"), "\(n): practice pages after everything planned")
        }
        XCTAssertEqual(order.last, "images/demo_unused.jpg", "the unplanned file goes last of all")
        XCTAssertEqual(Set(order).count, order.count, "nothing fetched twice")
    }

    // MARK: 3 Audio names from comic.json (a real export)

    func testPageAudioNamesComeFromComicJSONNotTheComicSlug() throws {
        // la_llegada's clips are still named after its old title, el_visitante.
        let dir = try extract(try fixture("la_llegada_trimmed"), into: root.appendingPathComponent("ref"))
        let comic = try XCTUnwrap(LocalComicStorage.loadComicIncludingPartial(from: dir))
        XCTAssertEqual(comic.id, "comic-la_llegada")
        let names = Set(try tree(dir).keys)
        let plan = ComicAssetPlan(comic: comic, entryNames: names)
        XCTAssertEqual(plan.pages[0].audio, ["audio/la_llegada_p0_s1_b1_t1.mp3"])
        XCTAssertEqual(plan.pages[1].audio, ["audio/el_visitante_p1_s1_b1_t1.mp3"],
                       "the sentences' audioUrl values that are in the bundle (the trimmed export kept one; an empty audioUrl is skipped)")
        XCTAssertTrue(plan.pages[1].interaction.contains("audio/el_visitante_p1_s1_b1_t1_en.mp3"))
        XCTAssertTrue(plan.pages[1].interaction.contains("audio/words/una.mp3"))
        let audio = plan.pages.flatMap(\.all).filter { $0.hasPrefix("audio/") }
        XCTAssertFalse(audio.contains { $0.hasPrefix("audio/la_llegada_p1") }, "no slug-derived audio name: \(audio)")
        // Every planned name exists in the bundle — nothing was guessed.
        for n in plan.pages.flatMap(\.all) + plan.comicWide + plan.practice { XCTAssertTrue(names.contains(n), n) }
        XCTAssertEqual(plan.pages[1].display, ["images/la_llegada_p1.jpg"])
        XCTAssertEqual(plan.pages[1].interaction.filter { $0.hasPrefix("images/") }, ["images/la_llegada_p1_s1.jpg"],
                       "the trimmed export lacks its blank bakes — they're simply not planned")
    }

    // MARK: 4–5 Changing page reprioritises what's still pending, refetches nothing

    func testChangingTheVisiblePageReprioritisesOutstandingFilesWithoutRefetching() async throws {
        let zip = demoZip()
        serve("comic-demo", zip)
        let m = try await reader.readManifest(try await reader.resolve(bundleRoute: route("comic-demo")).url)
        RangeStub.lock.withLock { RangeStub.ranges = []; RangeStub.holdObjectResponses = true }
        let d = downloader("comic-demo", internalId: "comic-demo", config: .init(concurrency: 1, maxChunkBytes: 6_000))
        let run = Task { try await d.run() }
        // Directory probe, then comic.json: let each through.
        try await waitUntil { RangeStub.heldCount == 1 }; RangeStub.releaseHeld()
        try await waitUntil { RangeStub.heldCount == 1 }; RangeStub.releaseHeld()
        // comic.json has landed and the cover image is in flight (held).
        try await waitUntil { RangeStub.heldCount == 1 }
        let planned = await d.currentPlan
        XCTAssertNotNil(planned)
        XCTAssertEqual(fetchOrder(m).last, "images/demo_cover.jpg")
        let before = RangeStub.objectRequests

        // The reader turns to page 3 while the cover is still coming.
        await d.focus(onPage: 2)
        let p = await d.currentPriorities
        XCTAssertEqual(p["images/demo_p2.jpg"], ComicAssetPlan.firstPageBase + ComicAssetPlan.displayLevel)
        XCTAssertGreaterThan(p["images/demo_p2.jpg"]!, p["images/demo_p1.jpg"]!, "page 3 now outranks page 2…")
        XCTAssertGreaterThan(p["images/demo_p1.jpg"]!, p["images/demo_cover.jpg"]!, "…which outranks the cover (previous page)")
        XCTAssertGreaterThan(p["images/demo_p2.jpg"]!, p["audio/viejo_titulo_p2_s1_b1_t1.mp3"]!)
        XCTAssertGreaterThan(p["audio/viejo_titulo_p2_s1_b1_t1.mp3"]!, p["images/demo_p2_s1.jpg"]!)
        XCTAssertEqual(RangeStub.objectRequests, before, "the request in flight wasn't cancelled or re-issued")

        RangeStub.releaseHeld()                                  // the cover arrives…
        try await waitUntil { RangeStub.heldCount == 1 }        // …and the next request is held
        XCTAssertEqual(fetchOrder(m).last, "images/demo_p2.jpg", "page 3's image is fetched next")
        RangeStub.holdObjectResponses = false
        RangeStub.releaseHeld()
        try await run.value

        let order = fetchOrder(m)
        XCTAssertEqual(Set(order).count, order.count, "nothing was fetched twice")
        XCTAssertEqual(order.filter { $0 == "comic.json" }.count, 1)
        XCTAssertEqual(try tree(comics.appendingPathComponent("comic-demo")).count, demoEntryNames.count)
        XCTAssertFalse(LocalComicStorage.isPartial(folder: comics.appendingPathComponent("comic-demo")))
    }

    func testAlreadyLandedFilesAreNeverRequestedAgainWhenPrioritiesChange() async throws {
        let zip = demoZip()
        serve("comic-demo", zip)
        // Cut the download after a few files, then resume it with the reader
        // on another page and asking for files that already landed.
        RangeStub.onObjectRequest = { RangeStub.lock.withLock { if RangeStub.objectRequests == 6 { RangeStub.failNextObjectRequests = 50 } } }
        let first = downloader("comic-demo", internalId: "comic-demo", config: .init(concurrency: 1, maxChunkBytes: 6_000, retriesPerChunk: 1, retryDelay: 0.01))
        do { try await first.run(); XCTFail("should have failed") } catch ProgressiveDownloader.DownloadError.network {}
        let folder = comics.appendingPathComponent("comic-demo")
        let landed = try tree(folder).keys.filter { !$0.hasPrefix(".") }
        XCTAssertTrue(landed.contains("comic.json") && landed.contains("images/demo_cover.jpg"), "\(landed)")

        RangeStub.lock.withLock { RangeStub.failNextObjectRequests = 0; RangeStub.onObjectRequest = nil; RangeStub.ranges = [] }
        let second = downloader("comic-demo", internalId: "comic-demo", config: .init(concurrency: 1, maxChunkBytes: 6_000))
        await second.focus(onPage: 1)
        await second.request(["images/demo_cover.jpg", "comic.json", "audio/viejo_titulo_p0_s1_b1_t1.mp3", "images/demo_p1.jpg"])
        let early = await second.currentPlan
        XCTAssertNil(early, "no plan before run — focus and requests are remembered")
        try await second.run()
        let m = try await reader.readManifest(try await reader.resolve(bundleRoute: route("comic-demo")).url)
        let order = fetchOrder(m)
        for n in landed { XCTAssertFalse(order.contains(n), "\(n) was already here") }
        XCTAssertEqual(Set(order).count, order.count)
        XCTAssertEqual(order.first, "images/demo_p1.jpg", "the requested page image that was still missing came first")
        XCTAssertEqual(try tree(folder), try tree(try extract(zip, into: root.appendingPathComponent("ref"))))
    }

    // MARK: 6–7 A missing page image: placeholder, then the page by itself

    func testAMissingPageImageShowsALoadingStateNotAFailure() throws {
        let id = "comic-la_llegada"
        let ref = try extract(try fixture("la_llegada_trimmed"), into: root.appendingPathComponent("ref"))
        let folder = try partialFolder(id, from: ref)
        let comic = try XCTUnwrap(LocalComicStorage.loadComicIncludingPartial(from: folder))
        let page = comic.pages.sorted { $0.pageNumber < $1.pageNumber }[1]

        XCTAssertNil(loader.loadImage(named: page.masterImage, forComic: id), "nothing on disk → nil, no throw")
        let c = pageContainer(page.masterImage, comicId: id)
        XCTAssertNil(c.imageView.image)
        XCTAssertTrue(c.isShowingPlaceholder)
        XCTAssertEqual(c.placeholderText, "Loading page…")
        // Offline: the placeholder says so instead of spinning.
        c.show(imageName: page.masterImage, comicId: id, pageKey: 0, forward: true, offline: true, assetStamp: 0)
        XCTAssertEqual(c.placeholderText, "Waiting for connection…")
        // Repeated updates and page turns with nothing on disk stay stable.
        for k in 0..<20 {
            c.show(imageName: k % 2 == 0 ? page.masterImage : comic.pages[0].masterImage, comicId: id, pageKey: k, forward: k % 3 == 0, offline: false, assetStamp: k)
        }
        XCTAssertTrue(c.isShowingPlaceholder)
        XCTAssertNil(c.imageView.image)
    }

    func testThePageAppearsByItselfWhenItsFileLands() async throws {
        let id = "comic-la_llegada"
        let ref = try extract(try fixture("la_llegada_trimmed"), into: root.appendingPathComponent("ref"))
        let folder = try partialFolder(id, from: ref, subfolders: ["images"])
        let comic = try XCTUnwrap(LocalComicStorage.loadComicIncludingPartial(from: folder))
        let page = comic.pages.sorted { $0.pageNumber < $1.pageNumber }[1]

        // The reader is on the page; the download is told, and asked for the image.
        let requests = Requests()
        availability.register(id, handle: requests.handle)
        availability.reader(id, isOnPage: 1)
        availability.request(image: page.masterImage, comicId: id)
        XCTAssertEqual(requests.focused, [1])
        XCTAssertEqual(requests.requested, ["images/\(page.masterImage).jpg", "images/\(page.masterImage).png"])

        let c = pageContainer(page.masterImage, comicId: id, stamp: availability.generation[id] ?? 0)
        XCTAssertTrue(c.isShowingPlaceholder)

        // The file lands (written whole, then the downloader reports it).
        try ProgressiveDownloader.writeAtomically(try Data(contentsOf: ref.appendingPathComponent("images/\(page.masterImage).jpg")),
                                                  to: folder.appendingPathComponent("images/\(page.masterImage).jpg"))
        availability.didLand(comicId: id, entryName: "images/\(page.masterImage).jpg")
        XCTAssertEqual(availability.generation[id] ?? 0, 0, "published after the batch interval, not synchronously")
        try await waitUntil { (self.availability.generation[id] ?? 0) == 1 }
        XCTAssertTrue(ComicAssetAvailability.includes(image: page.masterImage, comicId: id, in: availability.landed))
        XCTAssertFalse(ComicAssetAvailability.includes(image: page.masterImage, comicId: "comic-other", in: availability.landed), "per comic")

        // PageView passes the new stamp: the page swaps in, no page turn needed.
        c.show(imageName: page.masterImage, comicId: id, pageKey: 0, forward: true, offline: false, assetStamp: availability.generation[id]!)
        XCTAssertNotNil(c.imageView.image)
        XCTAssertFalse(c.isShowingPlaceholder)
        XCTAssertEqual(c.imageView.image?.size, UIImage(contentsOfFile: ref.appendingPathComponent("images/\(page.masterImage).jpg").path)?.size)

        // The SwiftUI ComicImage (panel art, hotspot slides, covers) renders
        // its placeholder for a missing file and lives on.
        let host = UIHostingController(rootView: ComicImage(imageName: "nothing_here", comicId: id).frame(width: 100, height: 100))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNotNil(host.view.window)
        window.isHidden = true
    }

    // MARK: 8 Fast page movement

    func testFastPageMovementReprioritisesSafely() async throws {
        let zip = demoZip()
        serve("comic-demo", zip)
        let d = downloader("comic-demo", internalId: "comic-demo", config: .init(concurrency: 2, maxChunkBytes: 6_000))
        let run = Task { try await d.run() }
        let mover = Task {
            for i in 0..<60 {
                await d.focus(onPage: [0, 2, 1, 2, 0][i % 5])
                if i % 7 == 0 { await d.request(["images/demo_p\(i % 3).jpg", "audio/words/una.mp3", "not/in/bundle.mp3"]) }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
        }
        try await run.value
        try await mover.value
        let folder = comics.appendingPathComponent("comic-demo")
        XCTAssertEqual(try tree(folder), try tree(try extract(zip, into: root.appendingPathComponent("ref"))))
        let m = try await reader.readManifest(try await reader.resolve(bundleRoute: route("comic-demo")).url)
        let order = fetchOrder(m)
        XCTAssertEqual(Set(order).count, order.count, "no file fetched twice")
        XCTAssertEqual(order.count, m.entries.filter(\.isExtracted).count)
        let entryRequests = RangeStub.ranges.filter { $0.start != nil }
        let spans = m.spans()
        XCTAssertEqual(entryRequests.reduce(0) { $0 + $1.end - $1.start! + 1 }, m.entries.filter(\.isExtracted).reduce(0) { $0 + spans[$1]!.count }, "no byte fetched twice")
    }

    // MARK: 9–10 Audio that hasn't arrived

    func testMissingAudioRequestsTheExactClipAndPlaysWhenItLands() async throws {
        let id = "comic-la_llegada"
        let ref = try extract(try fixture("la_llegada_trimmed"), into: root.appendingPathComponent("ref"))
        let folder = try partialFolder(id, from: ref, subfolders: ["audio"])
        let requests = Requests()
        availability.register(id, handle: requests.handle)

        let audio = audioManager(for: id)
        let clip = "el_visitante_p1_s1_b1_t1"   // the comic's own name for the sentence
        audio.play(clip, enableHighlighting: true)
        XCTAssertEqual(audio.waitingFor, clip, "the tap is remembered")
        XCTAssertTrue(audio.isLoading, "…and shown as loading")
        XCTAssertFalse(audio.isPlaying)
        XCTAssertEqual(requests.requested, ["audio/\(clip).mp3"], "exactly that clip is asked for")

        // Another tap first: the earlier wait is dropped (consistent with the user's latest tap).
        audio.play("words/una")
        XCTAssertEqual(audio.waitingFor, "words/una")
        audio.play(clip, enableHighlighting: true)

        // The clip lands.
        try ProgressiveDownloader.writeAtomically(try Data(contentsOf: ref.appendingPathComponent("audio/\(clip).mp3")),
                                                  to: folder.appendingPathComponent("audio/\(clip).mp3"))
        availability.didLand(comicId: id, entryName: "audio/\(clip).mp3")
        try await waitUntil { audio.waitingFor == nil }
        XCTAssertGreaterThan(audio.duration, 0, "the clip is loaded and playing")
        XCTAssertTrue(audio.isSentencePlayback, "with the highlighting the tap asked for")
        XCTAssertFalse(audio.isLoading)

        // A stop while waiting cancels the pending play.
        audio.play("el_visitante_p1_s3")
        XCTAssertEqual(audio.waitingFor, "el_visitante_p1_s3")
        audio.stop()
        XCTAssertNil(audio.waitingFor)
        XCTAssertFalse(audio.isLoading)
        try ProgressiveDownloader.writeAtomically(Data(), to: folder.appendingPathComponent("audio/el_visitante_p1_s3.mp3"))
        availability.didLand(comicId: id, entryName: "audio/el_visitante_p1_s3.mp3")
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertFalse(audio.isPlaying, "nothing plays from a cancelled tap")
    }

    func testAnotherComicsClipWithTheSameNameIsNeverSubstituted() async throws {
        // Comic B, complete, has the clip; comic A, downloading, doesn't yet.
        let zip = try fixture("la_llegada_trimmed")
        let b = "comic-b"
        try extract(zip, into: comics.appendingPathComponent(b))
        let a = "comic-a"
        let folderA = comics.appendingPathComponent(a)
        try FileManager.default.createDirectory(at: folderA.appendingPathComponent("audio"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: LocalComicStorage.partialMarkerURL(in: folderA))
        let requests = Requests()
        availability.register(a, handle: requests.handle)

        let audio = audioManager(for: a)
        let clip = "el_visitante_p1_s1_b1_t1"
        audio.play(clip)
        XCTAssertEqual(audio.waitingFor, clip, "A's clip is waited for")
        XCTAssertEqual(audio.duration, 0, "B's same-named file was NOT played")
        XCTAssertEqual(requests.requested, ["audio/\(clip).mp3"])

        // With the marker alone (download not running this moment — e.g. offline), still no substitution.
        availability.unregister(a)
        audio.stop()
        audio.play(clip)
        XCTAssertEqual(audio.waitingFor, clip)
        XCTAssertEqual(audio.duration, 0)

        // Reading B itself works as before.
        audio.stop()
        audio.activeComicId = b
        audio.play(clip)
        XCTAssertNil(audio.waitingFor)
        XCTAssertGreaterThan(audio.duration, 0)
    }

    // MARK: 11 Panel / bubble / hotspot assets recover when they land

    func testMissingPanelBubbleAndHotspotAssetsRecoverWhenTheyLand() async throws {
        let id = "comic-la_llegada"
        let ref = try extract(try fixture("la_llegada_trimmed"), into: root.appendingPathComponent("ref"))
        let comic = try XCTUnwrap(LocalComicStorage.loadComicIncludingPartial(from: ref))
        let page = comic.pages.sorted { $0.pageNumber < $1.pageNumber }[1]
        let panel = page.panels.sorted { $0.panelOrder < $1.panelOrder }[0]
        let bubble = panel.bubbles[0]
        let nb = CGRect(x: bubble.positionX, y: bubble.positionY, width: bubble.width, height: bubble.height)

        // What a complete comic gives for the bubble highlight (may legitimately be nil).
        try FileManager.default.copyItem(at: ref, to: comics.appendingPathComponent("comic-complete"))
        let expected = BubbleFill.overlay(maskSource: page.masterImage, inkSource: page.masterImage, comicId: "comic-complete",
                                          bubble: nb, color: .green, cacheKey: "irt-complete")
        let expectedMask = BubbleFill.interiorMask(maskSource: page.masterImage, comicId: "comic-complete", bubble: nb, cacheKey: "irt-complete-mask")

        // The partial comic: comic.json only.
        let folder = try partialFolder(id, from: ref, subfolders: ["images"])

        // Panel art (PanelView's ComicImage), the bubble fill and interior mask
        // (the green highlight / practice reveal / arrival hand), hotspot art:
        // all "nothing yet", none throw.
        XCTAssertNil(loader.loadImage(named: panel.artworkImage, forComic: id))
        XCTAssertNil(BubbleFill.overlay(maskSource: page.masterImage, inkSource: page.masterImage, comicId: id, bubble: nb, color: .green, cacheKey: "irt-partial"))
        XCTAssertNil(BubbleFill.interiorMask(maskSource: page.masterImage, comicId: id, bubble: nb, cacheKey: "irt-partial-mask"))
        XCTAssertNil(loader.loadImage(named: "some_hotspot_slide", forComic: id))

        // The plan puts these with the page they belong to, so they're on their way.
        let plan = ComicAssetPlan(comic: comic, entryNames: Set(try tree(ref).keys))
        XCTAssertTrue(plan.pages[1].interaction.contains("images/\(panel.artworkImage).jpg"))

        // They land.
        for name in [page.masterImage, panel.artworkImage] {
            try ProgressiveDownloader.writeAtomically(try Data(contentsOf: ref.appendingPathComponent("images/\(name).jpg")),
                                                      to: folder.appendingPathComponent("images/\(name).jpg"))
            availability.didLand(comicId: id, entryName: "images/\(name).jpg")
        }
        try await waitUntil { (self.availability.generation[id] ?? 0) == 1 }
        XCTAssertEqual(Set(availability.landed.map(\.entryName)), ["images/\(page.masterImage).jpg", "images/\(panel.artworkImage).jpg"], "one batch")

        // The same calls now give what the complete comic gives (the loader
        // didn't cache the miss).
        XCTAssertNotNil(loader.loadImage(named: panel.artworkImage, forComic: id))
        let after = BubbleFill.overlay(maskSource: page.masterImage, inkSource: page.masterImage, comicId: id, bubble: nb, color: .green, cacheKey: "irt-partial")
        XCTAssertEqual(after == nil, expected == nil)
        XCTAssertEqual(after?.region, expected?.region)
        let afterMask = BubbleFill.interiorMask(maskSource: page.masterImage, comicId: id, bubble: nb, cacheKey: "irt-partial-mask")
        XCTAssertEqual(afterMask == nil, expectedMask == nil)
        XCTAssertEqual(afterMask?.bounds, expectedMask?.bounds)
    }

    // MARK: 12–13 Network loss and return

    func testNetworkLossWhileWaitingLeavesTheReaderStableAndItsReturnBringsTheFileIn() async throws {
        let zip = try fixture("la_llegada_trimmed")
        let id = "comic-la_llegada"
        serve("comic-x", zip)
        // One file at a time; the connection goes once comic.json and the
        // cover (requests 2 and 3) have landed.
        RangeStub.onObjectRequest = { RangeStub.lock.withLock { if RangeStub.objectRequests == 3 { RangeStub.failNextObjectRequests = 50 } } }
        let (s, st) = store(config: .init(concurrency: 1, maxChunkBytes: 6_000, retriesPerChunk: 1, retryDelay: 0.01))
        s.wholeBundleDownloaderForTesting = { _, _ in XCTFail("whole-zip path must not run"); return "" }
        await s.downloadComic(storeComic(id, internalId: "comic-x"))
        guard case .failed = s.downloadState(for: id) else { return XCTFail("expected a failed, resumable download") }
        let folder = comics.appendingPathComponent(id)
        XCTAssertTrue(st.isPartiallyDownloaded(id))
        XCTAssertFalse(availability.isDownloading(id), "the download isn't running")
        let comic = try XCTUnwrap(LocalComicStorage.loadComicIncludingPartial(from: folder))
        let page = comic.pages.sorted { $0.pageNumber < $1.pageNumber }[1]

        // The reader (opened on the partial comic by the test-only path) waits:
        // page placeholder saying there's no connection, a tapped clip held.
        availability.setNetworkReachable(false)
        let c = pageContainer(page.masterImage, comicId: id, offline: !availability.isNetworkReachable)
        XCTAssertTrue(c.isShowingPlaceholder)
        XCTAssertEqual(c.placeholderText, "Waiting for connection…")
        let audio = audioManager(for: id)
        let clip = "el_visitante_p1_s1_b1_t1"
        audio.play(clip, enableHighlighting: true)
        XCTAssertEqual(audio.waitingFor, clip, "a missing clip of a partial comic is waited for even with no download running")
        availability.reader(id, isOnPage: 1)   // no download to tell — a no-op, not a crash
        availability.request(image: page.masterImage, comicId: id)

        // The network comes back: what the app wires up on launch.
        RangeStub.lock.withLock { RangeStub.failNextObjectRequests = 0; RangeStub.onObjectRequest = nil }
        availability.onNetworkReturned = { Task { await s.resumePartialDownloads(retryingFailed: true) } }
        availability.setNetworkReachable(true)
        try await waitUntil { s.downloadState(for: id) == .downloaded }
        try await waitUntil { audio.waitingFor == nil }
        XCTAssertGreaterThan(audio.duration, 0, "the held tap played once its clip arrived")
        XCTAssertTrue(audio.isSentencePlayback)
        c.show(imageName: page.masterImage, comicId: id, pageKey: 0, forward: true, offline: false, assetStamp: availability.generation[id]!)
        XCTAssertNotNil(c.imageView.image, "the page is in")
        XCTAssertFalse(c.isShowingPlaceholder)
        XCTAssertFalse(availability.isDownloading(id), "unregistered once complete")
        await st.loadDownloadedComics()
        XCTAssertTrue(st.isDownloaded(id))
    }

    // MARK: 14–15 Complete comics, with and without a network

    func testAFullyDownloadedComicBehavesExactlyAsBeforeOnlineOrOffline() async throws {
        let zip = try fixture("la_llegada_trimmed")
        let id = "comic-la_llegada"
        try extract(zip, into: comics.appendingPathComponent(id))
        let st = LocalComicStorage(comicsDirectory: comics)
        await st.loadDownloadedComics()
        let comic = try XCTUnwrap(st.downloadedComics.first { $0.id == id })
        let page = comic.pages.sorted { $0.pageNumber < $1.pageNumber }[1]
        // A download of some other comic is running — it must hear nothing about this one.
        let requests = Requests()
        availability.register("comic-other", handle: requests.handle)

        for offline in [false, true] {
            availability.setNetworkReachable(!offline)
            let c = pageContainer(page.masterImage, comicId: id, offline: !availability.isNetworkReachable)
            XCTAssertNotNil(c.imageView.image)
            XCTAssertFalse(c.isShowingPlaceholder)
            c.show(imageName: comic.pages[0].masterImage, comicId: id, pageKey: 1, forward: true, offline: offline, assetStamp: 0)
            XCTAssertNotNil(c.imageView.image, "page turn")
            XCTAssertFalse(c.isShowingPlaceholder)

            let audio = audioManager(for: id)
            audio.play("el_visitante_p1_s1_b1_t1", enableHighlighting: true)
            XCTAssertNil(audio.waitingFor)
            XCTAssertGreaterThan(audio.duration, 0)
            audio.play("words/una")
            XCTAssertGreaterThan(audio.duration, 0, "word audio by its words/ name")
            audio.stop()
        }
        XCTAssertTrue(requests.requested.isEmpty && requests.focused.isEmpty, "nothing was asked of any download")
        XCTAssertFalse(availability.isDownloading(id))
        XCTAssertTrue(st.isWholeComicAvailable(id))
        XCTAssertTrue(st.isCompleteOnDisk(id) && st.existsOnDevice(id) && st.isDownloaded(id))
        availability.reader(id, isOnPage: 1)   // the reader tells it anyway; nothing to do
        availability.request(audio: "x", comicId: id)
        XCTAssertTrue(requests.requested.isEmpty)
    }

    // MARK: 16 Whole-comic modes stay gated on completeness

    func testWholeComicModesRemainGatedByCompleteness() async throws {
        let zip = try fixture("la_ayuda_trimmed")
        serve("comic-y", zip)
        let id = "comic-la_ayuda_viene_en_camino"
        let st = LocalComicStorage(comicsDirectory: comics)
        XCTAssertFalse(st.isWholeComicAvailable(id), "not on the device")
        try extract(zip, into: comics.appendingPathComponent(id))
        XCTAssertTrue(st.isWholeComicAvailable(id), "complete")
        // Every file present but the marker still on (the download hasn't
        // declared itself finished): not ready for practice/tests.
        try await markPartial(id, internalId: "comic-y")
        XCTAssertFalse(st.isWholeComicAvailable(id))
        XCTAssertFalse(st.isCompleteOnDisk(id))
        try FileManager.default.removeItem(at: LocalComicStorage.partialMarkerURL(in: comics.appendingPathComponent(id)))
        XCTAssertTrue(st.isWholeComicAvailable(id))
    }

    // MARK: 17 Partial comics stay out of normal navigation

    func testAPartialComicIsStillNotExposedThroughNormalNavigation() async throws {
        let zip = try fixture("la_llegada_trimmed")
        serve("comic-x", zip)
        let id = "comic-la_llegada"
        try extract(zip, into: comics.appendingPathComponent(id))
        try await markPartial(id, internalId: "comic-x")
        let (s, st) = store()
        await st.loadDownloadedComics()
        XCTAssertFalse(st.isDownloaded(id))
        XCTAssertFalse(st.existsOnDevice(id))
        XCTAssertFalse(st.isCompleteOnDisk(id))
        XCTAssertTrue(st.isPartiallyDownloaded(id))
        XCTAssertTrue(st.libraryItems.isEmpty)
        XCTAssertEqual(s.downloadState(for: id), .notDownloaded)
        XCTAssertNil(s.recordedBundleVersion(for: id))
        // The only way in is the test/debug loader, which the app doesn't call.
        XCTAssertNotNil(LocalComicStorage.loadComicIncludingPartial(from: comics.appendingPathComponent(id)))
        XCTAssertNil(LocalComicStorage.loadComicIncludingPartial(from: comics.appendingPathComponent("nope")))
    }

    // MARK: Landed events are published only after the rename

    func testLandedIsReportedOnlyOnceTheFileIsInPlace() async throws {
        serve("comic-demo", demoZip())
        let folder = comics.appendingPathComponent("comic-demo")
        let seen = Requests()
        let d = downloader("comic-demo", internalId: "comic-demo", config: .init(concurrency: 3, maxChunkBytes: 6_000), onLanded: { name in
            // At the moment of the report the file is whole under its final name.
            let attrs = try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(name).path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? -1
            seen.lock.withLock { seen.requested.append(size > 0 ? name : "MISSING:\(name)") }
        })
        try await d.run()
        let reported = seen.lock.withLock { seen.requested }
        XCTAssertFalse(reported.contains { $0.hasPrefix("MISSING:") }, "\(reported.filter { $0.hasPrefix("MISSING:") })")
        XCTAssertEqual(Set(reported), demoEntryNames, "every file reported exactly once")
        XCTAssertEqual(reported.count, demoEntryNames.count)
        XCTAssertFalse(try tree(folder).keys.contains { $0.contains(".tmp-") })
    }
}
