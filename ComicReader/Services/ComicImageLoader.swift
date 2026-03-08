import SwiftUI
import UIKit

/// Loads images from comic folders (bundled or downloaded)
class ComicImageLoader {
    static let shared = ComicImageLoader()

    private let fileManager = FileManager.default
    private var imageCache = NSCache<NSString, UIImage>()

    init() {
        imageCache.countLimit = 50 // Cache up to 50 images
    }

    /// Load an image for a comic
    /// - Parameters:
    ///   - imageName: The image filename without extension (e.g., "alien_cover")
    ///   - comicId: The comic ID to locate the correct folder
    /// - Returns: The loaded UIImage or nil if not found
    func loadImage(named imageName: String, forComic comicId: String) -> UIImage? {
        let cacheKey = "\(comicId)/\(imageName)" as NSString

        // Check cache first
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        // Try loading from various locations
        var image: UIImage?

        // 1. Try BundledComics folder (for bundled sample comics)
        if let bundledURL = Bundle.main.url(forResource: "BundledComics", withExtension: nil) {
            let imagePath = bundledURL
                .appendingPathComponent(comicId.replacingOccurrences(of: "comic-", with: ""))
                .appendingPathComponent("images")
                .appendingPathComponent("\(imageName).png")

            if fileManager.fileExists(atPath: imagePath.path) {
                image = UIImage(contentsOfFile: imagePath.path)
            }
        }

        // 2. Try Documents/Comics folder (for downloaded comics)
        if image == nil {
            let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let downloadedPath = documents
                .appendingPathComponent("Comics")
                .appendingPathComponent(comicId)
                .appendingPathComponent("images")
                .appendingPathComponent("\(imageName).png")

            if fileManager.fileExists(atPath: downloadedPath.path) {
                image = UIImage(contentsOfFile: downloadedPath.path)
            }
        }

        // 3. Fallback to asset catalog (for backwards compatibility)
        if image == nil {
            image = UIImage(named: imageName)
        }

        // Cache the result
        if let image = image {
            imageCache.setObject(image, forKey: cacheKey)
        }

        return image
    }

    /// Clear the image cache
    func clearCache() {
        imageCache.removeAllObjects()
    }
}

// MARK: - SwiftUI View Extension
extension Image {
    /// Initialize an Image from a comic's image folder
    /// - Parameters:
    ///   - name: The image filename without extension
    ///   - comicId: The comic ID
    init(comicImage name: String, comicId: String) {
        if let uiImage = ComicImageLoader.shared.loadImage(named: name, forComic: comicId) {
            self.init(uiImage: uiImage)
        } else {
            // Fallback to a placeholder
            self.init(systemName: "photo")
        }
    }
}

// MARK: - SwiftUI View for async loading
struct ComicImage: View {
    let imageName: String
    let comicId: String

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage = uiImage {
                Image(uiImage: uiImage)
                    .resizable()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        ProgressView()
                    )
            }
        }
        .task(id: imageName) {
            // This runs when view appears AND when imageName changes
            // It also cancels the previous task automatically
            uiImage = nil
            let image = await loadImageAsync(named: imageName, forComic: comicId)
            // Only update if this task wasn't cancelled
            if !Task.isCancelled {
                uiImage = image
            }
        }
    }

    private func loadImageAsync(named name: String, forComic comicId: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = ComicImageLoader.shared.loadImage(named: name, forComic: comicId)
                continuation.resume(returning: image)
            }
        }
    }
}
