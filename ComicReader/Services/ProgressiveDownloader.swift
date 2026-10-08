import Foundation

// Rebuilds a comic's folder file by file from its bundle on the CDN, using
// byte ranges (BundleRangeReader), instead of downloading the whole zip and
// unzipping it. The result is the folder today's ZIPExtractor would produce —
// same files, same names — so once it's complete the comic is an ordinary
// downloaded comic.
//
// While it's under way the folder holds `.partial.json` (the marker): the
// bundle's manifest plus what's needed to resume. A folder with the marker is
// never a downloaded comic (LocalComicStorage skips it). Each file is written
// to a temporary name and renamed into place, so there are no half-written
// assets; a file is "landed" when it exists with the manifest's size.
// Resuming is therefore just "fetch whatever hasn't landed", after any
// interruption, including a relaunch.
//
// Entries are fetched in chunks of adjacent entries (one range per request;
// the host refuses multi-range), a few chunks at a time, highest priority
// first. Priority is a plain per-entry number so the reader can later push
// "the page I'm looking at" to the front without changing the downloader.

/// What `.partial.json` holds.
struct PartialDownloadMarker: Codable, Equatable {
    static let fileName = ".partial.json"
    static let currentFormat = 1

    var format: Int = PartialDownloadMarker.currentFormat
    /// The catalog id — the folder's name.
    let comicId: String
    /// The catalog's `downloadUrl` ("/api/reader/comics/<internal id>").
    let downloadUrl: String
    /// Version in the object key the bundle was resolved to (nil = unversioned).
    let bundleVersion: String?
    let fileSizeMB: Double
    let startedAt: Date
    let manifest: ZipManifest
}

actor ProgressiveDownloader {
    struct Configuration {
        var concurrency = 4
        /// Adjacent entries are fetched together up to about this many bytes.
        var maxChunkBytes = 4 << 20
        var retriesPerChunk = 3
        var retryDelay: TimeInterval = 1.5
        var urlLifetime: TimeInterval = BundleRangeReader.urlLifetime
    }

    enum DownloadError: Error, LocalizedError {
        /// The bundle can't be read by ranges (no redirect, no 206, an
        /// unsupported archive). Nothing was written; use the whole-zip path.
        case rangeUnsupported(Error)
        /// The server's bundle changed under a partial download (restart it).
        case bundleChanged
        /// The comic folder disappeared (deleted) while downloading.
        case folderGone
        case network(Error)
        case corrupt(String)

        var errorDescription: String? {
            switch self {
            case let .rangeUnsupported(e): return "Progressive download unavailable: \(e.localizedDescription)"
            case .bundleChanged: return "The comic was updated on the server during the download"
            case .folderGone: return "The comic was removed during the download"
            case let .network(e): return e.localizedDescription
            case let .corrupt(what): return "Downloaded data didn't match the bundle: \(what)"
            }
        }
    }

    /// Progress (0…1, bytes landed over bytes to land) — called off the main actor.
    typealias ProgressHandler = @Sendable (Double) -> Void
    /// A file is in place under its final name (after the rename) — called off the main actor.
    typealias LandedHandler = @Sendable (String) -> Void

    nonisolated let comicId: String
    nonisolated let folder: URL
    private let bundleRoute: URL
    private let downloadUrl: String
    private let fileSizeMB: Double
    private let reader: BundleRangeReader
    private let config: Configuration
    private let onProgress: ProgressHandler
    private let onLanded: LandedHandler?

    private var resolved: ResolvedBundle?
    private var resolving: Task<ResolvedBundle, Error>?
    private var manifest: ZipManifest?
    private var spans: [ZipEntry: Range<Int>] = [:]
    private var pending: Set<ZipEntry> = []
    private var inFlight: Set<ZipEntry> = []
    private var priorities: [String: Int] = [:]
    private var bytesLanded = 0
    private var bytesToLand = 0
    private var cancelled = false
    private var failure: Error?

    // Page priority: once comic.json is here it's decoded into a plan of which
    // files each page needs; the reader says which page it's on and the plan
    // becomes the priority table. Files the reader is waiting for right now
    // ("requested") go ahead of every page.
    private var plan: ComicAssetPlan?
    private var focusedPage = 0
    private var requested: Set<String> = []
    private(set) var decodedComicId: String?

    /// The newest priority wins; `comic.json` is always first unless told otherwise.
    static let topPriority = 1_000_000
    /// A file the reader is waiting for: above any page, below comic.json.
    static let requestedPriority = 900_000

    init(comicId: String, bundleRoute: URL, downloadUrl: String, fileSizeMB: Double, comicsDirectory: URL,
         reader: BundleRangeReader, configuration: Configuration = Configuration(),
         onProgress: @escaping ProgressHandler, onLanded: LandedHandler? = nil) {
        self.comicId = comicId
        self.folder = comicsDirectory.appendingPathComponent(comicId, isDirectory: true)
        self.bundleRoute = bundleRoute
        self.downloadUrl = downloadUrl
        self.fileSizeMB = fileSizeMB
        self.reader = reader
        self.config = configuration
        self.onProgress = onProgress
        self.onLanded = onLanded
        self.priorities["comic.json"] = Self.topPriority
    }

    nonisolated var markerURL: URL { folder.appendingPathComponent(PartialDownloadMarker.fileName) }

    // MARK: Priority

    /// Fetch these entries before anything else at a lower level. Entries
    /// already in flight finish as they are.
    func prioritise(_ names: [String], level: Int) {
        for n in names { priorities[n] = level }
    }

    /// Entries not yet landed, for callers deciding what to prioritise.
    var remainingEntryNames: [String] { pending.union(inFlight).map(\.name) }

    /// The current priority table (tests).
    var currentPriorities: [String: Int] { priorities }
    var currentPlan: ComicAssetPlan? { plan }

    /// The reader is on page `index` (0 = cover): that page's files first,
    /// then the following pages, then the rest. Nothing in flight is touched;
    /// only what's still pending is reordered. Remembered if comic.json hasn't
    /// landed yet.
    func focus(onPage index: Int) {
        focusedPage = index
        applyPlan()
    }

    /// The reader is waiting for these exact entries now (e.g. tapped audio):
    /// ahead of everything but comic.json. Names not in the bundle are ignored.
    func request(_ names: [String]) {
        for n in names { requested.insert(n) }
        applyPlan()
    }

    private func applyPlan() {
        var table: [String: Int] = ["comic.json": Self.topPriority]
        if let plan { table.merge(plan.priorities(focusedOn: focusedPage)) { _, new in new } }
        for n in requested { table[n] = Self.requestedPriority }
        priorities = table
    }

    /// comic.json is on disk: decode it and plan the pages from its data.
    private func planFromComicJSON() {
        guard plan == nil, let manifest,
              let data = try? Data(contentsOf: folder.appendingPathComponent("comic.json")),
              let json = try? JSONDecoder().decode(ComicJSON.self, from: data) else { return }
        decodedComicId = json.id
        plan = ComicAssetPlan(comic: json.toComic(basePath: folder), entryNames: Set(manifest.entries.map(\.name)))
        applyPlan()
    }

    // MARK: Run

    /// Start — or resume — and return when every file has landed and the
    /// marker is gone. Throws `rangeUnsupported` only before anything exists
    /// on disk, so the caller can fall back cleanly.
    func run() async throws {
        let fm = FileManager.default
        var marker = try? Self.readMarker(at: markerURL)
        let current = try await currentBundle()

        // A partial download of a different bundle can't be continued.
        if let m = marker, m.bundleVersion != current.bundleVersion {
            try? fm.removeItem(at: folder)
            marker = nil
        }

        if marker == nil {
            let manifest: ZipManifest
            do {
                manifest = try await reader.readManifest(current.url)
            } catch let e as BundleRangeReader.RangeError {
                throw DownloadError.rangeUnsupported(e)
            } catch let e as ZipManifest.ParseError {
                throw DownloadError.rangeUnsupported(e)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw DownloadError.network(error)
            }
            guard manifest.entries.contains(where: { $0.name == "comic.json" }) else {
                throw DownloadError.rangeUnsupported(ZipManifest.ParseError.inconsistent("no comic.json in the bundle"))
            }
            // If a complete comic is somehow here, we're replacing it: start clean.
            if fm.fileExists(atPath: folder.path) { try? fm.removeItem(at: folder) }
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let m = PartialDownloadMarker(comicId: comicId, downloadUrl: downloadUrl, bundleVersion: current.bundleVersion,
                                          fileSizeMB: fileSizeMB, startedAt: Date(), manifest: manifest)
            try Self.writeAtomically(try JSONEncoder().encode(m), to: markerURL)
            marker = m
        }
        guard let marker else { throw DownloadError.corrupt("no marker") }

        manifest = marker.manifest
        spans = marker.manifest.spans()
        let extracted = marker.manifest.entries.filter(\.isExtracted)
        bytesToLand = extracted.reduce(0) { $0 + $1.uncompressedSize }
        pending = Set(extracted.filter { !Self.hasLanded($0, in: folder) })
        bytesLanded = bytesToLand - pending.reduce(0) { $0 + $1.uncompressedSize }
        inFlight = []
        cancelled = false
        failure = nil
        report()
        // comic.json first, on its own: it's small, everything else is planned
        // from it, and the workers mustn't fill their chunks with whatever
        // sits lowest in the archive (megabytes of audio) before the plan
        // says what the first page needs. Resuming with it here already:
        // plan the pages before fetching anything.
        if let comicJSON = pending.first(where: { $0.name == "comic.json" }) {
            pending.remove(comicJSON)
            inFlight.insert(comicJSON)
            do { try await process([comicJSON]) } catch { fail(error) }
        } else {
            planFromComicJSON()
        }

        if failure == nil {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<max(1, config.concurrency) {
                    group.addTask { try await self.worker() }
                }
                try await group.waitForAll()
            }
        }
        if let failure { throw failure }
        try Task.checkCancellation()
        if cancelled { throw CancellationError() }
        guard pending.isEmpty, inFlight.isEmpty else { throw DownloadError.corrupt("entries left unfetched") }

        // Everything landed: the folder is a complete comic. Check the one
        // file everything hangs off before saying so.
        let comicJSON = folder.appendingPathComponent("comic.json")
        guard let data = try? Data(contentsOf: comicJSON), (try? JSONDecoder().decode(ComicJSON.self, from: data)) != nil else {
            throw DownloadError.corrupt("comic.json doesn't decode")
        }
        try fm.removeItem(at: markerURL)
    }

    func cancel() {
        cancelled = true
        resolving?.cancel()
    }

    // MARK: Workers

    private func worker() async throws {
        while let chunk = nextChunk() {
            do {
                try await process(chunk)
            } catch {
                fail(error)
                throw error
            }
        }
    }

    /// The next group of adjacent pending entries, starting from the highest
    /// priority one, up to `maxChunkBytes`. Neighbours join only when they're
    /// wanted about as soon (within a page band) — a page image mustn't drag
    /// megabytes of other pages' art along before that page's audio starts.
    /// Nil when nothing is pending or the download is stopping.
    private func nextChunk() -> [ZipEntry]? {
        guard !cancelled, failure == nil, !Task.isCancelled else { return nil }
        guard let first = pending.max(by: { a, b in
            let pa = priorities[a.name] ?? 0, pb = priorities[b.name] ?? 0
            return pa != pb ? pa < pb : a.localHeaderOffset > b.localHeaderOffset
        }) else { return nil }
        var chunk = [first]
        var bytes = spans[first]!.count
        let headPriority = priorities[first.name] ?? 0
        let byOffset = manifest!.entriesByOffset
        if let i = byOffset.firstIndex(of: first) {
            for e in byOffset[(i + 1)...] {
                guard pending.contains(e), bytes + spans[e]!.count <= config.maxChunkBytes,
                      abs((priorities[e.name] ?? 0) - headPriority) < ComicAssetPlan.pageBand else { break }
                chunk.append(e)
                bytes += spans[e]!.count
            }
        }
        for e in chunk { pending.remove(e); inFlight.insert(e) }
        return chunk
    }

    private func process(_ chunk: [ZipEntry]) async throws {
        let range = spans[chunk.first!]!.lowerBound..<spans[chunk.last!]!.upperBound
        let data = try await fetchWithRetries(range)
        for e in chunk {
            let local = spans[e]!.lowerBound - range.lowerBound
            let span = data.subdata(in: local..<(local + spans[e]!.count))
            let file: Data
            do { file = try ZipManifest.fileData(of: e, inSpan: span) } catch { throw DownloadError.corrupt(e.name) }
            guard file.count == e.uncompressedSize, CRC32.checksum(file) == e.crc32 else { throw DownloadError.corrupt(e.name) }
            // Deleted mid-download: stop, and don't recreate anything.
            guard FileManager.default.fileExists(atPath: markerURL.path) else { throw DownloadError.folderGone }
            try Self.writeAtomically(file, to: folder.appendingPathComponent(e.name))
            landed(e)
        }
    }

    private func landed(_ e: ZipEntry) {
        inFlight.remove(e)
        requested.remove(e.name)
        bytesLanded += e.uncompressedSize
        report()
        if e.name == "comic.json" { planFromComicJSON() }
        onLanded?(e.name)
    }

    private func fail(_ error: Error) {
        if failure == nil { failure = error }
        cancelled = true
    }

    private func report() {
        onProgress(bytesToLand > 0 ? min(1, Double(bytesLanded) / Double(bytesToLand)) : 0)
    }

    // MARK: Fetching

    private func fetchWithRetries(_ range: Range<Int>) async throws -> Data {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            if cancelled { throw CancellationError() }
            let bundle = try await currentBundle()
            do {
                return try await reader.fetch(bundle.url, start: range.lowerBound, end: range.upperBound - 1).data
            } catch BundleRangeReader.RangeError.expired {
                // The presigned link ran out: get a fresh one and go again (not an attempt).
                try await refreshBundle(ifStillAt: bundle)
            } catch let e as BundleRangeReader.RangeError {
                throw DownloadError.rangeUnsupported(e)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                attempt += 1
                if attempt > config.retriesPerChunk { throw DownloadError.network(error) }
                try await Task.sleep(nanoseconds: UInt64(config.retryDelay * Double(attempt) * 1_000_000_000))
            }
        }
    }

    /// The bundle's current location, re-resolved when the link is near its
    /// lifetime. Concurrent callers share one resolution.
    private func currentBundle() async throws -> ResolvedBundle {
        if let r = resolved, Date().timeIntervalSince(r.resolvedAt) < config.urlLifetime { return r }
        return try await refreshBundle(ifStillAt: resolved)
    }

    @discardableResult
    private func refreshBundle(ifStillAt stale: ResolvedBundle?) async throws -> ResolvedBundle {
        if let r = resolved, r != stale { return r }   // someone already refreshed
        if resolving == nil {
            let route = bundleRoute, reader = reader
            resolving = Task { try await reader.resolve(bundleRoute: route) }
        }
        defer { resolving = nil }
        let fresh: ResolvedBundle
        do {
            fresh = try await resolving!.value
        } catch let e as BundleRangeReader.RangeError {
            throw DownloadError.rangeUnsupported(e)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DownloadError.network(error)
        }
        // Mid-download, a different bundle version means a different zip:
        // offsets no longer apply. Stop; the caller restarts from scratch.
        if let had = resolved, had.bundleVersion != fresh.bundleVersion { throw DownloadError.bundleChanged }
        resolved = fresh
        return fresh
    }

    // MARK: Disk

    static func readMarker(at url: URL) throws -> PartialDownloadMarker? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let m = try JSONDecoder().decode(PartialDownloadMarker.self, from: Data(contentsOf: url))
        guard m.format == PartialDownloadMarker.currentFormat else { return nil }
        return m
    }

    /// A file has landed when it's in place with the manifest's size (files
    /// only ever appear whole, by rename).
    static func hasLanded(_ e: ZipEntry, in folder: URL) -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(e.name).path)
        return (attrs?[.size] as? NSNumber)?.intValue == e.uncompressedSize
    }

    /// Write to a temporary sibling, then rename into place.
    static func writeAtomically(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".tmp-\(UUID().uuidString)")
        try data.write(to: tmp)
        if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: tmp) }
        else { try fm.moveItem(at: tmp, to: url) }
    }

    /// Every comic folder holding a marker (downloads to resume), with it.
    static func partialDownloads(in comicsDirectory: URL) -> [PartialDownloadMarker] {
        guard let folders = try? FileManager.default.contentsOfDirectory(at: comicsDirectory, includingPropertiesForKeys: nil) else { return [] }
        return folders.compactMap { try? readMarker(at: $0.appendingPathComponent(PartialDownloadMarker.fileName)) }
    }
}
