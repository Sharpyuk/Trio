import Foundation

struct TrioCustomOrefVariables: JSON, Equatable {
    var average_total_data: Decimal
    var currentTDD: Decimal
    var weightedAverage: Decimal
    var past2hoursAverage: Decimal
    var date: Date
    var overridePercentage: Decimal
    var useOverride: Bool
    var duration: Decimal
    var unlimited: Bool
    var overrideTarget: Decimal
    var smbIsOff: Bool
    var advancedSettings: Bool
    var isfAndCr: Bool
    var isf: Bool
    var cr: Bool
    var smbIsScheduledOff: Bool
    var start: Decimal
    var end: Decimal
    var smbMinutes: Decimal
    var uamMinutes: Decimal
    var exerciseSensitivityMultiplier: Decimal
    var proteinFatAssistActive: Bool
    var proteinFatEarlySMBEnabled: Bool
    var proteinFatEarlySMBSuppressedByExercise: Bool
    var proteinFatAssistStartBG: Decimal
    var proteinFatEarlySMBMinBG: Decimal
    var proteinFatEarlySMBMinRise: Decimal
    var proteinFatEarlySMBMinPredictedRise: Decimal
    var proteinFatEarlySMBMaxUnits: Decimal

    init(
        average_total_data: Decimal,
        weightedAverage: Decimal,
        currentTDD: Decimal,
        past2hoursAverage: Decimal,
        date: Date,
        overridePercentage: Decimal,
        useOverride: Bool,
        duration: Decimal,
        unlimited: Bool,
        overrideTarget: Decimal,
        smbIsOff: Bool,
        advancedSettings: Bool,
        isfAndCr: Bool,
        isf: Bool,
        cr: Bool,
        smbIsScheduledOff: Bool,
        start: Decimal,
        end: Decimal,
        smbMinutes: Decimal,
        uamMinutes: Decimal,
        exerciseSensitivityMultiplier: Decimal = 1,
        proteinFatAssistActive: Bool = false,
        proteinFatEarlySMBEnabled: Bool = false,
        proteinFatEarlySMBSuppressedByExercise: Bool = false,
        proteinFatAssistStartBG: Decimal = 0,
        proteinFatEarlySMBMinBG: Decimal = 79,
        proteinFatEarlySMBMinRise: Decimal = Decimal(54) / 10,
        proteinFatEarlySMBMinPredictedRise: Decimal = Decimal(72) / 10,
        proteinFatEarlySMBMaxUnits: Decimal = 0
    ) {
        self.average_total_data = average_total_data
        self.weightedAverage = weightedAverage
        self.currentTDD = currentTDD
        self.past2hoursAverage = past2hoursAverage
        self.date = date
        self.overridePercentage = overridePercentage
        self.useOverride = useOverride
        self.duration = duration
        self.unlimited = unlimited
        self.overrideTarget = overrideTarget
        self.smbIsOff = smbIsOff
        self.advancedSettings = advancedSettings
        self.isfAndCr = isfAndCr
        self.isf = isf
        self.cr = cr
        self.smbIsScheduledOff = smbIsScheduledOff
        self.start = start
        self.end = end
        self.smbMinutes = smbMinutes
        self.uamMinutes = uamMinutes
        self.exerciseSensitivityMultiplier = exerciseSensitivityMultiplier
        self.proteinFatAssistActive = proteinFatAssistActive
        self.proteinFatEarlySMBEnabled = proteinFatEarlySMBEnabled
        self.proteinFatEarlySMBSuppressedByExercise = proteinFatEarlySMBSuppressedByExercise
        self.proteinFatAssistStartBG = proteinFatAssistStartBG
        self.proteinFatEarlySMBMinBG = proteinFatEarlySMBMinBG
        self.proteinFatEarlySMBMinRise = proteinFatEarlySMBMinRise
        self.proteinFatEarlySMBMinPredictedRise = proteinFatEarlySMBMinPredictedRise
        self.proteinFatEarlySMBMaxUnits = proteinFatEarlySMBMaxUnits
    }
}

extension TrioCustomOrefVariables {
    private enum CodingKeys: String, CodingKey {
        case average_total_data
        case weightedAverage
        case currentTDD
        case past2hoursAverage
        case date
        case overridePercentage
        case useOverride
        case duration
        case unlimited
        case overrideTarget
        case smbIsOff
        case advancedSettings
        case isfAndCr
        case isf
        case cr
        case smbIsScheduledOff
        case start
        case end
        case smbMinutes
        case uamMinutes
        case exerciseSensitivityMultiplier
        case proteinFatAssistActive
        case proteinFatEarlySMBEnabled
        case proteinFatEarlySMBSuppressedByExercise
        case proteinFatAssistStartBG
        case proteinFatEarlySMBMinBG
        case proteinFatEarlySMBMinRise
        case proteinFatEarlySMBMinPredictedRise
        case proteinFatEarlySMBMaxUnits
    }
}
