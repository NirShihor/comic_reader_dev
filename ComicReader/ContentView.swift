import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .library
    @State private var comicToOpen: Comic?
    @State private var libraryNavigationPath = NavigationPath()

    enum Tab {
        case library
        case store
        case vocabulary
        case settings
    }

    var body: some View {
        tabs
            // The Store's "Open in Library" presents the comic full-screen in
            // its own NavigationStack instead of pushing onto the Library
            // tab's stack. Programmatic pushes onto an off-screen stack
            // corrupt its destination table on recent iOS (blank/triangle
            // destinations, page taps popping to root), especially when the
            // main thread hangs during the tab switch on large libraries.
            .fullScreenCover(item: $comicToOpen) { comic in
                NavigationStack {
                    ComicDetailView(comic: comic)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    comicToOpen = nil
                                } label: {
                                    Image(systemName: "xmark")
                                }
                            }
                        }
                }
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--auto-open-test") {
                    runAutoOpenTest()
                }
                #endif
            }
    }

    #if DEBUG
    // Simulator-only reproduction of the Store -> "Open in Library" flow.
    private func runAutoOpenTest() {
        Task { @MainActor in
            print("[AutoTest] starting")
            let store = ComicStoreService.shared
            let storage = LocalComicStorage.shared
            if storage.downloadedComics.isEmpty {
                await store.fetchCatalog()
                print("[AutoTest] catalog: \(store.catalog.count) comics, error: \(store.catalogError ?? "none")")
                guard let smallest = store.catalog.min(by: { $0.fileSizeMB < $1.fileSizeMB }) else {
                    print("[AutoTest] FAIL: empty catalog"); return
                }
                print("[AutoTest] downloading \(smallest.id) (\(smallest.fileSizeMB) MB)")
                await store.downloadComic(smallest)
                print("[AutoTest] download finished, downloadedComics: \(storage.downloadedComics.count)")
            }
            guard let comic = storage.downloadedComics.first else {
                print("[AutoTest] FAIL: nothing downloaded"); return
            }
            // Two full open/close cycles — reproduces the repeat-open case.
            for cycle in 1...2 {
                selectedTab = .store
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                print("[AutoTest] CYCLE \(cycle): simulating Open in Library for \(comic.id)")
                selectedTab = .library
                comicToOpen = comic
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                print("[AutoTest] CYCLE \(cycle) settled: cover \(comicToOpen == nil ? "CLOSED (FAIL)" : "presented")")
                if cycle == 1 {
                    comicToOpen = nil
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            print("[AutoTest] complete")
        }
    }
    #endif

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $libraryNavigationPath) {
                LibraryView()
                    .navigationDestination(for: Comic.self) { comic in
                        ComicDetailView(comic: comic)
                    }
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }
            .tag(Tab.library)

            NavigationStack {
                StoreView(onOpenComic: { comic in
                    // Presented as a fullScreenCover by ContentView; the
                    // Library tab is selected behind it so dismissing the
                    // cover lands the user in their library.
                    selectedTab = .library
                    comicToOpen = comic
                })
            }
            .tabItem {
                Label("Store", systemImage: "bag.fill")
            }
            .tag(Tab.store)

            NavigationStack {
                VocabularyView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                selectedTab = .library
                            }
                        }
                    }
            }
            .tabItem {
                Label("Vocabulary", systemImage: "bookmark.fill")
            }
            .tag(Tab.vocabulary)

            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                selectedTab = .library
                            }
                        }
                    }
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(Tab.settings)
        }
        .tint(.primary)
    }
}

#Preview {
    ContentView()
        .environmentObject(SettingsManager())
        .environmentObject(ReadingProgressManager())
}
