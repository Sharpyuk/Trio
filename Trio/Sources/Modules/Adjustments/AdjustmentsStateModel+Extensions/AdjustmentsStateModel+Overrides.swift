import Combine
import CoreData
import Foundation
import SwiftUI

struct ExerciseReport: Codable, Identifiable {
    struct PhaseConfiguration: Codable {
        let basalPercentage: Double
        let target: Decimal?
        let smbSuppressed: Bool
    }

    struct GlucoseStats: Codable {
        let bgAtPreExerciseStart: Int?
        let bgAtExerciseStart: Int?
        let bgAtExerciseEnd: Int?
        let bgAtRecoveryEnd: Int?
        let minBGDuringExercise: Int?
        let maxBGDuringExercise: Int?
        let averageBGDuringExercise: Decimal?
        let glucoseTrendBeforeExercise: Decimal?
        let glucoseTrendAfterExercise: Decimal?
    }

    struct InsulinStats: Codable {
        let iobAtPreExerciseStart: Decimal?
        let iobAtExerciseStart: Decimal?
        let iobAtExerciseEnd: Decimal?
        let iobAtRecoveryEnd: Decimal?
        let basalDeliveredDuringPreExercise: Decimal?
        let basalDeliveredDuringExercise: Decimal?
        let basalDeliveredDuringRecovery: Decimal?
        let preExerciseSMBSuppressed: Bool
        let exerciseSMBSuppressed: Bool
        let recoverySMBSuppressed: Bool
        let bolusesDeliveredDuringSession: Decimal?
    }

    struct AnnouncementStats: Codable {
        let announceGlucoseEnabled: Bool
        let announcementInterval: Decimal
        let includeTrend: Bool
        let includeRateOfChange: Bool
        let urgentAnnouncementsEnabled: Bool
        let numberOfAnnouncementsMade: Int
    }

    let id: String
    let createdAt: Date
    let exerciseType: String
    let customExerciseTypeName: String?
    let preExerciseStartTime: Date?
    let exerciseStartTime: Date
    let exerciseStopTime: Date
    let actualExerciseDurationMinutes: Decimal
    let startedAutomatically: Bool
    let startedEarly: Bool
    let wasCancelled: Bool
    let recoverySkippedReason: String?
    let recoveryDurationCalculatedMinutes: Int
    let recoverySensitivityAdjustmentCalculated: Decimal
    let decayModelUsed: ExerciseSensitivityDecayType
    let preExerciseConfiguration: PhaseConfiguration?
    let exerciseConfiguration: PhaseConfiguration
    let recoveryConfiguration: PhaseConfiguration?
    let announcementStats: AnnouncementStats
    let glucoseStats: GlucoseStats
    let insulinStats: InsulinStats
}

enum ExerciseReportStore {
    static var reportsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("ExerciseReports", isDirectory: true)
    }

    static func save(_ report: ExerciseReport) throws -> URL {
        try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        let url = reportsDirectory.appendingPathComponent("exercise-report-\(report.id).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url, options: .atomic)
        return url
    }

    static func loadReports() -> [ExerciseReport] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: reportsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(ExerciseReport.self, from: $0) }
            .sorted { $0.exerciseStopTime > $1.exerciseStopTime }
    }

    static func loadReport(sessionID: String) -> ExerciseReport? {
        loadReports().first { $0.id == sessionID }
    }

    static func exportURL(for report: ExerciseReport) throws -> URL {
        try save(report)
    }

    static func csvURL(for report: ExerciseReport) throws -> URL {
        try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        let url = reportsDirectory.appendingPathComponent("exercise-report-\(report.id).csv")
        let rows = [
            ["field", "value"],
            ["exerciseType", report.exerciseType],
            ["preExerciseStartTime", report.preExerciseStartTime?.ISO8601Format() ?? ""],
            ["exerciseStartTime", report.exerciseStartTime.ISO8601Format()],
            ["exerciseStopTime", report.exerciseStopTime.ISO8601Format()],
            ["actualExerciseDurationMinutes", "\(report.actualExerciseDurationMinutes)"],
            ["recoveryDurationCalculatedMinutes", "\(report.recoveryDurationCalculatedMinutes)"],
            ["recoverySensitivityAdjustmentCalculated", "\(report.recoverySensitivityAdjustmentCalculated)"],
            ["decayModelUsed", report.decayModelUsed.title]
        ]
        let csv = rows.map { $0.map(csvEscape).joined(separator: ",") }.joined(separator: "\n")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

extension Adjustments.StateModel {
    // MARK: - Enact Overrides

    /// Enacts an Override Preset by enabling it and disabling others.
    @MainActor func enactOverridePreset(withID id: NSManagedObjectID) async {
        do {
            guard let overrideToEnact = try viewContext.existingObject(with: id) as? OverrideStored else { return }
            /// Wait for currently active override to be disabled before storing the new one
            await disableAllActiveOverrides(createOverrideRunEntry: currentActiveOverride != nil)
            await resetStateVariables()

            overrideToEnact.enabled = true
            overrideToEnact.date = Date()
            overrideToEnact.isUploadedToNS = false
            isOverrideEnabled = true

            guard viewContext.hasChanges else { return }
            try viewContext.save()

            updateLatestOverrideConfiguration()
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to enact Override Preset")
        }
    }

    // MARK: - Disable Overrides

    /// Disables all active Overrides, optionally creating a run entry.
    @MainActor func disableAllActiveOverrides(
        except overrideID: NSManagedObjectID? = nil,
        createOverrideRunEntry: Bool
    ) async {
        do {
            // Get ALL NSManagedObject IDs of ALL active Override to cancel every single Override
            let ids = try await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0)

            try await viewContext.perform {
                // Fetch the existing OverrideStored objects from the context
                let results = try ids.compactMap { id in
                    try self.viewContext.existingObject(with: id) as? OverrideStored
                }
                guard !results.isEmpty else { return }

                // Check if we also need to create a corresponding OverrideRunStored entry
                if createOverrideRunEntry {
                    // Use the first override to create a new OverrideRunStored entry
                    if let canceledOverride = results.first {
                        let newOverrideRunStored = OverrideRunStored(context: self.viewContext)
                        newOverrideRunStored.id = canceledOverride
                            .exercisePhase == .inactive ? UUID() : (UUID(uuidString: canceledOverride.id ?? "") ?? UUID())
                        newOverrideRunStored.name = canceledOverride.name
                        newOverrideRunStored.startDate = canceledOverride.date ?? .distantPast
                        newOverrideRunStored.endDate = Date()
                        newOverrideRunStored.target = NSDecimalNumber(
                            decimal: self.overrideStorage.calculateTarget(override: canceledOverride)
                        )
                        newOverrideRunStored.override = canceledOverride
                        newOverrideRunStored.isUploadedToNS = false
                    }
                }

                // Disable all overrides except the one with overrideID
                for overrideToCancel in results where overrideToCancel.objectID != overrideID {
                    overrideToCancel.enabled = false
                }

                if self.viewContext.hasChanges {
                    // Save changes and update the View
                    try self.viewContext.save()
                    ExerciseGlucoseAnnouncementManager.shared.stopSpeech()
                    self.updateLatestOverrideConfiguration()
                }
            }
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to disable active overrides: \(error)"
            )
        }
    }

    // MARK: - Save Overrides

    /// Saves a custom Override and activates it.
    func saveCustomOverride() async {
        do {
            let override = Override(
                name: overrideName,
                enabled: true,
                date: Date(),
                duration: overrideDuration,
                indefinite: indefinite,
                percentage: overridePercentage,
                smbIsOff: smbIsOff,
                isPreset: isPreset,
                id: id,
                overrideTarget: shouldOverrideTarget,
                target: target,
                advancedSettings: advancedSettings,
                isfAndCr: isfAndCr,
                isf: isf,
                cr: cr,
                smbIsScheduledOff: smbIsScheduledOff,
                start: start,
                end: end,
                smbMinutes: smbMinutes,
                uamMinutes: uamMinutes
            )

            // First disable all Overrides
            await disableAllActiveOverrides(createOverrideRunEntry: true)

            // Then save and activate a new custom Override
            try await overrideStorage.storeOverride(override: override)

            // Reset State variables
            await resetStateVariables()

            // Update View
            updateLatestOverrideConfiguration()
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to save custom override: \(error)"
            )
        }
    }

    /// Saves an Override Preset without activating it.
    /// `enabled` has to be false
    /// `isPreset` has to be true
    func saveOverridePreset() async {
        do {
            let preset = Override(
                name: overrideName,
                enabled: false,
                date: Date(),
                duration: overrideDuration,
                indefinite: indefinite,
                percentage: overridePercentage,
                smbIsOff: smbIsOff,
                isPreset: true,
                id: id,
                overrideTarget: shouldOverrideTarget,
                target: target,
                advancedSettings: advancedSettings,
                isfAndCr: isfAndCr,
                isf: isf,
                cr: cr,
                smbIsScheduledOff: smbIsScheduledOff,
                start: start,
                end: end,
                smbMinutes: smbMinutes,
                uamMinutes: uamMinutes
            )

            async let storeOverride: () = overrideStorage.storeOverride(override: preset)
            async let resetState: () = resetStateVariables()
            _ = try await (storeOverride, resetState)

            setupOverridePresetsArray()
            try await nightscoutManager.uploadProfiles()
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to save override preset: \(error)"
            )
        }
    }

    func saveExerciseMode() async {
        do {
            let now = Date()
            let sessionID = UUID().uuidString
            let exerciseTypeName = resolvedExerciseTypeName

            let preMinutes = preExerciseEnabled ? NSDecimalNumber(decimal: preExerciseDuration).doubleValue : 0
            let scheduledExerciseStart: Date = {
                if exerciseStartDate <= now.addingTimeInterval(60), preExerciseEnabled, preMinutes > 0 {
                    return now.addingTimeInterval(preMinutes * 60)
                }
                return exerciseStartDate <= now.addingTimeInterval(60) ? now : exerciseStartDate
            }()
            let plannedPreStart = preExerciseEnabled && preMinutes > 0
                ? scheduledExerciseStart.addingTimeInterval(-preMinutes * 60)
                : scheduledExerciseStart

            let initialPhase: ExercisePhase
            let initialStart: Date
            let initialDuration: Decimal
            let initialBasal: Double
            let initialSMB: Bool
            let initialTarget: Decimal

            if preExerciseEnabled, preMinutes > 0, now < scheduledExerciseStart {
                initialPhase = .preExercise
                initialStart = max(plannedPreStart, now)
                initialDuration = Decimal(max(1, scheduledExerciseStart.timeIntervalSince(initialStart) / 60))
                initialBasal = preExerciseBasalPercentage
                initialSMB = preExerciseSuppressSMB
                initialTarget = preExerciseTarget
            } else {
                initialPhase = .duringExercise
                initialStart = scheduledExerciseStart <= now.addingTimeInterval(60) ? now : scheduledExerciseStart
                initialDuration = 2160
                initialBasal = exerciseBasalPercentage
                initialSMB = exerciseSuppressSMB
                initialTarget = exerciseTarget
            }

            if initialStart <= now.addingTimeInterval(60) {
                await disableAllActiveOverrides(createOverrideRunEntry: true)
            }

            try await overrideStorage.storeOverride(override: exerciseOverride(
                sessionID: sessionID,
                exerciseTypeName: exerciseTypeName,
                phase: initialPhase,
                startDate: initialStart,
                duration: initialDuration,
                basalPercentage: initialBasal,
                suppressSMB: initialSMB,
                target: initialTarget
            ))

            try ExerciseSessionMetadataStore.save(ExerciseSessionMetadata(
                sessionID: sessionID,
                exerciseTypeName: exerciseTypeName,
                sessionCreatedAt: now,
                scheduledExerciseStart: scheduledExerciseStart,
                preExerciseStart: plannedPreStart,
                actualExerciseStart: initialPhase == .duringExercise ? initialStart : nil,
                preExerciseEnabled: preExerciseEnabled,
                preExerciseDurationMinutes: preExerciseDuration,
                preExerciseSettings: ExerciseSessionMetadata.PhaseSettings(
                    basalPercentage: preExerciseBasalPercentage,
                    target: preExerciseTarget,
                    suppressSMB: preExerciseSuppressSMB
                ),
                exerciseSettings: ExerciseSessionMetadata.PhaseSettings(
                    basalPercentage: exerciseBasalPercentage,
                    target: exerciseTarget,
                    suppressSMB: exerciseSuppressSMB
                ),
                postExerciseEnabled: postExerciseEnabled,
                postExerciseBasalPercentage: postExerciseBasalPercentage,
                postExerciseTarget: postExerciseTarget,
                postExerciseSuppressSMB: postExerciseSuppressSMB,
                announcementSettings: ExerciseAnnouncementSettings(
                    enabled: announceGlucoseDuringExercise,
                    intervalMinutes: announcementInterval,
                    includeTrend: announcementIncludeTrend,
                    includeRateOfChange: announcementIncludeRateOfChange,
                    urgentAnnouncementsEnabled: announcementUrgentEnabled,
                    lowThresholdMgdl: announcementLowThreshold,
                    highThresholdMgdl: announcementHighThreshold,
                    units: units,
                    announcementsMade: 0
                )
            ))
            debugPrint(
                "ExerciseOverride session \(sessionID) created phase=\(initialPhase.rawValue) scheduled=\(scheduledExerciseStart)"
            )
            ExerciseGlucoseAnnouncementManager.shared.startMonitoring()

            await resetExerciseModeState()
            setupScheduledExerciseOverridesArray()
            updateLatestOverrideConfiguration()
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to save exercise mode: \(error)"
            )
        }
    }

    @MainActor func startExerciseNow(_ objectID: NSManagedObjectID) async {
        do {
            guard let preExerciseOverride = try viewContext.existingObject(with: objectID) as? OverrideStored,
                  preExerciseOverride.exercisePhase == .preExercise,
                  let sessionID = preExerciseOverride.id
            else {
                return
            }

            let now = Date()
            if let preStartedAt = preExerciseOverride.date,
               let metadata = ExerciseSessionMetadataStore.load(sessionID: sessionID)
            {
                let settings = metadata.exerciseSettings
                preExerciseOverride.name = OverrideStored.exerciseOverrideName(
                    type: preExerciseOverride.exerciseTypeName ?? metadata.exerciseTypeName,
                    phase: .duringExercise
                )
                preExerciseOverride.date = now
                preExerciseOverride.duration = 2160
                preExerciseOverride.percentage = settings?.basalPercentage ?? exerciseBasalPercentage
                preExerciseOverride.smbIsOff = settings?.suppressSMB ?? exerciseSuppressSMB
                preExerciseOverride.target = (settings?.target ?? exerciseTarget) as NSDecimalNumber
            }
            preExerciseOverride.isUploadedToNS = false
            ExerciseSessionMetadataStore.update(sessionID: sessionID) {
                $0.actualExerciseStart = now
            }
            debugPrint("ExerciseOverride session \(sessionID) manual-start at \(now)")

            guard viewContext.hasChanges else { return }
            try viewContext.save()
            setupScheduledExerciseOverridesArray()
            updateLatestOverrideConfiguration()
            ExerciseGlucoseAnnouncementManager.shared.startMonitoring()
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to start Exercise Override early: \(error)"
            )
        }
    }

    private var resolvedExerciseTypeName: String {
        if exerciseType == .custom {
            let customName = customExerciseTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
            return customName.isEmpty ? ExerciseType.custom.rawValue : customName
        }

        return exerciseType.rawValue
    }

    private func exerciseOverride(
        sessionID: String,
        exerciseTypeName: String,
        phase: ExercisePhase,
        startDate: Date,
        duration: Decimal,
        basalPercentage: Double,
        suppressSMB: Bool,
        target: Decimal,
        sensitivityPercent: Decimal = 0,
        decayType: ExerciseSensitivityDecayType = .flat
    ) -> Override {
        Override(
            name: OverrideStored.exerciseOverrideName(type: exerciseTypeName, phase: phase),
            enabled: true,
            date: startDate,
            duration: duration,
            indefinite: false,
            percentage: basalPercentage,
            smbIsOff: suppressSMB,
            isPreset: false,
            id: sessionID,
            overrideTarget: true,
            target: target,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: sensitivityPercent,
            end: Decimal(decayType.rawValue),
            smbMinutes: defaultSmbMinutes,
            uamMinutes: defaultUamMinutes
        )
    }

    // MARK: - Override Preset Management

    /// Sets up the array of Override Presets for UI display.
    func setupOverridePresetsArray() {
        Task {
            do {
                let ids = try await overrideStorage.fetchForOverridePresets()
                await updateOverridePresetsArray(with: ids)
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Failed to setup override presets: \(error)"
                )
            }
        }
    }

    func setupScheduledExerciseOverridesArray() {
        Task {
            do {
                await advanceExerciseSessionsIfNeeded()
                let ids = try await overrideStorage.fetchScheduledExerciseOverrides()
                await updateScheduledExerciseOverridesArray(with: ids)
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Failed to setup scheduled exercise overrides: \(error)"
                )
            }
        }
    }

    @MainActor func advanceExerciseSessionsIfNeeded() async {
        do {
            let request: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            request.predicate = NSPredicate(
                format: "enabled == %@ AND name BEGINSWITH %@",
                true as NSNumber,
                OverrideStored.exerciseOverrideName + ":"
            )
            let overrides = try viewContext.fetch(request)
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
                    override.percentage = settings?.basalPercentage ?? exerciseBasalPercentage
                    override.smbIsOff = settings?.suppressSMB ?? exerciseSuppressSMB
                    override.target = (settings?.target ?? exerciseTarget) as NSDecimalNumber
                    override.isUploadedToNS = false
                    metadata.actualExerciseStart = override.date
                    try? ExerciseSessionMetadataStore.save(metadata)
                    debugPrint("ExerciseOverride session \(sessionID) auto-start at \(override.date ?? now)")

                case .exerciseActive where override.exercisePhase == .duringExercise && metadata.actualExerciseStart == nil:
                    metadata.actualExerciseStart = override.date ?? now
                    try? ExerciseSessionMetadataStore.save(metadata)
                    debugPrint("ExerciseOverride session \(sessionID) marked active at \(metadata.actualExerciseStart ?? now)")

                case .completed where override.exercisePhase == .postExercise:
                    override.enabled = false
                    override.isUploadedToNS = false
                    debugPrint("ExerciseOverride session \(sessionID) recovery expired")

                default:
                    break
                }
            }

            if viewContext.hasChanges {
                try viewContext.save()
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to advance Exercise Override sessions: \(error)"
            )
        }
    }

    /// Updates the array of Override Presets from Core Data.
    @MainActor private func updateOverridePresetsArray(with IDs: [NSManagedObjectID]) async {
        do {
            let overrideObjects = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? OverrideStored
            }
            overridePresets = overrideObjects
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to extract Overrides: \(error)"
            )
        }
    }

    @MainActor private func updateScheduledExerciseOverridesArray(with IDs: [NSManagedObjectID]) async {
        do {
            scheduledExerciseOverrides = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? OverrideStored
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to extract scheduled Exercise Modes: \(error)"
            )
        }
    }

    @MainActor func cancelScheduledExerciseOverride(_ objectID: NSManagedObjectID) async {
        do {
            guard let exerciseOverride = try viewContext.existingObject(with: objectID) as? OverrideStored else {
                return
            }

            let sessionID = exerciseOverride.id
            let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            if let sessionID {
                fetchRequest.predicate = NSPredicate(format: "id == %@", sessionID)
            } else {
                fetchRequest.predicate = NSPredicate(format: "self == %@", exerciseOverride)
            }

            let sessionOverrides = try viewContext.fetch(fetchRequest)
            for sessionOverride in sessionOverrides {
                sessionOverride.enabled = false
                sessionOverride.isUploadedToNS = false
            }
            if let sessionID {
                let cancelledAt = Date()
                ExerciseSessionMetadataStore.update(sessionID: sessionID) {
                    $0.cancelledAt = cancelledAt
                    if $0.actualExerciseStart != nil, $0.actualExerciseEnd == nil {
                        $0.actualExerciseEnd = cancelledAt
                    }
                    $0.recoverySkippedReason = "cancelled"
                }
                if let activeExercise = sessionOverrides.first(where: { $0.exercisePhase == .duringExercise && $0.date != nil }) {
                    let cancelledDurationMinutes = max(0, cancelledAt.timeIntervalSince(activeExercise.date ?? cancelledAt) / 60)
                    activeExercise.duration = Decimal(max(1, cancelledDurationMinutes)) as NSDecimalNumber
                    try? createExerciseReport(
                        sessionID: sessionID,
                        sessionOverrides: sessionOverrides,
                        exerciseOverride: activeExercise,
                        stopTime: cancelledAt,
                        recoveryRecommendation: ExerciseRecoveryRecommendation(
                            durationMinutes: 0,
                            sensitivityPercent: 0,
                            decayType: .linear
                        )
                    )
                }
                ExerciseGlucoseAnnouncementManager.shared.stopSpeech()
                debugPrint("ExerciseOverride session \(sessionID) cancelled")
            }

            guard viewContext.hasChanges else { return }
            try viewContext.save()
            setupScheduledExerciseOverridesArray()
            updateLatestOverrideConfiguration()
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to cancel scheduled Exercise Mode: \(error)"
            )
        }
    }

    @MainActor func stopExerciseNow(_ objectID: NSManagedObjectID) async {
        do {
            guard let exerciseOverride = try viewContext.existingObject(with: objectID) as? OverrideStored,
                  exerciseOverride.exercisePhase == .duringExercise,
                  let sessionID = exerciseOverride.id
            else {
                return
            }

            let now = Date()
            let exerciseStartedAt = exerciseOverride.date ?? now
            let actualDurationMinutes = max(0, now.timeIntervalSince(exerciseStartedAt) / 60)
            exerciseOverride.duration = Decimal(max(1, actualDurationMinutes)) as NSDecimalNumber
            exerciseOverride.enabled = false

            let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", sessionID)
            let sessionOverrides = try viewContext.fetch(fetchRequest)

            for sessionOverride in sessionOverrides where sessionOverride.exercisePhase == .postExercise {
                sessionOverride.enabled = false
                sessionOverride.isUploadedToNS = false
            }
            exerciseOverride.isUploadedToNS = false
            ExerciseGlucoseAnnouncementManager.shared.stopSpeech()

            let metadata = ExerciseSessionMetadataStore.load(sessionID: sessionID)
            let shouldCreateRecovery = metadata?.postExerciseEnabled ?? postExerciseEnabled
            let recoveryBasalPercentage = metadata?.postExerciseBasalPercentage ?? postExerciseBasalPercentage
            let recoveryTarget = metadata?.postExerciseTarget ?? postExerciseTarget
            let recoverySuppressSMB = metadata?.postExerciseSuppressSMB ?? postExerciseSuppressSMB

            let recoveryRecommendation = shouldCreateRecovery
                ? ExerciseRecoveryCalculator.recommendation(forExerciseDurationMinutes: actualDurationMinutes)
                : ExerciseRecoveryRecommendation(durationMinutes: 0, sensitivityPercent: 0, decayType: .linear)

            ExerciseSessionMetadataStore.update(sessionID: sessionID) {
                $0.actualExerciseEnd = now
                if recoveryRecommendation.hasRecoveryEffect {
                    $0.recoveryStart = now
                    $0.recoveryEnd = now.addingTimeInterval(TimeInterval(recoveryRecommendation.durationMinutes * 60))
                    $0.recoverySkippedReason = nil
                } else {
                    $0.recoveryStart = nil
                    $0.recoveryEnd = nil
                    if !shouldCreateRecovery {
                        $0.recoverySkippedReason = "recoveryDisabled"
                    } else if actualDurationMinutes < 10 {
                        $0.recoverySkippedReason = "exerciseDurationBelowMinimum"
                    } else {
                        $0.recoverySkippedReason = "noRecoveryEffect"
                    }
                }
            }
            debugPrint(
                "ExerciseOverride session \(sessionID) stopped duration=\(actualDurationMinutes) recovery=\(recoveryRecommendation.durationMinutes)m sensitivity=\(recoveryRecommendation.sensitivityPercent)"
            )

            if recoveryRecommendation.hasRecoveryEffect {
                let recoveryOverride = self.exerciseOverride(
                    sessionID: sessionID,
                    exerciseTypeName: exerciseOverride.exerciseTypeName ?? resolvedExerciseTypeName,
                    phase: .postExercise,
                    startDate: now,
                    duration: Decimal(recoveryRecommendation.durationMinutes),
                    basalPercentage: recoveryBasalPercentage,
                    suppressSMB: recoverySuppressSMB,
                    target: recoveryTarget,
                    sensitivityPercent: recoveryRecommendation.sensitivityPercent,
                    decayType: recoveryRecommendation.decayType
                )
                try await overrideStorage.storeOverride(override: recoveryOverride)
                debugPrint("ExerciseOverride session \(sessionID) recovery-start at \(now)")
            }

            try? createExerciseReport(
                sessionID: sessionID,
                sessionOverrides: sessionOverrides,
                exerciseOverride: exerciseOverride,
                stopTime: now,
                recoveryRecommendation: recoveryRecommendation
            )

            guard viewContext.hasChanges else {
                setupScheduledExerciseOverridesArray()
                updateLatestOverrideConfiguration()
                return
            }
            try viewContext.save()
            setupScheduledExerciseOverridesArray()
            updateLatestOverrideConfiguration()
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to stop Exercise Override: \(error)"
            )
        }
    }

    @MainActor private func createExerciseReport(
        sessionID: String,
        sessionOverrides: [OverrideStored],
        exerciseOverride: OverrideStored,
        stopTime: Date,
        recoveryRecommendation: ExerciseRecoveryRecommendation
    ) throws {
        let preOverride = sessionOverrides.first { $0.exercisePhase == .preExercise }
        let exerciseStart = exerciseOverride.date ?? stopTime
        let metadata = ExerciseSessionMetadataStore.load(sessionID: sessionID)
        let preStart = preOverride?.date ?? metadata?.preExerciseStart
        let actualDurationMinutes = Decimal(max(0, stopTime.timeIntervalSince(exerciseStart) / 60))
        let exerciseTypeName = exerciseOverride.exerciseTypeName ?? resolvedExerciseTypeName

        let glucoseStats = exerciseGlucoseStats(
            preStart: preStart,
            exerciseStart: exerciseStart,
            exerciseEnd: stopTime,
            recoveryEnd: recoveryRecommendation.hasRecoveryEffect
                ? stopTime.addingTimeInterval(TimeInterval(recoveryRecommendation.durationMinutes * 60))
                : nil
        )
        let insulinStats = exerciseInsulinStats(
            preStart: preStart,
            exerciseStart: exerciseStart,
            exerciseEnd: stopTime,
            recoveryEnd: recoveryRecommendation.hasRecoveryEffect
                ? stopTime.addingTimeInterval(TimeInterval(recoveryRecommendation.durationMinutes * 60))
                : nil,
            preOverride: preOverride,
            exerciseOverride: exerciseOverride
        )
        let shouldCreateRecovery = metadata?.postExerciseEnabled ?? postExerciseEnabled
        let recoveryBasalPercentage = metadata?.postExerciseBasalPercentage ?? postExerciseBasalPercentage
        let recoveryTarget = metadata?.postExerciseTarget ?? postExerciseTarget
        let recoverySuppressSMB = metadata?.postExerciseSuppressSMB ?? postExerciseSuppressSMB
        let announcementSettings = metadata?.announcementSettings ?? ExerciseAnnouncementSettings(
            enabled: announceGlucoseDuringExercise,
            intervalMinutes: announcementInterval,
            includeTrend: announcementIncludeTrend,
            includeRateOfChange: announcementIncludeRateOfChange,
            urgentAnnouncementsEnabled: announcementUrgentEnabled,
            lowThresholdMgdl: announcementLowThreshold,
            highThresholdMgdl: announcementHighThreshold,
            units: units,
            announcementsMade: 0
        )

        let report = ExerciseReport(
            id: sessionID,
            createdAt: Date(),
            exerciseType: exerciseTypeName,
            customExerciseTypeName: exerciseType == .custom ? customExerciseTypeName : nil,
            preExerciseStartTime: preStart,
            exerciseStartTime: exerciseStart,
            exerciseStopTime: stopTime,
            actualExerciseDurationMinutes: actualDurationMinutes,
            startedAutomatically: preOverride?.activeUntilDate() == exerciseStart,
            startedEarly: preOverride?.activeUntilDate() != nil && preOverride?.activeUntilDate() != exerciseStart,
            wasCancelled: metadata?.cancelledAt != nil,
            recoverySkippedReason: metadata?.recoverySkippedReason,
            recoveryDurationCalculatedMinutes: recoveryRecommendation.durationMinutes,
            recoverySensitivityAdjustmentCalculated: recoveryRecommendation.sensitivityPercent,
            decayModelUsed: recoveryRecommendation.decayType,
            preExerciseConfiguration: preOverride.map {
                ExerciseReport.PhaseConfiguration(
                    basalPercentage: $0.percentage,
                    target: $0.target?.decimalValue,
                    smbSuppressed: $0.smbIsOff
                )
            } ?? metadata?.preExerciseSettings.map {
                ExerciseReport.PhaseConfiguration(
                    basalPercentage: $0.basalPercentage,
                    target: $0.target,
                    smbSuppressed: $0.suppressSMB
                )
            },
            exerciseConfiguration: ExerciseReport.PhaseConfiguration(
                basalPercentage: exerciseOverride.percentage,
                target: exerciseOverride.target?.decimalValue,
                smbSuppressed: exerciseOverride.smbIsOff
            ),
            recoveryConfiguration: shouldCreateRecovery ? ExerciseReport.PhaseConfiguration(
                basalPercentage: recoveryBasalPercentage,
                target: recoveryTarget,
                smbSuppressed: recoverySuppressSMB
            ) : nil,
            announcementStats: ExerciseReport.AnnouncementStats(
                announceGlucoseEnabled: announcementSettings.enabled,
                announcementInterval: announcementSettings.intervalMinutes,
                includeTrend: announcementSettings.includeTrend,
                includeRateOfChange: announcementSettings.includeRateOfChange,
                urgentAnnouncementsEnabled: announcementSettings.urgentAnnouncementsEnabled,
                numberOfAnnouncementsMade: announcementSettings.announcementsMade
            ),
            glucoseStats: glucoseStats,
            insulinStats: insulinStats
        )

        _ = try ExerciseReportStore.save(report)
    }

    @MainActor private func exerciseGlucoseStats(
        preStart: Date?,
        exerciseStart: Date,
        exerciseEnd: Date,
        recoveryEnd: Date?
    ) -> ExerciseReport.GlucoseStats {
        let exerciseReadings = glucoseReadings(from: exerciseStart, to: exerciseEnd)
        let values = exerciseReadings.map { Int($0.glucose) }
        let average = values.isEmpty ? nil : Decimal(values.reduce(0, +)) / Decimal(values.count)

        return ExerciseReport.GlucoseStats(
            bgAtPreExerciseStart: preStart.flatMap { nearestGlucose(to: $0).map { Int($0.glucose) } },
            bgAtExerciseStart: nearestGlucose(to: exerciseStart).map { Int($0.glucose) },
            bgAtExerciseEnd: nearestGlucose(to: exerciseEnd).map { Int($0.glucose) },
            bgAtRecoveryEnd: recoveryEnd.flatMap { nearestGlucose(to: $0).map { Int($0.glucose) } },
            minBGDuringExercise: values.min(),
            maxBGDuringExercise: values.max(),
            averageBGDuringExercise: average,
            glucoseTrendBeforeExercise: glucoseTrend(endingAt: exerciseStart),
            glucoseTrendAfterExercise: glucoseTrend(startingAt: exerciseEnd)
        )
    }

    @MainActor private func exerciseInsulinStats(
        preStart: Date?,
        exerciseStart: Date,
        exerciseEnd: Date,
        recoveryEnd: Date?,
        preOverride: OverrideStored?,
        exerciseOverride: OverrideStored
    ) -> ExerciseReport.InsulinStats {
        let determinations = determinations(from: preStart ?? exerciseStart, to: recoveryEnd ?? exerciseEnd)
        let boluses = determinations.compactMap { $0.smbToDeliver?.decimalValue }
        let totalBoluses = boluses.isEmpty ? nil : boluses.reduce(0, +)

        return ExerciseReport.InsulinStats(
            iobAtPreExerciseStart: preStart.flatMap { nearestDetermination(to: $0)?.iob?.decimalValue },
            iobAtExerciseStart: nearestDetermination(to: exerciseStart)?.iob?.decimalValue,
            iobAtExerciseEnd: nearestDetermination(to: exerciseEnd)?.iob?.decimalValue,
            iobAtRecoveryEnd: recoveryEnd.flatMap { nearestDetermination(to: $0)?.iob?.decimalValue },
            basalDeliveredDuringPreExercise: nil,
            basalDeliveredDuringExercise: nil,
            basalDeliveredDuringRecovery: nil,
            preExerciseSMBSuppressed: preOverride?.smbIsOff ?? ExerciseSessionMetadataStore
                .load(sessionID: exerciseOverride.id ?? "")?.preExerciseSettings?.suppressSMB ?? false,
            exerciseSMBSuppressed: exerciseOverride.smbIsOff,
            recoverySMBSuppressed: ExerciseSessionMetadataStore
                .load(sessionID: exerciseOverride.id ?? "")?.postExerciseSuppressSMB ?? postExerciseSuppressSMB,
            bolusesDeliveredDuringSession: totalBoluses
        )
    }

    @MainActor private func nearestGlucose(to date: Date) -> GlucoseStored? {
        let request = GlucoseStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: false)]
        request.predicate = NSPredicate(
            format: "date >= %@ AND date <= %@",
            date.addingTimeInterval(-15 * 60) as NSDate,
            date.addingTimeInterval(15 * 60) as NSDate
        )
        return try? viewContext.fetch(request).min {
            abs(($0.date ?? .distantPast).timeIntervalSince(date)) < abs(($1.date ?? .distantPast).timeIntervalSince(date))
        }
    }

    @MainActor private func glucoseReadings(from start: Date, to end: Date) -> [GlucoseStored] {
        let request = GlucoseStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: true)]
        request.predicate = NSPredicate(format: "date >= %@ AND date <= %@", start as NSDate, end as NSDate)
        return (try? viewContext.fetch(request)) ?? []
    }

    @MainActor private func nearestDetermination(to date: Date) -> OrefDetermination? {
        let request = OrefDetermination.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \OrefDetermination.deliverAt, ascending: false)]
        request.predicate = NSPredicate(
            format: "deliverAt >= %@ AND deliverAt <= %@",
            date.addingTimeInterval(-20 * 60) as NSDate,
            date.addingTimeInterval(20 * 60) as NSDate
        )
        return try? viewContext.fetch(request).min {
            abs(($0.deliverAt ?? .distantPast).timeIntervalSince(date)) <
                abs(($1.deliverAt ?? .distantPast).timeIntervalSince(date))
        }
    }

    @MainActor private func determinations(from start: Date, to end: Date) -> [OrefDetermination] {
        let request = OrefDetermination.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \OrefDetermination.deliverAt, ascending: true)]
        request.predicate = NSPredicate(format: "deliverAt >= %@ AND deliverAt <= %@", start as NSDate, end as NSDate)
        return (try? viewContext.fetch(request)) ?? []
    }

    @MainActor private func glucoseTrend(endingAt date: Date) -> Decimal? {
        let readings = glucoseReadings(from: date.addingTimeInterval(-30 * 60), to: date)
        guard let first = readings.first, let last = readings.last, first.date != last.date else { return nil }
        return Decimal(Int(last.glucose) - Int(first.glucose))
    }

    @MainActor private func glucoseTrend(startingAt date: Date) -> Decimal? {
        let readings = glucoseReadings(from: date, to: date.addingTimeInterval(30 * 60))
        guard let first = readings.first, let last = readings.last, first.date != last.date else { return nil }
        return Decimal(Int(last.glucose) - Int(first.glucose))
    }

    /// Deletes an Override Preset and updates the view.
    func invokeOverridePresetDeletion(_ objectID: NSManagedObjectID) async {
        do {
            await overrideStorage.deleteOverridePreset(objectID)
            setupOverridePresetsArray()
            try await nightscoutManager.uploadProfiles()
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to delete override preset: \(error)"
            )
        }
    }

    // MARK: - Update Latest Override Configuration

    /// Updates the latest Override configuration and state.
    /// First get the latest Overrides corresponding NSManagedObjectID with a background fetch
    /// Then unpack it on the view context and update the State variables which can be used on in the View for some Logic
    /// This also needs to be called when we cancel an Override via the Home View to update the State of the Button for this case
    func updateLatestOverrideConfiguration() {
        Task { [weak self] in
            do {
                guard let self = self else { return }

                await self.advanceExerciseSessionsIfNeeded()
                let id = try await self.overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 1)

                // execute sequentially instead of concurrently
                await self.updateLatestOverrideConfigurationOfState(from: id)
                await self.setCurrentOverride(from: id)

                // perform determine basal sync to immediately apply override changes
                try await apsManager.determineBasalSync()
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Failed to update override configuration: \(error)"
                )
            }
        }
    }

    /// Updates state variables with the latest Override configuration.
    @MainActor func updateLatestOverrideConfigurationOfState(from IDs: [NSManagedObjectID]) async {
        do {
            let result = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? OverrideStored
            }
            isOverrideEnabled = result.first?.enabled ?? false
            if !isOverrideEnabled {
                await resetStateVariables()
            }
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update latest Override configuration")
        }
    }

    /// Sets the current active Override for UI purposes.
    @MainActor func setCurrentOverride(from IDs: [NSManagedObjectID]) async {
        do {
            guard let firstID = IDs.first else {
                activeOverrideName = "Custom Override"
                currentActiveOverride = nil
                return
            }

            if let overrideToEdit = try viewContext.existingObject(with: firstID) as? OverrideStored {
                currentActiveOverride = overrideToEdit
                activeOverrideName = overrideToEdit.name ?? String(localized: "Custom Override")
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to set active Override: \(error)"
            )
        }
    }

    /// Duplicates the active Override Preset and cancels the previous one.
    @MainActor func duplicateOverridePresetAndCancelPreviousOverride() async {
        guard let overridePresetToDuplicate = currentActiveOverride, overridePresetToDuplicate.isPreset else { return }

        let duplicateId = await overrideStorage.copyRunningOverride(overridePresetToDuplicate)

        do {
            try await viewContext.perform {
                overridePresetToDuplicate.enabled = false
                guard self.viewContext.hasChanges else { return }
                try self.viewContext.save()
            }

            if let overrideToEdit = try viewContext.existingObject(with: duplicateId) as? OverrideStored {
                currentActiveOverride = overrideToEdit
                activeOverrideName = overrideToEdit.name ?? String(localized: "Custom Override")
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to cancel previous Override: \(error)"
            )
        }
    }

    // MARK: - Helper Functions

    /// Resets state variables to default values.
    @MainActor func resetStateVariables() async {
        id = ""
        overrideDuration = 0
        indefinite = true
        overridePercentage = 100
        advancedSettings = false
        smbIsOff = false
        overrideName = ""
        shouldOverrideTarget = false
        isf = true
        cr = true
        isfAndCr = true
        smbIsScheduledOff = false
        start = 0
        end = 0
        smbMinutes = defaultSmbMinutes
        uamMinutes = defaultUamMinutes
        target = currentGlucoseTarget
    }

    @MainActor func resetExerciseModeState() async {
        exerciseStartDate = Date()
        exerciseType = .run
        customExerciseTypeName = ""
        preExerciseEnabled = true
        preExerciseDuration = 60
        preExerciseTarget = 108
        preExerciseBasalPercentage = 0
        preExerciseSuppressSMB = true
        exerciseTarget = 108
        exerciseBasalPercentage = 50
        exerciseSuppressSMB = true
        postExerciseEnabled = true
        postExerciseTarget = 108
        postExerciseBasalPercentage = 100
        postExerciseSuppressSMB = false
        postExerciseSensitivityDecayType = .linear
        announceGlucoseDuringExercise = false
        announcementInterval = 5
        announcementIncludeTrend = true
        announcementIncludeRateOfChange = false
        announcementUrgentEnabled = true
        announcementLowThreshold = 70
        announcementHighThreshold = 180
    }

    /// Rounds a target value to the nearest step.
    static func roundTargetToStep(_ target: Decimal, _ step: Decimal) -> Decimal {
        // Convert target and step to NSDecimalNumber
        guard let targetValue = NSDecimalNumber(decimal: target).doubleValue as Double?,
              let stepValue = NSDecimalNumber(decimal: step).doubleValue as Double?
        else {
            return target
        }

        // Perform the remainder check using truncatingRemainder
        let remainder = Decimal(targetValue.truncatingRemainder(dividingBy: stepValue))

        if remainder != 0 {
            // Calculate how much to adjust (up or down) based on the remainder
            let adjustment = step - remainder
            return target + adjustment
        }

        // Return the original target if no adjustment is needed
        return target
    }

    /// Rounds an Override percentage to the nearest step.
    static func roundOverridePercentageToStep(_ percentage: Double, _ step: Int) -> Double {
        let stepDouble = Double(step)
        // Check if overridePercentage is not divisible by the selected step
        if percentage.truncatingRemainder(dividingBy: stepDouble) != 0 {
            let roundedValue: Double

            if percentage > 100 {
                // Round down to the nearest valid step away from 100
                let stepCount = (percentage - 100) / stepDouble
                roundedValue = 100 + floor(stepCount) * stepDouble
            } else {
                // Round up to the nearest valid step away from 100
                let stepCount = (100 - percentage) / stepDouble
                roundedValue = 100 - floor(stepCount) * stepDouble
            }

            // Ensure the value stays between 10 and 200
            return max(10, min(roundedValue, 200))
        }

        return percentage
    }
}

enum IsfAndOrCrOptions: String, CaseIterable {
    case isfAndCr
    case isf
    case cr
    case nothing

    var displayName: String {
        switch self {
        case .isfAndCr:
            return String(localized: "ISF/CR", comment: "Option for both ISF and CR")
        case .isf:
            return String(localized: "ISF", comment: "Option for Insulin Sensitivity Factor")
        case .cr:
            return String(localized: "CR", comment: "Option for Carb Ratio")
        case .nothing:
            return String(localized: "None", comment: "Option for no selection")
        }
    }
}

enum DisableSmbOptions: String, CaseIterable {
    case dontDisable
    case disable
    case disableOnSchedule

    var displayName: String {
        switch self {
        case .dontDisable:
            return String(localized: "Don't Disable", comment: "Option to keep SMB enabled")
        case .disable:
            return String(localized: "Disable", comment: "Option to disable SMB")
        case .disableOnSchedule:
            return String(localized: "Disable on Schedule", comment: "Option to disable SMB based on schedule")
        }
    }
}
