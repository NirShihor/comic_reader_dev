import SwiftUI
import UIKit

struct ContentView: View {
    @State private var selectedTab: Tab = .library
    @State private var libraryNavigationPath = NavigationPath()
    @State private var showSplash = true
    // App appearance override, set from Settings → Appearance: "system"/"light"/"dark".
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil   // follow the system
        }
    }

    // Returning user = has launched before (flag set on first Get started) or
    // already has reading progress. They see "Continue learning".
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false
    @EnvironmentObject private var progressManager: ReadingProgressManager
    private var returningUser: Bool {
        hasLaunchedBefore || !progressManager.progressMap.isEmpty
    }

    enum Tab {
        case library
        case vocabulary
        case notebook
        case settings
    }

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--coachmark-preview") {
            CoachmarkPreviewHarness()
        } else {
            mainBody
        }
        #else
        mainBody
        #endif
    }

    var mainBody: some View {
        // Show the splash ALONE first — don't mount the TabView/LibraryView behind
        // it. On a cold first-download launch, mounting the library kicks off the
        // catalog fetch + comic loading + image decoding, and that main-thread
        // contention is what made the spin/typing stutter and mistime. Deferring it
        // until the splash is done keeps the intro smooth.
        Group {
            if showSplash {
                LandingView(
                    ctaTitle: returningUser ? "Continue learning" : "Get started",
                    onGetStarted: {
                        hasLaunchedBefore = true
                        withAnimation(.easeInOut(duration: 0.4)) { showSplash = false }
                    }
                )
            } else {
                tabs
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .onAppear { ContentView.warmUpNotebook() }
    }

    /// Pay the one-time costs (custom-font glyph load + keyboard subsystem init)
    /// during the splash, so the Notebook opens and accepts typing without the
    /// first-use hitch.
    private static var didWarmUp = false
    static func warmUpNotebook() {
        guard !didWarmUp else { return }
        didWarmUp = true

        // Force CoreText to load + lay out the handwritten font's glyphs.
        for name in ["ComicRelief-Regular", "ComicRelief-Bold"] {
            let label = UILabel()
            label.font = UIFont(name: name, size: 17)
            label.text = "warming up"
            label.sizeToFit()
        }

        // Pre-warm the keyboard so the first tap-to-type doesn't stall.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else { return }
            let field = UITextField(frame: .zero)
            window.addSubview(field)
            field.becomeFirstResponder()
            field.resignFirstResponder()
            field.removeFromSuperview()
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $libraryNavigationPath) {
                LibraryView()
                    .navigationDestination(for: Comic.self) { comic in
                        ComicDetailView(comic: comic)
                    }
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }
            .tag(Tab.library)

            NavigationStack {
                VocabularyView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                selectedTab = .library
                            }
                        }
                    }
            }
            .tabItem {
                Label("Vocabulary", systemImage: "bookmark.fill")
            }
            .tag(Tab.vocabulary)

            NavigationStack {
                NotebookView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                selectedTab = .library
                            }
                        }
                    }
            }
            .tabItem {
                Label("Notebook", systemImage: "book.closed")
            }
            .tag(Tab.notebook)

            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                selectedTab = .library
                            }
                        }
                    }
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(Tab.settings)
        }
        .tint(.primary)
    }
}

// MARK: - Landing / Splash

// Design tokens for the landing screen (match the rest of the refresh).
private enum Brand {
    static let accent        = Color(red: 0x5B/255, green: 0x5B/255, blue: 0xD6/255) // #5B5BD6
    static let yellow        = Color(red: 0xFF/255, green: 0xD2/255, blue: 0x3F/255) // #FFD23F
    static let violet        = Color(red: 0x6E/255, green: 0x40/255, blue: 0xF0/255) // #6E40F0
    static let ink           = Color(red: 0x15/255, green: 0x17/255, blue: 0x2A/255) // #15172A (bubble outline)
    static let bg            = Color(red: 0xF4/255, green: 0xF1/255, blue: 0xED/255) // #F4F1ED
    static let textPrimary   = Color(red: 0x1F/255, green: 0x1B/255, blue: 0x18/255) // #1F1B18
    static let textSecondary = Color(red: 0x75/255, green: 0x6E/255, blue: 0x67/255) // #756E67
    static let textTertiary  = Color(red: 0x6B/255, green: 0x63/255, blue: 0x5C/255) // #6B635C

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Luckiest Guy — comic display font, for headlines.
    static func display(_ size: CGFloat) -> Font {
        Font.custom("LuckiestGuy-Regular", size: size)
    }

    /// Inter — body font (variable; weights applied via .weight()).
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font.custom("Inter", size: size).weight(weight)
    }
}

/// Hand-drawn yellow underline squiggle, ported from the mockup SVG (viewBox 0 0 240 10).
private struct Squiggle: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 240, sy = rect.height / 10
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
        var p = Path()
        p.move(to: pt(2, 5))
        p.addQuadCurve(to: pt(80, 5),  control: pt(41, 1))
        p.addQuadCurve(to: pt(160, 5), control: pt(120, 9))
        p.addQuadCurve(to: pt(238, 5), control: pt(199, 1))
        return p
    }
}

/// First-run / landing screen — COMIGO logo on a solid violet field with the
/// "Spanish." tagline and "Get started" CTA.
struct LandingView: View {
    var ctaTitle: String = "Get started"
    var onGetStarted: () -> Void = {}

    var body: some View {
        ZStack {
            Brand.violet.ignoresSafeArea()

            // Content, pinned to the bottom
            VStack(spacing: 0) {
                Spacer()

                Image("comicgo_logo_yoni_1_alpha_layer_2")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 271)
                    .shadow(color: Brand.textPrimary.opacity(0.12), radius: 12, x: 0, y: 6)
                    .padding(.bottom, 46)
                    .offset(y: -125)

                // Tagline — "Spanish." in Luckiest Guy (yellow period), the line
                // below in Inter with a yellow squiggle underline.
                VStack(spacing: 6) {
                    (Text("Spanish").tracking(-1.5)
                        + Text(".").font(Brand.display(42)).foregroundColor(Brand.yellow))
                        .font(Brand.display(34))

                    (Text("One comic at a time") + Text("."))
                        .font(Brand.body(21, .heavy))
                        .overlay(alignment: .bottom) {
                            Squiggle()
                                .stroke(Brand.yellow, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .frame(height: 10)
                                .offset(y: 8)
                        }
                }
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

                Text("Read and listen to comics in Spanish, tap sentences and words to understand them and practice out loud.")
                    .font(Brand.body(15.5))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 280)
                    .padding(.top, 24)

                Button(action: onGetStarted) {
                    Text(ctaTitle)
                        .font(Brand.body(16, .heavy))
                        .foregroundColor(Brand.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Brand.ink, lineWidth: 3.5))
                        .shadow(color: Brand.ink.opacity(0.25), radius: 10, x: 0, y: 8)
                }
                .padding(.top, 30)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 46)
        }
    }
}

// MARK: - Mosaic backdrop
// Two columns of comic tiles. Swap MosaicTile's fill for real cover Images:
//   MosaicTile { Image("cover_rey").resizable().scaledToFill() }
// The warm gradient above handles the dimming, so tiles need no overlay of their own.
private struct MosaicBackdrop: View {
    // Primary violet from the v4 HTML mockup (--violet: #6E40F0).
    private let panel = Color(red: 0x6E/255, green: 0x40/255, blue: 0xF0/255)
    var body: some View {
        panel
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    ContentView()
        .environmentObject(SettingsManager())
        .environmentObject(ReadingProgressManager())
}

#Preview("Landing") {
    LandingView()
}

#if DEBUG
/// Screenshot-only harness: opens the panel reading screen on a rich in-memory
/// comic with the feature tour armed, so the coachmark overlay can be captured.
/// Launch with `--coachmark-preview` (and optional `--coachmark-step N`).
struct CoachmarkPreviewHarness: View {
    @EnvironmentObject var settingsManager: SettingsManager

    private static let comic: Comic = {
        let words = [
            Word(id: "w1", text: "Me", meaning: "myself", baseForm: "me"),
            Word(id: "w2", text: "escondí", meaning: "I hid", baseForm: "esconder"),
            Word(id: "w3", text: "detrás", meaning: "behind", baseForm: "detrás"),
            Word(id: "w4", text: "de", meaning: "of", baseForm: "de"),
            Word(id: "w5", text: "la", meaning: "the", baseForm: "la"),
            Word(id: "w6", text: "puerta", meaning: "door", baseForm: "puerta"),
        ]
        let sentence = Sentence(
            id: "s1",
            text: "Me escondí detrás de la puerta",
            translation: "I hid behind the door",
            grammarNote: "“Escondí” is the preterite (completed past) of esconder. The reflexive “me” shows he hid himself.",
            audioUrl: "preview-audio",
            words: words
        )
        let bubble = Bubble(id: "b1", type: .speech, positionX: 0.1, positionY: 0.1,
                            width: 0.8, height: 0.2, sentences: [sentence])
        let panel = Panel(id: "p1", artworkImage: "sample_cover", noTextImage: nil,
                          floating: false, corners: nil, panelOrder: 1,
                          tapZoneX: 0, tapZoneY: 0, tapZoneWidth: 0.5, tapZoneHeight: 0.5,
                          bubbles: [bubble])
        let page = Page(id: "pg1", pageNumber: 1, masterImage: "sample_cover", panels: [panel])
        let review = ReviewWord(word: words[1], panelId: "p1", pageId: "pg1")
        return Comic(id: "preview-comic", title: "Tour Preview", description: "",
                     coverImage: "sample_cover", level: .beginner, isPremium: false,
                     pages: [page], reviewWords: [review])
    }()

    var body: some View {
        let comic = Self.comic
        Group {
            // Smoke-test a rolled-out screen: just launching it exercises the
            // help env wiring (the tooltip layer reads @EnvironmentObject on
            // first render, so a misorder would crash on appear).
            if ProcessInfo.processInfo.arguments.contains("--flow-preview") {
                NavigationStack { FlowPracticeView(comic: comic) }
            } else if ProcessInfo.processInfo.arguments.contains("--practice-help-preview") {
                PracticeModesHelpView()
            } else if ProcessInfo.processInfo.arguments.contains("--quiz-preview") {
                NavigationStack { QuizView(comic: comic) }
            } else {
                PanelView(
                    comic: comic,
                    page: comic.pages[0],
                    panel: comic.pages[0].panels[0],
                    hotspots: [],
                    navigateToPage: .constant(nil)
                )
            }
        }
        .environmentObject(settingsManager)
    }
}
#endif

// MARK: - Notebook

/// A single notebook page: a title and free-form body text the user writes.
/// Pages saved from a hotspot also carry a deep link back into the comic
/// (optional fields, so previously stored pages decode unchanged).
struct NotebookPage: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String = ""
    var body: String = ""
    var linkComicId: String? = nil
    var linkPageNumber: Int? = nil
    var linkHotspotId: String? = nil

    var hasComicLink: Bool { linkComicId != nil && linkHotspotId != nil }
}

private let notebookHighlightColor = Color.yellow.opacity(0.55)

/// Render a note body, turning ==marked== spans into yellow highlights.
func notebookHighlighted(_ s: String) -> AttributedString {
    var result = AttributedString("")
    var rest = Substring(s)
    while let open = rest.range(of: "==") {
        result += AttributedString(String(rest[..<open.lowerBound]))
        let after = rest[open.upperBound...]
        if let close = after.range(of: "==") {
            var hi = AttributedString(String(after[..<close.lowerBound]))
            hi.backgroundColor = notebookHighlightColor
            result += hi
            rest = after[close.upperBound...]
        } else {
            result += AttributedString("==" + String(after))
            return result
        }
    }
    result += AttributedString(String(rest))
    return result
}

/// A UITextView-backed editor that shows ==marked== text as live yellow
/// highlights and provides a keyboard toolbar "Highlight" button. The stored
/// value stays a plain string with ==markers== (iOS 17 compatible).
struct HighlightingTextView: UIViewRepresentable {
    @Binding var markup: String
    var font: UIFont
    var textColor: UIColor

    static let highlightColor = UIColor.systemYellow.withAlphaComponent(0.55)

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = font
        tv.textColor = textColor
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        tv.typingAttributes = [.font: font, .foregroundColor: textColor]
        tv.attributedText = Self.attributed(from: markup, font: font, color: textColor)

        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(title: "🖍 Highlight", style: .plain, target: context.coordinator, action: #selector(Coordinator.toggleHighlight)),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .done, target: context.coordinator, action: #selector(Coordinator.endEditing))
        ]
        tv.inputAccessoryView = toolbar
        context.coordinator.textView = tv
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Only resync if the external value changed (avoids clobbering edits).
        if Self.markup(from: uiView.attributedText) != markup {
            let sel = uiView.selectedRange
            uiView.attributedText = Self.attributed(from: markup, font: font, color: textColor)
            uiView.selectedRange = sel
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: HighlightingTextView
        weak var textView: UITextView?
        init(_ parent: HighlightingTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.markup = HighlightingTextView.markup(from: textView.attributedText)
        }

        @objc func toggleHighlight() {
            guard let tv = textView, tv.selectedRange.length > 0 else { return }
            let range = tv.selectedRange
            let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
            var allHighlighted = true
            mutable.enumerateAttribute(.backgroundColor, in: range, options: []) { value, _, _ in
                if value == nil { allHighlighted = false }
            }
            if allHighlighted {
                mutable.removeAttribute(.backgroundColor, range: range)
            } else {
                mutable.addAttribute(.backgroundColor, value: HighlightingTextView.highlightColor, range: range)
            }
            mutable.addAttribute(.font, value: parent.font, range: NSRange(location: 0, length: mutable.length))
            mutable.addAttribute(.foregroundColor, value: parent.textColor, range: NSRange(location: 0, length: mutable.length))
            tv.attributedText = mutable
            tv.selectedRange = range
            tv.typingAttributes = [.font: parent.font, .foregroundColor: parent.textColor]
            parent.markup = HighlightingTextView.markup(from: mutable)
        }

        @objc func endEditing() { textView?.resignFirstResponder() }
    }

    static func attributed(from markup: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        var rest = Substring(markup)
        while let open = rest.range(of: "==") {
            result.append(NSAttributedString(string: String(rest[..<open.lowerBound]), attributes: base))
            let after = rest[open.upperBound...]
            if let close = after.range(of: "==") {
                var hiAttrs = base
                hiAttrs[.backgroundColor] = highlightColor
                result.append(NSAttributedString(string: String(after[..<close.lowerBound]), attributes: hiAttrs))
                rest = after[close.upperBound...]
            } else {
                result.append(NSAttributedString(string: "==" + String(after), attributes: base))
                return result
            }
        }
        result.append(NSAttributedString(string: String(rest), attributes: base))
        return result
    }

    static func markup(from attributed: NSAttributedString) -> String {
        var out = ""
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.backgroundColor, in: full, options: []) { value, range, _ in
            let sub = (attributed.string as NSString).substring(with: range)
            out += value != nil ? "==\(sub)==" : sub
        }
        return out
    }
}

// MARK: Admin notes (ship with the app)
//
// These pages are compiled into the app, so every user gets them and they're
// always available offline. To EDIT them, just change the text below: start a
// new page with a line beginning "# " (that becomes the page title); everything
// until the next "# " is that page's body. Plain text, real line breaks — no
// JSON escaping. (We can later move this to a server feed if you want to update
// notes without shipping a new build.)
private let adminNotesSource = """
# Ser vs. Estar
Both mean "to be", but:
• SER — permanent / essential traits: who/what something is. "Soy de España." "Es médico."
• ESTAR — states & locations that can change: how/where something is right now. "Estoy cansado." "Está en casa."

# Por vs. Para
• POR — reason, cause, exchange, duration, "through/by". "Gracias por la ayuda." "Por la mañana."
• PARA — purpose, destination, deadline, recipient. "Es para ti." "Salgo para Madrid."

# The Personal "a"
When the direct object of a verb is a specific person (or a loved pet), add "a":
"Veo a María." "Busco a mi hermano."
No "a" for things: "Veo la casa."
"""

/// Global notebook store. Admin pages are authored in the generator and fetched
/// from the server (cached on-device, so they stay available offline); the
/// compiled `adminNotesSource` is only a fallback before the first fetch.
/// User pages are device-local and editable, persisted to UserDefaults.
final class NotebookManager: ObservableObject {
    /// Read-only grammar pages from the server (cached). Updated on launch.
    @Published var adminPages: [NotebookPage]
    /// User-created pages, stored on this device.
    @Published var userPages: [NotebookPage] { didSet { save() } }
    /// Admin note ids the user has hidden on this device.
    @Published var hiddenAdminIds: Set<String> {
        didSet { UserDefaults.standard.set(Array(hiddenAdminIds), forKey: hiddenKey) }
    }

    private let storageKey = "notebookPages.v1"
    private let adminCacheKey = "notebookAdminCache.v1"
    private let hiddenKey = "notebookHiddenAdmin.v1"

    /// Admin pages the user hasn't hidden.
    var visibleAdminPages: [NotebookPage] { adminPages.filter { !hiddenAdminIds.contains($0.id) } }
    /// Admin pages the user has hidden.
    var hiddenAdminPages: [NotebookPage] { adminPages.filter { hiddenAdminIds.contains($0.id) } }

    func setAdminHidden(_ id: String, _ hidden: Bool) {
        if hidden { hiddenAdminIds.insert(id) } else { hiddenAdminIds.remove(id) }
    }

    init() {
        hiddenAdminIds = Set(UserDefaults.standard.array(forKey: "notebookHiddenAdmin.v1") as? [String] ?? [])
        // Admin: prefer the cached server copy; otherwise the compiled fallback.
        if let cached = UserDefaults.standard.data(forKey: adminCacheKey),
           let decoded = try? JSONDecoder().decode([NotebookPage].self, from: cached) {
            adminPages = decoded
        } else {
            adminPages = NotebookManager.parseAdminNotes(adminNotesSource)
        }
        // User pages.
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([NotebookPage].self, from: data) {
            userPages = decoded
        } else {
            userPages = []
        }
        // Refresh admin notes from the server in the background.
        Task { await fetchAdminNotes() }
    }

    /// Fetch the global admin notebook from the server and cache it. On failure
    /// (offline, etc.) the cached/fallback pages remain in place.
    @MainActor
    func fetchAdminNotes() async {
        guard let url = URL(string: "\(Secrets.serverBaseURL)/api/reader/notebook") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            struct Payload: Decodable {
                struct Note: Decodable { let id: String; let title: String; let body: String }
                let notes: [Note]
            }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let pages = payload.notes.map { NotebookPage(id: $0.id, title: $0.title, body: $0.body) }
            if let encoded = try? JSONEncoder().encode(pages) {
                UserDefaults.standard.set(encoded, forKey: adminCacheKey)
            }
            adminPages = pages
        } catch {
            // Keep whatever we already have (cache or fallback).
        }
    }

    /// Insert a new user page or update an existing one (matched by id).
    func upsert(_ page: NotebookPage) {
        if let idx = userPages.firstIndex(where: { $0.id == page.id }) {
            userPages[idx] = page
        } else {
            userPages.append(page)
        }
    }

    func delete(_ page: NotebookPage) {
        userPages.removeAll { $0.id == page.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(userPages) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Split the admin source into pages on lines beginning with "# ".
    static func parseAdminNotes(_ src: String) -> [NotebookPage] {
        var pages: [NotebookPage] = []
        var title: String?
        var bodyLines: [String] = []
        func flush() {
            guard let t = title else { return }
            let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            pages.append(NotebookPage(id: "admin-\(pages.count)", title: t, body: body))
        }
        for line in src.components(separatedBy: "\n") {
            if line.hasPrefix("# ") {
                flush()
                title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                bodyLines = []
            } else {
                bodyLines.append(line)
            }
        }
        flush()
        return pages
    }
}

/// A resolved "Open in comic" destination from a note's hotspot link.
private struct NotebookLinkTarget: Identifiable {
    let id = UUID()
    let comic: Comic
    let page: Page
    let hotspotId: String
}

/// Handwritten-style notebook. Cream paper pages in the Comic Relief face.
struct NotebookView: View {
    @EnvironmentObject private var notebook: NotebookManager
    @State private var editingPage: NotebookPage?
    @State private var readingPage: NotebookPage?
    @State private var showingHelp = false
    @State private var linkTarget: NotebookLinkTarget?
    @State private var linkError: String?

    private static let ink = Color(red: 0.14, green: 0.15, blue: 0.22)

    /// Resolve a note's hotspot link against the comics on this device and open
    /// it — or explain why we can't (comic deleted / not downloaded).
    private func openComicLink(_ page: NotebookPage) {
        guard let comicId = page.linkComicId, let hotspotId = page.linkHotspotId else { return }
        guard let comic = LocalComicStorage.shared.downloadedComics.first(where: { $0.id == comicId }) else {
            linkError = "This comic isn't on your device any more. Re-download it from your Library, then try the link again."
            return
        }
        let sorted = comic.pages.sorted { $0.pageNumber < $1.pageNumber }
        guard let target = sorted.first(where: { $0.pageNumber == page.linkPageNumber }) ?? sorted.first else {
            linkError = "This comic has no pages on this device."
            return
        }
        linkTarget = NotebookLinkTarget(comic: comic, page: target, hotspotId: hotspotId)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !notebook.visibleAdminPages.isEmpty {
                    sectionHeader("Admin Notes")
                    ForEach(notebook.visibleAdminPages) { page in
                        NotebookPaper(page: page, locked: true)
                            .onTapGesture { readingPage = page }
                            .contextMenu {
                                Button {
                                    notebook.setAdminHidden(page.id, true)
                                } label: {
                                    Label("Hide note", systemImage: "eye.slash")
                                }
                            }
                    }
                }

                if !notebook.hiddenAdminPages.isEmpty {
                    DisclosureGroup("Hidden admin notes (\(notebook.hiddenAdminPages.count))") {
                        ForEach(notebook.hiddenAdminPages) { page in
                            HStack {
                                Text(page.title.isEmpty ? "Untitled" : page.title)
                                    .font(.custom("ComicRelief-Regular", size: 16))
                                    .foregroundColor(Self.ink.opacity(0.7))
                                    .lineLimit(1)
                                Spacer()
                                Button("Unhide") { notebook.setAdminHidden(page.id, false) }
                                    .font(.custom("ComicRelief-Bold", size: 14))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .font(.custom("ComicRelief-Bold", size: 14))
                    .foregroundColor(Self.ink.opacity(0.6))
                    .tint(Self.ink.opacity(0.6))
                }

                sectionHeader("My notes")
                if notebook.userPages.isEmpty {
                    Text("Tap + to add your own page — notes, reminders, anything.")
                        .font(.custom("ComicRelief-Regular", size: 16))
                        .foregroundColor(Self.ink.opacity(0.55))
                        .padding(.vertical, 4)
                } else {
                    ForEach(notebook.userPages) { page in
                        NotebookPaper(page: page, locked: false,
                                      onOpenLink: page.hasComicLink ? { openComicLink(page) } : nil)
                            .onTapGesture { editingPage = page }
                            .contextMenu {
                                Button(role: .destructive) {
                                    notebook.delete(page)
                                } label: {
                                    Label("Delete page", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .padding()
        }
        .background(Color(red: 0.93, green: 0.91, blue: 0.85).ignoresSafeArea())
        .navigationTitle("Notebook")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingPage = NotebookPage()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingHelp) {
            NotebookHelpView()
        }
        .sheet(item: $editingPage) { page in
            NotebookPageEditor(page: page, onSave: { updated in
                // Don't keep an entirely empty page.
                if updated.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && updated.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    notebook.delete(updated)
                } else {
                    notebook.upsert(updated)
                }
            }, onDelete: {
                notebook.delete(page)
            })
        }
        .sheet(item: $readingPage) { page in
            NotebookPageReader(page: page, onCopyToMyNotes: {
                // Make an independent, editable copy in My notes (keeps admin highlights).
                let copy = NotebookPage(title: page.title, body: page.body)
                notebook.upsert(copy)
            }, onHide: {
                notebook.setAdminHidden(page.id, true)
            })
        }
        // "Open in comic": present the page full-screen and auto-open the hotspot
        // (mirrors the Vocabulary "see in context" pattern).
        .fullScreenCover(item: $linkTarget) { target in
            NavigationStack {
                PageView(
                    comic: target.comic,
                    page: target.page,
                    initialHotspotId: target.hotspotId,
                    savesProgress: false,
                    presentedModally: true
                )
            }
            .environmentObject(SettingsManager())
            .environmentObject(ReadingProgressManager())
        }
        .alert("Can't open link", isPresented: Binding(
            get: { linkError != nil },
            set: { if !$0 { linkError = nil } }
        )) {
            Button("OK", role: .cancel) { linkError = nil }
        } message: {
            Text(linkError ?? "")
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.custom("ComicRelief-Bold", size: 14))
            .foregroundColor(Self.ink.opacity(0.5))
            .padding(.top, 4)
    }
}

/// One page rendered as cream paper with faint rules.
private struct NotebookPaper: View {
    let page: NotebookPage
    var locked: Bool = false
    /// Set on pages saved from a hotspot — renders an "Open in comic" action
    /// that jumps straight back to the hotspot.
    var onOpenLink: (() -> Void)? = nil
    private static let paper = Color(red: 0.99, green: 0.98, blue: 0.94)
    private static let ink = Color(red: 0.14, green: 0.15, blue: 0.22)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if !page.title.isEmpty {
                    Text(page.title)
                        .font(.custom("ComicRelief-Bold", size: 20.4))
                        .foregroundColor(Self.ink)
                }
                Spacer(minLength: 8)
                if locked {
                    Text("ADMIN")
                        .font(.custom("ComicRelief-Bold", size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(red: 0x6E/255, green: 0x40/255, blue: 0xF0/255)))
                }
            }
            Text(page.body.isEmpty ? AttributedString("Tap to write…") : notebookHighlighted(page.body))
                .font(.custom("ComicRelief-Regular", size: 19))
                .foregroundColor(page.body.isEmpty ? Self.ink.opacity(0.4) : Self.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(6)
                .lineLimit(locked ? 6 : nil)

            if page.hasComicLink, let onOpenLink {
                Button(action: onOpenLink) {
                    Label("Open in comic", systemImage: "book.fill")
                        .font(.custom("ComicRelief-Bold", size: 15))
                }
                .buttonStyle(.borderless)
                .tint(Color(red: 0x27/255, green: 0xAE/255, blue: 0x60/255))
                .padding(.top, 2)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Self.paper))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(locked
                        ? Color(red: 0x6E/255, green: 0x40/255, blue: 0xF0/255)   // logo purple — Admin
                        : Color(red: 0x27/255, green: 0xAE/255, blue: 0x60/255),  // green — My Notes
                        lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 3)
    }
}

/// Read-only viewer for admin (grammar) pages, with a "copy to My Notes" action
/// so the user can make an editable, highlightable personal copy.
private struct NotebookPageReader: View {
    @Environment(\.dismiss) private var dismiss
    let page: NotebookPage
    var onCopyToMyNotes: () -> Void
    var onHide: () -> Void
    private static let paper = Color(red: 0.99, green: 0.98, blue: 0.94)
    private static let ink = Color(red: 0.14, green: 0.15, blue: 0.22)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(page.title)
                        .font(.custom("ComicRelief-Bold", size: 23.8))
                        .foregroundColor(Self.ink)
                    Text(notebookHighlighted(page.body))
                        .font(.custom("ComicRelief-Regular", size: 20))
                        .foregroundColor(Self.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(7)

                    Button {
                        onCopyToMyNotes()
                        dismiss()
                    } label: {
                        Label("Copy admin note to My Notes for editing", systemImage: "square.and.pencil")
                            .font(.custom("ComicRelief-Bold", size: 16))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0x6E/255, green: 0x40/255, blue: 0xF0/255))
                    .padding(.top, 12)

                    Button {
                        onHide()
                        dismiss()
                    } label: {
                        Label("Hide note", systemImage: "eye.slash")
                            .font(.custom("ComicRelief-Regular", size: 15))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(Self.ink.opacity(0.6))
                    .padding(.top, 2)
                }
                .padding(24)
            }
            .background(Self.paper.ignoresSafeArea())
            .navigationTitle("Admin Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Explains how the notebook works.
private struct NotebookHelpView: View {
    @Environment(\.dismiss) private var dismiss
    private static let paper = Color(red: 0.99, green: 0.98, blue: 0.94)
    private static let ink = Color(red: 0.14, green: 0.15, blue: 0.22)
    private static let purple = Color(red: 0x6E/255, green: 0x40/255, blue: 0xF0/255)
    private static let green = Color(red: 0x27/255, green: 0xAE/255, blue: 0x60/255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    block("Two kinds of notes", Self.ink, """
                    There are two sections in your notebook.
                    """)

                    block("📘 Admin Notes (purple border)", Self.purple, """
                    Grammar and tips from Comigo. They’re read-only here and update on their own — you can’t edit them directly, but you can copy or hide them.
                    """)

                    block("📗 My Notes (green border)", Self.green, """
                    Your own notes. Tap + at the top to add one, then tap a note to write and edit it.
                    """)

                    block("🖍 Highlighting", Self.ink, """
                    While editing a note, select some text and tap “Highlight” to mark it yellow. Tap it again to remove the highlight.
                    """)

                    block("Copy an admin note", Self.ink, """
                    Open an admin note and tap “Copy admin note to My Notes for editing” — the button is at the BOTTOM of the note. You’ll get your own editable copy (with its highlights) in My Notes.
                    """)

                    block("Hide an admin note", Self.ink, """
                    Open an admin note and tap “Hide note” at the BOTTOM (or press and hold the card). Hidden notes move into “Hidden admin notes” — tap Unhide to bring one back.
                    """)

                    block("Delete one of My Notes", Self.ink, """
                    Open your note and tap “Delete page” at the BOTTOM (or press and hold the card). Admin notes can’t be deleted — only hidden.
                    """)
                }
                .padding(24)
            }
            .background(Self.paper.ignoresSafeArea())
            .navigationTitle("How the notebook works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func block(_ title: String, _ titleColor: Color, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.custom("ComicRelief-Bold", size: 19))
                .foregroundColor(titleColor)
            Text(text)
                .font(.custom("ComicRelief-Regular", size: 16))
                .foregroundColor(Self.ink)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Editor sheet for a single page.
private struct NotebookPageEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var page: NotebookPage
    var onSave: (NotebookPage) -> Void
    var onDelete: (() -> Void)? = nil

    private static let paper = Color(red: 0.99, green: 0.98, blue: 0.94)
    private static let ink = Color(red: 0.14, green: 0.15, blue: 0.22)

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Title", text: $page.title)
                    .font(.custom("ComicRelief-Bold", size: 22))
                    .foregroundColor(Self.ink)
                Divider()
                HighlightingTextView(
                    markup: $page.body,
                    font: UIFont(name: "ComicRelief-Regular", size: 19) ?? .systemFont(ofSize: 19),
                    textColor: UIColor(Self.ink)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Delete page", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding()
            .background(Self.paper.ignoresSafeArea())
            .navigationTitle("Edit page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onSave(page); dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
