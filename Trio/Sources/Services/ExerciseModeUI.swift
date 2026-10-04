import Combine
import Foundation
import SwiftUI
import Swinject
import UIKit

struct ExerciseModeDefaults: Codable, Equatable, Sendable {
    var pre: ExercisePhaseConfiguration
    var exercise: ExercisePhaseConfiguration
    var postEnabled: Bool
    var post: ExercisePhaseConfiguration

    static let standard = ExerciseModeDefaults(
        pre: .init(
            insulinPercentage: 70,
            basalPercentage: 100,
            correctionPercentage: 100,
            smbEnabled: false,
            sensitivityPercentage: 100,
            targetGlucose: 120,
            durationMinutes: 45
        ),
        exercise: .init(
            insulinPercentage: 35,
            basalPercentage: 100,
            correctionPercentage: 100,
            smbEnabled: false,
            sensitivityPercentage: 100,
            targetGlucose: 140,
            announcementEnabled: true,
            announcementIntervalMinutes: 2
        ),
        postEnabled: true,
        post: .init(
            insulinPercentage: 70,
            basalPercentage: 100,
            correctionPercentage: 100,
            smbEnabled: false,
            sensitivityPercentage: 100,
            targetGlucose: 120,
            durationMinutes: 60
        )
    )
}

struct ExercisePreset: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var preEnabled: Bool
    var strategy: ExerciseModeDefaults

    static func migrated(from defaults: ExerciseModeDefaults) -> ExercisePreset {
        ExercisePreset(id: UUID(), name: "Exercise", preEnabled: true, strategy: defaults)
    }

    func configuration(_ value: ExercisePhaseConfiguration) -> ExercisePhaseConfiguration {
        var copy = value
        copy.presetID = id
        copy.presetName = name
        return copy
    }
}

struct ScheduledExercise: Codable, Equatable, Sendable {
    var presetSnapshot: ExercisePreset
    var exerciseStart: Date
    var preStart: Date {
        guard presetSnapshot.preEnabled else { return exerciseStart }
        let minutes = NSDecimalNumber(decimal: presetSnapshot.strategy.pre.durationMinutes ?? 0).doubleValue
        return exerciseStart.addingTimeInterval(-minutes * 60)
    }
}

@MainActor final class ExerciseModeController: ObservableObject {
    @Published private(set) var state: ExerciseModeState = .inactive
    @Published private(set) var presets: [ExercisePreset]
    @Published var selectedPresetID: UUID { didSet { persistLibrary() } }
    @Published private(set) var defaultPresetID: UUID
    /// A throw-away copy used for the next run. Editing it never changes the source preset.
    @Published var sessionDraft: ExercisePreset
    @Published private(set) var schedule: ScheduledExercise?
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    private let manager: ExerciseModeManager
    private let announcementCoordinator: ExerciseAnnouncementCoordinating?
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let libraryKey: String
    private let scheduleKey: String
    private let activeSnapshotKey: String
    private let selectedPresetKey: String
    private let observesLifecycle: Bool
    private var persistedActivePreset: ExercisePreset?
    private var foregroundObserver: AnyCancellable?
    private var scheduleTimer: AnyCancellable?

    init(
        manager: ExerciseModeManager,
        announcementCoordinator: ExerciseAnnouncementCoordinating? = nil,
        userDefaults: UserDefaults = .standard,
        storageKey: String = "trio.exerciseMode.defaults.v1",
        observeLifecycle: Bool = true,
        loadOnInit: Bool = true
    )
    {
        self.manager = manager
        self.announcementCoordinator = announcementCoordinator
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        libraryKey = storageKey + ".presets.v2"
        scheduleKey = storageKey + ".schedule.v2"
        activeSnapshotKey = storageKey + ".activePreset.v2"
        selectedPresetKey = storageKey + ".selectedPreset.v2"
        observesLifecycle = observeLifecycle

        if let data = userDefaults.data(forKey: libraryKey),
           let library = try? JSONDecoder().decode(PresetLibrary.self, from: data), !library.presets.isEmpty
        {
            let restoredSelection = userDefaults.string(forKey: selectedPresetKey).flatMap(UUID.init(uuidString:))
                .flatMap { id in library.presets.contains(where: { $0.id == id }) ? id : nil } ?? library.defaultPresetID
            presets = library.presets
            defaultPresetID = library.defaultPresetID
            selectedPresetID = restoredSelection
            sessionDraft = library.presets.first(where: { $0.id == restoredSelection }) ?? library.presets[0]
        } else {
            let legacy = userDefaults.data(forKey: storageKey)
                .flatMap { try? JSONDecoder().decode(ExerciseModeDefaults.self, from: $0) } ?? .standard
            let migrated = ExercisePreset.migrated(from: legacy)
            presets = [migrated]
            defaultPresetID = migrated.id
            selectedPresetID = migrated.id
            sessionDraft = migrated
        }
        schedule = userDefaults.data(forKey: scheduleKey)
            .flatMap { try? JSONDecoder().decode(ScheduledExercise.self, from: $0) }
        persistedActivePreset = userDefaults.data(forKey: activeSnapshotKey)
            .flatMap { try? JSONDecoder().decode(ExercisePreset.self, from: $0) }
        persistLibrary()

        if observeLifecycle {
            foregroundObserver = Foundation.NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
                .sink { [weak self] _ in Task { @MainActor in await self?.reconcile() } }
            updateScheduleTimer()
        }
        if loadOnInit { Task { await reconcile() } }
    }

    var activeState: ExerciseModeActiveState? { if case let .active(value) = state { value } else { nil } }
    var selectedPreset: ExercisePreset { presets.first(where: { $0.id == selectedPresetID }) ?? presets[0] }
    func select(_ id: UUID) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        selectedPresetID = id
        sessionDraft = preset
    }

    func resetSessionDraft() { sessionDraft = selectedPreset }

    func updateSourcePresetFromDraft() {
        var updated = sessionDraft
        updated.id = selectedPresetID
        save(updated)
        sessionDraft = updated
    }

    func setDefault(_ id: UUID) { guard presets.contains(where: { $0.id == id }) else { return }
        defaultPresetID = id
        persistLibrary() }

    func addPreset() -> ExercisePreset {
        var preset = selectedPreset
        preset.id = UUID()
        preset.name = "New Preset"
        presets.append(preset)
        selectedPresetID = preset.id
        persistLibrary()
        return preset
    }

    func duplicate(_ preset: ExercisePreset) {
        var copy = preset
        copy.id = UUID()
        copy.name += " Copy"
        presets.append(copy)
        selectedPresetID = copy.id
        persistLibrary()
    }

    func save(_ preset: ExercisePreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) { presets[index] = preset }
        else { presets.append(preset) }
        persistLibrary()
    }

    func delete(_ preset: ExercisePreset) {
        guard presets.count > 1 else { return }
        presets.removeAll { $0.id == preset.id }
        if selectedPresetID == preset.id { selectedPresetID = presets[0].id }
        if defaultPresetID == preset.id { defaultPresetID = presets[0].id }
        persistLibrary()
    }

    func schedule(_ start: Date) { schedule = ScheduledExercise(presetSnapshot: sessionDraft, exerciseStart: start)
        persistSchedule()
        updateScheduleTimer() }

    func cancelSchedule() { schedule = nil
        persistSchedule()
        updateScheduleTimer() }

    func startPreNow() async {
        await startPre(using: sessionDraft, exerciseAt: Date().addingTimeInterval(leadSeconds(sessionDraft))) }

    func startExerciseNow() async {
        let preset = sessionDraft
        let configuration = state.phase == .preExercise ? nil : preset.configuration(preset.strategy.exercise)
        await perform { try await manager.startExercise(configuration: configuration, source: .app) }
        if state.phase == .exercise, persistedActivePreset == nil { persistActiveSnapshot(preset) }
        if state.phase == .exercise { cancelSchedule() }
    }

    func cancelPreExercise() async { await perform { try await manager.cancelPreExercise(source: .app) }
        cancelSchedule() }

    func stopExercise(usePost: Bool) async {
        let preset = activePresetSnapshot ?? selectedPreset
        let post = usePost && preset.strategy.postEnabled ? [preset.configuration(preset.strategy.post)] : []
        await perform { try await manager.stopExercise(postConfigurations: post, source: .app) }
    }

    func endRecoveryNow() async { await perform { try await manager.endPostExercise(source: .app) } }
    func refresh() async { await perform { try await manager.currentState() } }
    func reconcile(at date: Date = Date()) async {
        if state.phase == nil, let schedule, date >= schedule.preStart {
            if schedule.presetSnapshot.preEnabled {
                await startPre(
                    using: schedule.presetSnapshot,
                    exerciseAt: schedule.exerciseStart,
                    source: .scheduled,
                    at: schedule.preStart
                )
            } else {
                let preset = schedule.presetSnapshot
                await perform {
                    try await manager.startExercise(
                        configuration: preset.configuration(preset.strategy.exercise), source: .scheduled,
                        at: schedule.exerciseStart
                    )
                }
                if state.phase == .exercise { persistActiveSnapshot(preset) }
            }
        }
        await perform(showBusy: false) { try await manager.reconcile(at: date) }
        if state.phase == .exercise { cancelSchedule() }
    }

    private var activePresetSnapshot: ExercisePreset? { persistedActivePreset }

    private func startPre(
        using preset: ExercisePreset,
        exerciseAt: Date,
        source: ExerciseTransitionSource = .app,
        at date: Date = Date()
    ) async
    {
        await perform {
            try await manager.startPreExercise(
                configuration: preset.configuration(preset.strategy.pre),
                exerciseConfiguration: preset.configuration(preset.strategy.exercise),
                scheduledExerciseAt: exerciseAt,
                source: source,
                at: date
            )
        }
        if state.phase == .preExercise { persistActiveSnapshot(preset) }
    }

    private func leadSeconds(_ preset: ExercisePreset) -> TimeInterval {
        NSDecimalNumber(decimal: preset.strategy.pre.durationMinutes ?? 0).doubleValue * 60
    }

    private func perform(
        showBusy: Bool = true,
        _ operation: () async throws -> ExerciseModeState
    ) async {
        guard !isBusy else { return }
        if showBusy { isBusy = true }
        defer { if showBusy { isBusy = false } }
        do {
            let nextState = try await operation()
            let stateChanged = state != nextState
            if stateChanged { state = nextState }
            if stateChanged { announcementCoordinator?.reconcile(state: state) }
            updateScheduleTimer()
            if state.phase == nil { clearActiveSnapshot() }
            if errorMessage != nil { errorMessage = nil } } catch { errorMessage = error.localizedDescription
            if let value = try? await manager.currentState() {
                let stateChanged = state != value
                if stateChanged { state = value }
                if stateChanged { announcementCoordinator?.reconcile(state: value) }
                updateScheduleTimer()
            } }
    }

    private func updateScheduleTimer() {
        guard observesLifecycle, schedule != nil || state.phase != nil else {
            scheduleTimer?.cancel()
            scheduleTimer = nil
            return
        }
        guard scheduleTimer == nil else { return }
        scheduleTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
            .sink { [weak self] date in
                Task { @MainActor in await self?.reconcile(at: date) }
            }
    }

    private func persistLibrary() {
        guard !presets.isEmpty else { return }
        let id = presets.contains(where: { $0.id == defaultPresetID }) ? defaultPresetID : presets[0].id
        userDefaults.set(try? JSONEncoder().encode(PresetLibrary(presets: presets, defaultPresetID: id)), forKey: libraryKey)
        userDefaults.set(selectedPresetID.uuidString, forKey: selectedPresetKey)
    }

    private func persistSchedule() {
        if let schedule { userDefaults.set(try? JSONEncoder().encode(schedule), forKey: scheduleKey) }
        else { userDefaults.removeObject(forKey: scheduleKey) }
    }

    private func persistActiveSnapshot(_ preset: ExercisePreset) {
        persistedActivePreset = preset
        userDefaults.set(try? JSONEncoder().encode(preset), forKey: activeSnapshotKey)
    }

    private func clearActiveSnapshot() {
        persistedActivePreset = nil
        userDefaults.removeObject(forKey: activeSnapshotKey)
    }

    private struct PresetLibrary: Codable { var presets: [ExercisePreset]
        var defaultPresetID: UUID }
}

enum ExerciseModeUI {
    static let preColor = Color.yellow, exerciseColor = Color.purple, postColor = Color.teal
    static func color(for phase: ExercisePhase?) -> Color { phase == .preExercise ? preColor : phase == .exercise ?
        exerciseColor :
        phase == .postExercise ? postColor : .secondary }

    static func title(for phase: ExercisePhase?) -> String { phase == .preExercise ? "PRE" : phase == .exercise ? "EXERCISE" :
        phase == .postExercise ? "RECOVERY" : "EXERCISE" }
}

struct ExerciseModeRootView: View {
    let resolver: Resolver
    @ObservedObject private var controller: ExerciseModeController
    private let units: GlucoseUnits
    init(resolver: Resolver, units: GlucoseUnits? = nil) {
        self.resolver = resolver
        controller = resolver.resolve(ExerciseModeController.self)!
        self.units = units ?? resolver.resolve(SettingsManager.self)!.settings.units
    }

    var body: some View {
        Group {
            controller.state
                .phase == nil ? AnyView(ExerciseLauncherView(controller: controller, units: units)) :
                AnyView(ExerciseActiveView(controller: controller, units: units)) }
            .navigationTitle("Exercise").navigationBarTitleDisplayMode(.inline)
            .task { await controller.reconcile() }
            .alert(
                "Exercise Mode",
                isPresented: .init(get: { controller.errorMessage != nil }, set: { if !$0 { controller.errorMessage = nil } })
            ) { Button("OK", role: .cancel) {} } message: { Text(controller.errorMessage ?? "") }
    }
}

struct ExerciseModeSettingsView: View {
    @ObservedObject private var controller: ExerciseModeController
    private let units: GlucoseUnits

    init(resolver: Resolver) {
        controller = resolver.resolve(ExerciseModeController.self)!
        units = resolver.resolve(SettingsManager.self)!.settings.units
    }

    var body: some View {
        ExercisePresetPicker(controller: controller, units: units)
    }
}

private struct ExerciseLauncherView: View {
    @ObservedObject var controller: ExerciseModeController
    let units: GlucoseUnits
    @State private var plannedStart = Date().addingTimeInterval(3600)
    var preset: ExercisePreset { controller.sessionDraft }
    var body: some View {
        List {
            Section {
                NavigationLink { ExercisePresetSelectionView(controller: controller, units: units) } label: {
                    LabeledContent("Preset", value: preset.name) } }
            Section { strategySummary }
            Section("Planned exercise start") {
                DatePicker("Exercise starts", selection: $plannedStart, in: Date()...)
                if preset.preEnabled {
                    LabeledContent("PRE starts", value: preStart.formatted(date: .abbreviated, time: .shortened))
                }
                Button("SCHEDULE") { controller.schedule(plannedStart) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("exercise-schedule")
                if let schedule = controller
                    .schedule
                {
                    Text(
                        schedule.presetSnapshot.preEnabled ?
                            "Scheduled: PRE \(schedule.preStart.formatted(date: .omitted, time: .shortened)) → Exercise \(schedule.exerciseStart.formatted(date: .omitted, time: .shortened))" :
                            "Scheduled: Exercise \(schedule.exerciseStart.formatted(date: .omitted, time: .shortened))"
                    )
                    .foregroundStyle(.secondary)
                    Button("CANCEL SCHEDULE", role: .destructive) { controller.cancelSchedule() }
                }
            }
            Section {
                if preset.preEnabled {
                    action("START PRE NOW", ExerciseModeUI.preColor, identifier: "exercise-start-pre") {
                        await controller.startPreNow()
                    }
                }
                action("START EXERCISE NOW", ExerciseModeUI.exerciseColor, identifier: "exercise-start-now") {
                    await controller.startExerciseNow()
                }
                NavigationLink("Adjust This Session") {
                    ExercisePresetEditor(controller: controller, preset: preset, units: units, sessionOnly: true)
                }
            }
            warning
        }
    }

    private var preStart: Date {
        plannedStart.addingTimeInterval(-NSDecimalNumber(decimal: preset.strategy.pre.durationMinutes ?? 0).doubleValue * 60) }

    private var strategySummary: some View {
        VStack(spacing: 12) {
            HStack {
                summary("PRE", preset.preEnabled ? "\(preset.strategy.pre.durationMinutes ?? 0) min" : "Off", preset.strategy.pre)
                summary("EXERCISE", "\(preset.strategy.exercise.insulinPercentage)%", preset.strategy.exercise)
                summary(
                    "POST",
                    preset.strategy
                        .postEnabled ?
                        "\(preset.strategy.post.insulinPercentage)% / \(preset.strategy.post.durationMinutes ?? 0)m" :
                        "Off",
                    preset.strategy.post
                ) }
        }.padding(.vertical, 6)
    }

    private func summary(
        _ title: String,
        _ value: String,
        _ config: ExercisePhaseConfiguration
    ) -> some View { VStack(spacing: 4) { Text(title).font(.caption.bold())
        Text(value).font(.subheadline.bold())
        Text(config.targetGlucose.formatted(withUnits: units)).font(.caption2)
        Text(config.smbEnabled ? "SMB ON" : "SMB OFF").font(.caption2) }.frame(maxWidth: .infinity) }
}

private struct ExerciseActiveView: View {
    @ObservedObject var controller: ExerciseModeController
    let units: GlucoseUnits
    @State private var confirmStop = false
    @ViewBuilder var body: some View {
        if let active = controller.activeState {
            List {
                Section { TimelineView(.periodic(from: .now, by: 1)) { now in
                    VStack(spacing: 8) {
                        Text("\(ExerciseModeUI.title(for: active.phase)) — \(active.configuration.presetName ?? "Exercise")")
                            .font(.title2.bold()).foregroundStyle(ExerciseModeUI.color(for: active.phase))
                        Text(elapsed(active.phaseStartedAt, now.date)).font(.title3.monospacedDigit())
                        LabeledContent("Insulin", value: "\(active.configuration.insulinPercentage)%")
                        LabeledContent("Target", value: active.configuration.targetGlucose.formatted(withUnits: units))
                        LabeledContent("SMB", value: active.configuration.smbEnabled ? "ON" : "OFF")
                        if let time = active
                            .scheduledExerciseAt
                        {
                            LabeledContent("Planned exercise", value: time.formatted(date: .omitted, time: .shortened)) } }
                        .frame(maxWidth: .infinity) } }
                Section("Controls") {
                    if active
                        .phase ==
                        .preExercise
                    {
                        action("START EXERCISE NOW", ExerciseModeUI.exerciseColor, identifier: "exercise-active-start") {
                            await controller.startExerciseNow()
                        }
                        action("CANCEL SESSION", .red, identifier: "exercise-active-cancel") {
                            await controller.cancelPreExercise()
                        } } else if active
                        .phase ==
                        .exercise
                    {
                        Button("STOP EXERCISE") { confirmStop = true }.foregroundStyle(.red)
                            .accessibilityIdentifier("exercise-active-stop")
                            .confirmationDialog("Stop Exercise", isPresented: $confirmStop) {
                                Button("ENTER RECOVERY") { Task { await controller.stopExercise(usePost: true) } }
                                Button("SKIP RECOVERY / END SESSION", role: .destructive) {
                                    Task { await controller.stopExercise(usePost: false) } } } } else {
                        action("END RECOVERY NOW", ExerciseModeUI.postColor, identifier: "exercise-active-end-post") {
                            await controller.endRecoveryNow()
                        } }
                }
                warning
            }
        }
    }

    private func elapsed(_ start: Date, _ end: Date) -> String { let s = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) }
}

struct ExercisePresetPicker: View {
    @ObservedObject var controller: ExerciseModeController
    let units: GlucoseUnits
    var body: some View { List { ForEach(controller.presets) { preset in
        Button { controller.select(preset.id) } label: {
            HStack { VStack(alignment: .leading) { Text(preset.name)
                Text(
                    "Exercise \(preset.strategy.exercise.insulinPercentage)% • \(preset.strategy.exercise.targetGlucose.formatted(withUnits: units))"
                )
                .font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if controller.selectedPresetID == preset.id { Image(systemName: "checkmark") }
            if controller.defaultPresetID == preset.id { Image(systemName: "star.fill") } } }
            .swipeActions { Button("Duplicate") { controller.duplicate(preset) }.tint(.blue)
                if controller.presets.count > 1 { Button("Delete", role: .destructive) { controller.delete(preset) } } } }
    Section { NavigationLink("Edit Selected Preset") {
        ExercisePresetEditor(controller: controller, preset: controller.selectedPreset, units: units)
    }
    Button("Create Preset") { _ = controller.addPreset() } }
    }.navigationTitle("Presets") }
}

private struct ExercisePresetSelectionView: View {
    @ObservedObject var controller: ExerciseModeController
    let units: GlucoseUnits
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Choose for this session") {
                ForEach(controller.presets) { preset in
                    Button {
                        controller.select(preset.id)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(preset.name).foregroundStyle(.primary)
                                Text(
                                    "PRE \(preset.preEnabled ? "\(preset.strategy.pre.durationMinutes ?? 0)m" : "Off") • Exercise \(preset.strategy.exercise.insulinPercentage)% • \(preset.strategy.exercise.targetGlucose.formatted(withUnits: units))"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if controller.selectedPresetID == preset.id { Image(systemName: "checkmark") }
                        }
                    }
                    .accessibilityIdentifier("exercise-preset-\(preset.id.uuidString)")
                }
            }
            Section {
                NavigationLink("Manage Presets") {
                    ExercisePresetPicker(controller: controller, units: units)
                }
            }
        }
        .navigationTitle("Exercise Preset")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ExercisePresetEditor: View {
    @ObservedObject var controller: ExerciseModeController
    @State var preset: ExercisePreset
    let units: GlucoseUnits
    var sessionOnly = false
    @Environment(\.dismiss) private var dismiss
    var body: some View { Form { Section { TextField("Preset name", text: $preset.name)
        Toggle("Use PRE", isOn: $preset.preEnabled) }
    if preset.preEnabled { config("PRE", $preset.strategy.pre, duration: true, announcements: false) }
    config("EXERCISE", $preset.strategy.exercise, duration: false, announcements: false)
    Section("POST") { Toggle("Use recovery", isOn: $preset.strategy.postEnabled)
        if preset.strategy.postEnabled { rows($preset.strategy.post, duration: true, announcements: false) } }
    Section {
        if sessionOnly {
            Button("Apply to This Session") {
                controller.sessionDraft = preset
                dismiss()
            }
            .accessibilityIdentifier("exercise-apply-session-draft")
            Button("Update Source Preset") {
                controller.sessionDraft = preset
                controller.updateSourcePresetFromDraft()
                dismiss()
            }
        } else {
            Button("Save Preset") { controller.save(preset) }
            Button("Set as Default") { controller.save(preset)
                controller.setDefault(preset.id) }
        }
    }
    warning }.navigationTitle(sessionOnly ? "Adjust Session" : preset.name).navigationBarTitleDisplayMode(.inline) }
    private func config(
        _ title: String,
        _ binding: Binding<ExercisePhaseConfiguration>,
        duration: Bool,
        announcements: Bool
    ) -> some View { Section(title) { rows(binding, duration: duration, announcements: announcements) } }
    @ViewBuilder private func rows(_ c: Binding<ExercisePhaseConfiguration>, duration: Bool, announcements: Bool) -> some View {
        percent("Overall insulin", c.insulinPercentage, 0 ... 100)
        percent("Basal component", c.basalPercentage, 0 ... 200)
        percent("Correction component", c.correctionPercentage, 0 ... 200)
        Toggle("SMB enabled", isOn: c.smbEnabled)
        percent("Sensitivity / ISF", c.sensitivityPercentage, 25 ... 300)
        let target = Binding<Double>(
            get: { NSDecimalNumber(decimal: c.wrappedValue.targetGlucose.asUnit(units)).doubleValue },
            set: { c.wrappedValue.targetGlucose = units == .mgdL ? Decimal($0) : Decimal($0).asMgdL }
        )
        Stepper(
            "Target: \(c.wrappedValue.targetGlucose.formatted(withUnits: units))",
            value: target,
            in: units == .mgdL ? 70 ... 250 : 3.9 ... 13.9,
            step: units == .mgdL ? 5 : 0.1
        )
        if duration { decimalStep("Duration", c.durationMinutes, 1 ... 360, 5, "min") }
        if announcements { Toggle("Glucose announcements", isOn: c.announcementEnabled)
            if c.wrappedValue.announcementEnabled { decimalStep("Interval", c.announcementIntervalMinutes, 1 ... 30, 1, "min") } }
    }

    private func percent(
        _ title: String,
        _ value: Binding<Decimal>,
        _ range: ClosedRange<Double>
    )
        -> some View
    { VStack(alignment: .leading) { LabeledContent(title, value: "\(value.wrappedValue)%")
        Slider(value: double(value), in: range, step: 5) } }
    private func decimalStep(
        _ title: String,
        _ value: Binding<Decimal?>,
        _ range: ClosedRange<Double>,
        _ step: Double,
        _ suffix: String
    ) -> some View { Stepper(
        "\(title): \(value.wrappedValue ?? 0) \(suffix)",
        value: Binding(
            get: { NSDecimalNumber(decimal: value.wrappedValue ?? 0).doubleValue },
            set: { value.wrappedValue = Decimal($0) }
        ),
        in: range,
        step: step
    ) }
    private func decimalStep(
        _ title: String,
        _ value: Binding<Decimal>,
        _ range: ClosedRange<Double>,
        _ step: Double,
        _ suffix: String
    ) -> some View { Stepper("\(title): \(value.wrappedValue) \(suffix)", value: double(value), in: range, step: step) }
    private func double(_ value: Binding<Decimal>)
        -> Binding<Double>
    {
        Binding(get: { NSDecimalNumber(decimal: value.wrappedValue).doubleValue }, set: { value.wrappedValue = Decimal($0) }) }
}

struct ExerciseModeHomeControl: View {
    @ObservedObject var controller: ExerciseModeController
    let action: () -> Void
    var body: some View { Button(action: action) { TimelineView(.periodic(from: .now, by: 1)) { now in
        HStack(spacing: 10) {
            Image(systemName: controller.state.phase == nil ? "figure.run" : "figure.run.circle.fill").font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                if let active = controller
                    .activeState
                {
                    Text("\(ExerciseModeUI.title(for: active.phase)) — \(active.configuration.presetName ?? "Exercise")")
                        .font(.caption.bold())
                    Text("\(active.configuration.insulinPercentage)% • \(timing(active, now.date))")
                        .font(.caption2.monospacedDigit()) } else { Text("Exercise").font(.subheadline.bold())
                    Text(
                        controller
                            .schedule == nil ? "Start or schedule a session" :
                            "Scheduled \(controller.schedule!.exerciseStart.formatted(date: .omitted, time: .shortened))"
                    ).font(.caption2) } }
            Spacer()
            Image(systemName: "chevron.right") }.foregroundStyle(controller.state.phase == nil ? Color.primary : Color.white)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        controller.state.phase == nil ? Color.secondary.opacity(0.13) : ExerciseModeUI
                            .color(for: controller.state.phase)
                    )
            )
    } }.buttonStyle(.plain).accessibilityLabel("Open Exercise Mode") }
    private func short(_ start: Date, _ end: Date) -> String { let s = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) }

    private func timing(_ active: ExerciseModeActiveState, _ now: Date) -> String {
        if active.phase == .preExercise, let scheduled = active.scheduledExerciseAt {
            return "Exercise \(scheduled.formatted(date: .omitted, time: .shortened)) • \(short(now, scheduled)) remaining"
        }
        if active.phase == .postExercise, let duration = active.configuration.durationMinutes {
            let end = active.phaseStartedAt.addingTimeInterval(NSDecimalNumber(decimal: duration).doubleValue * 60)
            return "\(short(now, end)) remaining"
        }
        return "\(short(active.phaseStartedAt, now)) elapsed"
    }
}

private var warning: some View {
    Section {
        Label("Active Exercise phase settings affect insulin dosing", systemImage: "checkmark.shield.fill").font(.caption.bold())
            .foregroundStyle(.secondary) } }

private func action(
    _ title: String,
    _ color: Color,
    identifier: String? = nil,
    operation: @escaping () async -> Void
) -> some View {
    Button(title) { Task { await operation() } }
        .fontWeight(.semibold)
        .foregroundStyle(color)
        .accessibilityIdentifier(identifier ?? "")
}
