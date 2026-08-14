import SwiftUI

struct ExerciseScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var coordinator: ExerciseCoordinator
    @State private var selectedPresetID: UUID
    @State private var activeStart = Date()

    init(coordinator: ExerciseCoordinator) {
        self.coordinator = coordinator
        _selectedPresetID = State(initialValue: coordinator.presets.first?.id ?? ExercisePreset.defaults[0].id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Preset", selection: $selectedPresetID) {
                    ForEach(coordinator.presets) { Text($0.name).tag($0.id) }
                }
                DatePicker("Active Exercise starts", selection: $activeStart)
                if let preset = coordinator.presets.first(where: { $0.id == selectedPresetID }) {
                    Section("Plan") {
                        LabeledContent("Pre Exercise", value: "\(preset.preExerciseDurationMinutes) min")
                        LabeledContent("Active basal", value: "\(preset.active.basalPercentage.formatted())%")
                        LabeledContent("Correction strength", value: "\(preset.active.insulinStrengthPercentage.formatted())%")
                    }
                }
            }
            .navigationTitle("Schedule Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") {
                        guard let preset = coordinator.presets.first(where: { $0.id == selectedPresetID }) else { return }
                        coordinator.schedule(preset: preset, activeStart: activeStart)
                        dismiss()
                    }
                }
            }
        }
    }
}
