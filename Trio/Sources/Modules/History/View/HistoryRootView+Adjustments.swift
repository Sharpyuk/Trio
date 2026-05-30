import CoreData
import SwiftUI

extension History.RootView {
    var adjustmentsList: some View {
        List {
            NavigationLink {
                ExerciseReportsListView()
            } label: {
                Label("Exercise Reports", systemImage: "figure.run")
            }

            HStack {
                Text("Adjustment").foregroundStyle(.secondary)
                Spacer()
            }
            if !combinedAdjustments.isEmpty {
                ForEach(combinedAdjustments) { item in
                    adjustmentView(for: item)
                }
            } else {
                ContentUnavailableView(
                    String(localized: "No data."),
                    systemImage: "clock.arrow.2.circlepath"
                )
            }
        }
        .listRowBackground(Color.chart)
    }

    fileprivate var combinedAdjustments: [AdjustmentItem] {
        let overrides = overrideRunStored.map { override -> AdjustmentItem in
            AdjustmentItem(
                id: override.objectID,
                name: override.name ?? String(localized: "Override"),
                startDate: override.startDate ?? Date(),
                endDate: override.endDate ?? Date(),
                target: override.target?.decimalValue,
                exerciseSessionID: exerciseSessionID(for: override),
                type: .override
            )
        }

        let tempTargets = tempTargetRunStored.map { tempTarget -> AdjustmentItem in
            AdjustmentItem(
                id: tempTarget.objectID,
                name: tempTarget.name ?? String(localized: "Temp Target"),
                startDate: tempTarget.startDate ?? Date(),
                endDate: tempTarget.endDate ?? Date(),
                target: tempTarget.target?.decimalValue,
                exerciseSessionID: nil,
                type: .tempTarget
            )
        }

        let combined = overrides + tempTargets
        return combined.sorted {
            if $0.startDate == $1.startDate {
                return $0.endDate > $1.endDate
            }
            return $0.startDate > $1.startDate
        }
    }

    fileprivate struct AdjustmentItem: Identifiable {
        let id: NSManagedObjectID
        let name: String
        let startDate: Date
        let endDate: Date
        let target: Decimal?
        let exerciseSessionID: String?
        let type: AdjustmentType
    }

    fileprivate enum AdjustmentType {
        case override
        case tempTarget

        var symbolName: String {
            switch self {
            case .override:
                return "clock.arrow.2.circlepath"
            case .tempTarget:
                return "target"
            }
        }

        var symbolColor: Color {
            switch self {
            case .override:
                return .orange
            case .tempTarget:
                return .blue
            }
        }
    }

    @ViewBuilder fileprivate func adjustmentView(for item: AdjustmentItem) -> some View {
        if let exerciseSessionID = item.exerciseSessionID {
            NavigationLink {
                exerciseAdjustmentDestination(sessionID: exerciseSessionID, item: item)
            } label: {
                adjustmentRowContent(for: item)
            }
        } else {
            adjustmentRowContent(for: item)
        }
    }

    @ViewBuilder fileprivate func adjustmentRowContent(for item: AdjustmentItem) -> some View {
        let formattedDates =
            "\(Formatter.dateFormatter.string(from: item.startDate)) - \(Formatter.dateFormatter.string(from: item.endDate))"

        let targetDescription: String = {
            guard let target = item.target, target != 0 else {
                return ""
            }
            return "\(state.units == .mgdL ? target : target.asMmolL) \(state.units.rawValue)"
        }()

        let labels: [String] = [
            targetDescription,
            formattedDates
        ].filter { !$0.isEmpty }

        ZStack(alignment: .trailing) {
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: item.type.symbolName)
                            .foregroundStyle(item.type == .override ? Color.purple : Color.green)
                        Text(item.name)
                            .font(.headline)
                        Spacer()
                    }
                    HStack(spacing: 5) {
                        ForEach(labels, id: \.self) { label in
                            Text(label)
                            if label != labels.last {
                                Divider()
                            }
                        }
                        Spacer()
                    }
                    .padding(.top, 2)
                    .foregroundColor(.secondary)
                    .font(.caption)
                }
                .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder fileprivate func exerciseAdjustmentDestination(sessionID: String, item: AdjustmentItem) -> some View {
        if let report = ExerciseReportStore.loadReport(sessionID: sessionID) {
            ExerciseReportDetailView(report: report)
        } else {
            List {
                Section("Exercise Session") {
                    row("Session ID", sessionID)
                    row("Name", item.name)
                    row("Start", Formatter.dateFormatter.string(from: item.startDate))
                    row("End", Formatter.dateFormatter.string(from: item.endDate))
                    row("Report", "Not created yet")
                }
            }
            .navigationTitle("Exercise Session")
        }
    }

    fileprivate func exerciseSessionID(for overrideRun: OverrideRunStored) -> String? {
        if let override = overrideRun.override, override.exercisePhase != .inactive {
            return override.id ?? overrideRun.id?.uuidString
        }

        guard overrideRun.name?.localizedCaseInsensitiveContains("Exercise Override") == true else {
            return nil
        }
        return overrideRun.id?.uuidString
    }

    fileprivate func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
