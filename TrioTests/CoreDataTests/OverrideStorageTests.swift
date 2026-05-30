import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("Override Storage Tests", .serialized) struct OverrideStorageTests: Injectable {
    @Injected() var storage: OverrideStorage!
    let resolver: Resolver
    var coreDataStack: CoreDataStack!
    var testContext: NSManagedObjectContext!

    init() async throws {
        // Create test context
        // As we are only using this single test context to initialize our in-memory DeterminationStorage we need to perform the Unit Tests serialized
        coreDataStack = try await CoreDataStack.createForTests()
        testContext = coreDataStack.newTaskContext()

        // Create assembler with test assembly
        let assembler = Assembler([
            StorageAssembly(),
            ServiceAssembly(),
            APSAssembly(),
            NetworkAssembly(),
            UIAssembly(),
            SecurityAssembly(),
            TestAssembly(testContext: testContext) // Add our test assembly last to override Storage
        ])

        resolver = assembler.resolver
        injectServices(resolver)
    }

    @Test("Storage is correctly initialized") func testStorageInitialization() {
        // Verify storage exists
        #expect(storage != nil, "OverrideStorage should be injected")

        // Verify it's the correct type
        #expect(storage is BaseOverrideStorage, "Storage should be of type BaseOverrideStorage")
    }

    @Test("Store and retrieve override") func testStoreAndRetrieveOverride() async throws {
        // Given
        let testOverride = Override(
            name: "Test Override",
            enabled: false,
            date: Date(),
            duration: 120,
            indefinite: false,
            percentage: 130,
            smbIsOff: true,
            isPreset: false,
            id: UUID().uuidString,
            overrideTarget: true,
            target: 110,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 1,
            end: 2,
            smbMinutes: 100,
            uamMinutes: 120
        )

        // When
        try await storage.storeOverride(override: testOverride)

        // Then verify stored entries
        let storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "name == %@", "Test Override"),
            key: "date",
            ascending: false
        ) as? [OverrideStored]

        #expect(storedEntries?.isEmpty == false, "Should have stored entries")
        #expect(storedEntries?.count == 1, "Should have exactly one entry")
        let storedOverride = storedEntries?.first
        #expect(storedOverride?.name == "Test Override", "Name should match")
        #expect(storedOverride?.percentage == 130, "Percentage should match")
        #expect(storedOverride?.target?.decimalValue == 110, "Target should match")
        #expect(storedOverride?.isPreset == false, "isPreset should match")
    }

    @Test("Store and retrieve override preset") func testStoreAndRetrieveOverridePreset() async throws {
        // Given
        let testPreset = Override(
            name: "Test Preset",
            enabled: false,
            date: Date(),
            duration: 0,
            indefinite: true,
            percentage: 120,
            smbIsOff: true,
            isPreset: true,
            id: UUID().uuidString,
            overrideTarget: true,
            target: 110,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 1,
            end: 2,
            smbMinutes: 100,
            uamMinutes: 120
        )

        // When
        try await storage.storeOverride(override: testPreset)
        let presetIDs = try await storage.fetchForOverridePresets()

        // Then
        #expect(!presetIDs.isEmpty, "Should have stored preset")

        let storedPresets = try await testContext.perform {
            try presetIDs.map { try testContext.existingObject(with: $0) as! OverrideStored }
        }

        #expect(storedPresets.count >= 1, "Should have at least one preset")
        let storedPreset = storedPresets.first { $0.name == "Test Preset" }
        #expect(storedPreset != nil, "Should find the test preset")
        #expect(storedPreset?.isPreset == true, "Should be marked as preset")
        #expect(storedPreset?.indefinite == true, "Should be indefinite")
        #expect(storedPreset?.percentage == 120, "Percentage should match")
    }

    @Test("Delete override preset") func testDeleteOverridePreset() async throws {
        // Given
        let testPreset = Override(
            name: "Delete Test",
            enabled: false,
            date: Date(),
            duration: 0,
            indefinite: true,
            percentage: 120,
            smbIsOff: true,
            isPreset: true,
            id: UUID().uuidString,
            overrideTarget: true,
            target: 110,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 1,
            end: 2,
            smbMinutes: 100,
            uamMinutes: 120
        )

        // Store the preset
        try await storage.storeOverride(override: testPreset)

        // Get the stored preset's ObjectID
        let storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "name == %@", "Delete Test"),
            key: "date",
            ascending: false
        ) as? [OverrideStored]

        guard let objectID = storedEntries?.first?.objectID else {
            throw TestError("Failed to get stored preset's ObjectID")
        }

        // When
        await storage.deleteOverridePreset(objectID)

        // Then verify deletion
        let remainingEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "name == %@", "Delete Test"),
            key: "date",
            ascending: false
        ) as? [OverrideStored]

        #expect(remainingEntries?.isEmpty == true, "Should have no entries after deletion")
    }

    @Test("Get overrides not yet uploaded to Nightscout") func testGetOverridesNotYetUploadedToNightscout() async throws {
        // Given
        let testOverride = Override(
            name: "NS Test",
            enabled: true, // getOverridesNotYetUploadedToNightscout() fetches only active overrides
            date: Date(),
            duration: 90,
            indefinite: false,
            percentage: 120,
            smbIsOff: true,
            isPreset: true,
            id: UUID().uuidString,
            overrideTarget: true,
            target: 110,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 1,
            end: 2,
            smbMinutes: 100,
            uamMinutes: 120
        )

        // When
        try await storage.storeOverride(override: testOverride)

        let notUploadedOverrides = try await storage.getOverridesNotYetUploadedToNightscout()

        // Then
        #expect(!notUploadedOverrides.isEmpty == true, "Should have overrides not uploaded to NS")
        #expect(notUploadedOverrides[0].notes == "NS Test", "Override name should match")
        #expect(notUploadedOverrides[0].duration == 90, "Duration should match")
        #expect(notUploadedOverrides[0].eventType == .nsExercise, "Event type should be exercise")
    }

    @Test("Expired finite overrides are not active") func testExpiredFiniteOverrideIsNotActive() async throws {
        let expiredOverride = Override(
            name: "Expired Override",
            enabled: true,
            date: Date().addingTimeInterval(-2.hours.timeInterval),
            duration: 30,
            indefinite: false,
            percentage: 50,
            smbIsOff: true,
            isPreset: false,
            id: UUID().uuidString,
            overrideTarget: true,
            target: 110,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 30,
            uamMinutes: 30
        )

        try await storage.storeOverride(override: expiredOverride)

        let activeOverrideIDs = try await storage.loadLatestOverrideConfigurations(fetchLimit: 1)

        #expect(activeOverrideIDs.isEmpty, "Expired finite overrides should not be active")
    }

    @Test("Exercise mode stores basal suspension and SMB suppression") func testExerciseModeOverrideValues() async throws {
        let exerciseOverride = Override(
            name: OverrideStored.exerciseModeName,
            enabled: true,
            date: Date(),
            duration: 180,
            indefinite: false,
            percentage: 0,
            smbIsOff: true,
            isPreset: false,
            id: UUID().uuidString,
            overrideTarget: true,
            target: 108,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 30,
            uamMinutes: 30
        )

        try await storage.storeOverride(override: exerciseOverride)

        let activeOverrideIDs = try await storage.loadLatestOverrideConfigurations(fetchLimit: 1)
        let activeOverrides = try await testContext.perform {
            try activeOverrideIDs.compactMap { try testContext.existingObject(with: $0) as? OverrideStored }
        }

        #expect(activeOverrides.first?.isExerciseMode == true, "Exercise Mode should be active")
        #expect(activeOverrides.first?.percentage == 0, "Exercise Mode should allow 0% basal")
        #expect(activeOverrides.first?.smbIsOff == true, "Exercise Mode should suppress SMBs when configured")
        #expect(activeOverrides.first?.target?.decimalValue == 108, "Exercise Mode should store the configured target")
    }

    @Test("Scheduled exercise mode is visible but not active before start") func testScheduledExerciseMode() async throws {
        let scheduledOverride = Override(
            name: OverrideStored.exerciseModeName,
            enabled: true,
            date: Date().addingTimeInterval(30.minutes.timeInterval),
            duration: 120,
            indefinite: false,
            percentage: 50,
            smbIsOff: true,
            isPreset: false,
            id: UUID().uuidString,
            overrideTarget: true,
            target: 108,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 30,
            uamMinutes: 30
        )

        try await storage.storeOverride(override: scheduledOverride)

        let activeOverrideIDs = try await storage.loadLatestOverrideConfigurations(fetchLimit: 1)
        let scheduledExerciseIDs = try await storage.fetchScheduledExerciseOverrides()

        #expect(activeOverrideIDs.isEmpty, "Scheduled Exercise Mode should not apply before its start time")
        #expect(scheduledExerciseIDs.count == 1, "Scheduled Exercise Mode should be listed for visibility")
    }

    @Test("Pre-exercise phase is active before activity start") func testPreExercisePhaseIsActiveBeforeActivity() async throws {
        let sessionID = UUID().uuidString
        let preExercise = Override(
            name: OverrideStored.exerciseOverrideName(type: ExerciseType.run.rawValue, phase: .preExercise),
            enabled: true,
            date: Date().addingTimeInterval(-15.minutes.timeInterval),
            duration: 60,
            indefinite: false,
            percentage: 0,
            smbIsOff: true,
            isPreset: false,
            id: sessionID,
            overrideTarget: true,
            target: 108,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 30,
            uamMinutes: 30
        )

        try await storage.storeOverride(override: preExercise)

        let activeOverrideIDs = try await storage.loadLatestOverrideConfigurations(fetchLimit: 1)
        let activeOverrides = try await testContext.perform {
            try activeOverrideIDs.compactMap { try testContext.existingObject(with: $0) as? OverrideStored }
        }

        #expect(activeOverrides.first?.exercisePhase == .preExercise)
        #expect(activeOverrides.first?.percentage == 0)
        #expect(activeOverrides.first?.smbIsOff == true)
    }

    @Test("Exercise phase replaces pre-exercise at activity start") func testExercisePhaseReplacesPreExercise() async throws {
        let sessionID = UUID().uuidString
        let preExercise = Override(
            name: OverrideStored.exerciseOverrideName(type: ExerciseType.run.rawValue, phase: .preExercise),
            enabled: true,
            date: Date().addingTimeInterval(-90.minutes.timeInterval),
            duration: 60,
            indefinite: false,
            percentage: 0,
            smbIsOff: true,
            isPreset: false,
            id: sessionID,
            overrideTarget: true,
            target: 108,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 30,
            uamMinutes: 30
        )
        let exercise = Override(
            name: OverrideStored.exerciseOverrideName(type: ExerciseType.run.rawValue, phase: .duringExercise),
            enabled: true,
            date: Date().addingTimeInterval(-30.minutes.timeInterval),
            duration: 120,
            indefinite: false,
            percentage: 40,
            smbIsOff: true,
            isPreset: false,
            id: sessionID,
            overrideTarget: true,
            target: 120,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 30,
            uamMinutes: 30
        )

        try await storage.storeOverride(override: preExercise)
        try await storage.storeOverride(override: exercise)

        let activeOverrideIDs = try await storage.loadLatestOverrideConfigurations(fetchLimit: 1)
        let activeOverrides = try await testContext.perform {
            try activeOverrideIDs.compactMap { try testContext.existingObject(with: $0) as? OverrideStored }
        }

        #expect(activeOverrides.first?.exercisePhase == .duringExercise)
        #expect(activeOverrides.first?.percentage == 40)
    }

    @Test("Post-exercise sensitivity decays and expires") func testPostExerciseSensitivityDecayAndExpiry() async throws {
        let now = Date()
        let postExercise = Override(
            name: OverrideStored.exerciseOverrideName(type: ExerciseType.run.rawValue, phase: .postExercise),
            enabled: true,
            date: now.addingTimeInterval(-4.hours.timeInterval),
            duration: 8 * 60,
            indefinite: false,
            percentage: 100,
            smbIsOff: false,
            isPreset: false,
            id: UUID().uuidString,
            overrideTarget: true,
            target: 108,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 30,
            end: Decimal(ExerciseSensitivityDecayType.linear.rawValue),
            smbMinutes: 30,
            uamMinutes: 30
        )

        try await storage.storeOverride(override: postExercise)

        let activeOverrideIDs = try await storage.loadLatestOverrideConfigurations(fetchLimit: 1)
        let activeOverrides = try await testContext.perform {
            try activeOverrideIDs.compactMap { try testContext.existingObject(with: $0) as? OverrideStored }
        }

        let effectiveSensitivity = activeOverrides.first?.effectivePostExerciseSensitivityPercent(at: now) ?? 0

        #expect(activeOverrides.first?.exercisePhase == .postExercise)
        #expect(effectiveSensitivity > 14 && effectiveSensitivity < 16)
        #expect(
            activeOverrides.first?
                .effectivePostExerciseSensitivityPercent(at: now.addingTimeInterval(9.hours.timeInterval)) == 0
        )
    }

    @Test("Short exercise creates no recovery effect") func testShortExerciseCreatesNoRecoveryEffect() {
        let recommendation = ExerciseRecoveryCalculator.recommendation(forExerciseDurationMinutes: 9)

        #expect(recommendation.durationMinutes == 0)
        #expect(recommendation.sensitivityPercent == 0)
        #expect(recommendation.hasRecoveryEffect == false)
    }

    @Test("Longer exercise creates proportional recovery") func testLongerExerciseCreatesProportionalRecovery() {
        let moderate = ExerciseRecoveryCalculator.recommendation(forExerciseDurationMinutes: 45)
        let long = ExerciseRecoveryCalculator.recommendation(forExerciseDurationMinutes: 90)
        let ultra = ExerciseRecoveryCalculator.recommendation(forExerciseDurationMinutes: 180)

        #expect(moderate.durationMinutes >= 240 && moderate.durationMinutes <= 480)
        #expect(moderate.sensitivityPercent >= 10 && moderate.sensitivityPercent <= 20)
        #expect(long.durationMinutes >= 480 && long.durationMinutes <= 720)
        #expect(long.sensitivityPercent >= 20 && long.sensitivityPercent <= 30)
        #expect(ultra.durationMinutes >= 720 && ultra.durationMinutes <= 1440)
        #expect(ultra.sensitivityPercent >= 25 && ultra.sensitivityPercent <= 40)
    }

    @Test("Exercise report export produces valid JSON") func testExerciseReportExportProducesValidJSON() throws {
        let report = ExerciseReport(
            id: UUID().uuidString,
            createdAt: Date(),
            exerciseType: ExerciseType.run.rawValue,
            customExerciseTypeName: nil,
            preExerciseStartTime: Date().addingTimeInterval(-90.minutes.timeInterval),
            exerciseStartTime: Date().addingTimeInterval(-30.minutes.timeInterval),
            exerciseStopTime: Date(),
            actualExerciseDurationMinutes: 30,
            startedAutomatically: true,
            startedEarly: false,
            wasCancelled: false,
            recoverySkippedReason: nil,
            recoveryDurationCalculatedMinutes: 240,
            recoverySensitivityAdjustmentCalculated: 10,
            decayModelUsed: .linear,
            preExerciseConfiguration: ExerciseReport.PhaseConfiguration(
                basalPercentage: 0,
                target: 108,
                smbSuppressed: true
            ),
            exerciseConfiguration: ExerciseReport.PhaseConfiguration(
                basalPercentage: 40,
                target: 108,
                smbSuppressed: true
            ),
            recoveryConfiguration: ExerciseReport.PhaseConfiguration(
                basalPercentage: 100,
                target: 108,
                smbSuppressed: false
            ),
            announcementStats: ExerciseReport.AnnouncementStats(
                announceGlucoseEnabled: true,
                announcementInterval: 5,
                includeTrend: true,
                includeRateOfChange: false,
                urgentAnnouncementsEnabled: true,
                numberOfAnnouncementsMade: 2
            ),
            glucoseStats: ExerciseReport.GlucoseStats(
                bgAtPreExerciseStart: 100,
                bgAtExerciseStart: 110,
                bgAtExerciseEnd: 120,
                bgAtRecoveryEnd: nil,
                minBGDuringExercise: 95,
                maxBGDuringExercise: 125,
                averageBGDuringExercise: 110,
                glucoseTrendBeforeExercise: 5,
                glucoseTrendAfterExercise: nil
            ),
            insulinStats: ExerciseReport.InsulinStats(
                iobAtPreExerciseStart: 1.2,
                iobAtExerciseStart: 0.8,
                iobAtExerciseEnd: 0.5,
                iobAtRecoveryEnd: nil,
                basalDeliveredDuringPreExercise: nil,
                basalDeliveredDuringExercise: nil,
                basalDeliveredDuringRecovery: nil,
                preExerciseSMBSuppressed: true,
                exerciseSMBSuppressed: true,
                recoverySMBSuppressed: false,
                bolusesDeliveredDuringSession: 0
            )
        )

        let url = try ExerciseReportStore.save(report)
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(object?["exerciseType"] as? String == ExerciseType.run.rawValue)
        #expect(object?["glucoseStats"] != nil)
        #expect(object?["insulinStats"] != nil)
        #expect(object?["announcementStats"] != nil)

        try? FileManager.default.removeItem(at: url)
    }

    @Test("Exercise glucose trend classification") func testExerciseGlucoseTrendClassification() {
        #expect(ExerciseGlucoseTrend.classify(rateMgdlPerMinute: -2) == .fallingFast)
        #expect(ExerciseGlucoseTrend.classify(rateMgdlPerMinute: -1) == .fallingSlowly)
        #expect(ExerciseGlucoseTrend.classify(rateMgdlPerMinute: 0) == .steady)
        #expect(ExerciseGlucoseTrend.classify(rateMgdlPerMinute: 1) == .risingSlowly)
        #expect(ExerciseGlucoseTrend.classify(rateMgdlPerMinute: 2) == .risingFast)
    }

    @Test(
        "Scheduled exercise with pre window already started is pre-exercise active"
    ) func testScheduledExerciseWithPreWindowAlreadyStartedIsActive() {
        let now = Date()
        let metadata = ExerciseSessionMetadata(
            sessionID: UUID().uuidString,
            exerciseTypeName: ExerciseType.run.rawValue,
            sessionCreatedAt: now,
            scheduledExerciseStart: now.addingTimeInterval(3.minutes.timeInterval),
            preExerciseStart: now.addingTimeInterval(-57.minutes.timeInterval),
            postExerciseEnabled: true,
            postExerciseBasalPercentage: 100,
            postExerciseTarget: 108,
            postExerciseSuppressSMB: false,
            announcementSettings: ExerciseAnnouncementSettings()
        )

        #expect(metadata.state(at: now) == .preExerciseActive)
        #expect(metadata.state(at: now.addingTimeInterval(3.minutes.timeInterval + 1)) == .exerciseActive)
    }

    @Test("Exercise session state completes after recovery expiry") func testExerciseSessionCompletesAfterRecoveryExpiry() {
        let now = Date()
        let metadata = ExerciseSessionMetadata(
            sessionID: UUID().uuidString,
            exerciseTypeName: ExerciseType.ultraRun.rawValue,
            sessionCreatedAt: now.addingTimeInterval(-4.hours.timeInterval),
            scheduledExerciseStart: now.addingTimeInterval(-3.hours.timeInterval),
            actualExerciseStart: now.addingTimeInterval(-3.hours.timeInterval),
            actualExerciseEnd: now.addingTimeInterval(-2.hours.timeInterval),
            recoveryStart: now.addingTimeInterval(-2.hours.timeInterval),
            recoveryEnd: now.addingTimeInterval(-1.minutes.timeInterval),
            postExerciseEnabled: true,
            postExerciseBasalPercentage: 100,
            postExerciseTarget: 108,
            postExerciseSuppressSMB: false,
            announcementSettings: ExerciseAnnouncementSettings()
        )

        #expect(metadata.state(at: now) == .completed)
    }
}
