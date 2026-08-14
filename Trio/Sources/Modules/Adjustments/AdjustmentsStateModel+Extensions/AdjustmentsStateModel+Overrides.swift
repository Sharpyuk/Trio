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

    struct GlucoseValue: Codable {
        let rawMgdl: Int?
        let displayValue: Decimal?
        let displayUnits: String
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
        var bgAtPreExerciseStartDisplay: GlucoseValue? = nil
        var bgAtExerciseStartDisplay: GlucoseValue? = nil
        var bgAtExerciseEndDisplay: GlucoseValue? = nil
        var bgAtRecoveryEndDisplay: GlucoseValue? = nil
        var minBGDuringExerciseDisplay: GlucoseValue? = nil
        var maxBGDuringExerciseDisplay: GlucoseValue? = nil
        var averageBGDuringExerciseDisplay: GlucoseValue? = nil
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

    struct GuardrailSummary: Codable {
        let settings: ExerciseGuardrailSettings
        let events: [ExerciseGuardrailEvent]
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
    var actualRecoveryEndTime: Date? = nil
    var guardrailSummary: GuardrailSummary? = nil
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

    static func updateReport(
        sessionID: String,
        update: (inout ExerciseReport) -> Void
    ) throws {
        guard var report = loadReport(sessionID: sessionID) else { return }
        update(&report)
        _ = try save(report)
    }

    static func exportURL(for report: ExerciseReport) throws -> URL {
        try save(report)
    }

    static func csvURL(for report: ExerciseReport) throws -> URL {
        try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        let url = reportsDirectory.appendingPathComponent("exercise-report-\(report.id).csv")
        let startDisplay = report.glucoseStats.bgAtExerciseStartDisplay?.displayValue.map { "\($0)" } ?? ""
        let endDisplay = report.glucoseStats.bgAtExerciseEndDisplay?.displayValue.map { "\($0)" } ?? ""
        let rows: [[String]] = [
            ["field", "value"],
            ["exerciseType", report.exerciseType],
            ["preExerciseStartTime", report.preExerciseStartTime?.ISO8601Format() ?? ""],
            ["exerciseStartTime", report.exerciseStartTime.ISO8601Format()],
            ["exerciseStopTime", report.exerciseStopTime.ISO8601Format()],
            ["actualExerciseDurationMinutes", "\(report.actualExerciseDurationMinutes)"],
            ["recoveryDurationCalculatedMinutes", "\(report.recoveryDurationCalculatedMinutes)"],
            ["recoverySensitivityAdjustmentCalculated", "\(report.recoverySensitivityAdjustmentCalculated)"],
            ["decayModelUsed", report.decayModelUsed.title],
            ["glucoseUnits", report.glucoseStats.bgAtExerciseStartDisplay?.displayUnits ?? ""],
            ["bgAtExerciseStartRawMgdl", report.glucoseStats.bgAtExerciseStart.map(String.init) ?? ""],
            ["bgAtExerciseStartDisplay", startDisplay],
            ["bgAtExerciseEndRawMgdl", report.glucoseStats.bgAtExerciseEnd.map(String.init) ?? ""],
            ["bgAtExerciseEndDisplay", endDisplay]
        ]
        let csv = rows.map { $0.map(csvEscape).joined(separator: ",") }.joined(separator: "\n")
        try csv.write(to: url, atomically: true, encoding: String.Encoding.utf8)
        return url
    }

    private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

extension Adjustments.StateModel {
    @MainActor private func markExerciseRecoveryEnded(sessionID: String, at endTime: Date) {
        ExerciseSessionMetadataStore.update(sessionID: sessionID) {
            $0.recoveryEnd = endTime
        }

        try? ExerciseReportStore.updateReport(sessionID: sessionID) { report in
            report.actualRecoveryEndTime = endTime
        }
    }

    @MainActor private func markActiveExerciseRecoveriesEnded(at endTime: Date) {
        let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "enabled == %@ AND name ENDSWITH %@",
            true as NSNumber,
            OverrideStored.exerciseNameSeparator + ExercisePhase.postExercise.title
        )

        guard let activeRecoveryOverrides = try? viewContext.fetch(fetchRequest) else { return }
        for recoveryOverride in activeRecoveryOverrides {
            guard let sessionID = recoveryOverride.id else { continue }
            markExerciseRecoveryEnded(sessionID: sessionID, at: endTime)
        }
    }

    @MainActor func reconcileStaleExerciseRecoveryReports(now: Date = Date()) {
        do {
            let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "enabled == %@", true as NSNumber)
            let activeExerciseSessionIDs = Set(
                try viewContext.fetch(fetchRequest)
                    .filter(\.isExerciseMode)
                    .compactMap(\.id)
            )

            for report in ExerciseReportStore.loadReports() {
                guard report.actualRecoveryEndTime == nil,
                      report.recoveryDurationCalculatedMinutes > 0,
                      !activeExerciseSessionIDs.contains(report.id)
                else {
                    continue
                }

                let calculatedRecoveryEnd = report.exerciseStopTime.addingTimeInterval(
                    TimeInterval(report.recoveryDurationCalculatedMinutes * 60)
                )
                guard calculatedRecoveryEnd > now else { continue }

                try? ExerciseReportStore.updateReport(sessionID: report.id) { updatedReport in
                    updatedReport.actualRecoveryEndTime = now
                }
                ExerciseSessionMetadataStore.update(sessionID: report.id) { metadata in
                    if metadata.recoveryEnd == nil || metadata.recoveryEnd! > now {
                        metadata.recoveryEnd = now
                    }
                }
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to reconcile stale Exercise recovery reports: \(error)"
            )
        }
    }

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

            // Fetch the existing OverrideStored objects from the context
            let results = try ids.compactMap { id in
                try viewContext.existingObject(with: id) as? OverrideStored
            }
            guard !results.isEmpty else { return }

            // Check if we also need to create a corresponding OverrideRunStored entry
            if createOverrideRunEntry {
                // Use the first override to create a new OverrideRunStored entry
                if let canceledOverride = results.first {
                    let newOverrideRunStored = OverrideRunStored(context: viewContext)
                    newOverrideRunStored.id = canceledOverride
                        .exercisePhase == .inactive ? UUID() : (UUID(uuidString: canceledOverride.id ?? "") ?? UUID())
                    newOverrideRunStored.name = canceledOverride.name
                    newOverrideRunStored.startDate = canceledOverride.date ?? .distantPast
                    newOverrideRunStored.endDate = Date()
                    newOverrideRunStored.target = NSDecimalNumber(
                        decimal: overrideStorage.calculateTarget(override: canceledOverride)
                    )
                    newOverrideRunStored.override = canceledOverride
                    newOverrideRunStored.isUploadedToNS = false
                }
            }

            // Disable all overrides except the one with overrideID
            for overrideToCancel in results where overrideToCancel.objectID != overrideID {
                overrideToCancel.enabled = false
            }

            if viewContext.hasChanges {
                // Save changes and update the View
                try viewContext.save()
                ExerciseGlucoseAnnouncementManager.shared.stopSpeech()
                updateLatestOverrideConfiguration()
            }
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to disable active overrides: \(error)"
            )
        }
    }

    @MainActor func cancelOverride(withID objectID: NSManagedObjectID, createOverrideRunEntry: Bool = true) async {
        do {
            guard let overrideToCancel = try viewContext.existingObject(with: objectID) as? OverrideStored else { return }

            if createOverrideRunEntry {
                let newOverrideRunStored = OverrideRunStored(context: viewContext)
                newOverrideRunStored.id = UUID(uuidString: overrideToCancel.id ?? "") ?? UUID()
                newOverrideRunStored.name = overrideToCancel.name
                newOverrideRunStored.startDate = overrideToCancel.date ?? .distantPast
                newOverrideRunStored.endDate = Date()
                newOverrideRunStored.target = NSDecimalNumber(
                    decimal: overrideStorage.calculateTarget(override: overrideToCancel)
                )
                newOverrideRunStored.override = overrideToCancel
                newOverrideRunStored.isUploadedToNS = false
            }

            overrideToCancel.enabled = false

            if viewContext.hasChanges {
                try viewContext.save()
                updateLatestOverrideConfiguration()
            }
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to cancel override: \(error)"
            )
        }
    }

    @MainActor func disableActiveNormalOverrides(createOverrideRunEntry: Bool) async {
        do {
            let ids = try await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0)
            let activeOverrides = try ids.compactMap { id in
                try viewContext.existingObject(with: id) as? OverrideStored
            }
            let normalOverrides = activeOverrides.filter { !$0.isExerciseMode && !$0.currentProteinFatAssist }
            guard !normalOverrides.isEmpty else { return }

            for overrideToCancel in normalOverrides {
                if createOverrideRunEntry {
                    let newOverrideRunStored = OverrideRunStored(context: viewContext)
                    newOverrideRunStored.id = UUID(uuidString: overrideToCancel.id ?? "") ?? UUID()
                    newOverrideRunStored.name = overrideToCancel.name
                    newOverrideRunStored.startDate = overrideToCancel.date ?? .distantPast
                    newOverrideRunStored.endDate = Date()
                    newOverrideRunStored.target = NSDecimalNumber(
                        decimal: overrideStorage.calculateTarget(override: overrideToCancel)
                    )
                    newOverrideRunStored.override = overrideToCancel
                    newOverrideRunStored.isUploadedToNS = false
                }

                overrideToCancel.enabled = false
                debug(
                    .default,
                    "Exercise Override start disabled normal override \(overrideToCancel.name ?? "Unknown")"
                )
            }

            if viewContext.hasChanges {
                try viewContext.save()
                updateLatestOverrideConfiguration()
            }
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to disable normal overrides: \(error)"
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

    @MainActor @discardableResult func saveExerciseMode() async -> Bool {
        do {
            let now = Date()
            let sessionID = UUID().uuidString
            let exerciseTypeName = resolvedExerciseTypeName

            let preMinutes = preExerciseEnabled ? NSDecimalNumber(decimal: preExerciseDuration).doubleValue : 0
            let scheduledExerciseStart = scheduleExerciseForFuture
                ? max(exerciseStartDate, now)
                : (preMinutes > 0 ? now.addingTimeInterval(preMinutes * 60) : now)
            let plannedExerciseEnd = exerciseHasPlannedDuration
                ? scheduledExerciseStart.addingTimeInterval(
                    NSDecimalNumber(decimal: exerciseDuration).doubleValue * 60
                )
                : nil
            let plannedPreStart = preExerciseEnabled && preMinutes > 0
                ? (scheduleExerciseForFuture ? scheduledExerciseStart.addingTimeInterval(-preMinutes * 60) : now)
                : scheduledExerciseStart

            debugPrint("ExerciseOverride START tapped")
            debugPrint("ExerciseOverride START activityType=\(exerciseTypeName)")
            debugPrint("ExerciseOverride START mode=\(scheduleExerciseForFuture ? "scheduled" : "immediate")")
            debugPrint("ExerciseOverride START scheduledExerciseStart=\(scheduledExerciseStart)")
            debugPrint("ExerciseOverride START preExerciseDuration=\(preExerciseDuration)")
            debugPrint("ExerciseOverride START calculatedPreExerciseStart=\(plannedPreStart)")
            debugPrint("ExerciseOverride START sessionId=\(sessionID)")
            debugPrint(
                "ExerciseOverride START guardrails before save enabled=\(exerciseGuardrailSettings.enabled) mode=\(exerciseGuardrailSettings.mode.rawValue)"
            )

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
                initialStart = scheduleExerciseForFuture ? scheduledExerciseStart : now
                initialDuration = plannedExerciseEnd.map {
                    Decimal(max(1, $0.timeIntervalSince(initialStart) / 60))
                } ?? 2160
                initialBasal = exerciseBasalPercentage
                initialSMB = exerciseSuppressSMB
                initialTarget = exerciseTarget
            }

            try ExerciseSessionMetadataStore.save(ExerciseSessionMetadata(
                sessionID: sessionID,
                exerciseTypeName: exerciseTypeName,
                sessionCreatedAt: now,
                scheduledExerciseStart: scheduledExerciseStart,
                plannedExerciseEnd: plannedExerciseEnd,
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
                postExerciseTargetEnabled: postExerciseTargetEnabled,
                postExerciseTarget: postExerciseTargetEnabled ? postExerciseTarget : 0,
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
                ),
                guardrailSettings: exerciseGuardrailSettings
            ))
            if let savedMetadata = ExerciseSessionMetadataStore.load(sessionID: sessionID) {
                debugPrint(
                    "ExerciseOverride START saved guardrails session=\(sessionID) enabled=\(savedMetadata.guardrailSettings.enabled) mode=\(savedMetadata.guardrailSettings.mode.rawValue)"
                )
            }

            if initialStart <= now.addingTimeInterval(60) {
                markActiveExerciseRecoveriesEnded(at: now)
                await disableActiveNormalOverrides(createOverrideRunEntry: true)
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
            debugPrint(
                "ExerciseOverride session \(sessionID) created phase=\(initialPhase.rawValue) scheduled=\(scheduledExerciseStart)"
            )
            ExerciseGlucoseAnnouncementManager.shared.startMonitoring()

            setupScheduledExerciseOverridesArray()
            updateLatestOverrideConfiguration()
            Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
            exerciseModeStartError = nil
            return true
        } catch {
            exerciseModeStartError = "Could not start Exercise Override: \(error.localizedDescription)"
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to save exercise mode: \(error)"
            )
            return false
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
            await disableActiveNormalOverrides(createOverrideRunEntry: true)

            if preExerciseOverride.date != nil,
               let metadata = ExerciseSessionMetadataStore.load(sessionID: sessionID)
            {
                let settings = metadata.exerciseSettings
                preExerciseOverride.name = OverrideStored.exerciseOverrideName(
                    type: preExerciseOverride.exerciseTypeName ?? metadata.exerciseTypeName,
                    phase: .duringExercise
                )
                preExerciseOverride.date = now
                preExerciseOverride.duration = (metadata.plannedExerciseEnd.map {
                    Decimal(max(1, $0.timeIntervalSince(now) / 60))
                } ?? 2160) as NSDecimalNumber
                preExerciseOverride.percentage = metadata.guardrailBasalReenabledAt == nil
                    ? (settings?.basalPercentage ?? exerciseBasalPercentage)
                    : 100
                preExerciseOverride.smbIsOff = metadata.guardrailSMBReenabledAt == nil
                    ? (settings?.suppressSMB ?? exerciseSuppressSMB)
                    : false
                preExerciseOverride.target = (settings?.target ?? exerciseTarget) as NSDecimalNumber
                preExerciseOverride.isfAndCr = true
                preExerciseOverride.isf = true
                preExerciseOverride.cr = true
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
            Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
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

    @MainActor func applyExercisePresetForSelectedType() {
        let preset = ExerciseActivityPresetStore.preset(named: resolvedExerciseTypeName)
        applyExerciseActivityPreset(preset)
    }

    @MainActor func applyExerciseActivityPreset(_ preset: ExerciseActivityPreset, editing: Bool = false) {
        if let matchingType = matchingExerciseType(for: preset.activityTypeName) {
            exerciseType = matchingType
            customExerciseTypeName = ""
        } else {
            exerciseType = .custom
            customExerciseTypeName = preset.activityTypeName
        }
        exercisePresetName = preset.activityTypeName
        editingExercisePresetID = editing ? preset.id : nil
        preExerciseEnabled = preset.preExerciseEnabled
        preExerciseDuration = preset.preExerciseDuration
        preExerciseTarget = preset.preExerciseTarget
        preExerciseBasalPercentage = preset.preExerciseBasalPercent
        preExerciseSuppressSMB = preset.preExerciseSMBSuppressed
        exerciseTarget = preset.exerciseTarget
        exerciseBasalPercentage = preset.exerciseBasalPercent
        exerciseSuppressSMB = preset.exerciseSMBSuppressed
        announceGlucoseDuringExercise = preset.announceGlucoseEnabled
        announcementInterval = preset.announcementInterval
        announcementIncludeTrend = preset.includeTrend
        announcementUrgentEnabled = preset.urgentAnnouncementsEnabled
        postExerciseEnabled = preset.recoveryEnabled
        postExerciseTargetEnabled = preset.postExerciseTargetEnabled
        postExerciseSensitivityDecayType = preset.defaultRecoveryDecayType
        exerciseGuardrailSettings = preset.guardrailSettings
        debugPrint("ExerciseOverride preset loaded \(preset.activityTypeName)")
    }

    @MainActor func saveCurrentExercisePreset() {
        let trimmedPresetName = exercisePresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedPresetName.isEmpty ? resolvedExerciseTypeName : trimmedPresetName
        let presetID = editingExercisePresetID ?? name
        let preset = ExerciseActivityPreset(
            id: presetID,
            activityTypeName: name,
            icon: exerciseType == .custom ? "figure.mixed.cardio" : "figure.run",
            preExerciseEnabled: preExerciseEnabled,
            preExerciseDuration: preExerciseDuration,
            preExerciseTarget: preExerciseTarget,
            preExerciseBasalPercent: preExerciseBasalPercentage,
            preExerciseSMBSuppressed: preExerciseSuppressSMB,
            exerciseTarget: exerciseTarget,
            exerciseBasalPercent: exerciseBasalPercentage,
            exerciseSMBSuppressed: exerciseSuppressSMB,
            announceGlucoseEnabled: announceGlucoseDuringExercise,
            announcementInterval: announcementInterval,
            includeTrend: announcementIncludeTrend,
            urgentAnnouncementsEnabled: announcementUrgentEnabled,
            recoveryEnabled: postExerciseEnabled,
            postExerciseTargetEnabled: postExerciseTargetEnabled,
            minimumDurationForRecovery: 10,
            defaultRecoveryDecayType: postExerciseSensitivityDecayType,
            guardrailSettings: exerciseGuardrailSettings
        )
        ExerciseActivityPresetStore.savePreset(preset)
        exerciseActivityPresets = ExerciseActivityPresetStore.loadPresets()
        exercisePresetName = name
        editingExercisePresetID = presetID
    }

    @MainActor func deleteExerciseActivityPreset(_ preset: ExerciseActivityPreset) {
        ExerciseActivityPresetStore.deletePreset(id: preset.id)
        exerciseActivityPresets = ExerciseActivityPresetStore.loadPresets()
        if editingExercisePresetID == preset.id {
            editingExercisePresetID = nil
        }
    }

    private func matchingExerciseType(for name: String) -> ExerciseType? {
        let normalizedName = normalizedExerciseTypeName(name)
        return ExerciseType.allCases.first { normalizedExerciseTypeName($0.rawValue) == normalizedName }
    }

    private func normalizedExerciseTypeName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
        overrideTarget: Bool = true,
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
            overrideTarget: overrideTarget,
            target: target,
            advancedSettings: false,
            // Oref applies override percentage to current basal. With ISF/CR enabled it also
            // raises ISF and carb ratio by the inverse percentage, so Exercise insulin strength
            // reduces temp-basal corrections, SMB limits, and correction aggressiveness together.
            isfAndCr: phase != .postExercise,
            isf: phase != .postExercise,
            cr: phase != .postExercise,
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
            reconcileStaleExerciseRecoveryReports()
            try await recreateMissingExercisePhaseOverridesIfNeeded(now: Date())

            let request: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            let sessionIDs = ExerciseSessionMetadataStore.visibleSessionIDs()
            request.predicate = sessionIDs.isEmpty
                ? NSPredicate(
                    format: "enabled == %@ AND name BEGINSWITH %@",
                    true as NSNumber,
                    OverrideStored.exerciseOverrideName + ":"
                )
                : NSPredicate(format: "enabled == %@ AND id IN %@", true as NSNumber, sessionIDs)
            let overrides = try viewContext.fetch(request)
            let now = Date()
            var changed = false

            for override in overrides {
                guard let sessionID = override.id,
                      var metadata = ExerciseSessionMetadataStore.load(sessionID: sessionID)
                else { continue }

                if override.exercisePhase == .duringExercise,
                   metadata.actualExerciseEnd == nil,
                   let plannedExerciseEnd = metadata.plannedExerciseEnd,
                   now >= plannedExerciseEnd
                {
                    await stopExerciseNow(override.objectID)
                    changed = true
                    continue
                }

                switch metadata.state(at: now) {
                case .exerciseActive where override.exercisePhase == .preExercise:
                    await disableActiveNormalOverrides(createOverrideRunEntry: true)

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
                        ? (settings?.basalPercentage ?? exerciseBasalPercentage)
                        : 100
                    override.smbIsOff = metadata.guardrailSMBReenabledAt == nil
                        ? (settings?.suppressSMB ?? exerciseSuppressSMB)
                        : false
                    override.target = (settings?.target ?? exerciseTarget) as NSDecimalNumber
                    override.isfAndCr = true
                    override.isf = true
                    override.cr = true
                    override.isUploadedToNS = false
                    metadata.actualExerciseStart = override.date
                    try? ExerciseSessionMetadataStore.save(metadata)
                    changed = true
                    debugPrint("ExerciseOverride session \(sessionID) auto-start at \(override.date ?? now)")

                case .exerciseActive where override.exercisePhase == .duringExercise && metadata.actualExerciseStart == nil:
                    metadata.actualExerciseStart = override.date ?? now
                    try? ExerciseSessionMetadataStore.save(metadata)
                    changed = true
                    debugPrint("ExerciseOverride session \(sessionID) marked active at \(metadata.actualExerciseStart ?? now)")

                case .completed where override.exercisePhase == .postExercise:
                    override.enabled = false
                    override.isUploadedToNS = false
                    changed = true
                    debugPrint("ExerciseOverride session \(sessionID) recovery expired")

                default:
                    break
                }
            }

            if viewContext.hasChanges {
                try viewContext.save()
            }
            if changed {
                Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
                reconcileStaleExerciseRecoveryReports(now: now)
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to advance Exercise Override sessions: \(error)"
            )
        }
    }

    @MainActor private func recreateMissingExercisePhaseOverridesIfNeeded(now: Date) async throws {
        for metadata in ExerciseSessionMetadataStore.loadAll() {
            let state = metadata.state(at: now)
            guard state != .completed, state != .cancelled else { continue }

            let request: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND enabled == %@", metadata.sessionID, true as NSNumber)
            let existingEnabled = try viewContext.fetch(request)
            guard existingEnabled.isEmpty else { continue }

            let phase: ExercisePhase
            let startDate: Date
            let duration: Decimal
            let settings: ExerciseSessionMetadata.PhaseSettings?
            let suppressSMB: Bool
            let target: Decimal
            let overrideTarget: Bool
            let sensitivityPercent: Decimal
            let decayType: ExerciseSensitivityDecayType

            switch state {
            case .preExerciseActive,
                 .scheduledPreExercise:
                phase = .preExercise
                startDate = metadata.preExerciseStart ?? metadata.scheduledExerciseStart ?? now
                let end = metadata.scheduledExerciseStart ?? now
                duration = Decimal(max(1, end.timeIntervalSince(startDate) / 60))
                settings = metadata.preExerciseSettings
                suppressSMB = settings?.suppressSMB ?? true
                target = settings?.target ?? preExerciseTarget
                overrideTarget = true
                sensitivityPercent = 0
                decayType = .flat

            case .exerciseActive:
                phase = .duringExercise
                startDate = metadata.actualExerciseStart ?? metadata.scheduledExerciseStart ?? now
                duration = metadata.plannedExerciseEnd.map {
                    Decimal(max(1, $0.timeIntervalSince(startDate) / 60))
                } ?? 2160
                settings = metadata.exerciseSettings
                suppressSMB = metadata.guardrailSMBReenabledAt == nil ? (settings?.suppressSMB ?? true) : false
                target = settings?.target ?? exerciseTarget
                overrideTarget = true
                sensitivityPercent = 0
                decayType = .flat

            case .recoveryActive:
                phase = .postExercise
                startDate = metadata.recoveryStart ?? metadata.actualExerciseEnd ?? now
                duration = metadata.recoveryEnd.map {
                    Decimal(max(1, $0.timeIntervalSince(startDate) / 60))
                } ?? Decimal(ExerciseRecoveryCalculator.recommendation(forExerciseDurationMinutes: 30).durationMinutes)
                settings = nil
                suppressSMB = metadata.postExerciseSuppressSMB
                target = metadata.postExerciseTargetEnabled ? metadata.postExerciseTarget : 0
                overrideTarget = metadata.postExerciseTargetEnabled
                sensitivityPercent = 0
                decayType = .linear

            case .cancelled,
                 .completed:
                continue
            }

            let strength = metadata.guardrailBasalReenabledAt == nil
                ? (settings?.insulinStrengthPercentage ?? metadata.postExerciseBasalPercentage)
                : 100

            try await overrideStorage.storeOverride(override: exerciseOverride(
                sessionID: metadata.sessionID,
                exerciseTypeName: metadata.exerciseTypeName,
                phase: phase,
                startDate: startDate,
                duration: duration,
                basalPercentage: strength,
                suppressSMB: suppressSMB,
                target: target,
                overrideTarget: overrideTarget,
                sensitivityPercent: sensitivityPercent,
                decayType: decayType
            ))
            debugPrint("ExerciseOverride session \(metadata.sessionID) recreated missing \(phase.rawValue) phase")
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
            viewContext.refreshAllObjects()
            scheduledExerciseOverrides = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? OverrideStored
            }
            debugPrint(
                "ExerciseOverride adjustments provider sessions=\(scheduledExerciseOverrides.compactMap(\.id).joined(separator: ","))"
            )
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
                markExerciseRecoveryEnded(sessionID: sessionID, at: cancelledAt)
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
            Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to cancel scheduled Exercise Mode: \(error)"
            )
        }
    }

    @MainActor func endExerciseRecovery(_ objectID: NSManagedObjectID) async {
        do {
            guard let recoveryOverride = try viewContext.existingObject(with: objectID) as? OverrideStored,
                  recoveryOverride.exercisePhase == .postExercise,
                  let sessionID = recoveryOverride.id
            else {
                return
            }

            let now = Date()
            let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@ AND enabled == %@", sessionID, true as NSNumber)
            let sessionOverrides = try viewContext.fetch(fetchRequest)

            for sessionOverride in sessionOverrides where sessionOverride.exercisePhase == .postExercise {
                sessionOverride.enabled = false
                sessionOverride.isUploadedToNS = false
                if let startDate = sessionOverride.date {
                    let elapsedMinutes = max(1, now.timeIntervalSince(startDate) / 60)
                    sessionOverride.duration = Decimal(elapsedMinutes) as NSDecimalNumber
                }
            }

            markExerciseRecoveryEnded(sessionID: sessionID, at: now)
            debugPrint("ExerciseOverride session \(sessionID) recovery-ended at \(now)")

            guard viewContext.hasChanges else {
                setupScheduledExerciseOverridesArray()
                updateLatestOverrideConfiguration()
                Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
                return
            }
            try viewContext.save()
            setupScheduledExerciseOverridesArray()
            updateLatestOverrideConfiguration()
            Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to end Exercise Override recovery: \(error)"
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
            let recoveryTargetEnabled = (metadata?.postExerciseTargetEnabled ?? postExerciseTargetEnabled) == true
            let recoveryTarget = recoveryTargetEnabled ? (metadata?.postExerciseTarget ?? postExerciseTarget) : 0
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
                    overrideTarget: recoveryTargetEnabled,
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
                Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
                return
            }
            try viewContext.save()
            setupScheduledExerciseOverridesArray()
            updateLatestOverrideConfiguration()
            Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
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
        let recoveryTargetEnabled = (metadata?.postExerciseTargetEnabled ?? postExerciseTargetEnabled) == true
        let recoveryTarget = recoveryTargetEnabled ? (metadata?.postExerciseTarget ?? postExerciseTarget) : 0
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
                target: recoveryTargetEnabled ? recoveryTarget : nil,
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
            guardrailSummary: metadata.map {
                ExerciseReport.GuardrailSummary(settings: $0.guardrailSettings, events: $0.guardrailEvents)
            },
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
        let preStartGlucose = preStart.flatMap { nearestGlucose(to: $0).map { Int($0.glucose) } }
        let startGlucose = nearestGlucose(to: exerciseStart).map { Int($0.glucose) }
        let endGlucose = nearestGlucose(to: exerciseEnd).map { Int($0.glucose) }
        let recoveryEndGlucose = recoveryEnd.flatMap { nearestGlucose(to: $0).map { Int($0.glucose) } }

        return ExerciseReport.GlucoseStats(
            bgAtPreExerciseStart: preStartGlucose,
            bgAtExerciseStart: startGlucose,
            bgAtExerciseEnd: endGlucose,
            bgAtRecoveryEnd: recoveryEndGlucose,
            minBGDuringExercise: values.min(),
            maxBGDuringExercise: values.max(),
            averageBGDuringExercise: average,
            glucoseTrendBeforeExercise: glucoseTrend(endingAt: exerciseStart),
            glucoseTrendAfterExercise: glucoseTrend(startingAt: exerciseEnd),
            bgAtPreExerciseStartDisplay: glucoseDisplayValue(preStartGlucose),
            bgAtExerciseStartDisplay: glucoseDisplayValue(startGlucose),
            bgAtExerciseEndDisplay: glucoseDisplayValue(endGlucose),
            bgAtRecoveryEndDisplay: glucoseDisplayValue(recoveryEndGlucose),
            minBGDuringExerciseDisplay: glucoseDisplayValue(values.min()),
            maxBGDuringExerciseDisplay: glucoseDisplayValue(values.max()),
            averageBGDuringExerciseDisplay: average.map {
                ExerciseReport.GlucoseValue(
                    rawMgdl: Int(truncating: NSDecimalNumber(decimal: $0)),
                    displayValue: displayGlucoseValue(rawMgdl: $0),
                    displayUnits: units.rawValue
                )
            }
        )
    }

    private func glucoseDisplayValue(_ rawMgdl: Int?) -> ExerciseReport.GlucoseValue? {
        guard let rawMgdl else { return nil }
        let raw = Decimal(rawMgdl)
        return ExerciseReport.GlucoseValue(
            rawMgdl: rawMgdl,
            displayValue: displayGlucoseValue(rawMgdl: raw),
            displayUnits: units.rawValue
        )
    }

    private func displayGlucoseValue(rawMgdl: Decimal) -> Decimal {
        units == .mgdL ? rawMgdl : rawMgdl.asMmolL
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
            viewContext.refreshAllObjects()
            guard let firstID = IDs.first else {
                activeOverrideName = "Custom Override"
                currentActiveOverride = nil
                debugPrint("ExerciseOverride adjustments active provider none")
                return
            }

            if let overrideToEdit = try viewContext.existingObject(with: firstID) as? OverrideStored {
                currentActiveOverride = overrideToEdit
                activeOverrideName = overrideToEdit.name ?? String(localized: "Custom Override")
                if overrideToEdit.isExerciseMode {
                    debugPrint("ExerciseOverride adjustments active provider session=\(overrideToEdit.id ?? "unknown")")
                }
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
        scheduleExerciseForFuture = false
        exerciseModeStartError = nil
        exerciseType = .run
        customExerciseTypeName = ""
        exerciseHasPlannedDuration = true
        exerciseDuration = 120
        exercisePresetName = ""
        editingExercisePresetID = nil
        exerciseActivityPresets = ExerciseActivityPresetStore.loadPresets()
        applyExercisePresetForSelectedType()
        postExerciseTargetEnabled = false
        postExerciseTarget = 108
        postExerciseBasalPercentage = 100
        postExerciseSuppressSMB = false
        announcementIncludeRateOfChange = false
        announcementLowThreshold = 70
        announcementHighThreshold = 180
        exerciseGuardrailSettings = ExerciseGuardrailSettings()
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
