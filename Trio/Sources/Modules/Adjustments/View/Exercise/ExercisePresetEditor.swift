import SwiftUI

struct ExercisePresetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var preset: ExercisePreset
    let save: (ExercisePreset) -> Void

    init(preset: ExercisePreset, save: @escaping (ExercisePreset) -> Void) {
        _preset = State(initialValue: preset)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $preset.name)
                Section("Pre Exercise") {
                    Stepper(
                        "Duration: \(preset.preExerciseDurationMinutes) min",
                        value: $preset.preExerciseDurationMinutes,
                        in: 0 ... 180,
                        step: 5
                    )
                    ExercisePhaseSettingsEditor(settings: $preset.preExercise)
                }
                Section("Active Exercise") {
                    ExercisePhaseSettingsEditor(settings: $preset.active)
                    Stepper(
                        "Safety timeout: \(preset.safetyTimeoutMinutes ?? 0) min",
                        value: timeoutBinding,
                        in: 0 ... 1440,
                        step: 15
                    )
                }
                Section("Recovery") {
                    Toggle("Enabled", isOn: $preset.recovery.enabled)
                    Stepper(
                        "Initial sensitivity increase: \(preset.recovery.initialSensitivityIncreasePercentage.formatted())%",
                        value: $preset.recovery.initialSensitivityIncreasePercentage,
                        in: 0 ... 100,
                        step: 5
                    )
                    OptionalExerciseTargetEditor(target: $preset.recovery.target)
                }
                Section("Audio announcements") {
                    Toggle("Announce glucose and trend", isOn: $preset.announcementsEnabled)
                    Picker("Repeat", selection: $preset.announcementIntervalMinutes) {
                        ForEach([2, 3, 4, 5], id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                }
            }
            .navigationTitle("Exercise Preset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(preset)
                        dismiss() }.disabled(preset.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var timeoutBinding: Binding<Int> {
        Binding(get: { preset.safetyTimeoutMinutes ?? 0 }, set: { preset.safetyTimeoutMinutes = $0 == 0 ? nil : $0 })
    }
}

private struct ExercisePhaseSettingsEditor: View {
    @Binding var settings: ExercisePhaseSettings
    var body: some View {
        Stepper("Basal: \(settings.basalPercentage.formatted())%", value: $settings.basalPercentage, in: 0 ... 200, step: 5)
        Toggle("SMB enabled", isOn: $settings.smbEnabled)
        Picker("Correction strength", selection: $settings.insulinStrengthPercentage) {
            ForEach([0, 25, 50, 75, 100], id: \.self) { Text("\($0)%").tag(Decimal($0)) }
        }
        OptionalExerciseTargetEditor(target: $settings.target)
    }
}

private struct OptionalExerciseTargetEditor: View {
    @Binding var target: Decimal?
    var body: some View {
        Toggle("Custom target", isOn: Binding(get: { target != nil }, set: { target = $0 ? (target ?? 110) : nil }))
        if target != nil {
            Stepper(
                "Target: \((target ?? 110).formatted()) mg/dL",
                value: Binding(get: { target ?? 110 }, set: { target = $0 }),
                in: 70 ... 250,
                step: 5
            )
        }
    }
}
