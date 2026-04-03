import SwiftUI

struct CollectionDetailView: View {
    let collection: ComicCollection
    @EnvironmentObject var progressManager: ReadingProgressManager

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection

                LazyVStack(spacing: 12) {
                    ForEach(collection.comics) { comic in
                        NavigationLink(destination: ComicDetailView(comic: comic)) {
                            EpisodeCard(comic: comic, progress: progressManager.getProgress(for: comic.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            ComicImage(imageName: collection.coverImage, comicId: collection.coverComicId)
                .aspectRatio(contentMode: .fit)
                .frame(width: 118)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(collection.title)
                    .font(.title2)
                    .fontWeight(.bold)

                Text("\(collection.episodeCount) episodes")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Text(collection.level.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(levelColor.opacity(0.2))
                    .foregroundStyle(levelColor)
                    .clipShape(Capsule())
                    .fixedSize()
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var levelColor: Color {
        switch collection.level {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        }
    }
}

// MARK: - Episode Card
struct EpisodeCard: View {
    let comic: Comic
    let progress: ReadingProgress?

    var body: some View {
        HStack(spacing: 16) {
            // Episode number
            Text("\(comic.episodeNumber ?? 0)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            // Cover Image
            ComicImage(imageName: comic.coverImage, comicId: comic.id)
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(comic.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Text(comic.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if progress != nil {
                    Label("In Progress", systemImage: "book.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
