import SwiftUI

/// Key phrases — a speaking drill over the comic's everyday phrases.
/// Shows the English, the learner says the Spanish, the app grades it with the
/// same speech pipeline as the other speaking modes, then reveals the phrase
/// on its practice page (the full-page scene drawn for it) and plays the audio.
/// Before the reveal the page is shown WITHOUT the bubble text so the answer
/// isn't given away.
struct KeyPhrasePracticeView: View {
    let comic: Comic

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var progressManager: ReadingProgressManager
    @ObservedObject private var whisperService = WhisperService.shared
    @ObservedObject private var audioManager = AudioManager.shared

    @State private var currentIndex = 0
    @State private var isRecording = false
    @State private var showResult = false
    @State private var isCorrect = false
    @State private var spokenText = ""
    @State private var score = 0
    @State private var attempted = 0
    @State private var complete = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @StateObject private var help = HelpModeController()

    private let noAudioClip = "no_audio"   // "I couldn't quite hear you." (bundle mp3, shared with the other modes)

    private var phrases: [KeyPhrase] { comic.keyPhrases ?? [] }
    private var current: KeyPhrase? { currentIndex < phrases.count ? phrases[currentIndex] : nil }

    /// The practice page drawn for this phrase, if it has one.
    private func practicePage(for phrase: KeyPhrase) -> Page? {
        guard let pid = phrase.practicePageId else { return nil }
        return comic.practicePages?.first { $0.id == pid }
    }

    /// The bubble sentence on the practice page that holds the phrase — its
    /// audio is the "hear it" reveal.
    private func pageSentence(for phrase: KeyPhrase) -> Sentence? {
        guard let page = practicePage(for: phrase) else { return nil }
        let all = page.panels.flatMap { $0.bubbles }.flatMap { $0.sentences }
        let key = Self.normalize(phrase.es)
        return all.first { Self.normalize($0.text) == key } ?? all.first
    }

    /// Width/height of the page image (generator pages are 2:3; read the file
    /// so an odd-sized page still gets a snug border).
    private func pageAspectRatio(_ imageName: String) -> CGFloat {
        if let img = ComicImageLoader.shared.loadImage(named: imageName, forComic: comic.id), img.size.height > 0 {
            return img.size.width / img.size.height
        }
        return 2.0 / 3.0
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if phrases.isEmpty {
                ContentUnavailableView("No Key Phrases", systemImage: "quote.bubble",
                                       description: Text("This comic doesn't have key phrases yet."))
            } else if complete {
                completeView
            } else if let phrase = current {
                card(for: phrase)
            }
        }
        .navigationTitle("Key Phrases")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            audioManager.activeComicId = comic.id
            // Always start at the first phrase. The saved practice position is
            // shared with the sentence-based modes, so resuming from it landed
            // the learner mid-list on a different mode's bookmark.
            currentIndex = 0
        }
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
            audioManager.stop()
            whisperService.cancelRecording()
            whisperService.endCaptureSession()
        }
        .onChange(of: whisperService.error) { _, newError in
            if let error = newError {
                errorMessage = error
                showingError = true
                isRecording = false
                whisperService.error = nil
            }
        }
        .alert("Speech Recognition Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: { Text(errorMessage) }
        .helpTooltipLayer()
        .environmentObject(help)
    }

    // MARK: - Card

    private func card(for phrase: KeyPhrase) -> some View {
        let page = practicePage(for: phrase)
        // A ScrollView is the one container here that reliably keeps clear of
        // the navigation and tab bars; the content is kept short enough to fit
        // without actually scrolling. Swipe left/right moves between phrases.
        return ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView(value: Double(currentIndex), total: Double(phrases.count))
                        .tint(.blue)
                    Text("\(currentIndex + 1) of \(phrases.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .padding(.horizontal)

                if let page {
                    let imageName = showResult
                        ? page.masterImage
                        : (page.emptyBubblesImage ?? page.noTextImage ?? page.masterImage)
                    let ratio = pageAspectRatio(imageName)
                    let imageHeight: CGFloat = 340
                    ComicImage(imageName: imageName, comicId: comic.id)
                        .frame(width: imageHeight * ratio, height: imageHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.comigoInk, lineWidth: 2))
                        .explains("Scene", "The moment in the story where this phrase fits. The Spanish appears once you've said it.")
                }

                if !showResult {
                    Text("Say this in Spanish:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }

                HStack(spacing: 10) {
                    Text(phrase.en)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    // English audio from the practice page, when it was generated.
                    if let en = pageSentence(for: phrase)?.translationAudioUrl, !en.isEmpty {
                        Button { audioManager.stop(); audioManager.play(en) } label: {
                            Image(systemName: "speaker.wave.2.circle")
                                .font(.title2)
                        }
                        .foregroundStyle(.secondary)
                        .explains("Hear the English", "Play the English prompt.")
                    }
                }
                .padding(.horizontal)

                if showResult {
                    resultView(for: phrase)
                } else {
                    recordingControls(for: phrase)
                        .padding(.top, 6)
                }

                if showResult {
                    HStack(spacing: 12) {
                        if currentIndex > 0 {
                            Button { previous() } label: {
                                Image(systemName: "chevron.left")
                                    .font(.headline)
                                    .padding()
                                    .background(Color(.systemGray5))
                                    .foregroundStyle(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .explains("Previous", "Go back to the previous phrase.")
                        }
                        Button { next() } label: {
                            Text(currentIndex < phrases.count - 1 ? "Next phrase" : "See results")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .explains("Next", "Continue to the next phrase, or see your results on the last one.")
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .scrollBounceBehavior(.basedOnSize)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.5, abs(dx) > 60, !isRecording else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if dx < 0 { next() } else { previous() }
                    }
                }
        )
    }

    // MARK: - Recording

    private func recordingControls(for phrase: KeyPhrase) -> some View {
        VStack(spacing: 12) {
            if whisperService.isProcessing {
                ProgressView("Processing...").padding(.vertical, 8)
            } else {
                HStack(spacing: 14) {
                    Button {
                        if isRecording { stopRecording(for: phrase) } else { startRecording() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(isRecording ? Color.red : Color.blue)
                                .frame(width: 72, height: 72)
                            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                        }
                    }
                    .explains("Record", "Tap, say the phrase in Spanish, then tap again to check it.")
                    Text(isRecording ? "Tap to stop" : "Tap to speak")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 24) {
                Button { previous() } label: { Image(systemName: "backward.fill").font(.subheadline) }
                    .foregroundStyle(.secondary)
                    .disabled(currentIndex == 0)
                    .opacity(currentIndex == 0 ? 0.3 : 1)
                    .explains("Previous", "Go back to the previous phrase.")

                Button { reveal(for: phrase, correct: false, counted: false) } label: {
                    Label("Show me", systemImage: "eye")
                        .font(.subheadline)
                }
                .foregroundStyle(.orange)
                .explains("Show me", "Reveal the Spanish and hear it, without scoring this phrase.")

                Button { skip() } label: { Image(systemName: "forward.fill").font(.subheadline) }
                    .foregroundStyle(.secondary)
                    .explains("Skip", "Move on without answering.")
            }
        }
    }

    private func startRecording() {
        audioManager.stop()
        isRecording = true
        spokenText = ""
        Task { await whisperService.startRecording() }
    }

    private func stopRecording(for phrase: KeyPhrase) {
        Task {
            let transcription = await whisperService.stopRecording(expectedText: phrase.es, language: "es")
            isRecording = false
            // The learner may have moved on while this was being graded: never
            // land the old phrase's result (and its audio) on the new card.
            guard current?.id == phrase.id else { return }
            spokenText = transcription
            let trimmed = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty && !whisperService.lastAttemptHeardSpeech {
                // Nothing was said (stop tapped straight away, or silence): don't
                // reveal or score — say "I couldn't quite hear you" and stay on
                // the record screen, as the other speaking modes do.
                spokenText = ""
                if Bundle.main.url(forResource: noAudioClip, withExtension: "mp3") != nil {
                    audioManager.play(noAudioClip)
                }
                return
            }
            var correct = false
            if !trimmed.isEmpty {
                // Reject reading the English prompt aloud, then grade the Spanish.
                let spokeEnglish = whisperService.spokeEnglish(transcription: trimmed, expectedSpanish: phrase.es, expectedTranslation: phrase.en)
                if !spokeEnglish {
                    correct = whisperService.compareText(spoken: trimmed, expected: phrase.es, passThreshold: 0.85).isCorrect
                }
            }
            reveal(for: phrase, correct: correct, counted: true)
        }
    }

    /// Show the answer (page with the bubble text, Spanish line), play it.
    private func reveal(for phrase: KeyPhrase, correct: Bool, counted: Bool) {
        if isRecording { whisperService.cancelRecording(); isRecording = false }
        isCorrect = correct
        if counted {
            attempted += 1
            if correct { score += 1 }
            UIImpactFeedbackGenerator(style: correct ? .light : .medium).impactOccurred()
        }
        showResult = true
        // Auto-play only after a graded attempt; "Show me" just shows, and
        // the learner taps Listen when they want to hear it.
        if counted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if current?.id == phrase.id && showResult { playPhrase(phrase) }
            }
        }
    }

    private func playPhrase(_ phrase: KeyPhrase) {
        if let audio = pageSentence(for: phrase)?.audioUrl, !audio.isEmpty {
            audioManager.play(audio)
        }
    }

    // MARK: - Result

    private func resultView(for phrase: KeyPhrase) -> some View {
        VStack(spacing: 8) {
            if attemptedThisPhrase {
                HStack(spacing: 8) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(isCorrect ? .green : .red)
                    Text(isCorrect ? "Correct!" : "Not quite")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                if !spokenText.isEmpty {
                    Text("You said: \u{201C}\(spokenText)\u{201D}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Text(phrase.es)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.primary)   // black in light mode, white in dark
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            HStack(spacing: 20) {
                Button { playPhrase(phrase) } label: {
                    Label("Listen", systemImage: "speaker.wave.2").font(.subheadline)
                }
                .disabled((pageSentence(for: phrase)?.audioUrl ?? "").isEmpty)
                .explains("Listen", "Hear the phrase again.")
                Button { tryAgain() } label: {
                    Label("Try again", systemImage: "arrow.counterclockwise").font(.subheadline)
                }
                .explains("Try again", "Have another go at saying it.")
            }
        }
        .padding(.horizontal)
    }

    private var attemptedThisPhrase: Bool { !spokenText.isEmpty || isCorrect }

    // MARK: - Navigation

    private func resetCard() {
        spokenText = ""
        showResult = false
        isCorrect = false
        audioManager.stop()
    }
    private func next() {
        if currentIndex < phrases.count - 1 { currentIndex += 1; resetCard() } else { complete = true }
    }
    private func previous() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1; resetCard()
    }
    private func skip() { next() }
    private func tryAgain() { resetCard() }
    private func restart() {
        currentIndex = 0; score = 0; attempted = 0; complete = false; resetCard()
    }

    // MARK: - Complete

    private var completeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "quote.bubble.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)
            Text("Key phrases done")
                .font(.title2)
                .fontWeight(.bold)
            Text("\(score) of \(attempted) said right")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button { restart() } label: {
                Text("Practice again")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Button("Done") { dismiss() }
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
