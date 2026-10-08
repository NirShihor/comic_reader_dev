import Foundation

// Which files in a comic's bundle belong to which page, built from the
// comic's own data (comic.json) — never from its slug: one comic's audio is
// still named after its old title, and practice pages (p1001…) sort between
// p1 and p2 in the archive. The progressive downloader uses the plan to
// fetch what the reader is looking at first; the levels are plain numbers so
// nothing here knows about views.
struct ComicAssetPlan: Equatable {
    /// One story page's files, by how soon the reader needs them.
    struct PageAssets: Equatable {
        let pageNumber: Int
        /// The baked page itself — the minimum to show the page.
        let display: [String]
        /// Spanish sentence audio — the first thing a reader taps.
        let audio: [String]
        /// Everything else the page's interactions use: the blank bakes (bubble
        /// highlight, practice), panel art, bubble/hotspot images, translation,
        /// word and hotspot audio.
        let interaction: [String]

        var all: [String] { display + audio + interaction }
    }

    /// Story pages in reading order (the cover first).
    let pages: [PageAssets]
    /// Comic-wide files (covers for the detail/library screens).
    let comicWide: [String]
    /// Practice pages' files — after everything else.
    let practice: [String]

    /// Priorities inside one page sit within this band; pages are a band apart.
    static let pageBand = 1000
    static let displayLevel = 900, audioLevel = 800, interactionLevel = 700
    static let firstPageBase = 500_000
    static let comicWideLevel = 200, practiceLevel = 100

    /// Only files that are actually in the bundle (`entryNames`) are planned;
    /// a reference comic.json makes to a file that isn't there is ignored.
    init(comic: Comic, entryNames: Set<String>) {
        func image(_ name: String?) -> [String] {
            guard let name, !name.isEmpty else { return [] }
            return Self.imageEntryNames(name).filter(entryNames.contains)
        }
        func audio(_ name: String?) -> [String] {
            guard let name, !name.isEmpty else { return [] }
            let entry = Self.audioEntryName(name)
            return entryNames.contains(entry) ? [entry] : []
        }
        func wordAudio(_ w: Word) -> [String] {
            var names: [String] = []
            names += audio(w.wordAudioUrl)
            names += audio(w.baseFormAudioUrl)
            names += audio(w.audioUrl)
            for form in w.forms ?? [] { names += audio(form.audioUrl) }
            return names
        }
        func pageAssets(_ page: Page, seen: inout Set<String>) -> PageAssets {
            // A file used by two pages is planned for the first one that uses it.
            func fresh(_ names: [String]) -> [String] {
                names.filter { seen.insert($0).inserted }
            }
            let display = fresh(image(page.masterImage))
            var sentenceAudio: [String] = []
            var interaction: [String] = image(page.emptyBubblesImage) + image(page.noTextImage)
            for panel in page.panels.sorted(by: { $0.panelOrder < $1.panelOrder }) {
                interaction += image(panel.artworkImage) + image(panel.noTextImage)
                for bubble in panel.bubbles {
                    interaction += image(bubble.imageUrl)
                    for s in bubble.sentences {
                        sentenceAudio += audio(s.audioUrl)
                        interaction += audio(s.translationAudioUrl)
                        for alt in s.alternativeAudioUrls ?? [] { interaction += audio(alt) }
                        for w in s.words { interaction += wordAudio(w) }
                    }
                }
            }
            for hotspot in page.hotspots ?? [] {
                for slide in hotspot.slides {
                    interaction += image(slide.imageUrl)
                    interaction += audio(slide.audioUrl)
                    interaction += audio(slide.translationAudioUrl)
                    for w in slide.words { interaction += wordAudio(w) }
                }
            }
            return PageAssets(pageNumber: page.pageNumber, display: display,
                              audio: fresh(sentenceAudio), interaction: fresh(interaction))
        }

        var seen: Set<String> = ["comic.json"]
        pages = comic.pages.sorted { $0.pageNumber < $1.pageNumber }.map { pageAssets($0, seen: &seen) }
        comicWide = (image(comic.coverImage) + image(comic.coverLandscape) + image(comic.collectionCoverImage))
            .filter { seen.insert($0).inserted }
        practice = (comic.practicePages ?? []).sorted { $0.pageNumber < $1.pageNumber }
            .map { pageAssets($0, seen: &seen) }.flatMap(\.all)
    }

    /// The bundle entry names a page image may have (the loader tries both).
    static func imageEntryNames(_ imageName: String) -> [String] {
        ["images/\(imageName).jpg", "images/\(imageName).png"]
    }

    /// The bundle entry name of an audio clip ("p1_s1_b1" or "words/el").
    static func audioEntryName(_ audioName: String) -> String {
        "audio/\(audioName).mp3"
    }

    /// Entry name → priority with the reader on page `index` (0 = cover):
    /// that page first (its display image, then sentence audio, then the
    /// rest), then the following pages in order, then the preceding ones,
    /// then the covers, then practice pages. Unlisted files get nothing (0).
    func priorities(focusedOn index: Int) -> [String: Int] {
        var out: [String: Int] = [:]
        let focus = min(max(index, 0), max(pages.count - 1, 0))
        for (i, page) in pages.enumerated() {
            // Rank: the page itself, then forward by distance, then backward
            // (previous page after the next two).
            let rank = i >= focus ? (i - focus) : (focus - i) + 2
            let base = Self.firstPageBase - rank * Self.pageBand
            for n in page.display { out[n] = base + Self.displayLevel }
            for n in page.audio { out[n] = base + Self.audioLevel }
            for n in page.interaction { out[n] = base + Self.interactionLevel }
        }
        for n in comicWide { out[n] = Self.comicWideLevel }
        for n in practice { out[n] = Self.practiceLevel }
        return out
    }
}
