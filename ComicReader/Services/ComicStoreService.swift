import Foundation
import SwiftUI

/// Represents a comic available in the store (not yet downloaded)
struct StoreComic: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let coverThumbnailUrl: String
    let level: String
    let totalPages: Int
    let estimatedMinutes: Int
    let language: String
    let fileSizeMB: Double
    let version: String
    let downloadUrl: String
    let collectionTitle: String?
    let episodeNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, description, coverThumbnailUrl, level
        case totalPages, estimatedMinutes, language, fileSizeMB, version, downloadUrl
        case collectionTitle, episodeNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        coverThumbnailUrl = try container.decodeIfPresent(String.self, forKey: .coverThumbnailUrl) ?? ""
        level = try container.decodeIfPresent(String.self, forKey: .level) ?? "beginner"
        totalPages = try container.decodeIfPresent(Int.self, forKey: .totalPages) ?? 0
        estimatedMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes) ?? 0
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "es"
        fileSizeMB = try container.decodeIfPresent(Double.self, forKey: .fileSizeMB) ?? 0
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "1.0"
        downloadUrl = try container.decodeIfPresent(String.self, forKey: .downloadUrl) ?? ""
        collectionTitle = try container.decodeIfPresent(String.self, forKey: .collectionTitle)
        episodeNumber = try container.decodeIfPresent(Int.self, forKey: .episodeNumber)
    }

    init(id: String, title: String, description: String, coverThumbnailUrl: String,
         level: String, totalPages: Int, estimatedMinutes: Int, language: String,
         fileSizeMB: Double, version: String, downloadUrl: String,
         collectionTitle: String? = nil, episodeNumber: Int? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.coverThumbnailUrl = coverThumbnailUrl
        self.level = level
        self.totalPages = totalPages
        self.estimatedMinutes = estimatedMinutes
        self.language = language
        self.fileSizeMB = fileSizeMB
        self.version = version
        self.downloadUrl = downloadUrl
        self.collectionTitle = collectionTitle
        self.episodeNumber = episodeNumber
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

    /// Get download state for a comic
    func downloadState(for comicId: String) -> DownloadState {
        downloadStates[comicId] ?? .notDownloaded
    }

    // MARK: - Downloads

    /// Download a comic from the store as a single ZIP bundle
    func downloadComic(_ comic: StoreComic) async {
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

                // 6. Done — unhide in case user previously deleted this comic
                localStorage.unhideComic(folderName)
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
    func restoreComic(_ comicId: String) async {
        localStorage.unhideComic(comicId)
        await localStorage.loadDownloadedComics()
        downloadStates[comicId] = .downloaded
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

    /// Delete a downloaded comic
    func deleteDownload(_ comicId: String) {
        localStorage.deleteComic(comicId)
        downloadStates[comicId] = .notDownloaded
    }
}

// MARK: - Download Helper

/// Handles file download with progress using URLSessionDownloadDelegate
class DownloadHelper: NSObject, URLSessionDownloadDelegate {
    private let destinationURL: URL
    private let estimatedSize: Int64
    private let onProgress: (Double) -> Void
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var downloadSession: URLSession?

    init(destinationURL: URL, estimatedSize: Int64, onProgress: @escaping (Double) -> Void) {
        self.destinationURL = destinationURL
        self.estimatedSize = estimatedSize
        self.onProgress = onProgress
    }

    func download(from url: URL) async throws -> (URL, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let config = URLSessionConfiguration.default
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.downloadSession = session
            let task = session.downloadTask(with: url)
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
}

