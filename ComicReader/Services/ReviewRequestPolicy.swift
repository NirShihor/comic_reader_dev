import Foundation

/// WHEN Comigo asks iOS for the App Store rating dialog — not the dialog
/// itself (that's SwiftUI's `requestReview`; iOS decides whether anything
/// appears, and shows it at most a few times a year). The request becomes
/// eligible once the reader has finished two different comics, and is then
/// made on the Library the next time they arrive there with nothing else on
/// screen — never inside the reader, never straight after the End of Episode
/// card, never over a tooltip, a help replay, the creator message, the
/// analytics card, the reminder offer or an alert. Once per installation: the
/// fact that we asked is stored, so later versions don't ask again.
///
/// No question of our own comes first, and nothing is offered for a rating.
@MainActor
final class ReviewRequestPolicy: ObservableObject {
    static let shared = ReviewRequestPolicy()

    /// Different comics finished (the End of Episode moment of a plain reading
    /// session) before the request is eligible. Re-reading the same comic
    /// doesn't count twice.
    static let comicsForEligibility = 2
    /// The ids of the comics finished so far, kept only until the milestone is
    /// reached. Persisted, so it survives relaunches and deleting a comic.
    static let completedComicsKey = "review.completedComicIds"
    /// True once `requestReview` has been called on this installation.
    static let requestedKey = "review.requested"

    @Published private(set) var completedComicIds: Set<String>
    @Published private(set) var requested: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        completedComicIds = Set(defaults.stringArray(forKey: Self.completedComicsKey) ?? [])
        requested = defaults.bool(forKey: Self.requestedKey)
    }

    /// The reader has finished enough different comics.
    var isEligible: Bool { completedComicIds.count >= Self.comicsForEligibility }

    /// Eligible and not yet asked on this installation — the Library should
    /// make the request at the next quiet moment.
    var isDue: Bool { isEligible && !requested }

    /// The reader moved past the last page of `comicId` (the same moment the
    /// reminder service and analytics hear about it). Shows nothing — the
    /// request waits for the Library.
    func recordComicCompleted(_ comicId: String) {
        guard !isEligible, !completedComicIds.contains(comicId) else { return }
        completedComicIds.insert(comicId)
        defaults.set(Array(completedComicIds).sorted(), forKey: Self.completedComicsKey)
    }

    /// `requestReview` is about to be called. Remembered for good: iOS hides
    /// whether a dialog appeared, so "asked" means "we called it".
    func markRequested() {
        guard !requested else { return }
        requested = true
        defaults.set(true, forKey: Self.requestedKey)
    }

    /// Everything the Library knows at the moment it would make the request.
    struct Situation: Equatable {
        /// `isDue` above.
        var due: Bool
        /// A first-run tooltip is on screen, or help mode is replaying them.
        var onboardingActive: Bool
        /// Something else is up or about to be: a sheet, an offer, the
        /// analytics card, the creator banner, an alert.
        var otherPresentation: Bool
        /// The scene is in the foreground and active.
        var sceneActive: Bool
    }

    static func shouldRequest(_ s: Situation) -> Bool {
        s.due && s.sceneActive && !s.onboardingActive && !s.otherPresentation
    }
}
