public enum BatteryPrimaryReadoutMode: String, Codable, CaseIterable, Sendable {
    case percentage
    case estimatedRange

    public mutating func toggle() {
        self = self == .percentage ? .estimatedRange : .percentage
    }
}

public enum BatteryEstimatedRangeDisplay: Equatable, Sendable {
    case valueMeters(Double)
    case learning
    case unavailable
}

public enum BatteryPrimaryReadoutValue: Equatable, Sendable {
    case percentage(Int)
    case estimatedRangeMeters(Double)
    case learningRange
    case unavailable
}

public struct BatteryPrimaryReadoutInputs: Equatable, Sendable {
    /// Display-layer SoC only. This value is never promoted to measured/raw telemetry by this type.
    public var displaySOCPercent: Int?

    /// A unit-neutral range result produced elsewhere by the authoritative range domain.
    /// This type never computes range from battery percentage or chooses user-facing units.
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
            case let .valueMeters(meters) where meters.isFinite && meters >= 0:
                primaryValue = .estimatedRangeMeters(meters)
            case .learning:
                primaryValue = .learningRange
            case .valueMeters, .unavailable:
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

public enum BatteryDisplaySOCFrameRole: Equatable, Sendable {
    /// A visual-only integer traversed between display endpoints.
    /// It must never be persisted or interpreted as a measured/estimated battery observation.
    case presentationIntermediate

    /// The final display value supplied by the caller.
    /// This role says nothing about whether that value is measured or estimated upstream.
    case targetDisplayValue
}

public struct BatteryDisplaySOCFrame: Equatable, Sendable {
    public let percent: Int
    public let role: BatteryDisplaySOCFrameRole

    public init(percent: Int, role: BatteryDisplaySOCFrameRole) {
        self.percent = percent
        self.role = role
    }
}

public enum BatteryDisplaySOCTransition: Equatable, Sendable {
    /// No legitimate target display SoC exists. The presentation should show its unavailable state.
    case clear

    /// A legitimate target exists but there is no useful integer transition to animate.
    case snap(Int)

    /// Ordered visual-only frames excluding the already-rendered start and including the target.
    case animate([BatteryDisplaySOCFrame])
}

public enum BatteryDisplaySOCTransitionPlanner {
    /// Builds presentation-only integer frames between two already-classified display SoC values.
    ///
    /// This type deliberately does not know whether either endpoint came from measured or estimated
    /// evidence. It never creates battery evidence; callers must keep that truth classification in
    /// the battery domain that supplied `targetDisplayPercent`.
    public static func plan(
        from currentDisplayPercent: Int?,
        to targetDisplayPercent: Int?
    ) -> BatteryDisplaySOCTransition {
        guard let targetDisplayPercent, isValidPercent(targetDisplayPercent) else {
            return .clear
        }

        guard let currentDisplayPercent, isValidPercent(currentDisplayPercent) else {
            return .snap(targetDisplayPercent)
        }

        guard currentDisplayPercent != targetDisplayPercent else {
            return .snap(targetDisplayPercent)
        }

        let direction = targetDisplayPercent > currentDisplayPercent ? 1 : -1
        var frames: [BatteryDisplaySOCFrame] = []
        frames.reserveCapacity(abs(targetDisplayPercent - currentDisplayPercent))

        var percent = currentDisplayPercent + direction
        while percent != targetDisplayPercent {
            frames.append(
                BatteryDisplaySOCFrame(
                    percent: percent,
                    role: .presentationIntermediate
                )
            )
            percent += direction
        }

        frames.append(
            BatteryDisplaySOCFrame(
                percent: targetDisplayPercent,
                role: .targetDisplayValue
            )
        )

        return .animate(frames)
    }

    private static func isValidPercent(_ percent: Int) -> Bool {
        (0...100).contains(percent)
    }
}
