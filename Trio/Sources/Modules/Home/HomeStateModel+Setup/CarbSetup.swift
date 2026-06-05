import CoreData
import Foundation

extension Home.StateModel {
    func setupCarbsArray() {
        Task {
            do {
                let ids = try await self.fetchCarbs()
                let carbObjects: [CarbEntryStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateCarbsArray(with: carbObjects)
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Error fetching carb objects: \(error) in \(#file):\(#line)")
            }
        }
    }

    private func fetchCarbs() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: carbsFetchContext,
            predicate: NSPredicate.carbsForChart,
            key: "date",
            ascending: false,
            batchSize: 5
        )

        return try await carbsFetchContext.perform {
            guard let fetchedResults = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateCarbsArray(with objects: [CarbEntryStored]) {
        carbsFromPersistence = objects
    }

    func setupFPUsArray() {
        Task {
            do {
                let ids = try await self.fetchFPUs()
                let fpuObjects: [CarbEntryStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateFPUsArray(with: fpuObjects)
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Error fetching FPU objects: \(error) in \(#file):\(#line)")
            }
        }
    }

    private func fetchFPUs() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: fpuFetchContext,
            predicate: NSPredicate.fpusForChart,
            key: "date",
            ascending: false
        )

        return try await fpuFetchContext.perform {
            guard let fetchedResults = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateFPUsArray(with objects: [CarbEntryStored]) {
        fpusFromPersistence = objects
    }

    func setupProteinFatActivityArray() {
        Task {
            do {
                let ids = try await self.fetchProteinFatMeals()
                let mealObjects: [CarbEntryStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateProteinFatActivityArray(with: mealObjects)
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) Error fetching protein/fat meal objects: \(error) in \(#file):\(#line)"
                )
            }
        }
    }

    private func fetchProteinFatMeals() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: carbsFetchContext,
            predicate: NSPredicate.proteinFatMealsForChart,
            key: "date",
            ascending: true
        )

        return try await carbsFetchContext.perform {
            guard let fetchedResults = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateProteinFatActivityArray(with objects: [CarbEntryStored]) {
        proteinFatMealActivityFromPersistence = objects
        setupProteinFatActivityPoints()
    }

    @MainActor func setupProteinFatActivityPoints() {
        guard proteinFatActivityGraphDisplay != .off else {
            proteinFatActivityPoints = []
            maxValueProteinFatActivityChart = 0
            return
        }

        let meals = proteinFatMealActivityFromPersistence
        guard !meals.isEmpty else {
            proteinFatActivityPoints = []
            maxValueProteinFatActivityChart = 0
            return
        }

        let pointInterval: TimeInterval = 10 * 60
        let visualScale = 0.5
        let proteinDurationFactor = doubleValue(proteinFatActivityProteinDurationFactor).clamped(to: 0.1 ... 1)

        var pointDates: Set<Date> = []
        var cursor = startMarker
        while cursor <= endMarker {
            pointDates.insert(cursor)
            cursor = cursor.addingTimeInterval(pointInterval)
        }

        for meal in meals {
            guard let mealDate = meal.date, mealDate >= startMarker, mealDate <= endMarker else { continue }
            pointDates.insert(mealDate)
        }

        var points: [ProteinFatActivityPoint] = []
        for date in pointDates.sorted() {
            var fatActivity = 0.0
            var proteinActivity = 0.0

            for meal in meals {
                guard let mealDate = meal.date else { continue }
                let fat = max(0, meal.fat)
                let protein = max(0, meal.protein)
                guard fat > 0 || protein > 0 else { continue }

                let fatDuration = proteinFatActivityDuration(for: meal)
                let proteinDuration = max(60 * 60, fatDuration * proteinDurationFactor)

                fatActivity += proteinFatRemainingActivity(
                    grams: fat,
                    mealDate: mealDate,
                    at: date,
                    duration: fatDuration
                )
                proteinActivity += proteinFatRemainingActivity(
                    grams: protein,
                    mealDate: mealDate,
                    at: date,
                    duration: proteinDuration
                )
            }

            points.append(
                ProteinFatActivityPoint(
                    date: date,
                    fatActivity: fatActivity * visualScale,
                    proteinActivity: proteinActivity * visualScale
                )
            )
        }

        proteinFatActivityPoints = points
        let maxActivity = points.map(\.combinedActivity).max() ?? 0
        maxValueProteinFatActivityChart = Decimal(maxActivity)
    }

    private func proteinFatActivityDuration(for meal: CarbEntryStored) -> TimeInterval {
        if let duration = proteinFatAssistDurationFromNote(meal.note) {
            return TimeInterval(duration * 60)
        }

        let fat = Decimal(meal.fat)
        let rawDuration = proteinFatAssistBaseDuration + (max(0, fat) / 10 * proteinFatAssistMinutesPer10gFat)
        let minDuration = min(proteinFatAssistMinimumDuration, proteinFatAssistMaximumDefaultDuration)
        let maxDuration = max(proteinFatAssistMinimumDuration, proteinFatAssistMaximumDefaultDuration)
        let clamped = min(max(rawDuration, minDuration), maxDuration)
        return TimeInterval(doubleValue(clamped) * 60)
    }

    private func proteinFatAssistDurationFromNote(_ note: String?) -> Double? {
        guard let note, let range = note.range(of: "Protein/Fat: Assist ") else { return nil }
        let suffix = note[range.upperBound...]
        guard let minutesEnd = suffix.firstIndex(of: "m") else { return nil }
        let minutesText = suffix[..<minutesEnd]
        return Double(minutesText).map { min(max($0, 60), 720) }
    }

    private func proteinFatRemainingActivity(
        grams: Double,
        mealDate: Date,
        at date: Date,
        duration: TimeInterval
    ) -> Double {
        guard grams > 0, duration > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(mealDate)
        guard elapsed >= 0, elapsed <= duration else { return 0 }

        return grams * max(0, duration - elapsed) / duration
    }

    private func doubleValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
