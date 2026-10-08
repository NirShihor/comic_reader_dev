import Foundation

// "Tap Download → the reader opens by itself once the comic can be read."
// A tap registers the wish; whichever card for that comic is on screen when
// the comic becomes available asks `comicToOpen` and gets it exactly once —
// several availability notifications, several cards, one navigation. The
// entitlement check is the caller's (the same one every open goes through);
// a locked comic is never handed out, and the wish is dropped so it can't
// open later behind the user's back.
@MainActor
final class InstantOpenCoordinator: ObservableObject {
    static let shared = InstantOpenCoordinator(localStorage: .shared)

    @Published private(set) var pending: Set<String> = []
    private let localStorage: LocalComicStorage

    init(localStorage: LocalComicStorage) {
        self.localStorage = localStorage
    }

    /// The user tapped Download: open the comic when it's available.
    func openWhenAvailable(_ comicId: String) { pending.insert(comicId) }

    /// Cancelled, deleted, failed for good, or opened — no automatic open.
    func forget(_ comicId: String) { pending.remove(comicId) }

    func isPending(_ comicId: String) -> Bool { pending.contains(comicId) }

    /// The comic to open now, if its open was requested, it's available and
    /// `unlocked` says the user may read it. Consumes the request.
    func comicToOpen(_ comicId: String, unlocked: () -> Bool) -> Comic? {
        comicToOpen(comicId, available: localStorage.availableComic(comicId), unlocked: unlocked)
    }

    /// The same, with the available comic supplied — for a view reacting to
    /// the availability publisher, which fires before storage has stored it.
    func comicToOpen(_ comicId: String, available comic: Comic?, unlocked: () -> Bool) -> Comic? {
        guard pending.contains(comicId), let comic else { return nil }
        pending.remove(comicId)
        return unlocked() ? comic : nil
    }
}
