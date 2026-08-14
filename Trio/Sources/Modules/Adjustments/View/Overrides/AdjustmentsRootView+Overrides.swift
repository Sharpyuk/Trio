import CoreData
import SwiftUI

extension Adjustments.RootView {
    @ViewBuilder func overrides() -> some View {
        if state.isOverrideEnabled,
           state.activeOverrideName.isNotEmpty,
           state.currentActiveOverride?.isExerciseMode != true
        {
            currentActiveAdjustment
        }
        if state.scheduledExerciseOverrides.isNotEmpty {
            scheduledExerciseModes
        }
        activeProteinFatAssistAdjustments
        if state.exerciseActivityPresets.isNotEmpty {
            exerciseOverridePresets
        }
        if state.overridePresets.isNotEmpty {
            overridePresets
        } else if state.exerciseActivityPresets.isEmpty {
            defaultText
        }
    }

    var scheduledExerciseModes: some View {
        Section {
            ForEach(state.scheduledExerciseOverrides) { exerciseOverride in
                ExercisePhaseStatusView(
                    override: exerciseOverride,
                    formattedTimeRemaining: formattedTimeRemaining,
                    startExerciseNow: {
                        Task {
                            await state.startExerciseNow(exerciseOverride.objectID)
                        }
                    },
                    stopExercise: {
                        Task {
                            await state.stopExerciseNow(exerciseOverride.objectID)
                        }
                    },
                    endRecovery: {
                        Task {
                            await state.endExerciseRecovery(exerciseOverride.objectID)
                        }
                    },
                    cancelExercise: {
                        Task {
                            await state.cancelScheduledExerciseOverride(exerciseOverride.objectID)
                        }
                    }
                )
            }
            .listRowBackground(Color.chart)
        } header: {
            Text("Exercise Override")
        }
    }

    var exerciseOverridePresets: some View {
        Section {
            ForEach(state.exerciseActivityPresets) { preset in
                Button {
                    state.applyExerciseActivityPreset(preset)
                    showExerciseModeCreationSheet = true
                } label: {
                    HStack {
                        Image(systemName: preset.icon)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.activityTypeName)
                                .foregroundStyle(.primary)
                            Text(exercisePresetSummary(preset))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .contextMenu {
                    exercisePresetActions(for: preset)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    exercisePresetActions(for: preset)
                }
            }
            .listRowBackground(Color.chart)
        } header: {
            Text("Exercise Override Presets")
        } footer: {
            Text("Tap a saved exercise preset to review its settings, then start immediately or schedule it for later.")
        }
    }

    var overridePresets: some View {
        Section {
            ForEach(state.overridePresets) { preset in
                overridesView(for: preset, showCheckMark: showOverrideCheckmark) {
                    requestOverridePresetActivation(preset)
                }
                .contextMenu {
                    actionButtonsForOverrides(for: preset)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    actionButtonsForOverrides(for: preset)
                }
            }
            .onMove(perform: state.reorderOverride)
            .confirmationDialog(
                "Delete the Override Preset \"\(selectedOverride?.name ?? "")\"?",
                isPresented: $isConfirmDeletePresented,
                titleVisibility: .visible
            ) {
                if let itemToDelete = selectedOverride {
                    Button(
                        state.currentActiveOverride == selectedOverride ? "Stop and Delete" : "Delete",
                        role: .destructive
                    ) {
                        if state.currentActiveOverride == selectedOverride {
                            Task {
                                // Save cancelled Override in OverrideRunStored Entity
                                // Cancel ALL active Override
                                await state.disableAllActiveOverrides(createOverrideRunEntry: true)
                            }
                        }
                        // Perform the delete action
                        Task {
                            await state.invokeOverridePresetDeletion(itemToDelete.objectID)
                        }
                        // Reset the selected item after deletion
                        selectedOverride = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    // Dismiss the dialog without action
                    selectedOverride = nil
                }
            } message: {
                if state.currentActiveOverride == selectedOverride {
                    Text(
                        state
                            .currentActiveOverride == selectedOverride ?
                            "This override preset is currently running. Deleting will stop it." : ""
                    )
                }
            }
            .listRowBackground(Color.chart)
        } header: {
            Text("Override Presets")
        } footer: {
            HStack {
                Image(systemName: "hand.draw.fill").foregroundStyle(.primary)
                Text("Swipe left to edit or delete an override preset. Hold, drag and drop to reorder a preset.")
            }
        }
    }

    @ViewBuilder private func exercisePresetActions(for preset: ExerciseActivityPreset) -> some View {
        let isBuiltIn = ExerciseActivityPresetStore.builtInPresets.contains { $0.id == preset.id }
        Button {
            state.applyExerciseActivityPreset(preset, editing: true)
            showExerciseModeCreationSheet = true
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        if !isBuiltIn {
            Button(role: .destructive) {
                state.deleteExerciseActivityPreset(preset)
            } label: {
                Label("Delete", systemImage: "trash.fill")
            }
        }
    }

    private func exercisePresetSummary(_ preset: ExerciseActivityPreset) -> String {
        var labels = [
            "pre \(Int(truncating: NSDecimalNumber(decimal: preset.preExerciseDuration)))m",
            "strength \(Int(preset.exerciseBasalPercent))%",
            preset.exerciseSMBSuppressed ? "SMB off" : "SMB allowed",
            preset.announceGlucoseEnabled ? "announce on" : "announce off"
        ]

        if preset.guardrailSettings.enabled {
            labels.append("guardrails \(preset.guardrailSettings.normalizedMode.title.lowercased())")
        } else {
            labels.append("guardrails off")
        }
        labels.append("timeout off")
        return labels.joined(separator: ", ")
    }

    private func requestOverridePresetActivation(_ preset: OverrideStored) {
        let activation = PendingPresetActivation.override(
            objectID: preset.objectID,
            presetID: preset.id,
            name: preset.name ?? ""
        )

        requestPresetActivation(activation)
    }

    func actionButtonsForOverrides(for preset: OverrideStored) -> some View {
        Group {
            Button(role: .destructive) {
                selectedOverride = preset
                isConfirmDeletePresented = true
            } label: {
                Label("Delete", systemImage: "trash.fill")
                    .tint(.red)
            }
            Button(action: {
                // Set the selected Override to the chosen Preset and pass it to the Edit Sheet
                selectedOverride = preset
                state.showOverrideEditSheet = true
            }, label: {
                Label("Edit", systemImage: "pencil")
                    .tint(.blue)
            })
        }
    }

    var overrideLabelDivider: some View {
        Divider()
            .frame(width: 1, height: 20)
    }

    var stickyStopOverrideButton: some View {
        ZStack {
            Rectangle()
                .frame(width: UIScreen.main.bounds.width, height: 65)
                .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                .background(.thinMaterial)
                .opacity(0.8)
                .clipShape(Rectangle())

            Button(action: {
                showCancelOverrideConfirmDialog = true
            }, label: {
                Text("Stop Override")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(10)
            })
                .frame(width: UIScreen.main.bounds.width * 0.9, height: 40, alignment: .center)
                .disabled(!state.isOverrideEnabled)
                .background(!state.isOverrideEnabled ? Color(.systemGray4) : Color(.systemRed))
                .tint(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                .padding(5)
        }
    }

    @ViewBuilder func overridesView(
        for preset: OverrideStored,
        showCheckMark _: Bool = false,
        onTap: (() -> Void)? = nil
    ) -> some View {
        let isSelected = preset.id == selectedOverridePresetID
        let name = preset.name ?? ""
        let indefinite = preset.indefinite
        let duration = preset.duration?.decimalValue ?? Decimal(0)
        let percentage = preset.percentage
        let smbMinutes = preset.smbMinutes?.decimalValue ?? Decimal(0)
        let uamMinutes = preset.uamMinutes?.decimalValue ?? Decimal(0)

        let target: String = {
            guard let targetValue = preset.target, targetValue != 0 else { return "" }
            return state.units == .mgdL ? targetValue.description : targetValue.decimalValue.formattedAsMmolL
        }()

        let targetString = target.isEmpty ? "" : "\(target) \(state.units.rawValue)"

        let durationString = indefinite ? "" : "\(state.formatHoursAndMinutes(Int(duration)))"

        let scheduledSMBString: String = {
            guard preset.smbIsScheduledOff, preset.start != preset.end else { return "" }
            return " \(formatTimeRange(start: preset.start?.stringValue, end: preset.end?.stringValue))"
        }()

        let smbString: String = {
            guard preset.smbIsOff || preset.smbIsScheduledOff else { return "" }
            return "SMBs Off\(scheduledSMBString)"
        }()

        let maxSmbMinsString: String = {
            guard smbMinutes != 0, preset.advancedSettings, !preset.smbIsOff,
                  smbMinutes != state.defaultSmbMinutes else { return "" }
            return "\(smbMinutes.formatted()) min SMB"
        }()

        let maxUamMinsString: String = {
            guard uamMinutes != 0, preset.advancedSettings, !preset.smbIsOff,
                  uamMinutes != state.defaultUamMinutes else { return "" }
            return "\(uamMinutes.formatted()) min UAM"
        }()

        let isfAndCrString: String = {
            switch (preset.isfAndCr, preset.isf, preset.cr) {
            case (_, true, true),
                 (true, _, _):
                return " ISF/CR"
            case (false, true, false):
                return " ISF"
            case (false, false, true):
                return " CR"
            default:
                return ""
            }
        }()

        let percentageString = percentage != 100 ? "\(Int(percentage))%\(isfAndCrString)" : ""

        // Combine all labels into a single array, filtering out empty strings
        let labels: [String] = [
            durationString,
            percentageString,
            targetString,
            smbString,
            maxSmbMinsString,
            maxUamMinsString
        ].filter { !$0.isEmpty }

        if !name.isEmpty {
            ZStack(alignment: .trailing) {
                HStack {
                    VStack {
                        HStack {
                            Text(name)
                            Spacer()
                        }
                        HStack(spacing: 5) {
                            ForEach(labels, id: \.self) { label in
                                Text(label)
                                if label != labels.last { // Add divider between labels
                                    overrideLabelDivider
                                }
                            }
                            Spacer()
                        }
                        .padding(.top, 2)
                        .foregroundColor(.secondary)
                        .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap?()
                    }
                }
                // show checkmark to indicate if the preset was actually pressed
                if showOverrideCheckmark && isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.large)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.green)
                } else {
                    Image(systemName: "line.3.horizontal")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
