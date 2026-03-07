import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .library

    enum Tab {
        case library
        case store
        case vocabulary
        case settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }
            .tag(Tab.library)

            NavigationStack {
                StoreView()
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
