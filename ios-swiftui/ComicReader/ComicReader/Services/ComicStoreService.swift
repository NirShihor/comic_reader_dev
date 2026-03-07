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
}

/// Catalog response from the API
struct StoreCatalog: Codable {
    let comics: [StoreComic]
    let lastUpdated: String
}

/// Download state for a comic
enum DownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case failed(error: String)
}

/// Manages the comic store - fetching catalog and downloading comics
@MainActor
class ComicStoreService: ObservableObject {
    static let shared = ComicStoreService()

    // TODO: Replace with your actual API URL
    private let catalogUrl = "https://your-api.com/api/comics"
    private let baseDownloadUrl = "https://your-cdn.com/comics/"

    @Published private(set) var catalog: [StoreComic] = []
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var catalogError: String?
    @Published var downloadStates: [String: DownloadState] = [:]

    private let localStorage = LocalComicStorage.shared
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]

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
            // For development, use sample catalog
            // In production, fetch from actual URL:
            // let (data, _) = try await URLSession.shared.data(from: URL(string: catalogUrl)!)
            // let catalog = try JSONDecoder().decode(StoreCatalog.self, from: data)

            // Sample catalog for development
            catalog = sampleCatalog()

            // Update download states
            for comic in catalog {
                if localStorage.isDownloaded(comic.id) {
                    downloadStates[comic.id] = .downloaded
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
            // In production, download from actual URL:
            // let url = URL(string: comic.downloadUrl)!
            // let (tempUrl, _) = try await URLSession.shared.download(from: url)
            // try await unzipAndSave(comicId: comic.id, from: tempUrl)

            // For development, simulate download
            for i in 1...10 {
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                downloadStates[comic.id] = .downloading(progress: Double(i) / 10.0)
            }

            // Mark as downloaded (in production, would actually save files)
            downloadStates[comic.id] = .downloaded

            // Reload local storage
            await localStorage.loadDownloadedComics()

        } catch {
            downloadStates[comic.id] = .failed(error: error.localizedDescription)
        }
    }

    /// Cancel an in-progress download
    func cancelDownload(_ comicId: String) {
        downloadTasks[comicId]?.cancel()
        downloadTasks.removeValue(forKey: comicId)
        downloadStates[comicId] = .notDownloaded
    }

    /// Delete a downloaded comic
    func deleteDownload(_ comicId: String) {
        do {
            try localStorage.deleteComic(comicId)
            downloadStates[comicId] = .notDownloaded
        } catch {
            print("Failed to delete comic: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func unzipAndSave(comicId: String, from tempUrl: URL) async throws {
        // In production, use ZIPFoundation or similar to unzip
        // let comicFolder = localStorage.comicsDirectory.appendingPathComponent(comicId)
        // try FileManager.default.unzipItem(at: tempUrl, to: comicFolder)
    }

    /// Sample catalog for development
    private func sampleCatalog() -> [StoreComic] {
        [
            StoreComic(
                id: "alien-friend",
                title: "My Alien Friend",
                description: "A young girl discovers a friendly alien in her backyard. Perfect for beginners!",
                coverThumbnailUrl: "https://example.com/thumbs/alien.jpg",
                level: "beginner",
                totalPages: 6,
                estimatedMinutes: 15,
                language: "es",
                fileSizeMB: 12.5,
                version: "1.0",
                downloadUrl: "https://example.com/comics/alien-friend.zip"
            ),
            StoreComic(
                id: "cooking-adventure",
                title: "Cooking Adventure",
                description: "Learn Spanish through delicious recipes and kitchen vocabulary.",
                coverThumbnailUrl: "https://example.com/thumbs/cooking.jpg",
                level: "beginner",
                totalPages: 8,
                estimatedMinutes: 20,
                language: "es",
                fileSizeMB: 15.2,
                version: "1.0",
                downloadUrl: "https://example.com/comics/cooking-adventure.zip"
            ),
            StoreComic(
                id: "city-explorer",
                title: "City Explorer",
                description: "Navigate a Spanish city and learn directions, transportation, and more.",
                coverThumbnailUrl: "https://example.com/thumbs/city.jpg",
                level: "intermediate",
                totalPages: 10,
                estimatedMinutes: 25,
                language: "es",
                fileSizeMB: 18.7,
                version: "1.0",
                downloadUrl: "https://example.com/comics/city-explorer.zip"
            ),
            StoreComic(
                id: "mystery-museum",
                title: "Mystery at the Museum",
                description: "Solve a mystery while learning past tense and descriptive vocabulary.",
                coverThumbnailUrl: "https://example.com/thumbs/museum.jpg",
                level: "intermediate",
                totalPages: 12,
                estimatedMinutes: 30,
                language: "es",
                fileSizeMB: 22.1,
                version: "1.0",
                downloadUrl: "https://example.com/comics/mystery-museum.zip"
            ),
            StoreComic(
                id: "space-journey",
                title: "Space Journey",
                description: "An epic space adventure with advanced vocabulary and complex grammar.",
                coverThumbnailUrl: "https://example.com/thumbs/space.jpg",
                level: "advanced",
                totalPages: 15,
                estimatedMinutes: 40,
                language: "es",
                fileSizeMB: 28.5,
                version: "1.0",
                downloadUrl: "https://example.com/comics/space-journey.zip"
            )
        ]
    }
}
