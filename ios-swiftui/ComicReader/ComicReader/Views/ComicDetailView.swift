import SwiftUI

enum PracticeDestination: Hashable {
    case quiz
    case speaking
}

struct ComicDetailView: View {
    let comic: Comic
    @EnvironmentObject var progressManager: ReadingProgressManager

    @State private var practiceDestination: PracticeDestination?
    @State private var selectedPage: Page?

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
                } label: {
                    Image(systemName: "graduationcap.fill")
                        .font(.body)
                }
            }
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

    // MARK: - Action Buttons
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                selectedPage = startingPage
            } label: {
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
            }

            if progressManager.getProgress(for: comic.id) != nil {
                Button {
                    selectedPage = comic.pages.min(by: { $0.pageNumber < $1.pageNumber })
                } label: {
                    Label("Start Again", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var startingPage: Page {
        if let progress = progressManager.getProgress(for: comic.id),
           let page = comic.pages.first(where: { $0.pageNumber == progress.pageNumber }) {
            return page
        }
        // Return the page with the lowest pageNumber (cover)
        return comic.pages.min(by: { $0.pageNumber < $1.pageNumber }) ?? comic.pages[0]
    }

    // MARK: - Pages Grid
    private var pagesGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(comic.pages) { page in
                Button {
                    selectedPage = page
                } label: {
                    PageThumbnail(page: page, comic: comic)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
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
