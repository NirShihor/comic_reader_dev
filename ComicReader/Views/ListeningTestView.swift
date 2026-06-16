import SwiftUI

struct ListeningTestView: View {
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
                    systemImage: "headphones",
                    description: Text("This comic doesn't have vocabulary words for listening practice.")
                )
            } else if testComplete {
                testCompleteView
            } else if let word = currentWord {
                testCard(for: word)
            }
        }
        .navigationTitle("Listening Practice")
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
                print("[ListeningTest] WhisperService error: \(error)")
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

            // Prompt: play audio, ask for English meaning
            VStack(spacing: 12) {
                Text("What does this word mean?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Large speaker button to play/replay the Spanish word
                Button {
                    playWordAudio()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 80, height: 80)

                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.blue)
                    }
                }
                .explains("Play the word", "Tap to hear the Spanish word, then say what it means in English.")

                Text("Tap to hear the word")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        .explains("Previous", "Go back to the previous word.", id: "listening.resultPrev")
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
        .onAppear {
            // Auto-play the Spanish word when the card first appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                playWordAudio()
            }
        }
        .onChange(of: currentIndex) { _, _ in
            // Auto-play when advancing to next word
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                playWordAudio()
            }
        }
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
                            .fill(isRecording ? Color.red : Color.green)
                            .frame(width: 80, height: 80)

                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                }
                .explains("Record", "Tap to say the English meaning of the word, then tap again to stop and check it.")

                Text(isRecording ? "Tap to stop" : "Tap to speak the English meaning")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Replay, Hint, and Skip buttons
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
                    Label("Replay", systemImage: "speaker.wave.2")
                        .font(.subheadline)
                }
                .explains("Replay", "Play the Spanish word again.")

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
        VStack(spacing: 16) {
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

                HStack {
                    Text("Correct meaning:")
                        .foregroundStyle(.secondary)
                    Text(reviewWord.word.meaning)
                        .fontWeight(.semibold)
                }

                HStack {
                    Text("Spanish word:")
                        .foregroundStyle(.secondary)
                    Text(stripPunctuation(reviewWord.word.text).capitalized)
                        .fontWeight(.semibold)
                }

                HStack(spacing: 12) {
                    Button {
                        playWordAudio()
                    } label: {
                        Label("Listen", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.bordered)
                    .explains("Listen", "Hear the Spanish word spoken aloud again.", id: "listening.resultListen")

                    Button {
                        tryAgain()
                    } label: {
                        Label("Try Again", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .explains("Try Again", "Record the meaning of this word again.", id: "listening.resultTryAgain")
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
        print("[ListeningTest] startRecording tapped, current isRecording: \(isRecording)")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await whisperService.startRecording()
            isRecording = whisperService.isRecording
            print("[ListeningTest] after startRecording, isRecording: \(isRecording)")
        }
    }

    private func stopRecording() {
        print("[ListeningTest] stopRecording tapped")
        Task {
            let expectedMeaning = currentWord?.word.meaning ?? ""
            let transcription = await whisperService.stopRecording(
                expectedText: expectedMeaning,
                language: "en"
            )
            isRecording = false
            spokenText = transcription
            print("[ListeningTest] transcription: '\(transcription)'")

            isCorrect = compareMeaning(spoken: transcription, expected: expectedMeaning)

            if isCorrect {
                score += 1
            }

            UIImpactFeedbackGenerator(style: isCorrect ? .light : .medium).impactOccurred()
            showResult = true

            // Auto-play the Spanish word after showing result
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                playWordAudio()
            }
        }
    }

    /// Compare spoken English meaning against expected meaning with leniency
    private func compareMeaning(spoken: String, expected: String) -> Bool {
        let spokenNorm = normalizeMeaning(spoken)
        let expectedNorm = normalizeMeaning(expected)

        // Empty spoken text is always wrong
        if spokenNorm.isEmpty { return false }

        // Exact match after normalization
        if spokenNorm == expectedNorm { return true }

        // Check if one contains the other (handles "house" matching "the house")
        if spokenNorm.contains(expectedNorm) || expectedNorm.contains(spokenNorm) {
            return true
        }

        // Fuzzy match with relaxed threshold
        let (isMatch, matchScore) = whisperService.compareText(spoken: spokenNorm, expected: expectedNorm)
        if isMatch || matchScore >= 0.8 { return true }

        // Handle comma-separated alternatives (e.g., meaning = "house, home")
        let commaAlts = expected.split(separator: ",").map { normalizeMeaning(String($0)) }
        for alt in commaAlts where !alt.isEmpty {
            if spokenNorm == alt { return true }
            if spokenNorm.contains(alt) || alt.contains(spokenNorm) { return true }
            let (altMatch, altScore) = whisperService.compareText(spoken: spokenNorm, expected: alt)
            if altMatch || altScore >= 0.8 { return true }
        }

        // Handle semicolon-separated alternatives (e.g., "to be; to exist")
        let semiAlts = expected.split(separator: ";").map { normalizeMeaning(String($0)) }
        for alt in semiAlts where !alt.isEmpty {
            if spokenNorm == alt { return true }
            if spokenNorm.contains(alt) || alt.contains(spokenNorm) { return true }
        }

        // Handle slash-separated alternatives (e.g., "old/ancient")
        let slashAlts = expected.split(separator: "/").map { normalizeMeaning(String($0)) }
        for alt in slashAlts where !alt.isEmpty {
            if spokenNorm == alt { return true }
            if spokenNorm.contains(alt) || alt.contains(spokenNorm) { return true }
        }

        return false
    }

    /// Normalize English meaning text for comparison
    private func normalizeMeaning(_ text: String) -> String {
        var result = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")

        // Strip leading articles
        let articlePrefixes = ["the ", "a ", "an "]
        for prefix in articlePrefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
            }
        }

        // Strip "to " prefix for verbs (e.g., "to be" -> "be")
        if result.hasPrefix("to ") {
            result = String(result.dropFirst(3))
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nextWord() {
        if currentIndex < reviewWords.count - 1 {
            currentIndex += 1
            spokenText = ""
            showResult = false
            isCorrect = false
        } else {
            testComplete = true
        }
    }

    private func tryAgain() {
        spokenText = ""
        showResult = false
        isCorrect = false
    }

    private func previousWord() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        spokenText = ""
        showResult = false
        isCorrect = false
    }

    private func skipWord() {
        if currentIndex < reviewWords.count - 1 {
            currentIndex += 1
            spokenText = ""
            showResult = false
            isCorrect = false
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
    ListeningTestView(comic: ComicData.allComics[0])
}
