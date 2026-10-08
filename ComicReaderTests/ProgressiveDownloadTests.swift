import XCTest
@testable import ComicReader

// MARK: - A stand-in for the /bundle route and the CDN

/// Serves bundles the way production does, in-process: the route 302s to an
/// object URL whose key carries the version; the object answers single byte
/// ranges with 206 + Content-Range, multi-range with 416, HEAD with 403.
/// Knobs make it ignore ranges, drop requests, expire links, or change the
/// bundle between resolutions.
final class RangeStub: URLProtocol {
    struct Object { var data: Data; var version: String? }

    static let lock = NSLock()
    nonisolated(unsafe) static var objects: [String: Object] = [:]     // internal comic id → current bundle
    nonisolated(unsafe) static var archive: [String: Data] = [:]       // object key → bytes (old versions stay)
    nonisolated(unsafe) static var ignoreRange = false                 // answer 200 + whole body
    nonisolated(unsafe) static var failNextObjectRequests = 0          // connection errors
    nonisolated(unsafe) static var expireAfter: Int? = nil             // object requests per resolution before 403
    nonisolated(unsafe) static var requestsSinceResolve = 0
    nonisolated(unsafe) static var resolves = 0
    nonisolated(unsafe) static var ranges: [(id: String, start: Int?, end: Int)] = []
    nonisolated(unsafe) static var objectRequests = 0
    nonisolated(unsafe) static var onObjectRequest: (() -> Void)?
    /// Hold object responses back until `releaseHeld()` — lets a test change
    /// priorities while requests are in flight, deterministically.
    nonisolated(unsafe) static var holdObjectResponses = false
    nonisolated(unsafe) static var held: [() -> Void] = []

    static let base = "https://stub.test"

    static func reset() {
        lock.withLock {
            objects = [:]; archive = [:]; ignoreRange = false; failNextObjectRequests = 0; expireAfter = nil
            requestsSinceResolve = 0; resolves = 0; ranges = []; objectRequests = 0; onObjectRequest = nil
            holdObjectResponses = false; held = []
        }
    }

    static var heldCount: Int { lock.withLock { held.count } }

    /// Deliver every held response (in arrival order).
    static func releaseHeld() {
        let h = lock.withLock { () -> [() -> Void] in let x = held; held = []; return x }
        h.forEach { $0() }
    }

    static func configuration() -> URLSessionConfiguration {
        let c = BundleRangeReader.defaultConfiguration()
        c.protocolClasses = [RangeStub.self]
        c.waitsForConnectivity = false
        return c
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "stub.test" || request.url?.host == "cdn.stub.test"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let client else { return }
        let path = url.path
        if url.host == "stub.test" {
            // /api/reader/comics/<id>/bundle → 302 to the object
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count == 5, parts[4] == "bundle" else { return respond(404, Data()) }
            let id = parts[3]
            let obj = Self.lock.withLock { () -> Object? in Self.resolves += 1; Self.requestsSinceResolve = 0; return Self.objects[id] }
            guard let obj else { return respond(404, Data()) }
            let key = obj.version.map { "bundles/\(id)-\($0).zip" } ?? "bundles/\(id).zip"
            Self.lock.withLock { Self.archive[key] = obj.data }   // the object stays fetchable by its key, as on the CDN
            let location = "https://cdn.stub.test/\(key)?X-Amz-Signature=sig"
            // A plain 302 response (the reader declines redirects and reads Location).
            respond(302, Data(), headers: ["Location": location])
            return
        }
        // The object: bundles/<id>[-<version>].zip
        let key = String(path.dropFirst(1))
        var data: Data?
        var drop = false, expired = false
        Self.lock.withLock {
            data = Self.archive[key]
            Self.objectRequests += 1
            Self.requestsSinceResolve += 1
            if Self.failNextObjectRequests > 0 { Self.failNextObjectRequests -= 1; drop = true }
            if let n = Self.expireAfter, Self.requestsSinceResolve > n { expired = true }
        }
        Self.onObjectRequest?()
        let deliver = objectResponse(key: key, data: data, drop: drop, expired: expired)
        let hold = Self.lock.withLock { () -> Bool in
            if Self.holdObjectResponses { Self.held.append(deliver); return true }
            return false
        }
        if !hold { deliver() }
    }

    /// The object's answer, as a closure so it can be delivered later.
    private func objectResponse(key: String, data: Data?, drop: Bool, expired: Bool) -> () -> Void {
        guard let client else { return {} }
        if drop { return { client.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)) } }
        if request.httpMethod == "HEAD" || expired { return { self.respond(403, Data()) } }
        guard let data else { return { self.respond(404, Data()) } }
        let obj = Object(data: data, version: nil)
        guard let range = request.value(forHTTPHeaderField: "Range"), !Self.ignoreRange else {
            return { self.respond(200, obj.data, headers: ["Accept-Ranges": "bytes", "Content-Length": "\(obj.data.count)"]) }
        }
        guard range.hasPrefix("bytes="), !range.contains(",") else { return { self.respond(416, Data()) } }
        let spec = range.dropFirst(6)
        let total = obj.data.count
        var start: Int?, end: Int
        if spec.hasPrefix("-") {
            let n = Int(spec.dropFirst())!
            end = min(n, total); start = nil
            let s = total - end
            Self.lock.withLock { Self.ranges.append((key, nil, n)) }
            return { self.respond(206, obj.data.subdata(in: s..<total), headers: ["Accept-Ranges": "bytes", "Content-Range": "bytes \(s)-\(total - 1)/\(total)"]) }
        }
        let bounds = spec.split(separator: "-", omittingEmptySubsequences: false)
        start = Int(bounds[0])!; end = bounds.count > 1 && !bounds[1].isEmpty ? Int(bounds[1])! : total - 1
        Self.lock.withLock { Self.ranges.append((key, start, end)) }
        guard let s = start, s < total else { return { self.respond(416, Data()) } }
        let e = min(end, total - 1)
        return { self.respond(206, obj.data.subdata(in: s..<(e + 1)), headers: ["Accept-Ranges": "bytes", "Content-Range": "bytes \(s)-\(e)/\(total)"]) }
    }

    private func respond(_ status: Int, _ body: Data, headers: [String: String] = [:]) {
        guard let url = request.url, let client else { return }
        let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: body)
        client.urlProtocolDidFinishLoading(self)
    }
}

// MARK: - A zip writer for synthetic archives

/// Writes STORED zips the way archiver does (local headers, central
/// directory, EOCD; no data descriptors), with hooks to poison them.
struct TestZip {
    var entries: [(name: String, data: Data)] = []
    /// Per-entry overrides of the central-directory method / flags / sizes.
    var method: [String: UInt16] = [:]
    var flags: [String: UInt16] = [:]
    var zip64Sizes: Set<String> = []

    func build() -> Data {
        var out = Data(), cd = Data()
        func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
        func le32(_ v: UInt32) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]) }
        for e in entries {
            let name = Data(e.name.utf8), crc = CRC32.checksum(e.data), m = Int(method[e.name] ?? 0), f = Int(flags[e.name] ?? 0)
            let off = out.count
            let n = UInt32(e.data.count)
            var local = Data([0x50, 0x4B, 0x03, 0x04])
            for part in [le16(20), le16(f), le16(m), le16(0), le16(0), le32(crc), le32(n), le32(n), le16(name.count), le16(0)] { local += part }
            out += local; out += name; out += e.data
            let size: UInt32 = zip64Sizes.contains(e.name) ? 0xFFFF_FFFF : n
            var central = Data([0x50, 0x4B, 0x01, 0x02])
            for part in [le16(20), le16(20), le16(f), le16(m), le16(0), le16(0), le32(crc), le32(size), le32(size), le16(name.count), le16(0), le16(0), le16(0), le16(0), le32(0), le32(UInt32(off))] { central += part }
            cd += central; cd += name
        }
        let cdOff = out.count
        out += cd
        var end = Data([0x50, 0x4B, 0x05, 0x06])
        for part in [le16(0), le16(0), le16(entries.count), le16(entries.count), le32(UInt32(cd.count)), le32(UInt32(cdOff)), le16(0)] { end += part }
        out += end
        return out
    }
}

// MARK: - Tests

@MainActor
final class ProgressiveDownloadTests: XCTestCase {
    private var root: URL!
    private var comics: URL!
    private var reader: BundleRangeReader!

    override func setUp() async throws {
        try await super.setUp()
        RangeStub.reset()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pdt-\(UUID().uuidString)", isDirectory: true)
        comics = root.appendingPathComponent("Comics", isDirectory: true)
        try FileManager.default.createDirectory(at: comics, withIntermediateDirectories: true)
        reader = BundleRangeReader(configuration: RangeStub.configuration())
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        RangeStub.reset()
        try await super.tearDown()
    }

    // The two real-format fixtures: trimmed exports zipped by the production
    // tool (archiver, level 0), so headers and layout match the CDN's.
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: ProgressiveDownloadTests.self).url(forResource: name, withExtension: "zip", subdirectory: "Fixtures")
                                ?? Bundle(for: ProgressiveDownloadTests.self).url(forResource: name, withExtension: "zip"))
        return try Data(contentsOf: url)
    }

    /// The id inside each fixture's comic.json — the folder a download ends up in.
    private func comicId(_ fixture: String) -> String { fixture == "la_llegada_trimmed" ? "comic-la_llegada" : "comic-la_ayuda_viene_en_camino" }
    private func realComicJSON() throws -> Data { try Data(contentsOf: reference(for: fixture("la_llegada_trimmed")).appendingPathComponent("comic.json")) }

    private func serve(_ id: String, _ data: Data, version: String? = "v1") {
        RangeStub.lock.withLock { RangeStub.objects[id] = .init(data: data, version: version) }
    }
    private func route(_ id: String) -> URL { URL(string: "\(RangeStub.base)/api/reader/comics/\(id)/bundle")! }

    private func downloader(_ comicId: String, internalId: String, config: ProgressiveDownloader.Configuration = .init(),
                            progress: @escaping @Sendable (Double) -> Void = { _ in }) -> ProgressiveDownloader {
        ProgressiveDownloader(comicId: comicId, bundleRoute: route(internalId), downloadUrl: "/api/reader/comics/\(internalId)",
                              fileSizeMB: 1, comicsDirectory: comics, reader: reader, configuration: config, onProgress: progress)
    }

    /// What today's path produces for the same zip: ZIPExtractor's output.
    private func reference(for zip: Data) throws -> URL {
        let z = root.appendingPathComponent("ref-\(UUID().uuidString).zip"), dir = root.appendingPathComponent("ref-\(UUID().uuidString)", isDirectory: true)
        try zip.write(to: z)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try ZIPExtractor.extract(zipFileURL: z, to: dir)
        return dir
    }

    /// Relative path → bytes, for every file under a folder.
    private func tree(_ dir: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey])!
        for case let f as URL in e where (try f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            out[String(f.path.dropFirst(dir.path.count + 1))] = try Data(contentsOf: f)
        }
        return out
    }

    private func store(storage: LocalComicStorage? = nil, defaults: UserDefaults? = nil) -> (ComicStoreService, LocalComicStorage) {
        let st = storage ?? LocalComicStorage(comicsDirectory: comics)
        let d = defaults ?? UserDefaults(suiteName: "pdt.\(UUID().uuidString)")!
        let s = ComicStoreService(localStorage: st, baseURL: RangeStub.base, defaults: d, rangeReader: reader,
                                  progressiveConfiguration: .init(retryDelay: 0.01))
        return (s, st)
    }

    private func storeComic(_ id: String, internalId: String, version: String? = "v1") -> StoreComic {
        StoreComic(id: id, title: id, description: "", coverThumbnailUrl: "", level: "beginner", totalPages: 2, estimatedMinutes: 1,
                   language: "es", fileSizeMB: 1, version: "1.0", bundleVersion: version, downloadUrl: "/api/reader/comics/\(internalId)")
    }

    // MARK: 1–2 Reading the directory

    func testDirectoryIsReadFromTheSuffixWhenItFits() async throws {
        serve("comic-a", try fixture("la_llegada_trimmed"))
        let resolved = try await reader.resolve(bundleRoute: route("comic-a"))
        XCTAssertEqual(resolved.bundleVersion, "v1")
        let m = try await reader.readManifest(resolved.url)
        XCTAssertEqual(RangeStub.ranges.count, 1, "one suffix request covers EOCD and directory")
        XCTAssertNil(RangeStub.ranges[0].start)
        XCTAssertTrue(m.entries.contains { $0.name == "comic.json" })
        XCTAssertTrue(m.entries.allSatisfy { $0.method == 0 })
        XCTAssertEqual(m.totalBytes, try fixture("la_llegada_trimmed").count)
        XCTAssertEqual(Set(m.entries.filter(\.isExtracted).map(\.name)), Set(try tree(reference(for: fixture("la_llegada_trimmed"))).keys))
    }

    func testDirectoryLargerThanTheSuffixIsFetchedSeparately() async throws {
        var z = TestZip()
        z.entries.append(("comic.json", Data("{\"id\":\"comic-big\",\"pages\":[]}".utf8)))
        for i in 0..<1500 { z.entries.append(("audio/words/a-rather-long-file-name-to-pad-the-directory-\(i).mp3", Data(repeating: UInt8(i & 0xFF), count: 10))) }
        let data = z.build()
        serve("comic-big", data)
        let resolved = try await reader.resolve(bundleRoute: route("comic-big"))
        let m = try await reader.readManifest(resolved.url)
        XCTAssertEqual(m.entries.count, 1501)
        XCTAssertEqual(RangeStub.ranges.count, 2, "suffix for the EOCD, then the directory itself")
        XCTAssertNotNil(RangeStub.ranges[1].start)
        XCTAssertEqual(m.centralDirectoryOffset, RangeStub.ranges[1].start)
    }

    // MARK: 3–5 What lands

    func testComicJSONAndEveryAssetLandByteIdentical() async throws {
        for name in ["la_llegada_trimmed", "la_ayuda_trimmed"] {
            RangeStub.reset()
            let zip = try fixture(name)
            serve("int-\(name)", zip)
            let d = downloader("comic-\(name)", internalId: "int-\(name)")
            try await d.run()
            let got = try tree(d.folder), want = try tree(reference(for: zip))
            XCTAssertEqual(got.keys.sorted(), want.keys.sorted(), name)
            for (path, bytes) in want { XCTAssertEqual(got[path], bytes, "\(name): \(path)") }
            XCTAssertFalse(got.keys.contains(where: { $0.hasPrefix(".") || $0.contains("/.") }), "no marker or temp files left")
            let json = try JSONDecoder().decode(ComicJSON.self, from: try XCTUnwrap(got["comic.json"]))
            XCTAssertEqual(json.pages.count, 2)
            XCTAssertTrue(got.keys.contains("images/\(json.pages[1].masterImage).jpg"))
        }
    }

    func testDeflatedEntriesAreInflated() async throws {
        // A stored zip with one deflated entry (raw deflate of "hello" repeated).
        let plain = Data(repeating: 0x41, count: 4000)
        let deflated = try XCTUnwrap(compress(plain))
        var z = TestZip()
        z.entries = [("comic.json", try realComicJSON()), ("images/x.jpg", deflated)]
        z.method["images/x.jpg"] = 8
        var data = z.build()
        // Patch the uncompressed size + crc the writer put in for the deflated entry.
        data = patchSizes(data, name: "images/x.jpg", compressed: deflated.count, uncompressed: plain.count, crc: CRC32.checksum(plain))
        serve("comic-d", data)
        let d = downloader("comic-d", internalId: "comic-d")
        try await d.run()
        XCTAssertEqual(try Data(contentsOf: d.folder.appendingPathComponent("images/x.jpg")), plain)
    }

    // MARK: 6–7 Requests

    func testOnlySingleRangesAreRequestedAndAdjacentEntriesAreCoalesced() async throws {
        let zip = try fixture("la_ayuda_trimmed")
        serve("comic-a", zip)
        let d = downloader("comic-a", internalId: "comic-a", config: .init(concurrency: 2, maxChunkBytes: 600_000))
        try await d.run()
        let m = try await reader.readManifest(try await reader.resolve(bundleRoute: route("comic-a")).url)
        let files = m.entries.filter(\.isExtracted).count
        let entryRequests = RangeStub.ranges.filter { $0.start != nil }
        XCTAssertLessThan(entryRequests.count, files, "adjacent entries ride in one request")
        XCTAssertGreaterThan(entryRequests.count, 1, "the chunk cap splits the bundle")
        for r in entryRequests { XCTAssertLessThanOrEqual(r.end - r.start! + 1, 600_000 + 65_536, "a chunk stays near the cap") }
        // Every byte of every entry was requested exactly once.
        let spans = m.spans()
        var covered = 0
        for e in m.entries where e.isExtracted {
            let s = spans[e]!
            XCTAssertEqual(entryRequests.filter { $0.start! <= s.lowerBound && $0.end >= s.upperBound - 1 }.count, 1, e.name)
            covered += s.count
        }
        XCTAssertEqual(entryRequests.reduce(0) { $0 + $1.end - $1.start! + 1 }, covered, "no byte fetched twice")
    }

    // MARK: 8–10 Interruption and resume

    func testAnInterruptedDownloadResumesWithoutRefetchingWhatLanded() async throws {
        let zip = try fixture("la_llegada_trimmed")
        serve("comic-a", zip)
        // Let a few requests through, then cut the connection for good (more
        // failures than retries).
        RangeStub.onObjectRequest = { RangeStub.lock.withLock { if RangeStub.objectRequests == 4 { RangeStub.failNextObjectRequests = 50 } } }
        let first = downloader("comic-a", internalId: "comic-a", config: .init(concurrency: 1, maxChunkBytes: 200_000, retriesPerChunk: 2, retryDelay: 0.01))
        do { try await first.run(); XCTFail("should have failed") } catch ProgressiveDownloader.DownloadError.network { }
        let folder = comics.appendingPathComponent("comic-a")
        XCTAssertTrue(LocalComicStorage.isPartial(folder: folder), "marker stays")
        let landedBefore = try tree(folder).filter { !$0.key.hasPrefix(".") }
        XCTAssertFalse(landedBefore.isEmpty, "some files landed before the cut")
        XCTAssertFalse(try tree(folder).keys.contains { $0.contains(".tmp-") }, "no half-written files")

        RangeStub.lock.withLock { RangeStub.failNextObjectRequests = 0; RangeStub.onObjectRequest = nil; RangeStub.ranges = [] }
        let second = downloader("comic-a", internalId: "comic-a", config: .init(concurrency: 1, maxChunkBytes: 200_000))
        try await second.run()
        XCTAssertFalse(LocalComicStorage.isPartial(folder: folder))
        let want = try tree(reference(for: zip))
        XCTAssertEqual(try tree(folder), want)
        // Nothing that had landed was asked for again.
        let m = try await reader.readManifest(try await reader.resolve(bundleRoute: route("comic-a")).url)
        let spans = m.spans()
        for (path, _) in landedBefore {
            let e = m.entries.first { $0.name == path }!
            XCTAssertFalse(RangeStub.ranges.contains { $0.start != nil && $0.start! <= spans[e]!.lowerBound && $0.end >= spans[e]!.upperBound - 1 }, "\(path) fetched again")
        }
    }

    func testARelaunchResumesThePersistedPartialDownload() async throws {
        let zip = try fixture("la_ayuda_trimmed")
        serve("comic-a", zip)
        RangeStub.onObjectRequest = { RangeStub.lock.withLock { if RangeStub.objectRequests == 3 { RangeStub.failNextObjectRequests = 50 } } }
        let id = comicId("la_ayuda_trimmed")
        let (s1, st1) = store()
        s1.wholeBundleDownloaderForTesting = { _, _ in XCTFail("whole-zip path must not run"); return "" }
        await s1.downloadComic(storeComic(id, internalId: "comic-a"))
        guard case .failed = s1.downloadState(for: id) else { return XCTFail("expected a failed, resumable download") }
        await st1.loadDownloadedComics()
        XCTAssertFalse(st1.isDownloaded(id))

        // "Relaunch": fresh service and storage over the same folder, catalog unknown.
        RangeStub.lock.withLock { RangeStub.failNextObjectRequests = 0; RangeStub.onObjectRequest = nil }
        let (s2, st2) = store()
        s2.wholeBundleDownloaderForTesting = { _, _ in XCTFail("whole-zip path must not run"); return "" }
        XCTAssertEqual(ProgressiveDownloader.partialDownloads(in: comics).map(\.comicId), [id])
        await s2.resumePartialDownloads()
        try await waitUntil { s2.downloadState(for: id) == .downloaded }
        await st2.loadDownloadedComics()
        XCTAssertTrue(st2.isDownloaded(id))
        XCTAssertEqual(try tree(comics.appendingPathComponent(id)), try tree(reference(for: zip)))
    }

    // MARK: 11 Version change

    func testAChangedBundleVersionDiscardsThePartialAndStartsOver() async throws {
        let old = try fixture("la_llegada_trimmed"), new = try fixture("la_ayuda_trimmed")
        serve("comic-a", old, version: "v1")
        RangeStub.onObjectRequest = { RangeStub.lock.withLock { if RangeStub.objectRequests == 3 { RangeStub.failNextObjectRequests = 50 } } }
        let first = downloader("comic-a", internalId: "comic-a", config: .init(concurrency: 1, maxChunkBytes: 200_000, retriesPerChunk: 1, retryDelay: 0.01))
        do { try await first.run(); XCTFail() } catch ProgressiveDownloader.DownloadError.network {}
        let folder = comics.appendingPathComponent("comic-a")
        let oldFiles = try tree(folder).keys.filter { !$0.hasPrefix(".") }
        XCTAssertFalse(oldFiles.isEmpty)

        // The server re-exported the comic: new version, different zip.
        RangeStub.lock.withLock { RangeStub.failNextObjectRequests = 0; RangeStub.onObjectRequest = nil }
        serve("comic-a", new, version: "v2")
        let second = downloader("comic-a", internalId: "comic-a")
        try await second.run()
        let got = try tree(folder)
        XCTAssertEqual(got, try tree(reference(for: new)))
        for f in oldFiles where (try tree(reference(for: new)))[f] == nil { XCTAssertNil(got[f], "old-version file \(f) must be gone") }
    }

    func testAVersionChangeMidDownloadIsRestartedByTheStore() async throws {
        let old = try fixture("la_llegada_trimmed"), new = try fixture("la_ayuda_trimmed")
        serve("comic-a", old, version: "v1")
        // Expire the link after 2 object requests; on re-resolve the server has v2.
        RangeStub.expireAfter = 2
        RangeStub.onObjectRequest = { RangeStub.lock.withLock { if RangeStub.objectRequests == 2 { RangeStub.objects["comic-a"] = .init(data: new, version: "v2") } } }
        let (s, st) = store()
        s.wholeBundleDownloaderForTesting = { _, _ in XCTFail("whole-zip path must not run"); return "" }
        let id = comicId("la_ayuda_trimmed")   // what the (new) bundle's comic.json says
        await s.downloadComic(storeComic(id, internalId: "comic-a"))
        XCTAssertEqual(s.downloadState(for: id), .downloaded)
        await st.loadDownloadedComics()
        XCTAssertEqual(try tree(comics.appendingPathComponent(id)), try tree(reference(for: new)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: comics.appendingPathComponent(comicId("la_llegada_trimmed")).path), "nothing of the old version")
        XCTAssertGreaterThanOrEqual(RangeStub.resolves, 2)
    }

    // MARK: 12 Link expiry

    func testAnExpiredLinkIsRefreshedAndTheDownloadCarriesOn() async throws {
        let zip = try fixture("la_ayuda_trimmed")
        serve("comic-a", zip)
        RangeStub.expireAfter = 2   // every link dies after two uses
        let d = downloader("comic-a", internalId: "comic-a", config: .init(concurrency: 2, maxChunkBytes: 300_000))
        try await d.run()
        XCTAssertGreaterThan(RangeStub.resolves, 2, "the link was refreshed more than once")
        XCTAssertEqual(try tree(d.folder), try tree(reference(for: zip)))
    }

    // MARK: 13–14 Cancel and delete

    func testCancellingRemovesThePartialFolderAndMarker() async throws {
        serve("comic-a", try fixture("la_ayuda_trimmed"))
        let id = comicId("la_ayuda_trimmed")
        let (s, st) = store(); s.wholeBundleDownloaderForTesting = { _, _ in XCTFail(); return "" }
        let comic = storeComic(id, internalId: "comic-a")
        RangeStub.onObjectRequest = { RangeStub.lock.withLock { if RangeStub.objectRequests == 3 { Task { @MainActor in s.cancelDownload(id) } } } }
        await s.downloadComic(comic)
        try await waitUntil { !s.isDownloading(id) }
        XCTAssertEqual(s.downloadState(for: id), .notDownloaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: comics.appendingPathComponent(id).path), "folder removed")
        await st.loadDownloadedComics()
        XCTAssertFalse(st.isDownloaded(id))
        XCTAssertFalse(st.existsOnDevice(id))
    }

    func testDeletingWhilePartialRemovesItAndDeletingWhenCompleteHidesIt() async throws {
        let zip = try fixture("la_llegada_trimmed")
        // A partial on disk from an earlier session.
        serve("comic-a", zip)
        RangeStub.onObjectRequest = { RangeStub.lock.withLock { if RangeStub.objectRequests == 3 { RangeStub.failNextObjectRequests = 50 } } }
        let d = downloader("comic-a", internalId: "comic-a", config: .init(concurrency: 1, maxChunkBytes: 200_000, retriesPerChunk: 1, retryDelay: 0.01))
        do { try await d.run(); XCTFail() } catch ProgressiveDownloader.DownloadError.network {}
        let (s, st) = store()
        XCTAssertTrue(st.isPartiallyDownloaded("comic-a"))
        s.deleteDownload("comic-a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: comics.appendingPathComponent("comic-a").path))
        XCTAssertEqual(s.downloadState(for: "comic-a"), .notDownloaded, "a removed partial isn't 'hidden' — there's nothing to restore")

        // A complete comic deletes as before: folder gone, id hidden.
        let folder = comics.appendingPathComponent("comic-b")
        try FileManager.default.moveItem(at: reference(for: zip), to: folder)
        await st.loadDownloadedComics()
        s.deleteDownload("comic-b")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(st.isHidden("comic-b"))
        XCTAssertEqual(s.downloadState(for: "comic-b"), .notDownloaded)
        st.unhideComic("comic-b")
    }

    // MARK: 15–16 Fallback

    func testAHostThatIgnoresRangesFallsBackToTheWholeZipLeavingNothingBehind() async throws {
        serve("comic-a", try fixture("la_llegada_trimmed"))
        RangeStub.ignoreRange = true
        let id = comicId("la_llegada_trimmed")
        let (s, _) = store()
        var fellBack = false
        s.wholeBundleDownloaderForTesting = { [self] comic, url in
            fellBack = true
            XCTAssertEqual(url, route("comic-a"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: comics.appendingPathComponent(comic.id).path), "no partial folder when falling back")
            let dir = try reference(for: try fixture("la_llegada_trimmed"))
            try FileManager.default.moveItem(at: dir, to: comics.appendingPathComponent(comic.id))
            return comic.id
        }
        await s.downloadComic(storeComic(id, internalId: "comic-a"))
        XCTAssertTrue(fellBack)
        XCTAssertEqual(s.downloadState(for: id), .downloaded)
        XCTAssertGreaterThan(RangeStub.objectRequests, 0, "a range was tried first")
    }

    func testUnsupportedArchivesFallBackSafely() async throws {
        var z = TestZip(); z.entries = [("comic.json", Data("{}".utf8)), ("images/a.jpg", Data(repeating: 1, count: 100))]
        var cases: [(String, Data)] = []
        var enc = z; enc.flags["images/a.jpg"] = 1; cases.append(("encrypted", enc.build()))
        var z64 = z; z64.zip64Sizes = ["images/a.jpg"]; cases.append(("zip64 sizes", z64.build()))
        var lzma = z; lzma.method["images/a.jpg"] = 12; cases.append(("bzip2 method", lzma.build()))
        cases.append(("not a zip", Data(repeating: 0, count: 100_000)))
        var noJSON = TestZip(); noJSON.entries = [("images/a.jpg", Data(repeating: 1, count: 100))]; cases.append(("no comic.json", noJSON.build()))
        for (what, data) in cases {
            RangeStub.reset()
            serve("comic-a", data)
            let d = downloader("comic-a", internalId: "comic-a")
            do { try await d.run(); XCTFail("\(what): should not be readable") }
            catch ProgressiveDownloader.DownloadError.rangeUnsupported { }
            catch { XCTFail("\(what): \(error)") }
            XCTAssertFalse(FileManager.default.fileExists(atPath: comics.appendingPathComponent("comic-a").path), "\(what): nothing on disk")

            let (s, _) = store()
            var fellBack = false
            s.wholeBundleDownloaderForTesting = { [self] comic, _ in
                fellBack = true
                try FileManager.default.createDirectory(at: comics.appendingPathComponent(comic.id), withIntermediateDirectories: true)
                try Data("{\"id\":\"comic-a\",\"title\":\"a\",\"pages\":[]}".utf8).write(to: comics.appendingPathComponent("comic-a/comic.json"))
                return comic.id
            }
            await s.downloadComic(storeComic("comic-a", internalId: "comic-a"))
            XCTAssertTrue(fellBack, what)
            try? FileManager.default.removeItem(at: comics.appendingPathComponent("comic-a"))
        }
    }

    // MARK: 17–19 What counts as downloaded

    func testAPartialFolderIsNeverADownloadedComic() async throws {
        let folder = comics.appendingPathComponent("comic-a")
        try FileManager.default.moveItem(at: reference(for: fixture("la_llegada_trimmed")), to: folder)
        // Even a folder with every file is partial while the marker is there.
        let marker = PartialDownloadMarker(comicId: "comic-a", downloadUrl: "/api/reader/comics/x", bundleVersion: "v1", fileSizeMB: 1, startedAt: Date(),
                                           manifest: ZipManifest(totalBytes: 0, entries: [], centralDirectoryOffset: 0))
        try JSONEncoder().encode(marker).write(to: LocalComicStorage.partialMarkerURL(in: folder))
        let (s, st) = store()
        await st.loadDownloadedComics()
        XCTAssertFalse(st.isDownloaded("comic-a"))
        XCTAssertFalse(st.existsOnDevice("comic-a"))
        XCTAssertFalse(st.isCompleteOnDisk("comic-a"))
        XCTAssertTrue(st.isPartiallyDownloaded("comic-a"))
        XCTAssertEqual(s.downloadState(for: "comic-a"), .notDownloaded)
        XCTAssertFalse(s.updateAvailable(for: "comic-a"))
    }

    func testOnlyACompletedDownloadBecomesDownloadedWithItsVersionRecorded() async throws {
        let zip = try fixture("la_llegada_trimmed")
        serve("comic-a", zip, version: "abc123")
        let id = comicId("la_llegada_trimmed")
        let (s, st) = store()
        s.wholeBundleDownloaderForTesting = { _, _ in XCTFail(); return "" }
        var sawDownloadedBeforeDone = false
        RangeStub.onObjectRequest = { Task { @MainActor in if st.isDownloaded(id) || st.isCompleteOnDisk(id) { sawDownloadedBeforeDone = true } } }
        var progress: [Double] = []
        let cancellable = s.$downloadStates.sink { if case let .downloading(p)? = $0[id] { progress.append(p) } }
        await s.downloadComic(storeComic(id, internalId: "comic-a", version: "abc123"))
        cancellable.cancel()
        XCTAssertFalse(sawDownloadedBeforeDone, "not downloaded until the last file is in")
        XCTAssertEqual(s.downloadState(for: id), .downloaded)
        XCTAssertTrue(st.isDownloaded(id))
        XCTAssertTrue(st.isCompleteOnDisk(id))
        XCTAssertFalse(st.isPartiallyDownloaded(id))
        XCTAssertEqual(s.recordedBundleVersion(for: id), "abc123")
        XCTAssertGreaterThan(progress.count, 1)
        XCTAssertEqual(progress.last, 1.0)
        XCTAssertEqual(try tree(comics.appendingPathComponent(id)), try tree(reference(for: zip)))
    }

    func testComicsDownloadedBeforeAreUntouchedAndUpdatedByTheWholeZipPath() async throws {
        let zip = try fixture("la_llegada_trimmed")
        let id = comicId("la_llegada_trimmed")
        let folder = comics.appendingPathComponent(id)
        try FileManager.default.moveItem(at: reference(for: zip), to: folder)
        let before = try tree(folder)
        let (s, st) = store()
        await st.loadDownloadedComics()
        XCTAssertTrue(st.isDownloaded(id))
        XCTAssertEqual(s.downloadState(for: id), .downloaded)
        XCTAssertTrue(st.existsOnDevice(id))
        // A re-download (an update) of a complete comic keeps today's path, so
        // the old copy stays readable until the new one is in.
        serve("comic-a", try fixture("la_ayuda_trimmed"), version: "v2")
        var fellBack = false
        s.wholeBundleDownloaderForTesting = { comic, _ in fellBack = true; return comic.id }
        await s.downloadComic(storeComic(id, internalId: "comic-a", version: "v2"))
        XCTAssertTrue(fellBack)
        XCTAssertEqual(try tree(folder), before, "no range request touched the existing folder")
        XCTAssertEqual(RangeStub.ranges.count, 0)
    }

    // MARK: 20 The whole-zip path

    func testTheWholeZipPathIsStillThereAndSwitchedToWhenProgressiveIsOff() async throws {
        let zip = try fixture("la_ayuda_trimmed")
        // The extractor itself still produces the comic (what the path relies on).
        let dir = try reference(for: zip)
        let files = try tree(dir)
        XCTAssertTrue(files.keys.contains("comic.json"))
        XCTAssertGreaterThan(files.count, 5)
        serve("comic-a", zip)
        let id = comicId("la_ayuda_trimmed")
        let (s, _) = store()
        s.progressiveDownloadsEnabled = false
        var used = false
        s.wholeBundleDownloaderForTesting = { [self] comic, _ in
            used = true
            try FileManager.default.moveItem(at: dir, to: comics.appendingPathComponent(comic.id)); return comic.id
        }
        await s.downloadComic(storeComic(id, internalId: "comic-a"))
        XCTAssertTrue(used)
        XCTAssertEqual(RangeStub.ranges.count, 0, "no range request was made")
        XCTAssertEqual(s.downloadState(for: id), .downloaded)
    }

    // MARK: Helpers

    private func waitUntil(timeout: TimeInterval = 10, _ cond: @escaping @MainActor () -> Bool) async throws {
        let start = Date()
        while !cond() {
            if Date().timeIntervalSince(start) > timeout { throw XCTSkip("timed out waiting") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func compress(_ data: Data) -> Data? {
        // Raw deflate via Compression (what zip method 8 stores).
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count + 1024); defer { dst.deallocate() }
        let n = data.withUnsafeBytes { src -> Int in
            compression_encode_buffer(dst, data.count + 1024, src.baseAddress!.assumingMemoryBound(to: UInt8.self), data.count, nil, COMPRESSION_ZLIB)
        }
        return n > 0 ? Data(bytes: dst, count: n) : nil
    }

    /// Rewrite the sizes/crc of one entry in both headers (TestZip stores
    /// `data.count` for both; a deflated entry needs the real figures).
    private func patchSizes(_ zip: Data, name: String, compressed: Int, uncompressed: Int, crc: UInt32) -> Data {
        var b = [UInt8](zip)
        let nameBytes = [UInt8](name.utf8)
        func le32(_ v: Int, at i: Int) { b[i] = UInt8(v & 0xFF); b[i + 1] = UInt8((v >> 8) & 0xFF); b[i + 2] = UInt8((v >> 16) & 0xFF); b[i + 3] = UInt8((v >> 24) & 0xFF) }
        var i = 0
        while i + 4 <= b.count {
            if b[i] == 0x50, b[i + 1] == 0x4B, b[i + 2] == 0x03, b[i + 3] == 0x04, Array(b[(i + 30)..<(i + 30 + nameBytes.count)]) == nameBytes {
                le32(Int(crc), at: i + 14); le32(compressed, at: i + 18); le32(uncompressed, at: i + 22)
            }
            if b[i] == 0x50, b[i + 1] == 0x4B, b[i + 2] == 0x01, b[i + 3] == 0x02, i + 46 + nameBytes.count <= b.count, Array(b[(i + 46)..<(i + 46 + nameBytes.count)]) == nameBytes {
                le32(Int(crc), at: i + 16); le32(compressed, at: i + 20); le32(uncompressed, at: i + 24)
            }
            i += 1
        }
        return Data(b)
    }
}

import Compression
