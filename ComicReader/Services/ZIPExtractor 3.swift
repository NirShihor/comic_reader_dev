import Foundation
import Compression

/// Minimal ZIP file extractor using Foundation
/// Handles standard ZIP archives (deflate + stored methods)
struct ZIPExtractor {

    enum ZIPError: Error, LocalizedError {
        case invalidArchive
        case unsupportedCompression(UInt16)
        case decompressionFailed
        case corruptedEntry(String)

        var errorDescription: String? {
            switch self {
            case .invalidArchive: return "Invalid ZIP archive"
            case .unsupportedCompression(let m): return "Unsupported compression method: \(m)"
            case .decompressionFailed: return "Failed to decompress data"
            case .corruptedEntry(let name): return "Corrupted entry: \(name)"
            }
        }
    }

    /// Extract a ZIP file to a destination directory
    /// - Parameters:
    ///   - zipFileURL: Path to the .zip file on disk
    ///   - destinationURL: Directory to extract into
    ///   - progress: Optional callback with (completedEntries, totalEntries)
    static func extract(
        zipFileURL: URL,
        to destinationURL: URL,
        progress: ((Int, Int) -> Void)? = nil
    ) throws {
        let data = try Data(contentsOf: zipFileURL)
        let fm = FileManager.default

        // Find end-of-central-directory record (search backwards)
        let eocdSignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        var eocdOffset = -1

        let bytes = [UInt8](data)
        let searchStart = max(0, bytes.count - 65557) // max comment = 65535 + 22 bytes EOCD
        for i in stride(from: bytes.count - 4, through: searchStart, by: -1) {
            if bytes[i] == eocdSignature[0] &&
               bytes[i+1] == eocdSignature[1] &&
               bytes[i+2] == eocdSignature[2] &&
               bytes[i+3] == eocdSignature[3] {
                eocdOffset = i
                break
            }
        }

        guard eocdOffset >= 0 else { throw ZIPError.invalidArchive }

        // Parse EOCD
        let totalEntries = Int(readUInt16(bytes, offset: eocdOffset + 10))
        let centralDirOffset = Int(readUInt32(bytes, offset: eocdOffset + 16))

        // Parse central directory entries
        var entries: [(name: String, offset: Int, compressedSize: Int, uncompressedSize: Int, method: UInt16)] = []
        var cdOffset = centralDirOffset

        for _ in 0..<totalEntries {
            guard cdOffset + 46 <= bytes.count else { throw ZIPError.invalidArchive }

            // Verify central directory signature
            guard bytes[cdOffset] == 0x50, bytes[cdOffset+1] == 0x4B,
                  bytes[cdOffset+2] == 0x01, bytes[cdOffset+3] == 0x02 else {
                throw ZIPError.invalidArchive
            }

            let method = readUInt16(bytes, offset: cdOffset + 10)
            let compressedSize = Int(readUInt32(bytes, offset: cdOffset + 20))
            let uncompressedSize = Int(readUInt32(bytes, offset: cdOffset + 24))
            let nameLength = Int(readUInt16(bytes, offset: cdOffset + 28))
            let extraLength = Int(readUInt16(bytes, offset: cdOffset + 30))
            let commentLength = Int(readUInt16(bytes, offset: cdOffset + 32))
            let localHeaderOffset = Int(readUInt32(bytes, offset: cdOffset + 42))

            let nameData = Data(bytes[cdOffset + 46 ..< cdOffset + 46 + nameLength])
            let name = String(data: nameData, encoding: .utf8) ?? ""

            entries.append((name: name, offset: localHeaderOffset, compressedSize: compressedSize, uncompressedSize: uncompressedSize, method: method))

            cdOffset += 46 + nameLength + extraLength + commentLength
        }

        // Extract each entry
        for (index, entry) in entries.enumerated() {
            // Skip directories and __MACOSX metadata
            if entry.name.hasSuffix("/") || entry.name.hasPrefix("__MACOSX") {
                progress?(index + 1, totalEntries)
                continue
            }

            // Parse local file header to find data start
            let localOffset = entry.offset
            guard localOffset + 30 <= bytes.count else { throw ZIPError.corruptedEntry(entry.name) }

            let localNameLength = Int(readUInt16(bytes, offset: localOffset + 26))
            let localExtraLength = Int(readUInt16(bytes, offset: localOffset + 28))
            let dataStart = localOffset + 30 + localNameLength + localExtraLength

            guard dataStart + entry.compressedSize <= bytes.count else {
                throw ZIPError.corruptedEntry(entry.name)
            }

            let compressedData = Data(bytes[dataStart ..< dataStart + entry.compressedSize])

            // Decompress
            let fileData: Data
            switch entry.method {
            case 0: // Stored (no compression)
                fileData = compressedData
            case 8: // Deflate
                guard let decompressed = decompress(compressedData, uncompressedSize: entry.uncompressedSize) else {
                    throw ZIPError.decompressionFailed
                }
                fileData = decompressed
            default:
                throw ZIPError.unsupportedCompression(entry.method)
            }

            // Write to destination
            let filePath = destinationURL.appendingPathComponent(entry.name)
            let parentDir = filePath.deletingLastPathComponent()
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try fileData.write(to: filePath)

            progress?(index + 1, totalEntries)
        }
    }

    // MARK: - Helpers

    private static func readUInt16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        UInt32(bytes[offset]) |
        (UInt32(bytes[offset + 1]) << 8) |
        (UInt32(bytes[offset + 2]) << 16) |
        (UInt32(bytes[offset + 3]) << 24)
    }

    /// Decompress deflate data using the Compression framework
    private static func decompress(_ data: Data, uncompressedSize: Int) -> Data? {
        // Raw deflate — use COMPRESSION_ZLIB with the raw flag
        let sourceSize = data.count
        let destinationSize = uncompressedSize + uncompressedSize / 10 + 12 // small safety margin
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destinationBuffer.deallocate() }

        let decodedSize = data.withUnsafeBytes { sourceBuffer -> Int in
            guard let sourcePtr = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_decode_buffer(
                destinationBuffer, destinationSize,
                sourcePtr, sourceSize,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decodedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: decodedSize)
    }
}
