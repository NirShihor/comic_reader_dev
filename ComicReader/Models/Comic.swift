import Foundation

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
}

// MARK: - Sentence
struct Sentence: Identifiable, Codable, Hashable {
    let id: String
    let text: String
    var translation: String?
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
    var imageUrl: String?
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
    let slides: [HotspotSlide]
}

// MARK: - Page
struct Page: Identifiable, Codable, Hashable {
    let id: String
    let pageNumber: Int
    let masterImage: String
    var noTextImage: String?
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
    let description: String
    let coverImage: String
    let level: DifficultyLevel
    let isPremium: Bool
    let pages: [Page]
    var reviewWords: [ReviewWord]?

    // Collection fields (optional — comics without these are standalone)
    var collectionId: String?
    var collectionTitle: String?
    var collectionCoverImage: String?
    var episodeNumber: Int?

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
