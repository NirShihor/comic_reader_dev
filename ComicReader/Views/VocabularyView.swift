import SwiftUI

struct VocabularyView: View {
    @StateObject private var vocabularyManager = VocabularyManager()
    @StateObject private var comicStorage = LocalComicStorage.shared
    @State private var selectedFilter: SavedWord.ReviewState? = nil
    @StateObject private var help = HelpModeController()

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
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { help.toggle() }
                } label: {
                    Image(systemName: help.isActive ? "questionmark.circle.fill" : "questionmark.circle")
                }
            }
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
        .helpTooltipLayer()
        .environmentObject(help)
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
            if help.isActive {
                HelpHint(icon: "trash",
                         label: "Swipe to delete",
                         title: "Remove a word",
                         text: "Swipe left on any word in the list to delete it from your vocabulary.",
                         animatedSwipe: true)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(Array(filteredWords.enumerated()), id: \.element.id) { index, savedWord in
                WordRow(savedWord: savedWord,
                        comics: comicStorage.downloadedComics,
                        isFirst: index == 0)
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
    var isFirst: Bool = false
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
                Text(savedWord.word.displayText)
                    .font(.headline)

                Text(savedWord.word.meaning)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let baseForm = savedWord.word.baseForm, baseForm != savedWord.word.displayText {
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
                .explainsIf(isFirst, "Hint",
                            "Open the comic panel where this word appears, to see it in context.",
                            id: "vocab.hint")
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
                .explainsIf(isFirst, "Play",
                            "Hear this word spoken aloud in Spanish.",
                            id: "vocab.play")
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
