import SwiftUI
import AVFoundation

struct HotspotView: View {
    let hotspot: Hotspot
    let comicId: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settingsManager: SettingsManager

    @State private var currentSlideIndex = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlayingAudio = false
    @State private var selectedWord: Word?

    // Test mode state
    @State private var isTestMode = false
    @State private var testMode: TestDirection = .enToEs
    @State private var testSlideIndex = 0
    @State private var isRecording = false
    @State private var showResult = false
    @State private var isCorrect = false
    @State private var spokenText = ""
    @State private var score = 0
    @State private var testComplete = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingHint = false

    @ObservedObject private var whisperService = WhisperService.shared

    enum TestDirection: String, CaseIterable {
        case enToEs = "EN → Spanish"
        case esToEn = "Spanish → EN"
    }

    private var currentSlide: HotspotSlide? {
        guard !hotspot.slides.isEmpty, currentSlideIndex < hotspot.slides.count else { return nil }
        return hotspot.slides[currentSlideIndex]
    }

    private var testSlides: [HotspotSlide] {
        hotspot.slides.filter { !$0.text.isEmpty && !$0.translation.isEmpty }
    }

    private var currentTestSlide: HotspotSlide? {
        guard !testSlides.isEmpty, testSlideIndex < testSlides.count else { return nil }
        return testSlides[testSlideIndex]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isTestMode {
                    if testComplete {
                        testCompleteView
                    } else {
                        testModeContent
                    }
                } else {
                    normalContent
                }
            }
            .contentShape(Rectangle())
            .gesture(
                isTestMode ? nil :
                DragGesture(minimumDistance: 50)
                    .onEnded { value in
                        let horizontal = value.translation.width
                        if horizontal > 50 && currentSlideIndex > 0 {
                            withAnimation { currentSlideIndex -= 1 }
                            stopAudio()
                        } else if horizontal < -50 && currentSlideIndex < hotspot.slides.count - 1 {
                            withAnimation { currentSlideIndex += 1 }
                            stopAudio()
                        }
                    }
            )
            .navigationTitle(isTestMode ? "Speaking Test" : (hotspot.label ?? "Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !testSlides.isEmpty {
                        Button(isTestMode ? "Back" : "Test") {
                            withAnimation {
                                if isTestMode {
                                    isTestMode = false
                                    resetTest()
                                } else {
                                    isTestMode = true
                                    resetTest()
                                }
                                stopAudio()
                            }
                        }
                        .foregroundColor(isTestMode ? .blue : .orange)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        stopAudio()
                        dismiss()
                    }
                }
            }
            .popover(item: $selectedWord) { word in
                VStack(alignment: .leading, spacing: 8) {
                    Text(word.text)
                        .font(.headline)
                    if !word.meaning.isEmpty {
                        Text(word.meaning)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    if let baseForm = word.baseForm, !baseForm.isEmpty, baseForm != word.text {
                        Text("Base: \(baseForm)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .presentationCompactAdaptation(.popover)
            }
            .onChange(of: whisperService.error) { _, newError in
                if let error = newError {
                    print("[HotspotTest] WhisperService error: \(error)")
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
            .sheet(isPresented: $showingHint) {
                if let slide = currentTestSlide {
                    NavigationStack {
                        VStack(spacing: 16) {
                            if let imageUrl = slide.imageUrl {
                                ComicImage(imageName: imageUrl, comicId: comicId)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .background(Color.black)
                            }

                            Text(testMode == .enToEs ? slide.text : slide.translation)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            Spacer()
                        }
                        .navigationTitle("Hint")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showingHint = false }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Normal Content

    private var normalContent: some View {
        VStack(spacing: 0) {
            // Slide image
            if let slide = currentSlide, let imageUrl = slide.imageUrl {
                ComicImage(imageName: imageUrl, comicId: comicId)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: UIScreen.main.bounds.height * 0.4)
                    .clipped()
                    .background(Color.black)
            }

            // Content area
            if let slide = currentSlide {
                VStack(spacing: 12) {
                    if !slide.text.isEmpty {
                        Text(slide.text)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    if !slide.translation.isEmpty {
                        Text(slide.translation)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    HStack(spacing: 16) {
                        if slide.audioUrl != nil {
                            Button {
                                playAudio(slide.audioUrl!, isTranslation: false)
                            } label: {
                                Label("Play", systemImage: "speaker.wave.2.fill")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                        if slide.translationAudioUrl != nil {
                            Button {
                                playAudio(slide.translationAudioUrl!, isTranslation: true)
                            } label: {
                                Label("EN", systemImage: "speaker.wave.2")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.purple)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.top, 4)

                    if !slide.words.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(slide.words) { word in
                                    Button {
                                        selectedWord = word
                                    } label: {
                                        Text(word.text)
                                            .font(.subheadline)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.cyan.opacity(0.15))
                                            .foregroundColor(.primary)
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.cyan.opacity(0.4), lineWidth: 1)
                                            )
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical, 16)
            }

            Spacer()

            // Navigation controls
            HStack {
                Button {
                    withAnimation { currentSlideIndex = max(0, currentSlideIndex - 1) }
                    stopAudio()
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(currentSlideIndex > 0 ? .blue : .gray)
                }
                .disabled(currentSlideIndex == 0)

                Spacer()

                Text("\(currentSlideIndex + 1) / \(hotspot.slides.count)")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    withAnimation { currentSlideIndex = min(hotspot.slides.count - 1, currentSlideIndex + 1) }
                    stopAudio()
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(currentSlideIndex < hotspot.slides.count - 1 ? .blue : .gray)
                }
                .disabled(currentSlideIndex >= hotspot.slides.count - 1)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Test Mode Content

    private var testModeContent: some View {
        VStack(spacing: 16) {
            // Mode picker
            Picker("Direction", selection: $testMode) {
                ForEach(TestDirection.allCases, id: \.self) { direction in
                    Text(direction.rawValue).tag(direction)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)
            .onChange(of: testMode) { _, _ in
                resetTest()
            }

            // Progress
            ProgressView(value: Double(testSlideIndex), total: Double(testSlides.count))
                .tint(.orange)
                .padding(.horizontal)

            Text("\(testSlideIndex + 1) of \(testSlides.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let slide = currentTestSlide {
                // Prompt
                VStack(spacing: 12) {
                    if testMode == .enToEs {
                        Text("Say this in Spanish:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(slide.translation)
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    } else {
                        Text("What does this mean in English?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        // Play Spanish audio button
                        Button {
                            playSlideAudio(slide, isTranslation: false)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.15))
                                    .frame(width: 80, height: 80)

                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .disabled(slide.audioUrl == nil)

                        Text("Tap to hear")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)

                // Recording controls or result
                if showResult {
                    testResultView(for: slide)
                } else {
                    testRecordingControls(for: slide)
                }

                Spacer()

                // Navigation buttons (after result)
                if showResult {
                    HStack(spacing: 12) {
                        if testSlideIndex > 0 {
                            Button {
                                previousTestSlide()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.headline)
                                    .frame(width: 50)
                                    .padding()
                                    .background(Color(.systemGray4))
                                    .foregroundStyle(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }

                        Button {
                            nextSlide()
                        } label: {
                            Text(testSlideIndex < testSlides.count - 1 ? "Next" : "See Results")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            } else {
                Spacer()
                Text("No test slides available")
                    .font(.body)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .onAppear {
            if testMode == .esToEn, let slide = currentTestSlide {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    playSlideAudio(slide, isTranslation: false)
                }
            }
        }
    }

    // MARK: - Test Recording Controls

    private func testRecordingControls(for slide: HotspotSlide) -> some View {
        VStack(spacing: 16) {
            if whisperService.isProcessing {
                ProgressView("Processing...")
                    .padding()
            } else {
                Button {
                    if isRecording {
                        stopTestRecording(for: slide)
                    } else {
                        startTestRecording()
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

                Text(isRecording ? "Tap to stop" : "Tap to speak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Helper buttons
            HStack(spacing: 16) {
                Button {
                    previousTestSlide()
                } label: {
                    Label("Back", systemImage: "backward.fill")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .disabled(testSlideIndex == 0)

                if testMode == .enToEs {
                    Button {
                        playSlideAudio(slide, isTranslation: false)
                    } label: {
                        Label("Listen", systemImage: "speaker.wave.2")
                            .font(.subheadline)
                    }
                    .disabled(slide.audioUrl == nil)
                } else {
                    Button {
                        playSlideAudio(slide, isTranslation: false)
                    } label: {
                        Label("Replay", systemImage: "speaker.wave.2")
                            .font(.subheadline)
                    }
                    .disabled(slide.audioUrl == nil)
                }

                Button {
                    showingHint = true
                } label: {
                    Label("Hint", systemImage: "lightbulb")
                        .font(.subheadline)
                }
                .foregroundStyle(.orange)

                Button {
                    skipSlide()
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Test Result View

    private func testResultView(for slide: HotspotSlide) -> some View {
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

                if testMode == .enToEs {
                    HStack {
                        Text("Correct:")
                            .foregroundStyle(.secondary)
                        Text(slide.text)
                            .fontWeight(.semibold)
                    }
                } else {
                    HStack {
                        Text("Correct:")
                            .foregroundStyle(.secondary)
                        Text(slide.translation)
                            .fontWeight(.semibold)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        playSlideAudio(slide, isTranslation: testMode == .esToEn)
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

            Text("You got \(score) out of \(testSlides.count) correct")
                .font(.title3)
                .foregroundStyle(.secondary)

            let percentage = testSlides.isEmpty ? 0 : Int((Double(score) / Double(testSlides.count)) * 100)
            Text("\(percentage)%")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(percentage: percentage))

            Button {
                resetTest()
            } label: {
                Label("Try Again", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)

            Button {
                isTestMode = false
                resetTest()
            } label: {
                Text("Back to Hotspot")
                    .font(.headline)
            }
        }
        .padding()
    }

    // MARK: - Test Actions

    private func startTestRecording() {
        print("[HotspotTest] startRecording")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        stopAudio()
        Task {
            await whisperService.startRecording()
            isRecording = whisperService.isRecording
        }
    }

    private func stopTestRecording(for slide: HotspotSlide) {
        print("[HotspotTest] stopRecording")
        Task {
            let transcription: String
            if testMode == .enToEs {
                // User speaking Spanish — compare against slide.text
                let expected = stripPunctuation(slide.text)
                transcription = await whisperService.stopRecording(expectedText: "The phrase is: \(expected)")
                isRecording = false
                spokenText = transcription
                let (correct, _) = whisperService.compareText(spoken: transcription, expected: expected)
                isCorrect = correct
            } else {
                // User speaking English — compare against slide.translation
                let expected = slide.translation
                transcription = await whisperService.stopRecording(expectedText: expected, language: "en")
                isRecording = false
                spokenText = transcription
                isCorrect = compareMeaning(spoken: transcription, expected: expected)
            }

            if isCorrect { score += 1 }
            UIImpactFeedbackGenerator(style: isCorrect ? .light : .medium).impactOccurred()
            showResult = true

            // Auto-play the correct answer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                playSlideAudio(slide, isTranslation: testMode == .esToEn)
            }
        }
    }

    private func nextSlide() {
        if testSlideIndex < testSlides.count - 1 {
            testSlideIndex += 1
            spokenText = ""
            showResult = false
            isCorrect = false
            showingHint = false
            // Auto-play Spanish audio in ES→EN mode
            if testMode == .esToEn, let slide = currentTestSlide {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    playSlideAudio(slide, isTranslation: false)
                }
            }
        } else {
            testComplete = true
        }
    }

    private func previousTestSlide() {
        guard testSlideIndex > 0 else { return }
        testSlideIndex -= 1
        spokenText = ""
        showResult = false
        isCorrect = false
        showingHint = false
        if testMode == .esToEn, let slide = currentTestSlide {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                playSlideAudio(slide, isTranslation: false)
            }
        }
    }

    private func skipSlide() {
        nextSlide()
    }

    private func tryAgain() {
        spokenText = ""
        showResult = false
        isCorrect = false
    }

    private func resetTest() {
        testSlideIndex = 0
        spokenText = ""
        showResult = false
        isCorrect = false
        score = 0
        testComplete = false
        showingHint = false
    }

    // MARK: - Text Comparison

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

    private func compareMeaning(spoken: String, expected: String) -> Bool {
        let spokenNorm = normalizeMeaning(spoken)
        let expectedNorm = normalizeMeaning(expected)

        if spokenNorm.isEmpty { return false }
        if spokenNorm == expectedNorm { return true }
        if spokenNorm.contains(expectedNorm) || expectedNorm.contains(spokenNorm) { return true }

        let (isMatch, matchScore) = whisperService.compareText(spoken: spokenNorm, expected: expectedNorm)
        if isMatch || matchScore >= 0.8 { return true }

        // Handle comma/semicolon/slash-separated alternatives
        let separators: [Character] = [",", ";", "/"]
        for sep in separators {
            let alts = expected.split(separator: sep).map { normalizeMeaning(String($0)) }
            for alt in alts where !alt.isEmpty {
                if spokenNorm == alt { return true }
                if spokenNorm.contains(alt) || alt.contains(spokenNorm) { return true }
                let (altMatch, altScore) = whisperService.compareText(spoken: spokenNorm, expected: alt)
                if altMatch || altScore >= 0.8 { return true }
            }
        }

        return false
    }

    private func normalizeMeaning(_ text: String) -> String {
        var result = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")

        let articlePrefixes = ["the ", "a ", "an "]
        for prefix in articlePrefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
            }
        }
        if result.hasPrefix("to ") {
            result = String(result.dropFirst(3))
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scoreColor(percentage: Int) -> Color {
        switch percentage {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }

    // MARK: - Audio

    private func playSlideAudio(_ slide: HotspotSlide, isTranslation: Bool) {
        let audioName = isTranslation ? slide.translationAudioUrl : slide.audioUrl
        guard let name = audioName else { return }
        playAudio(name, isTranslation: isTranslation)
    }

    private func playAudio(_ audioName: String, isTranslation: Bool) {
        stopAudio()
        let basePath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioPath = basePath
            .appendingPathComponent("Comics")
            .appendingPathComponent(comicId)
            .appendingPathComponent("audio")
            .appendingPathComponent("\(audioName).mp3")

        guard FileManager.default.fileExists(atPath: audioPath.path) else {
            if let bundledPath = Bundle.main.url(forResource: audioName, withExtension: "mp3", subdirectory: "BundledComics/\(comicId)/audio") {
                do {
                    audioPlayer = try AVAudioPlayer(contentsOf: bundledPath)
                    audioPlayer?.play()
                    isPlayingAudio = true
                } catch {
                    print("Failed to play bundled audio: \(error)")
                }
            }
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioPath)
            audioPlayer?.play()
            isPlayingAudio = true
        } catch {
            print("Failed to play audio: \(error)")
        }
    }

    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingAudio = false
    }
}
