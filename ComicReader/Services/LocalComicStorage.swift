import Foundation
import SwiftUI

/// Manages locally stored/downloaded comics
@MainActor
class LocalComicStorage: ObservableObject {
    static let shared = LocalComicStorage()

    @Published private(set) var downloadedComics: [Comic] = []
    @Published private(set) var isLoading = false

    private let fileManager = FileManager.default

    /// Base directory for downloaded comics
    var comicsDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Comics", isDirectory: true)
    }

    init() {
        createComicsDirectoryIfNeeded()
        Task {
            await loadDownloadedComics()
        }
    }

    // MARK: - Public Methods

    /// Reload all downloaded comics from disk
    func loadDownloadedComics() async {
        isLoading = true
        defer { isLoading = false }

        var comics: [Comic] = []

        // Load from Documents/Comics
        if let comicFolders = try? fileManager.contentsOfDirectory(at: comicsDirectory, includingPropertiesForKeys: nil) {
            for folder in comicFolders where folder.hasDirectoryPath {
                if let comic = loadComic(from: folder) {
                    comics.append(comic)
                }
            }
        }

        // Also load bundled comics
        let bundledComics = loadBundledComics()
        for bundledComic in bundledComics {
            // Only add if not already downloaded
            if !comics.contains(where: { $0.id == bundledComic.id }) {
                comics.append(bundledComic)
            }
        }

        downloadedComics = comics.sorted { $0.title < $1.title }
    }

    /// Get the base path for a comic's assets
    func assetPath(for comicId: String) -> URL? {
        let comicFolder = comicsDirectory.appendingPathComponent(comicId)
        if fileManager.fileExists(atPath: comicFolder.path) {
            return comicFolder
        }
        return nil
    }

    /// Check if a comic is downloaded
    func isDownloaded(_ comicId: String) -> Bool {
        downloadedComics.contains { $0.id == comicId }
    }

    /// Delete a downloaded comic
    func deleteComic(_ comicId: String) throws {
        let comicFolder = comicsDirectory.appendingPathComponent(comicId)
        try fileManager.removeItem(at: comicFolder)
        downloadedComics.removeAll { $0.id == comicId }
    }

    /// Save a downloaded comic package (called by DownloadManager)
    func saveComic(id: String, data: Data) async throws {
        let comicFolder = comicsDirectory.appendingPathComponent(id)

        // Create folder
        try fileManager.createDirectory(at: comicFolder, withIntermediateDirectories: true)

        // Unzip data to folder (simplified - in real implementation use ZIPFoundation)
        // For now, we'll handle this in DownloadManager

        // Reload comics
        await loadDownloadedComics()
    }

    /// Calculate total storage used by downloaded comics
    func calculateStorageUsed() -> Int64 {
        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(at: comicsDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }

        return totalSize
    }

    // MARK: - Private Methods

    private func createComicsDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: comicsDirectory.path) {
            try? fileManager.createDirectory(at: comicsDirectory, withIntermediateDirectories: true)
        }
    }

    private func loadComic(from folder: URL) -> Comic? {
        let jsonFile = folder.appendingPathComponent("comic.json")

        guard let data = try? Data(contentsOf: jsonFile),
              let comicJSON = try? JSONDecoder().decode(ComicJSON.self, from: data) else {
            return nil
        }

        return comicJSON.toComic(basePath: folder)
    }

    /// Load all bundled comics from the app bundle
    private func loadBundledComics() -> [Comic] {
        var comics: [Comic] = []

        // Load from BundledComics folder in the app bundle
        guard let bundledComicsURL = Bundle.main.url(forResource: "BundledComics", withExtension: nil),
              let comicFolders = try? fileManager.contentsOfDirectory(at: bundledComicsURL, includingPropertiesForKeys: nil) else {
            // Fallback to hardcoded ComicData if bundle folder not found
            return ComicData.allComics
        }

        // Load all bundled comics
        for folder in comicFolders where folder.hasDirectoryPath {
            if let comic = loadComic(from: folder) {
                comics.append(comic)
            }
        }

        // Fallback to ComicData if no comics loaded
        if comics.isEmpty {
            return ComicData.allComics
        }

        return comics
    }
}

// MARK: - JSON Models for parsing comic.json

struct ComicJSON: Codable {
    let id: String
    let title: String
    let description: String
    let coverImage: String
    let level: String
    let totalPages: Int
    let estimatedMinutes: Int
    let language: String
    let targetLanguage: String
    let version: String
    let pages: [PageJSON]
    let reviewWords: [ReviewWordEntry]?

    func toComic(basePath: URL) -> Comic {
        Comic(
            id: id,
            title: title,
            description: description,
            coverImage: coverImage,
            level: Comic.DifficultyLevel(rawValue: level) ?? .beginner,
            isPremium: false,
            pages: pages.map { $0.toPage() },
            reviewWords: reviewWords?.map { $0.toReviewWord() }
        )
    }
}

/// Handles both old format { word, panelId, pageId } and new format (just WordJSON)
struct ReviewWordEntry: Codable {
    // Old format fields
    let word: WordJSON?
    let panelId: String?
    let pageId: String?

    // New format fields (word properties directly)
    let id: String?
    let text: String?
    let meaning: String?
    let baseForm: String?

    func toReviewWord() -> ReviewWord {
        if let word = word {
            // Old format
            return ReviewWord(
                word: word.toWord(),
                panelId: panelId ?? "",
                pageId: pageId ?? ""
            )
        } else {
            // New format - word properties are at top level
            let wordObj = Word(
                id: id ?? "",
                text: text ?? "",
                meaning: meaning ?? "",
                baseForm: baseForm,
                audioUrl: nil,
                startTimeMs: nil,
                endTimeMs: nil
            )
            return ReviewWord(word: wordObj, panelId: "", pageId: "")
        }
    }
}

struct PageJSON: Codable {
    let id: String
    let pageNumber: Int
    let masterImage: String
    let panels: [PanelJSON]

    func toPage() -> Page {
        Page(
            id: id,
            pageNumber: pageNumber,
            masterImage: masterImage,
            panels: panels.map { $0.toPanel() }
        )
    }
}

struct PanelJSON: Codable {
    let id: String
    let artworkImage: String
    let panelOrder: Int
    let tapZone: TapZoneJSON
    let bubbles: [BubbleJSON]

    func toPanel() -> Panel {
        Panel(
            id: id,
            artworkImage: artworkImage,
            panelOrder: panelOrder,
            tapZoneX: tapZone.x,
            tapZoneY: tapZone.y,
            tapZoneWidth: tapZone.width,
            tapZoneHeight: tapZone.height,
            bubbles: bubbles.map { $0.toBubble() }
        )
    }
}

struct TapZoneJSON: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct BubbleJSON: Codable {
    let id: String
    let type: String
    let position: PositionJSON
    let sentences: [SentenceJSON]

    func toBubble() -> Bubble {
        Bubble(
            id: id,
            type: Bubble.BubbleType(rawValue: type) ?? .speech,
            positionX: position.x,
            positionY: position.y,
            width: position.width,
            height: position.height,
            sentences: sentences.map { $0.toSentence() }
        )
    }
}

struct PositionJSON: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct SentenceJSON: Codable {
    let id: String
    let text: String
    let translation: String?
    let audioUrl: String?
    let words: [WordJSON]

    func toSentence() -> Sentence {
        Sentence(
            id: id,
            text: text,
            translation: translation,
            audioUrl: audioUrl,
            words: words.map { $0.toWord() }
        )
    }
}

struct WordJSON: Codable {
    let id: String
    let text: String
    let meaning: String
    let baseForm: String?
    let audioUrl: String?
    let startTimeMs: Int?
    let endTimeMs: Int?

    func toWord() -> Word {
        Word(
            id: id,
            text: text,
            meaning: meaning,
            baseForm: baseForm,
            audioUrl: audioUrl,
            startTimeMs: startTimeMs,
            endTimeMs: endTimeMs
        )
    }
}
