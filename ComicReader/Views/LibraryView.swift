import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var progressManager: ReadingProgressManager
    @StateObject private var localStorage = LocalComicStorage.shared
    @StateObject private var storeService = ComicStoreService.shared
    @State private var comicToDelete: Comic?
    @State private var collectionToDelete: ComicCollection?
    @State private var searchText = ""
    @State private var selectedLevel: String? = nil
    @StateObject private var help = HelpModeController()
    // False only until the user has landed on the Library once, ever (persists
    // across launches). Used to auto-open the welcome overlay on the first visit;
    // afterwards the welcome stays reachable on demand via the "?" button.
    @AppStorage("hasSeenLibrary") private var hasSeenLibrary = false

    private var showInitialLoader: Bool {
        localStorage.isLoading && localStorage.downloadedComics.isEmpty
            && storeService.isLoadingCatalog && storeService.catalog.isEmpty
    }

    private var showEmptyState: Bool {
        localStorage.downloadedComics.isEmpty && availableItems.isEmpty && !storeService.isLoadingCatalog
    }

    var body: some View {
        Group {
            if showInitialLoader {
                ProgressView("Loading...")
            } else if showEmptyState {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Library")
        .background(Color(.systemGroupedBackground))
        .searchable(text: $searchText, prompt: "Search comics")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HelpModeButton()
            }
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
        .helpTooltipLayer()
        .environmentObject(help)
        .onAppear {
            // First time the user ever lands on the Library, open the welcome
            // automatically. Afterwards it's reachable any time via the "?" button.
            if !hasSeenLibrary {
                hasSeenLibrary = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeInOut(duration: 0.2)) { help.isActive = true }
                }
            }
        }
        .task {
            // Pull the catalog so available comics + author-set order load.
            await storeService.fetchCatalog()
        }
        .refreshable {
            await storeService.fetchCatalog()
            await localStorage.loadDownloadedComics()
        }
        .alert("Delete Comic", isPresented: Binding(
            get: { comicToDelete != nil },
            set: { if !$0 { comicToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { comicToDelete = nil }
            Button("Delete", role: .destructive) {
                if let comic = comicToDelete {
                    deleteComic(comic)
                    comicToDelete = nil
                }
            }
        } message: {
            if let comic = comicToDelete {
                Text("Delete \"\(comic.title)\"? This will remove it from your device. You can re-download it later.")
            }
        }
        .alert("Delete Collection", isPresented: Binding(
            get: { collectionToDelete != nil },
            set: { if !$0 { collectionToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { collectionToDelete = nil }
            Button("Delete All", role: .destructive) {
                if let collection = collectionToDelete {
                    deleteCollection(collection)
                    collectionToDelete = nil
                }
            }
        } message: {
            if let collection = collectionToDelete {
                Text("Delete all \(collection.episodeCount) episodes of \"\(collection.title)\"? You can re-download them later.")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Comics", systemImage: "books.vertical")
        } description: {
            Text("Pull down to refresh, or check your internet connection.")
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if help.isActive {
                    HelpHint(icon: "books.vertical.fill",
                             label: "Welcome",
                             title: "Your library",
                             text: "Collections that have downloaded comics in them sit at the top — tap one to open it. Comics under “Available to download” can be downloaded with the green button. Use the search bar and the filter (top right) to find a comic, and tap “?” any time for help.")
                    HelpHint(icon: "arrow.down.circle.fill",
                             label: "Download",
                             title: "Get a comic",
                             text: "Tap the green Download button on any available comic to save it to your device so you can read it offline.")
                }

                // Downloaded shelf (your comics) on top.
                if !localStorage.downloadedComics.isEmpty {
                    storageInfo
                    ForEach(filteredLibraryItems) { item in
                        downloadedRow(item)
                    }
                }

                availableSection
            }
            .padding()
        }
    }

    /// Downloaded shelf filtered by the search box + level filter. Without this the
    /// search only affected the "available to download" section below.
    private var filteredLibraryItems: [LibraryItem] {
        localStorage.libraryItems.filter { item in
            // Level filter
            if let level = selectedLevel {
                switch item {
                case .standalone(let c):
                    if c.level.rawValue != level { return false }
                case .collection(let col):
                    if col.level.rawValue != level { return false }
                }
            }
            // Search text (title / English title / description / collection name)
            guard !searchText.isEmpty else { return true }
            switch item {
            case .standalone(let c):
                return c.title.localizedCaseInsensitiveContains(searchText)
                    || (c.titleEn ?? "").localizedCaseInsensitiveContains(searchText)
                    || c.description.localizedCaseInsensitiveContains(searchText)
            case .collection(let col):
                return col.title.localizedCaseInsensitiveContains(searchText)
                    || (col.titleEn ?? "").localizedCaseInsensitiveContains(searchText)
                    || col.comics.contains { c in
                        c.title.localizedCaseInsensitiveContains(searchText)
                            || (c.titleEn ?? "").localizedCaseInsensitiveContains(searchText)
                    }
            }
        }
    }

    @ViewBuilder
    private func downloadedRow(_ item: LibraryItem) -> some View {
        switch item {
        case .standalone(let comic):
            NavigationLink(value: comic) {
                ComicCard(comic: comic, progress: progressManager.getProgress(for: comic.id))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    comicToDelete = comic
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

        case .collection(let collection):
            NavigationLink(destination: CollectionDetailView(title: collection.title)) {
                CollectionCard(collection: collection)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    collectionToDelete = collection
                } label: {
                    Label("Delete All Episodes", systemImage: "trash")
                }
            }
        }
    }

    // Comics from the catalog that aren't (fully) downloaded yet — shown with the
    // Store's download cards. Once downloaded they drop out of here and appear in
    // the shelf above.
    @ViewBuilder
    private var availableSection: some View {
        if storeService.isLoadingCatalog && storeService.catalog.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical)
        } else if storeService.catalogError != nil && storeService.catalog.isEmpty {
            if !localStorage.downloadedComics.isEmpty {
                Text("Couldn't load more comics — pull down to refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        } else if !availableItems.isEmpty {
            HStack {
                Text("Available to download")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 8)

            ForEach(availableItems) { item in
                switch item {
                case .standalone(let comic):
                    StoreComicCard(comic: comic, onOpenComic: nil)
                case .collection(let title, let comics):
                    StoreCollectionGroup(title: title, comics: comics, onOpenComic: nil)
                }
            }
        }
    }

    /// Catalog grouped into standalone/collection items, filtered by search/level
    /// and to exclude what's already fully downloaded, sorted author-order first.
    private var availableItems: [StoreView.StoreItem] {
        let downloadedIds = Set(localStorage.downloadedComics.map { $0.id })
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

        // Group by collection (mirrors StoreView)
        var items: [StoreView.StoreItem] = []
        var collectionMap: [String: [StoreComic]] = [:]
        var collectionOrder: [String] = []
        for comic in comics {
            if let collectionTitle = comic.collectionTitle {
                if collectionMap[collectionTitle] == nil { collectionOrder.append(collectionTitle) }
                collectionMap[collectionTitle, default: []].append(comic)
            } else {
                items.append(.standalone(comic))
            }
        }
        for title in collectionOrder {
            if let episodes = collectionMap[title] {
                let sorted = episodes.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
                items.append(.collection(title: title, comics: sorted))
            }
        }

        // Drop items already fully in the shelf (a collection stays here while it
        // still has episodes left to download, so you can complete it).
        items = items.filter { item in
            switch item {
            case .standalone(let c): return !downloadedIds.contains(c.id)
            case .collection(_, let cs): return !cs.contains { downloadedIds.contains($0.id) }
            }
        }

        return items.sorted { a, b in
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return a.sortTitle.localizedCaseInsensitiveCompare(b.sortTitle) == .orderedAscending
        }
    }

    private func deleteComic(_ comic: Comic) {
        localStorage.deleteComic(comic.id)
        progressManager.clearProgress(for: comic.id)
    }

    private func deleteCollection(_ collection: ComicCollection) {
        for comic in collection.comics {
            localStorage.deleteComic(comic.id)
            progressManager.clearProgress(for: comic.id)
        }
    }

    private var storageInfo: some View {
        let bytesUsed = localStorage.calculateStorageUsed()
        let mbUsed = Double(bytesUsed) / 1_000_000

        return HStack {
            Image(systemName: "internaldrive")
                .foregroundStyle(.secondary)
            Text("\(localStorage.downloadedComics.count) comics • \(String(format: "%.1f", mbUsed)) MB")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Comic Card
struct ComicCard: View {
    let comic: Comic
    let progress: ReadingProgress?

    var body: some View {
        HStack(spacing: 16) {
            // Cover Image
            ComicImage(imageName: comic.coverImage, comicId: comic.id)
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 2)

            // Info
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(comic.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let titleEn = comic.titleEn, !titleEn.isEmpty {
                        Text(titleEn)
                            .font(.subheadline)
                            .fontWeight(.regular)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(comic.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    // Level badge
                    Text(comic.level.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(levelColor.opacity(0.2))
                        .foregroundStyle(levelColor)
                        .clipShape(Capsule())
                        .fixedSize()

                    // Premium badge
                    if comic.isPremium {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }

                    Spacer()
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private var levelColor: Color {
        switch comic.level {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        }
    }
}

// MARK: - Collection Card
struct CollectionCard: View {
    let collection: ComicCollection
    @StateObject private var storeService = ComicStoreService.shared

    // Total episodes from the catalog (falls back to downloaded count offline).
    private var totalEpisodes: Int {
        let catalogTotal = storeService.catalog.filter { $0.collectionTitle == collection.title }.count
        return max(catalogTotal, collection.episodeCount)
    }

    private var episodesLabel: String {
        let downloaded = collection.episodeCount
        if totalEpisodes > downloaded {
            return "\(downloaded) of \(totalEpisodes) episodes"
        }
        return "\(totalEpisodes) episode\(totalEpisodes == 1 ? "" : "s")"
    }

    // English title: prefer a downloaded episode's value, else the catalog.
    private var titleEn: String? {
        collection.titleEn
            ?? storeService.catalog.first(where: { $0.collectionTitle == collection.title })?.collectionTitleEn
    }

    var body: some View {
        HStack(spacing: 16) {
            // Cover Image (from first episode)
            ComicImage(imageName: collection.coverImage, comicId: collection.coverComicId)
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 2)

            // Info
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let titleEn = titleEn, !titleEn.isEmpty {
                        Text(titleEn)
                            .font(.subheadline)
                            .fontWeight(.regular)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(episodesLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(collection.level.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(levelColor.opacity(0.2))
                        .foregroundStyle(levelColor)
                        .clipShape(Capsule())
                        .fixedSize()

                    Spacer()
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private var levelColor: Color {
        switch collection.level {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        }
    }
}

#Preview {
    NavigationStack {
        LibraryView()
            .environmentObject(ReadingProgressManager())
    }
}
