import SwiftUI

struct PanelView: View {
    let comic: Comic
    let page: Page
    let panel: Panel
    @Binding var navigateToPage: Int?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settingsManager: SettingsManager
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var whisperService = WhisperService.shared

    @State private var textRevealed = false
    @State private var translationRevealed = false
    @State private var currentSentenceIndex = 0
    @State private var highlightedWordIndex: Int?
    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var practiceFeedback: PracticeFeedback?
    @State private var currentPanelId: String
    @State private var showingError = false
    @State private var errorMessage = ""

    init(comic: Comic, page: Page, panel: Panel, navigateToPage: Binding<Int?>) {
        self.comic = comic
        self.page = page
        self.panel = panel
        self._navigateToPage = navigateToPage
        // Store the panel ID directly - no index calculations
        _currentPanelId = State(initialValue: panel.id)
    }

    struct PracticeFeedback {
        let isCorrect: Bool
        let spokenText: String
        let expectedText: String
    }

    // Panels sorted by panelOrder for consistent navigation
    var sortedPanels: [Panel] {
        page.panels.sorted { $0.panelOrder < $1.panelOrder }
    }

    // Find current panel by ID - always returns the correct panel
    var currentPanel: Panel {
        sortedPanels.first(where: { $0.id == currentPanelId }) ?? panel
    }

    // Get current index for display purposes
    var currentPanelIndex: Int {
        sortedPanels.firstIndex(where: { $0.id == currentPanelId }) ?? 0
    }

    var isLastPanel: Bool {
        currentPanelIndex >= sortedPanels.count - 1
    }

    var isFirstPanel: Bool {
        currentPanelIndex == 0
    }

    var hasNextPage: Bool {
        guard let pageIndex = comic.pages.firstIndex(where: { $0.id == page.id }) else { return false }
        return pageIndex < comic.pages.count - 1
    }

    var hasPreviousPage: Bool {
        guard let pageIndex = comic.pages.firstIndex(where: { $0.id == page.id }) else { return false }
        return pageIndex > 0
    }

    var currentSentence: Sentence? {
        let allSentences = currentPanel.bubbles.flatMap { $0.sentences }
        guard currentSentenceIndex < allSentences.count else { return nil }
        return allSentences[currentSentenceIndex]
    }

    var totalSentences: Int {
        currentPanel.bubbles.flatMap { $0.sentences }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Panel artwork
                    panelImage

                    // Speech bubbles / sentences
                    if let sentence = currentSentence {
                        sentenceCard(sentence)
                    } else if !currentPanel.bubbles.isEmpty {
                        // Fallback: show raw text if sentence parsing failed
                        Text("No sentence data")
                            .foregroundStyle(.secondary)
                    }

                    // Practice feedback
                    if let feedback = practiceFeedback {
                        feedbackCard(feedback)
                    }

                    // Sentence navigation
                    if totalSentences > 1 {
                        sentenceNavigation
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            let horizontalDistance = value.translation.width
                            if horizontalDistance > 50 {
                                // Swiped right → previous panel/page
                                goToPrevious()
                            } else if horizontalDistance < -50 {
                                // Swiped left → next panel/page
                                goToNext()
                            }
                        }
                )
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 20) {
                        Button {
                            goToPrevious()
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundStyle(isFirstPanel && !hasPreviousPage ? .gray : .blue)
                        }
                        .disabled(isFirstPanel && !hasPreviousPage)

                        Text("Panel \(currentPanelIndex + 1) of \(sortedPanels.count)")
                            .font(.headline)

                        Button {
                            goToNext()
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(isLastPanel && !hasNextPage ? .gray : .blue)
                        }
                        .disabled(isLastPanel && !hasNextPage)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .id(panel.id) // Force view recreation when panel changes
        .onChange(of: settingsManager.speakingPracticeMode) { _, _ in
            textRevealed = false
            practiceFeedback = nil
        }
        .onChange(of: whisperService.error) { _, newError in
            // Only show error if we have no transcribed text (actual failure)
            if let error = newError, whisperService.transcribedText.isEmpty {
                isRecording = false
                isProcessing = false
                errorMessage = error
                showingError = true
                whisperService.error = nil
            }
        }
        .onChange(of: audioManager.currentTime) { _, _ in
            // Update word highlighting based on audio position
            if let sentence = currentSentence {
                highlightedWordIndex = audioManager.currentWordIndex(for: sentence.words)
            }
        }
        .onChange(of: audioManager.isPlaying) { _, isPlaying in
            if !isPlaying {
                highlightedWordIndex = nil
            }
        }
        .onChange(of: settingsManager.playbackSpeed) { _, newSpeed in
            audioManager.setPlaybackRate(Float(newSpeed))
        }
        .onAppear {
            audioManager.setPlaybackRate(Float(settingsManager.playbackSpeed))
        }
        .alert("Speech Recognition Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Navigation
    private var currentPageIndex: Int {
        comic.pages.firstIndex(where: { $0.id == page.id }) ?? 0
    }

    private func goToNext() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if isLastPanel {
            // Navigate to next page then dismiss
            if hasNextPage {
                navigateToPage = currentPageIndex + 1
                dismiss()
            }
        } else {
            // Move to next panel by ID
            let nextIndex = currentPanelIndex + 1
            if nextIndex < sortedPanels.count {
                withAnimation {
                    currentPanelId = sortedPanels[nextIndex].id
                    resetPanelState()
                }
            }
        }
    }

    private func goToPrevious() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if isFirstPanel {
            // Navigate to previous page then dismiss
            if hasPreviousPage {
                navigateToPage = currentPageIndex - 1
                dismiss()
            }
        } else {
            // Move to previous panel by ID
            let prevIndex = currentPanelIndex - 1
            if prevIndex >= 0 {
                withAnimation {
                    currentPanelId = sortedPanels[prevIndex].id
                    resetPanelState()
                }
            }
        }
    }

    private func resetPanelState() {
        currentSentenceIndex = 0
        translationRevealed = false
        textRevealed = false
        practiceFeedback = nil
        audioManager.stop()
    }

    // MARK: - Panel Image
    private var panelImage: some View {
        let imageName = settingsManager.speakingPracticeMode && !textRevealed
            ? (currentPanel.noTextImage ?? currentPanel.artworkImage)
            : currentPanel.artworkImage

        return ZStack {
            ComicImage(imageName: imageName, comicId: comic.id)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 4)

            // Only show "Tap to reveal" if panel has text content (bubbles with sentences)
            let hasTextContent = currentPanel.bubbles.contains { !$0.sentences.isEmpty }
            if settingsManager.speakingPracticeMode && !textRevealed && hasTextContent {
                VStack {
                    Spacer()
                    Label("Tap to reveal", systemImage: "eye")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 12)
                }
            }
        }
        .onTapGesture {
            let hasTextContent = currentPanel.bubbles.contains { !$0.sentences.isEmpty }
            if settingsManager.speakingPracticeMode && hasTextContent {
                withAnimation {
                    textRevealed.toggle()
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        .id(currentPanel.id) // Force recreation when panel changes
    }

    // MARK: - Sentence Card
    private func sentenceCard(_ sentence: Sentence) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Main text (Spanish or English depending on mode)
            if settingsManager.speakingPracticeMode {
                // Show English translation
                Text(sentence.translation ?? "")
                    .font(.title3)
                    .fontWeight(.medium)
            } else {
                // Show Spanish word-by-word, or plain text if no words
                if sentence.words.isEmpty {
                    Text(sentence.text)
                        .font(.title3)
                        .fontWeight(.medium)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(Array(sentence.words.enumerated()), id: \.element.id) { index, word in
                            WordButton(
                                word: word,
                                isHighlighted: highlightedWordIndex == index
                            )
                        }
                    }
                }
            }

            // Translation (hidden until revealed in normal mode)
            if !settingsManager.speakingPracticeMode, let translation = sentence.translation {
                if translationRevealed {
                    Text(translation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        withAnimation {
                            translationRevealed = true
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Label("Show translation", systemImage: "eye")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }
            }

            Divider()

            // Audio/Recording controls
            HStack {
                if settingsManager.speakingPracticeMode {
                    // Mic button for practice
                    Button {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    } label: {
                        Label(
                            isRecording ? "Stop" : "Speak",
                            systemImage: isRecording ? "stop.fill" : "mic.fill"
                        )
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(isRecording ? Color.red : Color.blue)
                        .clipShape(Capsule())
                    }
                    .disabled(isProcessing)

                    if isProcessing {
                        ProgressView()
                            .padding(.leading, 8)
                    }
                } else {
                    // Play audio button
                    Button {
                        if audioManager.isPlaying {
                            audioManager.stop()
                        } else {
                            playAudio(sentence.audioUrl)
                        }
                    } label: {
                        Label(
                            audioManager.isPlaying ? "Stop" : "Play",
                            systemImage: audioManager.isPlaying ? "stop.fill" : "play.fill"
                        )
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(audioManager.isPlaying ? Color.red : Color.blue)
                        .clipShape(Capsule())
                    }
                }

                Spacer()

                // Playback speed
                Menu {
                    Button("0.5x") { settingsManager.playbackSpeed = 0.5 }
                    Button("0.75x") { settingsManager.playbackSpeed = 0.75 }
                    Button("1x") { settingsManager.playbackSpeed = 1.0 }
                    Button("1.25x") { settingsManager.playbackSpeed = 1.25 }
                } label: {
                    Text("\(settingsManager.playbackSpeed, specifier: "%.2g")x")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Feedback Card
    private func feedbackCard(_ feedback: PracticeFeedback) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: feedback.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(feedback.isCorrect ? .green : .red)
                Text(feedback.isCorrect ? "Correct!" : "Not quite")
                    .fontWeight(.semibold)
            }
            .font(.headline)

            if !feedback.isCorrect {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You said: \"\(feedback.spokenText)\"")
                        .font(.subheadline)
                    Text("Expected: \"\(feedback.expectedText)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    playAudio(currentSentence?.audioUrl)
                } label: {
                    Label("Listen", systemImage: "speaker.wave.2.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)

                Button {
                    practiceFeedback = nil
                } label: {
                    Label("Try Again", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(feedback.isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Sentence Navigation
    private var sentenceNavigation: some View {
        HStack {
            Button {
                if currentSentenceIndex > 0 {
                    currentSentenceIndex -= 1
                    practiceFeedback = nil
                    translationRevealed = false
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(currentSentenceIndex == 0)

            Spacer()

            Text("\(currentSentenceIndex + 1) / \(totalSentences)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                if currentSentenceIndex < totalSentences - 1 {
                    currentSentenceIndex += 1
                    practiceFeedback = nil
                    translationRevealed = false
                }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(currentSentenceIndex == totalSentences - 1)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions
    private func playAudio(_ url: String?) {
        guard let url = url else { return }
        audioManager.play(url)
    }

    private func startRecording() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await whisperService.startRecording()
            isRecording = whisperService.isRecording
        }
    }

    private func stopRecording() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isRecording = false
        isProcessing = true

        Task {
            let spokenText = await whisperService.stopRecording()
            let expectedText = currentSentence?.text ?? ""

            // Check for errors
            if let error = whisperService.error, spokenText.isEmpty {
                isProcessing = false
                errorMessage = error
                showingError = true
                whisperService.error = nil
                return
            }
            whisperService.error = nil

            // Compare spoken text with expected
            let (isCorrect, _) = whisperService.compareText(spoken: spokenText, expected: expectedText)

            // Small delay to let audio session switch back to playback
            try? await Task.sleep(nanoseconds: 300_000_000)

            isProcessing = false
            practiceFeedback = PracticeFeedback(
                isCorrect: isCorrect,
                spokenText: spokenText.isEmpty ? "(no speech detected)" : spokenText,
                expectedText: expectedText
            )
            // Auto-play correct pronunciation
            playAudio(currentSentence?.audioUrl)
        }
    }
}

// MARK: - Word Button
struct WordButton: View {
    let word: Word
    let isHighlighted: Bool
    @State private var showingDefinition = false
    @State private var isSaved = false
    @StateObject private var vocabularyManager = VocabularyManager()
    @StateObject private var audioManager = AudioManager.shared

    var body: some View {
        Button {
            showingDefinition = true
            // Check if word is already saved
            isSaved = vocabularyManager.savedWords.contains { $0.word.id == word.id }
        } label: {
            Text(word.text)
                .font(.body)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isHighlighted ? Color.yellow.opacity(0.3) : Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingDefinition) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(word.text)
                        .font(.headline)

                    Spacer()

                    // Play actual word from sentence (not base form)
                    Button {
                        // Use audioUrl if available, otherwise clean the word text
                        let cleanedText = word.text
                            .lowercased()
                            .replacingOccurrences(of: "¿", with: "")
                            .replacingOccurrences(of: "?", with: "")
                            .replacingOccurrences(of: "¡", with: "")
                            .replacingOccurrences(of: "!", with: "")
                            .replacingOccurrences(of: ".", with: "")
                            .replacingOccurrences(of: ",", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        // Remove accents for audio file lookup
                        let audioFile = word.audioUrl ?? (cleanedText.folding(options: .diacriticInsensitive, locale: .current))
                        audioManager.play(audioFile, volume: 1.0)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }

                Text(word.meaning)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let baseForm = word.baseForm, baseForm.lowercased() != word.text.lowercased() {
                    HStack {
                        Text("Base form: \(baseForm)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        // Play base form as alternative (30% quieter)
                        Button {
                            // Remove accents for audio file lookup
                            let audioFile = baseForm.lowercased().folding(options: .diacriticInsensitive, locale: .current)
                            audioManager.play(audioFile, volume: 1.0)
                        } label: {
                            Image(systemName: "speaker.wave.1.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                Button {
                    if isSaved {
                        vocabularyManager.removeWord(word.id)
                        isSaved = false
                    } else {
                        vocabularyManager.saveWord(word)
                        isSaved = true
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Label(
                        isSaved ? "Remove from Vocabulary" : "Add to Vocabulary",
                        systemImage: isSaved ? "bookmark.slash.fill" : "bookmark.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(isSaved ? .red : .blue)
                }
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .init(frame.size))
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}

#Preview {
    PanelView(
        comic: ComicData.allComics[0],
        page: ComicData.allComics[0].pages[0],
        panel: ComicData.allComics[0].pages[0].panels[0],
        navigateToPage: .constant(nil)
    )
    .environmentObject(SettingsManager())
}
