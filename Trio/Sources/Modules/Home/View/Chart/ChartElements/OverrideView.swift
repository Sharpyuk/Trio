import Charts
import CoreData
import Foundation
import SwiftUI

private struct ExerciseOverrideChartSegment: Identifiable {
    let id: String
    let start: Date
    let end: Date
    let target: Decimal
    let color: Color
}

struct OverrideView: ChartContent {
    var state: Home.StateModel
    let overrides: [OverrideStored]
    let overrideRunStored: [OverrideRunStored]
    let units: GlucoseUnits
    let viewContext: NSManagedObjectContext

    var body: some ChartContent {
        drawActiveOverrides()
        drawOverrideRunStored()
    }

    private func drawActiveOverrides() -> some ChartContent {
        ForEach(activeOverrideSegments()) { segment in
            RuleMark(
                xStart: .value("Start", segment.start, unit: .second),
                xEnd: .value("End", segment.end, unit: .second),
                y: .value("Value", units == .mgdL ? segment.target : segment.target.asMmolL)
            )
            .foregroundStyle(segment.color.opacity(0.45))
            .lineStyle(.init(lineWidth: 8))
        }
    }

    private func activeOverrideSegments() -> [ExerciseOverrideChartSegment] {
        var segments: [ExerciseOverrideChartSegment] = []
        var renderedExerciseSessionIDs = Set<String>()

        for override in overrides {
            if override.isExerciseMode, let sessionID = override.id {
                guard renderedExerciseSessionIDs.insert(sessionID).inserted else { continue }
                let exerciseSegments = exerciseSegments(sessionID: sessionID, fallbackOverride: override)
                segments.append(contentsOf: exerciseSegments)
            } else {
                let start = override.date ?? .distantPast
                segments.append(ExerciseOverrideChartSegment(
                    id: override.objectID.uriRepresentation().absoluteString,
                    start: start,
                    end: overrideEndDate(override: override, start: start),
                    target: getOverrideTarget(override: override),
                    color: .purple
                ))
            }
        }

        return segments
    }

    private func exerciseSegments(sessionID: String, fallbackOverride: OverrideStored) -> [ExerciseOverrideChartSegment] {
        guard let metadata = ExerciseSessionMetadataStore.load(sessionID: sessionID),
              metadata.cancelledAt == nil
        else {
            let start = fallbackOverride.date ?? .distantPast
            return [ExerciseOverrideChartSegment(
                id: fallbackOverride.objectID.uriRepresentation().absoluteString,
                start: start,
                end: overrideEndDate(override: fallbackOverride, start: start),
                target: getOverrideTarget(override: fallbackOverride),
                color: exerciseColor(fallbackOverride.exercisePhase)
            )]
        }

        var segments: [ExerciseOverrideChartSegment] = []
        if let scheduledStart = metadata.scheduledExerciseStart {
            let preStart = metadata.preExerciseStart ?? scheduledStart
            let preEnd = metadata.actualExerciseStart ?? scheduledStart
            appendSegment(
                &segments,
                id: "\(sessionID)-pre",
                start: preStart,
                end: preEnd,
                target: metadata.preExerciseSettings?.target ?? getOverrideTarget(override: fallbackOverride),
                color: .yellow
            )
        }

        if let exerciseStart = metadata.actualExerciseStart ?? metadata.scheduledExerciseStart {
            let exerciseEnd = metadata.actualExerciseEnd ?? overrideEndDate(
                override: fallbackOverride,
                start: fallbackOverride.date ?? exerciseStart
            )
            appendSegment(
                &segments,
                id: "\(sessionID)-exercise",
                start: exerciseStart,
                end: exerciseEnd,
                target: metadata.exerciseSettings?.target ?? getOverrideTarget(override: fallbackOverride),
                color: .green
            )
        }

        if let recoveryStart = metadata.recoveryStart,
           let recoveryEnd = metadata.recoveryEnd
        {
            appendSegment(
                &segments,
                id: "\(sessionID)-recovery",
                start: recoveryStart,
                end: recoveryEnd,
                target: metadata.postExerciseTargetEnabled ? metadata.postExerciseTarget : state.currentGlucoseTarget,
                color: .teal
            )
        }

        return segments
    }

    private func appendSegment(
        _ segments: inout [ExerciseOverrideChartSegment],
        id: String,
        start: Date,
        end: Date,
        target: Decimal,
        color: Color
    ) {
        guard end > start else { return }
        segments.append(ExerciseOverrideChartSegment(id: id, start: start, end: end, target: target, color: color))
    }

    private func overrideEndDate(override: OverrideStored, start: Date) -> Date {
        let duration = MainChartHelper.calculateDuration(
            objectID: override.objectID,
            attribute: "duration",
            context: viewContext
        ) ?? 0
        if override.indefinite {
            return start.addingTimeInterval(60 * 60 * 24 * 30)
        } else if duration != 0 {
            return start.addingTimeInterval(duration)
        } else {
            return start.addingTimeInterval(60 * 60 * 24 * 30)
        }
    }

    private func drawOverrideRunStored() -> some ChartContent {
        ForEach(overrideRunStored) { overrideRunStored in
            let start: Date = overrideRunStored.startDate ?? .distantPast
            let end: Date = overrideRunStored.endDate ?? Date()
            let target = (overrideRunStored.target?.decimalValue ?? 100) == 0 ? 100 : overrideRunStored.target!.decimalValue
            RuleMark(
                xStart: .value("Start", start, unit: .second),
                xEnd: .value("End", end, unit: .second),
                y: .value("Value", units == .mgdL ? target : target.asMmolL)
            )
            .foregroundStyle(Color.purple.opacity(0.25))
            .lineStyle(.init(lineWidth: 8))
        }
    }

    // Handle Overrides where no Target is provided
    private func getOverrideTarget(override: OverrideStored) -> Decimal {
        if let target = MainChartHelper
            .calculateTarget(objectID: override.objectID, attribute: "target", context: viewContext)
        {
            return target
        } else if override.target == 0 {
            return state.currentGlucoseTarget // Default target
        } else {
            return override.target?.decimalValue ?? state.currentGlucoseTarget
        }
    }

    private func exerciseColor(_ phase: ExercisePhase?) -> Color {
        switch phase {
        case .preExercise:
            return .yellow
        case .duringExercise:
            return .green
        case .postExercise:
            return .teal
        case .inactive,
             nil:
            return .purple
        }
    }
}
