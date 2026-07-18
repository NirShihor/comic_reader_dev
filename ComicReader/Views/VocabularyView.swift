import SwiftUI
import AVFoundation

struct VocabularyView: View {
    @ObservedObject private var vocabularyManager = VocabularyManager.shared
    @StateObject private var comicStorage = LocalComicStorage.shared
    @State private var selectedFilter: SavedWord.ReviewState? = nil
    @State private var showingTest = false
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
            // Test mode hidden for now — needs a recorded audio per word
            // before we expose it (no Apple system voice). Re-enable when ready.
            // ToolbarItem(placement: .topBarTrailing) {
            //     if !vocabularyManager.savedWords.isEmpty {
            //         Button("Test") { showingTest = true }
            //             .fontWeight(.semibold)
            //     }
            // }
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
        .fullScreenCover(isPresented: $showingTest) {
            VocabularyTestView(
                words: filteredWords.isEmpty ? vocabularyManager.savedWords : filteredWords,
                manager: vocabularyManager
            )
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

    /// Find the first comic/page/bubble where this word appears
    private var wordContext: (comic: Comic, page: Page, bubble: Bubble)? {
        for comic in comics {
            for page in comic.pages {
                for panel in page.panels {
                    for bubble in panel.bubbles {
                        for sentence in bubble.sentences {
                            if sentence.words.contains(where: { $0.id == savedWord.word.id }) {
                                return (comic, page, bubble)
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
        .fullScreenCover(isPresented: $showingContext) {
            if let context = wordContext {
                NavigationStack {
                    PageView(
                        comic: context.comic,
                        page: context.page,
                        initialBubbleId: context.bubble.id,
                        savesProgress: false,
                        presentedModally: true
                    )
                }
                .environmentObject(SettingsManager())
                .environmentObject(ReadingProgressManager())
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

// MARK: - Vocabulary Test (speaking)

enum VocabTestDirection: String, CaseIterable, Identifiable {
    case spanishToEnglish
    case englishToSpanish
    var id: String { rawValue }
    var label: String {
        switch self {
        case .spanishToEnglish: return "Spanish → English"
        case .englishToSpanish: return "English → Spanish"
        }
    }
}

/// Spoken vocabulary test. Two directions:
/// • Spanish → English: the Spanish word is shown; the user says the meaning.
/// • English → Spanish: the meaning is spoken aloud; the Spanish word is hidden
///   and the user says it. Results feed the new/learning/mastered state.
struct VocabularyTestView: View {
    let words: [SavedWord]
    @ObservedObject var manager: VocabularyManager

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var whisper = WhisperService.shared
    @StateObject private var audio = AudioManager.shared

    @State private var direction: VocabTestDirection = .spanishToEnglish
    @State private var deck: [SavedWord] = []
    @State private var index = 0
    @State private var score = 0
    @State private var isRecording = false
    @State private var processing = false
    @State private var showResult = false
    @State private var isCorrect = false
    @State private var spokenText = ""
    @State private var complete = false
    @State private var errorMessage: String?
    @State private var synth = AVSpeechSynthesizer()

    private var current: SavedWord? { index < deck.count ? deck[index] : nil }
    private var spanishToEnglish: Bool { direction == .spanishToEnglish }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Direction", selection: $direction) {
                    ForEach(VocabTestDirection.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: direction) { _, _ in restart() }

                if complete {
                    completeView
                } else if let word = current {
                    Text("\(index + 1) of \(deck.count)")
                        .font(.caption).foregroundStyle(.secondary)
                    testCard(word)
                } else {
                    Spacer()
                    Text("No words to test yet.").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Vocabulary Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                restart()
                whisper.warmUpCapture()
            }
            .onDisappear {
                whisper.cancelRecording()
                whisper.endCaptureSession()
                synth.stopSpeaking(at: .immediate)
            }
            .alert("Speech error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    // MARK: Card

    @ViewBuilder
    private func testCard(_ word: SavedWord) -> some View {
        VStack(spacing: 18) {
            Text(spanishToEnglish ? "Say the meaning in English" : "Say the word in Spanish")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            if spanishToEnglish {
                Text(word.word.displayText)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                if hasAudio(word) {
                    Button { playWord(word) } label: {
                        Label("Hear it", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text(word.word.meaning)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                Button { speak(word.word.meaning) } label: {
                    Label("Hear again", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)
            }

            if showResult {
                resultView(word)
            } else {
                recordControls()
            }
        }
        .padding(.top, 12)
    }

    private func recordControls() -> some View {
        VStack(spacing: 10) {
            if processing {
                ProgressView("Checking…").padding()
            } else {
                Button { isRecording ? stopRecording() : startRecording() } label: {
                    ZStack {
                        Circle().fill(isRecording ? Color.red : Color.green)
                            .frame(width: 84, height: 84)
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.title).foregroundStyle(.white)
                    }
                }
                Text(isRecording ? "Tap to stop" : "Tap and speak")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func resultView(_ word: SavedWord) -> some View {
        VStack(spacing: 12) {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 46))
                .foregroundStyle(isCorrect ? .green : .red)
            Text(isCorrect ? "Correct!" : "Not quite")
                .font(.title3.weight(.bold))
            if !spokenText.isEmpty {
                Text("You said: “\(spokenText)”")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 6) {
                Text(spanishToEnglish ? "Meaning:" : "Answer:").foregroundStyle(.secondary)
                Text(spanishToEnglish ? word.word.meaning : word.word.displayText).fontWeight(.semibold)
            }
            .font(.subheadline)

            Button { next() } label: {
                Text(index + 1 < deck.count ? "Next" : "See results")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var completeView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "trophy.fill").font(.system(size: 60)).foregroundStyle(.yellow)
            Text("Test complete!").font(.title2.weight(.bold))
            Text("You got \(score) of \(deck.count) right").foregroundStyle(.secondary)
            Button { restart() } label: {
                Label("Test again", systemImage: "arrow.counterclockwise").font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: Flow

    private func restart() {
        deck = words.shuffled()
        index = 0; score = 0
        spokenText = ""; isCorrect = false; showResult = false; processing = false
        isRecording = false; complete = false
        whisper.cancelRecording()
        presentCurrent()
    }

    /// In English→Spanish the system speaks the meaning; the Spanish word stays
    /// hidden until the answer is revealed.
    private func presentCurrent() {
        if !spanishToEnglish, let w = current {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { speak(w.word.meaning) }
        }
    }

    private func next() {
        showResult = false
        spokenText = ""
        isCorrect = false
        if index + 1 < deck.count {
            index += 1
            presentCurrent()
        } else {
            complete = true
        }
    }

    private func startRecording() {
        spokenText = ""
        isRecording = true
        Task {
            whisper.onSilenceDetected = {
                if self.isRecording { self.stopRecording() }
            }
            await whisper.startRecording()
            isRecording = whisper.isRecording
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        processing = true
        whisper.onSilenceDetected = nil
        Task {
            guard let w = current else { processing = false; return }
            let transcription = await whisper.stopRecording(language: spanishToEnglish ? "en" : "es")
            spokenText = transcription
            let correct: Bool
            if spanishToEnglish {
                correct = compareMeaning(spoken: transcription, expected: w.word.meaning)
            } else {
                correct = whisper.compareText(spoken: transcription, expected: w.word.displayText).isCorrect
            }
            isCorrect = correct
            if correct { score += 1 }
            manager.updateReviewState(w.wordId, state: correct ? .mastered : .learning)
            processing = false
            showResult = true
        }
    }

    // MARK: Audio

    private func hasAudio(_ w: SavedWord) -> Bool {
        (w.word.wordAudioUrl?.isEmpty == false) || (w.word.audioUrl?.isEmpty == false)
    }

    private func playWord(_ w: SavedWord) {
        if let name = w.word.wordAudioUrl ?? w.word.audioUrl, !name.isEmpty {
            audio.play(name)
        }
    }

    private func speak(_ text: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)
    }

    // MARK: Lenient English-meaning comparison

    private func compareMeaning(spoken: String, expected: String) -> Bool {
        let s = normalizeMeaning(spoken)
        let e = normalizeMeaning(expected)
        if s.isEmpty { return false }
        if s == e || s.contains(e) || e.contains(s) { return true }
        let r = whisper.compareText(spoken: s, expected: e)
        if r.isCorrect { return true }
        for sep in [",", ";", "/"] as [Character] {
            for altRaw in expected.split(separator: sep) {
                let alt = normalizeMeaning(String(altRaw))
                if alt.isEmpty { continue }
                if s == alt || s.contains(alt) || alt.contains(s) { return true }
                if whisper.compareText(spoken: s, expected: alt).isCorrect { return true }
            }
        }
        return false
    }

    private func normalizeMeaning(_ text: String) -> String {
        var r = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for ch in [".", ",", "!", "?", "(", ")"] { r = r.replacingOccurrences(of: ch, with: "") }
        for p in ["the ", "a ", "an "] where r.hasPrefix(p) { r = String(r.dropFirst(p.count)) }
        if r.hasPrefix("to ") { r = String(r.dropFirst(3)) }
        return r.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
