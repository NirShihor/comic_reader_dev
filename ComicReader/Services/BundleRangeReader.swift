import Foundation

// Reads a comic bundle (one STORED zip on the CDN) piece by piece over HTTP
// Range requests, so a comic can be reconstructed file by file instead of
// "download everything, then unzip". Verified against production (Oct 2026):
// the /bundle route 302s to a presigned Tigris URL signed for GET on `host`
// only (a Range header doesn't break the signature); single ranges answer 206
// with Content-Range; multi-range answers 416; HEAD answers 403. The zips are
// archiver level-0: every entry stored, no zip64.
//
// `ZipManifest` is pure parsing (bytes in, entries out) and `BundleRangeReader`
// is the HTTP around it. Nothing here touches the comic folder.

/// One file inside the bundle, as the central directory describes it.
struct ZipEntry: Codable, Equatable {
    let name: String
    let method: UInt16            // 0 = stored, 8 = deflate
    let compressedSize: Int
    let uncompressedSize: Int
    let crc32: UInt32
    /// Offset of the entry's local file header in the archive. The data
    /// follows the header (30 bytes + name + extra, lengths read from the
    /// local header itself — they can differ from the central directory's).
    let localHeaderOffset: Int

    var isDirectory: Bool { name.hasSuffix("/") }
    /// What ZIPExtractor writes to disk: files, minus Finder metadata.
    var isExtracted: Bool { !isDirectory && !name.hasPrefix("__MACOSX") }
}

/// The bundle's table of contents, from its central directory.
struct ZipManifest: Codable, Equatable {
    let totalBytes: Int
    let entries: [ZipEntry]
    /// Offset of the central directory — the end of the last entry's data.
    let centralDirectoryOffset: Int

    enum ParseError: Error, LocalizedError, Equatable {
        case noEndRecord
        case zip64
        case encrypted(String)
        case unsupportedMethod(UInt16, String)
        case truncated
        case inconsistent(String)

        var errorDescription: String? {
            switch self {
            case .noEndRecord: return "Not a zip archive (no end-of-central-directory record)"
            case .zip64: return "Zip64 archives aren't supported"
            case let .encrypted(n): return "Encrypted entry: \(n)"
            case let .unsupportedMethod(m, n): return "Unsupported compression method \(m): \(n)"
            case .truncated: return "Truncated central directory"
            case let .inconsistent(why): return "Inconsistent archive: \(why)"
            }
        }
    }

    /// Where the end-of-central-directory record says the directory is.
    struct EndRecord: Equatable {
        let entryCount: Int
        let centralDirectorySize: Int
        let centralDirectoryOffset: Int
    }

    /// Largest possible EOCD: 22 bytes + a 65535-byte comment.
    static let maxEndRecordBytes = 22 + 65_535
    /// What to ask for first: enough for the EOCD and, for most bundles, the
    /// whole central directory (a 290-entry comic's is 21 KB; a 999-entry
    /// one's is 72 KB and needs a second request).
    static let suffixProbeBytes = 65_536

    /// Parse the end record out of the archive's tail bytes (`tail` ends at
    /// the end of the archive). Searches backwards, as a comment may follow.
    static func endRecord(inTail tail: Data) throws -> EndRecord {
        let b = [UInt8](tail)
        guard b.count >= 22 else { throw ParseError.noEndRecord }
        var at = -1
        var i = b.count - 22
        while i >= 0 {
            if b[i] == 0x50, b[i + 1] == 0x4B, b[i + 2] == 0x05, b[i + 3] == 0x06 { at = i; break }
            i -= 1
        }
        guard at >= 0 else { throw ParseError.noEndRecord }
        let diskNumber = u16(b, at + 4), diskWithCD = u16(b, at + 6)
        let count = Int(u16(b, at + 10)), cdSize = Int(u32(b, at + 12)), cdOffset = Int(u32(b, at + 16))
        if diskNumber != 0 || diskWithCD != 0 { throw ParseError.zip64 }
        if count == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF { throw ParseError.zip64 }
        // A zip64 end-of-central-directory locator just before the EOCD.
        if at >= 20, b[at - 20] == 0x50, b[at - 19] == 0x4B, b[at - 18] == 0x06, b[at - 17] == 0x07 { throw ParseError.zip64 }
        return EndRecord(entryCount: count, centralDirectorySize: cdSize, centralDirectoryOffset: cdOffset)
    }

    /// Parse the central directory bytes (exactly `end.centralDirectorySize`
    /// bytes starting at `end.centralDirectoryOffset`).
    static func parse(centralDirectory cd: Data, end: EndRecord, totalBytes: Int) throws -> ZipManifest {
        let b = [UInt8](cd)
        guard b.count >= end.centralDirectorySize else { throw ParseError.truncated }
        var entries: [ZipEntry] = []
        var p = 0
        for _ in 0..<end.entryCount {
            guard p + 46 <= b.count, b[p] == 0x50, b[p + 1] == 0x4B, b[p + 2] == 0x01, b[p + 3] == 0x02 else { throw ParseError.truncated }
            let flags = u16(b, p + 8), method = u16(b, p + 10)
            let crc = u32(b, p + 16)
            let csize = Int(u32(b, p + 20)), usize = Int(u32(b, p + 24))
            let nameLen = Int(u16(b, p + 28)), extraLen = Int(u16(b, p + 30)), commentLen = Int(u16(b, p + 32))
            let lho = Int(u32(b, p + 42))
            guard p + 46 + nameLen <= b.count else { throw ParseError.truncated }
            let name = String(decoding: b[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            if flags & 0x0001 != 0 { throw ParseError.encrypted(name) }
            if csize == 0xFFFF_FFFF || usize == 0xFFFF_FFFF || lho == 0xFFFF_FFFF { throw ParseError.zip64 }
            if method != 0 && method != 8 { throw ParseError.unsupportedMethod(method, name) }
            if method == 0 && csize != usize { throw ParseError.inconsistent("stored entry \(name) sizes differ") }
            if lho + 30 + csize > end.centralDirectoryOffset { throw ParseError.inconsistent("\(name) extends past the central directory") }
            entries.append(ZipEntry(name: name, method: method, compressedSize: csize, uncompressedSize: usize, crc32: crc, localHeaderOffset: lho))
            p += 46 + nameLen + extraLen + commentLen
        }
        return ZipManifest(totalBytes: totalBytes, entries: entries, centralDirectoryOffset: end.centralDirectoryOffset)
    }

    /// Entries in archive order (by offset), which is how they're fetched.
    var entriesByOffset: [ZipEntry] { entries.sorted { $0.localHeaderOffset < $1.localHeaderOffset } }

    /// The byte span each entry occupies: from its local header up to the
    /// next entry's header (or the central directory) — exact, so a span can
    /// be fetched and parsed without guessing the local header's extra length.
    func spans() -> [ZipEntry: Range<Int>] {
        let sorted = entriesByOffset
        var out: [ZipEntry: Range<Int>] = [:]
        for (i, e) in sorted.enumerated() {
            let end = i + 1 < sorted.count ? sorted[i + 1].localHeaderOffset : centralDirectoryOffset
            out[e] = e.localHeaderOffset..<end
        }
        return out
    }

    /// The file's bytes out of its fetched span: parse the local header
    /// (30 bytes + name + extra) and take the data after it; inflate deflated
    /// entries. Throws if the span doesn't hold what the directory promised.
    static func fileData(of entry: ZipEntry, inSpan span: Data) throws -> Data {
        let b = [UInt8](span.prefix(30))
        guard b.count == 30, b[0] == 0x50, b[1] == 0x4B, b[2] == 0x03, b[3] == 0x04 else { throw ParseError.inconsistent("bad local header for \(entry.name)") }
        let nameLen = Int(u16(b, 26)), extraLen = Int(u16(b, 28))
        let start = 30 + nameLen + extraLen
        guard start + entry.compressedSize <= span.count else { throw ParseError.inconsistent("\(entry.name) span too short") }
        let raw = span.subdata(in: (span.startIndex + start)..<(span.startIndex + start + entry.compressedSize))
        switch entry.method {
        case 0: return raw
        case 8:
            guard let out = ZIPExtractor.inflate(raw, uncompressedSize: entry.uncompressedSize) else { throw ParseError.inconsistent("\(entry.name) failed to inflate") }
            return out
        default: throw ParseError.unsupportedMethod(entry.method, entry.name)
        }
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | (UInt16(b[i + 1]) << 8) }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }
}

extension ZipEntry: Hashable {}

/// CRC-32 (IEEE), as zip uses it, to check each written file against the directory.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { buf in for byte in buf { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) } }
        return c ^ 0xFFFF_FFFF
    }
}

/// Where a bundle lives right now: the presigned URL the /bundle route
/// redirected to, and the bundle version baked into its object key
/// (`bundles/<id>-<version>.zip`; nil for a legacy unversioned key or a
/// non-redirecting server).
struct ResolvedBundle: Equatable {
    let url: URL
    let bundleVersion: String?
    let resolvedAt: Date

    /// `bundles/<internalId>-<version>.zip` → version; `bundles/<internalId>.zip`
    /// (the legacy key) or anything else → nil.
    static func version(inObjectURL url: URL, internalId: String) -> String? {
        let m = url.lastPathComponent
        guard m.hasSuffix(".zip") else { return nil }
        let stem = String(m.dropLast(4))
        let prefix = internalId + "-"
        guard stem.hasPrefix(prefix), stem.count > prefix.count else { return nil }
        return String(stem.dropFirst(prefix.count))
    }
}

/// The HTTP side: resolve the bundle's location and fetch byte ranges.
/// Foreground session, no caching (the object key is already content-versioned).
final class BundleRangeReader: @unchecked Sendable {
    enum RangeError: Error, LocalizedError, Equatable {
        case notRedirected(Int)
        case rangeNotSupported(Int)
        case badContentRange
        case expired
        case unexpectedLength(expected: Int, got: Int)

        var errorDescription: String? {
            switch self {
            case let .notRedirected(s): return "The bundle route answered \(s) instead of redirecting"
            case let .rangeNotSupported(s): return "The bundle host doesn't serve byte ranges (status \(s))"
            case .badContentRange: return "Missing or malformed Content-Range"
            case .expired: return "The bundle link has expired"
            case let .unexpectedLength(e, g): return "Expected \(e) bytes, got \(g)"
            }
        }
    }

    let session: URLSession
    /// Presigned URLs last 3600 s; re-resolve well before that.
    static let urlLifetime: TimeInterval = 50 * 60

    init(configuration: URLSessionConfiguration = BundleRangeReader.defaultConfiguration()) {
        session = URLSession(configuration: configuration)
    }

    static func defaultConfiguration() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.waitsForConnectivity = true
        c.timeoutIntervalForRequest = 60
        c.httpMaximumConnectionsPerHost = 6
        return c
    }

    /// GET the /bundle route (`…/comics/<internalId>/bundle`) without
    /// following its redirect; the Location is the presigned object URL.
    func resolve(bundleRoute: URL) async throws -> ResolvedBundle {
        let internalId = bundleRoute.deletingLastPathComponent().lastPathComponent
        var req = URLRequest(url: bundleRoute)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (_, response) = try await session.data(for: req, delegate: NoRedirect())
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (300..<400).contains(http.statusCode),
              let loc = http.value(forHTTPHeaderField: "Location"),
              let url = URL(string: loc, relativeTo: bundleRoute)?.absoluteURL else {
            throw RangeError.notRedirected(http.statusCode)
        }
        return ResolvedBundle(url: url, bundleVersion: ResolvedBundle.version(inObjectURL: url, internalId: internalId), resolvedAt: Date())
    }

    /// One byte range (`bytes=start-end`, inclusive) or a suffix (`bytes=-n`
    /// when `start` is nil). Returns the bytes and the object's total size
    /// from Content-Range. Anything but 206 is a failure: 200 means the host
    /// ignored the range, 403 that the link expired, 416 that it's out of range.
    func fetch(_ url: URL, start: Int?, end: Int) async throws -> (data: Data, totalBytes: Int) {
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.setValue(start.map { "bytes=\($0)-\(end)" } ?? "bytes=-\(end)", forHTTPHeaderField: "Range")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 403 { throw RangeError.expired }
        guard http.statusCode == 206 else { throw RangeError.rangeNotSupported(http.statusCode) }
        guard let cr = http.value(forHTTPHeaderField: "Content-Range"),
              let slash = cr.lastIndex(of: "/"), let total = Int(cr[cr.index(after: slash)...]) else { throw RangeError.badContentRange }
        let expected = start.map { end - $0 + 1 } ?? min(end, total)
        guard data.count == expected else { throw RangeError.unexpectedLength(expected: expected, got: data.count) }
        return (data, total)
    }

    /// The bundle's table of contents: a suffix probe for the end record
    /// (and, when it fits, the directory), else a second fetch of exactly the
    /// directory. Errors here mean "fall back to the whole-zip download".
    func readManifest(_ url: URL) async throws -> ZipManifest {
        let (tail, total) = try await fetch(url, start: nil, end: ZipManifest.suffixProbeBytes)
        let end = try ZipManifest.endRecord(inTail: tail)
        let tailStart = total - tail.count
        let cd: Data
        if end.centralDirectoryOffset >= tailStart && end.centralDirectoryOffset + end.centralDirectorySize <= total {
            let from = end.centralDirectoryOffset - tailStart
            cd = tail.subdata(in: from..<(from + end.centralDirectorySize))
        } else {
            guard end.centralDirectoryOffset + end.centralDirectorySize <= total else { throw ZipManifest.ParseError.inconsistent("directory past the end") }
            cd = try await fetch(url, start: end.centralDirectoryOffset, end: end.centralDirectoryOffset + end.centralDirectorySize - 1).data
        }
        return try ZipManifest.parse(centralDirectory: cd, end: end, totalBytes: total)
    }

    /// Stops URLSession following the /bundle redirect so we can read it.
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
