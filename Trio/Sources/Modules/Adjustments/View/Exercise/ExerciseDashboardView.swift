import SwiftUI

struct ExerciseHomeBadge: View {
    @Bindable var coordinator: ExerciseCoordinator
    var body: some View {
        if let session = coordinator.activeSession {
            let phase = session.phase(at: Date())
            Label(label(for: phase), systemImage: "figure.run")
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(color(for: phase).opacity(0.85)))
        }
    }

    private func label(for phase: ExercisePhase) -> String {
        switch phase {
        case .scheduled: "Exercise scheduled"
        case .preExercise: "Pre Exercise"
        case .active: "Exercise active"
        case .recovery: "Exercise recovery"
        case .completed, .cancelled: ""
        }
    }

    private func color(for phase: ExercisePhase) -> Color {
        switch phase {
        case .preExercise: .yellow
        case .active: .purple
        case .recovery: .teal
        default: .secondary
        }
    }
}

struct ExerciseDashboardView: View {
    @Bindable var coordinator: ExerciseCoordinator
    @State private var showSchedule = false
    @State private var presetToEdit: ExercisePreset?
    @State private var now = Date()

    var body: some View {
        if let session = coordinator.activeSession {
            ExerciseStatusSection(session: session, now: now)
            ExerciseActionsSection(coordinator: coordinator, session: session, now: now)
        } else {
            Section {
                Button("Schedule Exercise") { showSchedule = true }
                    .frame(maxWidth: .infinity)
                Button("Start Exercise Now") { coordinator.startNow() }
                    .frame(maxWidth: .infinity)
            } header: {
                Text("Exercise Mode")
            } footer: {
                Text("Correction strength reduces the total positive correction requirement before SMB and temp basal are calculated.")
            }
        }

        Section("Presets") {
            ForEach(coordinator.presets) { preset in
                Button {
                    presetToEdit = preset
                } label: {
                    HStack {
                        Text(preset.name).foregroundStyle(.primary)
                        Spacer()
                        Text("\(preset.active.insulinStrengthPercentage.formatted())% correction")
                            .font(.caption).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        if coordinator.history.isNotEmpty {
            Section("Recent Exercise") {
                ForEach(coordinator.history.prefix(20)) { session in
                    ExerciseHistoryRow(session: session)
                }
            }
        }

        if coordinator.reports.isNotEmpty {
            Section("Reports") {
                ForEach(coordinator.reports.prefix(20)) { report in
                    NavigationLink(report.type) { ExerciseReportView(report: report) }
                }
            }
        }

        TimelineView(.periodic(from: .now, by: 30)) { context in
            Color.clear.frame(height: 0).onChange(of: context.date, initial: true) { _, value in
                now = value
                coordinator.reconcile(at: value)
            }
        }
        .listRowInsets(EdgeInsets()).frame(height: 0)
        .sheet(isPresented: $showSchedule) {
            ExerciseScheduleSheet(coordinator: coordinator)
        }
        .sheet(item: $presetToEdit) { preset in
            ExercisePresetEditor(preset: preset) { coordinator.savePreset($0) }
        }
    }
}

private struct ExerciseReportView: View {
    let report: ExerciseReport
    var body: some View {
        List {
            LabeledContent("Planned start", value: report.plannedStart.formatted())
            LabeledContent("Actual start", value: report.actualStart?.formatted() ?? "Not recorded")
            LabeledContent("Actual end", value: report.actualEnd?.formatted() ?? "Not recorded")
            LabeledContent("BG start / end", value: "\(report.bgStart.map(String.init) ?? "—") / \(report.bgEnd.map(String.init) ?? "—")")
            LabeledContent("BG min / max", value: "\(report.bgMinimum.map(String.init) ?? "—") / \(report.bgMaximum.map(String.init) ?? "—")")
            LabeledContent("IOB start / end", value: "\(report.iobStart?.formatted() ?? "—") / \(report.iobEnd?.formatted() ?? "—") U")
            LabeledContent("Insulin delivered", value: "\(report.insulinDelivered?.formatted() ?? "—") U")
            LabeledContent("SMB delivered", value: "\(report.smbDelivered.formatted()) U")
            LabeledContent("Temp basal", value: report.tempBasalSummary)
            LabeledContent("Basal", value: "\(report.basalPercentage.formatted())%")
            LabeledContent("Correction strength", value: "\(report.insulinStrengthPercentage.formatted())%")
            LabeledContent("Target", value: report.target?.formatted() ?? "Trio default")
            LabeledContent("Audio", value: report.announcementsEnabled ? "Every \(report.announcementIntervalMinutes) min" : "Off")
            ShareLink(item: exportText, subject: Text("Exercise report")) {
                Label("Export Report", systemImage: "square.and.arrow.up")
            }
        }
        .navigationTitle(report.type)
    }

    private var exportText: String {
        guard let data = try? JSONEncoder().encode(report) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

private struct ExerciseStatusSection: View {
    let session: ExerciseSession
    let now: Date

    private var adjustment: EffectiveExerciseAdjustment? {
        EffectiveExerciseAdjustment.resolve(session: session, at: now)
    }

    var body: some View {
        Section {
            LabeledContent("Phase", value: phaseName)
            LabeledContent("Preset", value: session.preset.name)
            if let adjustment {
                LabeledContent("Effective basal", value: "\((adjustment.basalScale * 100).formatted())%")
                LabeledContent("Correction strength", value: "\((adjustment.correctionScale * 100).formatted())%")
                LabeledContent("SMB", value: adjustment.smbEnabled ? "On" : "Off")
                LabeledContent("Target", value: adjustment.target.map { "\($0.formatted()) mg/dL" } ?? "Trio default")
            }
            LabeledContent(timeLabel, value: timeValue)
        } header: {
            Label("Exercise Mode", systemImage: "figure.run")
                .foregroundStyle(phaseColor)
        }
    }

    private var phaseName: String {
        switch session.phase(at: now) {
        case .scheduled: "Scheduled"
        case .preExercise: "Pre Exercise"
        case .active: "Active Exercise"
        case .recovery: "Recovery"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        }
    }

    private var phaseColor: Color {
        switch session.phase(at: now) {
        case .preExercise: .yellow
        case .active: .purple
        case .recovery: .teal
        default: .secondary
        }
    }

    private var timeLabel: String {
        switch session.phase(at: now) {
        case .scheduled, .preExercise: "Active start"
        case .active: "Started"
        case .recovery: "Recommended end"
        default: "Created"
        }
    }

    private var timeValue: String {
        let date: Date = switch session.phase(at: now) {
        case .scheduled, .preExercise: session.scheduledExerciseStart
        case .active: session.actualExerciseStart ?? session.scheduledExerciseStart
        case .recovery: session.recommendedRecoveryEnd ?? now
        default: session.createdAt
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct ExerciseActionsSection: View {
    let coordinator: ExerciseCoordinator
    let session: ExerciseSession
    let now: Date

    var body: some View {
        Section("Actions") {
            if [.scheduled, .preExercise].contains(session.phase(at: now)) {
                Button("Start Exercise Now") { coordinator.startNow(at: now) }
            }
            if session.phase(at: now) == .active {
                Button("Stop Exercise", role: .destructive) { coordinator.stopExercise(at: now) }
            }
            if session.phase(at: now) == .recovery {
                Button("End Recovery", role: .destructive) { coordinator.endRecovery(at: now) }
            }
            Button("Cancel", role: .destructive) { coordinator.cancel(at: now) }
        }
    }
}

private struct ExerciseHistoryRow: View {
    let session: ExerciseSession
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(session.preset.name); Spacer(); Text(session.phase(at: Date()).rawValue.capitalized) }
            Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                if let pre = session.actualPreExerciseStart, let active = session.actualExerciseStart, active > pre {
                    Capsule().fill(.yellow).frame(width: 30, height: 5)
                }
                if let start = session.actualExerciseStart, let end = session.actualExerciseEnd, end > start {
                    Capsule().fill(.purple).frame(width: 50, height: 5)
                }
                if let start = session.recoveryStart,
                   let end = session.actualRecoveryEnd ?? session.recommendedRecoveryEnd, end > start {
                    Capsule().fill(.teal).frame(width: 70, height: 5)
                }
            }
        }
    }
}
