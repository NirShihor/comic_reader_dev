import Foundation
import SwiftUI

@MainActor
class ReadingProgressManager: ObservableObject {
    @Published private(set) var progressMap: [String: ReadingProgress] = [:]

    private let storageKey = "readingProgress"

    init() {
        loadProgress()
    }

    func getProgress(for comicId: String) -> ReadingProgress? {
        progressMap[comicId]
    }

    func saveProgress(comicId: String, pageNumber: Int, panelNumber: Int) {
        let progress = ReadingProgress(
            comicId: comicId,
            pageNumber: pageNumber,
            panelNumber: panelNumber,
            updatedAt: Date()
        )
        progressMap[comicId] = progress
        persistProgress()
    }

    func clearProgress(for comicId: String) {
        progressMap.removeValue(forKey: comicId)
        persistProgress()
    }

    private func loadProgress() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: ReadingProgress].self, from: data) else {
            return
        }
        progressMap = decoded
    }

    private func persistProgress() {
        guard let data = try? JSONEncoder().encode(progressMap) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
