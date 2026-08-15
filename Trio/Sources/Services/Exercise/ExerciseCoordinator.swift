import Foundation
import Observation
import Swinject

@MainActor @Observable final class ExerciseCoordinator {
    private(set) var state: ExercisePersistedState
    private let storage: FileStorage
    private let announcer: ExerciseAnnouncementManager
    private let file = "exercise/state.json"

    init(resolver: Resolver) {
        storage = resolver.resolve(FileStorage.self)!
        state = storage.retrieve(file, as: ExercisePersistedState.self) ?? .initial
        announcer = ExerciseAnnouncementManager(storage: storage)
        reconcile(at: Date())
    }

    var activeSession: ExerciseSession? { state.activeSession }
    var presets: [ExercisePreset] { state.presets }
    var history: [ExerciseSession] { state.history.sorted { $0.createdAt > $1.createdAt } }
    var reports: [ExerciseReport] { state.reports.sorted { $0.plannedStart > $1.plannedStart } }

    func reconcile(at now: Date = Date()) {
        guard var session = state.activeSession else {
            announcer.stop()
            return
        }
        let previousSession = session
        ExerciseReconciler.reconcile(&session, at: now)

        // Most reconciliations only verify persisted timestamps. Avoid publishing an
        // equivalent state and rewriting JSON, both of which force unnecessary UI work.
        guard session != previousSession else {
            updateAnnouncements(at: now)
            return
        }

        state.activeSession = session
        archiveTerminalSessionIfNeeded(at: now)
        persist()
        updateAnnouncements(at: now)
    }

    func schedule(preset: ExercisePreset, activeStart: Date, now: Date = Date()) {
        terminateCurrentSession(at: now)
        var session = ExerciseSession(preset: preset, createdAt: now, scheduledExerciseStart: activeStart)
        ExerciseReconciler.reconcile(&session, at: now)
        state.activeSession = session
        persist()
        updateAnnouncements(at: now)
    }

    func startNow(preset: ExercisePreset? = nil, at now: Date = Date()) {
        if state.activeSession == nil {
            schedule(preset: preset ?? state.presets.first ?? ExercisePreset.defaults[0], activeStart: now, now: now)
            return
        }
        mutateSession(at: now) { ExerciseReconciler.startExerciseNow(&$0, at: now) }
    }

    func stopExercise(at now: Date = Date()) {
        mutateSession(at: now) { ExerciseReconciler.stopExercise(&$0, at: now) }
    }

    func endRecovery(at now: Date = Date()) {
        mutateSession(at: now) { ExerciseReconciler.endRecovery(&$0, at: now) }
    }

    func cancel(at now: Date = Date()) {
        mutateSession(at: now) { ExerciseReconciler.cancel(&$0, at: now) }
    }

    func savePreset(_ preset: ExercisePreset) {
        if let index = state.presets.firstIndex(where: { $0.id == preset.id }) {
            state.presets[index] = preset
        } else {
            state.presets.append(preset)
        }
        persist()
    }

    func deletePreset(id: UUID) {
        state.presets.removeAll { $0.id == id }
        persist()
    }

    private func mutateSession(at now: Date, _ mutation: (inout ExerciseSession) -> Void) {
        guard var session = state.activeSession else { return }
        mutation(&session)
        ExerciseReconciler.reconcile(&session, at: now)
        state.activeSession = session
        archiveTerminalSessionIfNeeded(at: now)
        persist()
        updateAnnouncements(at: now)
    }

    private func terminateCurrentSession(at now: Date) {
        guard var current = state.activeSession else { return }
        if current.phase(at: now) == .recovery {
            ExerciseReconciler.endRecovery(&current, at: now)
        } else {
            ExerciseReconciler.cancel(&current, at: now)
        }
        archive(current)
        state.activeSession = nil
        announcer.stop()
    }

    private func archiveTerminalSessionIfNeeded(at now: Date) {
        guard let session = state.activeSession,
              [.completed, .cancelled].contains(session.phase(at: now))
        else { return }
        archive(session)
        state.activeSession = nil
    }

    private func archive(_ session: ExerciseSession) {
        guard !state.history.contains(where: { $0.id == session.id }) else { return }
        state.history.append(session)
        state.reports.append(makeReport(for: session))
    }

    private func makeReport(for session: ExerciseSession) -> ExerciseReport {
        let start = session.actualExerciseStart
        let end = session.actualExerciseEnd
        let glucose = storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self) ?? []
        let readings = glucose.filter { reading in
            guard let start, let end else { return false }
            return reading.dateString >= start && reading.dateString <= end
        }.sorted { $0.dateString < $1.dateString }
        let values = readings.compactMap { $0.glucose ?? $0.sgv }
        let pumpHistory = storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self) ?? []
        let events = pumpHistory.filter { event in
            guard let start, let end else { return false }
            return event.timestamp >= start && event.timestamp <= end
        }
        let boluses = events.filter { $0.type == .bolus || $0.type == .smb }
        let smbDelivered = events.filter { $0.type == .smb || $0.isSMB == true }.compactMap(\.amount).reduce(0, +)
        let bolusDelivered = boluses.compactMap(\.amount).reduce(0, +)
        let temps = events.filter { $0.type == .tempBasal }
        let iob = storage.retrieve(OpenAPS.Monitor.iob, as: [IobResult].self)?.first

        return ExerciseReport(
            sessionID: session.id,
            type: session.preset.name,
            plannedStart: session.scheduledExerciseStart,
            actualStart: start,
            actualEnd: end,
            duration: start.flatMap { start in end.map { $0.timeIntervalSince(start) } },
            bgStart: values.first,
            bgEnd: values.last,
            bgMinimum: values.min(),
            bgMaximum: values.max(),
            iobStart: nil,
            iobEnd: iob?.iob,
            // Pump history provides exact bolus/SMB delivery. Basal delivery is summarized
            // separately because reconstructing volume requires paired duration records.
            insulinDelivered: bolusDelivered,
            smbDelivered: smbDelivered,
            tempBasalSummary: temps
                .isEmpty ? "No temp basal records" :
                "\(temps.count) temp basal changes; rates \(temps.compactMap(\.rate).map(String.init(describing:)).joined(separator: ", ")) U/hr",
            basalPercentage: session.preset.active.basalPercentage,
            insulinStrengthPercentage: session.preset.active.insulinStrengthPercentage,
            target: session.preset.active.target,
            recommendedRecoveryDuration: session.recoveryStart.flatMap { recoveryStart in
                session.recommendedRecoveryEnd.map { $0.timeIntervalSince(recoveryStart) }
            },
            actualRecoveryDuration: session.recoveryStart.flatMap { recoveryStart in
                session.actualRecoveryEnd.map { $0.timeIntervalSince(recoveryStart) }
            },
            announcementsEnabled: session.preset.announcementsEnabled,
            announcementIntervalMinutes: session.preset.announcementIntervalMinutes
        )
    }

    private func persist() {
        storage.save(state, as: file)
    }

    private func updateAnnouncements(at now: Date) {
        guard let session = state.activeSession,
              session.phase(at: now) == .active,
              session.preset.announcementsEnabled
        else {
            announcer.stop()
            return
        }
        announcer.start(intervalMinutes: session.preset.announcementIntervalMinutes)
    }
}
