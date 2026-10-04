import AVFAudio
import Combine
import CoreData
import Foundation
import Swinject
import UIKit

struct ExerciseAnnouncementPlan: Equatable, Sendable {
    let sessionID: UUID
    let phaseID: UUID
    let interval: TimeInterval

    init?(state: ExerciseModeState) {
        guard case let .active(active) = state,
              active.phase == .exercise,
              active.configuration.announcementEnabled
        else { return nil }

        sessionID = active.sessionID
        phaseID = active.phaseID
        interval = max(
            60,
            NSDecimalNumber(decimal: active.configuration.announcementIntervalMinutes).doubleValue * 60
        )
    }
}

@MainActor protocol ExerciseAnnouncementCoordinating: AnyObject {
    func reconcile(state: ExerciseModeState)
}

@MainActor final class ExerciseGlucoseAnnouncementService: NSObject, ExerciseAnnouncementCoordinating {
    private struct Reading: Sendable {
        let glucose: Int
        let date: Date
        let direction: BloodGlucose.Direction
    }

    private let manager: ExerciseModeManager
    private let glucoseStorage: GlucoseStorage
    private let settingsManager: SettingsManager
    private let synthesizer: AVSpeechSynthesizer
    private let makeContext: @Sendable() -> NSManagedObjectContext
    private var timer: AnyCancellable?
    private var glucoseUpdates: AnyCancellable?
    private var foregroundObserver: AnyCancellable?
    private var plan: ExerciseAnnouncementPlan?
    private var lastAnnouncementDate: Date?

    init(
        resolver: Resolver,
        contextProvider: (@Sendable() -> NSManagedObjectContext)? = nil,
        synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer(),
        observeLifecycle: Bool = true
    ) {
        manager = resolver.resolve(ExerciseModeManager.self)!
        glucoseStorage = resolver.resolve(GlucoseStorage.self)!
        settingsManager = resolver.resolve(SettingsManager.self)!
        self.synthesizer = synthesizer
        makeContext = contextProvider ?? { CoreDataStack.shared.newTaskContext() }
        super.init()
        synthesizer.delegate = self

        glucoseUpdates = glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.plan != nil else { return }
                Task { @MainActor in await self.announceIfDue() }
            }

        if observeLifecycle {
            foregroundObserver = Foundation.NotificationCenter.default
                .publisher(for: UIApplication.didBecomeActiveNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    Task { @MainActor in await self?.reconcilePersistedState() }
                }
        }

        Task { await reconcilePersistedState() }
    }

    func reconcile(state: ExerciseModeState) {
        let nextPlan = ExerciseAnnouncementPlan(state: state)
        guard nextPlan != plan else {
            if nextPlan != nil { Task { await announceIfDue() } }
            return
        }

        stopSchedulerAndSpeech()
        plan = nextPlan
        lastAnnouncementDate = nil
        guard nextPlan != nil else { return }

        timer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in await self?.reconcilePersistedState() }
            }
        Task { await announceIfDue() }
    }

    private func reconcilePersistedState() async {
        do {
            reconcile(state: try await manager.reconcile(at: Date()))
        } catch {
            reconcile(state: (try? await manager.currentState()) ?? .inactive)
            debug(.default, "Exercise announcement reconciliation failed: \(error.localizedDescription)")
        }
    }

    private func announceIfDue(now: Date = Date()) async {
        guard let plan else { return }
        if let lastAnnouncementDate, now.timeIntervalSince(lastAnnouncementDate) < plan.interval { return }
        guard !synthesizer.isSpeaking,
              let reading = await latestReading(),
              glucoseStorage.isGlucoseDataFresh(reading.date),
              reading.glucose >= 39
        else { return }

        let glucoseText = reading.glucose.formatted(for: settingsManager.settings.units)
        let utterance = AVSpeechUtterance(string: "Glucose \(glucoseText), \(spokenTrend(reading.direction)).")
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try audio.setActive(true)
            synthesizer.speak(utterance)
            lastAnnouncementDate = now
        } catch {
            deactivateAudioSession()
            debug(.default, "Exercise glucose announcement audio failed: \(error.localizedDescription)")
        }
    }

    private func latestReading() async -> Reading? {
        let context = makeContext()
        context.name = "exerciseGlucoseAnnouncement.latestReading"
        return await context.perform {
            let request: NSFetchRequest<GlucoseStored> = GlucoseStored.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: false)]
            request.fetchLimit = 1
            guard let stored = try? context.fetch(request).first,
                  let date = stored.date,
                  let direction = BloodGlucose.Direction(from: stored.direction ?? ""),
                  direction != .none,
                  direction != .notComputable,
                  direction != .rateOutOfRange
            else { return nil }
            return Reading(glucose: Int(stored.glucose), date: date, direction: direction)
        }
    }

    private func spokenTrend(_ direction: BloodGlucose.Direction) -> String {
        switch direction {
        case .doubleUp,
             .tripleUp: return "rising fast"
        case .singleUp: return "rising"
        case .fortyFiveUp: return "rising slowly"
        case .flat: return "steady"
        case .fortyFiveDown: return "falling slowly"
        case .singleDown: return "falling"
        case .doubleDown,
             .tripleDown: return "falling fast"
        case .none,
             .notComputable,
             .rateOutOfRange: return "trend unavailable"
        }
    }

    private func stopSchedulerAndSpeech() {
        timer?.cancel()
        timer = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        deactivateAudioSession()
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension ExerciseGlucoseAnnouncementService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.deactivateAudioSession() }
    }

    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.deactivateAudioSession() }
    }
}
