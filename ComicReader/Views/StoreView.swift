import SwiftUI

struct StoreView: View {
    @StateObject private var storeService = ComicStoreService.shared
    @StateObject private var localStorage = LocalComicStorage.shared
    @State private var searchText = ""
    @State private var selectedLevel: String? = nil
    var onOpenComic: ((Comic) -> Void)?

    /// Items to display: standalone comics + collection groups
    var storeItems: [StoreItem] {
        var comics = storeService.catalog

        if !searchText.isEmpty {
            comics = comics.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                ($0.collectionTitle ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        if let level = selectedLevel {
            comics = comics.filter { $0.level == level }
        }

        // Group by collection
        var items: [StoreItem] = []
        var collectionMap: [String: [StoreComic]] = [:]
        var collectionOrder: [String] = []

        for comic in comics {
            if let collectionTitle = comic.collectionTitle {
                if collectionMap[collectionTitle] == nil {
                    collectionOrder.append(collectionTitle)
                }
                collectionMap[collectionTitle, default: []].append(comic)
            } else {
                items.append(.standalone(comic))
            }
        }

        // Add collections in order they appeared
        for title in collectionOrder {
            if let episodes = collectionMap[title] {
                let sorted = episodes.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
                items.append(.collection(title: title, comics: sorted))
            }
        }

        return items
    }

    enum StoreItem: Identifiable {
        case standalone(StoreComic)
        case collection(title: String, comics: [StoreComic])

        var id: String {
            switch self {
            case .standalone(let comic): return comic.id
            case .collection(let title, _): return "collection-\(title)"
            }
        }
    }

    var body: some View {
        Group {
            if storeService.isLoadingCatalog && storeService.catalog.isEmpty {
                ProgressView("Loading comics...")
            } else if let error = storeService.catalogError {
                errorView(error)
            } else {
                catalogList
            }
        }
        .navigationTitle("Store")
        .searchable(text: $searchText, prompt: "Search comics")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("All Levels") { selectedLevel = nil }
                    Divider()
                    Button("Beginner") { selectedLevel = "beginner" }
                    Button("Intermediate") { selectedLevel = "intermediate" }
                    Button("Advanced") { selectedLevel = "advanced" }
                } label: {
                    Image(systemName: selectedLevel == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .task {
            if storeService.catalog.isEmpty {
                await storeService.fetchCatalog()
            }
        }
        .refreshable {
            await storeService.fetchCatalog()
        }
    }

    private func errorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label("Unable to Load", systemImage: "wifi.slash")
        } description: {
            Text("Check your internet connection and try again.")
        } actions: {
            Button("Retry") {
                Task {
                    await storeService.fetchCatalog()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var catalogList: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if storeItems.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(storeItems) { item in
                        switch item {
                        case .standalone(let comic):
                            StoreComicCard(comic: comic, onOpenComic: onOpenComic)

                        case .collection(let title, let comics):
                            StoreCollectionGroup(
                                title: title,
                                comics: comics,
                                onOpenComic: onOpenComic
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Store Comic Card
struct StoreComicCard: View {
    let comic: StoreComic
    var onOpenComic: ((Comic) -> Void)?
    var compact: Bool = false
    var episodeLabel: String? = nil
    @StateObject private var storeService = ComicStoreService.shared
    @StateObject private var localStorage = LocalComicStorage.shared

    var downloadState: DownloadState {
        storeService.downloadState(for: comic.id)
    }

    private var coverSize: (width: CGFloat, height: CGFloat) {
        compact ? (60, 90) : (80, 120)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: compact ? 12 : 16) {
                // Cover image from server
                AsyncImage(url: URL(string: "\(Secrets.serverBaseURL)\(comic.coverThumbnailUrl)")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: coverSize.width, height: coverSize.height)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    case .failure:
                        RoundedRectangle(cornerRadius: 6)
                            .fill(levelColor.opacity(0.2))
                            .frame(width: coverSize.width, height: coverSize.height)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(levelColor)
                            )
                    default:
                        RoundedRectangle(cornerRadius: 6)
                            .fill(levelColor.opacity(0.1))
                            .frame(width: coverSize.width, height: coverSize.height)
                            .overlay(ProgressView())
                    }
                }
                .frame(width: coverSize.width, height: coverSize.height)

                // Info
                VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                    HStack {
                        if let ep = episodeLabel {
                            Text(ep)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        }
                        Text(comic.title)
                            .font(compact ? .subheadline.weight(.semibold) : .headline)
                            .foregroundStyle(.primary)
                    }

                    // Show collection info only for standalone cards (not inside a group)
                    if !compact, let collection = comic.collectionTitle {
                        HStack(spacing: 4) {
                            Text(collection)
                                .font(.caption)
                                .foregroundStyle(.green)
                            if let episode = comic.episodeNumber, episode > 0 {
                                Text("· Episode \(episode)")
                                    .font(.caption)
                                    .foregroundStyle(.green.opacity(0.7))
                            }
                        }
                    }

                    Text(comic.description)
                        .font(compact ? .caption : .subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(compact ? 1 : 2)

                    HStack(spacing: 8) {
                        if !compact {
                            // Level badge (color-coded)
                            Text(comic.level.capitalized)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(levelColor)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .fixedSize()
                        }

                        // Pages count
                        Label("\(comic.totalPages)", systemImage: "book.pages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()

                        // Duration
                        Label("\(comic.estimatedMinutes)m", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()

                        if compact, comic.fileSizeMB > 0 {
                            Text("· \(String(format: "%.0f", comic.fileSizeMB)) MB")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .fixedSize()
                        }
                    }
                }
            }

            // File size (standalone only)
            if !compact, comic.fileSizeMB > 0 {
                Text("\(String(format: "%.1f", comic.fileSizeMB)) MB")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Download button / status
            downloadButton
        }
        .padding(compact ? 12 : 16)
        .background(compact ? Color.clear : Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 0 : 12))
    }

    @ViewBuilder
    private var downloadButton: some View {
        switch downloadState {
        case .notDownloaded:
            Button {
                Task {
                    await storeService.downloadComic(comic)
                }
            } label: {
                Label("Download", systemImage: "arrow.down.circle.fill")
                    .font(.subheadline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

        case .downloading(let progress):
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)

                HStack {
                    Text("Downloading... \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Cancel") {
                        storeService.cancelDownload(comic.id)
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }

        case .downloaded:
            HStack {
                Button {
                    if let downloadedComic = localStorage.downloadedComics.first(where: { $0.id == comic.id }) {
                        onOpenComic?(downloadedComic)
                    }
                } label: {
                    Label("Open in Library", systemImage: "book.fill")
                        .font(.subheadline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Spacer()

                Button {
                    storeService.deleteDownload(comic.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)

        case .hidden:
            Button {
                Task {
                    await storeService.restoreComic(comic.id)
                }
            } label: {
                Label("Restore to Library", systemImage: "arrow.uturn.backward.circle.fill")
                    .font(.subheadline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

        case .failed(let error):
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Download failed")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Retry") {
                    Task {
                        await storeService.downloadComic(comic)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var levelColor: Color {
        switch comic.level {
        case "beginner": return .green
        case "intermediate": return .orange
        case "advanced": return .red
        default: return .blue
        }
    }
}

// MARK: - Store Collection Group
struct StoreCollectionGroup: View {
    let title: String
    let comics: [StoreComic]
    var onOpenComic: ((Comic) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collection header
            HStack(spacing: 10) {
                Image(systemName: "books.vertical.fill")
                    .font(.title3)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    Text("\(comics.count) episode\(comics.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(
                .rect(topLeadingRadius: 12, topTrailingRadius: 12)
            )

            // Divider
            Rectangle()
                .fill(Color(.separator).opacity(0.3))
                .frame(height: 1)

            // Episode cards
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
            .clipShape(
                .rect(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
            )
        }
    }
}

#Preview {
    NavigationStack {
        StoreView(onOpenComic: nil)
    }
}
