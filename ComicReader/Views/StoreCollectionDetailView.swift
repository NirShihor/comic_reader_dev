import SwiftUI

struct StoreCollectionDetailView: View {
    let title: String
    let comics: [StoreComic]
    var onOpenComic: ((Comic) -> Void)?
    @StateObject private var storeService = ComicStoreService.shared
    @State private var showingFullCover = false

    private var collectionDescription: String? {
        comics.first?.collectionDescription
    }

    private var collectionCoverUrl: String? {
        if let url = comics.first?.collectionCoverThumbnailUrl, !url.isEmpty {
            return url
        }
        if let url = comics.first?.coverThumbnailUrl, !url.isEmpty {
            return url
        }
        return nil
    }

    private var levelColor: Color {
        switch comics.first?.level ?? "beginner" {
        case "beginner": return .green
        case "intermediate": return .orange
        case "advanced": return .red
        default: return .blue
        }
    }

    private var hasAnyDownloaded: Bool {
        comics.contains { storeService.downloadState(for: $0.id) == .downloaded }
    }

    private var allHidden: Bool {
        comics.allSatisfy { storeService.downloadState(for: $0.id) == .hidden }
    }

    private var totalSizeMB: Double {
        comics.reduce(0) { $0 + $1.fileSizeMB }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Cover image
                coverSection

                // Info section
                infoSection

                // Episodes
                episodeList
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasAnyDownloaded {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        storeService.deleteCollection(comics.map(\.id))
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
            } else if allHidden {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            for comic in comics {
                                await storeService.restoreComic(comic.id)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingFullCover) {
            fullCoverOverlay
        }
    }

    // MARK: - Cover
    private var coverSection: some View {
        Button {
            showingFullCover = true
        } label: {
            if let coverUrl = collectionCoverUrl {
                AsyncImage(url: URL(string: "\(Secrets.serverBaseURL)\(coverUrl)")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 350)
                    case .failure:
                        coverPlaceholder
                    default:
                        ProgressView()
                            .frame(height: 250)
                    }
                }
            } else {
                coverPlaceholder
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 0)
            .fill(levelColor.opacity(0.1))
            .frame(height: 250)
            .overlay(
                Image(systemName: "books.vertical.fill")
                    .font(.largeTitle)
                    .foregroundStyle(levelColor.opacity(0.4))
            )
    }

    // MARK: - Info
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 12) {
                Text(comics.first?.level.capitalized ?? "Beginner")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(levelColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())

                Label("\(comics.count) episode\(comics.count == 1 ? "" : "s")", systemImage: "books.vertical")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if totalSizeMB > 0 {
                    Label("\(String(format: "%.0f", totalSizeMB)) MB", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let desc = collectionDescription, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Episodes
    private var episodeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Episodes")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(Array(comics.enumerated()), id: \.element.id) { index, comic in
                    StoreComicCard(
                        comic: comic,
                        onOpenComic: onOpenComic,
                        compact: true,
                        episodeLabel: "Ep. \(comic.episodeNumber ?? (index + 1))"
                    )

                    if index < comics.count - 1 {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.3))
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Full Cover Overlay
    private var fullCoverOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let coverUrl = collectionCoverUrl {
                AsyncImage(url: URL(string: "\(Secrets.serverBaseURL)\(coverUrl)")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .ignoresSafeArea()
                    default:
                        ProgressView()
                            .tint(.white)
                    }
                }
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showingFullCover = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()
            }
        }
    }
}
