import SwiftUI

/// A single collection. Driven by the collection title so it works whether or not
/// any episodes are downloaded yet: it lists every episode from the catalog —
/// downloaded ones open in place, missing ones download in place — so there's no
/// separate Store screen and no "Open in Library" hop.
struct CollectionDetailView: View {
    let title: String
    @EnvironmentObject var progressManager: ReadingProgressManager
    @StateObject private var localStorage = LocalComicStorage.shared
    @StateObject private var storeService = ComicStoreService.shared
    @StateObject private var help = HelpModeController()

    // All episodes from the catalog (when loaded), in episode order.
    private var catalogEpisodes: [StoreComic] {
        storeService.catalog
            .filter { $0.collectionTitle == title }
            .sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
    }

    // Downloaded episodes — offline fallback + metadata source.
    private var downloadedEpisodes: [Comic] {
        localStorage.downloadedComics
            .filter { $0.collectionTitle == title }
            .sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
    }

    private var episodeCount: Int {
        catalogEpisodes.isEmpty ? downloadedEpisodes.count : catalogEpisodes.count
    }

    private var downloadedCount: Int {
        let ids = Set(localStorage.downloadedComics.map { $0.id })
        if !catalogEpisodes.isEmpty {
            return catalogEpisodes.filter { ids.contains($0.id) }.count
        }
        return downloadedEpisodes.count
    }

    private var levelString: String {
        catalogEpisodes.first?.level ?? downloadedEpisodes.first?.level.rawValue ?? "beginner"
    }

    private var levelColor: Color {
        switch levelString {
        case "intermediate": return .orange
        case "advanced": return .red
        default: return .green
        }
    }

    private var collectionDescription: String? {
        catalogEpisodes.first?.collectionDescription
    }

    private var titleEn: String? {
        catalogEpisodes.first?.collectionTitleEn ?? downloadedEpisodes.first?.collectionTitleEn
    }

    private func downloadedComic(_ id: String) -> Comic? {
        localStorage.downloadedComics.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                episodeSection
            }
            .padding(.vertical)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HelpModeButton()
            }
        }
        .helpTooltipLayer()
        .environmentObject(help)
        .task {
            // Load the catalog here too, not just from the Library. Opening a
            // collection before the Library's fetch has landed (or if it failed)
            // otherwise leaves this view showing only the downloaded episodes
            // (e.g. just episode 1) until some later navigation re-fetches.
            if storeService.catalog.isEmpty && !storeService.isLoadingCatalog {
                await storeService.fetchCatalog()
            }
        }
        .refreshable {
            await storeService.fetchCatalog()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Collection:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let titleEn = titleEn, !titleEn.isEmpty {
                    Text(titleEn)
                        .font(.title3)
                        .fontWeight(.regular)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 12) {
                Text(levelString.capitalized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(levelColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .fixedSize()

                let label = downloadedCount > 0 && downloadedCount < episodeCount
                    ? "\(episodeCount) episodes · \(downloadedCount) downloaded"
                    : "\(episodeCount) episode\(episodeCount == 1 ? "" : "s")"
                Label(label, systemImage: "books.vertical")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            if let desc = collectionDescription, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.comigoInk, lineWidth: 2))
        .padding(.horizontal)
        .explains("Collection",
                  "This is the collection — a series of comics. Its name, level and episode count are shown here. The comics in it are listed below.",
                  id: "collection.header")
    }

    @ViewBuilder
    private var episodeSection: some View {
        if !catalogEpisodes.isEmpty {
            LazyVStack(spacing: 12) {
                ForEach(Array(catalogEpisodes.enumerated()), id: \.element.id) { index, ep in
                    if let local = downloadedComic(ep.id) {
                        // Downloaded → open in place.
                        NavigationLink(destination: ComicDetailView(comic: local)) {
                            EpisodeCard(comic: local, progress: progressManager.getProgress(for: local.id))
                        }
                        .buttonStyle(.plain)
                        .explainsIf(index == 0, "Open a comic",
                                    "Tap a comic here to open it and start reading.",
                                    id: "collection.firstComic")
                    } else {
                        // Missing → download in place (flips to Open when done).
                        StoreComicCard(
                            comic: ep,
                            onOpenComic: nil,
                            compact: true,
                            episodeLabel: "Ep. \(ep.episodeNumber ?? index + 1)"
                        )
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.comigoInk, lineWidth: 2))
                    }
                }
            }
            .padding(.horizontal)
        } else if !downloadedEpisodes.isEmpty {
            // Catalog not loaded yet — show what's downloaded, open-only. If the
            // catalog is still loading, hint that more episodes may appear.
            LazyVStack(spacing: 12) {
                ForEach(Array(downloadedEpisodes.enumerated()), id: \.element.id) { index, comic in
                    NavigationLink(destination: ComicDetailView(comic: comic)) {
                        EpisodeCard(comic: comic, progress: progressManager.getProgress(for: comic.id))
                    }
                    .buttonStyle(.plain)
                    .explainsIf(index == 0, "Open a comic",
                                "Tap a comic here to open it and start reading.",
                                id: "collection.firstComic")
                }
                if storeService.isLoadingCatalog {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading episodes…").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
        }
    }
}

// MARK: - Episode Card (downloaded episode — name above a larger image)
struct EpisodeCard: View {
    let comic: Comic
    let progress: ReadingProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(comic.episodeNumber ?? 0)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(comic.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)

                    if let titleEn = comic.titleEn, !titleEn.isEmpty {
                        Text(titleEn)
                            .font(.subheadline)
                            .fontWeight(.regular)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .top, spacing: 16) {
                ComicImage(imageName: comic.coverImage, comicId: comic.id)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Text(comic.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    if progress != nil {
                        Label("In Progress", systemImage: "book.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.comigoInk, lineWidth: 2))
    }
}
