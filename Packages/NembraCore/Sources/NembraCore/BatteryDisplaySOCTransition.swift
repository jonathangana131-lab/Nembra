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
