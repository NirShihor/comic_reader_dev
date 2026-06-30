import SwiftUI

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
struct NotebookPage: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String = ""
    var body: String = ""
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

    private let storageKey = "notebookPages.v1"
    private let adminCacheKey = "notebookAdminCache.v1"

    init() {
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

/// Handwritten-style notebook. Cream paper pages in the Comic Relief face.
struct NotebookView: View {
    @EnvironmentObject private var notebook: NotebookManager
    @State private var editingPage: NotebookPage?
    @State private var readingPage: NotebookPage?

    private static let ink = Color(red: 0.14, green: 0.15, blue: 0.22)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !notebook.adminPages.isEmpty {
                    sectionHeader("Grammar")
                    ForEach(notebook.adminPages) { page in
                        NotebookPaper(page: page, locked: true)
                            .onTapGesture { readingPage = page }
                    }
                }

                sectionHeader("My notes")
                if notebook.userPages.isEmpty {
                    Text("Tap + to add your own page — notes, reminders, anything.")
                        .font(.custom("ComicRelief-Regular", size: 16))
                        .foregroundColor(Self.ink.opacity(0.55))
                        .padding(.vertical, 4)
                } else {
                    ForEach(notebook.userPages) { page in
                        NotebookPaper(page: page, locked: false)
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
                Button {
                    editingPage = NotebookPage()
                } label: {
                    Image(systemName: "plus")
                }
            }
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
            NotebookPageReader(page: page)
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
    private static let paper = Color(red: 0.99, green: 0.98, blue: 0.94)
    private static let ink = Color(red: 0.14, green: 0.15, blue: 0.22)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if !page.title.isEmpty {
                    Text(page.title)
                        .font(.custom("ComicRelief-Bold", size: 24))
                        .foregroundColor(Self.ink)
                }
                Spacer(minLength: 8)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Self.ink.opacity(0.3))
                }
            }
            Text(page.body.isEmpty ? "Tap to write…" : page.body)
                .font(.custom("ComicRelief-Regular", size: 19))
                .foregroundColor(page.body.isEmpty ? Self.ink.opacity(0.4) : Self.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(6)
                .lineLimit(locked ? 6 : nil)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Self.paper))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 3)
    }
}

/// Read-only viewer for bundled admin (grammar) pages.
private struct NotebookPageReader: View {
    @Environment(\.dismiss) private var dismiss
    let page: NotebookPage
    private static let paper = Color(red: 0.99, green: 0.98, blue: 0.94)
    private static let ink = Color(red: 0.14, green: 0.15, blue: 0.22)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(page.title)
                        .font(.custom("ComicRelief-Bold", size: 28))
                        .foregroundColor(Self.ink)
                    Text(page.body)
                        .font(.custom("ComicRelief-Regular", size: 20))
                        .foregroundColor(Self.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(7)
                }
                .padding(24)
            }
            .background(Self.paper.ignoresSafeArea())
            .navigationTitle("Grammar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
                TextEditor(text: $page.body)
                    .font(.custom("ComicRelief-Regular", size: 19))
                    .foregroundColor(Self.ink)
                    .scrollContentBackground(.hidden)
                    .lineSpacing(6)

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
