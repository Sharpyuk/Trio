import Combine
import CoreData
import Foundation
import LocalAuthentication
import LoopKit
import Observation
import SwiftUI
import Swinject

extension Treatments {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var unlockmanager: UnlockManager!
        @ObservationIgnored @Injected() var apsManager: APSManager!
        @ObservationIgnored @Injected() var broadcaster: Broadcaster!
        @ObservationIgnored @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        @ObservationIgnored @Injected() var settings: SettingsManager!
        @ObservationIgnored @Injected() var nsManager: NightscoutManager!
        @ObservationIgnored @Injected() var carbsStorage: CarbsStorage!
        @ObservationIgnored @Injected() var overrideStorage: OverrideStorage!
        @ObservationIgnored @Injected() var glucoseStorage: GlucoseStorage!
        @ObservationIgnored @Injected() var determinationStorage: DeterminationStorage!
        @ObservationIgnored @Injected() var bolusCalculationManager: BolusCalculationManager!
        @ObservationIgnored var onTreatmentDismiss: (@MainActor() -> Void)?

        var lowGlucose: Decimal = 70
        var highGlucose: Decimal = 180
        var glucoseColorScheme: GlucoseColorScheme = .staticColor

        var predictions: Predictions?
        var amount: Decimal = 0
        var insulinRecommended: Decimal = 0
        var insulinRequired: Decimal = 0
        var units: GlucoseUnits = .mgdL
        var threshold: Decimal = 0
        var maxBolus: Decimal = 0
        var maxExternal: Decimal { maxBolus * 3 }
        var maxIOB: Decimal = 0
        var maxCOB: Decimal = 0
        var errorString: Decimal = 0
        var evBG: Decimal = 0
        var insulin: Decimal = 0
        var isf: Decimal = 0
        var error: Bool = false
        var minGuardBG: Decimal = 0
        var minDelta: Decimal = 0
        var expectedDelta: Decimal = 0
        var minPredBG: Decimal = 0
        var lastLoopDate: Date?
        var isAwaitingDeterminationResult: Bool = false
        var carbRatio: Decimal = 0

        var addButtonPressed: Bool = false

        var target: Decimal = 0
        var cob: Int16 = 0
        var iob: Decimal = 0

        var currentBG: Decimal = 0
        var fifteenMinInsulin: Decimal = 0
        var deltaBG: Decimal = 0
        var targetDifferenceInsulin: Decimal = 0
        var targetDifference: Decimal = 0
        var wholeCob: Decimal = 0
        var wholeCobInsulin: Decimal = 0
        var iobInsulinReduction: Decimal = 0
        var wholeCalc: Decimal = 0
        var factoredInsulin: Decimal = 0
        var insulinCalculated: Decimal = 0
        var fraction: Decimal = 0
        var basal: Decimal = 0
        var isTreatmentSubmissionInProgress: Bool = false
        var shouldDismissWhenTreatmentSubmissionCompletes: Bool = false
        var fattyMeals: Bool = false
        var fattyMealFactor: Decimal = 0
        var useFattyMealCorrectionFactor: Bool = false
        var displayPresets: Bool = true
        var confirmBolus: Bool = false

        var currentBasal: Decimal = 0
        var currentCarbRatio: Decimal = 0
        var currentBGTarget: Decimal = 0
        var currentISF: Decimal = 0

        var sweetMeals: Bool = false
        var sweetMealFactor: Decimal = 0
        var useSuperBolus: Bool = false
        var superBolusInsulin: Decimal = 0

        var meal: [CarbsEntry]?
        var carbs: Decimal = 0
        var fat: Decimal = 0
        var protein: Decimal = 0
        var note: String = ""

        var date = Date()
        let defaultDate = Date()

        var carbsRequired: Decimal?
        var useFPUconversion: Bool = false
        var proteinFatMealStrategy: ProteinFatMealStrategy = .logOnly
        var proteinFatAssistDuration: Decimal = 300
        var proteinFatAssistAggressiveness: ProteinFatAssistAggressiveness = .medium
        var proteinFatAssistMildProfile: ProteinFatAssistProfileSettings = .defaults(for: .mild)
        var proteinFatAssistMediumProfile: ProteinFatAssistProfileSettings = .defaults(for: .medium)
        var proteinFatAssistStrongProfile: ProteinFatAssistProfileSettings = .defaults(for: .strong)
        var proteinFatAssistCustomProfile: ProteinFatAssistProfileSettings = .defaults(for: .custom)
        var proteinFatAssistBaseDuration: Decimal = 180
        var proteinFatAssistMinutesPer10gFat: Decimal = 30
        var proteinFatAssistMinimumDuration: Decimal = 120
        var proteinFatAssistMaximumDefaultDuration: Decimal = 480
        var proteinFatAssistDurationManuallyEdited: Bool = false
        var pendingProteinFatAssistConflict: PendingProteinFatAssistConflict?
        var dish: String = ""
        var selection: MealPresetStored?
        var summation: [String] = []
        var maxCarbs: Decimal = 0
        var maxFat: Decimal = 0
        var maxProtein: Decimal = 0

        var id_: String = ""
        var summary: String = ""

        var externalInsulin: Bool = false
        var showInfo: Bool = false
        var glucoseFromPersistence: [GlucoseStored] = []
        var determination: [OrefDetermination] = []
        var preprocessedData: [(id: UUID, forecast: Forecast, forecastValue: ForecastValue)] = []
        var predictionsForChart: Predictions?
        var simulatedDetermination: Determination?
        @MainActor var determinationObjectIDs: [NSManagedObjectID] = []

        var minForecast: [Int] = []
        var maxForecast: [Int] = []
        @MainActor var minCount: Int = 12 // count of Forecasts drawn in 5 min distances, i.e. 12 means a min of 1 hour
        var forecastDisplayType: ForecastDisplayType = .cone
        var isSmoothingEnabled: Bool = false
        var stops: [Gradient.Stop] = []

        let now = Date.now

        let viewContext = CoreDataStack.shared.persistentContainer.viewContext
        let glucoseFetchContext = CoreDataStack.shared.newTaskContext()
        let determinationFetchContext = CoreDataStack.shared.newTaskContext()
        let pumpHistoryFetchContext = CoreDataStack.shared.newTaskContext()

        var isActive: Bool = false

        var showDeterminationFailureAlert = false
        var determinationFailureMessage = ""

        // Queue for handling Core Data change notifications
        private let queue = DispatchQueue(label: "TreatmentsStateModel.queue", qos: .userInitiated)
        private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?
        private var subscriptions = Set<AnyCancellable>()

        typealias PumpEvent = PumpEventStored.EventType

        enum ProteinFatAssistConflictResolution {
            case keepCurrent
            case extendCurrent
            case replaceCurrent
        }

        struct PendingProteinFatAssistConflict {
            let currentName: String
            let proposedName: String
            let currentEnd: Date?
            let proposedEnd: Date

            var canExtend: Bool {
                guard let currentEnd else { return true }
                return proposedEnd > currentEnd
            }
        }

        var bolusProgress: Decimal?
        var isBolusInProgress: Bool { bolusProgress != nil }
        var lastPumpBolus: PumpEventStored?

        func unsubscribe() {
            subscriptions.forEach { $0.cancel() }
            subscriptions.removeAll()
        }

        override func subscribe() {
            guard isActive else {
                return
            }

            debug(.bolusState, "subscribe fired")
            coreDataPublisher =
                changedObjectsOnManagedObjectContextDidSavePublisher()
                    .receive(on: queue)
                    .share()
                    .eraseToAnyPublisher()
            registerHandlers()
            registerSubscribers()
            setupBolusStateConcurrently()
            subscribeToBolusProgress()
        }

        deinit {
            debug(.bolusState, "StateModel deinit called")
        }

        private var hasCleanedUp = false

        func cleanupTreatmentState() {
            guard !hasCleanedUp else { return }
            hasCleanedUp = true

            unsubscribe()
            lifetime = Lifetime()

            broadcaster?.unregister(DeterminationObserver.self, observer: self)
            broadcaster?.unregister(BolusFailureObserver.self, observer: self)

            debug(.bolusState, "StateModel cleanup() finished")
        }

        @MainActor func dismissTreatmentView() {
            hideModal()
            onTreatmentDismiss?()
        }

        @MainActor private func beginTreatmentSubmission() {
            addButtonPressed = true
            isTreatmentSubmissionInProgress = true
            shouldDismissWhenTreatmentSubmissionCompletes = false
        }

        @MainActor private func finishTreatmentSubmission(shouldDismiss: Bool) {
            isTreatmentSubmissionInProgress = false

            if shouldDismiss || shouldDismissWhenTreatmentSubmissionCompletes {
                shouldDismissWhenTreatmentSubmissionCompletes = false
                dismissTreatmentView()
            }
        }

        @MainActor fileprivate func dismissAfterTreatmentSubmissionIfReady() {
            if isTreatmentSubmissionInProgress {
                shouldDismissWhenTreatmentSubmissionCompletes = true
            } else {
                dismissTreatmentView()
            }
        }

        private func setupBolusStateConcurrently() {
            debug(.bolusState, "Setting up bolus state concurrently...")
            Task {
                do {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            self.setupGlucoseArray()
                        }
                        group.addTask {
                            self.setupDeterminationsAndForecasts()
                        }
                        group.addTask {
                            await self.setupSettings()
                        }
                        group.addTask {
                            self.registerObservers()
                        }
                        group.addTask {
                            self.setupLastBolus()
                        }

                        // Wait for all tasks to complete
                        try await group.waitForAll()
                    }
                } catch let error as NSError {
                    debug(.default, "Failed to setup bolus state concurrently: \(error)")
                }
            }
        }

        /// Mirrors `apsManager.bolusProgress` (a `CurrentValueSubject<Decimal?, Never>`) directly into the
        /// state model so the View can read both the progress fraction (0.0–1.0) and a derived in-progress
        /// flag. Stored in `lifetime` to match the Home module's pattern (HomeStateModel.registerObservers).
        private func subscribeToBolusProgress() {
            apsManager.bolusProgress
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.bolusProgress, on: self)
                .store(in: &lifetime)
        }

        func cancelBolus() {
            Task {
                await apsManager.cancelBolus(nil)
                try? await apsManager.determineBasalSync()
            }
        }

        // MARK: - Basal

        private enum SettingType {
            case basal
            case carbRatio
            case bgTarget
            case isf
        }

        func getAllSettingsValues() async {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self.getCurrentSettingValue(for: .basal)
                }
                group.addTask {
                    await self.getCurrentSettingValue(for: .carbRatio)
                }
                group.addTask {
                    await self.getCurrentSettingValue(for: .bgTarget)
                }
                group.addTask {
                    await self.getCurrentSettingValue(for: .isf)
                }
                group.addTask {
                    let getMaxBolus = await self.provider.getPumpSettings().maxBolus
                    await MainActor.run {
                        self.maxBolus = getMaxBolus
                    }
                }
                group.addTask {
                    let getPreferences = await self.provider.getPreferences()
                    await MainActor.run {
                        self.maxIOB = getPreferences.maxIOB
                        self.maxCOB = getPreferences.maxCOB
                    }
                }
            }
        }

        private func setupDeterminationsAndForecasts() {
            Task {
                async let getAllSettingsDefaults: () = getAllSettingsValues()
                async let setupDeterminations: () = setupDeterminationsArray()

                await getAllSettingsDefaults
                await setupDeterminations

                // Determination has updated, so we can use this to draw the initial Forecast Chart
                let forecastData = await mapForecastsForChart()
                await updateForecasts(with: forecastData)
            }
        }

        private func registerObservers() {
            broadcaster.register(DeterminationObserver.self, observer: self)
            broadcaster.register(BolusFailureObserver.self, observer: self)
        }

        @MainActor private func setupSettings() async {
            units = settingsManager.settings.units
            fraction = settings.settings.overrideFactor
            fattyMeals = settings.settings.fattyMeals
            fattyMealFactor = settings.settings.fattyMealFactor
            sweetMeals = settings.settings.sweetMeals
            sweetMealFactor = settings.settings.sweetMealFactor
            displayPresets = settings.settings.displayPresets
            confirmBolus = settings.settings.confirmBolus
            forecastDisplayType = settings.settings.forecastDisplayType
            lowGlucose = settingsManager.settings.low
            highGlucose = settingsManager.settings.high
            maxCarbs = settings.settings.maxCarbs
            maxFat = settings.settings.maxFat
            maxProtein = settings.settings.maxProtein
            useFPUconversion = settingsManager.settings.useFPUconversion
            proteinFatMealStrategy = settingsManager.settings.proteinFatMealStrategy
            proteinFatAssistDuration = settingsManager.settings.proteinFatAssistDuration
            proteinFatAssistAggressiveness = settingsManager.settings.proteinFatAssistAggressiveness
            proteinFatAssistMildProfile = settingsManager.settings.proteinFatAssistMildProfile.sanitized
            proteinFatAssistMediumProfile = settingsManager.settings.proteinFatAssistMediumProfile.sanitized
            proteinFatAssistStrongProfile = settingsManager.settings.proteinFatAssistStrongProfile.sanitized
            proteinFatAssistCustomProfile = settingsManager.settings.proteinFatAssistCustomProfile.sanitized
            proteinFatAssistBaseDuration = settingsManager.settings.proteinFatAssistBaseDuration
            proteinFatAssistMinutesPer10gFat = settingsManager.settings.proteinFatAssistMinutesPer10gFat
            proteinFatAssistMinimumDuration = settingsManager.settings.proteinFatAssistMinimumDuration
            proteinFatAssistMaximumDefaultDuration = settingsManager.settings.proteinFatAssistMaximumDefaultDuration
            updateRecommendedProteinFatAssistDuration()
            isSmoothingEnabled = settingsManager.settings.smoothGlucose
            glucoseColorScheme = settingsManager.settings.glucoseColorScheme
        }

        private func getCurrentSettingValue(for type: SettingType) async {
            let now = Date()
            let calendar = Calendar.current
            let entries: [(start: String, value: Decimal)]

            switch type {
            case .basal:
                let basalEntries = await provider.getBasalProfile()
                entries = basalEntries.map { ($0.start, $0.rate) }
            case .carbRatio:
                let carbRatios = await provider.getCarbRatios()
                entries = carbRatios.schedule.map { ($0.start, $0.ratio) }
            case .bgTarget:
                let bgTargets = await provider.getBGTargets()
                entries = bgTargets.targets.map { ($0.start, $0.low) }
            case .isf:
                let isfValues = await provider.getISFValues()
                entries = isfValues.sensitivities.map { ($0.start, $0.sensitivity) }
            }

            for (index, entry) in entries.enumerated() {
                guard let entryTime = TherapySettingsUtil.parseTime(entry.start) else {
                    debug(.default, "Invalid entry start time: \(entry.start)")
                    continue
                }

                let entryComponents = calendar.dateComponents([.hour, .minute, .second], from: entryTime)
                let entryStartTime = calendar.date(
                    bySettingHour: entryComponents.hour!,
                    minute: entryComponents.minute!,
                    second: entryComponents.second ?? 0, // Set seconds to 0 if not provided
                    of: now
                )!

                let entryEndTime: Date
                if index < entries.count - 1 {
                    if let nextEntryTime = TherapySettingsUtil.parseTime(entries[index + 1].start) {
                        let nextEntryComponents = calendar.dateComponents([.hour, .minute, .second], from: nextEntryTime)
                        entryEndTime = calendar.date(
                            bySettingHour: nextEntryComponents.hour!,
                            minute: nextEntryComponents.minute!,
                            second: nextEntryComponents.second ?? 0,
                            of: now
                        )!
                    } else {
                        entryEndTime = calendar.date(byAdding: .day, value: 1, to: entryStartTime)!
                    }
                } else {
                    entryEndTime = calendar.date(byAdding: .day, value: 1, to: entryStartTime)!
                }

                if now >= entryStartTime, now < entryEndTime {
                    await MainActor.run {
                        switch type {
                        case .basal:
                            currentBasal = entry.value
                        case .carbRatio:
                            currentCarbRatio = entry.value
                        case .bgTarget:
                            currentBGTarget = entry.value
                        case .isf:
                            currentISF = entry.value
                        }
                    }
                    return
                }
            }
        }

        // MARK: CALCULATIONS FOR THE BOLUS CALCULATOR

        /// Calculate insulin recommendation
        func calculateInsulin() async -> Decimal {
            // Safely get minPredBG on main thread
            let localMinPredBG = await MainActor.run {
                minPredBG
            }

            // Use the cob value of the simulation if we have a simulated determination
            var simulatedCOB: Int16?
            if let simulatedCobValue = simulatedDetermination?.cob {
                // Convert Decimal to Int16 and cap at maxCOB
                let cobInt16 = Int16(truncating: NSDecimalNumber(decimal: simulatedCobValue))
                let maxCobInt16 = Int16(truncating: NSDecimalNumber(decimal: maxCOB))
                simulatedCOB = min(maxCobInt16, cobInt16)
            }

            // Check if this is a backdated entry by comparing with the default date using a tolerance
            let isBackdated = abs(date.timeIntervalSince(defaultDate)) > 1.0

            let result = await bolusCalculationManager.handleBolusCalculation(
                carbs: carbs,
                useFattyMealCorrection: useFattyMealCorrectionFactor,
                useSuperBolus: useSuperBolus,
                lastLoopDate: apsManager.lastLoopDate,
                minPredBG: localMinPredBG,
                simulatedCOB: simulatedCOB,
                isBackdated: isBackdated
            )

            // Update state properties with calculation results on main thread
            await MainActor.run {
                targetDifference = result.targetDifference
                targetDifferenceInsulin = result.targetDifferenceInsulin
                wholeCob = result.wholeCob
                wholeCobInsulin = result.wholeCobInsulin
                iobInsulinReduction = result.iobInsulinReduction
                superBolusInsulin = result.superBolusInsulin
                wholeCalc = result.wholeCalc
                factoredInsulin = result.factoredInsulin
                fifteenMinInsulin = result.fifteenMinutesInsulin
            }

            return apsManager.roundBolus(amount: result.insulinCalculated)
        }

        // MARK: - Button tasks

        func invokeTreatmentsTask(proteinFatAssistResolution: ProteinFatAssistConflictResolution? = nil) {
            Task {
                debug(.bolusState, "invokeTreatmentsTask fired")
                guard await prepareProteinFatAssistSubmission(resolution: proteinFatAssistResolution) else {
                    return
                }

                await MainActor.run {
                    self.beginTreatmentSubmission()
                }
                let treatmentInput = await MainActor.run {
                    (
                        isInsulinGiven: self.amount > 0,
                        isCarbsPresent: self.carbs > 0,
                        isFatPresent: self.fat > 0,
                        isProteinPresent: self.protein > 0,
                        isExternalInsulin: self.externalInsulin
                    )
                }

                if treatmentInput.isCarbsPresent || treatmentInput.isFatPresent || treatmentInput.isProteinPresent {
                    await saveMeal(proteinFatAssistResolution: proteinFatAssistResolution)
                }

                if treatmentInput.isInsulinGiven {
                    await handleInsulin(isExternal: treatmentInput.isExternalInsulin)
                } else {
                    await MainActor.run {
                        self.finishTreatmentSubmission(shouldDismiss: true)
                    }
                    return
                }

                // If glucose data is stale end the custom loading animation by hiding the modal
                // Get date on Main thread
                let date = await MainActor.run {
                    glucoseFromPersistence.first?.date
                }

                guard glucoseStorage.isGlucoseDataFresh(date) else {
                    await MainActor.run {
                        isAwaitingDeterminationResult = false
                        showDeterminationFailureAlert = true
                        determinationFailureMessage = "Glucose data is stale"
                    }
                    return await MainActor.run {
                        self.finishTreatmentSubmission(shouldDismiss: true)
                    }
                }

                await MainActor.run {
                    self.finishTreatmentSubmission(shouldDismiss: false)
                }
            }
        }

        // MARK: - Insulin

        private func handleInsulin(isExternal: Bool) async {
            debug(.bolusState, "handleInsulin fired")

            if !isExternal {
                await addPumpInsulin()
            } else {
                await addExternalInsulin()
            }
        }

        /// Returns a user-facing localized error message for a given authentication error.
        ///
        /// This function inspects the provided `Error` to determine whether it is an `LAError`,
        /// and maps its error code to a human-readable, localized string describing the reason
        /// for the failure. If the error is not an `LAError`, a generic fallback message is returned.
        ///
        /// - Parameter error: The `Error` returned from an authentication attempt (e.g., via `LAContext.evaluatePolicy`).
        /// - Returns: A localized `String` describing the cause of the authentication failure.
        private func parseAuthenticationError(from error: Error) -> String {
            guard let laError = error as? LAError else {
                return String(
                    localized: "An unknown authentication error occurred. Please try again."
                )
            }

            switch laError.code {
            case .authenticationFailed:
                return String(
                    localized: "Authentication failed. Please try again."
                )

            case .userCancel:
                return String(
                    localized: "Authentication was canceled by you."
                )

            case .userFallback:
                return String(
                    localized: "You tapped the fallback option, but no fallback method is configured."
                )

            case .systemCancel:
                return String(
                    localized: "Authentication was canceled by the system. Try again."
                )

            case .appCancel:
                return String(
                    localized: "Authentication was canceled by the app."
                )

            case .invalidContext:
                return String(
                    localized: "Authentication context is invalid. Please try again."
                )

            case .notInteractive:
                return String(
                    localized: "Authentication UI cannot be displayed. Try restarting the app."
                )

            case .passcodeNotSet:
                return String(
                    localized: "Authentication requires a device passcode. Please set one in iOS Settings > Face ID & Passcode."
                )

            case .biometryNotAvailable:
                return String(
                    localized: "Biometric authentication is not available on this device."
                )

            case .biometryNotEnrolled:
                return String(
                    localized: "No biometric identities are enrolled. Please set up Face ID or Touch ID."
                )

            case .biometryLockout,
                 .touchIDLockout:
                return String(
                    localized: "Biometric authentication is locked due to multiple failed attempts. Please unlock your device using your passcode."
                )

            case .biometryDisconnected,
                 .biometryNotPaired:
                return String(
                    localized: "Biometric accessory is missing or not connected. Please reconnect it and try again."
                )

            default:
                return String(
                    localized: "An unknown biometric authentication error occurred. Please try again."
                )
            }
        }

        func addPumpInsulin() async {
            guard amount > 0 else {
                showModal(for: nil)
                return
            }

            let maxAmount = Double(min(amount, maxBolus))

            do {
                let authenticated = try await unlockmanager.unlock()
                if authenticated {
                    // show loading animation
                    await MainActor.run {
                        self.isAwaitingDeterminationResult = true
                    }
                    await apsManager.enactBolus(amount: maxAmount, isSMB: false, callback: nil)
                }
            } catch {
                debug(.bolusState, "Authentication error for pump bolus: \(error)")

                await MainActor.run {
                    self.isAwaitingDeterminationResult = false
                    self.showDeterminationFailureAlert = true
                    self.determinationFailureMessage = parseAuthenticationError(from: error)
                }
            }
        }

        // MARK: - EXTERNAL INSULIN

        func addExternalInsulin() async {
            guard amount > 0 else {
                showModal(for: nil)
                return
            }

            await MainActor.run {
                self.amount = min(self.amount, self.maxBolus * 3)
            }

            do {
                let authenticated = try await unlockmanager.unlock()
                if authenticated {
                    // show loading animation
                    await MainActor.run {
                        self.isAwaitingDeterminationResult = true
                    }
                    // store external dose to pump history
                    await pumpHistoryStorage.storeExternalInsulinEvent(amount: amount, timestamp: date)
                    // perform determine basal sync
                    try await apsManager.determineBasalSync()
                }
            } catch {
                debug(.bolusState, "authentication error for external insulin: \(error)")
                await MainActor.run {
                    self.isAwaitingDeterminationResult = false
                    self.showDeterminationFailureAlert = true
                    self.determinationFailureMessage = parseAuthenticationError(from: error)
                }
            }
        }

        // MARK: - Carbs

        func saveMeal(proteinFatAssistResolution: ProteinFatAssistConflictResolution? = nil) async {
            do {
                let meal = await MainActor.run {
                    self.carbs = min(self.carbs, self.maxCarbs)
                    self.fat = min(self.fat, self.maxFat)
                    self.protein = min(self.protein, self.maxProtein)
                    self.id_ = UUID().uuidString
                    let assistProfile = self.effectiveProteinFatAssistProfile.sanitized

                    return (
                        id: self.id_,
                        createdAt: self.now,
                        actualDate: self.date,
                        carbs: self.carbs,
                        fat: self.fat,
                        protein: self.protein,
                        note: self.note,
                        amount: self.amount,
                        proteinFatMealStrategy: self.proteinFatMealStrategy,
                        proteinFatAssistDuration: min(max(self.proteinFatAssistDuration, 60), 720),
                        proteinFatAssistAggressiveness: self.proteinFatAssistAggressiveness,
                        proteinFatAssistProfile: assistProfile
                    )
                }

                guard meal.carbs > 0 || meal.fat > 0 || meal.protein > 0 else { return }
                let hasProteinOrFat = meal.fat > 0 || meal.protein > 0
                let shouldCreateScheduledFPU = hasProteinOrFat && meal.proteinFatMealStrategy.isLegacyScheduledFPU
                let noteWithStrategy = note(
                    meal.note,
                    appendingProteinFatStrategy: hasProteinOrFat ? meal.proteinFatMealStrategy : nil,
                    duration: meal.proteinFatAssistDuration,
                    aggressiveness: meal.proteinFatAssistAggressiveness
                )

                await MainActor.run {
                    settingsManager.settings.proteinFatMealStrategy = meal.proteinFatMealStrategy
                    settingsManager.settings.proteinFatAssistDuration = meal.proteinFatAssistDuration
                    settingsManager.settings.proteinFatAssistAggressiveness = meal.proteinFatAssistAggressiveness
                }

                let carbsToStore = [CarbsEntry(
                    id: meal.id,
                    createdAt: meal.createdAt,
                    actualDate: meal.actualDate,
                    carbs: meal.carbs,
                    fat: meal.fat,
                    protein: meal.protein,
                    note: noteWithStrategy,
                    enteredBy: CarbsEntry.local,
                    isFPU: false,
                    fpuID: shouldCreateScheduledFPU ? UUID().uuidString : nil
                )]
                try await carbsStorage.storeCarbs(carbsToStore, areFetchedFromRemote: false)

                if hasProteinOrFat, meal.proteinFatMealStrategy == .assist {
                    try await storeProteinFatAssistOverride(
                        duration: meal.proteinFatAssistDuration,
                        aggressiveness: meal.proteinFatAssistAggressiveness,
                        profile: meal.proteinFatAssistProfile,
                        resolution: proteinFatAssistResolution
                    )
                }

                // only perform determine basal sync if the user doesn't use the pump bolus, otherwise the enact bolus func in the APSManger does a sync
                if meal.amount <= 0 {
                    await MainActor.run {
                        self.isAwaitingDeterminationResult = true
                    }
                    try await apsManager.determineBasalSync()
                }
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) Failed to save carbs: \(error)")
            }
        }

        private func note(
            _ originalNote: String,
            appendingProteinFatStrategy strategy: ProteinFatMealStrategy?,
            duration: Decimal,
            aggressiveness: ProteinFatAssistAggressiveness
        ) -> String {
            guard let strategy else { return originalNote }

            let summary: String
            switch strategy {
            case .logOnly:
                summary = String(localized: "Protein/Fat: Log only")
            case .assist:
                summary = String(
                    localized: "Protein/Fat: Assist \(Int(truncating: duration as NSNumber))m, \(aggressiveness.displayName)"
                )
            case .legacyScheduledFPU:
                summary = String(localized: "Protein/Fat: Legacy Scheduled FPU")
            }

            guard !originalNote.isEmpty else {
                return summary
            }

            return "\(originalNote) | \(summary)"
        }

        private func storeProteinFatAssistOverride(
            duration: Decimal,
            aggressiveness: ProteinFatAssistAggressiveness,
            profile: ProteinFatAssistProfileSettings,
            resolution: ProteinFatAssistConflictResolution? = nil
        ) async throws {
            await disableActiveNormalOverridesForProteinFatAssist()

            let profile = profile.sanitized
            let override = proteinFatAssistOverride(duration: duration, aggressiveness: aggressiveness, profile: profile)

            let activeAssists = await activeProteinFatAssistOverrides()
            for duplicateAssist in activeAssists.dropFirst() {
                await cancelProteinFatAssist(duplicateAssist)
            }

            if let activeAssist = activeAssists.first {
                let selectedResolution = resolution ??
                    (proteinFatAssist(activeAssist, matches: override) ? .extendCurrent : .keepCurrent)

                switch selectedResolution {
                case .keepCurrent:
                    debug(
                        .default,
                        "Protein/Fat Assist already active; logged meal only and kept current Assist \(activeAssist.name ?? "Unknown")"
                    )
                    return

                case .extendCurrent:
                    await extendProteinFatAssist(activeAssist, proposedDuration: override.duration)
                    return

                case .replaceCurrent:
                    await cancelProteinFatAssist(activeAssist)
                }
            }

            try await overrideStorage.storeOverride(override: override)
            debug(
                .default,
                "Protein/Fat Assist started: duration=\(duration)m profile=\(aggressiveness.rawValue) targetEnabled=\(profile.targetAdjustmentEnabled) target=\(override.target) isf=\(profile.isfPercent)% smb=\(override.smbMinutes)m uam=\(override.uamMinutes)m"
            )
        }

        @MainActor private func prepareProteinFatAssistSubmission(resolution: ProteinFatAssistConflictResolution?) async -> Bool {
            let input = (
                hasProteinOrFat: fat > 0 || protein > 0,
                strategy: proteinFatMealStrategy,
                duration: min(max(proteinFatAssistDuration, 60), 720),
                aggressiveness: proteinFatAssistAggressiveness,
                profile: effectiveProteinFatAssistProfile.sanitized
            )

            guard input.hasProteinOrFat, input.strategy == .assist else {
                pendingProteinFatAssistConflict = nil
                return true
            }

            guard let activeAssist = await activeProteinFatAssistOverrides().first else {
                pendingProteinFatAssistConflict = nil
                return true
            }

            let proposed = proteinFatAssistOverride(
                duration: input.duration,
                aggressiveness: input.aggressiveness,
                profile: input.profile
            )

            if proteinFatAssist(activeAssist, matches: proposed) {
                pendingProteinFatAssistConflict = nil
                return true
            }

            guard resolution == nil else {
                pendingProteinFatAssistConflict = nil
                return true
            }

            pendingProteinFatAssistConflict = PendingProteinFatAssistConflict(
                currentName: activeAssist.name ?? String(localized: "Protein/Fat Assist"),
                proposedName: proposed.name,
                currentEnd: activeAssist.activeUntilDate(),
                proposedEnd: proposed.date
                    .addingTimeInterval(TimeInterval(NSDecimalNumber(decimal: proposed.duration).doubleValue * 60))
            )
            return false
        }

        private func proteinFatAssistOverride(
            duration: Decimal,
            aggressiveness: ProteinFatAssistAggressiveness,
            profile: ProteinFatAssistProfileSettings
        ) -> Override {
            let targetBase = currentBGTarget > 0 ? currentBGTarget : 100
            let target = profile.targetAdjustmentEnabled ? max(72, min(270, targetBase - profile.targetAdjustmentMgDL)) : 0
            let defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
            let defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
            let smbMinutes = min(180, defaultSmbMinutes + profile.smbMinutesIncrease)
            let uamMinutes = min(180, defaultUamMinutes + profile.uamMinutesIncrease)
            let usesAdvancedSettings = smbMinutes != defaultSmbMinutes || uamMinutes != defaultUamMinutes

            return Override(
                name: "Protein/Fat Assist: \(aggressiveness.displayName)",
                enabled: true,
                date: Date(),
                duration: min(max(duration, 60), 720),
                indefinite: false,
                percentage: Double(truncating: profile.isfPercent as NSNumber),
                smbIsOff: false,
                isPreset: false,
                id: UUID().uuidString,
                overrideTarget: profile.targetAdjustmentEnabled,
                target: target,
                advancedSettings: usesAdvancedSettings,
                isfAndCr: false,
                isf: profile.isfPercent != 100,
                cr: false,
                smbIsScheduledOff: false,
                start: 0,
                end: 0,
                smbMinutes: smbMinutes,
                uamMinutes: uamMinutes
            )
        }

        private func proteinFatAssist(_ activeAssist: OverrideStored, matches proposed: Override) -> Bool {
            let activeTarget = activeAssist.target?.decimalValue ?? 0
            let activeSmbMinutes = activeAssist.smbMinutes?.decimalValue ?? 0
            let activeUamMinutes = activeAssist.uamMinutes?.decimalValue ?? 0

            return (activeAssist.name ?? "") == proposed.name &&
                Decimal(activeAssist.percentage) == Decimal(proposed.percentage) &&
                activeAssist.isf == proposed.isf &&
                activeAssist.advancedSettings == proposed.advancedSettings &&
                activeTarget == proposed.target &&
                activeSmbMinutes == proposed.smbMinutes &&
                activeUamMinutes == proposed.uamMinutes
        }

        @MainActor private func activeProteinFatAssistOverrides() async -> [OverrideStored] {
            do {
                let ids = try await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0)
                let activeOverrides = try ids.compactMap { id in
                    try viewContext.existingObject(with: id) as? OverrideStored
                }
                return activeOverrides.filter { $0.currentProteinFatAssist && $0.isActive() }
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Failed to fetch active Protein/Fat Assist overrides: \(error)"
                )
                return []
            }
        }

        @MainActor private func extendProteinFatAssist(_ activeAssist: OverrideStored, proposedDuration: Decimal) async {
            guard let activeStart = activeAssist.date else { return }

            let now = Date()
            let proposedEnd = now.addingTimeInterval(TimeInterval(NSDecimalNumber(decimal: proposedDuration).doubleValue * 60))
            let currentEnd = activeAssist.activeUntilDate() ?? activeStart
            guard proposedEnd > currentEnd else {
                debug(.default, "Protein/Fat Assist extension skipped because current Assist already lasts longer")
                return
            }

            activeAssist.duration = NSDecimalNumber(value: proposedEnd.timeIntervalSince(activeStart) / 60)
            activeAssist.isUploadedToNS = false

            do {
                if viewContext.hasChanges {
                    try viewContext.save()
                    Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
                }
                debug(.default, "Protein/Fat Assist extended until \(proposedEnd)")
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) Failed to extend Protein/Fat Assist: \(error)")
            }
        }

        @MainActor private func cancelProteinFatAssist(_ activeAssist: OverrideStored) async {
            do {
                let newOverrideRunStored = OverrideRunStored(context: viewContext)
                newOverrideRunStored.id = UUID(uuidString: activeAssist.id ?? "") ?? UUID()
                newOverrideRunStored.name = activeAssist.name
                newOverrideRunStored.startDate = activeAssist.date ?? .distantPast
                newOverrideRunStored.endDate = Date()
                newOverrideRunStored.target = NSDecimalNumber(
                    decimal: overrideStorage.calculateTarget(override: activeAssist)
                )
                newOverrideRunStored.override = activeAssist
                newOverrideRunStored.isUploadedToNS = false

                activeAssist.enabled = false
                activeAssist.isUploadedToNS = false

                if viewContext.hasChanges {
                    try viewContext.save()
                    Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
                }
                debug(.default, "Protein/Fat Assist replaced: cancelled \(activeAssist.name ?? "Unknown")")
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) Failed to cancel Protein/Fat Assist: \(error)")
            }
        }

        @MainActor private func disableActiveNormalOverridesForProteinFatAssist() async {
            do {
                let ids = try await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0)
                let activeOverrides = try ids.compactMap { id in
                    try viewContext.existingObject(with: id) as? OverrideStored
                }
                let normalOverrides = activeOverrides.filter { !$0.isExerciseMode && !$0.currentProteinFatAssist }
                guard !normalOverrides.isEmpty else { return }

                for overrideToCancel in normalOverrides {
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

                    overrideToCancel.enabled = false
                    debug(
                        .default,
                        "Protein/Fat Assist start disabled normal override \(overrideToCancel.name ?? "Unknown")"
                    )
                }

                if viewContext.hasChanges {
                    try viewContext.save()
                    Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
                }
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Failed to disable normal overrides before Protein/Fat Assist: \(error)"
                )
            }
        }

        var effectiveProteinFatAssistProfile: ProteinFatAssistProfileSettings {
            switch proteinFatAssistAggressiveness {
            case .mild:
                return proteinFatAssistMildProfile.sanitized
            case .medium:
                return proteinFatAssistMediumProfile.sanitized
            case .strong:
                return proteinFatAssistStrongProfile.sanitized
            case .custom:
                return proteinFatAssistCustomProfile.sanitized
            }
        }

        func updateRecommendedProteinFatAssistDuration(force: Bool = false) {
            guard force || !proteinFatAssistDurationManuallyEdited else { return }
            let recommended = proteinFatAssistRecommendedDuration(forFat: fat)
            proteinFatAssistDuration = recommended
        }

        func markProteinFatAssistDurationEdited() {
            proteinFatAssistDurationManuallyEdited = true
        }

        func resetProteinFatAssistDurationToRecommended() {
            proteinFatAssistDurationManuallyEdited = false
            updateRecommendedProteinFatAssistDuration(force: true)
        }

        private func proteinFatAssistRecommendedDuration(forFat fat: Decimal) -> Decimal {
            let rawDuration = proteinFatAssistBaseDuration + (max(0, fat) / 10 * proteinFatAssistMinutesPer10gFat)
            let minDuration = min(proteinFatAssistMinimumDuration, proteinFatAssistMaximumDefaultDuration)
            let maxDuration = max(proteinFatAssistMinimumDuration, proteinFatAssistMaximumDefaultDuration)
            return min(max(rawDuration, minDuration), maxDuration)
        }

        // MARK: - Presets

        func deletePreset() {
            if selection != nil {
                viewContext.delete(selection!)

                do {
                    guard viewContext.hasChanges else { return }
                    try viewContext.save()
                } catch {
                    print(error.localizedDescription)
                }
                carbs = 0
                fat = 0
                protein = 0
            }
            selection = nil
        }

        func removePresetFromNewMeal() {
            let a = summation.firstIndex(where: { $0 == selection?.dish! })
            if a != nil, summation[a ?? 0] != "" {
                summation.remove(at: a!)
            }
        }

        func addPresetToNewMeal() {
            if let selection = selection, let dish = selection.dish {
                summation.append(dish)
            }
        }

        func addNewPresetToWaitersNotepad(_ dish: String) {
            summation.append(dish)
        }

        func addToSummation() {
            summation.append(selection?.dish ?? "")
        }
    }
}

extension Treatments.StateModel: DeterminationObserver, BolusFailureObserver {
    func determinationDidUpdate(_: Determination) {
        guard isActive else {
            debug(.bolusState, "skipping determinationDidUpdate; view not active")
            return
        }

        DispatchQueue.main.async {
            debug(.bolusState, "determinationDidUpdate fired")
            self.isAwaitingDeterminationResult = false
            if self.addButtonPressed {
                self.dismissAfterTreatmentSubmissionIfReady()
            }
        }
    }

    func bolusDidFail() {
        DispatchQueue.main.async {
            debug(.bolusState, "bolusDidFail fired")
            self.isAwaitingDeterminationResult = false
            if self.addButtonPressed {
                self.dismissAfterTreatmentSubmissionIfReady()
            }
        }
    }
}

extension Treatments.StateModel {
    private func registerHandlers() {
        coreDataPublisher?.filteredByEntityName("OrefDetermination").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.setupDeterminationsArray()
                let forecastData = await self.mapForecastsForChart()
                await self.updateForecasts(with: forecastData)
            }
        }.store(in: &subscriptions)

        // Due to the Batch insert this only is used for observing Deletion of Glucose entries
        coreDataPublisher?.filteredByEntityName("GlucoseStored").sink { [weak self] _ in
            guard let self = self else { return }
            self.setupGlucoseArray()
        }.store(in: &subscriptions)

        // Refresh `lastPumpBolus` whenever a new pump event lands (mirrors HomeStateModel)
        coreDataPublisher?.filteredByEntityName("PumpEventStored").sink { [weak self] _ in
            self?.setupLastBolus()
        }.store(in: &subscriptions)
    }

    private func registerSubscribers() {
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.setupGlucoseArray()
            }
            .store(in: &subscriptions)
    }
}

// MARK: - Setup Glucose and Determinations

extension Treatments.StateModel {
    // Glucose
    private func setupGlucoseArray() {
        Task {
            do {
                let ids = try await self.fetchGlucose()
                let glucoseObjects: [GlucoseStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateGlucoseArray(with: glucoseObjects)
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Error setting up glucose array: \(error)"
                )
            }
        }
    }

    private func fetchGlucose() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: glucoseFetchContext,
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: false
        )

        return try await glucoseFetchContext.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateGlucoseArray(with objects: [GlucoseStored]) {
        // Store all objects for the forecast graph
        glucoseFromPersistence = objects

        // Always use the most recent reading for current glucose
        let lastGlucose = objects.first?.glucose ?? 0

        // Filter for readings less than 20 minutes old
        let twentyMinutesAgo = Date().addingTimeInterval(-20 * 60)
        let recentObjects = objects.filter {
            guard let date = $0.date else { return false }
            return date > twentyMinutesAgo
        }

        // Calculate delta using newest and oldest readings within 20-minute window
        let delta: Decimal
        if let newestInWindow = recentObjects.first?.glucose, let oldestInWindow = recentObjects.last?.glucose {
            // Newest is at index 0, oldest is at the last index
            delta = Decimal(newestInWindow) - Decimal(oldestInWindow)
        } else {
            // Not enough data points in the window
            delta = 0
        }

        currentBG = Decimal(lastGlucose)
        deltaBG = delta
    }

    // Determinations
    private func setupDeterminationsArray() async {
        do {
            let fetchedObjectIDs = try await determinationStorage.fetchLastDeterminationObjectID(
                predicate: NSPredicate.predicateFor30MinAgoForDetermination
            )

            await MainActor.run {
                determinationObjectIDs = fetchedObjectIDs
            }

            let determinationObjects: [OrefDetermination] = try await CoreDataStack.shared
                .getNSManagedObject(with: determinationObjectIDs, context: viewContext)

            updateDeterminationsArray(with: determinationObjects)
        } catch let error as CoreDataError {
            debug(.default, "Core Data error: \(error)")
        } catch {
            debug(.default, "Unexpected error: \(error)")
        }
    }

    private func mapForecastsForChart() async -> Determination? {
        do {
            let determinationObjects: [OrefDetermination] = try await CoreDataStack.shared
                .getNSManagedObject(with: determinationObjectIDs, context: determinationFetchContext)

            let determination = await determinationFetchContext.perform {
                let determinationObject = determinationObjects.first

                let forecastsSet = determinationObject?.forecasts ?? []
                let predictions = Predictions(
                    iob: forecastsSet.extractValues(for: "iob"),
                    zt: forecastsSet.extractValues(for: "zt"),
                    cob: forecastsSet.extractValues(for: "cob"),
                    uam: forecastsSet.extractValues(for: "uam")
                )

                return Determination(
                    id: UUID(),
                    reason: "",
                    units: 0,
                    insulinReq: 0,
                    sensitivityRatio: 0,
                    rate: 0,
                    duration: 0,
                    iob: 0,
                    cob: 0,
                    predictions: predictions.isEmpty ? nil : predictions,
                    carbsReq: 0,
                    temp: nil,
                    reservoir: 0,
                    insulinForManualBolus: 0,
                    manualBolusErrorString: 0,
                    carbRatio: 0,
                    received: false
                )
            }

            guard !determinationObjects.isEmpty else {
                return nil
            }

            return determination
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Error mapping forecasts for chart: \(error)"
            )
            return nil
        }
    }

    private func updateDeterminationsArray(with objects: [OrefDetermination]) {
        Task { @MainActor in
            guard let mostRecentDetermination = objects.first else { return }
            determination = objects

            // setup vars for bolus calculation
            insulinRequired = (mostRecentDetermination.insulinReq ?? 0) as Decimal
            evBG = (mostRecentDetermination.eventualBG ?? 0) as Decimal
            minPredBG = (mostRecentDetermination.minPredBGFromReason ?? 0) as Decimal
            lastLoopDate = apsManager.lastLoopDate as Date?
            insulin = (mostRecentDetermination.insulinForManualBolus ?? 0) as Decimal
            target = (mostRecentDetermination.currentTarget ?? currentBGTarget as NSDecimalNumber) as Decimal
            isf = (mostRecentDetermination.insulinSensitivity ?? currentISF as NSDecimalNumber) as Decimal
            cob = mostRecentDetermination.cob as Int16
            iob = (mostRecentDetermination.iob ?? 0) as Decimal
            basal = (mostRecentDetermination.tempBasal ?? 0) as Decimal
            carbRatio = (mostRecentDetermination.carbRatio ?? currentCarbRatio as NSDecimalNumber) as Decimal
            insulinCalculated = await calculateInsulin()
        }
    }
}

extension Treatments.StateModel {
    @MainActor func updateForecasts(with forecastData: Determination? = nil) async {
        guard isActive else {
            return
                debug(.bolusState, "updateForecasts not fired")
        }

        debug(.bolusState, "updateForecasts fired")
        if let forecastData = forecastData {
            simulatedDetermination = forecastData
            debugPrint("\(DebuggingIdentifiers.failed) minPredBG: \(minPredBG)")
        } else {
            simulatedDetermination = await Task { [self] in
                debug(.bolusState, "calling simulateDetermineBasal to get forecast data")
                return await apsManager.simulateDetermineBasal(
                    simulatedCarbsAmount: carbs,
                    simulatedBolusAmount: amount,
                    simulatedCarbsDate: date
                )
            }.value

            // Update evBG and minPredBG from simulated determination
            if let simDetermination = simulatedDetermination {
                evBG = Decimal(simDetermination.eventualBG ?? 0)
                minPredBG = simDetermination.minPredBGFromReason ?? 0
                debugPrint("\(DebuggingIdentifiers.inProgress) minPredBG: \(minPredBG)")
            }
        }

        predictionsForChart = simulatedDetermination?.predictions

        let nonEmptyArrays = [
            predictionsForChart?.iob,
            predictionsForChart?.zt,
            predictionsForChart?.cob,
            predictionsForChart?.uam
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        guard !nonEmptyArrays.isEmpty else {
            minForecast = []
            maxForecast = []
            return
        }

        minCount = max(12, nonEmptyArrays.map(\.count).min() ?? 0)
        guard minCount > 0 else { return }

        async let minForecastResult = Task {
            await (0 ..< self.minCount).map { index in
                nonEmptyArrays.compactMap { $0.indices.contains(index) ? $0[index] : nil }.min() ?? 0
            }
        }.value

        async let maxForecastResult = Task {
            await (0 ..< self.minCount).map { index in
                nonEmptyArrays.compactMap { $0.indices.contains(index) ? $0[index] : nil }.max() ?? 0
            }
        }.value

        minForecast = await minForecastResult
        maxForecast = await maxForecastResult
    }
}

private extension Set where Element == Forecast {
    func extractValues(for type: String) -> [Int]? {
        let values = first { $0.type == type }?
            .forecastValues?
            .sorted { $0.index < $1.index }
            .compactMap { Int($0.value) }
        return values?.isEmpty ?? true ? nil : values
    }
}

private extension Predictions {
    var isEmpty: Bool {
        iob == nil && zt == nil && cob == nil && uam == nil
    }
}

// MARK: - Last Pump Bolus

extension Treatments.StateModel {
    /// Mirrors `HomeStateModel.setupLastBolus` so the in-progress visualizer can show the
    /// running pump-bolus's amount as the denominator (not the user's pending entry).
    /// Filters out external boluses via `NSPredicate.lastPumpBolus`.
    func setupLastBolus() {
        Task {
            do {
                guard let id = try await fetchLastBolus() else { return }
                await updateLastBolus(with: id)
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) Error setting up last bolus: \(error)")
            }
        }
    }

    private func fetchLastBolus() async throws -> NSManagedObjectID? {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: pumpHistoryFetchContext,
            predicate: NSPredicate.lastPumpBolus,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1
        )

        return try await pumpHistoryFetchContext.perform {
            guard let fetched = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetched.map(\.objectID).first
        }
    }

    @MainActor private func updateLastBolus(with id: NSManagedObjectID) {
        do {
            lastPumpBolus = try viewContext.existingObject(with: id) as? PumpEventStored
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) updateLastBolus: \(error)")
        }
    }
}
