import SwiftUI

struct StoreView: View {
    @StateObject private var storeService = ComicStoreService.shared
    @State private var searchText = ""
    @State private var selectedLevel: String? = nil

    var filteredComics: [StoreComic] {
        var comics = storeService.catalog

        if !searchText.isEmpty {
            comics = comics.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }

        if let level = selectedLevel {
            comics = comics.filter { $0.level == level }
        }

        return comics
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
            LazyVStack(spacing: 16) {
                if filteredComics.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(filteredComics) { comic in
                        StoreComicCard(comic: comic)
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
    @StateObject private var storeService = ComicStoreService.shared

    var downloadState: DownloadState {
        storeService.downloadState(for: comic.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                // Cover image from server
                AsyncImage(url: URL(string: "\(Secrets.serverBaseURL)\(comic.coverThumbnailUrl)")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(levelColor.opacity(0.2))
                            .frame(width: 80, height: 120)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(levelColor)
                            )
                    default:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(levelColor.opacity(0.1))
                            .frame(width: 80, height: 120)
                            .overlay(ProgressView())
                    }
                }
                .frame(width: 80, height: 120)

                // Info
                VStack(alignment: .leading, spacing: 8) {
                    Text(comic.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let collection = comic.collectionTitle {
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
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
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
                    }
                }
            }

            // File size
            if comic.fileSizeMB > 0 {
                Text("\(String(format: "%.1f", comic.fileSizeMB)) MB")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Download button / status
            downloadButton
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Spacer()

                Button {
                    storeService.deleteDownload(comic.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 10)

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

#Preview {
    NavigationStack {
        StoreView()
    }
}
