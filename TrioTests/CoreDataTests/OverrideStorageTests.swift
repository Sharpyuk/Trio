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
}

@Suite("Exercise Mode Domain Tests") struct ExerciseModeDomainTests {
    private func session(start: Date, created: Date? = nil) -> ExerciseSession {
        ExerciseSession(
            id: UUID(),
            preset: ExercisePreset.defaults[0],
            createdAt: created ?? start.addingTimeInterval(-3600),
            scheduledExerciseStart: start
        )
    }

    @Test("Missed scheduled transitions reconcile directly to Active") func missedTransition() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var value = session(start: start)
        ExerciseReconciler.reconcile(&value, at: start.addingTimeInterval(15 * 60))
        #expect(value.actualPreExerciseStart != nil)
        #expect(value.actualExerciseStart == start)
        #expect(value.phase(at: start.addingTimeInterval(15 * 60)) == .active)
    }

    @Test("Reconciliation does not duplicate timestamps") func idempotentReconciliation() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var value = session(start: start)
        ExerciseReconciler.reconcile(&value, at: start.addingTimeInterval(60))
        let pre = value.actualPreExerciseStart
        let active = value.actualExerciseStart
        ExerciseReconciler.reconcile(&value, at: start.addingTimeInterval(600))
        #expect(value.actualPreExerciseStart == pre)
        #expect(value.actualExerciseStart == active)
    }

    @Test("Relaunch derives pre-exercise and active phases from persisted timestamps") func relaunchReconciliation() {
        let start = Date(timeIntervalSince1970: 1_000_000)

        var preExercise = session(start: start, created: start.addingTimeInterval(-3600))
        ExerciseReconciler.reconcile(&preExercise, at: start.addingTimeInterval(-60))
        #expect(preExercise.phase(at: start.addingTimeInterval(-60)) == .preExercise)
        #expect(preExercise.actualExerciseStart == nil)

        var active = session(start: start, created: start.addingTimeInterval(-3600))
        ExerciseReconciler.reconcile(&active, at: start.addingTimeInterval(60))
        #expect(active.phase(at: start.addingTimeInterval(60)) == .active)
        #expect(active.actualExerciseStart == start)
    }

    @Test("Pre, active, recovery, and completion timestamps are unique") func phaseTransitionsAreUnique() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var value = session(start: start, created: start.addingTimeInterval(-3600))
        ExerciseReconciler.reconcile(&value, at: start)
        ExerciseReconciler.stopExercise(&value, at: start.addingTimeInterval(30 * 60))

        #expect(value.actualPreExerciseStart != nil)
        #expect(value.actualExerciseStart == start)
        #expect(value.actualExerciseEnd == start.addingTimeInterval(30 * 60))
        #expect(value.recoveryStart == value.actualExerciseEnd)
        #expect(value.phase(at: start.addingTimeInterval(31 * 60)) == .recovery)

        let recoveryEnd = value.recommendedRecoveryEnd!
        ExerciseReconciler.reconcile(&value, at: recoveryEnd.addingTimeInterval(60))
        let completed = value
        ExerciseReconciler.reconcile(&value, at: recoveryEnd.addingTimeInterval(120))
        #expect(value == completed)
        #expect(value.actualRecoveryEnd == recoveryEnd)
        #expect(value.completedAt == recoveryEnd)
        #expect(value.phase(at: recoveryEnd) == .completed)
    }

    @Test("Default pre-exercise settings are independent from active settings") func independentPreExerciseDefaults() {
        for preset in ExercisePreset.defaults {
            #expect(preset.preExercise.basalPercentage == 0)
            #expect(preset.preExercise.insulinStrengthPercentage == 0)
            #expect(preset.preExercise.smbEnabled == false)
            #expect(preset.preExercise.target == nil)
        }
    }

    @Test("Optional target stays absent") func optionalTarget() {
        let start = Date()
        var value = session(start: start)
        ExerciseReconciler.startExerciseNow(&value, at: start)
        #expect(EffectiveExerciseAdjustment.resolve(session: value, at: start)?.target == nil)
    }

    @Test("Short exercise has no recovery") func shortExercise() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var value = session(start: start)
        ExerciseReconciler.startExerciseNow(&value, at: start)
        ExerciseReconciler.stopExercise(&value, at: start.addingTimeInterval(9 * 60))
        #expect(value.recoveryStart == nil)
        #expect(value.completedAt != nil)
    }

    @Test("Long recovery is capped at 24 hours") func recoveryCap() {
        #expect(ExerciseRecoveryCalculator.recommendation(forExerciseDuration: 20 * 3600) == 24 * 3600)
    }
}

@Suite("Exercise correction scaling tests") struct ExerciseCorrectionScalingTests {
    @Test("Positive correction scales deterministically", arguments: [
        (Decimal(1), Decimal(1)),
        (Decimal(string: "0.75")!, Decimal(string: "0.75")!),
        (Decimal(string: "0.5")!, Decimal(string: "0.5")!),
        (Decimal(string: "0.25")!, Decimal(string: "0.25")!),
        (Decimal(0), Decimal(0))
    ]) func positiveCorrection(scale: Decimal, expected: Decimal) {
        #expect(DosingEngine.exerciseScaledInsulinRequired(1, scale: scale) == expected)
    }

    @Test("Negative correction is preserved exactly", arguments: [
        Decimal(1), Decimal(string: "0.75")!, Decimal(string: "0.5")!, Decimal(string: "0.25")!, Decimal(0)
    ]) func negativeCorrection(scale: Decimal) {
        let requirement = Decimal(string: "-0.375")!
        #expect(DosingEngine.exerciseScaledInsulinRequired(requirement, scale: scale) == requirement)
    }

    @Test("High temp uses the scaled correction requirement") func highTempUsesScaledRequirement() {
        let scaled = DosingEngine.exerciseScaledInsulinRequired(1, scale: Decimal(string: "0.25")!)
        #expect(scaled == Decimal(string: "0.25")!)
        #expect(DosingEngine.requestedHighTempBasalRate(basal: 1, insulinRequired: scaled) == Decimal(string: "1.5")!)
        #expect(DosingEngine.requestedHighTempBasalRate(basal: 1, insulinRequired: 1) == 3)
    }

    @Test("SMB uses the scaled correction requirement") func smbUsesScaledRequirement() {
        let normal = DosingEngine.recommendedMicroBolus(
            insulinRequired: 1, deliveryRatio: Decimal(string: "0.5")!, maxBolus: 1, bolusIncrement: Decimal(string: "0.1")!
        )
        let scaled = DosingEngine.exerciseScaledInsulinRequired(1, scale: Decimal(string: "0.25")!)
        let exercise = DosingEngine.recommendedMicroBolus(
            insulinRequired: scaled, deliveryRatio: Decimal(string: "0.5")!, maxBolus: 1, bolusIncrement: Decimal(string: "0.1")!
        )
        #expect(normal == Decimal(string: "0.5")!)
        #expect(exercise == Decimal(string: "0.1")!)
    }

    @Test("SMB disabled cannot restore removed correction through high temp") func smbDisabledCannotRestoreCorrection() {
        let scaled = DosingEngine.exerciseScaledInsulinRequired(1, scale: 0)
        #expect(scaled == 0)
        #expect(
            DosingEngine.recommendedMicroBolus(
                insulinRequired: scaled,
                deliveryRatio: 1,
                maxBolus: 1,
                bolusIncrement: Decimal(string: "0.1")!
            ) == 0
        )
        #expect(DosingEngine.requestedHighTempBasalRate(basal: 1, insulinRequired: scaled) == 1)
    }
}
