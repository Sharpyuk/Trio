import SwiftUI
import Swinject

extension MealSettings {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State private var displayPickerMaxCarbs: Bool = false
        @State private var displayPickerMaxFat: Bool = false
        @State private var displayPickerMaxProtein: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var conversionFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1

            return formatter
        }

        private var intFormater: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.allowsFloats = false
            return formatter
        }

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        var body: some View {
            List {
                Section(
                    header: Text("Limits per Entry"),
                    content: {
                        VStack {
                            VStack {
                                HStack {
                                    Text("Max Carbs")

                                    Spacer()

                                    Group {
                                        Text(state.maxCarbs.description)
                                            .foregroundColor(!displayPickerMaxCarbs ? .primary : .accentColor)

                                        Text(" g").foregroundColor(.secondary)
                                    }
                                }
                                .onTapGesture {
                                    displayPickerMaxCarbs.toggle()
                                }
                            }.padding(.top)

                            if displayPickerMaxCarbs {
                                let setting = PickerSettingsProvider.shared.settings.maxCarbs
                                Picker(selection: $state.maxCarbs, label: Text("")) {
                                    ForEach(
                                        PickerSettingsProvider.shared.generatePickerValues(from: setting, units: state.units),
                                        id: \.self
                                    ) { value in
                                        Text("\(value.description)").tag(value)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(maxWidth: .infinity)
                            }

                            if state.useFPUconversion {
                                VStack {
                                    HStack {
                                        Text("Max Fat")

                                        Spacer()

                                        Group {
                                            Text(state.maxFat.description)
                                                .foregroundColor(!displayPickerMaxFat ? .primary : .accentColor)

                                            Text(" g").foregroundColor(.secondary)
                                        }
                                    }
                                    .onTapGesture {
                                        displayPickerMaxFat.toggle()
                                    }
                                }
                                .padding(.top)

                                if displayPickerMaxFat {
                                    let setting = PickerSettingsProvider.shared.settings.maxFat
                                    Picker(selection: $state.maxFat, label: Text("")) {
                                        ForEach(
                                            PickerSettingsProvider.shared.generatePickerValues(from: setting, units: state.units),
                                            id: \.self
                                        ) { value in
                                            Text("\(value.description)").tag(value)
                                        }
                                    }
                                    .pickerStyle(WheelPickerStyle())
                                    .frame(maxWidth: .infinity)
                                }

                                VStack {
                                    HStack {
                                        Text("Max Protein")

                                        Spacer()

                                        Group {
                                            Text(state.maxProtein.description)
                                                .foregroundColor(!displayPickerMaxProtein ? .primary : .accentColor)

                                            Text(" g").foregroundColor(.secondary)
                                        }
                                    }
                                    .onTapGesture {
                                        displayPickerMaxProtein.toggle()
                                    }
                                }
                                .padding(.top)

                                if displayPickerMaxProtein {
                                    let setting = PickerSettingsProvider.shared.settings.maxProtein
                                    Picker(selection: $state.maxProtein, label: Text("")) {
                                        ForEach(
                                            PickerSettingsProvider.shared.generatePickerValues(from: setting, units: state.units),
                                            id: \.self
                                        ) { value in
                                            Text("\(value.description)").tag(value)
                                        }
                                    }
                                    .pickerStyle(WheelPickerStyle())
                                    .frame(maxWidth: .infinity)
                                }
                            }

                            HStack(alignment: .center) {
                                Text(
                                    "Set limits for each type of macro per meal entry."
                                )
                                .lineLimit(nil)
                                .font(.footnote)
                                .foregroundColor(.secondary)

                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = String(localized: "Limits per Entry")
                                        selectedVerboseHint =
                                            AnyView(
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Max Carbs:").bold()
                                                    Text("Enter the largest carb value allowed per meal entry")
                                                    Text("Max Fat:").bold()
                                                    Text("Enter the largest fat value allowed per meal entry")
                                                    Text("Max Protein:").bold()
                                                    Text("Enter the largest protein value allowed per meal entry")
                                                }
                                            )
                                        shouldDisplayHint.toggle()
                                    },
                                    label: {
                                        HStack {
                                            Image(systemName: "questionmark.circle")
                                        }
                                    }
                                ).buttonStyle(BorderlessButtonStyle())
                            }.padding(.top)
                        }.padding(.bottom)
                    }
                ).listRowBackground(Color.chart)

                SettingInputSection(
                    decimalValue: $state.maxMealAbsorptionTime,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Maximum Meal Absorption Time")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxMealAbsorptionTime"),
                    label: String(localized: "Max Meal Absorption Time"),
                    miniHint: String(
                        localized: "The maximum duration for tracking carb entries in estimating Carbs on Board (COB)"
                    ),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 6 hours").bold()
                        Text(
                            "Carb entries will be fully decayed by the number of hours specified as Max Meal Absorption Time. Meals that are high in fat and/or protein can have long lasting effects on glucose levels. To allow such late meal effects to be considered by the carb decay model, a longer Max Meal Absorption Time than the default 6 hours can be set."
                        )
                        Text(
                            "If carb entries decay too slowly, it is possible to set a lower than default setting. But this should typically be adressed by tuning ISF and CR settings instead, which in combination determines the rate of carb decay."
                        )
                        Text(
                            "Min 4 hours, max 10 hours."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.useFPUconversion,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Enable Fat and Protein Entries")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Enable Fat and Protein Entries"),
                    miniHint: String(localized: "Add fat and protein macros to meal entries."),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        VStack(spacing: 10) {
                            Text(
                                "Enabling this setting allows you to log fat and protein, which are then converted into future carb equivalents using the Warsaw Method."
                            )
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Warsaw Method:").bold()
                                Text(
                                    "The Warsaw Method helps account for the delayed glucose spikes caused by fat and protein in meals. It uses Fat-Protein Units (FPU) to calculate the carb effect from fat and protein. The system spreads insulin delivery over several hours to mimic natural insulin release, helping to manage post-meal glucose spikes."
                                )
                            }
                            VStack(alignment: .center, spacing: 5) {
                                Text("Fat Conversion").bold()
                                Text("𝑭 = fat(g) × 90%")
                            }
                            VStack(alignment: .center, spacing: 5) {
                                Text("Protein Conversion").bold()
                                Text("𝑷 = protein(g) × 40%")
                            }
                            VStack(alignment: .center, spacing: 5) {
                                Text("FPU Conversion").bold()
                                Text("𝑭 + 𝑷 = g CHO")
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(
                                    "You can personalize the conversion calculation by adjusting the following settings that will appear when this option is enabled:"
                                )
                                Text("• Fat and Protein Delay")
                                Text("• Spread Interval")
                                Text("• Fat and Protein Percentage")
                            }
                        }
                    },
                    headerText: String(localized: "Fat and Protein")
                )

                Section {
                    Picker("Protein/Fat Strategy", selection: $state.proteinFatMealStrategy) {
                        ForEach(ProteinFatMealStrategy.allCases) { strategy in
                            Text(strategy.displayName).tag(strategy)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(
                        "Default: Log only. Protein/Fat Assist creates a temporary target adjustment; Legacy Scheduled FPU is opt-in."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    proteinFatActivityGraphSettings

                    proteinFatAssistDurationDefaults

                    ForEach(ProteinFatAssistAggressiveness.presetCases) { profile in
                        proteinFatAssistProfileSection(for: profile)
                    }
                }
                .listRowBackground(Color.chart)

                if state.useFPUconversion && state.proteinFatMealStrategy == .legacyScheduledFPU {
                    SettingInputSection(
                        decimalValue: $state.delay,
                        booleanValue: $booleanPlaceholder,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = String(localized: "Fat and Protein Delay")
                            }
                        ),
                        units: state.units,
                        type: .decimal("delay"),
                        label: String(localized: "Fat and Protein Delay"),
                        miniHint: String(localized: "Delay between fat & protein entry and first FPU entry."),
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Default: 60 min").bold()
                            Text(
                                "The Fat and Protein Delay setting defines the time between when you log fat and protein and when the system starts delivering insulin for the Fat-Protein Unit Carb Equivalents (FPUs)."
                            )
                            Text(
                                "This delay accounts for the slower absorption of fat and protein, as calculated by the Warsaw Method, ensuring insulin delivery is properly timed to manage glucose spikes caused by high-fat, high-protein meals."
                            )
                        }
                    )

                    SettingInputSection(
                        decimalValue: $state.minuteInterval,
                        booleanValue: $booleanPlaceholder,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = String(localized: "Spread Interval")
                            }
                        ),
                        units: state.units,
                        type: .decimal("minuteInterval"),
                        label: String(localized: "Spread Interval"),
                        miniHint: String(localized: "Time interval between FPUs."),
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Default: 30 minutes").bold()
                            Text(
                                "This determines how many minutes will be between individual Fat-Protein Unit Carb Equivalent (FPU) entries from a single Fat and/or Protein bolus calculator entry."
                            )
                            Text(
                                "Entries are capped at 33 grams each, with up to three entries, for a max total of 99 grams."
                            )
                        }
                    )

                    SettingInputSection(
                        decimalValue: $state.individualAdjustmentFactor,
                        booleanValue: $booleanPlaceholder,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = String(localized: "Fat and Protein Percentage")
                            }
                        ),
                        units: state.units,
                        type: .decimal("individualAdjustmentFactor"),
                        label: String(localized: "Fat and Protein Percentage"),
                        miniHint: String(localized: "Adjust the Warsaw Method FPU Conversion rate."),
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text("Default: 50%").bold()
                            VStack(spacing: 10) {
                                Text("This setting changes how much effect the fat and protein entry has on FPUs.")
                                VStack(alignment: .center, spacing: 5) {
                                    Text("50% is half effect:").bold()
                                    Text("(Fat × 45%) + (Protein × 20%)")
                                    Text("100% is full effect:").bold()
                                    Text("(Fat × 90%) + (Protein × 40%)")
                                    Text("110% makes fat-to-carbs ratio essentially equal:").bold()
                                    Text("(Fat × 99%) + (Protein x 44%)")
                                }
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                Text(
                                    "Tip: You may find that your normal carb ratio needs to increase to a larger number when you begin adding fat and protein entries. For this reason, it is best to start with a factor of about 50%."
                                )
                            }
                        }
                    )
                }
            }
            .listSectionSpacing(sectionSpacing)
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationBarTitle("Meal Settings")
            .navigationBarTitleDisplayMode(.automatic)
            .settingsHighlightScroll()
        }

        @ViewBuilder private var proteinFatActivityGraphSettings: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Protein/Fat Activity Graph")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Picker("Show Protein/Fat on graph", selection: $state.proteinFatActivityGraphDisplay) {
                    ForEach(ProteinFatActivityGraphDisplay.allCases) { display in
                        Text(display.displayName).tag(display)
                    }
                }
                .pickerStyle(.menu)

                Text("Visual only. This does not affect COB, IOB, predictions, or insulin dosing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                proteinFatAssistEffectRow(
                    title: "Protein duration factor",
                    value: state.proteinFatActivityProteinDurationFactor.formatted(
                        .number.precision(.fractionLength(2))
                    ),
                    decrement: {
                        state.proteinFatActivityProteinDurationFactor = max(
                            0.1,
                            state.proteinFatActivityProteinDurationFactor - 0.05
                        )
                    },
                    increment: {
                        state.proteinFatActivityProteinDurationFactor = min(
                            1,
                            state.proteinFatActivityProteinDurationFactor + 0.05
                        )
                    }
                )
            }
        }

        @ViewBuilder private var proteinFatAssistDurationDefaults: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Duration Defaults")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                proteinFatAssistEffectRow(
                    title: "Base duration",
                    value: "\(Int(truncating: state.proteinFatAssistBaseDuration as NSNumber)) min",
                    decrement: {
                        state.proteinFatAssistBaseDuration = max(60, state.proteinFatAssistBaseDuration - 30)
                    },
                    increment: {
                        state.proteinFatAssistBaseDuration = min(720, state.proteinFatAssistBaseDuration + 30)
                    }
                )

                proteinFatAssistEffectRow(
                    title: "Per 10g fat",
                    value: "+\(Int(truncating: state.proteinFatAssistMinutesPer10gFat as NSNumber)) min",
                    decrement: {
                        state.proteinFatAssistMinutesPer10gFat = max(0, state.proteinFatAssistMinutesPer10gFat - 5)
                    },
                    increment: {
                        state.proteinFatAssistMinutesPer10gFat = min(120, state.proteinFatAssistMinutesPer10gFat + 5)
                    }
                )

                proteinFatAssistEffectRow(
                    title: "Minimum",
                    value: "\(Int(truncating: state.proteinFatAssistMinimumDuration as NSNumber)) min",
                    decrement: {
                        state.proteinFatAssistMinimumDuration = max(60, state.proteinFatAssistMinimumDuration - 30)
                    },
                    increment: {
                        state.proteinFatAssistMinimumDuration = min(720, state.proteinFatAssistMinimumDuration + 30)
                    }
                )

                proteinFatAssistEffectRow(
                    title: "Maximum",
                    value: "\(Int(truncating: state.proteinFatAssistMaximumDefaultDuration as NSNumber)) min",
                    decrement: {
                        state.proteinFatAssistMaximumDefaultDuration = max(60, state.proteinFatAssistMaximumDefaultDuration - 30)
                    },
                    increment: {
                        state.proteinFatAssistMaximumDefaultDuration = min(720, state.proteinFatAssistMaximumDefaultDuration + 30)
                    }
                )
            }
        }

        @ViewBuilder private func proteinFatAssistProfileSection(for profile: ProteinFatAssistAggressiveness) -> some View {
            let settings = state.profileSettings(for: profile)
            VStack(alignment: .leading, spacing: 8) {
                Text(profile.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                proteinFatAssistEffectRow(
                    title: "ISF",
                    value: "\(Int(truncating: settings.isfPercent as NSNumber))%",
                    decrement: {
                        state.updateProfile(profile) { $0.isfPercent = max(70, $0.isfPercent - 1) }
                    },
                    increment: {
                        state.updateProfile(profile) { $0.isfPercent = min(100, $0.isfPercent + 1) }
                    }
                )

                proteinFatAssistEffectRow(
                    title: "SMB uplift",
                    value: "+\(Int(truncating: settings.smbMinutesIncrease as NSNumber)) min",
                    decrement: {
                        state.updateProfile(profile) { $0.smbMinutesIncrease = max(0, $0.smbMinutesIncrease - 5) }
                    },
                    increment: {
                        state.updateProfile(profile) { $0.smbMinutesIncrease = min(60, $0.smbMinutesIncrease + 5) }
                    }
                )

                proteinFatAssistEffectRow(
                    title: "UAM uplift",
                    value: "+\(Int(truncating: settings.uamMinutesIncrease as NSNumber)) min",
                    decrement: {
                        state.updateProfile(profile) { $0.uamMinutesIncrease = max(0, $0.uamMinutesIncrease - 5) }
                    },
                    increment: {
                        state.updateProfile(profile) { $0.uamMinutesIncrease = min(60, $0.uamMinutesIncrease + 5) }
                    }
                )

                Toggle("Target adjustment", isOn: Binding(
                    get: { state.profileSettings(for: profile).targetAdjustmentEnabled },
                    set: { isEnabled in
                        state.updateProfile(profile) { $0.targetAdjustmentEnabled = isEnabled }
                    }
                ))

                if settings.targetAdjustmentEnabled {
                    proteinFatAssistEffectRow(
                        title: "Target",
                        value: "-\(formattedProteinFatAssistTargetAdjustment(settings.targetAdjustmentMgDL))",
                        decrement: {
                            state.updateProfile(profile) { $0.targetAdjustmentMgDL = max(0, $0.targetAdjustmentMgDL - 1) }
                        },
                        increment: {
                            state.updateProfile(profile) { $0.targetAdjustmentMgDL = min(30, $0.targetAdjustmentMgDL + 1) }
                        }
                    )
                }

                Toggle("Early SMB nudges", isOn: Binding(
                    get: { state.profileSettings(for: profile).earlySMBEnabled },
                    set: { isEnabled in
                        state.updateProfile(profile) { $0.earlySMBEnabled = isEnabled }
                    }
                ))

                Text("Allows small SMBs earlier when glucose begins rising after a fat/protein meal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.earlySMBEnabled {
                    proteinFatAssistEffectRow(
                        title: "Minimum BG",
                        value: formattedProteinFatAssistGlucose(settings.earlySMBMinBGMgDL),
                        decrement: {
                            state.updateProfile(profile) { $0.earlySMBMinBGMgDL = max(54, $0.earlySMBMinBGMgDL - 1) }
                        },
                        increment: {
                            state.updateProfile(profile) { $0.earlySMBMinBGMgDL = min(180, $0.earlySMBMinBGMgDL + 1) }
                        }
                    )

                    proteinFatAssistEffectRow(
                        title: "Minimum rise",
                        value: formattedProteinFatAssistGlucose(settings.earlySMBMinRiseMgDL),
                        decrement: {
                            state.updateProfile(profile) { $0.earlySMBMinRiseMgDL = max(0, $0.earlySMBMinRiseMgDL - 1) }
                        },
                        increment: {
                            state.updateProfile(profile) { $0.earlySMBMinRiseMgDL = min(54, $0.earlySMBMinRiseMgDL + 1) }
                        }
                    )

                    proteinFatAssistEffectRow(
                        title: "Predicted rise",
                        value: formattedProteinFatAssistGlucose(settings.earlySMBMinPredictedRiseMgDL),
                        decrement: {
                            state.updateProfile(profile) {
                                $0.earlySMBMinPredictedRiseMgDL = max(0, $0.earlySMBMinPredictedRiseMgDL - 1)
                            }
                        },
                        increment: {
                            state.updateProfile(profile) {
                                $0.earlySMBMinPredictedRiseMgDL = min(72, $0.earlySMBMinPredictedRiseMgDL + 1)
                            }
                        }
                    )

                    proteinFatAssistEffectRow(
                        title: "Max early SMB",
                        value: formattedProteinFatAssistUnits(settings.earlySMBMaxUnits),
                        decrement: {
                            state.updateProfile(profile) { $0.earlySMBMaxUnits = max(0, $0.earlySMBMaxUnits - 0.05) }
                        },
                        increment: {
                            state.updateProfile(profile) { $0.earlySMBMaxUnits = min(1, $0.earlySMBMaxUnits + 0.05) }
                        }
                    )
                }
            }
        }

        private func formattedProteinFatAssistTargetAdjustment(_ adjustment: Decimal) -> String {
            if state.units == .mmolL {
                return "\(adjustment.asMmolL.formatted(.number.precision(.fractionLength(1)))) mmol/L"
            }
            return "\(Int(truncating: adjustment as NSNumber)) mg/dL"
        }

        private func formattedProteinFatAssistGlucose(_ glucose: Decimal) -> String {
            if state.units == .mmolL {
                return "\(glucose.asMmolL.formatted(.number.precision(.fractionLength(1)))) mmol/L"
            }
            return "\(glucose.formatted(.number.precision(.fractionLength(0)))) mg/dL"
        }

        private func formattedProteinFatAssistUnits(_ units: Decimal) -> String {
            "\(units.formatted(.number.precision(.fractionLength(2)))) U"
        }

        @ViewBuilder private func proteinFatAssistEffectRow(
            title: LocalizedStringKey,
            value: String,
            decrement: @escaping () -> Void,
            increment: @escaping () -> Void
        ) -> some View {
            HStack {
                Text(title)
                Spacer()
                Button(action: decrement) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                Text(value)
                    .frame(minWidth: 86, alignment: .center)
                Button(action: increment) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
