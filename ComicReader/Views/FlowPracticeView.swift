import SwiftUI
import AVFoundation
import UIKit

// Flow Practice — a live conversation with the AI that weaves the comic's
// vocabulary into new contexts, so the learner has to understand and produce
// the words rather than just recognize them. Reply by typing or speaking
// (speech is transcribed by Whisper); the AI's Spanish reply is read aloud.

// MARK: - Model

private struct FlowVocabWord: Identifiable, Hashable {
    var id: String { text.lowercased() }
    let text: String
    let meaning: String
}

struct FlowMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case user, assistant }
    let id: UUID
    let role: Role
    var content: String

    init(role: Role, content: String, id: UUID = UUID()) {
        self.id = id
        self.role = role
        self.content = content
    }
}

// MARK: - Persistence

/// Saves the in-progress conversation per comic so leaving the feature and
/// returning resumes where you left off (survives navigation and app relaunch).
/// Backed by UserDefaults — the payload is small, text-only chat history.
private enum FlowConversationStore {
    private static func key(_ comicId: String) -> String { "flowConversation.\(comicId)" }

    static func load(_ comicId: String) -> [FlowMessage] {
        guard let data = UserDefaults.standard.data(forKey: key(comicId)),
              let messages = try? JSONDecoder().decode([FlowMessage].self, from: data) else { return [] }
        return messages
    }

    static func save(_ messages: [FlowMessage], for comicId: String) {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: key(comicId))
    }

    static func clear(_ comicId: String) {
        UserDefaults.standard.removeObject(forKey: key(comicId))
    }
}

/// Brand blue, hardcoded so filled surfaces (button, user bubble) always show
/// white text on blue in BOTH light and dark mode — `Color.accentColor` can
/// resolve to white on some device configs, hiding white text.
private let flowAccent = Color(red: 0.20, green: 0.32, blue: 0.89)

private enum FlowError: LocalizedError {
    case server(String)
    var errorDescription: String? { if case .server(let m) = self { return m }; return nil }
}

/// Vocabulary for the conversation: the comic's curated key words if present,
/// otherwise every word in the comic. Deduped to base form + meaning,
/// excluding manual phrase entries and words without a meaning.
private func flowVocabulary(from comic: Comic) -> [FlowVocabWord] {
    let reviewWords = comic.reviewWords ?? []
    let source: [Word] = reviewWords.isEmpty ? allSentenceWords(comic) : reviewWords.map { $0.word }

    var seen = Set<String>()
    var result: [FlowVocabWord] = []
    for word in source {
        if word.manual == true { continue }
        let meaning = word.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (word.baseForm?.isEmpty == false ? word.baseForm! : word.displayText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let key = text.lowercased()
        guard !text.isEmpty, !meaning.isEmpty, !seen.contains(key) else { continue }
        seen.insert(key)
        result.append(FlowVocabWord(text: text, meaning: meaning))
    }
    return result.sorted { $0.text.localizedCaseInsensitiveCompare($1.text) == .orderedAscending }
}

/// Every word across the comic's sentences (fallback when there are no key words).
private func allSentenceWords(_ comic: Comic) -> [Word] {
    var out: [Word] = []
    for page in comic.pages {
        for panel in page.panels {
            for bubble in panel.bubbles {
                for sentence in bubble.sentences {
                    out.append(contentsOf: sentence.words)
                }
            }
        }
    }
    return out
}

// MARK: - Lip-sync (talking head)

/// One mouth shape to show starting at `time` seconds into the audio.
private struct VisemeFrame {
    let time: Double
    let mouth: String
}

/// Maps a character to one of the `mouth_*` assets. Spanish spelling is highly
/// phonetic, so a per-letter mapping reads as convincing lip-sync.
private enum Viseme {
    static let rest = "mouth_rest"

    static func mouth(for character: Character) -> String? {
        guard let c = character.lowercased().first else { return nil }
        switch c {
        case "a", "á", "à", "ä":           return "mouth_ah"
        case "e", "é", "è", "ë":           return "mouth_eh"
        case "i", "í", "ì", "ï", "y":      return "mouth_ee"
        case "o", "ó", "ò", "ö":           return "mouth_oh"
        case "u", "ú", "ù", "ü":           return "mouth_oo"
        case "m", "b", "p":                return "mouth_rest"   // lips meet (bilabial)
        case "f", "v":                     return "mouth_fv"
        case "l", "t", "d", "n", "ñ", "r": return "mouth_l"
        case "s", "z", "c", "x":           return "mouth_ss"     // sibilants
        case "j", "g", "k", "q", "h", "w": return "mouth_eh"     // open-ish / silent h
        // Sentence boundaries / pauses → close the mouth.
        case ".", "!", "?", "…", "¿", "¡", ";", ":", "\n": return rest
        default:                           return nil            // spaces, commas → hold
        }
    }
}

/// The /tts-timed response: base64 MP3 plus per-character timing.
private struct TimedTTS: Decodable {
    let audio: String
    let alignment: Alignment?
    struct Alignment: Decodable {
        let characters: [String]
        let character_start_times_seconds: [Double]
        let character_end_times_seconds: [Double]?
    }
}

/// Plays the AI's reply through the server TTS and drives the avatar's mouth in
/// time with the audio, so she looks like she's actually saying the words.
@MainActor
final class TalkingHeadController: ObservableObject {
    @Published var isSpeaking = false

    private var player: AVAudioPlayer?
    private var endDelegate: AudioEndDelegate?
    private var track: [VisemeFrame] = []
    private var generation = 0   // a fresh speak()/stop() invalidates in-flight fetches

    /// The mouth shape for the current playback position — `rest` when not
    /// speaking. The avatar's display link polls this every frame; nothing here
    /// is @Published, so updating the mouth never re-renders any SwiftUI view.
    func currentMouthName() -> String {
        guard let player = player, player.isPlaying, !track.isEmpty else { return Viseme.rest }
        let t = player.currentTime
        var current = Viseme.rest
        for frame in track {
            if frame.time <= t { current = frame.mouth } else { break }
        }
        return current
    }

    func speak(_ text: String) {
        let myGen = bumpGeneration()
        Task { await fetchAndPlay(text, generation: myGen) }
    }

    func stop() {
        bumpGeneration()
        player?.stop(); player = nil
        endDelegate = nil
        track = []
        isSpeaking = false
    }

    @discardableResult
    private func bumpGeneration() -> Int {
        generation += 1
        return generation
    }

    private func fetchAndPlay(_ text: String, generation myGen: Int) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Preferred path: timed TTS (audio + per-character timing for lip-sync).
        if let url = URL(string: "\(Secrets.serverBaseURL)/api/reader/tts-timed") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 30
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": trimmed])
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let decoded = try? JSONDecoder().decode(TimedTTS.self, from: data),
               let audioData = Data(base64Encoded: decoded.audio, options: .ignoreUnknownCharacters) {
                guard myGen == generation else { return }   // superseded by a newer turn
                startPlayback(audioData, alignment: decoded.alignment)
                return
            }
        }

        // Fallback: plain TTS (audio only, no lip-sync) so she still speaks even
        // when the timed endpoint isn't deployed/available.
        await fetchPlainAndPlay(trimmed, generation: myGen)
    }

    private func fetchPlainAndPlay(_ text: String, generation myGen: Int) async {
        guard let url = URL(string: "\(Secrets.serverBaseURL)/api/reader/tts") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty,
              myGen == generation else { return }
        startPlayback(data, alignment: nil)
    }

    private func startPlayback(_ audioData: Data, alignment: TimedTTS.Alignment?) {
        // Play out loud regardless of the silent switch. Safe here because the
        // mic engine is stopped between turns (see toggleMic).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let newPlayer = try? AVAudioPlayer(data: audioData) else { return }

        track = buildTrack(from: alignment)
        let delegate = AudioEndDelegate { [weak self] in
            Task { @MainActor in self?.finish() }
        }
        endDelegate = delegate
        newPlayer.delegate = delegate
        player?.stop()
        player = newPlayer
        newPlayer.prepareToPlay()
        isSpeaking = true
        newPlayer.play()
    }

    private func buildTrack(from alignment: TimedTTS.Alignment?) -> [VisemeFrame] {
        guard let a = alignment,
              a.characters.count == a.character_start_times_seconds.count else { return [] }
        var frames: [VisemeFrame] = []
        for (i, ch) in a.characters.enumerated() {
            guard let first = ch.first, let m = Viseme.mouth(for: first) else { continue }
            if frames.last?.mouth == m { continue }   // collapse repeats — holds the shape
            frames.append(VisemeFrame(time: a.character_start_times_seconds[i], mouth: m))
        }
        // Always end closed: drop a rest frame when the last sound finishes, so
        // the mouth shuts at the end of the reply instead of hanging open.
        if let lastEnd = a.character_end_times_seconds?.max(), frames.last?.mouth != Viseme.rest {
            frames.append(VisemeFrame(time: lastEnd, mouth: Viseme.rest))
        }
        return frames
    }

    private func finish() {
        player = nil
        endDelegate = nil
        track = []
        isSpeaking = false
    }
}

/// Bridges AVAudioPlayer's Obj-C delegate callback back to the controller.
private final class AudioEndDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: @Sendable () -> Void
    init(onFinish: @escaping @Sendable () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

/// Every mouth-shape asset, preloaded once so swaps never trigger a decode.
private let mouthAssetNames = [
    "mouth_rest", "mouth_ah", "mouth_eh", "mouth_ee", "mouth_oh",
    "mouth_oo", "mouth_fv", "mouth_l", "mouth_ss",
]

/// Self-contained UIKit view that drives the lip-sync with its own CADisplayLink.
/// Every mouth shape gets its OWN pre-rendered UIImageView, stacked on top of each
/// other; "swapping" is just toggling which one is hidden. No image is assigned,
/// decoded, or rescaled at swap time — so there is nothing to flicker. (Assigning
/// a 1024px image to a single shared view forced a decode/rescale on each swap,
/// which was the flicker that appeared only while speaking.)
@MainActor
private final class MouthDisplayView: UIView {
    weak var controller: TalkingHeadController?
    private var shapeViews: [String: UIImageView] = [:]
    private var displayLink: CADisplayLink?
    private var currentName = Viseme.rest

    init(controller: TalkingHeadController) {
        self.controller = controller
        super.init(frame: .zero)
        for name in mouthAssetNames {
            // Skip a shape whose asset is missing rather than registering a blank
            // view — otherwise selecting it would flash the dark background.
            guard let img = UIImage(named: name) else { continue }
            let iv = UIImageView(image: img)
            iv.contentMode = .scaleAspectFit
            iv.clipsToBounds = true
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.isHidden = name != currentName
            iv.layer.actions = ["hidden": NSNull()]   // no implicit fade on toggle
            addSubview(iv)
            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: leadingAnchor),
                iv.trailingAnchor.constraint(equalTo: trailingAnchor),
                iv.topAnchor.constraint(equalTo: topAnchor),
                iv.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            shapeViews[name] = iv
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Run the display link only while on screen (also breaks the CADisplayLink
    // ↔ self retain cycle when the view goes away).
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopLink() } else { startLink() }
    }

    private func startLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step() {
        apply(controller?.currentMouthName() ?? Viseme.rest)
    }

    private func apply(_ name: String) {
        guard name != currentName, let next = shapeViews[name] else { return }
        // Toggle visibility atomically, with implicit actions off — instant cut.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeViews[currentName]?.isHidden = true
        next.isHidden = false
        CATransaction.commit()
        currentName = name
    }
}

private struct TalkingHeadAnimator: UIViewRepresentable {
    let controller: TalkingHeadController

    func makeUIView(context: Context) -> MouthDisplayView {
        MouthDisplayView(controller: controller)
    }

    func updateUIView(_ uiView: MouthDisplayView, context: Context) {
        uiView.controller = controller
    }

    // Take the size SwiftUI proposes (the .frame), not the image's 1024px
    // intrinsic size — otherwise the clip shows only a zoomed-in centre.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MouthDisplayView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

/// The animated avatar: a portrait whose mouth swaps in time with speech, with a
/// gentle idle "breathing" motion and a ring while she's speaking.
private struct TalkingHeadView: View {
    @ObservedObject var head: TalkingHeadController

    var body: some View {
        // Deliberately minimal: no breathing scaleEffect and no shadow. Those put
        // the host view in a perpetual animation / rasterized state, and combined
        // with the mouth content changing (only while speaking) that produced the
        // flash. Static host = the UIKit shape-toggle can't flicker.
        TalkingHeadAnimator(controller: head)
            .frame(width: 132, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(flowAccent.opacity(head.isSpeaking ? 0.9 : 0), lineWidth: 3)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - View model

@MainActor
final class FlowChatViewModel: ObservableObject {
    @Published var messages: [FlowMessage] = []
    @Published var inputText = ""
    @Published var isThinking = false   // waiting on the AI
    @Published var started = false
    @Published var errorText: String?

    let comicTitle: String
    let level: String
    private let comicId: String
    private let vocab: [FlowVocabWord]
    private let sourceLang = "es"   // language being learned
    private let targetLang = "en"   // learner's native language

    let head = TalkingHeadController()
    private let whisper = WhisperService.shared

    fileprivate init(comicId: String, comicTitle: String, level: String, vocab: [FlowVocabWord]) {
        self.comicId = comicId
        self.comicTitle = comicTitle
        self.level = level
        self.vocab = vocab
        // Resume an in-progress conversation if one was saved for this comic.
        let saved = FlowConversationStore.load(comicId)
        if !saved.isEmpty {
            messages = saved
            started = true
        }
    }

    private func persist() {
        FlowConversationStore.save(messages, for: comicId)
    }

    var hasVocab: Bool { !vocab.isEmpty }
    var vocabCount: Int { vocab.count }

    func start() async {
        guard !started else { return }
        started = true
        await fetchAssistantTurn()   // empty history → AI opens
    }

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        inputText = ""
        head.stop()
        messages.append(FlowMessage(role: .user, content: text))
        persist()
        await fetchAssistantTurn()
    }

    /// Discard the saved conversation and begin a fresh one.
    func restart() async {
        head.stop()
        whisper.cancelRecording()
        whisper.endCaptureSession()
        messages.removeAll()
        errorText = nil
        inputText = ""
        started = false
        FlowConversationStore.clear(comicId)
        await start()
    }

    func replay(_ message: FlowMessage) {
        head.speak(message.content)
    }

    /// Toggle speech input. Tap to start recording, tap again to stop and
    /// transcribe; the transcription lands in the input field for review.
    func toggleMic() async {
        if whisper.isRecording {
            // Force Spanish transcription. Auto-detect let Whisper mis-hear spoken
            // Spanish as other languages (Hebrew, Portuguese, …) and also produced
            // homophone misspellings ("voi" for "voy"); pinning to es fixes both.
            // English help requests can be typed instead of spoken.
            let text = await whisper.stopRecording(expectedText: nil, language: "es")
            whisper.endCaptureSession()   // free the mic engine so TTS playback isn't fighting it
            let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !spoken.isEmpty {
                // Spoken input auto-sends (typed input still uses the Send button).
                inputText = spoken
                await send()
            }
        } else {
            head.stop()
            await whisper.startRecording()
        }
    }

    #if DEBUG
    /// Seed a fake exchange so the chat layout can be screenshotted without a
    /// live endpoint. Triggered by the `--flow-demo` launch arg.
    func seedDemo() {
        started = true
        messages = [
            FlowMessage(role: .assistant, content: "¡Hola! ¿Qué haces cuando alguien llama a la puerta de tu casa?"),
            FlowMessage(role: .user, content: "Abro la puerta y digo hola."),
            FlowMessage(role: .assistant, content: "¡Muy bien! Y si no quieres ver a nadie, ¿dónde te puedes esconder?"),
        ]
    }
    #endif

    func teardown() {
        head.stop()
        whisper.cancelRecording()
        whisper.endCaptureSession()
    }

    private func fetchAssistantTurn() async {
        isThinking = true
        errorText = nil
        do {
            let reply = try await requestReply(history: messages)
            let cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                errorText = "The tutor didn't reply — tap retry."
            } else {
                messages.append(FlowMessage(role: .assistant, content: cleaned))
                persist()
                head.speak(cleaned)
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isThinking = false
    }

    func retry() async {
        // Drop a trailing failed user turn? No — just re-request from current history.
        await fetchAssistantTurn()
    }

    private func requestReply(history: [FlowMessage]) async throws -> String {
        guard let url = URL(string: "\(Secrets.serverBaseURL)/api/reader/flow-practice") else {
            throw FlowError.server("Invalid server URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        let body: [String: Any] = [
            "comicTitle": comicTitle,
            "sourceLang": sourceLang,
            "targetLang": targetLang,
            "level": level,
            "vocab": vocab.map { ["text": $0.text, "meaning": $0.meaning] },
            "messages": history.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw FlowError.server("No response") }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard http.statusCode == 200 else {
            throw FlowError.server(json?["error"] as? String ?? "Server error (\(http.statusCode))")
        }
        return (json?["reply"] as? String) ?? ""
    }
}

// MARK: - View

struct FlowPracticeView: View {
    let comic: Comic
    @StateObject private var vm: FlowChatViewModel
    @ObservedObject private var whisper = WhisperService.shared
    @FocusState private var inputFocused: Bool
    @State private var showRestartConfirm = false

    init(comic: Comic) {
        self.comic = comic
        _vm = StateObject(wrappedValue: FlowChatViewModel(
            comicId: comic.id,
            comicTitle: comic.title,
            level: comic.level.rawValue,
            vocab: flowVocabulary(from: comic)
        ))
    }

    var body: some View {
        Group {
            if vm.started {
                chat
            } else {
                intro
            }
        }
        .navigationTitle("Flow Practice")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--flow-demo") { vm.seedDemo() }
            #endif
        }
        .onDisappear { vm.teardown() }
        .toolbar {
            if vm.started {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showRestartConfirm = true
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(vm.isThinking)
                }
            }
        }
        .confirmationDialog("Restart conversation?", isPresented: $showRestartConfirm, titleVisibility: .visible) {
            Button("Restart", role: .destructive) { Task { await vm.restart() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This clears the current chat and starts a new conversation.")
        }
    }

    // MARK: Intro (before the conversation starts)

    private var intro: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(Viseme.rest)
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
            Text("Flow Practice")
                .font(.title2.weight(.bold))
            Text("Chat in Spanish with the AI. It brings the words from \"\(comic.title)\" into new situations, so you practice understanding them and replying yourself — by typing or speaking.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if vm.hasVocab {
                Text("\(vm.vocabCount) words from this comic")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await vm.start() }
            } label: {
                Label("Start conversation", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(vm.hasVocab ? flowAccent : Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!vm.hasVocab)
            if !vm.hasVocab {
                Text("This comic has no vocabulary to practice yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: Chat

    private var chat: some View {
        VStack(spacing: 0) {
            TalkingHeadView(head: vm.head)
                .padding(.top, 8)
                .padding(.bottom, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(vm.messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }
                        if vm.isThinking {
                            thinkingBubble.id("thinking")
                        }
                        if let error = vm.errorText {
                            errorRow(error).id("error")
                        }
                        Color.clear.frame(height: 1).id("BOTTOM")
                    }
                    .padding()
                }
                .onChange(of: vm.messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: vm.isThinking) { _, _ in scrollToBottom(proxy) }
            }
            inputBar
        }
    }

    private func messageBubble(_ message: FlowMessage) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.role == .user { Spacer(minLength: 40) }

            if message.role == .assistant {
                Button { vm.replay(message) } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                }
            }

            Text(message.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.role == .user ? flowAccent : Color(.secondarySystemBackground))
                .foregroundStyle(message.role == .user ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var thinkingBubble: some View {
        HStack {
            ProgressView()
            Text("…")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func errorRow(_ error: String) -> some View {
        VStack(spacing: 6) {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
            Button("Retry") { Task { await vm.retry() } }
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await vm.toggleMic() }
            } label: {
                Group {
                    if whisper.isProcessing {
                        ProgressView()
                    } else {
                        Image(systemName: whisper.isRecording ? "stop.circle.fill" : "mic.fill")
                    }
                }
                .font(.title3)
                .foregroundStyle(whisper.isRecording ? Color.red : flowAccent)
                .frame(width: 36, height: 36)
            }
            .disabled(vm.isThinking || whisper.isProcessing)

            TextField(whisper.isRecording ? "Listening…" : "Type or speak…", text: $vm.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .focused($inputFocused)
                .disabled(whisper.isRecording)

            Button {
                inputFocused = false
                Task { await vm.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(canSend ? flowAccent : Color.gray)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var canSend: Bool {
        !vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !vm.isThinking && !whisper.isRecording
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("BOTTOM", anchor: .bottom)
        }
    }
}

#Preview {
    NavigationStack {
        FlowPracticeView(comic: ComicData.allComics[0])
    }
}
