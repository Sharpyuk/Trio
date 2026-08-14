import CoreData
import SwiftUI
import Swinject

extension Adjustments {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State var isEditing = false
        @State var showOverrideCreationSheet = false
        @State var showExerciseModeCreationSheet = false
        @State var showExerciseReportsSheet = false
        @State var showTempTargetCreationSheet = false
        @State var showingDetail = false
        @State var showOverrideCheckmark: Bool = false
        @State var showTempTargetCheckmark: Bool = false
        @State var selectedOverridePresetID: String?
        @State var selectedTempTargetPresetID: String?
        @State var selectedOverride: OverrideStored?
        @State var selectedTempTarget: TempTargetStored?
        @State var isConfirmDeletePresented = false
        @State var isPromptPresented = false
        @State var isRemoveAlertPresented = false
        @State var removeAlert: Alert?
        @State var isEditingTT = false
        @State var showCancelOverrideConfirmDialog = false
        @State var showCancelTempTargetConfirmDialog = false
        @State var pendingPresetActivation: PendingPresetActivation?

        @FetchRequest(fetchRequest: OverrideStored.fetch(
            NSPredicate.lastActiveOverride,
            ascending: false,
            fetchLimit: 0
        )) var activeOverrides: FetchedResults<OverrideStored>

        private var shouldDisplayStickyOverrideStopButton: Bool {
            state.isOverrideEnabled &&
                state.activeOverrideName.isNotEmpty &&
                state.currentActiveOverride?.isExerciseMode != true
        }

        private var shouldDisplayStickyTempTargetStopButton: Bool {
            state.isTempTargetEnabled && state.activeTempTargetName.isNotEmpty
        }

        private var activeProteinFatAssistOverrides: [OverrideStored] {
            let assists = activeOverrides.filter { override in
                override.isActive() &&
                    override.currentProteinFatAssist &&
                    override.objectID != state.currentActiveOverride?.objectID
            }
            return Array(assists.prefix(1))
        }

        private var hasActiveExerciseOverride: Bool {
            activeOverrides.contains { $0.isActive() && $0.isExerciseMode } ||
                state.scheduledExerciseOverrides.contains { $0.isActive() && $0.isExerciseMode }
        }

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        func formattedGlucose(glucose: Decimal) -> String {
            let formattedValue: String
            if state.units == .mgdL {
                formattedValue = Formatter.glucoseFormatter(for: state.units)
                    .string(from: glucose as NSDecimalNumber) ?? "\(glucose)"
            } else {
                formattedValue = glucose.formattedAsMmolL
            }
            return "\(formattedValue) \(state.units.rawValue)"
        }

        var body: some View {
            ZStack(alignment: .center, content: {
                VStack {
                    Picker("Adjustment Tabs", selection: $state.selectedTab) {
                        ForEach(Adjustments.Tab.allCases.indexed(), id: \.1) { index, item in
                            Text(item.name).tag(index)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)

                    List {
                        switch state.selectedTab {
                        case .overrides: overrides()
                        case .tempTargets: tempTargets() }
                    }
                    .scrollContentBackground(.hidden)
                    .background(appState.trioBackgroundColor(for: colorScheme))
                }
                .listSectionSpacing(10)
                .safeAreaInset(
                    edge: .bottom,
                    spacing: shouldDisplayStickyOverrideStopButton || shouldDisplayStickyTempTargetStopButton ? 30 : 0
                ) {
                    if shouldDisplayStickyOverrideStopButton, state.selectedTab == .overrides {
                        stickyStopOverrideButton
                    } else if shouldDisplayStickyTempTargetStopButton, state.selectedTab == .tempTargets {
                        stickyStopTempTargetButton
                    } else {
                        EmptyView()
                    }
                }
                .scrollContentBackground(.hidden)
                .background(appState.trioBackgroundColor(for: colorScheme))
                .onAppear(perform: configureView)
                .navigationBarTitle("Adjustments")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        switch state.selectedTab {
                        case .overrides:
                            Menu {
                                Button(action: {
                                    showExerciseModeCreationSheet = true
                                }, label: {
                                    Label("Exercise Override", systemImage: "figure.run")
                                })

                                Button(action: {
                                    showExerciseReportsSheet = true
                                }, label: {
                                    Label("Exercise Reports", systemImage: "doc.text.magnifyingglass")
                                })

                                Button(action: {
                                    showOverrideCreationSheet = true
                                }, label: {
                                    Label("Override", systemImage: "plus")
                                })
                            } label: {
                                HStack {
                                    Text("Add")
                                    Image(systemName: "plus")
                                }
                            }
                        case .tempTargets:
                            Button(action: {
                                showTempTargetCreationSheet = true
                            }, label: {
                                HStack {
                                    Text("Add Temp Target")
                                    Image(systemName: "plus")
                                }
                            })
                        }
                    }
                }
                .sheet(isPresented: $state.showOverrideEditSheet, onDismiss: {
                    Task {
                        await state.resetStateVariables()
                        state.showOverrideEditSheet = false
                    }

                }) {
                    if let override = selectedOverride {
                        EditOverrideForm(overrideToEdit: override, state: state)
                    }
                }
                .sheet(isPresented: $showOverrideCreationSheet, onDismiss: {
                    Task {
                        await state.resetStateVariables()
                        showOverrideCreationSheet = false
                    }
                }) {
                    AddOverrideForm(state: state)
                }
                .sheet(isPresented: $showExerciseModeCreationSheet, onDismiss: {
                    Task {
                        await state.resetExerciseModeState()
                        showExerciseModeCreationSheet = false
                    }
                }) {
                    ExerciseModeForm(state: state)
                }
                .sheet(isPresented: $showExerciseReportsSheet) {
                    ExerciseReportsListView()
                }
                .sheet(isPresented: $showTempTargetCreationSheet, onDismiss: {
                    Task {
                        await state.resetTempTargetState()
                        showTempTargetCreationSheet = false
                    }
                }) {
                    AddTempTargetForm(state: state)
                }
                .sheet(isPresented: $state.showTempTargetEditSheet, onDismiss: {
                    Task {
                        await state.resetTempTargetState()
                        state.showTempTargetEditSheet = false
                    }

                }) {
                    if let tempTarget = selectedTempTarget {
                        EditTempTargetForm(tempTargetToEdit: tempTarget, state: state)
                    }
                }
                .confirmationDialog("Override to Stop", isPresented: $showCancelOverrideConfirmDialog) {
                    Button("Stop", role: .destructive) {
                        Task {
                            // Save cancelled Override in OverrideRunStored Entity
                            // Cancel ALL active Override
                            await state.disableAllActiveOverrides(createOverrideRunEntry: true)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Stop the Override \"\(state.currentActiveOverride?.name ?? "")\"?")
                }
                .confirmationDialog("Temp Target to Stop", isPresented: $showCancelTempTargetConfirmDialog) {
                    Button("Stop", role: .destructive) {
                        Task {
                            // Save cancelled Temp Targets in TempTargetRunStored Entity
                            // Cancel ALL active Temp Targets
                            await state.disableAllActiveTempTargets(createTempTargetRunEntry: true)
                            // Update View
                            state.updateLatestTempTargetConfiguration()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Stop the Temp Target \"\(state.currentActiveTempTarget?.name ?? "")\"?")
                }
                .confirmationDialog(
                    "Activate Preset",
                    isPresented: presetActivationConfirmationBinding
                ) {
                    Button("Activate") {
                        if let activation = pendingPresetActivation {
                            activatePreset(activation)
                        }
                    }

                    Button("Cancel", role: .cancel) {
                        state.shouldDisplayPresetStartConfirmDialog = false
                        pendingPresetActivation = nil
                    }
                } message: {
                    if let activation = pendingPresetActivation {
                        Text(activation.confirmationMessage)
                    }
                }
            }).background(appState.trioBackgroundColor(for: colorScheme))
        }

        var defaultText: some View {
            switch state.selectedTab {
            case .overrides:
                Section {} header: {
                    Text("Add Preset or Override by tapping 'Add Override +' in the top right-hand corner of the screen.")
                        .textCase(nil)
                        .foregroundStyle(.secondary)
                }
            case .tempTargets:
                Section {} header: {
                    Text(
                        "Add Preset or Temp Target by tapping 'Add Temp Target +' in the top right-hand corner of the screen."
                    )
                    .textCase(nil)
                    .foregroundStyle(.secondary)
                }
            }
        }

        @ViewBuilder var currentActiveAdjustment: some View {
            switch state.selectedTab {
            case .overrides:
                Section {
                    if let override = state.currentActiveOverride, override.isExerciseMode {
                        ExercisePhaseStatusView(
                            override: override,
                            formattedTimeRemaining: formattedTimeRemaining,
                            startExerciseNow: {
                                Task {
                                    await state.startExerciseNow(override.objectID)
                                }
                            },
                            stopExercise: {
                                Task {
                                    await state.stopExerciseNow(override.objectID)
                                }
                            },
                            endRecovery: {
                                Task {
                                    await state.endExerciseRecovery(override.objectID)
                                }
                            },
                            cancelExercise: {
                                Task {
                                    await state.cancelScheduledExerciseOverride(override.objectID)
                                }
                            }
                        )
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(state.activeOverrideName) is running")

                                if let activeUntil = state.currentActiveOverride?.activeUntilDate() {
                                    Text("\(formattedTimeRemaining(activeUntil.timeIntervalSinceNow)) remaining")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let activeOverride = state.currentActiveOverride,
                                   let proteinFatAssistDetails = proteinFatAssistDetails(for: activeOverride)
                                {
                                    Text(proteinFatAssistDetails)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let activeOverride = state.currentActiveOverride,
                                   activeOverride.currentProteinFatAssist,
                                   hasActiveExerciseOverride
                                {
                                    Text(proteinFatExerciseMergeSummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                            Image(systemName: "square.and.pencil")
                                .foregroundStyle(Color.primary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                /// To avoid editing the Preset when a Preset-Override is running we first duplicate the Preset-Override as a non-Preset Override
                                /// The currentActiveOverride variable in the State will update automatically via MOC notification
                                await state.duplicateOverridePresetAndCancelPreviousOverride()

                                /// selectedOverride is used for passing the chosen Override to the EditSheet so we have to set the updated currentActiveOverride to be the selectedOverride
                                selectedOverride = state.currentActiveOverride

                                /// Now we can show the Edit sheet
                                state.showOverrideEditSheet = true
                            }
                        }
                    }
                }
                .listRowBackground(Color.purple.opacity(0.8))
            case .tempTargets:
                Section {
                    HStack {
                        Text("\(state.activeTempTargetName) is running")

                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Color.primary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task {
                            /// To avoid editing the Preset when a Preset-Override is running we first duplicate the Preset-Override as a non-Preset Override
                            /// The currentActiveOverride variable in the State will update automatically via MOC notification
                            await state.duplicateTempTargetPresetAndCancelPreviousTempTarget()

                            /// selectedOverride is used for passing the chosen Override to the EditSheet so we have to set the updated currentActiveOverride to be the selectedOverride
                            selectedTempTarget = state.currentActiveTempTarget

                            /// Now we can show the Edit sheet
                            state.showTempTargetEditSheet = true
                        }
                    }
                }
                .listRowBackground(Color.loopGreen.opacity(0.8))
            }
        }

        @ViewBuilder var activeProteinFatAssistAdjustments: some View {
            if !activeProteinFatAssistOverrides.isEmpty {
                Section {
                    ForEach(activeProteinFatAssistOverrides) { override in
                        activeProteinFatAssistRow(for: override)
                    }
                } header: {
                    Text("Protein/Fat Assist")
                }
                .listRowBackground(Color.gray.opacity(0.18))
            }
        }

        @ViewBuilder private func activeProteinFatAssistRow(for override: OverrideStored) -> some View {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(override.name ?? "Protein/Fat Assist") is running")

                    if let activeUntil = override.activeUntilDate() {
                        Text("\(formattedTimeRemaining(activeUntil.timeIntervalSinceNow)) remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let details = proteinFatAssistDetails(for: override) {
                        Text(details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if hasActiveExerciseOverride {
                        Text(proteinFatExerciseMergeSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Cancel") {
                    Task {
                        await state.cancelOverride(withID: override.objectID)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }

        private func proteinFatAssistDetails(for override: OverrideStored) -> String? {
            guard override.currentProteinFatAssist else { return nil }

            var details: [String] = []
            if let target = override.target?.decimalValue, target > 0 {
                let displayTarget = state.units == .mmolL ? target.asMmolL.formatted(.number.precision(.fractionLength(1))) :
                    target.formatted(.number.precision(.fractionLength(0)))
                details.append("target \(displayTarget) \(state.units.rawValue)")
            } else {
                details.append("target Off")
            }

            if override.isf, override.percentage != 100 {
                details.append("ISF \(Int(override.percentage))%")
            }

            if override.advancedSettings, !override.smbIsOff {
                if let smbMinutes = override.smbMinutes?.decimalValue {
                    details.append("SMB \(Int(truncating: smbMinutes as NSNumber))m")
                }
                if let uamMinutes = override.uamMinutes?.decimalValue {
                    details.append("UAM \(Int(truncating: uamMinutes as NSNumber))m")
                }
            }

            return details.isEmpty ? nil : details.joined(separator: ", ")
        }

        private var proteinFatExerciseMergeSummary: String {
            String(
                localized: "Exercise active: basal/target safety is controlled by Exercise; Protein/Fat ISF/SMB/UAM may be suppressed until Exercise/recovery ends."
            )
        }

        var cancelAdjustmentButton: some View {
            switch state.selectedTab {
            case .overrides:
                Button(action: {
                    showCancelOverrideConfirmDialog = true
                }, label: {
                    Text("Stop Override")

                })
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!state.isOverrideEnabled)
                    .listRowBackground(!state.isOverrideEnabled ? Color(.systemGray4) : Color(.systemRed))
                    .tint(.white)
            case .tempTargets:
                Button(action: {
                    showCancelTempTargetConfirmDialog = true
                }, label: {
                    Text("Stop Temp Target")

                })
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!state.isTempTargetEnabled)
                    .listRowBackground(!state.isTempTargetEnabled ? Color(.systemGray4) : Color(.systemRed))
                    .tint(.white)
            }
        }

        func formattedTimeRemaining(_ timeInterval: TimeInterval) -> String {
            let totalSeconds = Int(timeInterval)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60

            if hours > 0 {
                return "\(hours)h \(minutes)m \(seconds)s"
            } else if minutes > 0 {
                return "\(minutes)m \(seconds)s"
            } else {
                return "<1m"
            }
        }
    }
}

// MARK: Preset Activation Handling

extension Adjustments.RootView: View {
    enum PendingPresetActivation {
        case override(objectID: NSManagedObjectID, presetID: String?, name: String)
        case tempTarget(objectID: NSManagedObjectID, presetID: String?, name: String)

        var name: String {
            switch self {
            case let .override(_, _, name),
                 let .tempTarget(_, _, name):
                return name
            }
        }

        var adjustmentType: String {
            switch self {
            case .override:
                return String(localized: "Override")
            case .tempTarget:
                return String(localized: "Temp Target")
            }
        }

        var confirmationMessage: String {
            String(localized: "Start the \(adjustmentType) \"\(name)\"?", comment: "Confirmation message for starting a preset")
        }
    }

    private var presetActivationConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                state.requireAdjustmentsConfirmation &&
                    state.shouldDisplayPresetStartConfirmDialog &&
                    pendingPresetActivation != nil
            },
            set: { isPresented in
                if !isPresented {
                    state.shouldDisplayPresetStartConfirmDialog = false
                    pendingPresetActivation = nil
                }
            }
        )
    }

    func requestPresetActivation(_ activation: PendingPresetActivation) {
        if state.requireAdjustmentsConfirmation {
            pendingPresetActivation = activation
            state.shouldDisplayPresetStartConfirmDialog = true
        } else {
            activatePreset(activation)
        }
    }

    func activatePreset(_ activation: PendingPresetActivation) {
        Task {
            switch activation {
            case let .override(objectID, presetID, _):
                await state.enactOverridePreset(withID: objectID)

                await MainActor.run {
                    state.hideModal()
                    selectedOverridePresetID = presetID
                    showOverrideCheckmark = true
                    state.shouldDisplayPresetStartConfirmDialog = false
                    pendingPresetActivation = nil
                }

            case let .tempTarget(objectID, presetID, _):
                await state.enactTempTargetPreset(withID: objectID)

                await MainActor.run {
                    selectedTempTargetPresetID = presetID
                    showTempTargetCheckmark = true
                    state.shouldDisplayPresetStartConfirmDialog = false
                    pendingPresetActivation = nil
                }
            }
        }
    }
}

struct ExerciseModeForm: View {
    @Bindable var state: Adjustments.StateModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @State private var targetStep: Decimal = 5
    @State private var displayPreTarget = false
    @State private var displayExerciseTarget = false
    @State private var displayPostTarget = false

    private var isScheduled: Bool {
        state.exerciseStartDate > Date().addingTimeInterval(60)
    }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Exercise")) {
                    Picker("Type", selection: $state.exerciseType) {
                        ForEach(ExerciseType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .onChange(of: state.exerciseType) { _, _ in
                        state.applyExercisePresetForSelectedType()
                    }

                    if state.exerciseType == .custom {
                        TextField("Custom exercise type", text: $state.customExerciseTypeName)
                            .onSubmit {
                                state.applyExercisePresetForSelectedType()
                            }
                    }

                    Picker("Start", selection: $state.scheduleExerciseForFuture) {
                        Text("Start Immediately").tag(false)
                        Text("Schedule for Future").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if state.scheduleExerciseForFuture {
                        DatePicker("Exercise Start Time", selection: $state.exerciseStartDate, in: Date.now...)
                    }

                    Toggle("Use planned duration", isOn: $state.exerciseHasPlannedDuration)
                    if state.exerciseHasPlannedDuration {
                        durationStepper(
                            title: String(localized: "Exercise duration"),
                            value: Binding(
                                get: { Int(state.exerciseDuration) },
                                set: { state.exerciseDuration = Decimal($0) }
                            ),
                            range: 10 ... 720,
                            step: 5
                        )
                    }
                }
                .listRowBackground(Color.chart)

                Section(header: Text("Activity preset")) {
                    Text(
                        "Selecting an activity type loads its saved defaults. Use Save as Preset to reuse the current configuration later."
                    )
                    .foregroundStyle(.secondary)
                    TextField("Preset name", text: $state.exercisePresetName)
                    Button(state.editingExercisePresetID == nil ? "Save as Preset" : "Save Preset Changes") {
                        state.saveCurrentExercisePreset()
                    }
                    Button("Reset Built-in Presets") {
                        ExerciseActivityPresetStore.resetToDefaults()
                        state.exerciseActivityPresets = ExerciseActivityPresetStore.loadPresets()
                        state.applyExercisePresetForSelectedType()
                    }
                }
                .listRowBackground(Color.chart)

                Section(header: Text("Pre-exercise")) {
                    Toggle("Enable pre-exercise phase", isOn: $state.preExerciseEnabled)

                    if state.preExerciseEnabled {
                        durationStepper(
                            title: String(localized: "Starts before activity"),
                            value: Binding(
                                get: { Int(state.preExerciseDuration) },
                                set: { state.preExerciseDuration = Decimal($0) }
                            ),
                            range: 0 ... 120,
                            step: 5
                        )
                        exerciseStrengthStepper(
                            title: String(localized: "Pre-exercise insulin strength"),
                            value: $state.preExerciseBasalPercentage
                        )
                        Toggle("Suppress SMBs", isOn: $state.preExerciseSuppressSMB)
                        targetPicker(
                            label: String(localized: "Target Glucose"),
                            selection: $state.preExerciseTarget,
                            displayPickerTarget: $displayPreTarget
                        )
                    }
                }
                .listRowBackground(Color.chart)

                Section(header: Text("Active exercise")) {
                    exerciseStrengthStepper(
                        title: String(localized: "Exercise insulin strength"),
                        value: $state.exerciseBasalPercentage
                    )
                    Toggle("Suppress SMBs", isOn: $state.exerciseSuppressSMB)
                    targetPicker(
                        label: String(localized: "Target Glucose"),
                        selection: $state.exerciseTarget,
                        displayPickerTarget: $displayExerciseTarget
                    )
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("Exercise announcements"),
                    footer: Text("Announcements only run during active exercise and stop when exercise stops.")
                ) {
                    Toggle("Announce Glucose During Exercise", isOn: $state.announceGlucoseDuringExercise)

                    if state.announceGlucoseDuringExercise {
                        durationStepper(
                            title: String(localized: "Announcement interval"),
                            value: Binding(
                                get: { Int(state.announcementInterval) },
                                set: { state.announcementInterval = Decimal($0) }
                            ),
                            range: 1 ... 60,
                            step: 1
                        )
                        Toggle("Include trend direction", isOn: $state.announcementIncludeTrend)
                        Toggle("Include rate of change", isOn: $state.announcementIncludeRateOfChange)
                        Toggle("Announce urgent changes immediately", isOn: $state.announcementUrgentEnabled)
                        glucoseThresholdStepper(
                            title: String(localized: "Urgent low threshold"),
                            value: $state.announcementLowThreshold,
                            range: 50 ... 100,
                            step: 5
                        )
                        glucoseThresholdStepper(
                            title: String(localized: "Urgent high threshold"),
                            value: $state.announcementHighThreshold,
                            range: 120 ... 300,
                            step: 5
                        )
                    }
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("Post-exercise recovery"),
                    footer: Text(
                        "Recovery is calculated from the actual exercise duration when you stop exercise. Under 10 minutes creates a report without recovery sensitivity."
                    )
                ) {
                    Toggle("Enable recovery phase", isOn: $state.postExerciseEnabled)

                    if state.postExerciseEnabled {
                        Text("Sensitivity uses automatic linear decay based on completed exercise duration.")
                            .foregroundStyle(.secondary)
                        basalStepper(
                            title: String(localized: "Recovery basal rate"),
                            value: $state.postExerciseBasalPercentage
                        )
                        Toggle("Suppress SMBs", isOn: $state.postExerciseSuppressSMB)
                        Toggle("Set recovery target glucose", isOn: $state.postExerciseTargetEnabled)
                        if state.postExerciseTargetEnabled {
                            targetPicker(
                                label: String(localized: "Target Glucose"),
                                selection: $state.postExerciseTarget,
                                displayPickerTarget: $displayPostTarget
                            )
                        }
                    }
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("Guardrails"),
                    footer: Text(state.exerciseGuardrailSettings.mode.summary)
                ) {
                    Toggle("Enable Exercise Guardrails", isOn: $state.exerciseGuardrailSettings.enabled)
                    if state.exerciseGuardrailSettings.enabled {
                        Picker("Mode", selection: $state.exerciseGuardrailSettings.mode) {
                            ForEach(ExerciseGuardrailMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        glucoseThresholdStepper(
                            title: String(localized: "High glucose threshold"),
                            value: $state.exerciseGuardrailSettings.highGlucoseThresholdMgdl,
                            range: 120 ... 360,
                            step: 5
                        )
                        durationStepper(
                            title: String(localized: "Persistence duration"),
                            value: Binding(
                                get: { Int(state.exerciseGuardrailSettings.highGlucosePersistenceMinutes) },
                                set: { state.exerciseGuardrailSettings.highGlucosePersistenceMinutes = Decimal($0) }
                            ),
                            range: 0 ... 60,
                            step: 5
                        )
                        durationStepper(
                            title: String(localized: "Cooldown"),
                            value: Binding(
                                get: { Int(state.exerciseGuardrailSettings.cooldownMinutes) },
                                set: { state.exerciseGuardrailSettings.cooldownMinutes = Decimal($0) }
                            ),
                            range: 0 ... 120,
                            step: 5
                        )
                        Picker("Trend requirement", selection: $state.exerciseGuardrailSettings.trendRequirement) {
                            ForEach(ExerciseGuardrailTrendRequirement.allCases) { requirement in
                                Text(requirement.title).tag(requirement)
                            }
                        }
                        if state.exerciseGuardrailSettings.normalizedMode == .custom {
                            Toggle("Re-enable basal", isOn: $state.exerciseGuardrailSettings.actions.reenableBasal)
                            Toggle("Re-enable SMBs", isOn: $state.exerciseGuardrailSettings.actions.reenableSMB)
                            Toggle(
                                "Cancel exercise override",
                                isOn: $state.exerciseGuardrailSettings.actions.cancelExerciseOverride
                            )
                        }
                        Toggle("Announce warning", isOn: $state.exerciseGuardrailSettings.actions.announceWarning)
                    }
                }
                .listRowBackground(Color.chart)

                Section {
                    Button(action: {
                        Task {
                            let saved = await state.saveExerciseMode()
                            if saved {
                                dismiss()
                            }
                        }
                    }, label: {
                        Text(state.scheduleExerciseForFuture ? "Schedule Exercise Override" : "Start Exercise Override")
                    })
                        .frame(maxWidth: .infinity, alignment: .center)
                        .tint(.white)

                    if let error = state.exerciseModeStartError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .listRowBackground(Color(.systemBlue))
            }
            .listSectionSpacing(10)
            .padding(.top, 30)
            .ignoresSafeArea(edges: .top)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Exercise Override")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                targetStep = state.units == .mgdL ? 5 : 9
                if !state.scheduleExerciseForFuture {
                    state.exerciseStartDate = Date()
                }
                state.applyExercisePresetForSelectedType()
            }
        }
    }

    @ViewBuilder private func durationStepper(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text(state.formatHoursAndMinutes(value.wrappedValue))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func percentStepper(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("+\(value.wrappedValue)%")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func basalStepper(title: String, value: Binding<Double>) -> some View {
        Stepper(
            value: Binding(
                get: { Int(value.wrappedValue) },
                set: { value.wrappedValue = Double($0) }
            ),
            in: 0 ... 100,
            step: 5
        ) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))%")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func exerciseStrengthStepper(title: String, value: Binding<Double>) -> some View {
        Stepper(
            value: Binding(
                get: { Int(value.wrappedValue) },
                set: { value.wrappedValue = Double($0) }
            ),
            in: 0 ... 100,
            step: 25
        ) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))%")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func glucoseThresholdStepper(
        title: String,
        value: Binding<Decimal>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        Stepper(
            value: Binding(
                get: { Int(truncating: value.wrappedValue as NSNumber) },
                set: { value.wrappedValue = Decimal($0) }
            ),
            in: range,
            step: step
        ) {
            HStack {
                Text(title)
                Spacer()
                Text(formattedAnnouncementGlucose(glucose: value.wrappedValue))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formattedAnnouncementGlucose(glucose: Decimal) -> String {
        let formattedValue: String
        if state.units == .mgdL {
            formattedValue = Formatter.glucoseFormatter(for: state.units)
                .string(from: glucose as NSDecimalNumber) ?? "\(glucose)"
        } else {
            formattedValue = glucose.formattedAsMmolL
        }
        return "\(formattedValue) \(state.units.rawValue)"
    }

    @ViewBuilder private func targetPicker(
        label: String,
        selection: Binding<Decimal>,
        displayPickerTarget: Binding<Bool>
    ) -> some View {
        let settingsProvider = PickerSettingsProvider.shared
        let glucoseSetting = PickerSetting(value: 0, step: targetStep, min: 72, max: 270, type: .glucose)

        TargetPicker(
            label: label,
            selection: selection,
            options: settingsProvider.generatePickerValues(
                from: glucoseSetting,
                units: state.units,
                roundMinToStep: true
            ),
            units: state.units,
            targetStep: $targetStep,
            displayPickerTarget: displayPickerTarget,
            toggleScrollWheel: toggleScrollWheel
        )
    }

    private func toggleScrollWheel(_ toggle: Bool) -> Bool {
        displayPreTarget = false
        displayExerciseTarget = false
        displayPostTarget = false
        return !toggle
    }
}

private enum ExercisePhaseConfirmationAction: Identifiable {
    case startExercise
    case stopExercise
    case endRecovery
    case cancelExercise

    var id: String {
        switch self {
        case .startExercise:
            return "startExercise"
        case .stopExercise:
            return "stopExercise"
        case .endRecovery:
            return "endRecovery"
        case .cancelExercise:
            return "cancelExercise"
        }
    }

    var title: String {
        switch self {
        case .startExercise:
            return String(localized: "Start exercise now?")
        case .stopExercise:
            return String(localized: "Stop exercise?")
        case .endRecovery:
            return String(localized: "End recovery?")
        case .cancelExercise:
            return String(localized: "Cancel Exercise Override?")
        }
    }

    var message: String {
        switch self {
        case .startExercise:
            return String(localized: "This will skip the remaining pre-exercise phase and start active exercise immediately.")
        case .stopExercise:
            return String(
                localized: "This will end active exercise now, stop glucose announcements, save an Exercise Report, and start recovery if the completed duration qualifies."
            )
        case .endRecovery:
            return String(
                localized: "This will end recovery now, restore standard Trio behaviour, and keep the Exercise Report saved."
            )
        case .cancelExercise:
            return String(
                localized: "This cancels the current Exercise Override, stops any exercise effects and announcements, and saves a report if exercise had already started."
            )
        }
    }

    var primaryButtonLabel: String {
        switch self {
        case .startExercise:
            return String(localized: "Start Exercise")
        case .stopExercise:
            return String(localized: "Stop Exercise")
        case .endRecovery:
            return String(localized: "End Recovery")
        case .cancelExercise:
            return String(localized: "Cancel Override")
        }
    }

    var primaryButtonRole: ButtonRole? {
        switch self {
        case .startExercise:
            return nil
        case .cancelExercise,
             .endRecovery,
             .stopExercise:
            return .destructive
        }
    }

    func secondaryButtonLabel(sessionState: ExerciseSessionState) -> String {
        switch self {
        case .startExercise:
            return String(localized: "Not Yet")
        case .stopExercise:
            return String(localized: "Continue Running")
        case .endRecovery:
            return String(localized: "Continue Recovery")
        case .cancelExercise:
            if sessionState == .exerciseActive {
                return String(localized: "Continue Running")
            }
            if sessionState == .recoveryActive {
                return String(localized: "Continue Recovery")
            }
            return String(localized: "Keep Override")
        }
    }
}

struct ExercisePhaseStatusView: View {
    let override: OverrideStored
    let formattedTimeRemaining: (TimeInterval) -> String
    let startExerciseNow: () -> Void
    let stopExercise: () -> Void
    let endRecovery: () -> Void
    let cancelExercise: () -> Void
    @State private var pendingConfirmationAction: ExercisePhaseConfirmationAction?
    @State private var showSessionDetail = false

    private var phase: ExercisePhase {
        override.exercisePhase ?? .duringExercise
    }

    private var sessionState: ExerciseSessionState {
        guard let sessionID = override.id,
              let metadata = ExerciseSessionMetadataStore.load(sessionID: sessionID)
        else {
            return override.isActive() ? .exerciseActive : .scheduledPreExercise
        }
        return metadata.state()
    }

    private var phaseColor: Color {
        switch phase {
        case .preExercise:
            return .yellow
        case .duringExercise:
            return .green
        case .postExercise:
            return .teal
        case .inactive:
            return .gray
        }
    }

    private var remainingText: String {
        if sessionState == .scheduledPreExercise {
            guard let start = override.date else { return "scheduled" }
            if start.timeIntervalSinceNow < 60 {
                return "starting shortly"
            }
            return "starts in \(formattedTimeRemaining(start.timeIntervalSinceNow))"
        }

        if phase == .duringExercise {
            let elapsed = abs((override.date ?? Date()).timeIntervalSinceNow)
            return formattedTimeRemaining(elapsed) + " elapsed"
        }

        guard let activeUntil = override.activeUntilDate() else {
            return ""
        }

        return formattedTimeRemaining(activeUntil.timeIntervalSinceNow) + " remaining"
    }

    private var transitionText: String? {
        guard let sessionID = override.id,
              let metadata = ExerciseSessionMetadataStore.load(sessionID: sessionID),
              let scheduledStart = metadata.scheduledExerciseStart,
              sessionState == .scheduledPreExercise || sessionState == .preExerciseActive
        else { return nil }

        if scheduledStart.timeIntervalSinceNow <= 60 {
            return String(localized: "Starting shortly…")
        }
        return String(
            localized: "Exercise starts automatically at \(DateFormatter.localizedString(from: scheduledStart, dateStyle: .none, timeStyle: .short))"
        )
    }

    private var detailText: String {
        var details = ["basal \(Int(override.percentage))%"]
        details.append(override.smbIsOff ? "SMB off" : "SMB allowed")

        let sensitivity = override.effectivePostExerciseSensitivityPercent()
        if sensitivity > 0 {
            details.append("sensitivity +\(Int(truncating: NSDecimalNumber(decimal: sensitivity)))%")
        }

        return details.joined(separator: ", ")
    }

    private var metadata: ExerciseSessionMetadata? {
        guard let sessionID = override.id else { return nil }
        return ExerciseSessionMetadataStore.load(sessionID: sessionID)
    }

    private var guardrailSummaryText: String {
        guard let settings = metadata?.guardrailSettings, settings.enabled else {
            return String(localized: "Guardrails: Off")
        }

        let threshold = formatGlucose(
            settings.highGlucoseThresholdMgdl,
            units: metadata?.announcementSettings.units ?? .mgdL
        )
        let persistence = Int(truncating: NSDecimalNumber(decimal: settings.highGlucosePersistenceMinutes))
        let actionSummary: String
        if settings.normalizedMode == .custom {
            let actions = customGuardrailActions(settings.actions)
            actionSummary = actions.isEmpty ? "" : ", \(actions.joined(separator: ", "))"
        } else {
            actionSummary = ""
        }

        return "\(String(localized: "Guardrails")): \(settings.normalizedMode.title), high >\(threshold) for \(persistence)m\(actionSummary)"
    }

    private var timeoutSummaryText: String {
        String(localized: "Timeout: off")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(OverrideStored.exerciseOverrideName): \(phase.title)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(override.exerciseTypeName ?? String(localized: "Exercise")), \(remainingText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(guardrailSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(timeoutSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let transitionText {
                        Text(transitionText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showSessionDetail = true
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(phaseColor)
                        .frame(width: max(8, progressWidth(totalWidth: geo.size.width)))
                }
            }
            .frame(height: 8)

            if sessionState == .scheduledPreExercise {
                HStack {
                    Spacer()
                    cancelButton
                }
            } else if phase == .preExercise {
                HStack {
                    Button("Start Exercise") { requestConfirmation(.startExercise) }
                    Spacer()
                    cancelButton
                }
            } else if phase == .duringExercise {
                HStack {
                    Button("Stop Exercise") { requestConfirmation(.stopExercise) }
                    Spacer()
                    cancelButton
                }
            } else if phase == .postExercise {
                HStack {
                    Button("End Recovery") { requestConfirmation(.endRecovery) }
                    Spacer()
                    cancelButton
                }
            }
        }
        .buttonStyle(.borderless)
        .confirmationDialog(
            pendingConfirmationAction?.title ?? "",
            isPresented: Binding(
                get: { pendingConfirmationAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingConfirmationAction = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let action = pendingConfirmationAction {
                Button(action.primaryButtonLabel, role: action.primaryButtonRole) {
                    perform(action)
                }
                Button(action.secondaryButtonLabel(sessionState: sessionState), role: .cancel) {
                    pendingConfirmationAction = nil
                }
            }
        } message: {
            Text(pendingConfirmationAction?.message ?? "")
        }
        .sheet(isPresented: $showSessionDetail) {
            ExerciseSessionConfigurationView(
                override: override,
                metadata: metadata,
                formattedTimeRemaining: formattedTimeRemaining,
                requestAction: { requestConfirmation($0) }
            )
        }
    }

    private var cancelButton: some View {
        Button {
            requestConfirmation(.cancelExercise)
        } label: {
            Text("Cancel")
                .foregroundStyle(.red)
        }
    }

    private func requestConfirmation(_ action: ExercisePhaseConfirmationAction) {
        debugPrint(
            "Exercise action dialog requested: action=\(action.id) objectID=\(override.objectID.uriRepresentation().absoluteString)"
        )
        pendingConfirmationAction = action
    }

    private func perform(_ action: ExercisePhaseConfirmationAction) {
        pendingConfirmationAction = nil
        debugPrint(
            "Exercise action confirmed: action=\(action.id) objectID=\(override.objectID.uriRepresentation().absoluteString)"
        )
        switch action {
        case .startExercise:
            startExerciseNow()
        case .stopExercise:
            stopExercise()
        case .endRecovery:
            endRecovery()
        case .cancelExercise:
            cancelExercise()
        }
    }

    private func customGuardrailActions(_ actions: ExerciseGuardrailActions) -> [String] {
        var enabledActions: [String] = []
        if actions.reenableBasal {
            enabledActions.append(String(localized: "re-enable basal"))
        }
        if actions.reenableSMB {
            enabledActions.append(String(localized: "re-enable SMBs"))
        }
        if actions.cancelExerciseOverride {
            enabledActions.append(String(localized: "cancel override"))
        }
        if actions.announceWarning {
            enabledActions.append(String(localized: "announce warning"))
        }
        return enabledActions
    }

    private func progressWidth(totalWidth: CGFloat) -> CGFloat {
        guard let start = override.date,
              let end = override.activeUntilDate()
        else {
            return totalWidth
        }

        let total = end.timeIntervalSince(start)
        guard total > 0 else {
            return totalWidth
        }

        let elapsed = Date().timeIntervalSince(start)
        return totalWidth * CGFloat(max(0, min(1, elapsed / total)))
    }
}

private struct ExerciseSessionConfigurationView: View {
    let override: OverrideStored
    let metadata: ExerciseSessionMetadata?
    let formattedTimeRemaining: (TimeInterval) -> String
    let requestAction: (ExercisePhaseConfirmationAction) -> Void
    @Environment(\.dismiss) private var dismiss

    private var phase: ExercisePhase {
        override.exercisePhase ?? .inactive
    }

    private var sessionState: ExerciseSessionState {
        metadata?.state() ?? (override.isActive() ? .exerciseActive : .scheduledPreExercise)
    }

    var body: some View {
        NavigationView {
            List {
                Section("Session") {
                    row("Activity", override.exerciseTypeName ?? metadata?.exerciseTypeName ?? String(localized: "Exercise"))
                    row("Phase", phase.title)
                    row("State", sessionState.rawValue)
                    row("Created", formattedDate(metadata?.sessionCreatedAt))
                    row("Pre-exercise starts", formattedDate(metadata?.preExerciseStart))
                    row("Exercise starts", formattedDate(metadata?.scheduledExerciseStart))
                    row("Actual start", formattedDate(metadata?.actualExerciseStart))
                    row("Actual stop", formattedDate(metadata?.actualExerciseEnd))
                    row("Recovery ends", formattedDate(metadata?.recoveryEnd))
                }

                Section("Current Effect") {
                    row("Basal", "\(Int(override.percentage))%")
                    row("SMB", override.smbIsOff ? String(localized: "Suppressed") : String(localized: "Allowed"))
                    row("Target", targetText())
                    row("Sensitivity", sensitivityText(override.effectivePostExerciseSensitivityPercent()))
                }

                if let settings = metadata?.preExerciseSettings {
                    Section("Pre-exercise Settings") {
                        phaseRows(settings)
                    }
                }

                if let settings = metadata?.exerciseSettings {
                    Section("Active Exercise Settings") {
                        phaseRows(settings)
                    }
                }

                Section("Recovery Settings") {
                    row("Enabled", boolText(metadata?.postExerciseEnabled ?? false))
                    row("Basal", "\(Int(metadata?.postExerciseBasalPercentage ?? 100))%")
                    row(
                        "SMB",
                        (metadata?.postExerciseSuppressSMB ?? false) ? String(localized: "Suppressed") :
                            String(localized: "Allowed")
                    )
                    row("Target", recoveryTargetText())
                }

                Section("Announcements") {
                    let settings = metadata?.announcementSettings ?? ExerciseAnnouncementSettings()
                    row("Enabled", boolText(settings.enabled))
                    row("Interval", "\(Int(truncating: NSDecimalNumber(decimal: settings.intervalMinutes)))m")
                    row("Trend", boolText(settings.includeTrend))
                    row("Rate of change", boolText(settings.includeRateOfChange))
                    row("Urgent", boolText(settings.urgentAnnouncementsEnabled))
                }

                Section("Guardrails") {
                    guardrailRows(metadata?.guardrailSettings ?? ExerciseGuardrailSettings())
                }

                Section("Timeout Guardrail") {
                    row("Timeout", String(localized: "Off"))
                }

                Section {
                    phaseActionButtons
                    Button("Cancel") {
                        dismiss()
                        requestAction(.cancelExercise)
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Exercise Override")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder private var phaseActionButtons: some View {
        if sessionState == .preExerciseActive || phase == .preExercise {
            Button("Start Exercise") {
                dismiss()
                requestAction(.startExercise)
            }
        } else if sessionState == .exerciseActive || phase == .duringExercise {
            Button("Stop Exercise") {
                dismiss()
                requestAction(.stopExercise)
            }
        } else if sessionState == .recoveryActive || phase == .postExercise {
            Button("End Recovery") {
                dismiss()
                requestAction(.endRecovery)
            }
        }
    }

    @ViewBuilder private func phaseRows(_ settings: ExerciseSessionMetadata.PhaseSettings) -> some View {
        row("Basal", "\(Int(settings.basalPercentage))%")
        row("SMB", settings.suppressSMB ? String(localized: "Suppressed") : String(localized: "Allowed"))
        row("Target", formatGlucose(settings.target, units: metadata?.announcementSettings.units ?? .mgdL))
    }

    @ViewBuilder private func guardrailRows(_ settings: ExerciseGuardrailSettings) -> some View {
        row("Enabled", boolText(settings.enabled))
        row("Mode", settings.normalizedMode.title)
        row(
            "High threshold",
            formatGlucose(settings.highGlucoseThresholdMgdl, units: metadata?.announcementSettings.units ?? .mgdL)
        )
        row("Persistence", "\(Int(truncating: NSDecimalNumber(decimal: settings.highGlucosePersistenceMinutes)))m")
        row("Trend", settings.trendRequirement.title)
        row("Cooldown", "\(Int(truncating: NSDecimalNumber(decimal: settings.cooldownMinutes)))m")
        row("Re-enable basal", boolText(settings.actions.reenableBasal))
        row("Re-enable SMBs", boolText(settings.actions.reenableSMB))
        row("Cancel override", boolText(settings.actions.cancelExerciseOverride))
        row("Announce warning", boolText(settings.actions.announceWarning))
    }

    @ViewBuilder private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return String(localized: "Not set") }
        return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }

    private func boolText(_ value: Bool) -> String {
        value ? String(localized: "On") : String(localized: "Off")
    }

    private func targetText() -> String {
        if phase == .postExercise, metadata?.postExerciseTargetEnabled != true {
            return String(localized: "Profile target")
        }
        return formatGlucose(override.target?.decimalValue ?? 108, units: metadata?.announcementSettings.units ?? .mgdL)
    }

    private func recoveryTargetText() -> String {
        guard metadata?.postExerciseTargetEnabled == true else {
            return String(localized: "Profile target")
        }
        return formatGlucose(metadata?.postExerciseTarget ?? 108, units: metadata?.announcementSettings.units ?? .mgdL)
    }

    private func sensitivityText(_ value: Decimal) -> String {
        guard value > 0 else { return String(localized: "Normal") }
        return "+\(Int(truncating: NSDecimalNumber(decimal: value)))%"
    }
}

private func formatGlucose(_ rawMgdl: Decimal, units: GlucoseUnits) -> String {
    if units == .mgdL {
        let formatted = Formatter.glucoseFormatter(for: units)
            .string(from: rawMgdl as NSDecimalNumber) ?? "\(rawMgdl)"
        return "\(formatted) \(units.rawValue)"
    }
    return "\(rawMgdl.formattedAsMmolL) \(units.rawValue)"
}

struct ExerciseReportsListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reports: [ExerciseReport] = []

    var body: some View {
        NavigationStack {
            List {
                if reports.isEmpty {
                    Text("No exercise reports yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(reports) { report in
                        NavigationLink {
                            ExerciseReportDetailView(report: report)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(report.exerciseType)
                                    .font(.headline)
                                Text(report.exerciseStopTime, style: .date)
                                    +
                                    Text(" ")
                                    +
                                    Text(report.exerciseStopTime, style: .time)
                                Text(
                                    "\(Int(truncating: NSDecimalNumber(decimal: report.actualExerciseDurationMinutes))) min, recovery \(report.recoveryDurationCalculatedMinutes / 60)h, sensitivity +\(Int(truncating: NSDecimalNumber(decimal: report.recoverySensitivityAdjustmentCalculated)))%"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Exercise Reports")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                reports = ExerciseReportStore.loadReports()
            }
        }
    }
}

struct ExerciseReportDetailView: View {
    let report: ExerciseReport
    @State private var jsonURL: URL?
    @State private var csvURL: URL?

    var body: some View {
        List {
            Section("Session") {
                row("Type", report.exerciseType)
                row("Pre-exercise start", report.preExerciseStartTime.map(formatDate) ?? "None")
                row("Exercise start", formatDate(report.exerciseStartTime))
                row("Exercise stop", formatDate(report.exerciseStopTime))
                row("Duration", "\(Int(truncating: NSDecimalNumber(decimal: report.actualExerciseDurationMinutes))) min")
                row("Started early", report.startedEarly ? "Yes" : "No")
                row("Cancelled / no recovery", report.wasCancelled ? "Yes" : "No")
            }

            Section("Recovery") {
                row("Recommended duration", "\(report.recoveryDurationCalculatedMinutes) min")
                row("Sensitivity", "+\(report.recoverySensitivityAdjustmentCalculated)%")
                row("Decay", report.decayModelUsed.title)
                if let actualRecoveryEndTime = report.actualRecoveryEndTime {
                    row("Actual recovery ended", formatDate(actualRecoveryEndTime))
                    row("Actual recovery duration", "\(actualRecoveryDurationMinutes(endedAt: actualRecoveryEndTime)) min")
                }
                if let recoverySkippedReason = report.recoverySkippedReason {
                    row("Skipped reason", recoverySkippedReason)
                }
            }

            Section("Glucose") {
                row(
                    "BG at pre start",
                    glucoseValue(report.glucoseStats.bgAtPreExerciseStartDisplay, raw: report.glucoseStats.bgAtPreExerciseStart)
                )
                row(
                    "BG at exercise start",
                    glucoseValue(report.glucoseStats.bgAtExerciseStartDisplay, raw: report.glucoseStats.bgAtExerciseStart)
                )
                row(
                    "BG at exercise end",
                    glucoseValue(report.glucoseStats.bgAtExerciseEndDisplay, raw: report.glucoseStats.bgAtExerciseEnd)
                )
                row(
                    "Min during exercise",
                    glucoseValue(report.glucoseStats.minBGDuringExerciseDisplay, raw: report.glucoseStats.minBGDuringExercise)
                )
                row(
                    "Max during exercise",
                    glucoseValue(report.glucoseStats.maxBGDuringExerciseDisplay, raw: report.glucoseStats.maxBGDuringExercise)
                )
                row("Average during exercise", glucoseValue(report.glucoseStats.averageBGDuringExerciseDisplay, raw: nil))
                row("Trend before", report.glucoseStats.glucoseTrendBeforeExercise.map { "\($0)" } ?? "Unavailable")
                row("Trend after", report.glucoseStats.glucoseTrendAfterExercise.map { "\($0)" } ?? "Unavailable")
            }

            Section("Insulin") {
                row("IOB at pre start", optionalDecimal(report.insulinStats.iobAtPreExerciseStart))
                row("IOB at exercise start", optionalDecimal(report.insulinStats.iobAtExerciseStart))
                row("IOB at exercise end", optionalDecimal(report.insulinStats.iobAtExerciseEnd))
                row("Boluses during session", optionalDecimal(report.insulinStats.bolusesDeliveredDuringSession))
                row("Pre SMB", report.insulinStats.preExerciseSMBSuppressed ? "Suppressed" : "Allowed")
                row("Exercise SMB", report.insulinStats.exerciseSMBSuppressed ? "Suppressed" : "Allowed")
                row("Recovery SMB", report.insulinStats.recoverySMBSuppressed ? "Suppressed" : "Allowed")
            }

            Section("Announcements") {
                row("Enabled", report.announcementStats.announceGlucoseEnabled ? "Yes" : "No")
                row("Interval", "\(report.announcementStats.announcementInterval) min")
                row("Trend", report.announcementStats.includeTrend ? "Included" : "Off")
                row("Rate of change", report.announcementStats.includeRateOfChange ? "Included" : "Off")
                row("Urgent", report.announcementStats.urgentAnnouncementsEnabled ? "Enabled" : "Off")
                row("Announcements made", "\(report.announcementStats.numberOfAnnouncementsMade)")
            }

            if let guardrailSummary = report.guardrailSummary {
                Section("Guardrails") {
                    row("Mode", guardrailSummary.settings.mode.title)
                    row("High threshold", glucoseValue(
                        ExerciseReport.GlucoseValue(
                            rawMgdl: Int(truncating: NSDecimalNumber(
                                decimal: guardrailSummary.settings
                                    .highGlucoseThresholdMgdl
                            )),
                            displayValue: nil,
                            displayUnits: ""
                        ),
                        raw: Int(truncating: NSDecimalNumber(decimal: guardrailSummary.settings.highGlucoseThresholdMgdl))
                    ))
                    row("Events", "\(guardrailSummary.events.count)")
                }
            }

            Section("Export") {
                if let jsonURL {
                    ShareLink(item: jsonURL) {
                        Label("Export JSON", systemImage: "square.and.arrow.up")
                    }
                }
                if let csvURL {
                    ShareLink(item: csvURL) {
                        Label("Export CSV", systemImage: "tablecells")
                    }
                }
            }
        }
        .navigationTitle(report.exerciseType)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            jsonURL = try? ExerciseReportStore.exportURL(for: report)
            csvURL = try? ExerciseReportStore.csvURL(for: report)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func glucoseValue(_ value: ExerciseReport.GlucoseValue?, raw: Int?) -> String {
        if let value, let displayValue = value.displayValue {
            let formatted: String
            if value.displayUnits == GlucoseUnits.mmolL.rawValue {
                formatted = displayValue.formattedAsMmolL
            } else {
                formatted = Formatter.glucoseFormatter(for: .mgdL)
                    .string(from: displayValue as NSDecimalNumber) ?? "\(displayValue)"
            }
            return "\(formatted) \(value.displayUnits)"
        }
        return raw.map { "\($0) \(GlucoseUnits.mgdL.rawValue)" } ?? "Unavailable"
    }

    private func optionalDecimal(_ value: Decimal?) -> String {
        value.map { "\($0)" } ?? "Unavailable"
    }

    private func formatDate(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    private func actualRecoveryDurationMinutes(endedAt endTime: Date) -> Int {
        max(0, Int(endTime.timeIntervalSince(report.exerciseStopTime) / 60))
    }
}
