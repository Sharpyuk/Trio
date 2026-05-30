import Foundation
import Testing

@testable import Trio

@Suite("Exercise Session Metadata Tests") struct ExerciseSessionMetadataTests {
    @Test("Immediate start derives pre-exercise active") func immediateStartDerivesPreExerciseActive() {
        let now = Date()
        let metadata = makeMetadata(
            createdAt: now,
            scheduledExerciseStart: now.addingTimeInterval(60 * 60),
            preExerciseStart: now
        )

        #expect(metadata.state(at: now) == .preExerciseActive)
    }

    @Test("Future start inside pre-exercise window derives pre-exercise active") func shortFutureStartDerivesPreExerciseActive() {
        let now = Date()
        let scheduledExerciseStart = now.addingTimeInterval(10 * 60)
        let metadata = makeMetadata(
            createdAt: now,
            scheduledExerciseStart: scheduledExerciseStart,
            preExerciseStart: scheduledExerciseStart.addingTimeInterval(-60 * 60)
        )

        #expect(metadata.state(at: now) == .preExerciseActive)
    }

    @Test("Future start before pre-exercise window derives scheduled") func longFutureStartDerivesScheduled() {
        let now = Date()
        let scheduledExerciseStart = now.addingTimeInterval(3 * 60 * 60)
        let metadata = makeMetadata(
            createdAt: now,
            scheduledExerciseStart: scheduledExerciseStart,
            preExerciseStart: scheduledExerciseStart.addingTimeInterval(-60 * 60)
        )

        #expect(metadata.state(at: now) == .scheduledPreExercise)
        #expect(metadata.state(at: scheduledExerciseStart.addingTimeInterval(-30 * 60)) == .preExerciseActive)
        #expect(metadata.state(at: scheduledExerciseStart) == .exerciseActive)
    }

    @Test("Completed recovery expires") func completedRecoveryExpires() {
        let now = Date()
        let metadata = makeMetadata(
            createdAt: now.addingTimeInterval(-3 * 60 * 60),
            scheduledExerciseStart: now.addingTimeInterval(-2 * 60 * 60),
            preExerciseStart: now.addingTimeInterval(-3 * 60 * 60),
            actualExerciseStart: now.addingTimeInterval(-2 * 60 * 60),
            actualExerciseEnd: now.addingTimeInterval(-60 * 60),
            recoveryStart: now.addingTimeInterval(-60 * 60),
            recoveryEnd: now.addingTimeInterval(-1)
        )

        #expect(metadata.state(at: now) == .completed)
    }

    private func makeMetadata(
        createdAt: Date,
        scheduledExerciseStart: Date,
        preExerciseStart: Date,
        actualExerciseStart: Date? = nil,
        actualExerciseEnd: Date? = nil,
        recoveryStart: Date? = nil,
        recoveryEnd: Date? = nil
    ) -> ExerciseSessionMetadata {
        ExerciseSessionMetadata(
            sessionID: UUID().uuidString,
            exerciseTypeName: "Run",
            sessionCreatedAt: createdAt,
            scheduledExerciseStart: scheduledExerciseStart,
            preExerciseStart: preExerciseStart,
            actualExerciseStart: actualExerciseStart,
            actualExerciseEnd: actualExerciseEnd,
            recoveryStart: recoveryStart,
            recoveryEnd: recoveryEnd,
            preExerciseEnabled: true,
            preExerciseDurationMinutes: 60,
            preExerciseSettings: .init(basalPercentage: 0, target: 108, suppressSMB: true),
            exerciseSettings: .init(basalPercentage: 50, target: 108, suppressSMB: true),
            postExerciseEnabled: true,
            postExerciseBasalPercentage: 100,
            postExerciseTarget: 108,
            postExerciseSuppressSMB: false,
            announcementSettings: ExerciseAnnouncementSettings()
        )
    }
}
