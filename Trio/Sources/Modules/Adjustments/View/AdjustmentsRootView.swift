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

        private var shouldDisplayStickyOverrideStopButton: Bool {
            state.isOverrideEnabled && state.activeOverrideName.isNotEmpty
        }

        private var shouldDisplayStickyTempTargetStopButton: Bool {
            state.isTempTargetEnabled && state.activeTempTargetName.isNotEmpty
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

                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showOverrideCheckmark = false
                }

            case let .tempTarget(objectID, presetID, _):
                await state.enactTempTargetPreset(withID: objectID)

                await MainActor.run {
                    selectedTempTargetPresetID = presetID
                    showTempTargetCheckmark = true
                    state.shouldDisplayPresetStartConfirmDialog = false
                    pendingPresetActivation = nil
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showTempTargetCheckmark = false
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

                    if state.exerciseType == .custom {
                        TextField("Custom exercise type", text: $state.customExerciseTypeName)
                    }

                    DatePicker("Override Start Time", selection: $state.exerciseStartDate, in: Date.now...)
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
                            step: 30
                        )
                        basalStepper(
                            title: String(localized: "Basal Rate"),
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
                    basalStepper(
                        title: String(localized: "Basal Rate"),
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
                            title: String(localized: "Basal Rate"),
                            value: $state.postExerciseBasalPercentage
                        )
                        Toggle("Suppress SMBs", isOn: $state.postExerciseSuppressSMB)
                        targetPicker(
                            label: String(localized: "Target Glucose"),
                            selection: $state.postExerciseTarget,
                            displayPickerTarget: $displayPostTarget
                        )
                    }
                }
                .listRowBackground(Color.chart)

                Section {
                    Button(action: {
                        Task {
                            await state.saveExerciseMode()
                            dismiss()
                        }
                    }, label: {
                        Text(isScheduled ? "Schedule Exercise Override" : "Start Exercise Override")
                    })
                        .frame(maxWidth: .infinity, alignment: .center)
                        .tint(.white)
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
                state.exerciseStartDate = Date()
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

struct ExercisePhaseStatusView: View {
    let override: OverrideStored
    let formattedTimeRemaining: (TimeInterval) -> String
    let startExerciseNow: () -> Void
    let stopExercise: () -> Void
    @State private var confirmStopExercise = false

    private var phase: ExercisePhase {
        override.exercisePhase ?? .duringExercise
    }

    private var phaseColor: Color {
        switch phase {
        case .preExercise:
            return .yellow
        case .duringExercise:
            return .purple
        case .postExercise:
            return .green
        case .inactive:
            return .gray
        }
    }

    private var remainingText: String {
        if phase == .duringExercise {
            let elapsed = abs((override.date ?? Date()).timeIntervalSinceNow)
            return formattedTimeRemaining(elapsed) + " elapsed"
        }

        guard let activeUntil = override.activeUntilDate() else {
            return ""
        }

        return formattedTimeRemaining(activeUntil.timeIntervalSinceNow) + " remaining"
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
                }
                Spacer()
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

            if phase == .preExercise {
                Button {
                    startExerciseNow()
                } label: {
                    Label("Start Exercise Now", systemImage: "figure.run")
                }
                .buttonStyle(.borderless)
            } else if phase == .duringExercise {
                Button(role: .destructive) {
                    confirmStopExercise = true
                } label: {
                    Label("Stop Exercise", systemImage: "stop.circle")
                }
                .buttonStyle(.borderless)
                .confirmationDialog("Stop exercise and start recovery now?", isPresented: $confirmStopExercise) {
                    Button("Stop Exercise", role: .destructive, action: stopExercise)
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
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
                row("Duration", "\(report.recoveryDurationCalculatedMinutes) min")
                row("Sensitivity", "+\(report.recoverySensitivityAdjustmentCalculated)%")
                row("Decay", report.decayModelUsed.title)
            }

            Section("Glucose") {
                row("BG at pre start", optionalInt(report.glucoseStats.bgAtPreExerciseStart))
                row("BG at exercise start", optionalInt(report.glucoseStats.bgAtExerciseStart))
                row("BG at exercise end", optionalInt(report.glucoseStats.bgAtExerciseEnd))
                row("Min during exercise", optionalInt(report.glucoseStats.minBGDuringExercise))
                row("Max during exercise", optionalInt(report.glucoseStats.maxBGDuringExercise))
                row("Average during exercise", report.glucoseStats.averageBGDuringExercise.map { "\($0)" } ?? "Unavailable")
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

    private func optionalInt(_ value: Int?) -> String {
        value.map(String.init) ?? "Unavailable"
    }

    private func optionalDecimal(_ value: Decimal?) -> String {
        value.map { "\($0)" } ?? "Unavailable"
    }

    private func formatDate(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}
