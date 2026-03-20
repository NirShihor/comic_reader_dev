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

                Text(isRecording ? "Tap to stop" : "Tap to speak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Listen, Hint, and Skip buttons
            HStack(spacing: 16) {
                Button {
                    playWordAudio()
                } label: {
                    Label("Listen", systemImage: "speaker.wave.2")
                        .font(.subheadline)
                }

                if contextPanel != nil {
                    Button {
                        showingContext = true
                    } label: {
                        Label("Hint", systemImage: "text.bubble")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.orange)
                }

                Button {
                    skipWord()
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
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
                    Text("Correct pronunciation:")
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

                    Button {
                        tryAgain()
                    } label: {
                        Label("Try Again", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
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

    private func stopRecording() {
        print("[SpeakingTest] stopRecording tapped")
        Task {
            let transcription = await whisperService.stopRecording()
            isRecording = false
            spokenText = transcription
            print("[SpeakingTest] transcription: '\(transcription)', error: \(whisperService.error ?? "none")")

            // Compare with expected word (strip punctuation for fair comparison)
            let expectedWord = stripPunctuation(currentWord?.word.text ?? "")
            let (correct, _) = whisperService.compareText(spoken: transcription, expected: expectedWord)
            isCorrect = correct

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
        } else {
            testComplete = true
        }
    }

    private func tryAgain() {
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
    SpeakingTestView(comic: ComicData.allComics[0])
}
