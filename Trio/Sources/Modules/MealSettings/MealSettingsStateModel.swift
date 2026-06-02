import SwiftUI

extension MealSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Published var units: GlucoseUnits = .mgdL
        @Published var useFPUconversion: Bool = false
        @Published var maxCarbs: Decimal = 250
        @Published var maxFat: Decimal = 250
        @Published var maxProtein: Decimal = 250
        @Published var individualAdjustmentFactor: Decimal = 0.5
        @Published var proteinFatMealStrategy: ProteinFatMealStrategy = .logOnly
        @Published var proteinFatAssistDuration: Decimal = 300
        @Published var proteinFatAssistAggressiveness: ProteinFatAssistAggressiveness = .medium
        @Published var proteinFatAssistMildProfile: ProteinFatAssistProfileSettings = .defaults(for: .mild)
        @Published var proteinFatAssistMediumProfile: ProteinFatAssistProfileSettings = .defaults(for: .medium)
        @Published var proteinFatAssistStrongProfile: ProteinFatAssistProfileSettings = .defaults(for: .strong)
        @Published var proteinFatAssistBaseDuration: Decimal = 180
        @Published var proteinFatAssistMinutesPer10gFat: Decimal = 30
        @Published var proteinFatAssistMinimumDuration: Decimal = 120
        @Published var proteinFatAssistMaximumDefaultDuration: Decimal = 480
        @Published var proteinFatActivityGraphDisplay: ProteinFatActivityGraphDisplay = .combined
        @Published var proteinFatActivityProteinDurationFactor: Decimal = 0.7
        @Published var proteinFatActivityFatPeakPercent: Decimal = 0.45
        @Published var proteinFatActivityProteinPeakPercent: Decimal = 0.30
        @Published var minuteInterval: Decimal = 30
        @Published var delay: Decimal = 60
        @Published var maxMealAbsorptionTime: Decimal = 6

        override func subscribe() {
            units = settingsManager.settings.units

            subscribeSetting(\.maxCarbs, on: $maxCarbs) { maxCarbs = $0 }
            subscribeSetting(\.maxFat, on: $maxFat) { maxFat = $0 }
            subscribeSetting(\.maxProtein, on: $maxProtein) { maxProtein = $0 }

            subscribePreferencesSetting(\.maxMealAbsorptionTime, on: $maxMealAbsorptionTime) { maxMealAbsorptionTime = $0 }

            subscribeSetting(\.useFPUconversion, on: $useFPUconversion) { useFPUconversion = $0 }
            subscribeSetting(\.proteinFatMealStrategy, on: $proteinFatMealStrategy) { proteinFatMealStrategy = $0 }
            subscribeSetting(
                \.proteinFatAssistDuration,
                on: $proteinFatAssistDuration,
                initial: { proteinFatAssistDuration = $0 },
                map: { min(max($0, 60), 720) }
            )
            subscribeSetting(\.proteinFatAssistAggressiveness, on: $proteinFatAssistAggressiveness) {
                proteinFatAssistAggressiveness = $0
            }
            subscribeSetting(\.proteinFatAssistMildProfile, on: $proteinFatAssistMildProfile) {
                proteinFatAssistMildProfile = $0.sanitized
            }
            subscribeSetting(\.proteinFatAssistMediumProfile, on: $proteinFatAssistMediumProfile) {
                proteinFatAssistMediumProfile = $0.sanitized
            }
            subscribeSetting(\.proteinFatAssistStrongProfile, on: $proteinFatAssistStrongProfile) {
                proteinFatAssistStrongProfile = $0.sanitized
            }
            subscribeSetting(\.proteinFatAssistBaseDuration, on: $proteinFatAssistBaseDuration) {
                proteinFatAssistBaseDuration = min(max($0, 60), 720)
            }
            subscribeSetting(\.proteinFatAssistMinutesPer10gFat, on: $proteinFatAssistMinutesPer10gFat) {
                proteinFatAssistMinutesPer10gFat = min(max($0, 0), 120)
            }
            subscribeSetting(\.proteinFatAssistMinimumDuration, on: $proteinFatAssistMinimumDuration) {
                proteinFatAssistMinimumDuration = min(max($0, 60), 720)
            }
            subscribeSetting(\.proteinFatAssistMaximumDefaultDuration, on: $proteinFatAssistMaximumDefaultDuration) {
                proteinFatAssistMaximumDefaultDuration = min(max($0, 60), 720)
            }
            subscribeSetting(\.proteinFatActivityGraphDisplay, on: $proteinFatActivityGraphDisplay) {
                proteinFatActivityGraphDisplay = $0
            }
            subscribeSetting(\.proteinFatActivityProteinDurationFactor, on: $proteinFatActivityProteinDurationFactor) {
                proteinFatActivityProteinDurationFactor = min(max($0, 0.1), 1)
            }
            subscribeSetting(\.proteinFatActivityFatPeakPercent, on: $proteinFatActivityFatPeakPercent) {
                proteinFatActivityFatPeakPercent = min(max($0, 0.1), 0.9)
            }
            subscribeSetting(\.proteinFatActivityProteinPeakPercent, on: $proteinFatActivityProteinPeakPercent) {
                proteinFatActivityProteinPeakPercent = min(max($0, 0.1), 0.9)
            }

            // "Fat and Protein Delay"
            subscribeSetting(\.delay, on: $delay) { delay = $0 }

            // "Spread Interval"
            subscribeSetting(\.minuteInterval, on: $minuteInterval) { minuteInterval = $0 }

            // "Fat and Protein Percentage"
            subscribeSetting(\.individualAdjustmentFactor, on: $individualAdjustmentFactor) { individualAdjustmentFactor = $0 }
        }

        func profileSettings(for profile: ProteinFatAssistAggressiveness) -> ProteinFatAssistProfileSettings {
            switch profile {
            case .mild:
                return proteinFatAssistMildProfile.sanitized
            case .medium:
                return proteinFatAssistMediumProfile.sanitized
            case .strong:
                return proteinFatAssistStrongProfile.sanitized
            case .custom:
                return .defaults(for: .custom)
            }
        }

        func updateProfile(_ profile: ProteinFatAssistAggressiveness, _ update: (inout ProteinFatAssistProfileSettings) -> Void) {
            var settings = profileSettings(for: profile)
            update(&settings)
            settings = settings.sanitized
            switch profile {
            case .mild:
                proteinFatAssistMildProfile = settings
            case .medium:
                proteinFatAssistMediumProfile = settings
            case .strong:
                proteinFatAssistStrongProfile = settings
            case .custom:
                break
            }
        }
    }
}

extension MealSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
