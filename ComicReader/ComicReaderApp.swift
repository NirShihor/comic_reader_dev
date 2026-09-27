import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AnalyticsService.shared.start()
        // Read the StoreKit entitlement at launch so the first events carry it.
        _ = StoreService.shared
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        DownloadHelper.backgroundCompletionHandlers[identifier] = completionHandler
    }
}

@main
struct ComicReaderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var progressManager = ReadingProgressManager()
    @StateObject private var notebookManager = NotebookManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settingsManager)
                .environmentObject(progressManager)
                .environmentObject(notebookManager)
        }
    }
}
