import Foundation
import SwiftUI

/// Manages locally stored/downloaded comics
@MainActor
class LocalComicStorage: ObservableObject {
    static let shared = LocalComicStorage()

    @Published private(set) var downloadedComics: [Comic] = []
    @Published private(set) var isLoading = false

    private let fileManager = FileManager.default
    private let hiddenComicsKey = "hiddenComicIds"

    /// IDs of comics the user has removed from their library
    private var hiddenComicIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: hiddenComicsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: hiddenComicsKey) }
    }

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

        // Also load bundled comics from app bundle
        let bundledComics = loadBundledComics()
        for bundledComic in bundledComics {
            if !comics.contains(where: { $0.id == bundledComic.id }) {
                comics.append(bundledComic)
            }
        }

        // Filter out comics the user has deleted
        let hidden = hiddenComicIds
        comics.removeAll { hidden.contains($0.id) }

        downloadedComics = comics.sorted { $0.title < $1.title }
    }

    /// Comics grouped into library items (standalone comics + collections)
    var libraryItems: [LibraryItem] {
        var items: [LibraryItem] = []
        var collectionMap: [String: [Comic]] = [:]

        for comic in downloadedComics {
            if let collectionId = comic.collectionId {
                collectionMap[collectionId, default: []].append(comic)
            } else {
                items.append(.standalone(comic))
            }
        }

        for (collectionId, comics) in collectionMap {
            let sorted = comics.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
            let title = sorted.first?.collectionTitle ?? "Collection"
            let collection = ComicCollection(id: collectionId, title: title, comics: sorted)
            items.append(.collection(collection))
        }

        return items.sorted { $0.sortTitle.localizedCaseInsensitiveCompare($1.sortTitle) == .orderedAscending }
    }

    /// Get the base path for a comic's assets
    func assetPath(for comicId: String) -> URL? {
        let comicFolder = comicsDirectory.appendingPathComponent(comicId)
        if fileManager.fileExists(atPath: comicFolder.path) {
            return comicFolder
        }
        return nil
    }

    /// Check if a comic is downloaded (and visible in library)
    func isDownloaded(_ comicId: String) -> Bool {
        downloadedComics.contains { $0.id == comicId }
    }

    /// Check if a comic exists on device (bundled or downloaded), even if hidden
    func existsOnDevice(_ comicId: String) -> Bool {
        // Check Documents/Comics
        let comicFolder = comicsDirectory.appendingPathComponent(comicId)
        if fileManager.fileExists(atPath: comicFolder.path) {
            return true
        }
        // Check BundledComics
        let slug = comicId.replacingOccurrences(of: "comic-", with: "")
        if let bundledURL = Bundle.main.url(forResource: "BundledComics", withExtension: nil) {
            let bundledFolder = bundledURL.appendingPathComponent(slug)
            if fileManager.fileExists(atPath: bundledFolder.path) {
                return true
            }
        }
        return false
    }

    /// Check if a comic has been hidden (deleted from library)
    func isHidden(_ comicId: String) -> Bool {
        hiddenComicIds.contains(comicId)
    }

    /// Unhide a comic (e.g. when re-downloaded from the store)
    func unhideComic(_ comicId: String) {
        hiddenComicIds.remove(comicId)
    }

    /// Delete a comic from the library
    func deleteComic(_ comicId: String) {
        // Remove from Documents/Comics if it exists there
        let comicFolder = comicsDirectory.appendingPathComponent(comicId)
        if fileManager.fileExists(atPath: comicFolder.path) {
            try? fileManager.removeItem(at: comicFolder)
        }

        // Mark as hidden so bundled comics don't reappear
        hiddenComicIds.insert(comicId)

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

    /// Load comics from the BundledComics folder in the app bundle
    private func loadBundledComics() -> [Comic] {
        guard let bundledComicsURL = Bundle.main.url(forResource: "BundledComics", withExtension: nil),
              let comicFolders = try? fileManager.contentsOfDirectory(at: bundledComicsURL, includingPropertiesForKeys: nil) else {
            return []
        }

        var comics: [Comic] = []
        for folder in comicFolders where folder.hasDirectoryPath {
            if let comic = loadComic(from: folder) {
                comics.append(comic)
            }
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

    // Collection fields (optional)
    let collectionId: String?
    let collectionTitle: String?
    let episodeNumber: Int?

    func toComic(basePath: URL) -> Comic {
        Comic(
            id: id,
            title: title,
            description: description,
            coverImage: coverImage,
            level: Comic.DifficultyLevel(rawValue: level) ?? .beginner,
            isPremium: false,
            pages: pages.map { $0.toPage() },
            reviewWords: reviewWords?.map { $0.toReviewWord() },
            collectionId: collectionId,
            collectionTitle: collectionTitle,
            episodeNumber: episodeNumber
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
                endTimeMs: nil,
                manual: nil
            )
            return ReviewWord(word: wordObj, panelId: "", pageId: "")
        }
    }
}

struct PageJSON: Codable {
    let id: String
    let pageNumber: Int
    let masterImage: String
    let noTextImage: String?
    let panels: [PanelJSON]

    func toPage() -> Page {
        Page(
            id: id,
            pageNumber: pageNumber,
            masterImage: masterImage,
            noTextImage: noTextImage,
            panels: panels.map { $0.toPanel() }
        )
    }
}

struct CornerPointJSON: Codable {
    let x: Double
    let y: Double
}

struct PanelJSON: Codable {
    let id: String
    let artworkImage: String
    let noTextImage: String?
    let floating: Bool?
    let corners: [CornerPointJSON]?
    let panelOrder: Int
    let tapZone: TapZoneJSON
    let bubbles: [BubbleJSON]

    func toPanel() -> Panel {
        Panel(
            id: id,
            artworkImage: artworkImage,
            noTextImage: noTextImage,
            floating: floating ?? false,
            corners: corners?.map { CornerPoint(x: $0.x, y: $0.y) },
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
    let isSoundEffect: Bool?
    let imageUrl: String?
    let position: PositionJSON
    let sentences: [SentenceJSON]

    func toBubble() -> Bubble {
        Bubble(
            id: id,
            type: Bubble.BubbleType(rawValue: type) ?? .speech,
            isSoundEffect: isSoundEffect,
            imageUrl: imageUrl,
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
    let alternativeTexts: [String]?
    let alternativeAudioUrls: [String]?
    let words: [WordJSON]

    func toSentence() -> Sentence {
        Sentence(
            id: id,
            text: text,
            translation: translation,
            audioUrl: audioUrl,
            alternativeTexts: alternativeTexts,
            alternativeAudioUrls: alternativeAudioUrls,
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
    let wordAudioUrl: String?
    let baseFormAudioUrl: String?
    let startTimeMs: Int?
    let endTimeMs: Int?
    let manual: Bool?

    func toWord() -> Word {
        Word(
            id: id,
            text: text,
            meaning: meaning,
            baseForm: baseForm,
            audioUrl: audioUrl,
            wordAudioUrl: wordAudioUrl,
            baseFormAudioUrl: baseFormAudioUrl,
            startTimeMs: startTimeMs,
            endTimeMs: endTimeMs,
            manual: manual
        )
    }
}
