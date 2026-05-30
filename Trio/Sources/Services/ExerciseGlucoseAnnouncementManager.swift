import AVFAudio
import Combine
import CoreData
import Foundation

struct ExerciseAnnouncementSettings: Codable, Equatable {
    var enabled: Bool = false
    var intervalMinutes: Decimal = 5
    var includeTrend: Bool = true
    var includeRateOfChange: Bool = false
    var urgentAnnouncementsEnabled: Bool = true
    var lowThresholdMgdl: Decimal = 70
    var highThresholdMgdl: Decimal = 180
    var units: GlucoseUnits = .mgdL
    var announcementsMade: Int = 0
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
    }

    let sessionID: String
    let exerciseTypeName: String
    var sessionCreatedAt = Date()
    var scheduledExerciseStart: Date?
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
    let postExerciseTarget: Decimal
    let postExerciseSuppressSMB: Bool
    var recoverySkippedReason: String?
    var announcementSettings: ExerciseAnnouncementSettings

    enum CodingKeys: String, CodingKey {
        case sessionID
        case exerciseTypeName
        case sessionCreatedAt
        case scheduledExerciseStart
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
        case postExerciseTarget
        case postExerciseSuppressSMB
        case recoverySkippedReason
        case announcementSettings
    }

    init(
        sessionID: String,
        exerciseTypeName: String,
        sessionCreatedAt: Date = Date(),
        scheduledExerciseStart: Date? = nil,
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
        postExerciseTarget: Decimal,
        postExerciseSuppressSMB: Bool,
        recoverySkippedReason: String? = nil,
        announcementSettings: ExerciseAnnouncementSettings
    ) {
        self.sessionID = sessionID
        self.exerciseTypeName = exerciseTypeName
        self.sessionCreatedAt = sessionCreatedAt
        self.scheduledExerciseStart = scheduledExerciseStart
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
        self.postExerciseTarget = postExerciseTarget
        self.postExerciseSuppressSMB = postExerciseSuppressSMB
        self.recoverySkippedReason = recoverySkippedReason
        self.announcementSettings = announcementSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        exerciseTypeName = try container.decode(String.self, forKey: .exerciseTypeName)
        sessionCreatedAt = try container.decodeIfPresent(Date.self, forKey: .sessionCreatedAt) ?? Date()
        scheduledExerciseStart = try container.decodeIfPresent(Date.self, forKey: .scheduledExerciseStart)
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
        postExerciseTarget = try container.decode(Decimal.self, forKey: .postExerciseTarget)
        postExerciseSuppressSMB = try container.decode(Bool.self, forKey: .postExerciseSuppressSMB)
        recoverySkippedReason = try container.decodeIfPresent(String.self, forKey: .recoverySkippedReason)
        announcementSettings = try container.decodeIfPresent(ExerciseAnnouncementSettings.self, forKey: .announcementSettings)
            ?? ExerciseAnnouncementSettings()
    }

    func state(at now: Date = Date()) -> ExerciseSessionState {
        if cancelledAt != nil { return .cancelled }

        if let actualExerciseEnd {
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

    override private init() {
        super.init()
    }

    func startMonitoring() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        evaluate()
    }

    func stopSpeech() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func evaluate() {
        advanceDueExerciseSessions()

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
        speak(
            latest: latest,
            trend: trendInfo.trend,
            rateMgdlPerMinute: trendInfo.rate,
            settings: metadata.announcementSettings
        )
        lastAnnouncementDate = now
        if urgentDue {
            lastUrgentAnnouncementDate = now
        }
        ExerciseSessionMetadataStore.incrementAnnouncementCount(sessionID: sessionID)
    }

    private func speak(
        latest: GlucoseStored,
        trend: ExerciseGlucoseTrend,
        rateMgdlPerMinute: Decimal?,
        settings: ExerciseAnnouncementSettings
    ) {
        guard !synthesizer.isSpeaking else { return }

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
        synthesizer.speak(utterance)
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

    private func advanceDueExerciseSessions() {
        let request = OverrideStored.fetchRequest()
        request.predicate = NSPredicate(
            format: "enabled == %@ AND name BEGINSWITH %@",
            true as NSNumber,
            OverrideStored.exerciseOverrideName + ":"
        )
        let overrides = (try? context.fetch(request)) ?? []
        let now = Date()

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
                override.duration = 2160
                override.percentage = settings?.basalPercentage ?? override.percentage
                override.smbIsOff = settings?.suppressSMB ?? override.smbIsOff
                override.target = (settings?.target ?? override.target?.decimalValue ?? 0) as NSDecimalNumber
                override.isUploadedToNS = false
                metadata.actualExerciseStart = override.date
                try? ExerciseSessionMetadataStore.save(metadata)
                debugPrint("ExerciseOverride session \(sessionID) announcement-manager auto-start at \(override.date ?? now)")

            case .completed where override.exercisePhase == .postExercise:
                override.enabled = false
                override.isUploadedToNS = false
                debugPrint("ExerciseOverride session \(sessionID) announcement-manager expired recovery")

            case .cancelled:
                override.enabled = false
                override.isUploadedToNS = false

            default:
                break
            }
        }

        if context.hasChanges {
            try? context.save()
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
}
