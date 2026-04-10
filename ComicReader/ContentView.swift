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
                    libraryNavigationPath = NavigationPath()
                    selectedTab = .library
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        libraryNavigationPath.append(comic)
                    }
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
