import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var progressManager: ReadingProgressManager
    @StateObject private var localStorage = LocalComicStorage.shared
    @State private var comicToDelete: Comic?
    @State private var collectionToDelete: ComicCollection?

    var body: some View {
        Group {
            if localStorage.isLoading {
                ProgressView("Loading...")
            } else if localStorage.downloadedComics.isEmpty {
                emptyState
            } else {
                comicList
            }
        }
        .navigationTitle("Library")
        .background(Color(.systemGroupedBackground))
        .refreshable {
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
            Label("No Comics Downloaded", systemImage: "books.vertical")
        } description: {
            Text("Visit the Store to browse and download comics.")
        } actions: {
            Text("Tap the Store tab below")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var comicList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Storage info
                storageInfo

                ForEach(localStorage.libraryItems) { item in
                    switch item {
                    case .standalone(let comic):
                        NavigationLink(destination: ComicDetailView(comic: comic)) {
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
                        NavigationLink(destination: CollectionDetailView(collection: collection)) {
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
            }
            .padding()
        }
    }

    private func deleteComic(_ comic: Comic) {
        try? localStorage.deleteComic(comic.id)
        progressManager.clearProgress(for: comic.id)
    }

    private func deleteCollection(_ collection: ComicCollection) {
        for comic in collection.comics {
            try? localStorage.deleteComic(comic.id)
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
                Text(comic.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

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

    var body: some View {
        HStack(spacing: 16) {
            // Cover Image (from first episode)
            ComicImage(imageName: collection.coverImage, comicId: collection.coverComicId)
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 2)
                .overlay(
                    Text("\(collection.episodeCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                        .padding(4),
                    alignment: .topTrailing
                )

            // Info
            VStack(alignment: .leading, spacing: 8) {
                Text(collection.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("\(collection.episodeCount) episodes")
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
