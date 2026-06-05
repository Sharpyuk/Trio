import CoreData
import Foundation

extension NSPredicate {
    static var allOverridePresets: NSPredicate {
        NSPredicate(format: "isPreset == %@", true as NSNumber)
    }

    static var lastActiveOverride: NSPredicate {
        NSPredicate(
            format: "date <= %@ AND (date >= %@ OR indefinite == %@) AND enabled == %@",
            Date() as NSDate,
            Date().addingTimeInterval(-48 * 60 * 60) as NSDate,
            true as NSNumber,
            true as NSNumber
        )
    }
}

extension OverrideStored {
    static let exerciseModeName = String(localized: "Exercise Mode")
    static let exerciseOverrideName = String(localized: "Exercise Override")
    static let exerciseNameSeparator = " - "

    var isExerciseMode: Bool {
        name == Self.exerciseModeName || exercisePhase != nil
    }

    var currentProteinFatAssist: Bool {
        (name ?? "").hasPrefix("Protein/Fat Assist")
    }

    var exercisePhase: ExercisePhase? {
        guard let name else { return nil }

        if name == Self.exerciseModeName {
            return .duringExercise
        }

        return ExercisePhase.allCases.first { phase in
            name.hasSuffix(Self.exerciseNameSeparator + phase.title)
        }
    }

    var exerciseTypeName: String? {
        guard let name, exercisePhase != nil else { return nil }
        let prefix = Self.exerciseOverrideName + ": "
        guard name.hasPrefix(prefix) else { return nil }

        let withoutPrefix = String(name.dropFirst(prefix.count))
        return withoutPrefix
            .components(separatedBy: Self.exerciseNameSeparator)
            .first
    }

    var exerciseDisplayName: String {
        guard let phase = exercisePhase else {
            return name ?? Self.exerciseOverrideName
        }

        let type = exerciseTypeName ?? String(localized: "Exercise")
        return "\(type) \(phase.shortTitle)"
    }

    var postExerciseSensitivityStartPercent: Decimal {
        start?.decimalValue ?? 0
    }

    var postExerciseSensitivityDecayType: ExerciseSensitivityDecayType {
        ExerciseSensitivityDecayType(rawValue: Int(end?.intValue ?? 0)) ?? .flat
    }

    func effectivePostExerciseSensitivityPercent(at now: Date = Date()) -> Decimal {
        guard exercisePhase == .postExercise,
              let date,
              let activeUntil = activeUntilDate(),
              now >= date,
              now < activeUntil
        else {
            return 0
        }

        let startingPercent = postExerciseSensitivityStartPercent
        guard postExerciseSensitivityDecayType == .linear else {
            return startingPercent
        }

        let totalDuration = activeUntil.timeIntervalSince(date)
        guard totalDuration > 0 else {
            return 0
        }

        let elapsed = now.timeIntervalSince(date)
        let remainingFraction = max(0, min(1, 1 - elapsed / totalDuration))
        return startingPercent * Decimal(remainingFraction)
    }

    static func exerciseOverrideName(type: String, phase: ExercisePhase) -> String {
        "\(exerciseOverrideName): \(type)\(exerciseNameSeparator)\(phase.title)"
    }

    func activeUntilDate() -> Date? {
        guard !indefinite,
              let date,
              let duration
        else {
            return nil
        }

        return date.addingTimeInterval(TimeInterval(duration.doubleValue * 60))
    }

    func isActive(at now: Date = Date()) -> Bool {
        guard enabled, let date, date <= now else {
            return false
        }

        if indefinite {
            return true
        }

        guard let activeUntil = activeUntilDate() else {
            return false
        }

        return activeUntil > now
    }

    static func fetch(_ predicate: NSPredicate, ascending: Bool, fetchLimit: Int? = nil) -> NSFetchRequest<OverrideStored> {
        let request = OverrideStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: ascending)]
        request.predicate = predicate
        if let fetchLimit = fetchLimit {
            request.fetchLimit = fetchLimit
        }
        return request
    }
}

extension OverrideStored {
    enum EventType: String, JSON {
        case nsExercise = "Exercise"
    }
}

enum ExercisePhase: String, CaseIterable {
    case preExercise
    case duringExercise
    case postExercise
    case inactive

    var title: String {
        switch self {
        case .preExercise:
            return String(localized: "Pre-exercise")
        case .duringExercise:
            return String(localized: "Active exercise")
        case .postExercise:
            return String(localized: "Post-exercise recovery")
        case .inactive:
            return String(localized: "Inactive")
        }
    }

    var shortTitle: String {
        switch self {
        case .preExercise:
            return String(localized: "pre")
        case .duringExercise:
            return String(localized: "active")
        case .postExercise:
            return String(localized: "recovery")
        case .inactive:
            return String(localized: "inactive")
        }
    }
}

enum ExerciseSensitivityDecayType: Int, CaseIterable, Identifiable, Codable {
    case flat = 0
    case linear = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .flat:
            return String(localized: "Flat")
        case .linear:
            return String(localized: "Linear decay")
        }
    }
}

struct ExerciseRecoveryRecommendation: Codable, Equatable {
    let durationMinutes: Int
    let sensitivityPercent: Decimal
    let decayType: ExerciseSensitivityDecayType

    var hasRecoveryEffect: Bool {
        durationMinutes > 0 && sensitivityPercent > 0
    }
}

enum ExerciseRecoveryCalculator {
    static func recommendation(forExerciseDurationMinutes minutes: Double) -> ExerciseRecoveryRecommendation {
        let boundedMinutes = max(0, minutes)

        if boundedMinutes < 10 {
            return ExerciseRecoveryRecommendation(durationMinutes: 0, sensitivityPercent: 0, decayType: .linear)
        }

        if boundedMinutes < 30 {
            return ExerciseRecoveryRecommendation(
                durationMinutes: interpolatedInt(minutes: boundedMinutes, from: 10, to: 30, min: 120, max: 240),
                sensitivityPercent: interpolatedDecimal(minutes: boundedMinutes, from: 10, to: 30, min: 5, max: 10),
                decayType: .linear
            )
        }

        if boundedMinutes < 60 {
            return ExerciseRecoveryRecommendation(
                durationMinutes: interpolatedInt(minutes: boundedMinutes, from: 30, to: 60, min: 240, max: 480),
                sensitivityPercent: interpolatedDecimal(minutes: boundedMinutes, from: 30, to: 60, min: 10, max: 20),
                decayType: .linear
            )
        }

        if boundedMinutes < 120 {
            return ExerciseRecoveryRecommendation(
                durationMinutes: interpolatedInt(minutes: boundedMinutes, from: 60, to: 120, min: 480, max: 720),
                sensitivityPercent: interpolatedDecimal(minutes: boundedMinutes, from: 60, to: 120, min: 20, max: 30),
                decayType: .linear
            )
        }

        return ExerciseRecoveryRecommendation(
            durationMinutes: interpolatedInt(minutes: min(boundedMinutes, 360), from: 120, to: 360, min: 720, max: 1440),
            sensitivityPercent: interpolatedDecimal(minutes: min(boundedMinutes, 360), from: 120, to: 360, min: 25, max: 40),
            decayType: .linear
        )
    }

    private static func interpolatedInt(
        minutes: Double,
        from lowerMinutes: Double,
        to upperMinutes: Double,
        min minValue: Int,
        max maxValue: Int
    ) -> Int {
        let fraction = interpolationFraction(minutes: minutes, from: lowerMinutes, to: upperMinutes)
        return Int((Double(minValue) + (Double(maxValue - minValue) * fraction)).rounded())
    }

    private static func interpolatedDecimal(
        minutes: Double,
        from lowerMinutes: Double,
        to upperMinutes: Double,
        min minValue: Double,
        max maxValue: Double
    ) -> Decimal {
        let fraction = interpolationFraction(minutes: minutes, from: lowerMinutes, to: upperMinutes)
        let value = minValue + ((maxValue - minValue) * fraction)
        return Decimal((value * 10).rounded() / 10)
    }

    private static func interpolationFraction(minutes: Double, from lowerMinutes: Double, to upperMinutes: Double) -> Double {
        guard upperMinutes > lowerMinutes else { return 0 }
        return max(0, min(1, (minutes - lowerMinutes) / (upperMinutes - lowerMinutes)))
    }
}

enum ExerciseType: String, CaseIterable, Identifiable {
    case run = "Run"
    case longRun = "Long run"
    case ultraRun = "Ultra run"
    case walk = "Walk"
    case hike = "Hike"
    case cycle = "Cycle"
    case strengthTraining = "Strength training"
    case custom = "Custom"

    var id: String { rawValue }
}
