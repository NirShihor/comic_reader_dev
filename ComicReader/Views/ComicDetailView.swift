import SwiftUI

enum PracticeDestination: Hashable {
    case quiz
    case speaking
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

                // Action buttons
                HStack(spacing: 12) {
                    Label(
                        progressManager.getProgress(for: comic.id) != nil ? "Continue" : "Start Reading",
                        systemImage: "book.fill"
                    )
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPage = startingPage
                    }

                    if progressManager.getProgress(for: comic.id) != nil {
                        Label("Start Again", systemImage: "arrow.counterclockwise")
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray5))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPage = firstPage
                            }
                    }
                }
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
                HStack(spacing: 16) {
                    Menu {
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
                        }

                        Section {
                            Toggle(isOn: $settingsManager.speakingPracticeMode) {
                                Label("Speaking Practice Mode", systemImage: "bubble.left.and.text.bubble.right")
                            }
                        }
                    } label: {
                        Image(systemName: "graduationcap.fill")
                            .font(.body)
                            .foregroundStyle(settingsManager.speakingPracticeMode ? .green : .accentColor)
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
            }
        }
        .navigationDestination(item: $selectedPage) { page in
            PageView(comic: comic, page: page)
                .id(page.id)  // Force new view instance for each page
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
                PageThumbnail(page: page, comic: comic)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPage = page
                    }
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
    @EnvironmentObject var progressManager: ReadingProgressManager

    var body: some View {
        VStack(spacing: 8) {
            ComicImage(imageName: page.masterImage, comicId: comic.id)
                .aspectRatio(contentMode: .fill)
                .frame(height: 180)
                .clipped()
                .overlay(
                    Rectangle()
                        .stroke(isCurrentPage ? Color.accentColor : Color.clear, lineWidth: 3)
                )

            HStack {
                Text("Page \(page.pageNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isCurrentPage {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var isCurrentPage: Bool {
        progressManager.getProgress(for: comic.id)?.pageNumber == page.pageNumber
    }
}

#Preview {
    NavigationStack {
        ComicDetailView(comic: ComicData.allComics[0])
            .environmentObject(ReadingProgressManager())
            .environmentObject(SettingsManager())
    }
}
