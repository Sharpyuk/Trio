import AVFAudio
import Combine
import CoreData
import Foundation

struct ExerciseAnnouncementSettings: Codable, Equatable {
    var enabled: Bool = false
    var intervalMinutes: Decimal = 2
    var includeTrend: Bool = true
    var includeRateOfChange: Bool = false
    var urgentAnnouncementsEnabled: Bool = true
    var lowThresholdMgdl: Decimal = 70
    var highThresholdMgdl: Decimal = 180
    var units: GlucoseUnits = .mgdL
    var announcementsMade: Int = 0
}

enum ExerciseGuardrailMode: String, Codable, CaseIterable, Identifiable {
    case inform
    case warn
    case assist
    case intervene
    case custom

    static var allCases: [ExerciseGuardrailMode] {
        [.inform, .warn, .custom]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inform: return String(localized: "Inform")
        case .warn: return String(localized: "Warn")
        case .assist: return String(localized: "Custom")
        case .intervene: return String(localized: "Custom")
        case .custom: return String(localized: "Custom")
        }
    }

    var summary: String {
        switch self {
        case .inform:
            return String(localized: "Log events only. No automatic changes.")
        case .warn:
            return String(localized: "Warn me if glucose exceeds threshold.")
        case .assist,
             .intervene:
            return String(localized: "Manually configure thresholds and actions.")
        case .custom:
            return String(localized: "Manually configure thresholds and actions.")
        }
    }
}

enum ExerciseGuardrailTrendRequirement: String, Codable, CaseIterable, Identifiable {
    case any
    case rising
    case risingFast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return String(localized: "Any")
        case .rising: return String(localized: "Rising")
        case .risingFast: return String(localized: "Rising fast")
        }
    }
}

struct ExerciseGuardrailActions: Codable, Equatable {
    var reenableBasal = false
    var reenableSMB = false
    var cancelExerciseOverride = false
    var announceWarning = true
    var logOnly = false
}

struct ExerciseGuardrailSettings: Codable, Equatable {
    var enabled = false
    var mode: ExerciseGuardrailMode = .inform
    var highGlucoseThresholdMgdl: Decimal = 216
    var highGlucosePersistenceMinutes: Decimal = 10
    var trendRequirement: ExerciseGuardrailTrendRequirement = .any
    var actions = ExerciseGuardrailActions()
    var cooldownMinutes: Decimal = 15

    var normalizedMode: ExerciseGuardrailMode {
        switch mode {
        case .assist,
             .intervene:
            return .custom
        default:
            return mode
        }
    }
}

struct ExerciseGuardrailEvent: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var timestamp: Date
    var glucoseMgdl: Decimal?
    var glucoseDisplayValue: Decimal?
    var glucoseDisplayUnits: String
    var trend: String?
    var phase: String
    var triggerReason: String
    var actionsTaken: [String]
}

struct ExerciseActivityPreset: Codable, Identifiable, Equatable {
    var id: String
    var activityTypeName: String
    var icon: String
    var preExerciseEnabled: Bool
    var preExerciseDuration: Decimal
    var preExerciseTarget: Decimal
    var preExerciseBasalPercent: Double
    var preExerciseSMBSuppressed: Bool
    var exerciseTarget: Decimal
    var exerciseBasalPercent: Double
    var exerciseSMBSuppressed: Bool
    var announceGlucoseEnabled: Bool
    var announcementInterval: Decimal
    var includeTrend: Bool
    var urgentAnnouncementsEnabled: Bool
    var recoveryEnabled: Bool
    var postExerciseTargetEnabled: Bool
    var minimumDurationForRecovery: Decimal
    var defaultRecoveryDecayType: ExerciseSensitivityDecayType
    var guardrailSettings: ExerciseGuardrailSettings

    static func builtIn(
        _ name: String,
        icon: String,
        preBasal: Double,
        exerciseBasal: Double,
        announce: Bool = false
    ) -> ExerciseActivityPreset {
        ExerciseActivityPreset(
            id: name,
            activityTypeName: name,
            icon: icon,
            preExerciseEnabled: true,
            preExerciseDuration: 60,
            preExerciseTarget: 108,
            preExerciseBasalPercent: preBasal,
            preExerciseSMBSuppressed: true,
            exerciseTarget: 108,
            exerciseBasalPercent: exerciseBasal,
            exerciseSMBSuppressed: true,
            announceGlucoseEnabled: announce,
            announcementInterval: 2,
            includeTrend: true,
            urgentAnnouncementsEnabled: true,
            recoveryEnabled: true,
            postExerciseTargetEnabled: false,
            minimumDurationForRecovery: 10,
            defaultRecoveryDecayType: .linear,
            guardrailSettings: ExerciseGuardrailSettings()
        )
    }
}

enum ExerciseActivityPresetStore {
    private static let storageKey = "ExerciseActivityPresets.v1"

    static let builtInPresets: [ExerciseActivityPreset] = [
        .builtIn("Run", icon: "figure.run", preBasal: 0, exerciseBasal: 25),
        .builtIn("Ultra Run", icon: "figure.run", preBasal: 0, exerciseBasal: 25, announce: true),
        .builtIn("Walk", icon: "figure.walk", preBasal: 50, exerciseBasal: 25),
        .builtIn("Hike", icon: "figure.hiking", preBasal: 50, exerciseBasal: 25),
        .builtIn("Cycle", icon: "bicycle", preBasal: 25, exerciseBasal: 25),
        .builtIn("Strength Training", icon: "dumbbell", preBasal: 80, exerciseBasal: 80),
        .builtIn("Custom", icon: "figure.mixed.cardio", preBasal: 0, exerciseBasal: 25)
    ]

    static func loadPresets() -> [ExerciseActivityPreset] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ExerciseActivityPreset].self, from: data)
        else {
            savePresets(builtInPresets)
            return builtInPresets
        }

        let missingBuiltIns = builtInPresets.filter { builtIn in
            !decoded.contains { $0.id == builtIn.id }
        }
        return decoded + missingBuiltIns
    }

    static func preset(named name: String) -> ExerciseActivityPreset {
        let normalizedName = normalizedPresetName(name)
        return loadPresets().first {
            normalizedPresetName($0.activityTypeName) == normalizedName || normalizedPresetName($0.id) == normalizedName
        } ??
            builtInPresets.first { $0.activityTypeName == "Custom" }!
    }

    static func savePreset(_ preset: ExerciseActivityPreset) {
        var presets = loadPresets()
        if let index = presets.firstIndex(where: { $0.id == preset.id || $0.activityTypeName == preset.activityTypeName }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        savePresets(presets)
        debugPrint("ExerciseOverride preset saved \(preset.activityTypeName)")
    }

    static func deletePreset(id: String) {
        let presets = loadPresets().filter { $0.id != id }
        savePresets(presets)
        debugPrint("ExerciseOverride preset deleted \(id)")
    }

    static func resetToDefaults() {
        savePresets(builtInPresets)
    }

    private static func savePresets(_ presets: [ExerciseActivityPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func normalizedPresetName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum ExerciseSessionState: String, Codable, Equatable {
    case scheduledPreExercise
    case preExerciseActive
    case exerciseActive
    case recoveryActive
    case completed
    case cancelled
}

struct ExerciseSessionMetadata: Codable, Equatable {
    struct PhaseSettings: Codable, Equatable {
        var basalPercentage: Double
        var target: Decimal
        var suppressSMB: Bool

        var insulinStrengthPercentage: Double { basalPercentage }
    }

    let sessionID: String
    let exerciseTypeName: String
    var sessionCreatedAt = Date()
    var scheduledExerciseStart: Date?
    var plannedExerciseEnd: Date?
    var preExerciseStart: Date?
    var actualExerciseStart: Date?
    var actualExerciseEnd: Date?
    var recoveryStart: Date?
    var recoveryEnd: Date?
    var cancelledAt: Date?
    var preExerciseEnabled: Bool = true
    var preExerciseDurationMinutes: Decimal = 60
    var preExerciseSettings: PhaseSettings?
    var exerciseSettings: PhaseSettings?
    let postExerciseEnabled: Bool
    let postExerciseBasalPercentage: Double
    let postExerciseTargetEnabled: Bool
    let postExerciseTarget: Decimal
    let postExerciseSuppressSMB: Bool
    var recoverySkippedReason: String?
    var announcementSettings: ExerciseAnnouncementSettings
    var guardrailSettings = ExerciseGuardrailSettings()
    var guardrailEvents: [ExerciseGuardrailEvent] = []
    var lastGuardrailTriggerAt: Date?
    var guardrailBasalReenabledAt: Date?
    var guardrailSMBReenabledAt: Date?

    enum CodingKeys: String, CodingKey {
        case sessionID
        case exerciseTypeName
        case sessionCreatedAt
        case scheduledExerciseStart
        case plannedExerciseEnd
        case preExerciseStart
        case actualExerciseStart
        case actualExerciseEnd
        case recoveryStart
        case recoveryEnd
        case cancelledAt
        case preExerciseEnabled
        case preExerciseDurationMinutes
        case preExerciseSettings
        case exerciseSettings
        case postExerciseEnabled
        case postExerciseBasalPercentage
        case postExerciseTargetEnabled
        case postExerciseTarget
        case postExerciseSuppressSMB
        case recoverySkippedReason
        case announcementSettings
        case guardrailSettings
        case guardrailEvents
        case lastGuardrailTriggerAt
        case guardrailBasalReenabledAt
        case guardrailSMBReenabledAt
    }

    init(
        sessionID: String,
        exerciseTypeName: String,
        sessionCreatedAt: Date = Date(),
        scheduledExerciseStart: Date? = nil,
        plannedExerciseEnd: Date? = nil,
        preExerciseStart: Date? = nil,
        actualExerciseStart: Date? = nil,
        actualExerciseEnd: Date? = nil,
        recoveryStart: Date? = nil,
        recoveryEnd: Date? = nil,
        cancelledAt: Date? = nil,
        preExerciseEnabled: Bool = true,
        preExerciseDurationMinutes: Decimal = 60,
        preExerciseSettings: PhaseSettings? = nil,
        exerciseSettings: PhaseSettings? = nil,
        postExerciseEnabled: Bool,
        postExerciseBasalPercentage: Double,
        postExerciseTargetEnabled: Bool = false,
        postExerciseTarget: Decimal,
        postExerciseSuppressSMB: Bool,
        recoverySkippedReason: String? = nil,
        announcementSettings: ExerciseAnnouncementSettings,
        guardrailSettings: ExerciseGuardrailSettings = ExerciseGuardrailSettings(),
        guardrailEvents: [ExerciseGuardrailEvent] = [],
        lastGuardrailTriggerAt: Date? = nil,
        guardrailBasalReenabledAt: Date? = nil,
        guardrailSMBReenabledAt: Date? = nil
    ) {
        self.sessionID = sessionID
        self.exerciseTypeName = exerciseTypeName
        self.sessionCreatedAt = sessionCreatedAt
        self.scheduledExerciseStart = scheduledExerciseStart
        self.plannedExerciseEnd = plannedExerciseEnd
        self.preExerciseStart = preExerciseStart
        self.actualExerciseStart = actualExerciseStart
        self.actualExerciseEnd = actualExerciseEnd
        self.recoveryStart = recoveryStart
        self.recoveryEnd = recoveryEnd
        self.cancelledAt = cancelledAt
        self.preExerciseEnabled = preExerciseEnabled
        self.preExerciseDurationMinutes = preExerciseDurationMinutes
        self.preExerciseSettings = preExerciseSettings
        self.exerciseSettings = exerciseSettings
        self.postExerciseEnabled = postExerciseEnabled
        self.postExerciseBasalPercentage = postExerciseBasalPercentage
        self.postExerciseTargetEnabled = postExerciseTargetEnabled
        self.postExerciseTarget = postExerciseTarget
        self.postExerciseSuppressSMB = postExerciseSuppressSMB
        self.recoverySkippedReason = recoverySkippedReason
        self.announcementSettings = announcementSettings
        self.guardrailSettings = guardrailSettings
        self.guardrailEvents = guardrailEvents
        self.lastGuardrailTriggerAt = lastGuardrailTriggerAt
        self.guardrailBasalReenabledAt = guardrailBasalReenabledAt
        self.guardrailSMBReenabledAt = guardrailSMBReenabledAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        exerciseTypeName = try container.decode(String.self, forKey: .exerciseTypeName)
        sessionCreatedAt = try container.decodeIfPresent(Date.self, forKey: .sessionCreatedAt) ?? Date()
        scheduledExerciseStart = try container.decodeIfPresent(Date.self, forKey: .scheduledExerciseStart)
        plannedExerciseEnd = try container.decodeIfPresent(Date.self, forKey: .plannedExerciseEnd)
        preExerciseStart = try container.decodeIfPresent(Date.self, forKey: .preExerciseStart)
        actualExerciseStart = try container.decodeIfPresent(Date.self, forKey: .actualExerciseStart)
        actualExerciseEnd = try container.decodeIfPresent(Date.self, forKey: .actualExerciseEnd)
        recoveryStart = try container.decodeIfPresent(Date.self, forKey: .recoveryStart)
        recoveryEnd = try container.decodeIfPresent(Date.self, forKey: .recoveryEnd)
        cancelledAt = try container.decodeIfPresent(Date.self, forKey: .cancelledAt)
        preExerciseEnabled = try container.decodeIfPresent(Bool.self, forKey: .preExerciseEnabled) ?? true
        preExerciseDurationMinutes = try container.decodeIfPresent(Decimal.self, forKey: .preExerciseDurationMinutes) ?? 60
        preExerciseSettings = try container.decodeIfPresent(PhaseSettings.self, forKey: .preExerciseSettings)
        exerciseSettings = try container.decodeIfPresent(PhaseSettings.self, forKey: .exerciseSettings)
        postExerciseEnabled = try container.decode(Bool.self, forKey: .postExerciseEnabled)
        postExerciseBasalPercentage = try container.decode(Double.self, forKey: .postExerciseBasalPercentage)
        postExerciseTargetEnabled = try container.decodeIfPresent(Bool.self, forKey: .postExerciseTargetEnabled) ?? false
        postExerciseTarget = try container.decode(Decimal.self, forKey: .postExerciseTarget)
        postExerciseSuppressSMB = try container.decode(Bool.self, forKey: .postExerciseSuppressSMB)
        recoverySkippedReason = try container.decodeIfPresent(String.self, forKey: .recoverySkippedReason)
        announcementSettings = try container.decodeIfPresent(ExerciseAnnouncementSettings.self, forKey: .announcementSettings)
            ?? ExerciseAnnouncementSettings()
        guardrailSettings = try container.decodeIfPresent(ExerciseGuardrailSettings.self, forKey: .guardrailSettings)
            ?? ExerciseGuardrailSettings()
        guardrailEvents = try container.decodeIfPresent([ExerciseGuardrailEvent].self, forKey: .guardrailEvents) ?? []
        lastGuardrailTriggerAt = try container.decodeIfPresent(Date.self, forKey: .lastGuardrailTriggerAt)
        guardrailBasalReenabledAt = try container.decodeIfPresent(Date.self, forKey: .guardrailBasalReenabledAt)
        guardrailSMBReenabledAt = try container.decodeIfPresent(Date.self, forKey: .guardrailSMBReenabledAt)
    }

    func state(at now: Date = Date()) -> ExerciseSessionState {
        if cancelledAt != nil { return .cancelled }

        if actualExerciseEnd != nil {
            if let recoveryEnd, now < recoveryEnd {
                return .recoveryActive
            }
            return .completed
        }

        if actualExerciseStart != nil {
            return .exerciseActive
        }

        guard let scheduledExerciseStart else {
            return .completed
        }

        let preStart = preExerciseStart ?? scheduledExerciseStart
        if now < preStart {
            return .scheduledPreExercise
        }
        if now < scheduledExerciseStart {
            return .preExerciseActive
        }
        return .exerciseActive
    }

    mutating func reconcileTimestamps(at now: Date = Date()) {
        guard cancelledAt == nil else { return }

        if actualExerciseStart == nil,
           let scheduledExerciseStart,
           now >= scheduledExerciseStart
        {
            actualExerciseStart = scheduledExerciseStart
        }
    }
}

enum ExerciseSessionMetadataStore {
    static var metadataDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("ExerciseSessions", isDirectory: true)
    }

    static func save(_ metadata: ExerciseSessionMetadata) throws {
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        let url = url(for: metadata.sessionID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: url, options: .atomic)
    }

    static func load(sessionID: String) -> ExerciseSessionMetadata? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url(for: sessionID)) else { return nil }
        return try? decoder.decode(ExerciseSessionMetadata.self, from: data)
    }

    static func loadAll() -> [ExerciseSessionMetadata] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: metadataDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url)
            else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(ExerciseSessionMetadata.self, from: data)
        }
    }

    static func visibleSessionIDs(at now: Date = Date()) -> [String] {
        loadAll()
            .filter { metadata in
                let state = metadata.state(at: now)
                return state != .completed && state != .cancelled
            }
            .map(\.sessionID)
    }

    static func update(sessionID: String, _ changes: (inout ExerciseSessionMetadata) -> Void) {
        guard var metadata = load(sessionID: sessionID) else { return }
        changes(&metadata)
        try? save(metadata)
    }

    static func incrementAnnouncementCount(sessionID: String) {
        guard var metadata = load(sessionID: sessionID) else { return }
        metadata.announcementSettings.announcementsMade += 1
        try? save(metadata)
    }

    private static func url(for sessionID: String) -> URL {
        metadataDirectory.appendingPathComponent("exercise-session-\(sessionID).json")
    }
}

enum ExerciseGlucoseTrend: String, Codable, Equatable {
    case risingFast = "rising fast"
    case risingSlowly = "rising slowly"
    case steady
    case fallingSlowly = "falling slowly"
    case fallingFast = "falling fast"

    static func classify(rateMgdlPerMinute: Decimal) -> ExerciseGlucoseTrend {
        if rateMgdlPerMinute <= -1.8 { return .fallingFast }
        if rateMgdlPerMinute < -0.5 { return .fallingSlowly }
        if rateMgdlPerMinute >= 1.8 { return .risingFast }
        if rateMgdlPerMinute > 0.5 { return .risingSlowly }
        return .steady
    }
}

final class ExerciseGlucoseAnnouncementManager: NSObject {
    static let shared = ExerciseGlucoseAnnouncementManager()

    private let synthesizer = AVSpeechSynthesizer()
    private let context = CoreDataStack.shared.persistentContainer.viewContext
    private var timer: Timer?
    private var lastAnnouncementDate: Date?
    private var lastUrgentAnnouncementDate: Date?
    private var activeSessionID: String?
    private var lastGuardrailGlucoseDateBySession: [String: Date] = [:]
    private var speechAudioSessionActive = false

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    func startMonitoring() {
        if let timer, timer.isValid {
            return
        }
        reconcileExerciseSessions(reason: "startMonitoring")
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        evaluate()
    }

    func stopSpeech() {
        synthesizer.stopSpeaking(at: .immediate)
        deactivateSpeechAudioSession()
    }

    func evaluate() {
        reconcileExerciseSessions(reason: "evaluate")
        advanceDueExerciseSessions()

        evaluateGuardrails()

        guard let override = activeExerciseOverride(),
              let sessionID = override.id,
              let metadata = ExerciseSessionMetadataStore.load(sessionID: sessionID),
              metadata.state() == .exerciseActive,
              metadata.announcementSettings.enabled
        else {
            activeSessionID = nil
            stopSpeech()
            return
        }

        if activeSessionID != sessionID {
            activeSessionID = sessionID
            lastAnnouncementDate = nil
            lastUrgentAnnouncementDate = nil
        }

        guard let latest = latestGlucose(),
              let latestDate = latest.date,
              abs(latestDate.timeIntervalSinceNow) <= 20 * 60
        else {
            return
        }

        let trendInfo = trend(for: latest)
        let now = Date()
        let interval = max(60, NSDecimalNumber(decimal: metadata.announcementSettings.intervalMinutes).doubleValue * 60)
        let urgent = isUrgent(
            glucoseMgdl: Decimal(Int(latest.glucose)),
            trend: trendInfo.trend,
            settings: metadata.announcementSettings
        )
        let urgentDue = urgent &&
            metadata.announcementSettings.urgentAnnouncementsEnabled &&
            (lastUrgentAnnouncementDate == nil || now.timeIntervalSince(lastUrgentAnnouncementDate!) >= 120)
        let intervalDue = lastAnnouncementDate == nil || now.timeIntervalSince(lastAnnouncementDate!) >= interval

        guard urgentDue || intervalDue else { return }
        guard speak(
            latest: latest,
            trend: trendInfo.trend,
            rateMgdlPerMinute: trendInfo.rate,
            settings: metadata.announcementSettings
        ) else {
            return
        }
        lastAnnouncementDate = now
        if urgentDue {
            lastUrgentAnnouncementDate = now
        }
        ExerciseSessionMetadataStore.incrementAnnouncementCount(sessionID: sessionID)
    }

    private func evaluateGuardrails() {
        guard let latest = latestGlucose(),
              let latestDate = latest.date,
              abs(latestDate.timeIntervalSinceNow) <= 20 * 60
        else {
            return
        }

        let trendInfo = trend(for: latest)
        for override in activeExerciseSessionOverrides() {
            guard let sessionID = override.id,
                  var metadata = ExerciseSessionMetadataStore.load(sessionID: sessionID),
                  metadata.guardrailSettings.enabled,
                  metadata.state() != .completed,
                  metadata.state() != .cancelled,
                  shouldEvaluateGuardrail(sessionID: sessionID, latestDate: latestDate),
                  highGlucoseGuardrailTriggered(
                      latest: latest,
                      trend: trendInfo.trend,
                      settings: metadata.guardrailSettings,
                      now: latestDate
                  )
            else {
                continue
            }

            let now = Date()
            let cooldown = max(0, NSDecimalNumber(decimal: metadata.guardrailSettings.cooldownMinutes).doubleValue * 60)
            if let last = metadata.lastGuardrailTriggerAt, now.timeIntervalSince(last) < cooldown {
                continue
            }

            let actionsTaken = applyGuardrailActions(
                sessionID: sessionID,
                override: override,
                metadata: &metadata,
                latest: latest,
                trend: trendInfo.trend,
                now: now
            )
            guard !actionsTaken.isEmpty else { continue }

            metadata.lastGuardrailTriggerAt = now
            metadata.guardrailEvents.append(ExerciseGuardrailEvent(
                timestamp: now,
                glucoseMgdl: Decimal(Int(latest.glucose)),
                glucoseDisplayValue: displayGlucoseValue(
                    rawMgdl: Decimal(Int(latest.glucose)),
                    units: metadata.announcementSettings.units
                ),
                glucoseDisplayUnits: metadata.announcementSettings.units.rawValue,
                trend: trendInfo.trend.rawValue,
                phase: (override.exercisePhase ?? .inactive).title,
                triggerReason: "highGlucosePersisted",
                actionsTaken: actionsTaken
            ))
            try? ExerciseSessionMetadataStore.save(metadata)
            lastGuardrailGlucoseDateBySession[sessionID] = latestDate
            debugPrint(
                "ExerciseOverride guardrail session \(sessionID) phase=\((override.exercisePhase ?? .inactive).title) actions=\(actionsTaken.joined(separator: ","))"
            )
        }

        if context.hasChanges {
            try? context.save()
            Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
        }
    }

    private func shouldEvaluateGuardrail(sessionID: String, latestDate: Date) -> Bool {
        if let lastDate = lastGuardrailGlucoseDateBySession[sessionID], lastDate >= latestDate {
            return false
        }
        return true
    }

    private func highGlucoseGuardrailTriggered(
        latest: GlucoseStored,
        trend: ExerciseGlucoseTrend,
        settings: ExerciseGuardrailSettings,
        now: Date
    ) -> Bool {
        guard Decimal(Int(latest.glucose)) >= settings.highGlucoseThresholdMgdl,
              trendMatchesRequirement(trend, settings.trendRequirement)
        else {
            return false
        }

        let persistenceSeconds = max(
            0,
            NSDecimalNumber(decimal: settings.highGlucosePersistenceMinutes).doubleValue * 60
        )
        guard persistenceSeconds > 0 else { return true }

        let start = now.addingTimeInterval(-persistenceSeconds)
        let request = GlucoseStored.fetchRequest()
        request.predicate = NSPredicate(format: "date >= %@ AND date <= %@", start as NSDate, now as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: true)]
        let readings = (try? context.fetch(request)) ?? []
        guard let first = readings.first,
              let firstDate = first.date,
              now.timeIntervalSince(firstDate) >= persistenceSeconds * 0.8,
              readings.count >= 2
        else {
            return false
        }

        return readings.allSatisfy { Decimal(Int($0.glucose)) >= settings.highGlucoseThresholdMgdl }
    }

    private func trendMatchesRequirement(
        _ trend: ExerciseGlucoseTrend,
        _ requirement: ExerciseGuardrailTrendRequirement
    ) -> Bool {
        switch requirement {
        case .any:
            return true
        case .rising:
            return trend == .risingSlowly || trend == .risingFast
        case .risingFast:
            return trend == .risingFast
        }
    }

    private func applyGuardrailActions(
        sessionID: String,
        override _: OverrideStored,
        metadata: inout ExerciseSessionMetadata,
        latest: GlucoseStored,
        trend: ExerciseGlucoseTrend,
        now: Date
    ) -> [String] {
        let mode = metadata.guardrailSettings.normalizedMode
        var actionsTaken: [String] = []

        switch mode {
        case .inform:
            actionsTaken.append("logged")

        case .warn:
            speakGuardrailWarning(latest: latest, trend: trend, units: metadata.announcementSettings.units)
            actionsTaken.append("warned")

        case .custom:
            let actions = metadata.guardrailSettings.actions
            if actions.announceWarning {
                speakGuardrailWarning(latest: latest, trend: trend, units: metadata.announcementSettings.units)
                actionsTaken.append("announced")
            }
            if actions.reenableBasal, metadata.guardrailBasalReenabledAt == nil {
                reenableBasal(sessionID: sessionID, from: now)
                metadata.guardrailBasalReenabledAt = now
                actionsTaken.append("reenabledBasal")
            }
            if actions.reenableSMB, metadata.guardrailSMBReenabledAt == nil {
                reenableSMB(sessionID: sessionID, from: now)
                metadata.guardrailSMBReenabledAt = now
                actionsTaken.append("reenabledSMB")
            }
            if actions.cancelExerciseOverride {
                cancelExerciseSession(sessionID: sessionID, at: now)
                metadata.cancelledAt = now
                if metadata.actualExerciseStart != nil, metadata.actualExerciseEnd == nil {
                    metadata.actualExerciseEnd = now
                }
                metadata.recoverySkippedReason = "guardrailCancelled"
                actionsTaken.append("cancelledExerciseOverride")
            }

        case .assist,
             .intervene:
            break
        }

        return actionsTaken
    }

    private func reenableBasal(sessionID: String, from _: Date) {
        for override in sessionOverrides(sessionID: sessionID) where override.enabled {
            override.percentage = 100
            override.isUploadedToNS = false
        }
    }

    private func reenableSMB(sessionID: String, from _: Date) {
        for override in sessionOverrides(sessionID: sessionID) where override.enabled {
            override.smbIsOff = false
            override.isUploadedToNS = false
        }
    }

    private func cancelExerciseSession(sessionID: String, at _: Date) {
        for override in sessionOverrides(sessionID: sessionID) where override.enabled {
            override.enabled = false
            override.isUploadedToNS = false
        }
        stopSpeech()
    }

    private func speakGuardrailWarning(latest: GlucoseStored, trend: ExerciseGlucoseTrend, units: GlucoseUnits) {
        guard !synthesizer.isSpeaking else { return }
        prepareSpeechAudioSession()
        let glucose = Decimal(Int(latest.glucose))
        let display = displayGlucoseValue(rawMgdl: glucose, units: units)
        let text = units == .mmolL
            ? formatDecimal(display, maximumFractionDigits: 1)
            : formatDecimal(display, maximumFractionDigits: 0)
        let utterance = AVSpeechUtterance(string: "Exercise guardrail warning. Glucose \(text), \(trend.rawValue).")
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    @discardableResult func reconcileExerciseSessions(reason: String) -> Bool {
        let request = OverrideStored.fetchRequest()
        let sessionIDs = ExerciseSessionMetadataStore.loadAll().map(\.sessionID)
        request.predicate = sessionIDs.isEmpty
            ? NSPredicate(
                format: "enabled == %@ AND name BEGINSWITH %@",
                true as NSNumber,
                OverrideStored.exerciseOverrideName + ":"
            )
            : NSPredicate(
                format: "enabled == %@ AND (id IN %@ OR name BEGINSWITH %@)",
                true as NSNumber,
                sessionIDs,
                OverrideStored.exerciseOverrideName + ":"
            )
        let overrides = (try? context.fetch(request)) ?? []
        let now = Date()
        var changed = false

        for override in overrides {
            guard let sessionID = override.id,
                  var metadata = ExerciseSessionMetadataStore.load(sessionID: sessionID)
            else {
                override.enabled = false
                override.isUploadedToNS = false
                changed = true
                debugPrint("ExerciseOverride cleanup \(reason): disabled orphan override")
                continue
            }

            let state = metadata.state(at: now)
            let age = now.timeIntervalSince(metadata.sessionCreatedAt)
            let exerciseAge = metadata.actualExerciseStart.map { now.timeIntervalSince($0) } ?? 0
            let staleScheduled = metadata.actualExerciseStart == nil && age > 24 * 60 * 60
            let staleExercise = metadata.actualExerciseStart != nil && metadata
                .actualExerciseEnd == nil && exerciseAge > 24 * 60 * 60

            if state == .completed || state == .cancelled || staleScheduled || staleExercise {
                override.enabled = false
                override.isUploadedToNS = false
                if staleScheduled || staleExercise {
                    metadata.cancelledAt = now
                    metadata.recoverySkippedReason = staleScheduled ? "staleScheduledSession" : "staleExerciseSession"
                    try? ExerciseSessionMetadataStore.save(metadata)
                }
                changed = true
                debugPrint(
                    "ExerciseOverride cleanup \(reason): session \(sessionID) state=\(state.rawValue) staleScheduled=\(staleScheduled) staleExercise=\(staleExercise)"
                )
            }
        }

        if context.hasChanges {
            try? context.save()
        }

        if changed {
            stopSpeech()
            Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
        }
        if recreateMissingExercisePhaseOverrides(now: now, reason: reason) {
            changed = true
        }
        return changed
    }

    @discardableResult private func recreateMissingExercisePhaseOverrides(now: Date, reason: String) -> Bool {
        var changed = false

        for metadata in ExerciseSessionMetadataStore.loadAll() {
            let state = metadata.state(at: now)
            guard state != .completed, state != .cancelled else { continue }
            guard sessionOverrides(sessionID: metadata.sessionID).filter(\.enabled).isEmpty else { continue }

            if state == .exerciseActive,
               let plannedExerciseEnd = metadata.plannedExerciseEnd,
               now >= plannedExerciseEnd
            {
                createRecoveryFromPlannedEnd(metadata: metadata, plannedExerciseEnd: plannedExerciseEnd, now: now)
                changed = true
                continue
            }

            let phase: ExercisePhase
            let startDate: Date
            let duration: Decimal
            let percentage: Double
            let suppressSMB: Bool
            let target: Decimal
            let overrideTarget: Bool

            switch state {
            case .preExerciseActive,
                 .scheduledPreExercise:
                phase = .preExercise
                startDate = metadata.preExerciseStart ?? metadata.scheduledExerciseStart ?? now
                duration = Decimal(max(1, (metadata.scheduledExerciseStart ?? now).timeIntervalSince(startDate) / 60))
                percentage = metadata.preExerciseSettings?.insulinStrengthPercentage ?? 0
                suppressSMB = metadata.preExerciseSettings?.suppressSMB ?? true
                target = metadata.preExerciseSettings?.target ?? 108
                overrideTarget = true

            case .exerciseActive:
                phase = .duringExercise
                startDate = metadata.actualExerciseStart ?? metadata.scheduledExerciseStart ?? now
                duration = metadata.plannedExerciseEnd.map {
                    Decimal(max(1, $0.timeIntervalSince(startDate) / 60))
                } ?? 2160
                percentage = metadata.guardrailBasalReenabledAt == nil
                    ? (metadata.exerciseSettings?.insulinStrengthPercentage ?? 25)
                    : 100
                suppressSMB = metadata.guardrailSMBReenabledAt == nil
                    ? (metadata.exerciseSettings?.suppressSMB ?? true)
                    : false
                target = metadata.exerciseSettings?.target ?? 108
                overrideTarget = true

            case .recoveryActive:
                phase = .postExercise
                startDate = metadata.recoveryStart ?? metadata.actualExerciseEnd ?? now
                duration = metadata.recoveryEnd.map {
                    Decimal(max(1, $0.timeIntervalSince(startDate) / 60))
                } ?? 1
                percentage = metadata.postExerciseBasalPercentage
                suppressSMB = metadata.postExerciseSuppressSMB
                target = metadata.postExerciseTargetEnabled ? metadata.postExerciseTarget : 0
                overrideTarget = metadata.postExerciseTargetEnabled

            case .cancelled,
                 .completed:
                continue
            }

            insertExerciseOverride(
                metadata: metadata,
                phase: phase,
                startDate: startDate,
                duration: duration,
                percentage: percentage,
                suppressSMB: suppressSMB,
                target: target,
                overrideTarget: overrideTarget
            )
            changed = true
            debugPrint("ExerciseOverride recreate \(reason): session \(metadata.sessionID) phase=\(phase.rawValue)")
        }

        if context.hasChanges {
            try? context.save()
            Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
        }
        return changed
    }

    @discardableResult private func speak(
        latest: GlucoseStored,
        trend: ExerciseGlucoseTrend,
        rateMgdlPerMinute: Decimal?,
        settings: ExerciseAnnouncementSettings
    ) -> Bool {
        guard !synthesizer.isSpeaking else { return false }

        let glucose = Decimal(Int(latest.glucose))
        let units = settings.units
        let glucoseText: String
        if units == .mmolL {
            glucoseText = formatDecimal(glucose * GlucoseUnits.exchangeRate, maximumFractionDigits: 1)
        } else {
            glucoseText = formatDecimal(glucose, maximumFractionDigits: 0)
        }

        var parts = ["Glucose \(glucoseText)"]
        if settings.includeTrend {
            parts.append(trend.rawValue)
        }
        if settings.includeRateOfChange, let rateMgdlPerMinute {
            let rateText: String
            if units == .mmolL {
                rateText = formatDecimal(rateMgdlPerMinute * GlucoseUnits.exchangeRate, maximumFractionDigits: 2)
                parts.append("\(rateText) mmol per liter per minute")
            } else {
                rateText = formatDecimal(rateMgdlPerMinute, maximumFractionDigits: 1)
                parts.append("\(rateText) milligrams per deciliter per minute")
            }
        }

        let utterance = AVSpeechUtterance(string: parts.joined(separator: ", ") + ".")
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        prepareSpeechAudioSession()
        synthesizer.speak(utterance)
        return true
    }

    private func prepareSpeechAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers, .mixWithOthers]
            )
            try session.setActive(true)
            speechAudioSessionActive = true
        } catch {
            debugPrint("Exercise glucose announcement audio session activation failed: \(error)")
        }
    }

    private func deactivateSpeechAudioSession() {
        guard speechAudioSessionActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            debugPrint("Exercise glucose announcement audio session deactivation failed: \(error)")
        }
        speechAudioSessionActive = false
    }

    private func isUrgent(
        glucoseMgdl: Decimal,
        trend: ExerciseGlucoseTrend,
        settings: ExerciseAnnouncementSettings
    ) -> Bool {
        glucoseMgdl <= settings.lowThresholdMgdl ||
            glucoseMgdl >= settings.highThresholdMgdl ||
            trend == .fallingFast ||
            trend == .risingFast
    }

    private func activeExerciseOverride() -> OverrideStored? {
        let request = OverrideStored.fetchRequest()
        request.predicate = NSPredicate.lastActiveOverride
        request.sortDescriptors = [NSSortDescriptor(keyPath: \OverrideStored.date, ascending: false)]
        let overrides = (try? context.fetch(request)) ?? []
        return overrides.first {
            guard $0.isActive(),
                  $0.exercisePhase == .duringExercise,
                  let sessionID = $0.id,
                  ExerciseSessionMetadataStore.load(sessionID: sessionID)?.state() == .exerciseActive
            else {
                return false
            }
            return true
        }
    }

    private func activeExerciseSessionOverrides() -> [OverrideStored] {
        let request = OverrideStored.fetchRequest()
        let sessionIDs = ExerciseSessionMetadataStore.visibleSessionIDs()
        request.predicate = sessionIDs.isEmpty
            ? NSPredicate(
                format: "enabled == %@ AND name BEGINSWITH %@",
                true as NSNumber,
                OverrideStored.exerciseOverrideName + ":"
            )
            : NSPredicate(format: "enabled == %@ AND id IN %@", true as NSNumber, sessionIDs)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \OverrideStored.date, ascending: false)]
        let overrides = (try? context.fetch(request)) ?? []
        return overrides.filter {
            guard $0.isActive(),
                  $0.isExerciseMode,
                  let sessionID = $0.id,
                  let metadata = ExerciseSessionMetadataStore.load(sessionID: sessionID)
            else {
                return false
            }
            switch metadata.state() {
            case .exerciseActive,
                 .preExerciseActive,
                 .recoveryActive:
                return true
            case .cancelled,
                 .completed,
                 .scheduledPreExercise:
                return false
            }
        }
    }

    private func sessionOverrides(sessionID: String) -> [OverrideStored] {
        let request = OverrideStored.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", sessionID)
        return (try? context.fetch(request)) ?? []
    }

    private func insertExerciseOverride(
        metadata: ExerciseSessionMetadata,
        phase: ExercisePhase,
        startDate: Date,
        duration: Decimal,
        percentage: Double,
        suppressSMB: Bool,
        target: Decimal,
        overrideTarget: Bool,
        sensitivityPercent: Decimal = 0,
        decayType: ExerciseSensitivityDecayType = .flat
    ) {
        let override = OverrideStored(context: context)
        override.name = OverrideStored.exerciseOverrideName(type: metadata.exerciseTypeName, phase: phase)
        override.id = metadata.sessionID
        override.date = startDate
        override.duration = duration as NSDecimalNumber
        override.indefinite = false
        override.percentage = percentage
        override.enabled = true
        override.isPreset = false
        override.isUploadedToNS = false
        override.smbIsOff = suppressSMB
        override.target = overrideTarget ? target as NSDecimalNumber : NSDecimalNumber.zero
        override.advancedSettings = false
        override.isfAndCr = phase != .postExercise
        override.isf = phase != .postExercise
        override.cr = phase != .postExercise
        override.smbIsScheduledOff = false
        override.start = sensitivityPercent as NSDecimalNumber
        override.end = Decimal(decayType.rawValue) as NSDecimalNumber
    }

    private func createRecoveryFromPlannedEnd(
        metadata: ExerciseSessionMetadata,
        plannedExerciseEnd: Date,
        now: Date
    ) {
        let exerciseStart = metadata.actualExerciseStart ?? metadata.scheduledExerciseStart ?? plannedExerciseEnd
        let exerciseDurationMinutes = max(0, plannedExerciseEnd.timeIntervalSince(exerciseStart) / 60)
        let recommendation = metadata.postExerciseEnabled
            ? ExerciseRecoveryCalculator.recommendation(forExerciseDurationMinutes: exerciseDurationMinutes)
            : ExerciseRecoveryRecommendation(durationMinutes: 0, sensitivityPercent: 0, decayType: .linear)

        ExerciseSessionMetadataStore.update(sessionID: metadata.sessionID) {
            $0.actualExerciseStart = exerciseStart
            $0.actualExerciseEnd = plannedExerciseEnd
            if recommendation.hasRecoveryEffect {
                $0.recoveryStart = plannedExerciseEnd
                $0.recoveryEnd = plannedExerciseEnd.addingTimeInterval(TimeInterval(recommendation.durationMinutes * 60))
                $0.recoverySkippedReason = nil
            } else {
                $0.recoverySkippedReason = metadata.postExerciseEnabled ? "noRecoveryEffect" : "recoveryDisabled"
            }
        }

        guard recommendation.hasRecoveryEffect,
              plannedExerciseEnd.addingTimeInterval(TimeInterval(recommendation.durationMinutes * 60)) > now
        else {
            return
        }

        insertExerciseOverride(
            metadata: metadata,
            phase: .postExercise,
            startDate: plannedExerciseEnd,
            duration: Decimal(recommendation.durationMinutes),
            percentage: metadata.postExerciseBasalPercentage,
            suppressSMB: metadata.postExerciseSuppressSMB,
            target: metadata.postExerciseTargetEnabled ? metadata.postExerciseTarget : 0,
            overrideTarget: metadata.postExerciseTargetEnabled,
            sensitivityPercent: recommendation.sensitivityPercent,
            decayType: recommendation.decayType
        )
    }

    private func advanceDueExerciseSessions() {
        let request = OverrideStored.fetchRequest()
        let sessionIDs = ExerciseSessionMetadataStore.visibleSessionIDs()
        request.predicate = sessionIDs.isEmpty
            ? NSPredicate(
                format: "enabled == %@ AND name BEGINSWITH %@",
                true as NSNumber,
                OverrideStored.exerciseOverrideName + ":"
            )
            : NSPredicate(format: "enabled == %@ AND id IN %@", true as NSNumber, sessionIDs)
        let overrides = (try? context.fetch(request)) ?? []
        let now = Date()
        var changed = false

        for override in overrides {
            guard let sessionID = override.id,
                  var metadata = ExerciseSessionMetadataStore.load(sessionID: sessionID)
            else { continue }

            switch metadata.state(at: now) {
            case .exerciseActive where override.exercisePhase == .preExercise:
                let settings = metadata.exerciseSettings
                override.name = OverrideStored.exerciseOverrideName(
                    type: override.exerciseTypeName ?? metadata.exerciseTypeName,
                    phase: .duringExercise
                )
                override.date = metadata.scheduledExerciseStart ?? now
                override.duration = (metadata.plannedExerciseEnd.map {
                    Decimal(max(1, $0.timeIntervalSince(override.date ?? now) / 60))
                } ?? 2160) as NSDecimalNumber
                override.percentage = metadata.guardrailBasalReenabledAt == nil
                    ? (settings?.basalPercentage ?? override.percentage)
                    : 100
                override.smbIsOff = metadata.guardrailSMBReenabledAt == nil
                    ? (settings?.suppressSMB ?? override.smbIsOff)
                    : false
                override.target = (settings?.target ?? override.target?.decimalValue ?? 0) as NSDecimalNumber
                override.isfAndCr = true
                override.isf = true
                override.cr = true
                override.isUploadedToNS = false
                metadata.actualExerciseStart = override.date
                try? ExerciseSessionMetadataStore.save(metadata)
                changed = true
                debugPrint("ExerciseOverride session \(sessionID) announcement-manager auto-start at \(override.date ?? now)")

            case .completed where override.exercisePhase == .postExercise:
                override.enabled = false
                override.isUploadedToNS = false
                changed = true
                debugPrint("ExerciseOverride session \(sessionID) announcement-manager expired recovery")

            case .cancelled:
                override.enabled = false
                override.isUploadedToNS = false
                changed = true

            default:
                break
            }
        }

        if context.hasChanges {
            try? context.save()
        }
        if changed {
            Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
        }
    }

    private func latestGlucose() -> GlucoseStored? {
        let request = GlucoseStored.fetchRequest()
        request.predicate = NSPredicate(format: "date >= %@", Date().addingTimeInterval(-20 * 60) as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: false)]
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func trend(for latest: GlucoseStored) -> (trend: ExerciseGlucoseTrend, rate: Decimal?) {
        guard let latestDate = latest.date else {
            return (.steady, nil)
        }

        let request = GlucoseStored.fetchRequest()
        request.predicate = NSPredicate(
            format: "date < %@ AND date >= %@",
            latestDate as NSDate,
            latestDate.addingTimeInterval(-20 * 60) as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: false)]
        request.fetchLimit = 1

        guard let previous = try? context.fetch(request).first,
              let previousDate = previous.date
        else {
            return (.steady, nil)
        }

        let minutes = latestDate.timeIntervalSince(previousDate) / 60
        guard minutes > 0 else {
            return (.steady, nil)
        }

        let rate = Decimal(Int(latest.glucose) - Int(previous.glucose)) / Decimal(minutes)
        return (ExerciseGlucoseTrend.classify(rateMgdlPerMinute: rate), rate)
    }

    private func formatDecimal(_ value: Decimal, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = maximumFractionDigits > 0 ? 1 : 0
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private func displayGlucoseValue(rawMgdl: Decimal, units: GlucoseUnits) -> Decimal {
        units == .mgdL ? rawMgdl : rawMgdl.asMmolL
    }
}

extension ExerciseGlucoseAnnouncementManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        deactivateSpeechAudioSession()
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        deactivateSpeechAudioSession()
    }
}
