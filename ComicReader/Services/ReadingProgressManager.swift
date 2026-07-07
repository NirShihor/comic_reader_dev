import Foundation
import SwiftUI

/// Where a practice run left off, so it can resume mid-session.
struct PracticePosition: Codable, Hashable {
    let index: Int   // 0-based sentence index
    let total: Int
}

@MainActor
class ReadingProgressManager: ObservableObject {
    @Published private(set) var progressMap: [String: ReadingProgress] = [:]
    @Published private(set) var practicePositions: [String: PracticePosition] = [:]
    /// Word-drill (Writing/Speaking/Listening) resume index per comic. Kept separate
    /// from `practicePositions` (sentence index) so the two index spaces don't collide.
    @Published private(set) var wordPositions: [String: Int] = [:]
    /// The bubble the on-screen "Read & speak" run was last on, so Continue reopens
    /// the same page at the same bubble.
    @Published private(set) var practiceBubbleIds: [String: String] = [:]
    /// Kind of the most recent interaction per comic: "reading" or "practice".
    @Published private(set) var interactionKinds: [String: String] = [:]
    /// Last practice mode used per comic, so Restart can relaunch the same one.
    @Published private(set) var practiceModes: [String: String] = [:]

    private let storageKey = "readingProgress"
    private let practiceKey = "practicePositions"
    private let wordKey = "wordDrillPositions"
    private let bubbleKey = "practiceBubbleIds"
    private let kindKey = "interactionKinds"
    private let modeStorageKey = "practiceModes"

    init() {
        loadProgress()
    }

    func getProgress(for comicId: String) -> ReadingProgress? {
        progressMap[comicId]
    }

    /// Reading position — also marks the last interaction as reading, unless
    /// `asPractice` is set (e.g. the on-screen "Read & speak" guided run, which
    /// still advances the page position but should count as practice).
    func saveProgress(comicId: String, pageNumber: Int, panelNumber: Int, asPractice: Bool = false) {
        progressMap[comicId] = ReadingProgress(
            comicId: comicId, pageNumber: pageNumber, panelNumber: panelNumber, updatedAt: Date()
        )
        interactionKinds[comicId] = asPractice ? "practice" : "reading"
        persistProgress()
    }

    /// Mark a comic as the most-recently-interacted-with via practice (e.g. when a
    /// practice session launches) without moving the reading position.
    func touchProgress(comicId: String) {
        let existing = progressMap[comicId]
        progressMap[comicId] = ReadingProgress(
            comicId: comicId,
            pageNumber: existing?.pageNumber ?? 1,
            panelNumber: existing?.panelNumber ?? 0,
            updatedAt: Date()
        )
        interactionKinds[comicId] = "practice"
        persistProgress()
    }

    /// Save how far a practice run has progressed (and mark practice as latest).
    func savePracticePosition(comicId: String, index: Int, total: Int) {
        practicePositions[comicId] = PracticePosition(index: index, total: total)
        touchProgress(comicId: comicId)   // also bumps recency + sets kind = practice
    }

    func practicePosition(for comicId: String) -> PracticePosition? {
        practicePositions[comicId]
    }

    /// Index a practice run should resume from (0 if none/at the end).
    func practiceStartIndex(for comicId: String) -> Int {
        practicePositions[comicId]?.index ?? 0
    }

    /// Clear the saved practice spot (e.g. when a run completes).
    func clearPracticePosition(for comicId: String) {
        practicePositions.removeValue(forKey: comicId)
        persistPracticePositions()
    }

    /// Save how far a word drill has progressed (and mark practice as latest).
    func saveWordPosition(comicId: String, index: Int) {
        wordPositions[comicId] = index
        touchProgress(comicId: comicId)
        persistWordPositions()
    }

    /// Word index a drill should resume from (0 if none).
    func wordStartIndex(for comicId: String) -> Int {
        wordPositions[comicId] ?? 0
    }

    /// Clear the saved word-drill spot (e.g. when a run completes or on Restart).
    func clearWordPosition(for comicId: String) {
        wordPositions.removeValue(forKey: comicId)
        persistWordPositions()
    }

    /// Remember the bubble the on-screen practice run is on.
    func savePracticeBubble(comicId: String, bubbleId: String) {
        practiceBubbleIds[comicId] = bubbleId
        persistPracticeBubbles()
    }

    /// The bubble an on-screen practice run should resume at (nil if none).
    func practiceBubbleId(for comicId: String) -> String? {
        practiceBubbleIds[comicId]
    }

    /// Clear the saved practice bubble (e.g. on Restart).
    func clearPracticeBubble(for comicId: String) {
        practiceBubbleIds.removeValue(forKey: comicId)
        persistPracticeBubbles()
    }

    func interactionKind(for comicId: String) -> String {
        interactionKinds[comicId] ?? "reading"
    }

    /// Record which practice mode was last launched for a comic.
    func setPracticeMode(_ comicId: String, mode: String) {
        practiceModes[comicId] = mode
        persistProgress()
    }

    /// The last practice mode used (empty string if none recorded).
    func lastPracticeMode(for comicId: String) -> String {
        practiceModes[comicId] ?? ""
    }

    func clearProgress(for comicId: String) {
        progressMap.removeValue(forKey: comicId)
        practicePositions.removeValue(forKey: comicId)
        wordPositions.removeValue(forKey: comicId)
        practiceBubbleIds.removeValue(forKey: comicId)
        interactionKinds.removeValue(forKey: comicId)
        practiceModes.removeValue(forKey: comicId)
        persistProgress()
    }

    private func loadProgress() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: ReadingProgress].self, from: data) {
            progressMap = decoded
        }
        if let data = UserDefaults.standard.data(forKey: practiceKey),
           let decoded = try? JSONDecoder().decode([String: PracticePosition].self, from: data) {
            practicePositions = decoded
        }
        if let data = UserDefaults.standard.data(forKey: wordKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            wordPositions = decoded
        }
        if let data = UserDefaults.standard.data(forKey: bubbleKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            practiceBubbleIds = decoded
        }
        if let data = UserDefaults.standard.data(forKey: kindKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            interactionKinds = decoded
        }
        if let data = UserDefaults.standard.data(forKey: modeStorageKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            practiceModes = decoded
        }
    }

    private func persistProgress() {
        if let data = try? JSONEncoder().encode(progressMap) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        if let data = try? JSONEncoder().encode(interactionKinds) {
            UserDefaults.standard.set(data, forKey: kindKey)
        }
        if let data = try? JSONEncoder().encode(practiceModes) {
            UserDefaults.standard.set(data, forKey: modeStorageKey)
        }
        persistPracticePositions()
    }

    private func persistPracticePositions() {
        if let data = try? JSONEncoder().encode(practicePositions) {
            UserDefaults.standard.set(data, forKey: practiceKey)
        }
    }

    private func persistWordPositions() {
        if let data = try? JSONEncoder().encode(wordPositions) {
            UserDefaults.standard.set(data, forKey: wordKey)
        }
    }

    private func persistPracticeBubbles() {
        if let data = try? JSONEncoder().encode(practiceBubbleIds) {
            UserDefaults.standard.set(data, forKey: bubbleKey)
        }
    }
}
