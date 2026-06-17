import SwiftUI

enum PracticeDestination: Hashable {
    case quiz
    case speaking
    case listening
    case repeatPractice
    case repeatListen
    case originListen
    case flowPractice
}

struct ComicDetailView: View {
    let comic: Comic
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var progressManager: ReadingProgressManager
    @EnvironmentObject var settingsManager: SettingsManager
    @StateObject private var localStorage = LocalComicStorage.shared

    @State private var practiceDestination: PracticeDestination?
    @State private var selectedPage: Page?
    @State private var showingDeleteConfirmation = false
    @State private var showingPracticeHelp = false
    @StateObject private var help = HelpModeController()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with cover and info
                headerSection
                    .padding(.horizontal, 16)

                actionButtons
                    .padding(.horizontal, 16)

                // Pages grid
                pagesGrid
            }
            .padding(.vertical, 16)
        }
        .navigationTitle(comic.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                trailingToolbar
            }
        }
        .alert("Delete Comic", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                localStorage.deleteComic(comic.id)
                progressManager.clearProgress(for: comic.id)
                dismiss()
            }
        } message: {
            Text("Delete \"\(comic.title)\"? This will remove it from your device. You can re-download it later.")
        }
        .navigationDestination(item: $practiceDestination) { destination in
            switch destination {
            case .quiz:
                QuizView(comic: comic)
            case .speaking:
                SpeakingTestView(comic: comic)
            case .listening:
                ListeningTestView(comic: comic)
            case .repeatPractice:
                RepeatPracticeView(comic: comic)
            case .repeatListen:
                RepeatListenView(comic: comic)
            case .originListen:
                OriginListenView(comic: comic)
            case .flowPractice:
                FlowPracticeView(comic: comic)
            }
        }
        .navigationDestination(item: $selectedPage) { page in
            PageView(comic: comic, page: page)
                .id(page.id)  // Force new view instance for each page
        }
        .sheet(isPresented: $showingPracticeHelp) {
            PracticeModesHelpView()
        }
        .helpTooltipLayer()
        .environmentObject(help)
    }

    // MARK: - Trailing Toolbar
    @ViewBuilder
    private var trailingToolbar: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { help.toggle() }
            } label: {
                Image(systemName: help.isActive ? "questionmark.circle.fill" : "questionmark.circle")
            }

            if help.isActive {
                // In help mode the hat explains the practice modes instead of opening the menu.
                Button {
                    showingPracticeHelp = true
                } label: {
                    Image(systemName: "graduationcap.fill")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                                )
                        )
                }
            } else {
                practiceMenu
            }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Action Buttons
    private var hasProgress: Bool {
        progressManager.getProgress(for: comic.id) != nil
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Label(hasProgress ? "Continue" : "Start Reading", systemImage: "book.fill")
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .onTapGesture { selectedPage = startingPage }
                .explains("Start reading",
                          "Open the comic and start reading — it picks up from where you left off.")

            if hasProgress {
                Label("Start Again", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .onTapGesture { selectedPage = firstPage }
                    .explains("Start again",
                              "Go back to the first page and read the comic from the beginning.")
            }
        }
    }

    // MARK: - Practice Menu (graduation cap)
    private var practiceMenu: some View {
        Menu {
            Section("Sentence Practice") {
                Button {
                    practiceDestination = .repeatPractice
                } label: {
                    Label("Repeat Practice", systemImage: "mouth.fill")
                }
                Button {
                    practiceDestination = .repeatListen
                } label: {
                    Label("Repeat Listen", systemImage: "headphones")
                }
                Button {
                    practiceDestination = .originListen
                } label: {
                    Label("Origin Listen", systemImage: "play.circle")
                }
                // Flow Practice is hidden until it's ready (AI behaviour / English
                // handling still being refined). Re-enable by restoring this button.
                // Button {
                //     practiceDestination = .flowPractice
                // } label: {
                //     Label("Flow Practice", systemImage: "bubble.left.and.bubble.right")
                // }
            }

            Section("Practice Key Words") {
                Button {
                    practiceDestination = .quiz
                } label: {
                    Label("Writing", systemImage: "pencil.line")
                }

                Button {
                    practiceDestination = .speaking
                } label: {
                    Label("Speaking", systemImage: "mic.fill")
                }

                Button {
                    practiceDestination = .listening
                } label: {
                    Label("Listening", systemImage: "headphones")
                }
            }

            Section("Reading and Speaking Practice") {
                Toggle(isOn: Binding(
                    get: { settingsManager.speakingPracticeMode },
                    set: { newValue in
                        settingsManager.speakingPracticeMode = newValue
                        if newValue { settingsManager.listeningPracticeMode = false }
                    }
                )) {
                    Label("Speaking Practice Mode", systemImage: "bubble.left.and.text.bubble.right")
                }

                Toggle(isOn: Binding(
                    get: { settingsManager.listeningPracticeMode },
                    set: { newValue in
                        settingsManager.listeningPracticeMode = newValue
                        if newValue { settingsManager.speakingPracticeMode = false }
                    }
                )) {
                    Label("Listening Practice Mode", systemImage: "headphones")
                }
            }
        } label: {
            let activePractice = settingsManager.speakingPracticeMode || settingsManager.listeningPracticeMode
            Image(systemName: "graduationcap.fill")
                .font(.body)
                .foregroundStyle(activePractice ? .green : .accentColor)
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            ComicImage(imageName: comic.coverImage, comicId: comic.id)
                .aspectRatio(contentMode: .fit)
                .frame(width: 118)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(comic.title)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(comic.description)
                    .font(.body)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Label(comic.level.displayName, systemImage: "chart.bar.fill")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(levelColor.opacity(0.2))
                        .foregroundStyle(levelColor)
                        .clipShape(Capsule())
                        .fixedSize()

                    Label("\(comic.pages.count) pages", systemImage: "book.pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // Pages sorted by pageNumber for navigation
    private var sortedPages: [Page] {
        comic.pages.sorted { $0.pageNumber < $1.pageNumber }
    }

    // The first page (cover)
    private var firstPage: Page {
        sortedPages.first ?? comic.pages[0]
    }

    private var startingPage: Page {
        if let progress = progressManager.getProgress(for: comic.id),
           let page = comic.pages.first(where: { $0.pageNumber == progress.pageNumber }) {
            return page
        }
        // Return the first page (cover)
        return firstPage
    }

    // MARK: - Pages Grid
    private var pagesGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(comic.pages) { page in
                PageThumbnail(page: page, comic: comic, isCover: page.pageNumber <= 1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPage = page
                    }
                    .explainsIf(page.id == comic.pages.first?.id,
                                "Jump to a page",
                                "Tap any page thumbnail to open the comic straight at that page.")
            }
        }
        .padding(.horizontal, 16)
        .clipped()
    }

    private var levelColor: Color {
        switch comic.level {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        }
    }
}

// MARK: - Page Thumbnail
struct PageThumbnail: View {
    let page: Page
    let comic: Comic
    var isCover: Bool = false
    @EnvironmentObject var progressManager: ReadingProgressManager
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let practiceActive = settingsManager.speakingPracticeMode || settingsManager.listeningPracticeMode
                let imageName = practiceActive
                    ? (page.noTextImage ?? page.masterImage)
                    : page.masterImage
                ComicImage(imageName: imageName, comicId: comic.id)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: isCover ? .top : .center)
            }
            .frame(height: 180)
            .clipped()
                .overlay(
                    Rectangle()
                        .stroke(isCurrentPage ? .green : Color.clear, lineWidth: 3)
                )

            HStack {
                Text("Page \(page.pageNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isCurrentPage {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var isCurrentPage: Bool {
        progressManager.getProgress(for: comic.id)?.pageNumber == page.pageNumber
    }
}

// MARK: - Practice Modes Help
/// Explains each entry in the practice (graduation-cap) menu. Shown when the
/// hat is tapped in help mode.
struct PracticeModesHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Mode: Identifiable {
        let id = UUID()
        let icon: String
        let name: String
        let detail: String
    }

    private let sentenceModes: [Mode] = [
        Mode(icon: "mouth.fill", name: "Repeat Practice",
             detail: "Listen to each sentence, then say it back. The app checks your pronunciation and understanding before moving on."),
        Mode(icon: "headphones", name: "Repeat Listen",
             detail: "Hear each sentence in Spanish and recall its meaning, then reveal the translation — listening practice, hands-free."),
        Mode(icon: "play.circle", name: "Origin Listen",
             detail: "Sit back and listen to the whole story read aloud, sentence by sentence."),
        // Flow Practice hidden until ready — restore alongside the menu button.
        // Mode(icon: "bubble.left.and.bubble.right", name: "Flow Practice",
        //      detail: "Have a live chat with the AI that weaves in the words and phrases from this comic — used in new situations, so you have to understand and reply with them."),
    ]

    private let keyWordModes: [Mode] = [
        Mode(icon: "pencil.line", name: "Writing",
             detail: "Quiz yourself by typing the Spanish for each key word from the comic."),
        Mode(icon: "mic.fill", name: "Speaking",
             detail: "Say each key word out loud; the app listens and checks your pronunciation."),
        Mode(icon: "headphones", name: "Listening",
             detail: "Hear a key word in Spanish and say what it means in English."),
    ]

    private let practiceToggles: [Mode] = [
        Mode(icon: "bubble.left.and.text.bubble.right", name: "Speaking Practice Mode",
             detail: "Hides the Spanish text while you read, so you try to say each line yourself before revealing it."),
        Mode(icon: "headphones", name: "Listening Practice Mode",
             detail: "Hides the text and asks for the English meaning as you read — a listening-first way through the comic."),
    ]

    var body: some View {
        NavigationStack {
            List {
                section("Sentence Practice", sentenceModes)
                section("Practice Key Words", keyWordModes)
                section("Reading and Speaking Practice", practiceToggles)
            }
            .navigationTitle("Practice modes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func section(_ title: String, _ modes: [Mode]) -> some View {
        Section(title) {
            ForEach(modes) { mode in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: mode.icon)
                        .font(.title3)
                        .foregroundStyle(.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(mode.name)
                            .font(.headline)
                        Text(mode.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ComicDetailView(comic: ComicData.allComics[0])
            .environmentObject(ReadingProgressManager())
            .environmentObject(SettingsManager())
    }
}
