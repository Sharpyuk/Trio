import AVFoundation
import Foundation

@MainActor final class ExerciseAnnouncementManager: NSObject, AVSpeechSynthesizerDelegate {
    private let storage: FileStorage
    private let synthesizer = AVSpeechSynthesizer()
    private var timer: Timer?
    private var intervalMinutes: Int?

    init(storage: FileStorage) {
        self.storage = storage
        super.init()
        synthesizer.delegate = self
    }

    func start(intervalMinutes: Int) {
        let clamped = max(2, min(5, intervalMinutes))
        guard timer == nil || self.intervalMinutes != clamped else { return }
        stop()
        self.intervalMinutes = clamped
        announceLatestGlucose()
        timer = Timer.scheduledTimer(withTimeInterval: Double(clamped) * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.announceLatestGlucose() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        intervalMinutes = nil
        synthesizer.stopSpeaking(at: .immediate)
        deactivateAudioSession()
    }

    private func announceLatestGlucose() {
        guard let glucose = storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self)?.first,
              let value = glucose.glucose ?? glucose.sgv
        else { return }
        let trend = glucose.direction.map(spokenTrend) ?? "trend unavailable"
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
            synthesizer.speak(AVSpeechUtterance(string: "Glucose \(value), \(trend)"))
        } catch {
            debug(.default, "Exercise glucose announcement failed: \(error)")
        }
    }

    private func spokenTrend(_ direction: BloodGlucose.Direction) -> String {
        switch direction {
        case .doubleUp,
             .tripleUp: "rising rapidly"
        case .fortyFiveUp,
             .singleUp: "rising"
        case .flat: "steady"
        case .fortyFiveDown,
             .singleDown: "falling"
        case .doubleDown,
             .tripleDown: "falling rapidly"
        default: "trend unavailable"
        }
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        deactivateAudioSession()
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        deactivateAudioSession()
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
