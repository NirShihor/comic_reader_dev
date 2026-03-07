import SwiftUI

@main
struct ComicReaderApp: App {
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var progressManager = ReadingProgressManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settingsManager)
                .environmentObject(progressManager)
        }
    }
}
