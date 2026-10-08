import Foundation

/// WHEN the optional-analytics choice ("Help improve Comigo") is asked for —
/// not what it does. The request becomes eligible once the user has read a
/// few pages of a comic (enough to know what Comigo is), and the card is then
/// shown on the Library the next time they arrive there, once — never inside
/// the reader, never over the first-run tooltips or a replay of them, never
/// over another prompt.
///
/// Nothing here touches the choice itself (AnalyticsService, "analytics.consent")
/// or the anonymous aggregate counts (AggregateTelemetryService), which run
/// regardless.
@MainActor
final class AnalyticsConsentPrompt: ObservableObject {
    static let shared = AnalyticsConsentPrompt()

    /// Story-page views (the cover doesn't count) in a reading session before
    /// the request is eligible.
    static let pagesForEligibility = 3
    /// The only state: pages read so far, capped at the threshold. Persisted,
    /// so the milestone survives relaunches and is never undone by a restart
    /// of the comic, swiping back, or deleting it.
    static let pagesReadKey = "analytics.consentPrompt.pagesRead"

    @Published private(set) var pagesRead: Int

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pagesRead = min(Self.pagesForEligibility, max(0, defaults.integer(forKey: Self.pagesReadKey)))
    }

    /// The user has read enough of a comic for the request to be made.
    var isEligible: Bool { pagesRead >= Self.pagesForEligibility }

    /// The reader showed a story page in a plain reading session (the same
    /// moment it counts a page view; the reader leaves the cover out). Shows
    /// nothing — the card waits for the Library.
    func recordPageRead() {
        guard !isEligible else { return }
        pagesRead += 1
        defaults.set(pagesRead, forKey: Self.pagesReadKey)
    }

    /// Everything the Library knows at the moment it would show the card.
    struct Situation: Equatable {
        /// The stored choice, nil until one has been made (AnalyticsService.consent).
        var consent: AnalyticsConsent?
        /// The milestone above has been reached.
        var eligible: Bool
        /// A first-run tooltip is on screen, or help mode is replaying them.
        var onboardingActive: Bool
        /// Something else is being presented over the screen (a sheet, an offer).
        var otherPresentation: Bool
    }

    static func shouldShow(_ s: Situation) -> Bool {
        s.consent == nil && s.eligible && !s.onboardingActive && !s.otherPresentation
    }
}
