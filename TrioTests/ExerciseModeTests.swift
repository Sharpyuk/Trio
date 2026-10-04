import CoreData
import Foundation
import Testing

@testable import Trio

@Suite("Exercise Mode persistence and state machine", .serialized) struct ExerciseModeTests {
    let stack: CoreDataStack
    let manager: BaseExerciseModeManager

    init() async throws {
        stack = try await CoreDataStack.createForTests()
        let capturedStack = stack
        manager = BaseExerciseModeManager(contextProvider: { capturedStack.newTaskContext() })
    }

    private var pre: ExercisePhaseConfiguration {
        ExercisePhaseConfiguration(
            insulinPercentage: 50,
            basalPercentage: 20,
            correctionPercentage: 50,
            smbEnabled: false,
            sensitivityPercentage: 125,
            targetGlucose: 150,
            durationMinutes: 45
        )
    }

    private var exercise: ExercisePhaseConfiguration {
        ExercisePhaseConfiguration(
            insulinPercentage: 35,
            basalPercentage: 100,
            correctionPercentage: 100,
            smbEnabled: false,
            sensitivityPercentage: 100,
            targetGlucose: 145,
            announcementEnabled: true
        )
    }

    private func post(percent: Decimal = 70, minutes: Decimal = 60) -> ExercisePhaseConfiguration {
        ExercisePhaseConfiguration(
            insulinPercentage: percent,
            basalPercentage: 100,
            correctionPercentage: 100,
            smbEnabled: false,
            sensitivityPercentage: 100,
            targetGlucose: 120,
            durationMinutes: minutes
        )
    }

    @Test("inactive to PRE") func inactiveToPre() async throws {
        let now = Date()
        let state = try await manager.startPreExercise(
            configuration: pre,
            exerciseConfiguration: exercise,
            scheduledExerciseAt: now.addingTimeInterval(45 * 60),
            source: .app,
            at: now
        )
        #expect(state.phase == .preExercise)
        #expect(await counts() == Counts(activeSessions: 1, activePhases: 1, sessions: 1, phases: 1))
    }

    @Test("inactive to EXERCISE") func inactiveToExercise() async throws {
        let state = try await manager.startExercise(configuration: exercise, source: .app, at: Date())
        #expect(state.phase == .exercise)
        #expect(await counts().activeSessions == 1)
        #expect(await counts().activePhases == 1)
    }

    @Test("PRE to EXERCISE is one persisted transition") func preToExercise() async throws {
        let now = Date()
        try await startPre(at: now)
        let state = try await manager.startExercise(configuration: nil, source: .app, at: now.addingTimeInterval(10 * 60))
        #expect(state.phase == .exercise)

        let phases = await phaseRows()
        #expect(phases.count == 2)
        #expect(phases.filter(\.isActive).count == 1)
        #expect(phases.first(where: { $0.kind == ExercisePhase.preExercise.rawValue })?.endDate != nil)
    }

    @Test("Manual Start Exercise transitions before scheduled time") func manualEarlyTransition() async throws {
        let now = Date()
        try await startPre(at: now, scheduled: now.addingTimeInterval(60 * 60))
        let state = try await manager.startExercise(configuration: nil, source: .app, at: now.addingTimeInterval(5 * 60))
        #expect(state.phase == .exercise)
    }

    @Test("PRE transition failure rolls back and leaves PRE active") func failedPreTransitionLeavesPre() async throws {
        let now = Date()
        try await startPre(at: now)
        let capturedStack = stack
        let failing = BaseExerciseModeManager(
            contextProvider: { capturedStack.newTaskContext() },
            beforeSave: { mutation in
                if mutation == .preToExercise { throw InjectedFailure() }
            }
        )

        await #expect(throws: ExerciseModeError.self) {
            try await failing.startExercise(configuration: nil, source: .app, at: now.addingTimeInterval(60))
        }
        #expect(try await manager.currentState().phase == .preExercise)
        #expect(await counts().activePhases == 1)
        #expect(await transitionRows().contains { !$0.succeeded && $0.toPhase == ExercisePhase.exercise.rawValue })
    }

    @Test("Automatic PRE transition failure never expires to inactive") func failedScheduledTransitionLeavesPre() async throws {
        let now = Date()
        try await startPre(at: now, scheduled: now.addingTimeInterval(60))
        let capturedStack = stack
        let failing = BaseExerciseModeManager(
            contextProvider: { capturedStack.newTaskContext() },
            beforeSave: { mutation in
                if mutation == .preToExercise { throw InjectedFailure() }
            }
        )
        await #expect(throws: ExerciseModeError.self) {
            try await failing.reconcile(at: now.addingTimeInterval(120))
        }
        #expect(try await manager.currentState().phase == .preExercise)
    }

    @Test("EXERCISE to POST") func exerciseToPost() async throws {
        let now = Date()
        try await manager.startExercise(configuration: exercise, source: .app, at: now)
        let state = try await manager.stopExercise(
            postConfigurations: [post()],
            source: .app,
            at: now.addingTimeInterval(2 * 60 * 60)
        )
        #expect(state.phase == .postExercise)
        #expect(await counts().activePhases == 1)
    }

    @Test("EXERCISE to inactive skips POST") func exerciseToInactive() async throws {
        let now = Date()
        try await manager.startExercise(configuration: exercise, source: .app, at: now)
        let state = try await manager.stopExercise(
            postConfigurations: [],
            source: .app,
            at: now.addingTimeInterval(60)
        )
        #expect(state == .inactive)
        #expect(await counts().activeSessions == 0)
        #expect(await counts().activePhases == 0)
    }

    @Test("POST to inactive is persisted") func postToInactive() async throws {
        let now = Date()
        try await startPost(at: now)
        let state = try await manager.endPostExercise(source: .app, at: now.addingTimeInterval(30 * 60))
        #expect(state == .inactive)
        #expect(await transitionRows().contains {
            $0.succeeded && $0.fromPhase == ExercisePhase.postExercise.rawValue && $0.toPhase == "inactive"
        })
    }

    @Test("PRE can be cancelled to inactive") func cancelPreExercise() async throws {
        let now = Date()
        try await startPre(at: now)
        let state = try await manager.cancelPreExercise(source: .app, at: now.addingTimeInterval(60))
        #expect(state == .inactive)
        #expect(await counts().activeSessions == 0)
        #expect(await transitionRows().contains {
            $0.succeeded && $0.fromPhase == ExercisePhase.preExercise.rawValue && $0.toPhase == "inactive"
        })
    }

    @Test("Expired POST deterministically returns to inactive") func postExpiryReconciliation() async throws {
        let now = Date()
        try await startPost(at: now, configuration: post(minutes: 60))
        let state = try await manager.reconcile(at: now.addingTimeInterval(61 * 60))
        #expect(state == .inactive)
        let transition = await transitionRows().last
        #expect(transition?.committedAt == now.addingTimeInterval(60 * 60))
    }

    @Test("POST taper segments advance and retain snapshots") func postTaperSegments() async throws {
        let now = Date()
        try await manager.startExercise(configuration: exercise, source: .app, at: now)
        try await manager.stopExercise(
            postConfigurations: [post(percent: 70, minutes: 60), post(percent: 85, minutes: 60)],
            source: .app,
            at: now
        )
        let state = try await manager.reconcile(at: now.addingTimeInterval(61 * 60))
        guard case let .active(active) = state else { Issue.record("Expected active second POST segment")
            return }
        #expect(active.phase == .postExercise)
        #expect(active.postSegmentIndex == 1)
        #expect(active.configuration.insulinPercentage == 85)
    }

    @Test("Invalid transitions return errors and are logged") func invalidTransitions() async throws {
        await #expect(throws: ExerciseModeError.invalidTransition(from: nil, to: nil)) {
            try await manager.endPostExercise(source: .app, at: Date())
        }
        #expect(await transitionRows().count == 1)
        #expect(await transitionRows().first?.succeeded == false)
    }

    @Test("Restart preserves PRE") func restartPre() async throws {
        let now = Date()
        try await startPre(at: now, scheduled: now.addingTimeInterval(60 * 60))
        let restarted = BaseExerciseModeManager(contextProvider: { stack.newTaskContext() })
        #expect(try await restarted.reconcile(at: now.addingTimeInterval(10 * 60)).phase == .preExercise)
    }

    @Test("Restart preserves indefinite EXERCISE") func restartExercise() async throws {
        let now = Date()
        try await manager.startExercise(configuration: exercise, source: .app, at: now)
        let restarted = BaseExerciseModeManager(contextProvider: { stack.newTaskContext() })
        #expect(try await restarted.reconcile(at: now.addingTimeInterval(24 * 60 * 60)).phase == .exercise)
    }

    @Test("Restart preserves unexpired POST") func restartPost() async throws {
        let now = Date()
        try await startPost(at: now, configuration: post(minutes: 120))
        let restarted = BaseExerciseModeManager(contextProvider: { stack.newTaskContext() })
        #expect(try await restarted.reconcile(at: now.addingTimeInterval(60 * 60)).phase == .postExercise)
    }

    @Test("Restart while inactive stays inactive") func restartInactive() async throws {
        let restarted = BaseExerciseModeManager(contextProvider: { stack.newTaskContext() })
        #expect(try await restarted.reconcile(at: Date()) == .inactive)
    }

    @Test("Historical configuration snapshot never follows changed defaults") func snapshotDoesNotChange() async throws {
        let now = Date()
        try await manager.startExercise(configuration: exercise, source: .app, at: now)
        var changedDefault = exercise
        changedDefault.insulinPercentage = 40
        _ = changedDefault // A later default is deliberately not written to the phase.

        let state = try await manager.currentState()
        guard case let .active(active) = state else { Issue.record("Expected active exercise")
            return }
        #expect(active.configuration.insulinPercentage == 35)
        let stored = await phaseRows().first
        #expect(stored?.insulinPercentage?.decimalValue == 35)
    }

    @MainActor
    @Test("UI defaults persist while active snapshot remains unchanged") func uiDefaultsPersistWithoutChangingSnapshot() async throws {
        let suite = "ExerciseModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "defaults"
        let controller = ExerciseModeController(
            manager: manager,
            userDefaults: defaults,
            storageKey: key,
            observeLifecycle: false,
            loadOnInit: false
        )
        var preset = controller.selectedPreset
        preset.strategy.exercise.insulinPercentage = 40
        controller.save(preset)
        controller.select(preset.id)
        await controller.startExerciseNow()
        preset.strategy.exercise.insulinPercentage = 45
        controller.save(preset)

        guard case let .active(active) = controller.state else {
            Issue.record("Expected active Exercise state")
            return
        }
        #expect(active.configuration.insulinPercentage == 40)

        let reloaded = ExerciseModeController(
            manager: manager,
            userDefaults: defaults,
            storageKey: key,
            observeLifecycle: false,
            loadOnInit: false
        )
        #expect(reloaded.selectedPreset.strategy.exercise.insulinPercentage == 45)
    }

    @MainActor
    @Test("Session edits do not mutate their source preset") func sessionDraftIsIsolatedFromPreset() throws {
        let suite = "ExerciseModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "session-copy"
        let controller = ExerciseModeController(
            manager: manager,
            userDefaults: defaults,
            storageKey: key,
            observeLifecycle: false,
            loadOnInit: false
        )
        let source = controller.selectedPreset

        controller.sessionDraft.strategy.exercise.insulinPercentage = 25
        controller.sessionDraft.strategy.exercise.targetGlucose = 155

        #expect(controller.selectedPreset == source)
        let restarted = ExerciseModeController(
            manager: manager,
            userDefaults: defaults,
            storageKey: key,
            observeLifecycle: false,
            loadOnInit: false
        )
        #expect(restarted.selectedPreset == source)
    }

    @MainActor
    @Test("Scheduled session snapshot survives controller restart") func scheduledSnapshotSurvivesRestart() throws {
        let suite = "ExerciseModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "schedule-restart"
        let controller = ExerciseModeController(
            manager: manager,
            userDefaults: defaults,
            storageKey: key,
            observeLifecycle: false,
            loadOnInit: false
        )
        controller.sessionDraft.strategy.exercise.insulinPercentage = 30
        let start = Date().addingTimeInterval(3600)
        controller.schedule(start)

        let restarted = ExerciseModeController(
            manager: manager,
            userDefaults: defaults,
            storageKey: key,
            observeLifecycle: false,
            loadOnInit: false
        )
        #expect(restarted.schedule?.exerciseStart == start)
        #expect(restarted.schedule?.presetSnapshot.strategy.exercise.insulinPercentage == 30)
        #expect(restarted.selectedPreset.strategy.exercise.insulinPercentage != 30)
    }

    @Test("Concurrent starts leave one active session and phase") func onlyOneActiveSessionAndPhase() async throws {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = try? await manager.startExercise(configuration: exercise, source: .app, at: Date()) }
            group.addTask { _ = try? await manager.startExercise(configuration: exercise, source: .app, at: Date()) }
            await group.waitForAll()
        }
        let result = await counts()
        #expect(result.activeSessions == 1)
        #expect(result.activePhases == 1)
    }

    @Test("Core Data model can infer migration from pre-Exercise schema") func lightweightMigration() throws {
        let current = CoreDataStack.managedObjectModel
        let old = current.copy() as! NSManagedObjectModel
        old.entities = old.entities.filter { !($0.name?.hasPrefix("Exercise") ?? false) }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Trio.sqlite")

        let oldCoordinator = NSPersistentStoreCoordinator(managedObjectModel: old)
        _ = try oldCoordinator.addPersistentStore(type: .sqlite, at: url)
        try oldCoordinator.remove(oldCoordinator.persistentStores[0])

        let currentCoordinator = NSPersistentStoreCoordinator(managedObjectModel: current)
        _ = try currentCoordinator.addPersistentStore(
            type: .sqlite,
            at: url,
            options: [
                NSMigratePersistentStoresAutomaticallyOption: true,
                NSInferMappingModelAutomaticallyOption: true
            ]
        )
        #expect(currentCoordinator.persistentStores.count == 1)
    }

    private func startPre(at date: Date, scheduled: Date? = nil) async throws {
        _ = try await manager.startPreExercise(
            configuration: pre,
            exerciseConfiguration: exercise,
            scheduledExerciseAt: scheduled ?? date.addingTimeInterval(45 * 60),
            source: .app,
            at: date
        )
    }

    private func startPost(at date: Date, configuration: ExercisePhaseConfiguration? = nil) async throws {
        _ = try await manager.startExercise(configuration: exercise, source: .app, at: date)
        _ = try await manager.stopExercise(
            postConfigurations: [configuration ?? post()],
            source: .app,
            at: date
        )
    }

    private func counts() async -> Counts {
        let context = stack.newTaskContext()
        return await context.perform {
            func count(_ entity: String, predicate: NSPredicate? = nil) -> Int {
                let request = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
                request.predicate = predicate
                return (try? context.count(for: request)) ?? -1
            }
            return Counts(
                activeSessions: count("ExerciseSessionStored", predicate: NSPredicate(format: "status == %@", "active")),
                activePhases: count("ExercisePhaseStored", predicate: NSPredicate(format: "isActive == YES")),
                sessions: count("ExerciseSessionStored"),
                phases: count("ExercisePhaseStored")
            )
        }
    }

    private func phaseRows() async -> [PhaseRow] {
        let context = stack.newTaskContext()
        return await context.perform {
            let request: NSFetchRequest<ExercisePhaseStored> = ExercisePhaseStored.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: true)]
            return (try? context.fetch(request))?.map {
                PhaseRow(
                    kind: $0.kind,
                    isActive: $0.isActive,
                    endDate: $0.endDate,
                    insulinPercentage: $0.insulinPercentage
                )
            } ?? []
        }
    }

    private func transitionRows() async -> [TransitionRow] {
        let context = stack.newTaskContext()
        return await context.perform {
            let request: NSFetchRequest<ExerciseTransitionStored> = ExerciseTransitionStored.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "requestedAt", ascending: true)]
            return (try? context.fetch(request))?.map {
                TransitionRow(
                    fromPhase: $0.fromPhase,
                    toPhase: $0.toPhase,
                    committedAt: $0.committedAt,
                    succeeded: $0.succeeded
                )
            } ?? []
        }
    }
}

@Suite(
    "Exercise-inactive dosing baseline",
    .serialized,
    .enabled(if: ParityEnv.isPinned, "pipeline baselines require \(ParityEnv.timeZoneIdentifier)")
) struct ExerciseInactiveDosingBaselineTests {
    private func pipeline(_ name: String) throws -> Determination {
        let output = try ParityScenarios.runPipeline(ParityScenarios.build(name))
        return try #require(output.determination)
    }

    private func blankDetermination() -> Determination {
        Determination(
            id: UUID(), reason: "", units: nil, insulinReq: nil, eventualBG: nil,
            sensitivityRatio: nil, rate: nil, duration: nil, iob: nil, cob: nil,
            predictions: nil, deliverAt: nil, carbsReq: nil, temp: nil, bg: nil,
            reservoir: nil, isf: nil, timestamp: nil, tdd: nil, current_target: nil,
            minDelta: nil, expectedDelta: nil, minGuardBG: nil, minPredBG: nil,
            threshold: nil, carbRatio: nil, received: nil
        )
    }

    @Test("inactive Exercise context is a dosing identity") func inactiveContextIsIdentity() {
        let context = ExerciseDosingContext.inactive
        #expect(context.phase == nil)
        #expect(context.effectiveBasalFactor == 1)
        #expect(context.effectivePositiveCorrectionFactor == 1)
        #expect(context.smbEnabled)
        #expect(context.sensitivityFactor == 1)
        #expect(context.targetGlucose == nil)
    }

    @Test("proposed factors compose once without an SMB double multiplier") func factorComposition() {
        let context = ExerciseDosingContext(
            phase: .exercise,
            configuration: ExercisePhaseConfiguration(
                insulinPercentage: 35,
                basalPercentage: 100,
                correctionPercentage: 100,
                smbEnabled: true,
                sensitivityPercentage: 100,
                targetGlucose: 140
            )
        )
        #expect(context.effectiveBasalFactor == 0.35)
        #expect(context.effectivePositiveCorrectionFactor == 0.35)
    }

    @Test("active state is captured as one immutable phase/configuration snapshot") func activeSnapshotCapture() {
        let sessionID = UUID()
        let phaseID = UUID()
        let configuration = ExercisePhaseConfiguration(
            insulinPercentage: 35,
            basalPercentage: 80,
            correctionPercentage: 60,
            smbEnabled: false,
            sensitivityPercentage: 125,
            targetGlucose: 145,
            announcementEnabled: true,
            announcementIntervalMinutes: 3
        )
        let context = ExerciseDosingContext(state: .active(ExerciseModeActiveState(
            sessionID: sessionID,
            phaseID: phaseID,
            phase: .preExercise,
            phaseStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
            scheduledExerciseAt: Date(timeIntervalSince1970: 1_700_003_600),
            postSegmentIndex: 0,
            configuration: configuration
        )))

        #expect(context.sessionID == sessionID)
        #expect(context.phaseID == phaseID)
        #expect(context.phase == .preExercise)
        #expect(context.configuration == configuration)
        #expect(context.effectiveBasalFactor == Decimal(string: "0.28"))
        #expect(context.effectivePositiveCorrectionFactor == Decimal(string: "0.21"))
        #expect(!context.smbEnabled)
        #expect(context.sensitivityFactor == 1.25)
        #expect(context.targetGlucose == 145)
    }

    @Test("at target has zero correction requirement") func glucoseAtTarget() {
        let result = DosingEngine.calculateInsulinRequired(
            minForecastGlucose: 100, eventualGlucose: 100, targetGlucose: 100,
            adjustedSensitivity: 50, maxIob: 5, currentIob: 0,
            determination: blankDetermination()
        )
        #expect(result.insulinRequired == 0)
        #expect(result.determination.insulinReq == 0)
    }

    @Test("positive and negative correction requirements retain current signs and values") func correctionRequirements() {
        let positive = DosingEngine.calculateInsulinRequired(
            minForecastGlucose: 150, eventualGlucose: 180, targetGlucose: 100,
            adjustedSensitivity: 50, maxIob: 5, currentIob: 0,
            determination: blankDetermination()
        )
        let negative = DosingEngine.calculateInsulinRequired(
            minForecastGlucose: 90, eventualGlucose: 95, targetGlucose: 100,
            adjustedSensitivity: 50, maxIob: 5, currentIob: 0,
            determination: blankDetermination()
        )
        #expect(positive.insulinRequired == 1)
        #expect(negative.insulinRequired == -0.2)
    }

    @Test("max IOB caps positive correction before delivery paths") func maxIobLimit() {
        let result = DosingEngine.calculateInsulinRequired(
            minForecastGlucose: 200, eventualGlucose: 200, targetGlucose: 100,
            adjustedSensitivity: 20, maxIob: 3, currentIob: 1,
            determination: blankDetermination()
        )
        #expect(result.insulinRequired == 2)
        #expect(result.determination.reason.contains("max_iob 3"))
    }

    @Test("inactive baseline preserves high-temp construction and max-basal safety") func highTempBaseline() throws {
        var profile = Profile()
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.maxBasal = 2

        let result = try DosingEngine.determineHighTempBasal(
            insulinRequired: 1,
            basal: 1,
            profile: profile,
            currentTemp: TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date()),
            determination: blankDetermination()
        )

        #expect(result.rate == 2)
        #expect(result.duration == 30)
        #expect(result.reason.contains("maxSafeBasal: 2"))
    }

    @Test("inactive baseline preserves excessive high-temp cancellation") func excessiveTempBaseline() throws {
        var profile = Profile()
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.maxBasal = 5

        let result = try DosingEngine.determineHighTempBasal(
            insulinRequired: 0.5,
            basal: 1,
            profile: profile,
            currentTemp: TempBasal(duration: 30, rate: 4, temp: .absolute, timestamp: Date()),
            determination: blankDetermination()
        )

        #expect(result.rate == 2)
        #expect(result.duration == 30)
        #expect(result.reason.contains("> 2 * insulinReq"))
    }

    @Test("inactive baseline preserves zero and low temp clamping") func zeroAndLowTempBaseline() throws {
        var profile = Profile()
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.maxBasal = 5

        let zero = try TempBasalFunctions.setTempBasal(
            rate: -1,
            duration: 30,
            profile: profile,
            determination: blankDetermination(),
            currentTemp: TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date())
        )
        let low = try TempBasalFunctions.setTempBasal(
            rate: 0.4,
            duration: 30,
            profile: profile,
            determination: blankDetermination(),
            currentTemp: TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date())
        )

        #expect(zero.rate == 0)
        #expect(zero.duration == 30)
        #expect(low.rate == 0.4)
        #expect(low.duration == 30)
    }

    @Test("strong rise with UAM keeps current SMB and high-temp output") func risingUamSmbBaseline() throws {
        let result = try pipeline("high-bg-rising-smb")
        #expect(result.bg == 210)
        #expect(result.insulinReq == 0.96)
        #expect(result.units == 0.4)
        #expect(result.rate == 2.8)
        #expect(result.duration == 30)
        #expect(result.predictions?.uam?.last == 108)
    }

    @Test("falling and predicted-low glucose retain zero-temp safety") func fallingPredictedLowBaseline() throws {
        let result = try pipeline("low-bg-falling")
        #expect(result.bg == 68)
        #expect(result.minGuardBG == -45)
        #expect(result.rate == 0)
        #expect(result.duration == 120)
        #expect(result.units == nil)
    }

    @Test("COB contributes to forecasts and current SMB output") func cobBaseline() throws {
        let result = try pipeline("post-meal-cob-active")
        #expect(result.cob == 26)
        #expect(result.insulinReq == 0.84)
        #expect(result.units == 0.4)
        #expect(result.predictions?.cob?.last == 168)
    }

    @Test("SMB-disabled path remains temp-basal only") func smbDisabledBaseline() throws {
        let result = try pipeline("smb-disabled-temp-only")
        #expect(result.units == nil)
        #expect(result.rate == 0.45)
        #expect(result.duration == 30)
    }

    @Test("dynamic ISF baseline remains unchanged") func dynamicIsfBaseline() throws {
        let result = try pipeline("dynamic-isf-logarithmic")
        #expect(result.sensitivityRatio?.jsRounded(scale: 2) == 1.16)
        #expect(result.insulinReq == 0.4)
        #expect(result.units == 0.2)
        #expect(result.reason.contains("Dynamic ISF: On"))
    }

    @Test("ordinary Override baseline remains unchanged") func overrideBaseline() throws {
        let result = try pipeline("override-active")
        #expect(result.current_target == 90)
        #expect(result.sensitivityRatio == 1)
        #expect(result.insulinReq == 0.71)
        #expect(result.units == 0.3)
        #expect(result.rate == 0.38)
    }

    @Test("Temp Target baseline retains raised target and zero-temp output") func tempTargetBaseline() throws {
        let result = try pipeline("temp-target-active")
        #expect(result.current_target == 130)
        #expect(result.sensitivityRatio == 0.67)
        #expect(result.rate == 0)
        #expect(result.duration == 120)
        #expect(result.units == nil)
    }
}

@Suite(
    "Exercise dosing integration",
    .serialized,
    .enabled(if: ParityEnv.isPinned, "pipeline tests require \(ParityEnv.timeZoneIdentifier)")
) struct ExerciseDosingIntegrationTests {
    private func context(
        phase: ExercisePhase = .exercise,
        overall: Decimal = 35,
        basal: Decimal = 100,
        correction: Decimal = 100,
        smb: Bool = false,
        sensitivity: Decimal = 100,
        target: Decimal = 95
    ) -> ExerciseDosingContext {
        ExerciseDosingContext(
            sessionID: UUID(),
            phaseID: UUID(),
            phase: phase,
            configuration: ExercisePhaseConfiguration(
                insulinPercentage: overall,
                basalPercentage: basal,
                correctionPercentage: correction,
                smbEnabled: smb,
                sensitivityPercentage: sensitivity,
                targetGlucose: target
            )
        )
    }

    private func pipeline(
        _ name: String,
        context: ExerciseDosingContext = .inactive
    ) throws -> Determination {
        let output = try ParityScenarios.runPipeline(
            ParityScenarios.build(name),
            exerciseDosingContext: context
        )
        return try #require(output.determination)
    }

    @Test("inactive context preserves the exact native determination") func inactiveIdentity() throws {
        let normal = try pipeline("high-bg-rising-smb")
        let inactive = try pipeline("high-bg-rising-smb", context: .inactive)
        #expect(inactive.reason == normal.reason)
        #expect(inactive.units == normal.units)
        #expect(inactive.insulinReq == normal.insulinReq)
        #expect(inactive.rate == normal.rate)
        #expect(inactive.duration == normal.duration)
        #expect(inactive.current_target == normal.current_target)
        #expect(inactive.isf == normal.isf)
    }

    @Test("35 percent overall scales basal once") func basalScaling() {
        let profile = Profile()
        #expect(context().adjustedBasal(1, profile: profile) == 0.35)
    }

    @Test("positive correction is constrained after native calculation") func positiveCorrection() {
        #expect(context().allowedCorrection(1) == 0.35)
    }

    @Test("overall and correction component compose once") func correctionComponent() {
        #expect(context(overall: 50, correction: 50).allowedCorrection(1) == 0.25)
    }

    @Test("negative correction is never weakened") func negativeCorrection() {
        #expect(context().allowedCorrection(-0.5) == -0.5)
    }

    @Test("zero correction remains zero") func zeroCorrection() {
        #expect(context().allowedCorrection(0) == 0)
    }

    @Test("predicted-low recommendation is not weakened") func predictedLow() throws {
        let normal = try pipeline("low-bg-falling")
        let exercise = try pipeline("low-bg-falling", context: context(target: 126))
        #expect(exercise.rate == normal.rate)
        #expect(exercise.duration == normal.duration)
        #expect(exercise.units == nil)
    }

    @Test("zero-temp safety remains authoritative") func zeroTemp() throws {
        let exercise = try pipeline("low-bg-falling", context: context(target: 126))
        #expect(exercise.rate == 0)
        #expect(exercise.duration == 120)
    }

    @Test("Exercise SMB off prevents an otherwise eligible SMB") func smbOff() throws {
        let result = try pipeline("high-bg-rising-smb", context: context(smb: false))
        #expect(result.units == nil)
    }

    @Test("Exercise SMB on retains native eligibility and consumes constrained correction") func smbOn() throws {
        let result = try pipeline("high-bg-rising-smb", context: context(smb: true))
        #expect(result.insulinReq == Decimal(string: "0.336"))
        #expect(result.units == 0.1)
    }

    @Test("SMB path does not apply the 35 percent factor twice") func noDoubleScaling() throws {
        let result = try pipeline("high-bg-rising-smb", context: context(smb: true))
        #expect(result.units == 0.1)
        #expect(result.insulinReq == Decimal(string: "0.336"))
    }

    @Test("100 percent sensitivity preserves adjusted ISF") func isfIdentity() {
        #expect(context(sensitivity: 100).adjustedSensitivity(50) == 50)
    }

    @Test("125 percent sensitivity multiplies adjusted ISF exactly once") func isf125() {
        #expect(context(sensitivity: 125).adjustedSensitivity(50) == 62.5)
    }

    @Test("Exercise target is direct and does not invoke Temp Target sensitivity") func exerciseTarget() throws {
        let normal = try pipeline("high-bg-rising-smb")
        let exercise = try pipeline("high-bg-rising-smb", context: context(smb: false, target: 126))
        #expect(exercise.current_target == 126)
        #expect(exercise.sensitivityRatio == normal.sensitivityRatio)
    }

    @Test("PRE to EXERCISE uses two coherent immutable snapshots") func phaseTransition() {
        let pre = context(phase: .preExercise, overall: 70, target: 120)
        let exercise = context(phase: .exercise, overall: 35, target: 140)
        #expect(pre.phase == .preExercise)
        #expect(pre.adjustedBasal(1, profile: Profile()) == 0.7)
        #expect(pre.allowedCorrection(1) == 0.7)
        #expect(pre.targetGlucose == 120)
        #expect(exercise.phase == .exercise)
        #expect(exercise.adjustedBasal(1, profile: Profile()) == 0.35)
        #expect(exercise.allowedCorrection(1) == 0.35)
        #expect(exercise.targetGlucose == 140)
    }

    @Test("native max basal remains authoritative after Exercise scaling") func maxBasal() throws {
        var profile = Profile()
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.maxBasal = 0.8
        let result = try DosingEngine.determineHighTempBasal(
            insulinRequired: context().allowedCorrection(10),
            basal: context().adjustedBasal(1, profile: profile),
            profile: profile,
            currentTemp: TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date()),
            determination: Determination(
                id: UUID(), reason: "", units: nil, insulinReq: nil, eventualBG: nil,
                sensitivityRatio: nil, rate: nil, duration: nil, iob: nil, cob: nil,
                predictions: nil, deliverAt: nil, carbsReq: nil, temp: nil, bg: nil,
                reservoir: nil, isf: nil, timestamp: nil, tdd: nil, current_target: nil,
                minDelta: nil, expectedDelta: nil, minGuardBG: nil, minPredBG: nil,
                threshold: nil, carbRatio: nil, received: nil
            )
        )
        #expect(result.rate == 0.8)
    }

    @Test("reference NORMAL versus EXERCISE determination") func referenceDetermination() throws {
        let normal = try pipeline("high-bg-rising-smb")
        let exercise = try pipeline(
            "high-bg-rising-smb",
            context: context(smb: false, sensitivity: 100, target: 126)
        )
        #expect(normal.current_target == 95)
        #expect(normal.rate == 2.8)
        #expect(normal.units == 0.4)
        #expect(exercise.current_target == 126)
        #expect(exercise.isf == normal.isf)
        #expect(exercise.units == nil)
        #expect(exercise.insulinReq == Decimal(string: "0.14"))
        #expect(exercise.rate == nil)
        #expect(exercise.reason.contains("temp 0.75 >~ req"))
        #expect(exercise.reason.contains("Exercise exercise"))
    }
}

@Suite("Exercise glucose announcement lifecycle") struct ExerciseAnnouncementLifecycleTests {
    private func state(
        phase: ExercisePhase,
        enabled: Bool = true,
        interval: Decimal = 2
    ) -> ExerciseModeState {
        .active(ExerciseModeActiveState(
            sessionID: UUID(),
            phaseID: UUID(),
            phase: phase,
            phaseStartedAt: Date(),
            scheduledExerciseAt: nil,
            postSegmentIndex: 0,
            configuration: ExercisePhaseConfiguration(
                announcementEnabled: enabled,
                announcementIntervalMinutes: interval
            )
        ))
    }

    @Test("only EXERCISE with announcements enabled creates a schedule") func exerciseOnly() {
        #expect(ExerciseAnnouncementPlan(state: state(phase: .exercise)) != nil)
        #expect(ExerciseAnnouncementPlan(state: state(phase: .preExercise)) == nil)
        #expect(ExerciseAnnouncementPlan(state: state(phase: .postExercise)) == nil)
        #expect(ExerciseAnnouncementPlan(state: .inactive) == nil)
    }

    @Test("disabled configuration remains silent") func disabled() {
        #expect(ExerciseAnnouncementPlan(state: state(phase: .exercise, enabled: false)) == nil)
    }

    @Test("configured interval is retained") func configuredInterval() throws {
        let plan = try #require(ExerciseAnnouncementPlan(state: state(phase: .exercise, interval: 3)))
        #expect(plan.interval == 180)
    }

    @Test("interval has a safe one-minute floor") func intervalFloor() throws {
        let plan = try #require(ExerciseAnnouncementPlan(state: state(phase: .exercise, interval: 0)))
        #expect(plan.interval == 60)
    }

    @Test("phase identity changes produce a new scheduler plan") func phaseSnapshotIdentity() throws {
        let first = try #require(ExerciseAnnouncementPlan(state: state(phase: .exercise)))
        let second = try #require(ExerciseAnnouncementPlan(state: state(phase: .exercise)))
        #expect(first != second)
    }
}

private struct InjectedFailure: Error {}

private struct Counts: Equatable {
    let activeSessions: Int
    let activePhases: Int
    let sessions: Int
    let phases: Int
}

private struct PhaseRow {
    let kind: String?
    let isActive: Bool
    let endDate: Date?
    let insulinPercentage: NSDecimalNumber?
}

private struct TransitionRow {
    let fromPhase: String?
    let toPhase: String?
    let committedAt: Date?
    let succeeded: Bool
}
