import NembraCore

public enum NavigationGuidanceAnnouncement: Equatable, Sendable {
    case unavailable(
        routeName: String,
        reason: NavigationGuidanceUnavailableReason
    )
    case maneuver(
        routeName: String,
        instruction: String,
        notice: String?
    )
}

/// Emits accessibility-worthy navigation changes without coupling announcement
/// frequency to GPS/render cadence.
///
/// Changing remaining-distance estimates alone never creates a new announcement.
/// Provider instruction/notice strings are preserved exactly; this tracker does
/// not parse text into maneuver semantics or synthesize turn types.
public struct NavigationGuidanceAnnouncementTracker: Sendable {
    private enum Identity: Equatable, Sendable {
        case unavailable(
            routeName: String,
            reason: NavigationGuidanceUnavailableReason
        )
        case maneuver(
            routeName: String,
            instruction: String,
            notice: String?
        )
    }

    private var lastIdentity: Identity?

    public init() {}

    @discardableResult
    public mutating func update(
        _ guidance: NavigationGuidancePresentation
    ) -> NavigationGuidanceAnnouncement? {
        switch guidance {
        case .inactive:
            lastIdentity = nil
            return nil

        case let .unavailable(routeName, reason):
            let identity = Identity.unavailable(
                routeName: routeName,
                reason: reason
            )
            guard identity != lastIdentity else {
                return nil
            }
            lastIdentity = identity
            return .unavailable(routeName: routeName, reason: reason)

        case let .active(
            routeName,
            currentInstruction,
            currentNotice,
            _,
            _,
            _,
            _
        ):
            let identity = Identity.maneuver(
                routeName: routeName,
                instruction: currentInstruction,
                notice: currentNotice
            )
            guard identity != lastIdentity else {
                return nil
            }
            lastIdentity = identity
            return .maneuver(
                routeName: routeName,
                instruction: currentInstruction,
                notice: currentNotice
            )
        }
    }

    public mutating func reset() {
        lastIdentity = nil
    }
}
