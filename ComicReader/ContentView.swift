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

    // Push a comic that was requested from another tab (e.g. the Store's
    // "Open in Library" button). Called from the Library tab's onAppear so
    // the navigation happens only once its NavigationStack is actually live —
    // appending to the path on a timer during the tab-switch transition gets
    // silently dropped by SwiftUI.
    private func openPendingComic() {
        guard let comic = comicToOpen else { return }
        comicToOpen = nil
        // One runloop hop so the append lands after the appearance transaction
        DispatchQueue.main.async {
            libraryNavigationPath.append(comic)
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $libraryNavigationPath) {
                LibraryView()
                    .navigationDestination(for: Comic.self) { comic in
                        ComicDetailView(comic: comic)
                    }
                    .onAppear {
                        openPendingComic()
                    }
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }
            .tag(Tab.library)

            NavigationStack {
                StoreView(onOpenComic: { comic in
                    libraryNavigationPath = NavigationPath()
                    comicToOpen = comic
                    selectedTab = .library
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
