import SwiftUI

struct SpeakingTestView: View {
    let comic: Comic

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var whisperService = WhisperService.shared
    @ObservedObject private var audioManager = AudioManager.shared

    @State private var currentIndex = 0
    @State private var isRecording = false
    @State private var showResult = false
    @State private var isCorrect = false
    @State private var spokenText = ""
    @State private var score = 0
    @State private var testComplete = false
    @State private var showingContext = false
    @State private var dummyNavigateToPage: Int? = nil
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isGenderVariant = false
    @State private var isFormVariant = false
    @StateObject private var help = HelpModeController()

    var reviewWords: [ReviewWord] {
        comic.reviewWords ?? []
    }

    var currentWord: ReviewWord? {
        guard currentIndex < reviewWords.count else { return nil }
        return reviewWords[currentIndex]
    }

    var contextPage: Page? {
        guard let word = currentWord else { return nil }
        if let page = comic.pages.first(where: { $0.id == word.pageId }) {
            return page
        }
        return comic.pages.first(where: { page in
            page.panels.contains(where: { panel in
                panel.bubbles.contains(where: { bubble in
                    bubble.sentences.contains(where: { sentence in
                        sentence.words.contains(where: { $0.id == word.word.id })
                    })
                })
            })
        })
    }

    var contextPanel: Panel? {
        guard let word = currentWord, let page = contextPage else { return nil }
        if let panel = page.panels.first(where: { $0.id == word.panelId }) {
            return panel
        }
        return page.panels.first(where: { panel in
            panel.bubbles.contains(where: { bubble in
                bubble.sentences.contains(where: { sentence in
                    sentence.words.contains(where: { $0.id == word.word.id })
                })
            })
        })
    }

    var body: some View {
        Group {
            if reviewWords.isEmpty {
                ContentUnavailableView(
                    "No Words Available",
                    systemImage: "text.bubble",
                    description: Text("This comic doesn't have vocabulary words for speaking practice.")
                )
            } else if testComplete {
                testCompleteView
            } else if let word = currentWord {
                testCard(for: word)
            }
        }
        .navigationTitle("Speaking Practice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { help.toggle() }
                } label: {
                    Image(systemName: help.isActive ? "questionmark.circle.fill" : "questionmark.circle")
                }
            }
        }
        .onDisappear {
            whisperService.cancelRecording()
            whisperService.endCaptureSession()
        }
        .sheet(isPresented: $showingContext) {
            if let page = contextPage, let panel = contextPanel {
                PanelView(
                    comic: comic,
                    page: page,
                    panel: panel,
                    navigateToPage: $dummyNavigateToPage
                )
                .environmentObject(SettingsManager())
            }
        }
        .onChange(of: whisperService.error) { _, newError in
            if let error = newError {
                print("[SpeakingTest] WhisperService error: \(error)")
                errorMessage = error
                showingError = true
                isRecording = false
                whisperService.error = nil
            }
        }
        .alert("Speech Recognition Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .helpTooltipLayer()
        .environmentObject(help)
    }

    // MARK: - Test Card
    private func testCard(for reviewWord: ReviewWord) -> some View {
        VStack(spacing: 16) {
            // Progress
            ProgressView(value: Double(currentIndex), total: Double(reviewWords.count))
                .tint(.blue)
                .padding(.horizontal)

            Text("\(currentIndex + 1) of \(reviewWords.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Word prompt
            VStack(spacing: 12) {
                Text("Say this word in Spanish:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(reviewWord.word.meaning)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            // Recording or result
            if showResult {
                resultView(for: reviewWord)
            } else {
                recordingControls
            }

            Spacer()

            // Action button
            if showResult {
                HStack(spacing: 12) {
                    if currentIndex > 0 {
                        Button {
                            previousWord()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                                .padding()
                                .background(Color(.systemGray5))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .explains("Previous", "Go back to the previous word.", id: "speaking.resultPrev")
                    }
                    Button {
                        nextWord()
                    } label: {
                        Text(currentIndex < reviewWords.count - 1 ? "Next Word" : "See Results")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .explains("Next", "Continue to the next word, or see your results on the last one.")
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .padding()
    }

    // MARK: - Recording Controls
    private var recordingControls: some View {
        VStack(spacing: 16) {
            if whisperService.isProcessing {
                ProgressView("Processing...")
                    .padding()
            } else {
                Button {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red : Color.blue)
                            .frame(width: 80, height: 80)

                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                }
                .explains("Record", "Tap to start speaking the Spanish word, then tap again to stop and check it.")

                Text(isRecording ? "Tap to stop" : "Tap to speak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Listen, Hint, and Skip buttons
            HStack(spacing: 16) {
                Button {
                    previousWord()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .disabled(currentIndex == 0)
                .opacity(currentIndex == 0 ? 0.3 : 1)
                .explains("Previous", "Go back to the previous word.")

                Button {
                    playWordAudio()
                } label: {
                    Label("Listen", systemImage: "speaker.wave.2")
                        .font(.subheadline)
                }
                .explains("Listen", "Hear the correct Spanish word spoken aloud.")

                if contextPanel != nil {
                    Button {
                        showingContext = true
                    } label: {
                        Label("Hint", systemImage: "text.bubble")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.orange)
                    .explains("Hint", "Open the comic panel where this word appears for context.")
                }

                Button {
                    skipWord()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .explains("Skip", "Move on to the next word without answering.")
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Result View
    private func resultView(for reviewWord: ReviewWord) -> some View {
        let expectedWord = stripPunctuation(reviewWord.word.text)
        let contextSentence = findContextSentence(for: reviewWord)

        return VStack(spacing: 16) {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(isCorrect ? .green : .red)

            Text(isCorrect ? "Correct!" : "Not quite")
                .font(.title2)
                .fontWeight(.bold)

            VStack(spacing: 8) {
                if !spokenText.isEmpty {
                    Text("You said: \"\(spokenText)\"")
                        .foregroundStyle(.secondary)
                }

                if isGenderVariant {
                    // Gender variant — correct but explain the difference
                    VStack(spacing: 4) {
                        Text("\"\(spokenText.capitalized)\" is correct, but in this phrase the \(genderLabel(for: expectedWord)) form is used:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text(expectedWord.capitalized)
                            .fontWeight(.semibold)
                        if let sentence = contextSentence {
                            Text("\"" + sentence + "\"")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .italic()
                                .multilineTextAlignment(.center)
                                .padding(.top, 2)
                        }
                    }
                } else if isFormVariant {
                    // Different form of the same word — correct but explain
                    VStack(spacing: 4) {
                        Text("\"\(spokenText.capitalized)\" is another form of this word — in this phrase the comic uses:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text(expectedWord.capitalized)
                            .fontWeight(.semibold)
                        if let sentence = contextSentence {
                            Text("\"" + sentence + "\"")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .italic()
                                .multilineTextAlignment(.center)
                                .padding(.top, 2)
                        }
                    }
                } else {
                    HStack {
                        Text("Correct pronunciation:")
                            .foregroundStyle(.secondary)
                        Text(expectedWord.capitalized)
                            .fontWeight(.semibold)
                    }
                    if !isCorrect, let sentence = contextSentence {
                        Text("Used in: \"" + sentence + "\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        playWordAudio()
                    } label: {
                        Label("Listen", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.bordered)
                    .explains("Listen", "Hear the correct Spanish word spoken aloud.", id: "speaking.resultListen")

                    Button {
                        tryAgain()
                    } label: {
                        Label("Try Again", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .explains("Try Again", "Record this word again.", id: "speaking.resultTryAgain")
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Test Complete View
    private var testCompleteView: some View {
        VStack(spacing: 24) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 80))
                .foregroundStyle(.yellow)

            Text("Test Complete!")
                .font(.title)
                .fontWeight(.bold)

            Text("You got \(score) out of \(reviewWords.count) correct")
                .font(.title3)
                .foregroundStyle(.secondary)

            let percentage = Int((Double(score) / Double(reviewWords.count)) * 100)
            Text("\(percentage)%")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(percentage: percentage))

            Button {
                restartTest()
            } label: {
                Label("Try Again", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
            }
        }
        .padding()
    }

    // MARK: - Actions
    private func stripPunctuation(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "¿", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "¡", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "...", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "…", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startRecording() {
        print("[SpeakingTest] startRecording tapped, current isRecording: \(isRecording)")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await whisperService.startRecording()
            isRecording = whisperService.isRecording
            print("[SpeakingTest] after startRecording, isRecording: \(isRecording), whisper.isRecording: \(whisperService.isRecording), error: \(whisperService.error ?? "none")")
        }
    }

    private func genderLabel(for word: String) -> String {
        let w = word.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let feminineWords: Set<String> = ["la", "las", "una", "unas", "esta", "estas", "esa", "esas", "aquella", "aquellas", "nuestra", "nuestras", "vuestra", "vuestras", "suya", "suyas", "mia", "mias", "tuya", "tuyas"]
        if feminineWords.contains(w) || w.hasSuffix("a") || w.hasSuffix("as") {
            return "feminine"
        }
        return "masculine"
    }

    // Spanish gender/number variant pairs — spoken word maps to its counterpart(s)
    private static let genderVariants: [String: Set<String>] = {
        let pairs: [(String, String)] = [
            ("el", "la"), ("los", "las"),
            ("un", "una"), ("unos", "unas"),
            ("del", "de la"), ("al", "a la"),
            ("este", "esta"), ("estos", "estas"),
            ("ese", "esa"), ("esos", "esas"),
            ("aquel", "aquella"), ("aquellos", "aquellas"),
            ("nuestro", "nuestra"), ("nuestros", "nuestras"),
            ("vuestro", "vuestra"), ("vuestros", "vuestras"),
            ("suyo", "suya"), ("suyos", "suyas"),
            ("mío", "mía"), ("míos", "mías"),
            ("tuyo", "tuya"), ("tuyos", "tuyas"),
        ]
        var dict: [String: Set<String>] = [:]
        for (a, b) in pairs {
            let aLow = a.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let bLow = b.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            dict[aLow, default: []].insert(bLow)
            dict[bLow, default: []].insert(aLow)
        }
        return dict
    }()

    /// Check if the spoken word matches the word's base form or one of its listed forms
    /// (e.g. saying "escondo" when the comic uses "escondí")
    private func matchesKnownForm(_ spoken: String) -> Bool {
        guard let word = currentWord?.word else { return false }
        func norm(_ s: String) -> String {
            stripPunctuation(s)
                .folding(options: .diacriticInsensitive, locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let spokenNorm = norm(spoken)
        guard !spokenNorm.isEmpty else { return false }
        var candidates: [String] = []
        if let baseForm = word.baseForm { candidates.append(baseForm) }
        if let forms = word.forms { candidates.append(contentsOf: forms.map { $0.text }) }
        return candidates.contains { norm($0) == spokenNorm }
    }

    private func isGenderVariantMatch(spoken: String, expected: String) -> Bool {
        let spokenNorm = spoken.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedNorm = expected.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let variants = Self.genderVariants[expectedNorm], variants.contains(spokenNorm) {
            return true
        }
        // Also check adjective-style -o/-a endings (e.g., bueno/buena, pequeño/pequeña)
        if expectedNorm.count >= 4 {
            if (expectedNorm.hasSuffix("o") && spokenNorm == String(expectedNorm.dropLast()) + "a") ||
               (expectedNorm.hasSuffix("a") && spokenNorm == String(expectedNorm.dropLast()) + "o") ||
               (expectedNorm.hasSuffix("os") && spokenNorm == String(expectedNorm.dropLast(2)) + "as") ||
               (expectedNorm.hasSuffix("as") && spokenNorm == String(expectedNorm.dropLast(2)) + "os") {
                return true
            }
        }
        return false
    }

    private func stopRecording() {
        print("[SpeakingTest] stopRecording tapped")
        Task {
            let expectedWord = stripPunctuation(currentWord?.word.text ?? "")
            let transcription = await whisperService.stopRecording(expectedText: "The word is: \(expectedWord)")
            isRecording = false
            spokenText = transcription
            print("[SpeakingTest] transcription: '\(transcription)', error: \(whisperService.error ?? "none")")

            let spokenNorm = transcription.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let expectedNorm = expectedWord.lowercased()
            let isExact = spokenNorm == expectedNorm

            isFormVariant = false
            if isExact {
                // Exact match
                isCorrect = true
                isGenderVariant = false
            } else if isGenderVariantMatch(spoken: transcription, expected: expectedWord) {
                // Said the opposite gender form — accept but explain
                isCorrect = true
                isGenderVariant = true
            } else if matchesKnownForm(transcription) {
                // Said another known form of the word — accept but explain
                isCorrect = true
                isGenderVariant = false
                isFormVariant = true
            } else {
                // For short single words (≤3 chars), require exact match —
                // fuzzy matching is too lenient (e.g. "le" would match "la")
                if expectedNorm.count <= 3 && !spokenNorm.contains(" ") {
                    isCorrect = false
                } else {
                    let (correct, _) = whisperService.compareText(spoken: transcription, expected: expectedWord)
                    isCorrect = correct
                }
                isGenderVariant = false
            }

            if isCorrect {
                score += 1
            }

            UIImpactFeedbackGenerator(style: isCorrect ? .light : .medium).impactOccurred()
            showResult = true

            // Auto-play correct pronunciation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                playWordAudio()
            }
        }
    }

    private func nextWord() {
        if currentIndex < reviewWords.count - 1 {
            currentIndex += 1
            spokenText = ""
            showResult = false
            isCorrect = false
            isGenderVariant = false
            isFormVariant = false
        } else {
            testComplete = true
        }
    }

    private func tryAgain() {
        spokenText = ""
        showResult = false
        isCorrect = false
        isGenderVariant = false
        isFormVariant = false
    }

    private func previousWord() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        spokenText = ""
        showResult = false
        isCorrect = false
        isGenderVariant = false
        isFormVariant = false
    }

    private func skipWord() {
        if currentIndex < reviewWords.count - 1 {
            currentIndex += 1
            spokenText = ""
            showResult = false
            isCorrect = false
            isGenderVariant = false
            isFormVariant = false
        } else {
            testComplete = true
        }
    }

    private func restartTest() {
        currentIndex = 0
        spokenText = ""
        showResult = false
        isCorrect = false
        score = 0
        testComplete = false
    }

    private func playWordAudio() {
        guard let reviewWord = currentWord else { return }
        if let wordAudio = reviewWord.word.wordAudioUrl {
            audioManager.play(wordAudio)
        } else if let baseAudio = reviewWord.word.baseFormAudioUrl {
            audioManager.play(baseAudio)
        } else if let sentenceAudio = findSentenceAudio(for: reviewWord) {
            audioManager.play(sentenceAudio)
        } else {
            let audioName = stripPunctuation(reviewWord.word.text)
            audioManager.play(audioName)
        }
    }

    private func findSentenceAudio(for reviewWord: ReviewWord) -> String? {
        guard let page = comic.pages.first(where: { $0.id == reviewWord.pageId }),
              let panel = page.panels.first(where: { $0.id == reviewWord.panelId }) else {
            return nil
        }
        for bubble in panel.bubbles {
            for sentence in bubble.sentences {
                if sentence.words.contains(where: { $0.id == reviewWord.word.id }),
                   let audioUrl = sentence.audioUrl, !audioUrl.isEmpty {
                    return audioUrl
                }
            }
        }
        return nil
    }

    private func findContextSentence(for reviewWord: ReviewWord) -> String? {
        guard let page = comic.pages.first(where: { $0.id == reviewWord.pageId }),
              let panel = page.panels.first(where: { $0.id == reviewWord.panelId }) else {
            return nil
        }
        for bubble in panel.bubbles {
            for sentence in bubble.sentences {
                if sentence.words.contains(where: { $0.id == reviewWord.word.id }),
                   !sentence.text.isEmpty {
                    return sentence.text
                }
            }
        }
        return nil
    }

    private func scoreColor(percentage: Int) -> Color {
        switch percentage {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }
}

#Preview {
    SpeakingTestView(comic: ComicData.allComics[0])
}
