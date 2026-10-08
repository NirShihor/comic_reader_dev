import Foundation
import Combine
import Network

// What the reader watches while a comic is still arriving. A progressive
// download tells it each file that has landed (after the atomic rename), and
// the reader tells it which page is on screen and which file it's waiting
// for; those go to the comic's downloader. Views observe `landed` /
// `generation` and re-check the disk when something arrives — a missing
// file is "not here yet", never a failure.
//
// Nothing here reads the disk and nothing decides what the user may open:
// LocalComicStorage still owns that (a partial folder is not a comic).
@MainActor
final class ComicAssetAvailability: ObservableObject {
    static let shared = ComicAssetAvailability()

    struct Landed: Equatable, Hashable {
        let comicId: String
        let entryName: String
    }

    /// What a comic's running downloader accepts from the reader.
    struct DownloadHandle {
        let focus: @Sendable (Int) -> Void
        let request: @Sendable ([String]) -> Void
    }

    /// Files that landed since the last publish (batched, see `didLand`).
    @Published private(set) var landed: [Landed] = []
    /// Bumped per comic each time files land — views that only need "something
    /// arrived for my comic" watch this.
    @Published private(set) var generation: [String: Int] = [:]
    /// False while the device has no route to the network — the reader shows
    /// "waiting for connection" instead of a plain spinner.
    @Published private(set) var isNetworkReachable = true

    private var handles: [String: DownloadHandle] = [:]
    private var aliases: [String: String] = [:]   // comic.json id → folder id, when they differ
    private var batch: [Landed] = []
    private var flush: Task<Void, Never>?
    private var monitor: NWPathMonitor?
    /// Called when the network comes back after being away — the store resumes
    /// stalled downloads.
    var onNetworkReturned: (() -> Void)?

    /// How long landed files are batched before views hear about them.
    static let batchInterval: TimeInterval = 0.1

    // MARK: Downloads

    /// A progressive download of `comicId` is running and takes requests.
    func register(_ comicId: String, handle: DownloadHandle) { handles[comicId] = handle }
    func unregister(_ comicId: String) {
        handles[comicId] = nil
        aliases = aliases.filter { $0.value != comicId }
    }
    /// The comic's own id (from comic.json) when it differs from the folder id.
    func alias(_ comicJsonId: String, to folderId: String) {
        if comicJsonId != folderId { aliases[comicJsonId] = folderId }
    }
    /// Whether a download of this comic is under way (so a missing file is on its way).
    func isDownloading(_ comicId: String) -> Bool { handle(for: comicId) != nil }

    private func handle(for comicId: String) -> DownloadHandle? {
        handles[comicId] ?? aliases[comicId].flatMap { handles[$0] }
    }

    /// From the downloader, once a file is in place under its final name.
    func didLand(comicId: String, entryName: String) {
        batch.append(Landed(comicId: comicId, entryName: entryName))
        if flush == nil {
            flush = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.batchInterval * 1_000_000_000))
                self?.publishBatch()
            }
        }
    }

    private func publishBatch() {
        flush = nil
        guard !batch.isEmpty else { return }
        let items = batch
        batch = []
        for id in Set(items.map(\.comicId)) { generation[id, default: 0] += 1 }
        landed = items
    }

    // MARK: From the reader

    /// The reader is looking at page `index` (0 = cover) of this comic.
    func reader(_ comicId: String, isOnPage index: Int) {
        handle(for: comicId)?.focus(index)
    }

    /// The reader needs these bundle entries now (e.g. a tapped sentence's audio).
    func request(_ comicId: String, entries: [String]) {
        handle(for: comicId)?.request(entries)
    }

    func request(image name: String, comicId: String) {
        request(comicId, entries: ComicAssetPlan.imageEntryNames(name))
    }

    func request(audio name: String, comicId: String) {
        request(comicId, entries: [ComicAssetPlan.audioEntryName(name)])
    }

    /// Whether a landed batch includes this comic's image (either extension).
    static func includes(image name: String, comicId: String, in landed: [Landed]) -> Bool {
        let names = Set(ComicAssetPlan.imageEntryNames(name))
        return landed.contains { $0.comicId == comicId && names.contains($0.entryName) }
    }

    static func includes(audio name: String, comicId: String, in landed: [Landed]) -> Bool {
        let entry = ComicAssetPlan.audioEntryName(name)
        return landed.contains { $0.comicId == comicId && $0.entryName == entry }
    }

    // MARK: Network

    /// Watch the network (production); tests set reachability directly.
    func startMonitoringNetwork() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.setNetworkReachable(path.status == .satisfied) }
        }
        m.start(queue: DispatchQueue(label: "ComicAssetAvailability.network"))
        monitor = m
    }

    func setNetworkReachable(_ reachable: Bool) {
        let returned = reachable && !isNetworkReachable
        isNetworkReachable = reachable
        if returned { onNetworkReturned?() }
    }
}
