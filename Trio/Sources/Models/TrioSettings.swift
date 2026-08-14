import Foundation

enum BolusShortcutLimit: String, JSON, CaseIterable, Identifiable {
    var id: String { rawValue }
    case notAllowed
    case limitWithSafetyChecks

    var displayName: String {
        switch self {
        case .notAllowed:
            return String(localized: "Not allowed")
        case .limitWithSafetyChecks:
            return String(localized: "Limit with Safety Checks")
        }
    }
}

enum ProteinFatMealStrategy: String, Codable, CaseIterable, Identifiable, Equatable {
    case logOnly
    case assist
    case legacyScheduledFPU

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .logOnly:
            return String(localized: "Log only")
        case .assist:
            return String(localized: "Protein/Fat Assist")
        case .legacyScheduledFPU:
            return String(localized: "Legacy Scheduled FPU")
        }
    }

    var isLegacyScheduledFPU: Bool {
        self == .legacyScheduledFPU
    }
}

enum ProteinFatAssistAggressiveness: String, Codable, CaseIterable, Identifiable, Equatable {
    case mild
    case medium
    case strong
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mild:
            return String(localized: "Mild")
        case .medium:
            return String(localized: "Medium")
        case .strong:
            return String(localized: "Strong")
        case .custom:
            return String(localized: "Custom")
        }
    }

    static var presetCases: [ProteinFatAssistAggressiveness] {
        [.mild, .medium, .strong]
    }

    var targetAdjustmentMgDL: Decimal {
        switch self {
        case .mild:
            return 4
        case .medium:
            return 7
        case .strong:
            return 11
        case .custom:
            return 0
        }
    }

    var isfPercent: Decimal {
        switch self {
        case .mild:
            return 95
        case .medium:
            return 90
        case .strong:
            return 85
        case .custom:
            return 90
        }
    }

    var smbMinutesIncrease: Decimal {
        switch self {
        case .mild:
            return 5
        case .medium:
            return 10
        case .strong:
            return 20
        case .custom:
            return 10
        }
    }

    var uamMinutesIncrease: Decimal {
        switch self {
        case .mild:
            return 5
        case .medium:
            return 10
        case .strong:
            return 20
        case .custom:
            return 10
        }
    }

    var earlySMBMaxUnits: Decimal {
        switch self {
        case .mild:
            return 0.1
        case .medium:
            return 0.2
        case .strong:
            return 0.3
        case .custom:
            return 0.2
        }
    }
}

enum ProteinFatActivityGraphDisplay: String, Codable, CaseIterable, Identifiable, Equatable {
    case off
    case combined
    case separate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:
            return String(localized: "Off")
        case .combined:
            return String(localized: "Combined")
        case .separate:
            return String(localized: "Separate")
        }
    }
}

struct ProteinFatAssistProfileSettings: Codable, Equatable {
    var isfPercent: Decimal
    var smbMinutesIncrease: Decimal
    var uamMinutesIncrease: Decimal
    var targetAdjustmentEnabled: Bool
    var targetAdjustmentMgDL: Decimal
    var earlySMBEnabled: Bool
    var earlySMBMinBGMgDL: Decimal
    var earlySMBMinRiseMgDL: Decimal
    var earlySMBMinPredictedRiseMgDL: Decimal
    var earlySMBMaxUnits: Decimal

    static func defaults(for profile: ProteinFatAssistAggressiveness) -> Self {
        Self(
            isfPercent: profile.isfPercent,
            smbMinutesIncrease: profile.smbMinutesIncrease,
            uamMinutesIncrease: profile.uamMinutesIncrease,
            targetAdjustmentEnabled: false,
            targetAdjustmentMgDL: profile.targetAdjustmentMgDL,
            earlySMBEnabled: true,
            earlySMBMinBGMgDL: 79,
            earlySMBMinRiseMgDL: Decimal(54) / 10,
            earlySMBMinPredictedRiseMgDL: Decimal(72) / 10,
            earlySMBMaxUnits: profile.earlySMBMaxUnits
        )
    }

    var sanitized: Self {
        Self(
            isfPercent: min(max(isfPercent, 70), 100),
            smbMinutesIncrease: min(max(smbMinutesIncrease, 0), 60),
            uamMinutesIncrease: min(max(uamMinutesIncrease, 0), 60),
            targetAdjustmentEnabled: targetAdjustmentEnabled,
            targetAdjustmentMgDL: min(max(targetAdjustmentMgDL, 0), 30),
            earlySMBEnabled: earlySMBEnabled,
            earlySMBMinBGMgDL: min(max(earlySMBMinBGMgDL, 54), 180),
            earlySMBMinRiseMgDL: min(max(earlySMBMinRiseMgDL, 0), 54),
            earlySMBMinPredictedRiseMgDL: min(max(earlySMBMinPredictedRiseMgDL, 0), 72),
            earlySMBMaxUnits: min(max(earlySMBMaxUnits, 0), 1)
        )
    }
}

extension ProteinFatAssistProfileSettings {
    enum CodingKeys: String, CodingKey {
        case isfPercent
        case smbMinutesIncrease
        case uamMinutesIncrease
        case targetAdjustmentEnabled
        case targetAdjustmentMgDL
        case earlySMBEnabled
        case earlySMBMinBGMgDL
        case earlySMBMinRiseMgDL
        case earlySMBMinPredictedRiseMgDL
        case earlySMBMaxUnits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ProteinFatAssistProfileSettings.defaults(for: .medium)

        isfPercent = (try? container.decode(Decimal.self, forKey: .isfPercent)) ?? defaults.isfPercent
        smbMinutesIncrease = (try? container.decode(Decimal.self, forKey: .smbMinutesIncrease)) ?? defaults.smbMinutesIncrease
        uamMinutesIncrease = (try? container.decode(Decimal.self, forKey: .uamMinutesIncrease)) ?? defaults.uamMinutesIncrease
        targetAdjustmentEnabled = (try? container.decode(Bool.self, forKey: .targetAdjustmentEnabled)) ??
            defaults.targetAdjustmentEnabled
        targetAdjustmentMgDL = (try? container.decode(Decimal.self, forKey: .targetAdjustmentMgDL)) ??
            defaults.targetAdjustmentMgDL
        earlySMBEnabled = (try? container.decode(Bool.self, forKey: .earlySMBEnabled)) ?? defaults.earlySMBEnabled
        earlySMBMinBGMgDL = (try? container.decode(Decimal.self, forKey: .earlySMBMinBGMgDL)) ??
            defaults.earlySMBMinBGMgDL
        earlySMBMinRiseMgDL = (try? container.decode(Decimal.self, forKey: .earlySMBMinRiseMgDL)) ??
            defaults.earlySMBMinRiseMgDL
        earlySMBMinPredictedRiseMgDL =
            (try? container.decode(Decimal.self, forKey: .earlySMBMinPredictedRiseMgDL)) ??
            defaults.earlySMBMinPredictedRiseMgDL
        earlySMBMaxUnits = (try? container.decode(Decimal.self, forKey: .earlySMBMaxUnits)) ?? -1
    }

    func profileDefaulted(for profile: ProteinFatAssistAggressiveness) -> Self {
        var settings = self

        if settings.earlySMBMaxUnits < 0 {
            settings.earlySMBMaxUnits = ProteinFatAssistProfileSettings.defaults(for: profile).earlySMBMaxUnits
        }

        return settings
    }
}

struct TrioSettings: JSON, Equatable, Encodable {
    var units: GlucoseUnits = .mgdL
    var closedLoop: Bool = false
    var isUploadEnabled: Bool = false
    var isDownloadEnabled: Bool = false
    var useLocalGlucoseSource: Bool = false
    var localGlucosePort: Int = 8080
    var debugOptions: Bool = false
    var cgm: CGMType = .none
    var cgmPluginIdentifier: String = ""
    var libreGlucoseReadIntervalMinutes: Int = 5
    var uploadGlucose: Bool = true
    var useCalendar: Bool = false
    var displayCalendarIOBandCOB: Bool = false
    var displayCalendarEmojis: Bool = false
    var glucoseBadge: Bool = false
    var notificationsPump: Bool = true
    var notificationsCgm: Bool = true
    var notificationsCarb: Bool = true
    var notificationsAlgorithm: Bool = true
    var glucoseNotificationsOption: GlucoseNotificationsOption = .onlyAlarmLimits
    var addSourceInfoToGlucoseNotifications: Bool = false
    var lowGlucose: Decimal = 72
    var highGlucose: Decimal = 270
    var carbsRequiredThreshold: Decimal = 10
    var showCarbsRequiredBadge: Bool = true
    var useFPUconversion: Bool = false
    var proteinFatMealStrategy: ProteinFatMealStrategy = .logOnly
    var proteinFatAssistDuration: Decimal = 300
    var proteinFatAssistAggressiveness: ProteinFatAssistAggressiveness = .medium
    var proteinFatAssistMildProfile: ProteinFatAssistProfileSettings = .defaults(for: .mild)
    var proteinFatAssistMediumProfile: ProteinFatAssistProfileSettings = .defaults(for: .medium)
    var proteinFatAssistStrongProfile: ProteinFatAssistProfileSettings = .defaults(for: .strong)
    var proteinFatAssistCustomProfile: ProteinFatAssistProfileSettings = .defaults(for: .custom)
    var proteinFatAssistBaseDuration: Decimal = 180
    var proteinFatAssistMinutesPer10gFat: Decimal = 30
    var proteinFatAssistMinimumDuration: Decimal = 120
    var proteinFatAssistMaximumDefaultDuration: Decimal = 480
    var proteinFatActivityGraphDisplay: ProteinFatActivityGraphDisplay = .combined
    var proteinFatActivityProteinDurationFactor: Decimal = 0.7
    var proteinFatActivityFatPeakPercent: Decimal = 0.45
    var proteinFatActivityProteinPeakPercent: Decimal = 0.30
    var individualAdjustmentFactor: Decimal = 0.5
    var minuteInterval: Decimal = 30
    var delay: Decimal = 60
    var useAppleHealth: Bool = false
    var smoothGlucose: Bool = false
    var eA1cDisplayUnit: EstimatedA1cDisplayUnit = .percent
    var high: Decimal = 180
    var low: Decimal = 70
    var glucoseColorScheme: GlucoseColorScheme = .staticColor
    var xGridLines: Bool = true
    var yGridLines: Bool = true
    var hideInsulinBadge: Bool = false
    var allowDilution: Bool = false
    var insulinConcentration: Decimal = 1
    var showCobIobChart: Bool = true
    var rulerMarks: Bool = true
    var bolusDisplayThreshold: BolusDisplayThreshold = .allUnits
    var forecastDisplayType: ForecastDisplayType = .cone
    var maxCarbs: Decimal = 250
    var maxFat: Decimal = 250
    var maxProtein: Decimal = 250
    var confirmBolusFaster: Bool = false
    var overrideFactor: Decimal = 0.8
    var fattyMeals: Bool = false
    var fattyMealFactor: Decimal = 0.7
    var sweetMeals: Bool = false
    var sweetMealFactor: Decimal = 1
    var displayPresets: Bool = true
    var confirmBolus: Bool = false
    var useLiveActivity: Bool = false
    var lockScreenView: LockScreenView = .simple
    var smartStackView: LockScreenView = .simple
    var bolusShortcut: BolusShortcutLimit = .notAllowed
    var timeInRangeType: TimeInRangeType = .timeInTightRange
    var requireAdjustmentsConfirmation: Bool = false

    /// Selected Garmin watchface (Trio or SwissAlpine)
    var garminWatchface: GarminWatchface = .trio
    var garminDatafield: GarminDatafield = .none

    /// Primary attribute choice for Garmin display (COB, ISF, or Sensitivity Ratio)
    var primaryAttributeChoice: GarminPrimaryAttributeChoice = .cob

    /// Secondary attribute choice for Garmin display (TBR or Eventual BG)
    var secondaryAttributeChoice: GarminSecondaryAttributeChoice = .tbr

    /// Controls whether watchface data transmission is enabled
    var isWatchfaceDataEnabled: Bool = false

    /// Computed property that groups all Garmin settings into a single struct
    var garminSettings: GarminWatchSettings {
        get {
            GarminWatchSettings(
                watchface: garminWatchface,
                datafield: garminDatafield,
                primaryAttributeChoice: primaryAttributeChoice,
                secondaryAttributeChoice: secondaryAttributeChoice,
                isWatchfaceDataEnabled: isWatchfaceDataEnabled
            )
        }
        set {
            garminWatchface = newValue.watchface
            garminDatafield = newValue.datafield
            primaryAttributeChoice = newValue.primaryAttributeChoice
            secondaryAttributeChoice = newValue.secondaryAttributeChoice
            isWatchfaceDataEnabled = newValue.isWatchfaceDataEnabled
        }
    }
}

extension TrioSettings {
    static let libreGlucoseReadIntervalOptions = [5, 4, 3, 2]

    static func sanitizedLibreGlucoseReadIntervalMinutes(_ value: Int) -> Int {
        min(5, max(2, value))
    }

    var sanitizedLibreGlucoseReadIntervalMinutes: Int {
        Self.sanitizedLibreGlucoseReadIntervalMinutes(libreGlucoseReadIntervalMinutes)
    }
}

extension TrioSettings: Decodable {
    /// Custom decoder to handle incomplete JSON and provide default values for missing fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var settings = TrioSettings()

        if let units = try? container.decode(GlucoseUnits.self, forKey: .units) {
            settings.units = units
        }

        if let closedLoop = try? container.decode(Bool.self, forKey: .closedLoop) {
            settings.closedLoop = closedLoop
        }

        if let isUploadEnabled = try? container.decode(Bool.self, forKey: .isUploadEnabled) {
            settings.isUploadEnabled = isUploadEnabled
        }

        if let isDownloadEnabled = try? container.decode(Bool.self, forKey: .isDownloadEnabled) {
            settings.isDownloadEnabled = isDownloadEnabled
        }

        if let useLocalGlucoseSource = try? container.decode(Bool.self, forKey: .useLocalGlucoseSource) {
            settings.useLocalGlucoseSource = useLocalGlucoseSource
        }

        if let localGlucosePort = try? container.decode(Int.self, forKey: .localGlucosePort) {
            settings.localGlucosePort = localGlucosePort
        }

        if let debugOptions = try? container.decode(Bool.self, forKey: .debugOptions) {
            settings.debugOptions = debugOptions
        }

        if let cgm = try? container.decode(CGMType.self, forKey: .cgm) {
            settings.cgm = cgm
        }

        if let cgmPluginIdentifier = try? container.decode(String.self, forKey: .cgmPluginIdentifier) {
            settings.cgmPluginIdentifier = cgmPluginIdentifier
        }

        if let libreGlucoseReadIntervalMinutes = try? container.decode(
            Int.self,
            forKey: .libreGlucoseReadIntervalMinutes
        ) {
            settings.libreGlucoseReadIntervalMinutes = TrioSettings
                .sanitizedLibreGlucoseReadIntervalMinutes(libreGlucoseReadIntervalMinutes)
        }

        if let uploadGlucose = try? container.decode(Bool.self, forKey: .uploadGlucose) {
            settings.uploadGlucose = uploadGlucose
        }

        if let useCalendar = try? container.decode(Bool.self, forKey: .useCalendar) {
            settings.useCalendar = useCalendar
        }

        if let displayCalendarIOBandCOB = try? container.decode(Bool.self, forKey: .displayCalendarIOBandCOB) {
            settings.displayCalendarIOBandCOB = displayCalendarIOBandCOB
        }

        if let displayCalendarEmojis = try? container.decode(Bool.self, forKey: .displayCalendarEmojis) {
            settings.displayCalendarEmojis = displayCalendarEmojis
        }

        if let useAppleHealth = try? container.decode(Bool.self, forKey: .useAppleHealth) {
            settings.useAppleHealth = useAppleHealth
        }

        if let glucoseBadge = try? container.decode(Bool.self, forKey: .glucoseBadge) {
            settings.glucoseBadge = glucoseBadge
        }

        if let useFPUconversion = try? container.decode(Bool.self, forKey: .useFPUconversion) {
            settings.useFPUconversion = useFPUconversion
        }

        if let proteinFatMealStrategy = try? container.decode(
            ProteinFatMealStrategy.self,
            forKey: .proteinFatMealStrategy
        ) {
            settings.proteinFatMealStrategy = proteinFatMealStrategy
        }

        if let proteinFatAssistDuration = try? container.decode(Decimal.self, forKey: .proteinFatAssistDuration) {
            settings.proteinFatAssistDuration = min(max(proteinFatAssistDuration, 60), 720)
        }

        if let proteinFatAssistAggressiveness = try? container.decode(
            ProteinFatAssistAggressiveness.self,
            forKey: .proteinFatAssistAggressiveness
        ) {
            settings.proteinFatAssistAggressiveness = proteinFatAssistAggressiveness
        }

        if let proteinFatAssistMildProfile = try? container.decode(
            ProteinFatAssistProfileSettings.self,
            forKey: .proteinFatAssistMildProfile
        ) {
            settings.proteinFatAssistMildProfile = proteinFatAssistMildProfile
                .profileDefaulted(for: .mild)
                .sanitized
        }

        if let proteinFatAssistMediumProfile = try? container.decode(
            ProteinFatAssistProfileSettings.self,
            forKey: .proteinFatAssistMediumProfile
        ) {
            settings.proteinFatAssistMediumProfile = proteinFatAssistMediumProfile
                .profileDefaulted(for: .medium)
                .sanitized
        }

        if let proteinFatAssistStrongProfile = try? container.decode(
            ProteinFatAssistProfileSettings.self,
            forKey: .proteinFatAssistStrongProfile
        ) {
            settings.proteinFatAssistStrongProfile = proteinFatAssistStrongProfile
                .profileDefaulted(for: .strong)
                .sanitized
        }

        if let proteinFatAssistCustomProfile = try? container.decode(
            ProteinFatAssistProfileSettings.self,
            forKey: .proteinFatAssistCustomProfile
        ) {
            settings.proteinFatAssistCustomProfile = proteinFatAssistCustomProfile
                .profileDefaulted(for: .custom)
                .sanitized
        }

        if let proteinFatAssistBaseDuration = try? container.decode(Decimal.self, forKey: .proteinFatAssistBaseDuration) {
            settings.proteinFatAssistBaseDuration = min(max(proteinFatAssistBaseDuration, 60), 720)
        }

        if let proteinFatAssistMinutesPer10gFat = try? container.decode(
            Decimal.self,
            forKey: .proteinFatAssistMinutesPer10gFat
        ) {
            settings.proteinFatAssistMinutesPer10gFat = min(max(proteinFatAssistMinutesPer10gFat, 0), 120)
        }

        if let proteinFatAssistMinimumDuration = try? container.decode(
            Decimal.self,
            forKey: .proteinFatAssistMinimumDuration
        ) {
            settings.proteinFatAssistMinimumDuration = min(max(proteinFatAssistMinimumDuration, 60), 720)
        }

        if let proteinFatAssistMaximumDefaultDuration = try? container.decode(
            Decimal.self,
            forKey: .proteinFatAssistMaximumDefaultDuration
        ) {
            settings.proteinFatAssistMaximumDefaultDuration = min(max(proteinFatAssistMaximumDefaultDuration, 60), 720)
        }

        if let proteinFatActivityGraphDisplay = try? container.decode(
            ProteinFatActivityGraphDisplay.self,
            forKey: .proteinFatActivityGraphDisplay
        ) {
            settings.proteinFatActivityGraphDisplay = proteinFatActivityGraphDisplay
        }

        if let proteinFatActivityProteinDurationFactor = try? container.decode(
            Decimal.self,
            forKey: .proteinFatActivityProteinDurationFactor
        ) {
            settings.proteinFatActivityProteinDurationFactor = min(max(proteinFatActivityProteinDurationFactor, 0.1), 1)
        }

        if let proteinFatActivityFatPeakPercent = try? container.decode(
            Decimal.self,
            forKey: .proteinFatActivityFatPeakPercent
        ) {
            settings.proteinFatActivityFatPeakPercent = min(max(proteinFatActivityFatPeakPercent, 0.1), 0.9)
        }

        if let proteinFatActivityProteinPeakPercent = try? container.decode(
            Decimal.self,
            forKey: .proteinFatActivityProteinPeakPercent
        ) {
            settings.proteinFatActivityProteinPeakPercent = min(max(proteinFatActivityProteinPeakPercent, 0.1), 0.9)
        }

        if let individualAdjustmentFactor = try? container.decode(Decimal.self, forKey: .individualAdjustmentFactor) {
            settings.individualAdjustmentFactor = individualAdjustmentFactor
        }

        if let fattyMeals = try? container.decode(Bool.self, forKey: .fattyMeals) {
            settings.fattyMeals = fattyMeals
        }

        if let fattyMealFactor = try? container.decode(Decimal.self, forKey: .fattyMealFactor) {
            settings.fattyMealFactor = fattyMealFactor
        }

        if let sweetMeals = try? container.decode(Bool.self, forKey: .sweetMeals) {
            settings.sweetMeals = sweetMeals
        }

        if let sweetMealFactor = try? container.decode(Decimal.self, forKey: .sweetMealFactor) {
            settings.sweetMealFactor = sweetMealFactor
        }

        if let overrideFactor = try? container.decode(Decimal.self, forKey: .overrideFactor) {
            settings.overrideFactor = overrideFactor
        }

        if let minuteInterval = try? container.decode(Decimal.self, forKey: .minuteInterval) {
            settings.minuteInterval = minuteInterval
        }

        if let delay = try? container.decode(Decimal.self, forKey: .delay) {
            settings.delay = delay
        }

        if let notificationsPump = try? container.decode(Bool.self, forKey: .notificationsPump) {
            settings.notificationsPump = notificationsPump
        }

        if let notificationsCgm = try? container.decode(Bool.self, forKey: .notificationsCgm) {
            settings.notificationsCgm = notificationsCgm
        }

        if let notificationsCarb = try? container.decode(Bool.self, forKey: .notificationsCarb) {
            settings.notificationsCarb = notificationsCarb
        }

        if let notificationsAlgorithm = try? container.decode(Bool.self, forKey: .notificationsAlgorithm) {
            settings.notificationsAlgorithm = notificationsAlgorithm
        }

        if let glucoseNotificationsOption = try? container.decode(
            GlucoseNotificationsOption.self,
            forKey: .glucoseNotificationsOption
        ) {
            settings.glucoseNotificationsOption = glucoseNotificationsOption
        }

        if let addSourceInfoToGlucoseNotifications = try? container.decode(
            Bool.self,
            forKey: .addSourceInfoToGlucoseNotifications
        ) {
            settings.addSourceInfoToGlucoseNotifications = addSourceInfoToGlucoseNotifications
        }

        if let lowGlucose = try? container.decode(Decimal.self, forKey: .lowGlucose) {
            settings.lowGlucose = lowGlucose
        }

        if let highGlucose = try? container.decode(Decimal.self, forKey: .highGlucose) {
            settings.highGlucose = highGlucose
        }

        if let carbsRequiredThreshold = try? container.decode(Decimal.self, forKey: .carbsRequiredThreshold) {
            settings.carbsRequiredThreshold = carbsRequiredThreshold
        }

        if let showCarbsRequiredBadge = try? container.decode(Bool.self, forKey: .showCarbsRequiredBadge) {
            settings.showCarbsRequiredBadge = showCarbsRequiredBadge
        }

        if let smoothGlucose = try? container.decode(Bool.self, forKey: .smoothGlucose) {
            settings.smoothGlucose = smoothGlucose
        }

        if let low = try? container.decode(Decimal.self, forKey: .low) {
            settings.low = low
        }

        if let high = try? container.decode(Decimal.self, forKey: .high) {
            settings.high = high
        }

        if let glucoseColorScheme = try? container.decode(GlucoseColorScheme.self, forKey: .glucoseColorScheme) {
            settings.glucoseColorScheme = glucoseColorScheme
        }

        if let xGridLines = try? container.decode(Bool.self, forKey: .xGridLines) {
            settings.xGridLines = xGridLines
        }

        if let yGridLines = try? container.decode(Bool.self, forKey: .yGridLines) {
            settings.yGridLines = yGridLines
        }

        if let showCobIobChart = try? container.decode(Bool.self, forKey: .showCobIobChart) {
            settings.showCobIobChart = showCobIobChart
        }

        if let hideInsulinBadge = try? container.decode(Bool.self, forKey: .hideInsulinBadge) {
            settings.hideInsulinBadge = hideInsulinBadge
        }

        if let allowDilution = try? container.decode(Bool.self, forKey: .allowDilution) {
            settings.allowDilution = allowDilution
        }

        if let insulinConcentration = try? container.decode(Decimal.self, forKey: .insulinConcentration) {
            settings.insulinConcentration = insulinConcentration
        }

        if let rulerMarks = try? container.decode(Bool.self, forKey: .rulerMarks) {
            settings.rulerMarks = rulerMarks
        }

        if let bolusDisplayThreshold = try? container.decode(BolusDisplayThreshold.self, forKey: .bolusDisplayThreshold) {
            settings.bolusDisplayThreshold = bolusDisplayThreshold
        }

        if let forecastDisplayType = try? container.decode(ForecastDisplayType.self, forKey: .forecastDisplayType) {
            settings.forecastDisplayType = forecastDisplayType
        }

        if let eA1cDisplayUnit = try? container.decode(EstimatedA1cDisplayUnit.self, forKey: .eA1cDisplayUnit) {
            settings.eA1cDisplayUnit = eA1cDisplayUnit
        }

        if let maxCarbs = try? container.decode(Decimal.self, forKey: .maxCarbs) {
            settings.maxCarbs = maxCarbs
        }

        if let maxFat = try? container.decode(Decimal.self, forKey: .maxFat) {
            settings.maxFat = maxFat
        }

        if let maxProtein = try? container.decode(Decimal.self, forKey: .maxProtein) {
            settings.maxProtein = maxProtein
        }

        if let confirmBolusFaster = try? container.decode(Bool.self, forKey: .confirmBolusFaster) {
            settings.confirmBolusFaster = confirmBolusFaster
        }

        if let displayPresets = try? container.decode(Bool.self, forKey: .displayPresets) {
            settings.displayPresets = displayPresets
        }

        if let confirmBolus = try? container.decode(Bool.self, forKey: .confirmBolus) {
            settings.confirmBolus = confirmBolus
        }

        if let useLiveActivity = try? container.decode(Bool.self, forKey: .useLiveActivity) {
            settings.useLiveActivity = useLiveActivity
        }

        if let lockScreenView = try? container.decode(LockScreenView.self, forKey: .lockScreenView) {
            settings.lockScreenView = lockScreenView
        }

        if let smartStackView = try? container.decode(LockScreenView.self, forKey: .smartStackView) {
            settings.smartStackView = smartStackView
        }

        if let bolusShortcut = try? container.decode(BolusShortcutLimit.self, forKey: .bolusShortcut) {
            settings.bolusShortcut = bolusShortcut
        }

        if let timeInRangeType = try? container.decode(TimeInRangeType.self, forKey: .timeInRangeType) {
            settings.timeInRangeType = timeInRangeType
        }

        if let requireAdjustmentsConfirmation = try? container.decode(Bool.self, forKey: .requireAdjustmentsConfirmation) {
            settings.requireAdjustmentsConfirmation = requireAdjustmentsConfirmation
        }

        if let garminWatchface = try? container.decode(GarminWatchface.self, forKey: .garminWatchface) {
            settings.garminWatchface = garminWatchface
        }

        if let garminDatafield = try? container.decode(GarminDatafield.self, forKey: .garminDatafield) {
            settings.garminDatafield = garminDatafield
        }

        if let primaryAttributeChoice = try? container
            .decode(GarminPrimaryAttributeChoice.self, forKey: .primaryAttributeChoice)
        {
            settings.primaryAttributeChoice = primaryAttributeChoice
        }

        if let secondaryAttributeChoice = try? container.decode(
            GarminSecondaryAttributeChoice.self,
            forKey: .secondaryAttributeChoice
        ) {
            settings.secondaryAttributeChoice = secondaryAttributeChoice
        }

        if let isWatchfaceDataEnabled = try? container.decode(Bool.self, forKey: .isWatchfaceDataEnabled) {
            settings.isWatchfaceDataEnabled = isWatchfaceDataEnabled
        }

        self = settings
    }
}
