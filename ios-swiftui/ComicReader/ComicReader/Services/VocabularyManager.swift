import Foundation
import SwiftUI

@MainActor
class VocabularyManager: ObservableObject {
    @Published private(set) var savedWords: [SavedWord] = []

    private let storageKey = "savedVocabulary"

    init() {
        loadWords()
    }

    func saveWord(_ word: Word) {
        // Don't add duplicates
        guard !savedWords.contains(where: { $0.wordId == word.id }) else { return }

        let savedWord = SavedWord(
            wordId: word.id,
            word: word,
            savedAt: Date(),
            reviewState: .new
        )
        savedWords.append(savedWord)
        persistWords()
    }

    func removeWord(_ wordId: String) {
        savedWords.removeAll { $0.wordId == wordId }
        persistWords()
    }

    func updateReviewState(_ wordId: String, state: SavedWord.ReviewState) {
        if let index = savedWords.firstIndex(where: { $0.wordId == wordId }) {
            savedWords[index].reviewState = state
            persistWords()
        }
    }

    func isWordSaved(_ wordId: String) -> Bool {
        savedWords.contains { $0.wordId == wordId }
    }

    private func loadWords() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedWord].self, from: data) else {
            return
        }
        savedWords = decoded
    }

    private func persistWords() {
        guard let data = try? JSONEncoder().encode(savedWords) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
