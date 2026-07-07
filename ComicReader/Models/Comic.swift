import Foundation

// MARK: - WordForm
struct WordForm: Codable, Hashable {
    let label: String     // e.g. "Present", "Preterite", "Feminine plural"
    let text: String      // e.g. "escondo", "escondí", "altas"
    var audioUrl: String? // e.g. "words/escondo"
}

// MARK: - Word
struct Word: Identifiable, Codable, Hashable {
    let id: String
    let text: String
    let meaning: String
    var baseForm: String?
    var audioUrl: String?  // Legacy field
    var wordAudioUrl: String?  // Audio for the exact word as spoken
    var baseFormAudioUrl: String?  // Audio for the dictionary/base form
    var startTimeMs: Int?
    var endTimeMs: Int?
    var manual: Bool?
    var forms: [WordForm]?

    /// Word text with surrounding punctuation stripped (e.g. "¡Hola!" -> "Hola"),
    /// for places that show the word on its own rather than inside a sentence.
    var displayText: String {
        text.trimmingCharacters(in: CharacterSet.letters.union(.decimalDigits).inverted)
    }
}

// MARK: - Sentence
struct Sentence: Identifiable, Codable, Hashable {
    let id: String
    let text: String
    var translation: String?
    var grammarNote: String?
    var audioUrl: String?
    var translationAudioUrl: String?
    var alternativeTexts: [String]?
    var alternativeAudioUrls: [String]?
    let words: [Word]
}

// MARK: - Bubble
struct Bubble: Identifiable, Codable, Hashable {
    let id: String
    let type: BubbleType
    var isSoundEffect: Bool?
    var bgTransparent: Bool?   // borderless/transparent narration (e.g. "continuará") — no green highlight
    var imageUrl: String?
    var fontSize: Double?
    let positionX: Double  // percentage 0-1
    let positionY: Double
    let width: Double
    let height: Double
    let sentences: [Sentence]

    enum BubbleType: String, Codable, Hashable {
        case speech
        case narration
        case thought
        case image
    }
}

// MARK: - CornerPoint
struct CornerPoint: Codable, Hashable {
    let x: Double
    let y: Double
}

// MARK: - Panel
struct Panel: Identifiable, Codable, Hashable {
    let id: String
    let artworkImage: String
    var noTextImage: String?
    let floating: Bool
    var corners: [CornerPoint]?
    let panelOrder: Int
    // Tap zone coordinates for master page (percentage 0-1)
    let tapZoneX: Double
    let tapZoneY: Double
    let tapZoneWidth: Double
    let tapZoneHeight: Double
    let bubbles: [Bubble]
}

// MARK: - HotspotSlide
struct HotspotSlide: Identifiable, Codable, Hashable {
    let id: String
    var imageUrl: String?
    let text: String
    let translation: String
    var audioUrl: String?
    var translationAudioUrl: String?
    var speakingTest: Bool?
    let words: [Word]
}

// MARK: - Hotspot
struct Hotspot: Identifiable, Codable, Hashable {
    let id: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    var label: String?
    var borderColor: String?
    // Optional traced outline (normalized page coords). When present (>=3 points)
    // the reader draws this polygon instead of the x/y/width/height rectangle;
    // x/y/width/height remain the bounding box used for hit-testing and layout.
    var points: [CornerPoint]?
    // How much the traced cut-out enlarges at the pulse peak, as a fraction
    // (0.64 = grows 64%). Falls back to a default when unset.
    var pulseScale: Double?
    // Extra brightness added to the cut-out at the pulse peak (0.2 = +20%), so
    // the enlarged image stands out. Falls back to a default when unset.
    var pulseBrightness: Double?
    // Optional glow tint (hex) washed over the cut-out at the pulse peak; nil/empty = none.
    var pulseTint: String?
    let slides: [HotspotSlide]
}

// MARK: - Page
struct Page: Identifiable, Codable, Hashable {
    let id: String
    let pageNumber: Int
    let masterImage: String
    var noTextImage: String?
    var emptyBubblesImage: String? = nil   // bubbles drawn, text blank — for practice modes
    let panels: [Panel]
    var hotspots: [Hotspot]?
}

// MARK: - ReviewWord
struct ReviewWord: Codable, Hashable {
    let word: Word
    let panelId: String
    let pageId: String
}

// MARK: - Comic
struct Comic: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    var titleEn: String?   // optional English title, shown under the Spanish
    let description: String
    let coverImage: String
    var coverLandscape: String? = nil   // 3:2 banner for the detail view (falls back to coverImage)
    var bannerTitlePosition: String? = nil   // topLeft|topRight|bottomLeft|bottomRight|center|hidden
    var bubbleDotColor: String? = nil        // hex for the open-bubble flashing dot (per comic)
    let level: DifficultyLevel
    let isPremium: Bool
    let pages: [Page]
    var reviewWords: [ReviewWord]?

    // Collection fields (optional — comics without these are standalone)
    var collectionId: String?
    var collectionTitle: String?
    var collectionTitleEn: String?   // optional English collection title
    var collectionCoverImage: String?
    var episodeNumber: Int?

    /// Manual sort position set in the generator (lower = higher up).
    /// Falls back to title ordering when absent/equal.
    var order: Int?

    enum DifficultyLevel: String, Codable, Hashable {
        case beginner
        case intermediate
        case advanced

        var displayName: String {
            switch self {
            case .beginner: return "Beginner"
            case .intermediate: return "Intermediate"
            case .advanced: return "Advanced"
            }
        }

        var color: String {
            switch self {
            case .beginner: return "green"
            case .intermediate: return "orange"
            case .advanced: return "red"
            }
        }
    }
}

// MARK: - ComicCollection
struct ComicCollection: Identifiable, Hashable {
    let id: String
    let title: String
    let comics: [Comic]

    /// English collection title, derived from the first episode that carries one.
    var titleEn: String? {
        comics.compactMap { $0.collectionTitleEn }.first
    }

    /// The comic that provides the collection cover (prefers collection cover, falls back to first comic)
    private var coverComic: Comic? {
        comics.first(where: { $0.collectionCoverImage != nil }) ?? comics.first
    }

    var coverImage: String {
        if let colCover = coverComic?.collectionCoverImage {
            return colCover
        }
        return coverComic?.coverImage ?? ""
    }

    var coverComicId: String {
        coverComic?.id ?? ""
    }

    var episodeCount: Int {
        comics.count
    }

    var level: Comic.DifficultyLevel {
        comics.first?.level ?? .beginner
    }
}

// MARK: - LibraryItem
enum LibraryItem: Identifiable, Hashable {
    case standalone(Comic)
    case collection(ComicCollection)

    var id: String {
        switch self {
        case .standalone(let comic): return comic.id
        case .collection(let collection): return collection.id
        }
    }

    var sortTitle: String {
        switch self {
        case .standalone(let comic): return comic.title
        case .collection(let collection): return collection.title
        }
    }

    /// Manual sort position. A collection takes the lowest `order` among its
    /// episodes so it sits where the author placed that series.
    var sortOrder: Int {
        switch self {
        case .standalone(let comic):
            return comic.order ?? 0
        case .collection(let collection):
            return collection.comics.map { $0.order ?? 0 }.min() ?? 0
        }
    }
}

// MARK: - SavedWord
struct SavedWord: Identifiable, Codable, Hashable {
    var id: String { wordId }
    let wordId: String
    let word: Word
    let savedAt: Date
    var reviewState: ReviewState

    enum ReviewState: String, Codable, Hashable {
        case new
        case learning
        case mastered
    }
}

// MARK: - DictionaryEntry
struct DictionaryEntry: Codable, Hashable {
    let baseForm: String
    let meaning: String
    var partOfSpeech: PartOfSpeech?
    var audioUrl: String?

    enum PartOfSpeech: String, Codable, Hashable {
        case noun
        case verb
        case adjective
        case adverb
        case pronoun
        case preposition
        case conjunction
        case interjection
        case article
    }
}

// MARK: - ReadingProgress
struct ReadingProgress: Codable, Hashable {
    let comicId: String
    let pageNumber: Int
    let panelNumber: Int
    let updatedAt: Date
}
