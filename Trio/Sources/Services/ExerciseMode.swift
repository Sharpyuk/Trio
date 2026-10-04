import CoreData
import Foundation
import Swinject

enum ExercisePhase: String, Codable, CaseIterable, Sendable {
    case preExercise
    case exercise
    case postExercise
}

enum ExerciseTransitionSource: String, Codable, Sendable {
    case app
    case scheduled
    case reconciliation
}

/// Immutable settings copied onto every persisted phase when that phase starts.
struct ExercisePhaseConfiguration: Codable, Equatable, Sendable {
    var presetID: UUID?
    var presetName: String?
    var insulinPercentage: Decimal
    var basalPercentage: Decimal
    var correctionPercentage: Decimal
    var smbEnabled: Bool
    var sensitivityPercentage: Decimal
    var targetGlucose: Decimal
    /// Used by PRE for display/planning and by POST as the segment duration. EXERCISE ignores it.
    var durationMinutes: Decimal?
    var announcementEnabled: Bool
    var announcementIntervalMinutes: Decimal

    init(
        presetID: UUID? = nil,
        presetName: String? = nil,
        insulinPercentage: Decimal = 100,
        basalPercentage: Decimal = 100,
        correctionPercentage: Decimal = 100,
        smbEnabled: Bool = true,
        sensitivityPercentage: Decimal = 100,
        targetGlucose: Decimal = 100,
        durationMinutes: Decimal? = nil,
        announcementEnabled: Bool = false,
        announcementIntervalMinutes: Decimal = 2
    ) {
        self.presetID = presetID
        self.presetName = presetName
        self.insulinPercentage = insulinPercentage
        self.basalPercentage = basalPercentage
        self.correctionPercentage = correctionPercentage
        self.smbEnabled = smbEnabled
        self.sensitivityPercentage = sensitivityPercentage
        self.targetGlucose = targetGlucose
        self.durationMinutes = durationMinutes
        self.announcementEnabled = announcementEnabled
        self.announcementIntervalMinutes = announcementIntervalMinutes
    }
}

struct ExerciseModeActiveState: Equatable, Sendable {
    let sessionID: UUID
    let phaseID: UUID
    let phase: ExercisePhase
    let phaseStartedAt: Date
    let scheduledExerciseAt: Date?
    let postSegmentIndex: Int
    let configuration: ExercisePhaseConfiguration
}

enum ExerciseModeState: Equatable, Sendable {
    case inactive
    case active(ExerciseModeActiveState)

    var phase: ExercisePhase? {
        guard case let .active(state) = self else { return nil }
        return state.phase
    }
}

/// Immutable Exercise inputs captured once at the start of a dosing determination.
/// Percentages are unit factors (`0.35`, not `35`). SMB will consume the already-adjusted
/// positive correction requirement, so there is no second SMB multiplier to double-scale it.
struct ExerciseDosingContext: Equatable, Sendable {
    let sessionID: UUID?
    let phaseID: UUID?
    let phase: ExercisePhase?
    let configuration: ExercisePhaseConfiguration?

    static let inactive = ExerciseDosingContext(
        sessionID: nil,
        phaseID: nil,
        phase: nil,
        configuration: nil
    )

    init(state: ExerciseModeState) {
        switch state {
        case .inactive:
            self = .inactive
        case let .active(active):
            sessionID = active.sessionID
            phaseID = active.phaseID
            phase = active.phase
            configuration = active.configuration
        }
    }

    init(
        sessionID: UUID? = nil,
        phaseID: UUID? = nil,
        phase: ExercisePhase?,
        configuration: ExercisePhaseConfiguration?
    ) {
        self.sessionID = sessionID
        self.phaseID = phaseID
        self.phase = phase
        self.configuration = configuration
    }

    var overallInsulinFactor: Decimal { (configuration?.insulinPercentage ?? 100) / 100 }
    var basalFactor: Decimal { (configuration?.basalPercentage ?? 100) / 100 }
    var positiveCorrectionFactor: Decimal { (configuration?.correctionPercentage ?? 100) / 100 }
    var smbEnabled: Bool { configuration?.smbEnabled ?? true }
    var sensitivityFactor: Decimal { (configuration?.sensitivityPercentage ?? 100) / 100 }
    var targetGlucose: Decimal? { configuration?.targetGlucose }
    var effectiveBasalFactor: Decimal { overallInsulinFactor * basalFactor }
    var effectivePositiveCorrectionFactor: Decimal { overallInsulinFactor * positiveCorrectionFactor }

    var isActive: Bool { phase != nil && configuration != nil }

    func adjustedBasal(_ normalBasal: Decimal, profile: Profile) -> Decimal {
        guard isActive else { return normalBasal }
        return TempBasalFunctions.roundBasal(profile: profile, basalRate: normalBasal * effectiveBasalFactor)
    }

    func adjustedSensitivity(_ normalSensitivity: Decimal) -> Decimal {
        guard isActive else { return normalSensitivity }
        return normalSensitivity * sensitivityFactor
    }

    func allowedCorrection(_ rawInsulinRequired: Decimal) -> Decimal {
        guard isActive, rawInsulinRequired > 0 else { return rawInsulinRequired }
        return rawInsulinRequired * effectivePositiveCorrectionFactor
    }
}

/// Structured before/after values from the single native dosing calculation.
/// This is diagnostic only; it never participates in a dosing decision.
struct ExerciseDosingTrace: CustomStringConvertible {
    let context: ExerciseDosingContext
    let normalTarget: Decimal
    let effectiveTarget: Decimal
    let normalAdjustedSensitivity: Decimal
    let effectiveSensitivity: Decimal
    let normalBasal: Decimal
    let effectiveBasal: Decimal
    let rawInsulinRequired: Decimal
    let allowedCorrection: Decimal
    let iob: Decimal
    let cob: Decimal
    let minForecastGlucose: Decimal
    let eventualGlucose: Decimal

    var description: String {
        "active=true session=\(context.sessionID?.uuidString ?? "nil") phaseID=\(context.phaseID?.uuidString ?? "nil") " +
            "phase=\(context.phase?.rawValue ?? "inactive") overall=\(context.overallInsulinFactor) " +
            "basalComponent=\(context.basalFactor) effectiveBasalFactor=\(context.effectiveBasalFactor) " +
            "correctionComponent=\(context.positiveCorrectionFactor) effectiveCorrectionFactor=\(context.effectivePositiveCorrectionFactor) " +
            "smbAllowed=\(context.smbEnabled) sensitivityFactor=\(context.sensitivityFactor) " +
            "target=\(normalTarget)->\(effectiveTarget) isf=\(normalAdjustedSensitivity)->\(effectiveSensitivity) " +
            "basal=\(normalBasal)->\(effectiveBasal) insulinReq=\(rawInsulinRequired)->\(allowedCorrection) " +
            "iob=\(iob) cob=\(cob) minPred=\(minForecastGlucose) eventual=\(eventualGlucose)"
    }

    var reasonFragment: String {
        "; Exercise \(context.phase?.rawValue ?? "active") basal \(normalBasal)->\(effectiveBasal), " +
            "target \(normalTarget)->\(effectiveTarget), ISF \(normalAdjustedSensitivity)->\(effectiveSensitivity), " +
            "insulinReq \(rawInsulinRequired)->\(allowedCorrection), SMB \(context.smbEnabled ? "permitted" : "off"). "
    }
}

enum ExerciseModeError: LocalizedError, Equatable {
    case invalidTransition(from: ExercisePhase?, to: ExercisePhase?)
    case missingExerciseConfiguration
    case invalidPostConfiguration(index: Int)
    case inconsistentStore(String)
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidTransition(from, to):
            return "Exercise Mode cannot transition from \(from?.rawValue ?? "inactive") to \(to?.rawValue ?? "inactive")."
        case .missingExerciseConfiguration:
            return "No Exercise configuration is available for the transition."
        case let .invalidPostConfiguration(index):
            return "Post-exercise segment \(index + 1) must have a duration greater than zero."
        case let .inconsistentStore(message):
            return "Exercise Mode data is inconsistent: \(message)"
        case .persistenceFailed:
            return "Exercise Mode could not save the transition."
        }
    }
}

protocol ExerciseStorage {
    func currentState() async throws -> ExerciseModeState
    func sessions() async throws -> [NSManagedObjectID]
    func phases(sessionID: UUID) async throws -> [NSManagedObjectID]
    func transitions(sessionID: UUID?) async throws -> [NSManagedObjectID]
}

final class BaseExerciseStorage: ExerciseStorage {
    private let makeContext: () -> NSManagedObjectContext

    init(contextProvider: (() -> NSManagedObjectContext)? = nil) {
        makeContext = contextProvider ?? { CoreDataStack.shared.newTaskContext() }
    }

    func currentState() async throws -> ExerciseModeState {
        let context = makeContext()
        context.name = "exerciseCurrentState"
        return try await context.perform { try ExercisePersistence.currentState(in: context) }
    }

    func sessions() async throws -> [NSManagedObjectID] {
        let context = makeContext()
        context.name = "exerciseSessions"
        return try await context.perform {
            let request: NSFetchRequest<ExerciseSessionStored> = ExerciseSessionStored.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            return try context.fetch(request).map(\.objectID)
        }
    }

    func phases(sessionID: UUID) async throws -> [NSManagedObjectID] {
        let context = makeContext()
        context.name = "exercisePhases"
        return try await context.perform {
            let request: NSFetchRequest<ExercisePhaseStored> = ExercisePhaseStored.fetchRequest()
            request.predicate = NSPredicate(format: "session.id == %@", sessionID as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: true)]
            return try context.fetch(request).map(\.objectID)
        }
    }

    func transitions(sessionID: UUID?) async throws -> [NSManagedObjectID] {
        let context = makeContext()
        context.name = "exerciseTransitions"
        return try await context.perform {
            let request: NSFetchRequest<ExerciseTransitionStored> = ExerciseTransitionStored.fetchRequest()
            if let sessionID {
                request.predicate = NSPredicate(format: "session.id == %@", sessionID as CVarArg)
            }
            request.sortDescriptors = [NSSortDescriptor(key: "requestedAt", ascending: true)]
            return try context.fetch(request).map(\.objectID)
        }
    }
}

protocol ExerciseModeManager: AnyObject {
    func currentState() async throws -> ExerciseModeState
    @discardableResult func startPreExercise(
        configuration: ExercisePhaseConfiguration,
        exerciseConfiguration: ExercisePhaseConfiguration,
        scheduledExerciseAt: Date,
        source: ExerciseTransitionSource,
        at date: Date
    ) async throws -> ExerciseModeState
    @discardableResult func cancelPreExercise(
        source: ExerciseTransitionSource,
        at date: Date
    ) async throws -> ExerciseModeState
    @discardableResult func startExercise(
        configuration: ExercisePhaseConfiguration?,
        source: ExerciseTransitionSource,
        at date: Date
    ) async throws -> ExerciseModeState
    @discardableResult func stopExercise(
        postConfigurations: [ExercisePhaseConfiguration],
        source: ExerciseTransitionSource,
        at date: Date
    ) async throws -> ExerciseModeState
    @discardableResult func endPostExercise(
        source: ExerciseTransitionSource,
        at date: Date
    ) async throws -> ExerciseModeState
    /// Applies due PRE→EXERCISE and POST segment/expiry transitions. A failed automatic
    /// transition is rolled back, leaving the previous phase active.
    @discardableResult func reconcile(at date: Date) async throws -> ExerciseModeState
}

extension ExerciseModeManager {
    func startPreExercise(
        configuration: ExercisePhaseConfiguration,
        exerciseConfiguration: ExercisePhaseConfiguration,
        scheduledExerciseAt: Date,
        source: ExerciseTransitionSource = .app
    ) async throws -> ExerciseModeState {
        try await startPreExercise(
            configuration: configuration,
            exerciseConfiguration: exerciseConfiguration,
            scheduledExerciseAt: scheduledExerciseAt,
            source: source,
            at: Date()
        )
    }

    func startExercise(
        configuration: ExercisePhaseConfiguration? = nil,
        source: ExerciseTransitionSource = .app
    ) async throws -> ExerciseModeState {
        try await startExercise(configuration: configuration, source: source, at: Date())
    }

    func cancelPreExercise(source: ExerciseTransitionSource = .app) async throws -> ExerciseModeState {
        try await cancelPreExercise(source: source, at: Date())
    }

    func stopExercise(
        postConfigurations: [ExercisePhaseConfiguration] = [],
        source: ExerciseTransitionSource = .app
    ) async throws -> ExerciseModeState {
        try await stopExercise(postConfigurations: postConfigurations, source: source, at: Date())
    }

    func endPostExercise(source: ExerciseTransitionSource = .app) async throws -> ExerciseModeState {
        try await endPostExercise(source: source, at: Date())
    }
}

/// The sole writer for operational Exercise Mode state.
final class BaseExerciseModeManager: ExerciseModeManager, @unchecked Sendable {
    enum Mutation: Equatable, Sendable {
        case inactiveToPre
        case inactiveToExercise
        case preToExercise
        case preToInactive
        case exerciseToPost
        case exerciseToInactive
        case postToPost
        case postToInactive
    }

    private let makeContext: @Sendable() -> NSManagedObjectContext
    private let beforeSave: @Sendable(Mutation) throws -> Void
    private let serializer = ExerciseMutationSerializer()

    init(
        contextProvider: (@Sendable() -> NSManagedObjectContext)? = nil,
        beforeSave: @escaping @Sendable(Mutation) throws -> Void = { _ in }
    ) {
        makeContext = contextProvider ?? { CoreDataStack.shared.newTaskContext() }
        self.beforeSave = beforeSave
    }

    func currentState() async throws -> ExerciseModeState {
        let context = makeContext()
        context.name = "exerciseManagerCurrentState"
        return try await context.perform { try ExercisePersistence.currentState(in: context) }
    }

    func startPreExercise(
        configuration: ExercisePhaseConfiguration,
        exerciseConfiguration: ExercisePhaseConfiguration,
        scheduledExerciseAt: Date,
        source: ExerciseTransitionSource,
        at date: Date
    ) async throws -> ExerciseModeState {
        try await serializer.run {
            try await self.mutate(
                expected: nil,
                destination: .preExercise,
                mutation: .inactiveToPre,
                source: source,
                date: date
            ) { context, _, _ in
                let session = ExerciseSessionStored(context: context)
                session.id = UUID()
                session.setValue(configuration.presetID, forKey: "presetID")
                session.setValue(configuration.presetName, forKey: "presetName")
                session.createdAt = date
                session.scheduledExerciseAt = scheduledExerciseAt
                session.status = ExercisePersistence.activeStatus
                session.plannedExerciseConfiguration = try ExercisePersistence.encode(exerciseConfiguration)
                let phase = ExercisePersistence.makePhase(
                    .preExercise,
                    configuration: configuration,
                    session: session,
                    startDate: date,
                    segmentIndex: 0,
                    in: context
                )
                return (session, phase)
            }
        }
    }

    func startExercise(
        configuration: ExercisePhaseConfiguration?,
        source: ExerciseTransitionSource,
        at date: Date
    ) async throws -> ExerciseModeState {
        try await serializer.run {
            let initial = try await self.currentState()
            switch initial.phase {
            case nil:
                guard let configuration else {
                    return try await self.reject(
                        from: nil,
                        to: .exercise,
                        source: source,
                        at: date,
                        error: .missingExerciseConfiguration
                    )
                }
                return try await self.mutate(
                    expected: nil,
                    destination: .exercise,
                    mutation: .inactiveToExercise,
                    source: source,
                    date: date
                ) { context, _, _ in
                    let session = ExerciseSessionStored(context: context)
                    session.id = UUID()
                    session.setValue(configuration.presetID, forKey: "presetID")
                    session.setValue(configuration.presetName, forKey: "presetName")
                    session.createdAt = date
                    session.exerciseStartDate = date
                    session.status = ExercisePersistence.activeStatus
                    let phase = ExercisePersistence.makePhase(
                        .exercise,
                        configuration: configuration,
                        session: session,
                        startDate: date,
                        segmentIndex: 0,
                        in: context
                    )
                    return (session, phase)
                }
            case .preExercise:
                return try await self.transitionPreToExercise(configuration: configuration, source: source, at: date)
            default:
                return try await self.reject(
                    from: initial.phase,
                    to: .exercise,
                    source: source,
                    at: date,
                    error: .invalidTransition(from: initial.phase, to: .exercise)
                )
            }
        }
    }

    func cancelPreExercise(
        source: ExerciseTransitionSource,
        at date: Date
    ) async throws -> ExerciseModeState {
        try await serializer.run {
            let state = try await self.currentState()
            guard state.phase == .preExercise else {
                return try await self.reject(
                    from: state.phase,
                    to: nil,
                    source: source,
                    at: date,
                    error: .invalidTransition(from: state.phase, to: nil)
                )
            }
            return try await self.finishActiveSession(
                expected: .preExercise,
                mutation: .preToInactive,
                source: source,
                at: date
            )
        }
    }

    func stopExercise(
        postConfigurations: [ExercisePhaseConfiguration],
        source: ExerciseTransitionSource,
        at date: Date
    ) async throws -> ExerciseModeState {
        try await serializer.run {
            let state = try await self.currentState()
            guard state.phase == .exercise else {
                return try await self.reject(
                    from: state.phase,
                    to: postConfigurations.isEmpty ? nil : .postExercise,
                    source: source,
                    at: date,
                    error: .invalidTransition(from: state.phase, to: postConfigurations.isEmpty ? nil : .postExercise)
                )
            }
            for (index, configuration) in postConfigurations.enumerated() {
                guard let duration = configuration.durationMinutes, duration > 0 else {
                    return try await self.reject(
                        from: .exercise,
                        to: .postExercise,
                        source: source,
                        at: date,
                        error: .invalidPostConfiguration(index: index)
                    )
                }
            }

            if postConfigurations.isEmpty {
                return try await self.finishActiveSession(
                    expected: .exercise,
                    mutation: .exerciseToInactive,
                    source: source,
                    at: date
                )
            }

            return try await self.mutate(
                expected: .exercise,
                destination: .postExercise,
                mutation: .exerciseToPost,
                source: source,
                date: date
            ) { context, session, oldPhase in
                guard let session, let oldPhase else {
                    throw ExerciseModeError.inconsistentStore("missing active exercise")
                }
                oldPhase.isActive = false
                oldPhase.endDate = date
                session.exerciseEndDate = date
                session.postPlan = try ExercisePersistence.encode(Array(postConfigurations.dropFirst()))
                let phase = ExercisePersistence.makePhase(
                    .postExercise,
                    configuration: postConfigurations[0],
                    session: session,
                    startDate: date,
                    segmentIndex: 0,
                    in: context
                )
                return (session, phase)
            }
        }
    }

    func endPostExercise(
        source: ExerciseTransitionSource,
        at date: Date
    ) async throws -> ExerciseModeState {
        try await serializer.run {
            let state = try await self.currentState()
            guard state.phase == .postExercise else {
                return try await self.reject(
                    from: state.phase,
                    to: nil,
                    source: source,
                    at: date,
                    error: .invalidTransition(from: state.phase, to: nil)
                )
            }
            return try await self.finishActiveSession(
                expected: .postExercise,
                mutation: .postToInactive,
                source: source,
                at: date
            )
        }
    }

    func reconcile(at date: Date) async throws -> ExerciseModeState {
        try await serializer.run {
            let state = try await self.currentState()
            switch state {
            case .inactive:
                return .inactive
            case let .active(active) where active.phase == .preExercise:
                guard let scheduled = active.scheduledExerciseAt, date >= scheduled else { return state }
                return try await self.transitionPreToExercise(configuration: nil, source: .scheduled, at: date)
            case let .active(active) where active.phase == .exercise:
                return state
            case let .active(active):
                return try await self.reconcilePost(active: active, at: date)
            }
        }
    }

    private func transitionPreToExercise(
        configuration: ExercisePhaseConfiguration?,
        source: ExerciseTransitionSource,
        at date: Date
    ) async throws -> ExerciseModeState {
        try await mutate(
            expected: .preExercise,
            destination: .exercise,
            mutation: .preToExercise,
            source: source,
            date: date
        ) { context, session, oldPhase in
            guard let session, let oldPhase else {
                throw ExerciseModeError.inconsistentStore("missing active pre-exercise phase")
            }
            let selected = try configuration ?? ExercisePersistence.decode(
                ExercisePhaseConfiguration.self,
                from: session.plannedExerciseConfiguration
            )
            oldPhase.isActive = false
            oldPhase.endDate = date
            session.exerciseStartDate = date
            let phase = ExercisePersistence.makePhase(
                .exercise,
                configuration: selected,
                session: session,
                startDate: date,
                segmentIndex: 0,
                in: context
            )
            return (session, phase)
        }
    }

    private func reconcilePost(active: ExerciseModeActiveState, at date: Date) async throws -> ExerciseModeState {
        guard let duration = active.configuration.durationMinutes, duration > 0 else {
            return try await reject(
                from: .postExercise,
                to: nil,
                source: .reconciliation,
                at: date,
                error: .invalidPostConfiguration(index: active.postSegmentIndex)
            )
        }
        let expiry = active.phaseStartedAt.addingTimeInterval(NSDecimalNumber(decimal: duration).doubleValue * 60)
        guard date >= expiry else { return .active(active) }

        let context = makeContext()
        context.name = "reconcilePost"
        do {
            let state = try await context.perform { () throws -> ExerciseModeState in
                let (session, oldPhase) = try ExercisePersistence.activeRows(in: context)
                guard let session, let oldPhase,
                      ExercisePersistence.phase(of: oldPhase) == .postExercise
                else { throw ExerciseModeError.invalidTransition(from: nil, to: nil) }

                var boundary = expiry
                var phase = oldPhase
                var pending = try ExercisePersistence.decode(
                    [ExercisePhaseConfiguration].self,
                    from: session.postPlan,
                    default: []
                )
                var segmentIndex = Int(phase.segmentIndex)

                while true {
                    phase.isActive = false
                    phase.endDate = boundary
                    if pending.isEmpty {
                        session.status = ExercisePersistence.completedStatus
                        session.completedAt = boundary
                        ExercisePersistence.recordTransition(
                            from: .postExercise,
                            to: nil,
                            source: .reconciliation,
                            requestedAt: date,
                            committedAt: boundary,
                            succeeded: true,
                            error: nil,
                            session: session,
                            in: context
                        )
                        try self.beforeSave(.postToInactive)
                        try context.save()
                        return .inactive
                    }

                    let next = pending.removeFirst()
                    segmentIndex += 1
                    ExercisePersistence.recordTransition(
                        from: .postExercise,
                        to: .postExercise,
                        source: .reconciliation,
                        requestedAt: date,
                        committedAt: boundary,
                        succeeded: true,
                        error: nil,
                        session: session,
                        in: context
                    )
                    phase = ExercisePersistence.makePhase(
                        .postExercise,
                        configuration: next,
                        session: session,
                        startDate: boundary,
                        segmentIndex: segmentIndex,
                        in: context
                    )
                    session.postPlan = try ExercisePersistence.encode(pending)
                    try self.beforeSave(.postToPost)

                    guard let nextDuration = next.durationMinutes, nextDuration > 0 else {
                        throw ExerciseModeError.invalidPostConfiguration(index: segmentIndex)
                    }
                    let nextBoundary = boundary.addingTimeInterval(NSDecimalNumber(decimal: nextDuration).doubleValue * 60)
                    if date < nextBoundary {
                        try context.save()
                        return try ExercisePersistence.snapshot(session: session, phase: phase)
                    }
                    boundary = nextBoundary
                }
            }
            return state
        } catch {
            await logFailure(from: .postExercise, to: nil, source: .reconciliation, at: date, error: error)
            throw normalized(error)
        }
    }

    private func finishActiveSession(
        expected: ExercisePhase,
        mutation: Mutation,
        source: ExerciseTransitionSource,
        at date: Date
    ) async throws -> ExerciseModeState {
        try await mutate(
            expected: expected,
            destination: nil,
            mutation: mutation,
            source: source,
            date: date
        ) { _, session, phase in
            guard let session, let phase else {
                throw ExerciseModeError.inconsistentStore("missing active phase")
            }
            phase.isActive = false
            phase.endDate = date
            if expected == .exercise { session.exerciseEndDate = date }
            session.status = ExercisePersistence.completedStatus
            session.completedAt = date
            session.postPlan = nil
            return (session, nil)
        }
    }

    private typealias MutationBody = (
        NSManagedObjectContext,
        ExerciseSessionStored?,
        ExercisePhaseStored?
    ) throws -> (ExerciseSessionStored, ExercisePhaseStored?)

    private func mutate(
        expected: ExercisePhase?,
        destination: ExercisePhase?,
        mutation: Mutation,
        source: ExerciseTransitionSource,
        date: Date,
        body: @escaping MutationBody
    ) async throws -> ExerciseModeState {
        let context = makeContext()
        context.name = "exerciseTransition.\(mutation)"
        do {
            return try await context.perform {
                let (activeSession, activePhase) = try ExercisePersistence.activeRows(in: context)
                let actual = activePhase.flatMap(ExercisePersistence.phase)
                guard actual == expected else {
                    throw ExerciseModeError.invalidTransition(from: actual, to: destination)
                }
                let (session, newPhase) = try body(context, activeSession, activePhase)
                ExercisePersistence.recordTransition(
                    from: expected,
                    to: destination,
                    source: source,
                    requestedAt: date,
                    committedAt: date,
                    succeeded: true,
                    error: nil,
                    session: session,
                    in: context
                )
                try self.beforeSave(mutation)
                try context.save()
                guard let newPhase else { return .inactive }
                return try ExercisePersistence.snapshot(session: session, phase: newPhase)
            }
        } catch {
            context.rollback()
            await logFailure(from: expected, to: destination, source: source, at: date, error: error)
            throw normalized(error)
        }
    }

    private func reject(
        from: ExercisePhase?,
        to: ExercisePhase?,
        source: ExerciseTransitionSource,
        at date: Date,
        error: ExerciseModeError
    ) async throws -> ExerciseModeState {
        await logFailure(from: from, to: to, source: source, at: date, error: error)
        throw error
    }

    private func logFailure(
        from: ExercisePhase?,
        to: ExercisePhase?,
        source: ExerciseTransitionSource,
        at date: Date,
        error: Error
    ) async {
        let context = makeContext()
        context.name = "exerciseTransitionFailure"
        await context.perform {
            let activeSession = try? ExercisePersistence.activeRows(in: context).session
            ExercisePersistence.recordTransition(
                from: from,
                to: to,
                source: source,
                requestedAt: date,
                committedAt: nil,
                succeeded: false,
                error: String(describing: error),
                session: activeSession,
                in: context
            )
            do { try context.save() } catch {
                debug(.service, "Failed to persist Exercise Mode transition failure: \(error)")
            }
        }
    }

    private func normalized(_ error: Error) -> ExerciseModeError {
        if let exerciseError = error as? ExerciseModeError { return exerciseError }
        return .persistenceFailed(String(describing: error))
    }
}

private actor ExerciseMutationSerializer {
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ operation: @escaping @Sendable() async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> {
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}

private enum ExercisePersistence {
    static let activeStatus = "active"
    static let completedStatus = "completed"

    static func currentState(in context: NSManagedObjectContext) throws -> ExerciseModeState {
        let (session, phase) = try activeRows(in: context)
        guard let session, let phase else { return .inactive }
        return try snapshot(session: session, phase: phase)
    }

    static func activeRows(
        in context: NSManagedObjectContext
    ) throws -> (session: ExerciseSessionStored?, phase: ExercisePhaseStored?) {
        let sessionRequest: NSFetchRequest<ExerciseSessionStored> = ExerciseSessionStored.fetchRequest()
        sessionRequest.predicate = NSPredicate(format: "status == %@", activeStatus)
        sessionRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let sessions = try context.fetch(sessionRequest)
        guard sessions.count <= 1 else {
            throw ExerciseModeError.inconsistentStore("more than one active session")
        }
        guard let session = sessions.first else { return (nil, nil) }

        let phaseRequest: NSFetchRequest<ExercisePhaseStored> = ExercisePhaseStored.fetchRequest()
        phaseRequest.predicate = NSPredicate(format: "session == %@ AND isActive == YES", session)
        phaseRequest.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        let phases = try context.fetch(phaseRequest)
        guard phases.count == 1, let phase = phases.first else {
            throw ExerciseModeError.inconsistentStore("active session must have exactly one active phase")
        }
        return (session, phase)
    }

    static func makePhase(
        _ kind: ExercisePhase,
        configuration: ExercisePhaseConfiguration,
        session: ExerciseSessionStored,
        startDate: Date,
        segmentIndex: Int,
        in context: NSManagedObjectContext
    ) -> ExercisePhaseStored {
        let phase = ExercisePhaseStored(context: context)
        phase.id = UUID()
        phase.kind = kind.rawValue
        phase.startDate = startDate
        phase.isActive = true
        phase.segmentIndex = Int16(segmentIndex)
        phase.insulinPercentage = configuration.insulinPercentage as NSDecimalNumber
        phase.basalPercentage = configuration.basalPercentage as NSDecimalNumber
        phase.correctionPercentage = configuration.correctionPercentage as NSDecimalNumber
        phase.smbEnabled = configuration.smbEnabled
        phase.sensitivityPercentage = configuration.sensitivityPercentage as NSDecimalNumber
        phase.targetGlucose = configuration.targetGlucose as NSDecimalNumber
        phase.durationMinutes = configuration.durationMinutes.map(NSDecimalNumber.init(decimal:))
        phase.announcementEnabled = configuration.announcementEnabled
        phase.announcementIntervalMinutes = configuration.announcementIntervalMinutes as NSDecimalNumber
        phase.configurationSnapshot = try? encode(configuration)
        phase.session = session
        return phase
    }

    static func recordTransition(
        from: ExercisePhase?,
        to: ExercisePhase?,
        source: ExerciseTransitionSource,
        requestedAt: Date,
        committedAt: Date?,
        succeeded: Bool,
        error: String?,
        session: ExerciseSessionStored?,
        in context: NSManagedObjectContext
    ) {
        let transition = ExerciseTransitionStored(context: context)
        transition.id = UUID()
        transition.fromPhase = from?.rawValue ?? "inactive"
        transition.toPhase = to?.rawValue ?? "inactive"
        transition.source = source.rawValue
        transition.requestedAt = requestedAt
        transition.committedAt = committedAt
        transition.succeeded = succeeded
        transition.errorMessage = error
        transition.session = session
    }

    static func phase(of stored: ExercisePhaseStored) -> ExercisePhase? {
        stored.kind.flatMap(ExercisePhase.init(rawValue:))
    }

    static func snapshot(
        session: ExerciseSessionStored,
        phase: ExercisePhaseStored
    ) throws -> ExerciseModeState {
        guard let sessionID = session.id,
              let phaseID = phase.id,
              let phaseKind = self.phase(of: phase),
              let startDate = phase.startDate
        else { throw ExerciseModeError.inconsistentStore("active records contain missing required values") }

        let configuration: ExercisePhaseConfiguration
        if let data = phase.configurationSnapshot {
            configuration = try decode(ExercisePhaseConfiguration.self, from: data)
        } else {
            configuration = ExercisePhaseConfiguration(
                insulinPercentage: phase.insulinPercentage?.decimalValue ?? 100,
                basalPercentage: phase.basalPercentage?.decimalValue ?? 100,
                correctionPercentage: phase.correctionPercentage?.decimalValue ?? 100,
                smbEnabled: phase.smbEnabled,
                sensitivityPercentage: phase.sensitivityPercentage?.decimalValue ?? 100,
                targetGlucose: phase.targetGlucose?.decimalValue ?? 100,
                durationMinutes: phase.durationMinutes?.decimalValue,
                announcementEnabled: phase.announcementEnabled,
                announcementIntervalMinutes: phase.announcementIntervalMinutes?.decimalValue ?? 2
            )
        }
        return .active(ExerciseModeActiveState(
            sessionID: sessionID,
            phaseID: phaseID,
            phase: phaseKind,
            phaseStartedAt: startDate,
            scheduledExerciseAt: session.scheduledExerciseAt,
            postSegmentIndex: Int(phase.segmentIndex),
            configuration: configuration
        ))
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) throws -> T {
        guard let data else { throw ExerciseModeError.missingExerciseConfiguration }
        return try JSONDecoder().decode(type, from: data)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?, default value: T) throws -> T {
        guard let data else { return value }
        return try JSONDecoder().decode(type, from: data)
    }
}
