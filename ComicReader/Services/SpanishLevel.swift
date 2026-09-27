import Foundation

/// The learner's self-reported Spanish level, asked once on first run and
/// changeable in Settings. Stored on the device regardless of analytics
/// consent (it may personalise the app later); sent to analytics only while
/// the user has opted in.
enum SpanishLevel: String, CaseIterable, Identifiable {
    case completeBeginner = "complete_beginner"
    case beginner
    case intermediate
    case advanced

    static let storageKey = "spanishLevel"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .completeBeginner: return "Complete beginner"
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }

    var detail: String {
        switch self {
        case .completeBeginner: return "I know little or no Spanish"
        case .beginner: return "I know some basic words and sentences"
        case .intermediate: return "I can understand and use Spanish in everyday situations"
        case .advanced: return "I can understand most everyday Spanish and hold conversations comfortably"
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> SpanishLevel? {
        defaults.string(forKey: storageKey).flatMap(SpanishLevel.init(rawValue:))
    }

    /// Saves the choice and, only if analytics is allowed right now, records
    /// `spanish_level_selected` (AnalyticsService drops it otherwise — a
    /// choice made before consent is never reported later). Re-selecting the
    /// current level is not a change and records nothing.
    @MainActor
    static func select(_ level: SpanishLevel, defaults: UserDefaults = .standard,
                       analytics: AnalyticsService = .shared) {
        guard stored(in: defaults) != level else { return }
        defaults.set(level.rawValue, forKey: storageKey)
        analytics.track(.spanishLevelSelected(level: level))
    }
}
