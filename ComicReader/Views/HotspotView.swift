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

    private var currentSlide: HotspotSlide? {
        guard !hotspot.slides.isEmpty, currentSlideIndex < hotspot.slides.count else { return nil }
        return hotspot.slides[currentSlideIndex]
    }

    var body: some View {
        NavigationStack {
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
                        // Foreign language text
                        if !slide.text.isEmpty {
                            Text(slide.text)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // Translation
                        if !slide.translation.isEmpty {
                            Text(slide.translation)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // Audio buttons
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

                        // Words (tappable for definitions)
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
                        withAnimation {
                            currentSlideIndex = max(0, currentSlideIndex - 1)
                        }
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
                        withAnimation {
                            currentSlideIndex = min(hotspot.slides.count - 1, currentSlideIndex + 1)
                        }
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
            .contentShape(Rectangle())
            .gesture(
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
            .navigationTitle(hotspot.label ?? "Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
        }
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
            // Try bundled path
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
