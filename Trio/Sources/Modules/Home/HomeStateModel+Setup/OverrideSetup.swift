import CoreData
import Foundation

extension Home.StateModel {
    // Setup Overrides
    func setupOverrides() {
        Task {
            do {
                await MainActor.run {
                    ExerciseGlucoseAnnouncementManager.shared.evaluate()
                }
                let ids = try await self.fetchOverrides()
                let overrideObjects: [OverrideStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateOverrideArray(with: overrideObjects)
            } catch let error as CoreDataError {
                debug(.default, "Core Data error in setupOverrides: \(error)")
            } catch {
                debug(.default, "Unexpected error in setupOverrides: \(error)")
            }
        }
    }

    private func fetchOverrides() async throws -> [NSManagedObjectID] {
        let visibleSessionIDs = ExerciseSessionMetadataStore.visibleSessionIDs()
        let activeResults = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: overrideFetchContext,
            predicate: NSPredicate.lastActiveOverride, // this predicate filters for all Overrides within the last 24h
            key: "date",
            ascending: false
        )
        let exerciseResults = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: overrideFetchContext,
            predicate: visibleSessionIDs.isEmpty
                ? NSPredicate(
                    format: "enabled == %@ AND name BEGINSWITH %@",
                    true as NSNumber,
                    OverrideStored.exerciseOverrideName + ":"
                )
                : NSPredicate(format: "enabled == %@ AND id IN %@", true as NSNumber, visibleSessionIDs),
            key: "date",
            ascending: true
        )

        return try await overrideFetchContext.perform {
            guard let fetchedActiveResults = activeResults as? [OverrideStored],
                  let fetchedExerciseResults = exerciseResults as? [OverrideStored]
            else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            let visibleExercise = fetchedExerciseResults.filter { override in
                guard let sessionID = override.id,
                      let metadata = ExerciseSessionMetadataStore.load(sessionID: sessionID)
                else { return false }
                let state = metadata.state()
                return state != .completed && state != .cancelled
            }
            var seen = Set<NSManagedObjectID>()
            let combined = (fetchedActiveResults.filter { $0.isActive() } + visibleExercise).filter { override in
                guard !seen.contains(override.objectID) else { return false }
                seen.insert(override.objectID)
                return true
            }
            return combined.map(\.objectID)
        }
    }

    @MainActor private func updateOverrideArray(with objects: [OverrideStored]) {
        overrides = objects
        let exerciseIDs = objects.filter(\.isExerciseMode).compactMap(\.id).joined(separator: ",")
        if !exerciseIDs.isEmpty {
            debugPrint("ExerciseOverride home provider sessions=\(exerciseIDs)")
        }
    }

    // Setup expired Overrides
    func setupOverrideRunStored() {
        Task {
            do {
                let ids = try await self.fetchOverrideRunStored()
                let overrideRunObjects: [OverrideRunStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateOverrideRunStoredArray(with: overrideRunObjects)
            } catch let error as CoreDataError {
                debug(.default, "Core Data error in setupOverrideRunStored: \(error)")
            } catch {
                debug(.default, "Unexpected error in setupOverrideRunStored: \(error)")
            }
        }
    }

    private func fetchOverrideRunStored() async throws -> [NSManagedObjectID] {
        let predicate = NSPredicate(format: "startDate >= %@", Date.oneDayAgo as NSDate)
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideRunStored.self,
            onContext: overrideFetchContext,
            predicate: predicate,
            key: "startDate",
            ascending: false
        )

        return try await overrideFetchContext.perform {
            guard let fetchedResults = results as? [OverrideRunStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateOverrideRunStoredArray(with objects: [OverrideRunStored]) {
        overrideRunStored = objects
    }

    /// Cancels the running Override, creates an entry in the OverrideRunStored Core Data entity and posts a custom notification so that the AdjustmentsView gets updated
    @MainActor func cancelOverride(withID id: NSManagedObjectID) async {
        do {
            guard let profileToCancel = try viewContext.existingObject(with: id) as? OverrideStored else { return }

            if profileToCancel.isExerciseMode, let sessionID = profileToCancel.id {
                let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", sessionID)
                let sessionOverrides = try viewContext.fetch(fetchRequest)
                for sessionOverride in sessionOverrides {
                    sessionOverride.enabled = false
                    sessionOverride.isUploadedToNS = false
                }
                ExerciseSessionMetadataStore.update(sessionID: sessionID) {
                    $0.cancelledAt = Date()
                    if $0.actualExerciseStart != nil, $0.actualExerciseEnd == nil {
                        $0.actualExerciseEnd = Date()
                    }
                    $0.recoverySkippedReason = "cancelled"
                }
                ExerciseGlucoseAnnouncementManager.shared.stopSpeech()
                debugPrint("ExerciseOverride session \(sessionID) cancelled from Home")
            } else {
                profileToCancel.enabled = false
            }

            guard viewContext.hasChanges else { return }
            try viewContext.save()

            await saveToOverrideRunStored(object: profileToCancel)

            Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
        } catch let error as NSError {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to cancel Profile with error: \(error)")
        }
    }

    /// We can safely pass the NSManagedObject  as we are doing everything on the Main Actor
    @MainActor func saveToOverrideRunStored(object: OverrideStored) async {
        let newOverrideRunStored = OverrideRunStored(context: viewContext)
        newOverrideRunStored.id = object.exercisePhase == .inactive ? UUID() : (UUID(uuidString: object.id ?? "") ?? UUID())
        newOverrideRunStored.name = object.name
        newOverrideRunStored.startDate = object.date ?? .distantPast
        newOverrideRunStored.endDate = Date()
        newOverrideRunStored.target = NSDecimalNumber(decimal: overrideStorage.calculateTarget(override: object))
        newOverrideRunStored.override = object
        newOverrideRunStored.isUploadedToNS = false

        do {
            guard viewContext.hasChanges else { return }
            try viewContext.save()
        } catch let error as NSError {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save an Override to the OverrideRunStored entity with error: \(error)"
            )
        }
    }
}
