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

    enum CodingKeys: String, CodingKey {
        case id, title, description, coverThumbnailUrl, level
        case totalPages, estimatedMinutes, language, fileSizeMB, version, downloadUrl
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
    }

    init(id: String, title: String, description: String, coverThumbnailUrl: String,
         level: String, totalPages: Int, estimatedMinutes: Int, language: String,
         fileSizeMB: Double, version: String, downloadUrl: String) {
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

    /// Download a comic from the store
    func downloadComic(_ comic: StoreComic) async {
        downloadStates[comic.id] = .downloading(progress: 0)

        do {
            // 1. Fetch comic data + asset manifest
            guard let detailUrl = URL(string: "\(baseURL)\(comic.downloadUrl)") else {
                downloadStates[comic.id] = .failed(error: "Invalid download URL")
                return
            }

            let (detailData, _) = try await URLSession.shared.data(from: detailUrl)
            let response = try JSONDecoder().decode(ComicDownloadResponse.self, from: detailData)

            // 2. Create local directories using the comic.json id (e.g. "comic-conocer_a_los_padres")
            // This matches what ComicImageLoader expects when looking in Documents/Comics/
            let folderName = response.comic.id
            let comicDir = localStorage.comicsDirectory.appendingPathComponent(folderName)
            let imagesDir = comicDir.appendingPathComponent("images")
            let audioDir = comicDir.appendingPathComponent("audio")
            let wordsDir = audioDir.appendingPathComponent("words")

            let fm = FileManager.default
            try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: wordsDir, withIntermediateDirectories: true)

            // 3. Write comic.json
            let comicJsonData = try JSONEncoder().encode(response.comic)
            try comicJsonData.write(to: comicDir.appendingPathComponent("comic.json"))

            // 4. Download all assets with progress tracking
            let allAssets: [(serverPath: String, localUrl: URL)] =
                response.assets.images.map { ($0, imagesDir.appendingPathComponent(URL(string: $0)!.lastPathComponent)) } +
                response.assets.audio.map { ($0, audioDir.appendingPathComponent(URL(string: $0)!.lastPathComponent)) } +
                response.assets.wordAudio.map { ($0, wordsDir.appendingPathComponent(URL(string: $0)!.lastPathComponent)) }

            let totalFiles = allAssets.count
            var completed = 0

            // Download files with concurrency limit
            let batchSize = 4
            for batchStart in stride(from: 0, to: allAssets.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, allAssets.count)
                let batch = allAssets[batchStart..<batchEnd]

                try await withThrowingTaskGroup(of: Void.self) { group in
                    for asset in batch {
                        group.addTask {
                            guard let fileUrl = URL(string: "\(self.baseURL)\(asset.serverPath)") else { return }
                            let (fileData, _) = try await URLSession.shared.data(from: fileUrl)
                            try fileData.write(to: asset.localUrl)
                        }
                    }
                    try await group.waitForAll()
                }

                completed += batch.count
                downloadStates[comic.id] = .downloading(progress: Double(completed) / Double(max(totalFiles, 1)))
            }

            // 5. Done — unhide in case user previously deleted this comic
            localStorage.unhideComic(response.comic.id)
            downloadStates[comic.id] = .downloaded
            await localStorage.loadDownloadedComics()

        } catch {
            downloadStates[comic.id] = .failed(error: error.localizedDescription)
            // Clean up partial download
            let folderName = comic.id
            let comicDir = localStorage.comicsDirectory.appendingPathComponent(folderName)
            try? FileManager.default.removeItem(at: comicDir)
        }
    }

    /// Restore a hidden comic back to the library
    func restoreComic(_ comicId: String) async {
        localStorage.unhideComic(comicId)
        await localStorage.loadDownloadedComics()
        downloadStates[comicId] = .downloaded
    }

    /// Cancel an in-progress download
    func cancelDownload(_ comicId: String) {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        downloadStates[comicId] = .notDownloaded
    }

    /// Delete a downloaded comic
    func deleteDownload(_ comicId: String) {
        localStorage.deleteComic(comicId)
        downloadStates[comicId] = .notDownloaded
    }
}
