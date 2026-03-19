import SwiftUI

struct QuizView: View {
    let comic: Comic
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex = 0
    @State private var userAnswer = ""
    @State private var showResult = false
    @State private var isCorrect = false
    @State private var score = 0
    @State private var quizComplete = false
    @State private var showingContext = false
    @State private var dummyNavigateToPage: Int? = nil
    @ObservedObject private var audioManager = AudioManager.shared

    var reviewWords: [ReviewWord] {
        comic.reviewWords ?? []
    }

    var currentWord: ReviewWord? {
        guard currentIndex < reviewWords.count else { return nil }
        return reviewWords[currentIndex]
    }

    var contextPage: Page? {
        guard let word = currentWord else { return nil }
        // Try by ID first, then search for the word in all pages
        if let page = comic.pages.first(where: { $0.id == word.pageId }) {
            return page
        }
        // Fallback: find first page containing this word
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
        // Try by ID first, then search for the word in panels
        if let panel = page.panels.first(where: { $0.id == word.panelId }) {
            return panel
        }
        // Fallback: find first panel containing this word
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
            if quizComplete {
                quizCompleteView
            } else if let word = currentWord {
                quizCard(for: word)
            } else {
                ContentUnavailableView(
                    "No Quiz Available",
                    systemImage: "brain.head.profile",
                    description: Text("This comic doesn't have vocabulary words for quizzing.")
                )
            }
        }
        .navigationTitle("Vocabulary Quiz")
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
    }

    // MARK: - Quiz Card
    private func quizCard(for reviewWord: ReviewWord) -> some View {
        VStack(spacing: 24) {
            // Progress
            ProgressView(value: Double(currentIndex), total: Double(reviewWords.count))
                .tint(.blue)
                .padding(.horizontal)

            Text("\(currentIndex + 1) of \(reviewWords.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Word prompt
            VStack(spacing: 12) {
                Text("What is the Spanish word for:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(reviewWord.word.meaning)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
            }
            .padding()

            // Answer input or result
            if showResult {
                resultView(for: reviewWord)
            } else {
                answerInput
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
            }
        }
        .padding()
    }

    // MARK: - Answer Input
    private var answerInput: some View {
        VStack(spacing: 16) {
            TextField("Type your answer...", text: $userAnswer)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .multilineTextAlignment(.center)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal)

            Button {
                checkAnswer()
            } label: {
                Text("Check Answer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(userAnswer.isEmpty ? Color.gray : Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(userAnswer.isEmpty)
            .padding(.horizontal)

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
        }
    }

    // MARK: - Result View
    private func resultView(for reviewWord: ReviewWord) -> some View {
        VStack(spacing: 16) {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(isCorrect ? .green : .red)

            Text(isCorrect ? "Correct!" : "Not quite")
                .font(.title2)
                .fontWeight(.bold)

            VStack(spacing: 8) {
                if !isCorrect {
                    Text("Your answer: \(userAnswer)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Correct answer:")
                        .foregroundStyle(.secondary)
                    Text(reviewWord.word.text)
                        .fontWeight(.semibold)
                }

                Button {
                    playWordAudio()
                } label: {
                    Label("Listen", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Quiz Complete View
    private var quizCompleteView: some View {
        VStack(spacing: 24) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 80))
                .foregroundStyle(.yellow)

            Text("Quiz Complete!")
                .font(.title)
                .fontWeight(.bold)

            Text("You got \(score) out of \(reviewWords.count) correct")
                .font(.title3)
                .foregroundStyle(.secondary)

            // Score percentage
            let percentage = reviewWords.isEmpty ? 0 : Int((Double(score) / Double(reviewWords.count)) * 100)
            Text("\(percentage)%")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(percentage: percentage))

            Button {
                restartQuiz()
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
    private func checkAnswer() {
        let normalizedAnswer = userAnswer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCorrect = (currentWord?.word.text ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Simple comparison - could add fuzzy matching later
        isCorrect = normalizedAnswer == normalizedCorrect ||
                    normalizedAnswer == normalizedCorrect.replacingOccurrences(of: "¡", with: "").replacingOccurrences(of: "!", with: "")

        if isCorrect {
            score += 1
        }

        UIImpactFeedbackGenerator(style: isCorrect ? .light : .medium).impactOccurred()
        showResult = true

        // Auto-play correct pronunciation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            playWordAudio()
        }
    }

    private func nextWord() {
        if currentIndex < reviewWords.count - 1 {
            currentIndex += 1
            userAnswer = ""
            showResult = false
            isCorrect = false
        } else {
            quizComplete = true
        }
    }

    private func skipWord() {
        if currentIndex < reviewWords.count - 1 {
            currentIndex += 1
            userAnswer = ""
            showResult = false
            isCorrect = false
        } else {
            quizComplete = true
        }
    }

    private func restartQuiz() {
        currentIndex = 0
        userAnswer = ""
        showResult = false
        isCorrect = false
        score = 0
        quizComplete = false
    }

    private func playWordAudio() {
        guard let reviewWord = currentWord else { return }
        if let wordAudio = reviewWord.word.wordAudioUrl {
            audioManager.play(wordAudio)
            if let baseAudio = reviewWord.word.baseFormAudioUrl, baseAudio != wordAudio {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    audioManager.play(baseAudio)
                }
            }
        } else if let baseAudio = reviewWord.word.baseFormAudioUrl {
            audioManager.play(baseAudio)
        } else {
            let audioName = reviewWord.word.text
                .lowercased()
                .replacingOccurrences(of: "¿", with: "")
                .replacingOccurrences(of: "?", with: "")
                .replacingOccurrences(of: "¡", with: "")
                .replacingOccurrences(of: "!", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            audioManager.play(audioName)
        }
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
    QuizView(comic: ComicData.allComics[0])
}
