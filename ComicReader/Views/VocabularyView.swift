import SwiftUI

struct VocabularyView: View {
    @StateObject private var vocabularyManager = VocabularyManager()
    @State private var selectedFilter: SavedWord.ReviewState? = nil

    var body: some View {
        Group {
            if vocabularyManager.savedWords.isEmpty {
                emptyState
            } else {
                wordList
            }
        }
        .navigationTitle("Vocabulary")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("All") { selectedFilter = nil }
                    Button("New") { selectedFilter = .new }
                    Button("Learning") { selectedFilter = .learning }
                    Button("Mastered") { selectedFilter = .mastered }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Saved Words", systemImage: "bookmark")
        } description: {
            Text("Tap on words while reading to save them to your vocabulary list.")
        }
    }

    // MARK: - Word List
    private var wordList: some View {
        List {
            ForEach(filteredWords) { savedWord in
                WordRow(savedWord: savedWord)
            }
            .onDelete(perform: deleteWords)
        }
    }

    private var filteredWords: [SavedWord] {
        if let filter = selectedFilter {
            return vocabularyManager.savedWords.filter { $0.reviewState == filter }
        }
        return vocabularyManager.savedWords
    }

    private func deleteWords(at offsets: IndexSet) {
        for index in offsets {
            let word = filteredWords[index]
            vocabularyManager.removeWord(word.wordId)
        }
    }

}

// MARK: - Word Row
struct WordRow: View {
    let savedWord: SavedWord
    @StateObject private var audioManager = AudioManager.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(savedWord.word.text)
                    .font(.headline)

                Text(savedWord.word.meaning)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let baseForm = savedWord.word.baseForm, baseForm != savedWord.word.text {
                    Text("Base: \(baseForm)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Review state indicator
            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)

            // Play audio button
            if let audioUrl = savedWord.word.audioUrl {
                Button {
                    audioManager.play(audioUrl)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var stateColor: Color {
        switch savedWord.reviewState {
        case .new: return .blue
        case .learning: return .orange
        case .mastered: return .green
        }
    }
}

#Preview {
    NavigationStack {
        VocabularyView()
    }
}
