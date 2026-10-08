import Foundation
import SwiftUI

/// Manages locally stored/downloaded comics
@MainActor
class LocalComicStorage: ObservableObject {
    static let shared = LocalComicStorage()

    @Published private(set) var downloadedComics: [Comic] = []
    @Published private(set) var isLoading = false

    /// Comics still downloading progressively that can already be opened —
    /// comic.json and the image of the page the reader will show first have
    /// landed (see `InitialReaderPage`). Keyed by comic id. Never in
    /// `downloadedComics`: a partial comic is readable, not downloaded.
    @Published private(set) var availablePartials: [String: Comic] = [:]

    /// Per-comic sort order from the live catalog, keyed by comic id. Lets the
    /// Library reflect the author's order without re-exporting/re-downloading —
    /// it overrides the (possibly stale) `order` baked into each bundle.
    @Published private(set) var catalogOrders: [String: Int] = [:]

    private let fileManager = FileManager.default
    private let hiddenComicsKey = "hiddenComicIds"
    private let catalogOrdersKey = "catalogOrders"

    /// IDs of comics the user has removed from their library
    private var hiddenComicIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: hiddenComicsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: hiddenComicsKey) }
    }

    /// Base directory for downloaded comics
    let comicsDirectory: URL

    nonisolated static var defaultComicsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Comics", isDirectory: true)
    }

    init(comicsDirectory: URL = LocalComicStorage.defaultComicsDirectory) {
        self.comicsDirectory = comicsDirectory
        catalogOrders = (UserDefaults.standard.dictionary(forKey: catalogOrdersKey) as? [String: Int]) ?? [:]
        createComicsDirectoryIfNeeded()
        Task {
            await loadDownloadedComics()
        }
    }

    /// Refresh per-comic order from the live catalog. Call after fetching the
    /// catalog; the Library re-sorts immediately and the map is persisted for
    /// offline use.
    func updateCatalogOrders(_ orders: [String: Int]) {
        guard orders != catalogOrders else { return }
        catalogOrders = orders
        UserDefaults.standard.set(orders, forKey: catalogOrdersKey)
    }

    /// A comic's effective sort position: live catalog order if known, else the
    /// value baked into its bundle, else 0.
    func effectiveOrder(for comic: Comic) -> Int {
        catalogOrders[comic.id] ?? comic.order ?? 0
    }

    /// Order by effective order (lower first), then alphabetically.
    func ordersBefore(_ a: Comic, _ b: Comic) -> Bool {
        let ao = effectiveOrder(for: a), bo = effectiveOrder(for: b)
        if ao != bo { return ao < bo }
        return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }

    // MARK: - Public Methods

    /// Reload all downloaded comics from disk.
    /// The file reads + JSON decodes run OFF the main actor — decoding a whole
    /// library of multi-MB comic.json files on the main thread froze the app
    /// for seconds right after launch (taps silently dropped).
    func loadDownloadedComics() async {
        isLoading = true
        defer { isLoading = false }

        let dir = comicsDirectory
        var comics: [Comic] = await Task.detached(priority: .userInitiated) {
            var loaded: [Comic] = []
            if let comicFolders = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for folder in comicFolders where folder.hasDirectoryPath {
                    if let comic = Self.loadComic(from: folder) {
                        loaded.append(comic)
                    }
                }
            }
            // Also load bundled comics from app bundle
            for bundledComic in Self.loadBundledComics() {
                if !loaded.contains(where: { $0.id == bundledComic.id }) {
                    loaded.append(bundledComic)
                }
            }
            return loaded
        }.value

        // Filter out comics the user has deleted
        let hidden = hiddenComicIds
        comics.removeAll { hidden.contains($0.id) }

        downloadedComics = comics.sorted { ordersBefore($0, $1) }
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

        // Author-set order first (lower = higher up), then alphabetical. A
        // collection sits at the lowest effective order among its episodes.
        func itemOrder(_ item: LibraryItem) -> Int {
            switch item {
            case .standalone(let comic):
                return effectiveOrder(for: comic)
            case .collection(let collection):
                return collection.comics.map { effectiveOrder(for: $0) }.min() ?? 0
            }
        }
        return items.sorted { a, b in
            let ao = itemOrder(a), bo = itemOrder(b)
            if ao != bo { return ao < bo }
            return a.sortTitle.localizedCaseInsensitiveCompare(b.sortTitle) == .orderedAscending
        }
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

    // MARK: Partial downloads
    //
    // A progressive download (ProgressiveDownloader) builds the comic's folder
    // in place, file by file, and keeps `.partial.json` in it until every file
    // has landed. Such a folder is NOT a downloaded comic: it's skipped when
    // loading the library and doesn't count as existing on the device.

    /// The marker a folder carries while a progressive download is under way.
    nonisolated static func partialMarkerURL(in folder: URL) -> URL { folder.appendingPathComponent(PartialDownloadMarker.fileName) }

    nonisolated static func isPartial(folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: partialMarkerURL(in: folder).path)
    }

    /// A progressive download of this comic is on disk, unfinished.
    func isPartiallyDownloaded(_ comicId: String) -> Bool {
        Self.isPartial(folder: comicsDirectory.appendingPathComponent(comicId))
    }

    /// The comic's folder is complete on disk (comic.json, no marker) —
    /// whether or not it's hidden from the library.
    func isCompleteOnDisk(_ comicId: String) -> Bool {
        let folder = comicsDirectory.appendingPathComponent(comicId)
        return fileManager.fileExists(atPath: folder.appendingPathComponent("comic.json").path) && !Self.isPartial(folder: folder)
    }

    // MARK: Available partials (instant reading)

    /// The comic can be opened: it's downloaded, or it's a partial whose
    /// opening requirements have landed. Technically readable — entitlement
    /// is the detail screen's business, as for any comic.
    func isAvailable(_ comicId: String) -> Bool {
        isDownloaded(comicId) || availablePartials[comicId] != nil
    }

    /// The comic to open, if it can be: the downloaded one, else the partial.
    func availableComic(_ comicId: String) -> Comic? {
        downloadedComics.first { $0.id == comicId } ?? availablePartials[comicId]
    }

    /// The store found a partial's opening requirements on disk.
    func markPartialAvailable(_ comic: Comic) {
        guard !isDownloaded(comic.id), availablePartials[comic.id] == nil else { return }
        availablePartials[comic.id] = comic
    }

    /// The partial finished, was cancelled or deleted.
    func clearPartial(_ comicId: String) {
        availablePartials[comicId] = nil
    }

    /// The partial comic in `folder` if it can be opened now: comic.json is
    /// here, its id matches the folder (the reader loads assets by comic id),
    /// and the image the reader will show first exists. Off the main actor —
    /// it decodes comic.json.
    nonisolated static func openablePartial(in folder: URL, progress: ReadingProgress?) -> Comic? {
        guard isPartial(folder: folder), let comic = loadComicIncludingPartial(from: folder),
              comic.id == folder.lastPathComponent else { return nil }
        return openingImageExists(for: comic, in: folder, progress: progress) ? comic : nil
    }

    nonisolated static func openingImageExists(for comic: Comic, in folder: URL, progress: ReadingProgress?) -> Bool {
        guard let image = InitialReaderPage.openingImage(for: comic, progress: progress) else { return false }
        return ComicAssetPlan.imageEntryNames(image).contains { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

    /// Every file of the comic is here: a complete download or a bundled
    /// comic. Whole-comic modes (practice, tests, key phrases) need this; a
    /// comic still arriving isn't ready for them, however much has landed.
    func isWholeComicAvailable(_ comicId: String) -> Bool {
        if isCompleteOnDisk(comicId) { return true }
        if fileManager.fileExists(atPath: comicsDirectory.appendingPathComponent(comicId).path) { return false }
        return existsOnDevice(comicId)   // bundled
    }

    /// A comic from a folder whether or not it still carries the partial
    /// marker. The normal library path (`loadComic`, `loadDownloadedComics`,
    /// `existsOnDevice`) never does this; the instant-reading path does, via
    /// `openablePartial`, once the opening requirements are on disk.
    nonisolated static func loadComicIncludingPartial(from folder: URL) -> Comic? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("comic.json")),
              let comicJSON = try? JSONDecoder().decode(ComicJSON.self, from: data) else { return nil }
        return comicJSON.toComic(basePath: folder)
    }

    /// Check if a comic exists on device (bundled or downloaded), even if hidden
    func existsOnDevice(_ comicId: String) -> Bool {
        // Check Documents/Comics (a partial download doesn't count)
        let comicFolder = comicsDirectory.appendingPathComponent(comicId)
        if fileManager.fileExists(atPath: comicFolder.path) && !Self.isPartial(folder: comicFolder) {
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

        // Clear cached images so re-download shows fresh content
        ComicImageLoader.shared.clearCache(forComic: comicId)

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

    private nonisolated static func loadComic(from folder: URL) -> Comic? {
        // Still being downloaded progressively: not a comic yet.
        guard !isPartial(folder: folder) else { return nil }
        let jsonFile = folder.appendingPathComponent("comic.json")

        guard let data = try? Data(contentsOf: jsonFile),
              let comicJSON = try? JSONDecoder().decode(ComicJSON.self, from: data) else {
            return nil
        }

        return comicJSON.toComic(basePath: folder)
    }

    /// Load comics from the BundledComics folder in the app bundle
    private nonisolated static func loadBundledComics() -> [Comic] {
        guard let bundledComicsURL = Bundle.main.url(forResource: "BundledComics", withExtension: nil),
              let comicFolders = try? FileManager.default.contentsOfDirectory(at: bundledComicsURL, includingPropertiesForKeys: nil) else {
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
    let titleEn: String?
    let description: String
    let coverImage: String
    let coverLandscape: String?
    let bannerTitlePosition: String?
    let bubbleDotColor: String?
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
    let collectionTitleEn: String?
    let collectionCoverImage: String?
    let episodeNumber: Int?

    // Key phrases + practice pages (optional — older bundles lack them)
    let keyPhrases: [KeyPhraseJSON]?
    let practicePages: [PageJSON]?

    func toComic(basePath: URL) -> Comic {
        var comic = Comic(
            id: id,
            title: title,
            titleEn: titleEn,
            description: description,
            coverImage: coverImage,
            coverLandscape: coverLandscape,
            bannerTitlePosition: bannerTitlePosition,
            bubbleDotColor: bubbleDotColor,
            level: Comic.DifficultyLevel(rawValue: level) ?? .beginner,
            isPremium: false,
            pages: pages.map { $0.toPage() },
            reviewWords: reviewWords?.map { $0.toReviewWord() },
            collectionId: collectionId,
            collectionTitle: collectionTitle,
            collectionTitleEn: collectionTitleEn,
            collectionCoverImage: collectionCoverImage,
            episodeNumber: episodeNumber
        )
        comic.keyPhrases = keyPhrases?.map { $0.toKeyPhrase() }
        comic.practicePages = practicePages?.map { $0.toPage() }
        return comic
    }
}

struct KeyPhraseJSON: Codable {
    let id: String
    let es: String
    let en: String
    let kind: String?
    let sourcePages: [Int]?
    let practicePageId: String?

    func toKeyPhrase() -> KeyPhrase {
        KeyPhrase(id: id, es: es, en: en, kind: kind, sourcePages: sourcePages, practicePageId: practicePageId)
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

struct HotspotSlideJSON: Codable {
    let id: String
    let imageUrl: String?
    let text: String
    let translation: String
    let audioUrl: String?
    let translationAudioUrl: String?
    let words: [WordJSON]?

    func toHotspotSlide() -> HotspotSlide {
        HotspotSlide(
            id: id,
            imageUrl: imageUrl,
            text: text,
            translation: translation,
            audioUrl: audioUrl,
            translationAudioUrl: translationAudioUrl,
            words: (words ?? []).map { $0.toWord() }
        )
    }
}

struct HotspotJSON: Codable {
    let id: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let label: String?
    let borderColor: String?
    let points: [CornerPointJSON]?
    let pulseScale: Double?
    let pulseBrightness: Double?
    let pulseTint: String?
    let displayStyle: String?
    let buttonLabel: String?
    let triggerBubbleId: String?
    let advanceOnClose: Bool?
    let slides: [HotspotSlideJSON]

    func toHotspot() -> Hotspot {
        Hotspot(
            id: id,
            x: x,
            y: y,
            width: width,
            height: height,
            label: label,
            borderColor: borderColor,
            points: points?.map { CornerPoint(x: $0.x, y: $0.y) },
            pulseScale: pulseScale,
            pulseBrightness: pulseBrightness,
            pulseTint: pulseTint,
            displayStyle: displayStyle,
            buttonLabel: buttonLabel,
            triggerBubbleId: triggerBubbleId,
            advanceOnClose: advanceOnClose,
            slides: slides.map { $0.toHotspotSlide() }
        )
    }
}

struct PageJSON: Codable {
    let id: String
    let pageNumber: Int
    let masterImage: String
    let noTextImage: String?
    let emptyBubblesImage: String?
    let panels: [PanelJSON]
    let hotspots: [HotspotJSON]?
    let keyPhraseId: String?

    func toPage() -> Page {
        Page(
            id: id,
            pageNumber: pageNumber,
            masterImage: masterImage,
            noTextImage: noTextImage,
            emptyBubblesImage: emptyBubblesImage,
            panels: panels.map { $0.toPanel() },
            hotspots: hotspots?.map { $0.toHotspot() },
            keyPhraseId: keyPhraseId
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
    let bgTransparent: Bool?
    let hidden: Bool?
    let highlightWash: Bool?
    let textColor: String?
    let readingOrder: Int?
    let imageUrl: String?
    let position: PositionJSON
    let sentences: [SentenceJSON]

    func toBubble() -> Bubble {
        Bubble(
            id: id,
            type: Bubble.BubbleType(rawValue: type) ?? .speech,
            isSoundEffect: isSoundEffect,
            bgTransparent: bgTransparent,
            hidden: hidden,
            highlightWash: highlightWash,
            textColor: textColor,
            readingOrder: readingOrder,
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
    let grammarNote: String?
    let audioUrl: String?
    let translationAudioUrl: String?
    let alternativeTexts: [String]?
    let alternativeAudioUrls: [String]?
    let words: [WordJSON]

    func toSentence() -> Sentence {
        Sentence(
            id: id,
            text: text,
            translation: translation,
            grammarNote: grammarNote,
            audioUrl: audioUrl,
            translationAudioUrl: translationAudioUrl,
            alternativeTexts: alternativeTexts,
            alternativeAudioUrls: alternativeAudioUrls,
            words: words.map { $0.toWord() }
        )
    }
}

struct WordFormJSON: Codable {
    let label: String
    let text: String
    let audioUrl: String?

    func toWordForm() -> WordForm {
        WordForm(label: label, text: text, audioUrl: audioUrl)
    }
}

struct WordJSON: Codable {
    let id: String
    let text: String
    let meaning: String
    let baseForm: String?
    let baseMeaning: String?
    let audioUrl: String?
    let wordAudioUrl: String?
    let baseFormAudioUrl: String?
    let startTimeMs: Int?
    let endTimeMs: Int?
    let manual: Bool?
    let forms: [WordFormJSON]?

    func toWord() -> Word {
        Word(
            id: id,
            text: text,
            meaning: meaning,
            baseForm: baseForm,
            baseMeaning: baseMeaning,
            audioUrl: audioUrl,
            wordAudioUrl: wordAudioUrl,
            baseFormAudioUrl: baseFormAudioUrl,
            startTimeMs: startTimeMs,
            endTimeMs: endTimeMs,
            manual: manual,
            forms: forms?.map { $0.toWordForm() }
        )
    }
}

// MARK: - The reader's first page

/// Which page the reader shows first — the rule the comic screen's
/// "Start/Continue reading" uses: the saved reading position when the comic
/// has that page, otherwise the first page by number (every export's cover).
/// The instant-reading gate waits for exactly that page's image.
enum InitialReaderPage {
    static func page(for comic: Comic, progress: ReadingProgress?) -> Page? {
        if let progress, let page = comic.pages.first(where: { $0.pageNumber == progress.pageNumber }) {
            return page
        }
        return comic.pages.min { $0.pageNumber < $1.pageNumber }
    }

    /// The image plain reading draws for that page (the full bake with text).
    static func openingImage(for comic: Comic, progress: ReadingProgress?) -> String? {
        page(for: comic, progress: progress)?.masterImage
    }
}
