import SwiftUI
import UIKit

/// Loads images from comic folders (bundled or downloaded)
class ComicImageLoader {
    static let shared = ComicImageLoader()

    private let fileManager = FileManager.default
    private var imageCache = NSCache<NSString, UIImage>()
    /// Where downloaded comics live (Documents/Comics; tests point elsewhere).
    let comicsDirectory: URL

    init(comicsDirectory: URL = LocalComicStorage.defaultComicsDirectory) {
        self.comicsDirectory = comicsDirectory
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
        // Downloaded comics take priority over bundled ones (user may re-download updated versions)
        // Try .jpg first (optimized exports), then .png (legacy/bundled)
        var image: UIImage?
        let extensions = ["jpg", "png"]

        // 1. Try Documents/Comics folder (downloaded comics — checked first for updates)
        let downloadedBase = comicsDirectory
            .appendingPathComponent(comicId)
            .appendingPathComponent("images")

        for ext in extensions {
            let path = downloadedBase.appendingPathComponent("\(imageName).\(ext)")
            if fileManager.fileExists(atPath: path.path) {
                image = UIImage(contentsOfFile: path.path)
                break
            }
        }

        // 2. Fallback to BundledComics folder (bundled sample comics)
        if image == nil {
            if let bundledURL = Bundle.main.url(forResource: "BundledComics", withExtension: nil) {
                let bundledBase = bundledURL
                    .appendingPathComponent(comicId.replacingOccurrences(of: "comic-", with: ""))
                    .appendingPathComponent("images")

                for ext in extensions {
                    let path = bundledBase.appendingPathComponent("\(imageName).\(ext)")
                    if fileManager.fileExists(atPath: path.path) {
                        image = UIImage(contentsOfFile: path.path)
                        break
                    }
                }
            }
        }

        // 3. Fallback to asset catalog (for backwards compatibility)
        if image == nil {
            image = UIImage(named: imageName)
        }

        // Force the JPEG/PNG decode NOW, on whatever thread we're on (the
        // ComicImage path calls this on a background queue). Without this,
        // UIImage(contentsOfFile:) defers decoding to first RENDER — on the
        // main thread — so a screenful of fresh covers froze the UI and
        // dropped taps right after the Library appeared.
        if let raw = image, let prepared = raw.preparingForDisplay() {
            image = prepared
        }

        // Cache the result
        if let image = image {
            imageCache.setObject(image, forKey: cacheKey)
        }

        return image
    }

    /// Clear the entire image cache
    func clearCache() {
        imageCache.removeAllObjects()
    }

    /// Clear cached images for a specific comic
    func clearCache(forComic comicId: String) {
        // NSCache doesn't support key enumeration, so we clear everything.
        // This is safe — images will be reloaded from disk on next access.
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

// MARK: - Retrying remote image
/// AsyncImage that RETRIES failed loads. AsyncImage keeps its .failure phase
/// forever — on the Library a burst of simultaneous thumbnail fetches can
/// transiently fail (cold server, network blip) and those covers then stay
/// blank placeholders until the app relaunches. This wrapper re-attempts with
/// backoff (and again when the view reappears), up to `maxRetries`.
struct RetryingAsyncImage<Content: View>: View {
    let url: URL?
    var maxRetries: Int = 4
    @ViewBuilder var content: (AsyncImagePhase) -> Content

    @State private var attempt = 0

    var body: some View {
        AsyncImage(url: url) { phase in
            content(phase)
                .onAppear {
                    if case .failure = phase, attempt < maxRetries {
                        let delay = 1.5 * Double(attempt + 1)
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            attempt += 1   // new identity → AsyncImage refetches
                        }
                    }
                }
        }
        .id("\(url?.absoluteString ?? "")#\(attempt)")
    }
}

// MARK: - Loading placeholder
/// What stands in for an asset that hasn't arrived yet — a light grey block
/// with a spinner, or a "waiting for connection" note when the device is
/// offline. Minimal by design; it's replaced the moment the file lands.
struct AssetLoadingPlaceholder: View {
    var offline = false

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay {
                if offline {
                    VStack(spacing: 6) {
                        Image(systemName: "wifi.slash").foregroundStyle(.secondary)
                        Text("Waiting for connection…").font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                }
            }
    }
}

// MARK: - SwiftUI View for async loading
/// A comic's image from its folder. While the file hasn't arrived (the comic
/// is still downloading) it shows a placeholder, asks the download for that
/// file, and swaps the real image in by itself when it lands.
struct ComicImage: View {
    let imageName: String
    let comicId: String
    /// Catalog thumbnail path (e.g. "/api/reader/cover-thumbnail/<id>") shown when
    /// the local image isn't on device yet — so covers appear before download.
    var remoteFallbackPath: String? = nil
    /// Ask a running download for the file when it's missing. Off for views
    /// that show many images at once (page thumbnails) — they'd push every
    /// page ahead of the one being read.
    var requestsWhenMissing = true

    @State private var uiImage: UIImage?
    @State private var localMissing = false
    @State private var reloads = 0
    @ObservedObject private var availability = ComicAssetAvailability.shared

    var body: some View {
        Group {
            if let uiImage = uiImage {
                Image(uiImage: uiImage)
                    .resizable()
            } else if localMissing,
                      let path = remoteFallbackPath, !path.isEmpty,
                      let url = URL(string: "\(Secrets.serverBaseURL)\(path)") {
                RetryingAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                    case .failure:
                        Rectangle().fill(Color.gray.opacity(0.2))
                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    default:
                        Rectangle().fill(Color.gray.opacity(0.2)).overlay(ProgressView())
                    }
                }
            } else {
                AssetLoadingPlaceholder(offline: localMissing && !availability.isNetworkReachable)
            }
        }
        .task(id: "\(imageName)#\(reloads)") {
            // This runs when view appears AND when imageName changes
            // It also cancels the previous task automatically
            uiImage = nil
            localMissing = false
            let image = await loadImageAsync(named: imageName, forComic: comicId)
            // Only update if this task wasn't cancelled
            if !Task.isCancelled {
                uiImage = image
                localMissing = (image == nil)
                // Not here yet: ask for it; the landing below reloads.
                if image == nil, requestsWhenMissing { availability.request(image: imageName, comicId: comicId) }
            }
        }
        .onReceive(availability.$landed) { landed in
            if uiImage == nil, ComicAssetAvailability.includes(image: imageName, comicId: comicId, in: landed) {
                reloads += 1
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
