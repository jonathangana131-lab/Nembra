public enum BatteryPrimaryReadoutMode: String, Codable, CaseIterable, Sendable {
    case percentage
    case estimatedRange

    public mutating func toggle() {
        self = self == .percentage ? .estimatedRange : .percentage
    }
}

public enum BatteryEstimatedRangeDisplay: Equatable, Sendable {
    case valueMiles(Double)
    case learning
    case unavailable
}

public enum BatteryPrimaryReadoutValue: Equatable, Sendable {
    case percentage(Int)
    case estimatedRangeMiles(Double)
    case learningRange
    case unavailable
}

public struct BatteryPrimaryReadoutInputs: Equatable, Sendable {
    /// Display-layer SoC only. This value is never promoted to measured/raw telemetry by this type.
    public var displaySOCPercent: Int?

    /// A range result produced elsewhere by the authoritative range domain.
    /// This type never computes range from battery percentage.
    public var estimatedRange: BatteryEstimatedRangeDisplay

    public init(
        displaySOCPercent: Int?,
        estimatedRange: BatteryEstimatedRangeDisplay
    ) {
        self.displaySOCPercent = displaySOCPercent
        self.estimatedRange = estimatedRange
    }
}

public struct BatteryPrimaryReadoutPresentation: Equatable, Sendable {
    public let mode: BatteryPrimaryReadoutMode
    public let primaryValue: BatteryPrimaryReadoutValue

    /// The battery graphic remains charge-oriented even when the primary number shows range.
    /// `nil` means the presentation layer has no legitimate display SoC to render.
    public let batteryFillPercent: Int?

    public init(
        mode: BatteryPrimaryReadoutMode,
        primaryValue: BatteryPrimaryReadoutValue,
        batteryFillPercent: Int?
    ) {
        self.mode = mode
        self.primaryValue = primaryValue
        self.batteryFillPercent = batteryFillPercent
    }
}

public struct BatteryPrimaryReadoutState: Equatable, Codable, Sendable {
    public var mode: BatteryPrimaryReadoutMode

    public init(mode: BatteryPrimaryReadoutMode = .percentage) {
        self.mode = mode
    }

    /// The normal battery-instrument tap. This changes presentation preference only.
    /// It does not mutate battery evidence, measured SoC, display SoC, or learned range state.
    public mutating func toggle() {
        mode.toggle()
    }

    public func presentation(
        for inputs: BatteryPrimaryReadoutInputs
    ) -> BatteryPrimaryReadoutPresentation {
        let displayPercent = validatedDisplayPercent(inputs.displaySOCPercent)
        let primaryValue: BatteryPrimaryReadoutValue

        switch mode {
        case .percentage:
            if let displayPercent {
                primaryValue = .percentage(displayPercent)
            } else {
                primaryValue = .unavailable
            }

        case .estimatedRange:
            switch inputs.estimatedRange {
            case let .valueMiles(miles) where miles.isFinite && miles >= 0:
                primaryValue = .estimatedRangeMiles(miles)
            case .learning:
                primaryValue = .learningRange
            case .valueMiles, .unavailable:
                primaryValue = .unavailable
            }
        }

        return BatteryPrimaryReadoutPresentation(
            mode: mode,
            primaryValue: primaryValue,
            batteryFillPercent: displayPercent
        )
    }

    private func validatedDisplayPercent(_ percent: Int?) -> Int? {
        guard let percent, (0...100).contains(percent) else {
            return nil
        }
        return percent
    }
}
