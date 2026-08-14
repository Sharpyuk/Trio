import Charts
import Foundation
import SwiftUI

struct ExercisePhaseChartView: ChartContent {
    let sessions: [ExerciseSession]
    let units: GlucoseUnits

    var body: some ChartContent {
        ForEach(sessions) { session in
            if let preStart = session.actualPreExerciseStart,
               let activeStart = session.actualExerciseStart,
               activeStart > preStart
            {
                phaseBar(start: preStart, end: activeStart, color: .yellow, level: 72)
                if let target = session.preset.preExercise.target {
                    targetBar(start: preStart, end: activeStart, target: target)
                }
            }
            if let activeStart = session.actualExerciseStart {
                let activeEnd = session.actualExerciseEnd ?? Date()
                if activeEnd > activeStart {
                    phaseBar(start: activeStart, end: activeEnd, color: .purple, level: 78)
                    if let target = session.preset.active.target {
                        targetBar(start: activeStart, end: activeEnd, target: target)
                    }
                }
            }
            if let recoveryStart = session.recoveryStart,
               let recoveryEnd = session.actualRecoveryEnd ?? session.recommendedRecoveryEnd,
               recoveryEnd > recoveryStart
            {
                phaseBar(start: recoveryStart, end: recoveryEnd, color: .teal, level: 84)
                if let target = session.preset.recovery.target {
                    targetBar(start: recoveryStart, end: recoveryEnd, target: target)
                }
            }
        }
    }

    private func phaseBar(start: Date, end: Date, color: Color, level: Decimal) -> some ChartContent {
        RuleMark(
            xStart: .value("Exercise phase start", start, unit: .second),
            xEnd: .value("Exercise phase end", end, unit: .second),
            y: .value("Exercise phase", units == .mgdL ? level : level.asMmolL)
        )
        .foregroundStyle(color.opacity(0.8))
        .lineStyle(.init(lineWidth: 6))
    }

    private func targetBar(start: Date, end: Date, target: Decimal) -> some ChartContent {
        RuleMark(
            xStart: .value("Exercise target start", start, unit: .second),
            xEnd: .value("Exercise target end", end, unit: .second),
            y: .value("Effective Exercise target", units == .mgdL ? target : target.asMmolL)
        )
        .foregroundStyle(Color.green.opacity(0.65))
        .lineStyle(.init(lineWidth: 2, dash: [4, 3]))
    }
}
