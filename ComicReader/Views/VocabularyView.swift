import SwiftUI

struct VocabularyView: View {
    @StateObject private var vocabularyManager = VocabularyManager()
    @StateObject private var comicStorage = LocalComicStorage.shared
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
                WordRow(savedWord: savedWord, comics: comicStorage.downloadedComics)
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
    let comics: [Comic]
    @StateObject private var audioManager = AudioManager.shared
    @State private var showingContext = false
    @State private var dummyNavigateToPage: Int? = nil

    /// Find the first comic/page/panel where this word appears
    private var wordContext: (comic: Comic, page: Page, panel: Panel)? {
        for comic in comics {
            for page in comic.pages {
                for panel in page.panels {
                    for bubble in panel.bubbles {
                        for sentence in bubble.sentences {
                            if sentence.words.contains(where: { $0.id == savedWord.word.id }) {
                                return (comic, page, panel)
                            }
                        }
                    }
                }
            }
        }
        return nil
    }

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

            // Hint button - show panel context
            if wordContext != nil {
                Button {
                    showingContext = true
                } label: {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }

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
        .sheet(isPresented: $showingContext) {
            if let context = wordContext {
                PanelView(
                    comic: context.comic,
                    page: context.page,
                    panel: context.panel,
                    navigateToPage: $dummyNavigateToPage
                )
                .environmentObject(SettingsManager())
            }
        }
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
