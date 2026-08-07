public enum NavigationGuidanceProgressError: Error, Equatable, Sendable {
    case invalidObservation
    case invalidStepIndex
    case nonMonotonicObservation
    case selectionSequenceExhausted
}

public struct NavigationGuidanceSelectionToken: Equatable, Sendable {
    public let sequence: UInt64

    fileprivate init(sequence: UInt64) {
        self.sequence = sequence
    }
}

public enum NavigationGuidanceUnavailableReason: Equatable, Sendable {
    case awaitingEvidence
    case ambiguousProgress
    case continuityGap
}

/// A progress observation produced only after accepted phone-location evidence
/// has been compared with the currently selected route geometry by a future
/// guidance geometry layer. It is presentation/navigation evidence, never ride
/// telemetry and never a replacement for the accepted GPS-distance pipeline.
public struct NavigationGuidanceProgressObservation: Equatable, Sendable {
    public let selectionToken: NavigationGuidanceSelectionToken
    public let receivedAtUptimeNanoseconds: UInt64
    public let stepIndex: Int
    public let distanceRemainingOnStepMeters: Double
    public let distanceRemainingOnRouteMeters: Double
    public let isProgressAssignmentConfident: Bool

    public init(
        selectionToken: NavigationGuidanceSelectionToken,
        receivedAtUptimeNanoseconds: UInt64,
        stepIndex: Int,
        distanceRemainingOnStepMeters: Double,
        distanceRemainingOnRouteMeters: Double,
        isProgressAssignmentConfident: Bool
    ) throws {
        guard stepIndex >= 0,
              distanceRemainingOnStepMeters.isFinite,
              distanceRemainingOnStepMeters >= 0,
              distanceRemainingOnRouteMeters.isFinite,
              distanceRemainingOnRouteMeters >= 0,
              distanceRemainingOnStepMeters <= distanceRemainingOnRouteMeters else {
            throw NavigationGuidanceProgressError.invalidObservation
        }

        self.selectionToken = selectionToken
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.stepIndex = stepIndex
        self.distanceRemainingOnStepMeters = distanceRemainingOnStepMeters
        self.distanceRemainingOnRouteMeters = distanceRemainingOnRouteMeters
        self.isProgressAssignmentConfident = isProgressAssignmentConfident
    }
}

public struct NavigationGuidanceActiveProgress: Equatable, Sendable {
    public let currentStepIndex: Int
    public let currentStep: NavigationRouteStepSnapshot
    public let nextStep: NavigationRouteStepSnapshot?
    public let distanceRemainingOnStepMeters: Double
    public let distanceRemainingOnRouteMeters: Double
}

public enum NavigationGuidanceProgressState: Equatable, Sendable {
    case idle
    case unavailable(
        token: NavigationGuidanceSelectionToken,
        route: NavigationRouteSnapshot,
        reason: NavigationGuidanceUnavailableReason
    )
    case active(
        token: NavigationGuidanceSelectionToken,
        route: NavigationRouteSnapshot,
        progress: NavigationGuidanceActiveProgress
    )
}

/// Platform-neutral guidance-state reducer above route geometry matching.
///
/// Selection tokens isolate route generations so late observations for a prior
/// route cannot publish onto a newly selected route. Process-local monotonic
/// uptime rejects re-ordered callbacks within the selected route generation.
/// Once confident evidence advances to a later provider step, a newer match to
/// an earlier step fails current progress closed instead of resurrecting an old
/// maneuver. No meter-based backward-progress tolerance is guessed here; normal
/// same-step distance jitter remains a geometry/presentation concern.
/// This type deliberately does not snap coordinates, compute geometry, reroute,
/// mutate ride distance, or infer maneuver semantics from localized text.
public struct NavigationGuidanceProgressTracker: Sendable {
    public private(set) var state: NavigationGuidanceProgressState = .idle
    private var lastSelectionSequence: UInt64
    private var lastAcceptedObservationUptimeNanoseconds: UInt64?
    private var highestConfidentStepIndex: Int?

    public init() {
        lastSelectionSequence = 0
        highestConfidentStepIndex = nil
    }

    init(initialSelectionSequence: UInt64) {
        lastSelectionSequence = initialSelectionSequence
        highestConfidentStepIndex = nil
    }

    @discardableResult
    public mutating func select(
        route: NavigationRouteSnapshot
    ) throws -> NavigationGuidanceSelectionToken {
        guard lastSelectionSequence < UInt64.max else {
            throw NavigationGuidanceProgressError.selectionSequenceExhausted
        }

        lastSelectionSequence += 1
        let token = NavigationGuidanceSelectionToken(sequence: lastSelectionSequence)
        lastAcceptedObservationUptimeNanoseconds = nil
        highestConfidentStepIndex = nil
        state = .unavailable(token: token, route: route, reason: .awaitingEvidence)
        return token
    }

    /// Returns `false` when the observation belongs to a superseded route
    /// selection. Invalid observations for the current selection throw without
    /// partially mutating state.
    @discardableResult
    public mutating func observe(
        _ observation: NavigationGuidanceProgressObservation
    ) throws -> Bool {
        let token: NavigationGuidanceSelectionToken
        let route: NavigationRouteSnapshot

        switch state {
        case .idle:
            return false
        case let .unavailable(currentToken, currentRoute, _),
             let .active(currentToken, currentRoute, _):
            token = currentToken
            route = currentRoute
        }

        guard observation.selectionToken == token else {
            return false
        }

        if let lastAcceptedObservationUptimeNanoseconds,
           observation.receivedAtUptimeNanoseconds <= lastAcceptedObservationUptimeNanoseconds {
            throw NavigationGuidanceProgressError.nonMonotonicObservation
        }

        guard route.steps.indices.contains(observation.stepIndex) else {
            throw NavigationGuidanceProgressError.invalidStepIndex
        }

        let currentStep = route.steps[observation.stepIndex]
        guard observation.distanceRemainingOnStepMeters <= currentStep.distanceMeters,
              observation.distanceRemainingOnRouteMeters <= route.distanceMeters else {
            throw NavigationGuidanceProgressError.invalidObservation
        }

        lastAcceptedObservationUptimeNanoseconds = observation.receivedAtUptimeNanoseconds

        guard observation.isProgressAssignmentConfident else {
            state = .unavailable(token: token, route: route, reason: .ambiguousProgress)
            return true
        }

        if let highestConfidentStepIndex,
           observation.stepIndex < highestConfidentStepIndex {
            state = .unavailable(token: token, route: route, reason: .ambiguousProgress)
            return true
        }
        highestConfidentStepIndex = observation.stepIndex

        let nextIndex = observation.stepIndex + 1
        let nextStep = route.steps.indices.contains(nextIndex) ? route.steps[nextIndex] : nil
        state = .active(
            token: token,
            route: route,
            progress: NavigationGuidanceActiveProgress(
                currentStepIndex: observation.stepIndex,
                currentStep: currentStep,
                nextStep: nextStep,
                distanceRemainingOnStepMeters: observation.distanceRemainingOnStepMeters,
                distanceRemainingOnRouteMeters: observation.distanceRemainingOnRouteMeters
            )
        )
        return true
    }

    /// Known location/guidance continuity loss invalidates the displayed route
    /// progress immediately. The selected route remains available for rendering,
    /// while no current step/distance is claimed until fresh accepted evidence.
    public mutating func markKnownContinuityGap() {
        switch state {
        case .idle:
            return
        case let .unavailable(token, route, _),
             let .active(token, route, _):
            state = .unavailable(token: token, route: route, reason: .continuityGap)
        }
    }

    public mutating func clearSelection() {
        state = .idle
        lastAcceptedObservationUptimeNanoseconds = nil
        highestConfidentStepIndex = nil
    }
}
