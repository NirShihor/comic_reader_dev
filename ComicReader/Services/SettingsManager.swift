import Foundation
import SwiftUI

@MainActor
class SettingsManager: ObservableObject {
    // Single user preference behind the "Speaking exercises" toggle (Comic Detail
    // Practice section). When off, the on-screen read-and-speak mode is hidden and
    // off-screen practice collapses to listen-only.
    @AppStorage("speakingEnabled") var speakingEnabled = true

    // Transient render flags set when a specific practice mode launches.
    @AppStorage("speakingPracticeMode") var speakingPracticeMode = false
    @AppStorage("listeningPracticeMode") var listeningPracticeMode = false
    @AppStorage("autoPlayAudio") var autoPlayAudio = false
    @AppStorage("hapticFeedback") var hapticFeedback = true
    @AppStorage("playbackSpeed") var playbackSpeed = 1.0
}
