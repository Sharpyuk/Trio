import Foundation

enum ExercisePhase: String, Codable, CaseIterable {
    case scheduled
    case preExercise
    case active
    case recovery
    case completed
    case cancelled
}

enum ExerciseRecoveryDecay: String, Codable, CaseIterable {
    case linear
}

struct ExercisePhaseSettings: Codable, Equatable {
    var basalPercentage: Decimal
    var smbEnabled: Bool
    var target: Decimal?
    var insulinStrengthPercentage: Decimal

    static let normal = ExercisePhaseSettings(
        basalPercentage: 100,
        smbEnabled: true,
        target: nil,
        insulinStrengthPercentage: 100
    )
}

struct ExerciseRecoverySettings: Codable, Equatable {
    var enabled: Bool
    var initialSensitivityIncreasePercentage: Decimal
    var decay: ExerciseRecoveryDecay
    var target: Decimal?
}

struct ExercisePreset: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var preExerciseDurationMinutes: Int
    var preExercise: ExercisePhaseSettings
    var active: ExercisePhaseSettings
    var recovery: ExerciseRecoverySettings
    var safetyTimeoutMinutes: Int?
    var announcementsEnabled: Bool
    var announcementIntervalMinutes: Int

    static let defaults: [ExercisePreset] = [
        preset("Run", pre: 30, basal: 30, strength: 25),
        preset("Long Run", pre: 45, basal: 20, strength: 25),
        preset("Ultra Run", pre: 60, basal: 10, strength: 0, timeout: nil),
        preset("Walk", pre: 20, basal: 60, strength: 50),
        preset("Hike", pre: 30, basal: 40, strength: 25),
        preset("Cycle", pre: 30, basal: 30, strength: 25),
        preset("Strength", pre: 15, basal: 80, strength: 75),
        preset("Custom", pre: 30, basal: 50, strength: 50)
    ]

    private static func preset(
        _ name: String,
        pre: Int,
        basal: Decimal,
        strength: Decimal,
        timeout: Int? = 360
    ) -> ExercisePreset {
        ExercisePreset(
            id: UUID(),
            name: name,
            preExerciseDurationMinutes: pre,
            preExercise: ExercisePhaseSettings(
                basalPercentage: 0,
                smbEnabled: false,
                target: nil,
                insulinStrengthPercentage: 0
            ),
            active: ExercisePhaseSettings(
                basalPercentage: basal,
                smbEnabled: false,
                target: nil,
                insulinStrengthPercentage: strength
            ),
            recovery: ExerciseRecoverySettings(
                enabled: true,
                initialSensitivityIncreasePercentage: 20,
                decay: .linear,
                target: nil
            ),
            safetyTimeoutMinutes: timeout,
            announcementsEnabled: false,
            announcementIntervalMinutes: 3
        )
    }
}

struct ExerciseSession: Codable, Equatable, Identifiable {
    var id: UUID
    var preset: ExercisePreset
    var createdAt: Date
    var scheduledExerciseStart: Date
    var actualPreExerciseStart: Date?
    var actualExerciseStart: Date?
    var actualExerciseEnd: Date?
    var recoveryStart: Date?
    var recommendedRecoveryEnd: Date?
    var actualRecoveryEnd: Date?
    var completedAt: Date?
    var cancelledAt: Date?

    init(
        id: UUID = UUID(),
        preset: ExercisePreset,
        createdAt: Date = Date(),
        scheduledExerciseStart: Date,
        actualPreExerciseStart: Date? = nil,
        actualExerciseStart: Date? = nil,
        actualExerciseEnd: Date? = nil,
        recoveryStart: Date? = nil,
        recommendedRecoveryEnd: Date? = nil,
        actualRecoveryEnd: Date? = nil,
        completedAt: Date? = nil,
        cancelledAt: Date? = nil
    ) {
        self.id = id
        self.preset = preset
        self.createdAt = createdAt
        self.scheduledExerciseStart = scheduledExerciseStart
        self.actualPreExerciseStart = actualPreExerciseStart
        self.actualExerciseStart = actualExerciseStart
        self.actualExerciseEnd = actualExerciseEnd
        self.recoveryStart = recoveryStart
        self.recommendedRecoveryEnd = recommendedRecoveryEnd
        self.actualRecoveryEnd = actualRecoveryEnd
        self.completedAt = completedAt
        self.cancelledAt = cancelledAt
    }

    var preExerciseStart: Date {
        scheduledExerciseStart.addingTimeInterval(-Double(preset.preExerciseDurationMinutes) * 60)
    }

    func phase(at now: Date) -> ExercisePhase {
        if cancelledAt != nil { return .cancelled }
        if completedAt != nil { return .completed }
        if recoveryStart != nil, actualRecoveryEnd == nil { return .recovery }
        if actualExerciseStart != nil, actualExerciseEnd == nil { return .active }
        if actualPreExerciseStart != nil { return .preExercise }
        return .scheduled
    }

    func settings(at now: Date) -> ExercisePhaseSettings? {
        switch phase(at: now) {
        case .preExercise:
            return preset.preExercise
        case .active:
            return preset.active
        case .recovery:
            let strength = ExerciseRecoveryCalculator.insulinStrengthPercentage(session: self, at: now)
            return ExercisePhaseSettings(
                basalPercentage: 100,
                smbEnabled: true,
                target: preset.recovery.target,
                insulinStrengthPercentage: strength
            )
        default:
            return nil
        }
    }
}

enum ExerciseRecoveryCalculator {
    static func recommendation(forExerciseDuration duration: TimeInterval) -> TimeInterval {
        guard duration >= 10 * 60 else { return 0 }
        let exerciseHours = duration / 3600
        return min(24 * 3600, max(3600, exerciseHours * 3 * 3600))
    }

    static func insulinStrengthPercentage(session: ExerciseSession, at now: Date) -> Decimal {
        guard let start = session.recoveryStart,
              let end = session.recommendedRecoveryEnd,
              end > start
        else { return 100 }
        let total = end.timeIntervalSince(start)
        let remaining = max(0, end.timeIntervalSince(now))
        let initialReduction = session.preset.recovery.initialSensitivityIncreasePercentage
        let reduction = initialReduction * Decimal(remaining / total)
        return max(0, min(100, 100 - reduction))
    }
}

enum ExerciseReconciler {
    static func reconcile(_ session: inout ExerciseSession, at now: Date) {
        guard session.cancelledAt == nil, session.completedAt == nil else { return }

        if let recoveryEnd = session.recommendedRecoveryEnd,
           session.recoveryStart != nil,
           session.actualRecoveryEnd == nil,
           now >= recoveryEnd
        {
            session.actualRecoveryEnd = recoveryEnd
            session.completedAt = recoveryEnd
            return
        }

        if session.actualExerciseStart == nil, now >= session.preExerciseStart,
           session.actualPreExerciseStart == nil
        {
            session.actualPreExerciseStart = max(session.createdAt, session.preExerciseStart)
        }

        if session.actualExerciseStart == nil, now >= session.scheduledExerciseStart {
            session.actualExerciseStart = session.scheduledExerciseStart
        }

        if let timeout = session.preset.safetyTimeoutMinutes,
           let start = session.actualExerciseStart,
           session.actualExerciseEnd == nil,
           now >= start.addingTimeInterval(Double(timeout) * 60)
        {
            stopExercise(&session, at: start.addingTimeInterval(Double(timeout) * 60))
        }
    }

    static func startExerciseNow(_ session: inout ExerciseSession, at now: Date) {
        guard session.cancelledAt == nil, session.completedAt == nil,
              session.actualExerciseEnd == nil else { return }
        if session.actualPreExerciseStart == nil { session.actualPreExerciseStart = now }
        if session.actualExerciseStart == nil { session.actualExerciseStart = now }
    }

    static func stopExercise(_ session: inout ExerciseSession, at now: Date) {
        guard let start = session.actualExerciseStart, session.actualExerciseEnd == nil else { return }
        session.actualExerciseEnd = max(start, now)
        let recoveryDuration = ExerciseRecoveryCalculator.recommendation(
            forExerciseDuration: session.actualExerciseEnd!.timeIntervalSince(start)
        )
        if session.preset.recovery.enabled, recoveryDuration > 0 {
            session.recoveryStart = session.actualExerciseEnd
            session.recommendedRecoveryEnd = session.actualExerciseEnd!.addingTimeInterval(recoveryDuration)
        } else {
            session.completedAt = session.actualExerciseEnd
        }
    }

    static func endRecovery(_ session: inout ExerciseSession, at now: Date) {
        guard session.recoveryStart != nil, session.actualRecoveryEnd == nil else { return }
        session.actualRecoveryEnd = now
        session.completedAt = now
    }

    static func cancel(_ session: inout ExerciseSession, at now: Date) {
        guard session.completedAt == nil, session.cancelledAt == nil else { return }
        session.cancelledAt = now
        if session.recoveryStart != nil, session.actualRecoveryEnd == nil { session.actualRecoveryEnd = now }
        if session.actualExerciseStart != nil, session.actualExerciseEnd == nil { session.actualExerciseEnd = now }
    }
}

struct ExercisePersistedState: Codable, Equatable {
    var activeSession: ExerciseSession?
    var presets: [ExercisePreset]

    static let initial = ExercisePersistedState(activeSession: nil, presets: ExercisePreset.defaults)
}

protocol ExerciseStorage {
    func load() async -> ExercisePersistedState
    func update(_ mutation: @Sendable (inout ExercisePersistedState) -> Void) async -> ExercisePersistedState
}

actor BaseExerciseStorage: ExerciseStorage {
    private let storage: FileStorage
    private let file = "exercise/state.json"

    init(storage: FileStorage) {
        self.storage = storage
    }

    func load() async -> ExercisePersistedState {
        await storage.retrieveAsync(file, as: ExercisePersistedState.self) ?? .initial
    }

    func update(_ mutation: @Sendable (inout ExercisePersistedState) -> Void) async -> ExercisePersistedState {
        var state = await load()
        mutation(&state)
        await storage.saveAsync(state, as: file)
        return state
    }
}

struct EffectiveExerciseAdjustment: Codable, Equatable {
    var sessionID: UUID
    var phase: ExercisePhase
    var basalScale: Decimal
    var correctionScale: Decimal
    var smbEnabled: Bool
    var target: Decimal?
    var source: String

    static func resolve(session: ExerciseSession?, at now: Date) -> EffectiveExerciseAdjustment? {
        guard let session, let settings = session.settings(at: now) else { return nil }
        return EffectiveExerciseAdjustment(
            sessionID: session.id,
            phase: session.phase(at: now),
            basalScale: max(0, min(100, settings.basalPercentage)) / 100,
            correctionScale: max(0, min(100, settings.insulinStrengthPercentage)) / 100,
            smbEnabled: settings.smbEnabled,
            target: settings.target,
            source: "Exercise \(session.preset.name) / \(session.phase(at: now).rawValue)"
        )
    }
}
