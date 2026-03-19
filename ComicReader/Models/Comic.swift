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
    let words: [Word]
}

// MARK: - Bubble
struct Bubble: Identifiable, Codable, Hashable {
    let id: String
    let type: BubbleType
    var isSoundEffect: Bool?
    let positionX: Double  // percentage 0-1
    let positionY: Double
    let width: Double
    let height: Double
    let sentences: [Sentence]

    enum BubbleType: String, Codable, Hashable {
        case speech
        case narration
        case thought
    }
}

// MARK: - Panel
struct Panel: Identifiable, Codable, Hashable {
    let id: String
    let artworkImage: String
    let panelOrder: Int
    // Tap zone coordinates for master page (percentage 0-1)
    let tapZoneX: Double
    let tapZoneY: Double
    let tapZoneWidth: Double
    let tapZoneHeight: Double
    let bubbles: [Bubble]

    /// Returns the no-text version image name if available
    var noTextImage: String? {
        // No bubbles = no text, use regular image
        guard !bubbles.isEmpty else { return nil }
        // Convention: append _no_text before extension
        guard artworkImage.contains("_") else { return nil }
        return "\(artworkImage)_no_text"
    }
}

// MARK: - Page
struct Page: Identifiable, Codable, Hashable {
    let id: String
    let pageNumber: Int
    let masterImage: String
    let panels: [Panel]

    /// Returns the no-text version image name if available
    var noTextImage: String? {
        return "\(masterImage)_no_text"
    }
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
