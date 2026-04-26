import Foundation
import SwiftUI

@MainActor
class SettingsManager: ObservableObject {
    @AppStorage("speakingPracticeMode") var speakingPracticeMode = false
    @AppStorage("listeningPracticeMode") var listeningPracticeMode = false
    @AppStorage("autoPlayAudio") var autoPlayAudio = false
    @AppStorage("hapticFeedback") var hapticFeedback = true
    @AppStorage("playbackSpeed") var playbackSpeed = 1.0
}
