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
        VStack(alignment: .leading, spacing: 12) {
            // Title above the image, full width so long names never break mid-word.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(comic.episodeNumber ?? 0)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text(comic.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .top, spacing: 16) {
                // Cover Image (a little larger)
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
    }
}
