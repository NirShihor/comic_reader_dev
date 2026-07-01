import SwiftUI

extension Color {
    /// Navy outline matching the logo bubble (#15172A).
    static let comigoInk = Color(red: 0x15/255, green: 0x17/255, blue: 0x2A/255)
}

struct LibraryView: View {
    @EnvironmentObject var progressManager: ReadingProgressManager
    @StateObject private var localStorage = LocalComicStorage.shared
    @StateObject private var storeService = ComicStoreService.shared
    @State private var comicToDelete: Comic?
    @State private var collectionToDelete: ComicCollection?
    @State private var searchText = ""
    @State private var selectedLevel: String? = nil
    @StateObject private var help = HelpModeController()

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HelpModeButton()
            }
        }
        .helpTooltipLayer()
        .environmentObject(help)
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

    // Indigo brand accent (reserved for primary actions / selected chips).
    private var accentColor: Color { Color(red: 91/255, green: 91/255, blue: 214/255) }

    // Navy outline matching the logo bubble — used for card/chip/field borders.
    private var borderInk: Color { .comigoInk }

    // Custom (bordered) search field — replaces the system .searchable bar so it
    // can carry the navy outline. Bound to the same searchText, so filtering is unchanged.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search comics", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderInk, lineWidth: 2))
    }

    /// The most-recently-started downloaded comic, resolved to the library item
    /// (collection or standalone) it belongs to — so the hero links to the
    /// collection page when it's part of a series.
    private var continueItem: (item: LibraryItem, startedComic: Comic, progress: ReadingProgress)? {
        guard let started = localStorage.downloadedComics
            .compactMap({ c -> (Comic, ReadingProgress)? in
                guard let p = progressManager.getProgress(for: c.id) else { return nil }
                return (c, p)
            })
            .max(by: { $0.1.updatedAt < $1.1.updatedAt }) else { return nil }

        let startedComic = started.0
        let item = localStorage.libraryItems.first { item in
            switch item {
            case .standalone(let c): return c.id == startedComic.id
            case .collection(let col): return col.comics.contains { $0.id == startedComic.id }
            }
        }
        guard let item else { return nil }
        return (item, startedComic, started.1)
    }

    @ViewBuilder
    private func continueHero(_ item: LibraryItem, _ startedComic: Comic, _ progress: ReadingProgress) -> some View {
        let practicing = progressManager.interactionKind(for: startedComic.id) == "practice"
        let practicePos = progressManager.practicePosition(for: startedComic.id)
        let pageTotal = max(startedComic.pages.count, 1)

        // Progress line + bar fraction depend on whether reading or practicing.
        let practiceLine = practicePos.map { "Sentence \($0.index + 1) of \($0.total)" }
        let fraction: Double = {
            if practicing, let p = practicePos, p.total > 0 {
                return Double(min(p.index, p.total)) / Double(p.total)
            }
            return Double(min(progress.pageNumber, pageTotal)) / Double(pageTotal)
        }()

        switch item {
        case .standalone(let comic):
            let line = practicing ? (practiceLine ?? "In practice")
                                   : "Page \(progress.pageNumber) of \(pageTotal)"
            NavigationLink(destination: ComicDetailView(comic: startedComic, autoResume: true)) {
                heroCard(coverName: comic.coverImage, coverComicId: comic.id,
                         title: comic.title, subtitle: comic.titleEn,
                         line: line, fraction: fraction, practicing: practicing)
            }
            .buttonStyle(.plain)

        case .collection(let collection):
            let totalEpisodes = max(storeService.catalog.filter { $0.collectionTitle == collection.title }.count,
                                    collection.episodeCount)
            let episodeLine = "Episode \(startedComic.episodeNumber ?? 1) of \(totalEpisodes)"
            let line = practicing ? (practiceLine ?? episodeLine) : episodeLine
            // Resume the exact episode the user left off in, at its spot and mode.
            NavigationLink(destination: ComicDetailView(comic: startedComic, autoResume: true)) {
                heroCard(coverName: collection.coverImage, coverComicId: collection.coverComicId,
                         title: collection.title, subtitle: collection.titleEn,
                         line: line, fraction: fraction, practicing: practicing)
            }
            .buttonStyle(.plain)
        }
    }

    private func heroCard(coverName: String, coverComicId: String,
                          title: String, subtitle: String?,
                          line: String, fraction: Double, practicing: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ComicImage(imageName: coverName, comicId: coverComicId)
                .aspectRatio(contentMode: .fill)
                .frame(width: 106, height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text(practicing ? "CONTINUE PRACTICING" : "CONTINUE READING")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(accentColor)

                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(line)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                ProgressView(value: fraction, total: 1.0)
                    .tint(accentColor)

                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.system(size: 12, weight: .bold))
                    Text(practicing ? "Continue practicing" : "Continue reading")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(accentColor, in: Capsule())
                .overlay(Capsule().stroke(borderInk, lineWidth: 2))
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(borderInk, lineWidth: 2))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
    }

    private let levelOptions: [(label: String, value: String?)] = [
        ("All", nil), ("Beginner", "beginner"), ("Intermediate", "intermediate"), ("Advanced", "advanced")
    ]

    private var levelChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(levelOptions, id: \.label) { option in
                    let selected = selectedLevel == option.value
                    Text(option.label)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? .white : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(selected ? accentColor : Color(.secondarySystemGroupedBackground),
                                    in: Capsule())
                        .overlay(Capsule().stroke(borderInk, lineWidth: 2))
                        .contentShape(Capsule())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) { selectedLevel = option.value }
                        }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
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
                searchField

                if help.isActive {
                    HelpHint(icon: "books.vertical.fill",
                             label: "How it works",
                             title: "Your library",
                             text: "Collections that have downloaded comics in them sit at the top — tap one to open it. Comics under “Available to download” can be downloaded with the green button. Use the search bar and the level filter to find a comic, and tap “?” any time for help.")
                }

                // The series/comic the reader has started — shown first, with Continue.
                if let cont = continueItem {
                    continueHero(cont.item, cont.startedComic, cont.progress)
                }

                levelChips

                // Downloaded shelf (your comics) on top.
                if !localStorage.downloadedComics.isEmpty {
                    storageInfo
                    ForEach(filteredLibraryItems) { item in
                        downloadedRow(item)
                    }
                }

                availableSection

                // A level filter that has no comics yet (e.g. Advanced) — invite the
                // reader back rather than showing a blank screen. Not shown for search
                // misses (those aren't "coming soon").
                if selectedLevel != nil && searchText.isEmpty
                    && filteredLibraryItems.isEmpty && availableItems.isEmpty
                    && !storeService.isLoadingCatalog {
                    comingSoonPlaceholder
                }
            }
            .padding()
        }
    }

    private var comingSoonPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Coming soon")
                .font(.title3.weight(.bold))
            Text("\((selectedLevel ?? "These").capitalized) comics are on the way — check back soon!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 24)
    }

    /// Downloaded shelf filtered by the search box + level filter. Without this the
    /// search only affected the "available to download" section below.
    private var filteredLibraryItems: [LibraryItem] {
        // The in-progress item is surfaced by the Continue hero, so drop it here
        // to avoid showing it twice.
        let heroId = continueItem?.item.id
        return localStorage.libraryItems.filter { item in
            if let heroId, item.id == heroId { return false }
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
                .frame(width: 106, height: 159)
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
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.comigoInk, lineWidth: 2))
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
                .frame(width: 106, height: 159)
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
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.comigoInk, lineWidth: 2))
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
