import Foundation
import SwiftUI

/// Represents a comic available in the store (not yet downloaded)
struct StoreComic: Identifiable, Codable {
    let id: String
    let title: String
    let titleEn: String?
    let description: String
    let coverThumbnailUrl: String
    let level: String
    let totalPages: Int
    let estimatedMinutes: Int
    let language: String
    let fileSizeMB: Double
    let version: String
    /// Content hash of the server's current bundle — compared against the
    /// hash recorded at download time to detect available updates.
    let bundleVersion: String?
    let downloadUrl: String
    let collectionId: String?
    let collectionTitle: String?
    let collectionTitleEn: String?
    let episodeNumber: Int?
    let collectionDescription: String?
    let collectionCoverThumbnailUrl: String?
    let order: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, titleEn, description, coverThumbnailUrl, level
        case totalPages, estimatedMinutes, language, fileSizeMB, version, bundleVersion, downloadUrl
        case collectionId, collectionTitle, collectionTitleEn, episodeNumber
        case collectionDescription, collectionCoverThumbnailUrl
        case order
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        titleEn = try container.decodeIfPresent(String.self, forKey: .titleEn)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        coverThumbnailUrl = try container.decodeIfPresent(String.self, forKey: .coverThumbnailUrl) ?? ""
        level = try container.decodeIfPresent(String.self, forKey: .level) ?? "beginner"
        totalPages = try container.decodeIfPresent(Int.self, forKey: .totalPages) ?? 0
        estimatedMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes) ?? 0
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "es"
        fileSizeMB = try container.decodeIfPresent(Double.self, forKey: .fileSizeMB) ?? 0
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "1.0"
        bundleVersion = try container.decodeIfPresent(String.self, forKey: .bundleVersion)
        downloadUrl = try container.decodeIfPresent(String.self, forKey: .downloadUrl) ?? ""
        collectionId = try container.decodeIfPresent(String.self, forKey: .collectionId)
        collectionTitle = try container.decodeIfPresent(String.self, forKey: .collectionTitle)
        collectionTitleEn = try container.decodeIfPresent(String.self, forKey: .collectionTitleEn)
        episodeNumber = try container.decodeIfPresent(Int.self, forKey: .episodeNumber)
        collectionDescription = try container.decodeIfPresent(String.self, forKey: .collectionDescription)
        collectionCoverThumbnailUrl = try container.decodeIfPresent(String.self, forKey: .collectionCoverThumbnailUrl)
        order = try container.decodeIfPresent(Int.self, forKey: .order)
    }

    init(id: String, title: String, titleEn: String? = nil, description: String, coverThumbnailUrl: String,
         level: String, totalPages: Int, estimatedMinutes: Int, language: String,
         fileSizeMB: Double, version: String, bundleVersion: String? = nil, downloadUrl: String,
         collectionId: String? = nil, collectionTitle: String? = nil, collectionTitleEn: String? = nil, episodeNumber: Int? = nil,
         collectionDescription: String? = nil, collectionCoverThumbnailUrl: String? = nil,
         order: Int? = nil) {
        self.id = id
        self.title = title
        self.titleEn = titleEn
        self.description = description
        self.coverThumbnailUrl = coverThumbnailUrl
        self.level = level
        self.totalPages = totalPages
        self.estimatedMinutes = estimatedMinutes
        self.language = language
        self.fileSizeMB = fileSizeMB
        self.version = version
        self.bundleVersion = bundleVersion
        self.downloadUrl = downloadUrl
        self.collectionId = collectionId
        self.collectionTitle = collectionTitle
        self.collectionTitleEn = collectionTitleEn
        self.episodeNumber = episodeNumber
        self.collectionDescription = collectionDescription
        self.collectionCoverThumbnailUrl = collectionCoverThumbnailUrl
        self.order = order
    }
}

/// Catalog response from the API
struct StoreCatalog: Codable {
    let comics: [StoreComic]
    let lastUpdated: String
}

/// Response from the comic download endpoint
struct ComicDownloadResponse: Codable {
    let comic: ComicJSON
    let assets: AssetManifest
}

/// Manifest of all asset URLs to download
struct AssetManifest: Codable {
    let images: [String]
    let audio: [String]
    let wordAudio: [String]
}

/// Download state for a comic
enum DownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case hidden // On device but removed from library
    case failed(error: String)
}

/// Manages the comic store - fetching catalog and downloading comics
@MainActor
class ComicStoreService: ObservableObject {
    static let shared = ComicStoreService()

    private let baseURL = Secrets.serverBaseURL

    @Published private(set) var catalog: [StoreComic] = []
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var catalogError: String?
    @Published var downloadStates: [String: DownloadState] = [:]

    private let localStorage = LocalComicStorage.shared
    private var activeDownloadTask: Task<Void, Never>?
    private var activeDownloadHelper: DownloadHelper?

    init() {
        // Initialize download states for downloaded comics
        for comic in localStorage.downloadedComics {
            downloadStates[comic.id] = .downloaded
        }
    }

    // MARK: - Catalog

    /// Fetch the comic catalog from the server
    func fetchCatalog() async {
        isLoadingCatalog = true
        catalogError = nil

        do {
            guard let url = URL(string: "\(baseURL)/api/reader/catalog") else {
                catalogError = "Invalid server URL"
                isLoadingCatalog = false
                return
            }

            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(StoreCatalog.self, from: data)
            catalog = response.comics

            // Refresh the Library's order map from the live catalog so the
            // downloaded shelf reflects the author's order without re-export.
            let orderMap = Dictionary(catalog.map { ($0.id, $0.order ?? 0) },
                                      uniquingKeysWith: { first, _ in first })
            localStorage.updateCatalogOrders(orderMap)

            // Update download states
            for comic in catalog {
                if localStorage.isDownloaded(comic.id) {
                    downloadStates[comic.id] = .downloaded
                } else if localStorage.existsOnDevice(comic.id) && localStorage.isHidden(comic.id) {
                    downloadStates[comic.id] = .hidden
                } else if downloadStates[comic.id] == nil {
                    downloadStates[comic.id] = .notDownloaded
                }
            }

        } catch {
            catalogError = error.localizedDescription
        }

        isLoadingCatalog = false
    }

    /// Get download state for a comic. Transient states (downloading / failed)
    /// are tracked in `downloadStates`; the persistent truth (downloaded / hidden
    /// / not-downloaded) is derived from local storage so it stays correct when a
    /// comic is deleted directly from the Library (which doesn't touch this dict).
    func downloadState(for comicId: String) -> DownloadState {
        if let state = downloadStates[comicId] {
            switch state {
            case .downloading, .failed: return state
            default: break
            }
        }
        if localStorage.isDownloaded(comicId) { return .downloaded }
        if localStorage.existsOnDevice(comicId) && localStorage.isHidden(comicId) { return .hidden }
        return .notDownloaded
    }

    // MARK: - Bundle versions (update detection)

    /// comicId → bundleVersion recorded when that bundle was downloaded.
    private let bundleVersionsKey = "downloadedBundleVersions.v1"
    private var downloadedBundleVersions: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: bundleVersionsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: bundleVersionsKey) }
    }

    /// True when the server's bundle differs from what this device downloaded.
    /// Devices that downloaded before version tracking existed have no record,
    /// which deliberately reads as "update available" — their bundles predate
    /// the current exporter anyway.
    func updateAvailable(for comicId: String) -> Bool {
        guard localStorage.isDownloaded(comicId),
              let latest = catalog.first(where: { $0.id == comicId })?.bundleVersion,
              !latest.isEmpty else { return false }
        return downloadedBundleVersions[comicId] != latest
    }

    // MARK: - Downloads

    /// Download a comic from the store as a single ZIP bundle
    /// Free space a download needs: the zip, plus the unzipped comic (about
    /// the same size again) while both exist, plus a margin for the system.
    static func storageNeededBytes(fileSizeMB: Double) -> Int64 {
        Int64(max(fileSizeMB, 10) * 2.2 * 1024 * 1024) + 40 * 1024 * 1024
    }

    /// The message shown when the phone doesn't have room for a comic.
    static func notEnoughStorageMessage(fileSizeMB: Double, availableBytes: Int64) -> String {
        let needMB = Int((Double(storageNeededBytes(fileSizeMB: fileSizeMB)) / (1024 * 1024)).rounded(.up))
        let haveMB = Int(Double(availableBytes) / (1024 * 1024))
        return "Not enough storage: this comic needs about \(needMB) MB free and the phone has \(haveMB) MB. Free up space in Settings → General → iPhone Storage, then try again."
    }

    /// Free space the system is willing to give to something the user asked for.
    static func availableStorageBytes(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    func downloadComic(_ comic: StoreComic) async {
        // Say so up front when the comic won't fit — iOS otherwise reports it as
        // a generic failure part-way through, after the whole download.
        if let available = Self.availableStorageBytes(at: localStorage.comicsDirectory),
           available < Self.storageNeededBytes(fileSizeMB: comic.fileSizeMB) {
            downloadStates[comic.id] = .failed(error: Self.notEnoughStorageMessage(fileSizeMB: comic.fileSizeMB, availableBytes: available))
            return
        }
        downloadStates[comic.id] = .downloading(progress: 0)

        // Store the task so cancelDownload can cancel it
        let task = Task {
            do {
                // 1. Build the bundle URL
                guard let bundleUrl = URL(string: "\(baseURL)\(comic.downloadUrl)/bundle") else {
                    downloadStates[comic.id] = .failed(error: "Invalid download URL")
                    return
                }

                // 2. Download ZIP with progress tracking
                let estimatedBytes = Int64(comic.fileSizeMB * 1024 * 1024)
                let (zipFileURL, _) = try await downloadWithProgress(
                    url: bundleUrl,
                    comicId: comic.id,
                    downloadPhaseWeight: 0.8, // 80% of progress bar for download
                    estimatedSizeBytes: estimatedBytes
                )

                try Task.checkCancellation()

                // 3. Unzip to a temp directory first, then determine comic ID from comic.json
                downloadStates[comic.id] = .downloading(progress: 0.85)

                let fm = FileManager.default
                let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

                // Always clean up the zip file
                defer { try? fm.removeItem(at: zipFileURL) }

                try ZIPExtractor.extract(zipFileURL: zipFileURL, to: tempDir)

                try Task.checkCancellation()

                downloadStates[comic.id] = .downloading(progress: 0.92)

                // 4. Read comic.json to get the actual comic ID for the folder name
                let comicJsonURL = tempDir.appendingPathComponent("comic.json")
                let comicJsonData = try Data(contentsOf: comicJsonURL)
                let comicJson = try JSONDecoder().decode(ComicJSON.self, from: comicJsonData)
                let folderName = comicJson.id

                // 5. Move to final location in Documents/Comics/{comicId}/
                let comicDir = localStorage.comicsDirectory.appendingPathComponent(folderName)

                // Remove existing if re-downloading
                if fm.fileExists(atPath: comicDir.path) {
                    try fm.removeItem(at: comicDir)
                }

                try fm.moveItem(at: tempDir, to: comicDir)

                downloadStates[comic.id] = .downloading(progress: 1.0)

                // 6. Done — clear image cache, URL cache, and unhide
                ComicImageLoader.shared.clearCache(forComic: folderName)
                URLCache.shared.removeAllCachedResponses()
                localStorage.unhideComic(folderName)
                if let bv = comic.bundleVersion, !bv.isEmpty {
                    downloadedBundleVersions[folderName] = bv
                }
                downloadStates[comic.id] = .downloaded
                await localStorage.loadDownloadedComics()

            } catch is CancellationError {
                // User cancelled — state already reset by cancelDownload
            } catch {
                if !Task.isCancelled {
                    downloadStates[comic.id] = .failed(error: error.localizedDescription)
                }
            }
        }
        activeDownloadTask = task
        await task.value
        activeDownloadTask = nil
        activeDownloadHelper = nil
    }

    /// Download a file with progress tracking
    private func downloadWithProgress(
        url: URL,
        comicId: String,
        downloadPhaseWeight: Double,
        estimatedSizeBytes: Int64 = 0
    ) async throws -> (URL, URLResponse) {
        let stableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(comicId).zip")
        if FileManager.default.fileExists(atPath: stableURL.path) {
            try FileManager.default.removeItem(at: stableURL)
        }

        let downloadHelper = DownloadHelper(destinationURL: stableURL, estimatedSize: estimatedSizeBytes) { progress in
            Task { @MainActor [weak self] in
                self?.downloadStates[comicId] = .downloading(progress: progress * downloadPhaseWeight)
            }
        }
        activeDownloadHelper = downloadHelper

        return try await downloadHelper.download(from: url)
    }

    /// Restore a hidden comic back to the library
    /// If the downloaded files were deleted, re-download from the server
    func restoreComic(_ comicId: String) async {
        let comicFolder = localStorage.comicsDirectory.appendingPathComponent(comicId)
        let hasDownloadedFiles = FileManager.default.fileExists(atPath: comicFolder.path)

        if hasDownloadedFiles {
            // Files still on disk — just unhide
            localStorage.unhideComic(comicId)
            await localStorage.loadDownloadedComics()
            downloadStates[comicId] = .downloaded
        } else if let storeComic = catalog.first(where: { $0.id == comicId }) {
            // Files were deleted (e.g. deleteComic removed them) — re-download fresh
            localStorage.unhideComic(comicId)
            await downloadComic(storeComic)
        } else {
            // No server entry found — just unhide and hope bundled version exists
            localStorage.unhideComic(comicId)
            await localStorage.loadDownloadedComics()
            downloadStates[comicId] = .downloaded
        }
    }

    /// Cancel an in-progress download
    func cancelDownload(_ comicId: String) {
        activeDownloadHelper?.cancel()
        activeDownloadHelper = nil
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        downloadStates[comicId] = .notDownloaded
        // Clean up any temp zip file
        let tempZip = FileManager.default.temporaryDirectory.appendingPathComponent("\(comicId).zip")
        try? FileManager.default.removeItem(at: tempZip)
    }

    /// Delete a downloaded comic (hides it; can be restored)
    func deleteDownload(_ comicId: String) {
        localStorage.deleteComic(comicId)
        downloadStates[comicId] = .hidden
    }

    /// Delete all comics in a collection (hides them all; can be restored individually)
    func deleteCollection(_ comicIds: [String]) {
        for comicId in comicIds {
            localStorage.deleteComic(comicId)
            downloadStates[comicId] = .hidden
        }
    }
}

// MARK: - Download Helper

/// Handles file download with progress using URLSessionDownloadDelegate
class DownloadHelper: NSObject, URLSessionDownloadDelegate {
    /// Background session completion handlers, keyed by session identifier
    static var backgroundCompletionHandlers: [String: () -> Void] = [:]

    private let destinationURL: URL
    private let estimatedSize: Int64
    private let onProgress: (Double) -> Void
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var downloadSession: URLSession?
    private var sessionIdentifier: String?

    init(destinationURL: URL, estimatedSize: Int64, onProgress: @escaping (Double) -> Void) {
        self.destinationURL = destinationURL
        self.estimatedSize = estimatedSize
        self.onProgress = onProgress
    }

    func download(from url: URL) async throws -> (URL, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let identifier = "com.comicreader.download.\(UUID().uuidString)"
            self.sessionIdentifier = identifier
            let config = URLSessionConfiguration.background(withIdentifier: identifier)
            config.isDiscretionary = false
            config.sessionSendsLaunchEvents = true
            // Never serve a bundle from cache. The /bundle URL is fixed per comic,
            // and the redirect target carries a long max-age, so without this the
            // background session replays a stale cached zip on every re-download —
            // a content update on the server would never reach the device.
            // (URLCache.shared.removeAllCachedResponses() does NOT clear a background
            // session's own cache, so disabling it here is the reliable fix.)
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.downloadSession = session
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let task = session.downloadTask(with: request)
            task.resume()
        }
    }

    func cancel() {
        downloadSession?.invalidateAndCancel()
        downloadSession = nil
    }

    // Called periodically with download progress
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected: Int64
        if totalBytesExpectedToWrite > 0 {
            expected = totalBytesExpectedToWrite
        } else if estimatedSize > 0 {
            expected = estimatedSize
        } else {
            return
        }
        let progress = min(Double(totalBytesWritten) / Double(expected), 0.99)
        onProgress(progress)
    }

    // Called when download finishes — move temp file to destination
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: location, to: destinationURL)
            if let response = downloadTask.response {
                continuation?.resume(returning: (destinationURL, response))
            } else {
                continuation?.resume(throwing: URLError(.badServerResponse))
            }
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
        session.invalidateAndCancel()
    }

    // Called on error
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation?.resume(throwing: error)
            continuation = nil
            session.invalidateAndCancel()
        }
    }

    // Called when all background events have been delivered
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let id = sessionIdentifier,
              let handler = DownloadHelper.backgroundCompletionHandlers.removeValue(forKey: id) else { return }
        DispatchQueue.main.async { handler() }
    }
}

