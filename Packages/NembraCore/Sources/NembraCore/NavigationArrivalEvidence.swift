public enum NavigationArrivalEvidenceError: Error, Equatable, Sendable {
    case invalidPolicy
    case selectionIdentityMismatch
    case observationWithoutSelectedRoute
    case observationForFutureSelection
    case observationStateMismatch
    case nonMonotonicObservation
    case observationCountExhausted
}

/// Explicit thresholds for declaring that guidance evidence is near enough to
/// the selected route's destination to become an arrival candidate.
///
/// NembraCore deliberately provides no production defaults. A caller must make
/// the product choice explicitly and may tune it only from legitimate field
/// evidence. The structural requirements below prevent a single location sample
/// or an instantaneous burst from ending navigation.
public struct NavigationArrivalEvidencePolicy: Equatable, Sendable {
    public let maximumFinalStepDistanceRemainingMeters: Double
    public let maximumRouteDistanceRemainingMeters: Double
    public let minimumQualifyingObservationCount: Int
    public let minimumSustainedDurationNanoseconds: UInt64

    public init(
        maximumFinalStepDistanceRemainingMeters: Double,
        maximumRouteDistanceRemainingMeters: Double,
        minimumQualifyingObservationCount: Int,
        minimumSustainedDurationNanoseconds: UInt64
    ) throws {
        guard maximumFinalStepDistanceRemainingMeters.isFinite,
              maximumFinalStepDistanceRemainingMeters >= 0,
              maximumRouteDistanceRemainingMeters.isFinite,
              maximumRouteDistanceRemainingMeters >= 0,
              minimumQualifyingObservationCount >= 2,
              minimumSustainedDurationNanoseconds > 0 else {
            throw NavigationArrivalEvidenceError.invalidPolicy
        }

        self.maximumFinalStepDistanceRemainingMeters = maximumFinalStepDistanceRemainingMeters
        self.maximumRouteDistanceRemainingMeters = maximumRouteDistanceRemainingMeters
        self.minimumQualifyingObservationCount = minimumQualifyingObservationCount
        self.minimumSustainedDurationNanoseconds = minimumSustainedDurationNanoseconds
    }
}

public struct NavigationArrivalCandidateEvidence: Equatable, Sendable {
    public let selectionToken: NavigationGuidanceSelectionToken
    public let firstQualifyingObservationUptimeNanoseconds: UInt64
    public let latestQualifyingObservationUptimeNanoseconds: UInt64
    public let qualifyingObservationCount: Int
}

public struct NavigationArrivalConfirmedEvidence: Equatable, Sendable {
    public let selectionToken: NavigationGuidanceSelectionToken
    public let firstQualifyingObservationUptimeNanoseconds: UInt64
    public let confirmedAtUptimeNanoseconds: UInt64
    public let qualifyingObservationCount: Int
}

/// Process-local arrival evidence for one selected route generation.
///
/// `arrived` is intentionally latched for the selection that earned it. A new
/// route selection or explicit clear starts a new evidence generation. This is
/// navigation evidence only: it never completes a ride, invents route legality,
/// changes measured distance, or turns provider ETA/distance into telemetry.
public enum NavigationArrivalEvidenceState: Equatable, Sendable {
    case idle
    case awaitingEvidence(token: NavigationGuidanceSelectionToken)
    case candidate(NavigationArrivalCandidateEvidence)
    case arrived(NavigationArrivalConfirmedEvidence)
}

public enum NavigationArrivalObservationResult: Equatable, Sendable {
    case ignoredSupersededSelection
    case awaitingEvidence
    case candidate
    case arrived
    case alreadyArrived
}

/// Fail-closed reducer for destination-arrival evidence.
///
/// The caller must first pass the exact token and route from
/// `NavigationGuidanceProgressTracker.select(route:)` to `select(token:route:)`.
/// Accepted guidance observations can then be projected through
/// `observeAccepted(_:resultingGuidanceState:)`. This explicit selection step is
/// what prevents a late callback from an old route generation from advancing
/// arrival after a newer route was selected but before its first location sample.
public struct NavigationArrivalEvidenceTracker: Sendable {
    public private(set) var state: NavigationArrivalEvidenceState = .idle

    private let policy: NavigationArrivalEvidencePolicy
    private var selectedToken: NavigationGuidanceSelectionToken?
    private var selectedRoute: NavigationRouteSnapshot?
    private var lastAcceptedObservationUptimeNanoseconds: UInt64?

    public init(policy: NavigationArrivalEvidencePolicy) {
        self.policy = policy
    }

    /// Returns `false` for a superseded selection token. Repeating the exact
    /// current token+route is idempotent and does not erase candidate/arrival
    /// evidence. Reusing the token for different route facts fails closed.
    @discardableResult
    public mutating func select(
        token: NavigationGuidanceSelectionToken,
        route: NavigationRouteSnapshot
    ) throws -> Bool {
        if let selectedToken {
            if token.sequence < selectedToken.sequence {
                return false
            }
            if token == selectedToken {
                guard selectedRoute == route else {
                    throw NavigationArrivalEvidenceError.selectionIdentityMismatch
                }
                return true
            }
        }

        selectedToken = token
        selectedRoute = route
        lastAcceptedObservationUptimeNanoseconds = nil
        state = .awaitingEvidence(token: token)
        return true
    }

    /// Consumes an observation only after the guidance tracker accepted it.
    /// The resulting guidance state is cross-checked against the observation and
    /// exact selected route so stale or mismatched state cannot become arrival
    /// evidence.
    @discardableResult
    public mutating func observeAccepted(
        _ observation: NavigationGuidanceProgressObservation,
        resultingGuidanceState: NavigationGuidanceProgressState
    ) throws -> NavigationArrivalObservationResult {
        guard let selectedToken, let selectedRoute else {
            throw NavigationArrivalEvidenceError.observationWithoutSelectedRoute
        }

        if observation.selectionToken.sequence < selectedToken.sequence {
            return .ignoredSupersededSelection
        }
        guard observation.selectionToken == selectedToken else {
            throw NavigationArrivalEvidenceError.observationForFutureSelection
        }

        let qualification = try qualification(
            for: observation,
            resultingGuidanceState: resultingGuidanceState,
            selectedRoute: selectedRoute
        )

        if let lastAcceptedObservationUptimeNanoseconds,
           observation.receivedAtUptimeNanoseconds <= lastAcceptedObservationUptimeNanoseconds {
            throw NavigationArrivalEvidenceError.nonMonotonicObservation
        }

        if case .arrived = state {
            lastAcceptedObservationUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
            return .alreadyArrived
        }

        guard qualification else {
            lastAcceptedObservationUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
            state = .awaitingEvidence(token: selectedToken)
            return .awaitingEvidence
        }

        let candidate: NavigationArrivalCandidateEvidence
        switch state {
        case let .candidate(existing):
            let (nextCount, overflow) = existing.qualifyingObservationCount
                .addingReportingOverflow(1)
            guard !overflow else {
                throw NavigationArrivalEvidenceError.observationCountExhausted
            }
            candidate = NavigationArrivalCandidateEvidence(
                selectionToken: selectedToken,
                firstQualifyingObservationUptimeNanoseconds:
                    existing.firstQualifyingObservationUptimeNanoseconds,
                latestQualifyingObservationUptimeNanoseconds:
                    observation.receivedAtUptimeNanoseconds,
                qualifyingObservationCount: nextCount
            )

        case .idle, .awaitingEvidence, .arrived:
            candidate = NavigationArrivalCandidateEvidence(
                selectionToken: selectedToken,
                firstQualifyingObservationUptimeNanoseconds:
                    observation.receivedAtUptimeNanoseconds,
                latestQualifyingObservationUptimeNanoseconds:
                    observation.receivedAtUptimeNanoseconds,
                qualifyingObservationCount: 1
            )
        }

        let sustainedDuration =
            candidate.latestQualifyingObservationUptimeNanoseconds -
            candidate.firstQualifyingObservationUptimeNanoseconds

        lastAcceptedObservationUptimeNanoseconds = observation.receivedAtUptimeNanoseconds

        guard candidate.qualifyingObservationCount >= policy.minimumQualifyingObservationCount,
              sustainedDuration >= policy.minimumSustainedDurationNanoseconds else {
            state = .candidate(candidate)
            return .candidate
        }

        state = .arrived(
            NavigationArrivalConfirmedEvidence(
                selectionToken: selectedToken,
                firstQualifyingObservationUptimeNanoseconds:
                    candidate.firstQualifyingObservationUptimeNanoseconds,
                confirmedAtUptimeNanoseconds:
                    candidate.latestQualifyingObservationUptimeNanoseconds,
                qualifyingObservationCount: candidate.qualifyingObservationCount
            )
        )
        return .arrived
    }

    /// A known guidance/location continuity gap invalidates an in-flight arrival
    /// candidate. Confirmed arrival remains latched for the current selection.
    public mutating func markKnownContinuityGap() {
        guard let selectedToken else {
            return
        }
        guard case .arrived = state else {
            state = .awaitingEvidence(token: selectedToken)
            return
        }
    }

    public mutating func clearSelection() {
        selectedToken = nil
        selectedRoute = nil
        lastAcceptedObservationUptimeNanoseconds = nil
        state = .idle
    }

    private func qualification(
        for observation: NavigationGuidanceProgressObservation,
        resultingGuidanceState: NavigationGuidanceProgressState,
        selectedRoute: NavigationRouteSnapshot
    ) throws -> Bool {
        switch resultingGuidanceState {
        case .idle:
            throw NavigationArrivalEvidenceError.observationStateMismatch

        case let .unavailable(token, route, reason):
            // The guidance reducer owns why accepted evidence became unavailable.
            // A raw observation may itself be unconfident, or it may be confident
            // but fail a higher-level invariant such as backward-step regression.
            // Arrival must honor the accepted ambiguous state in either case.
            guard token == observation.selectionToken,
                  route == selectedRoute,
                  reason == .ambiguousProgress else {
                throw NavigationArrivalEvidenceError.observationStateMismatch
            }
            return false

        case let .active(token, route, progress):
            guard token == observation.selectionToken,
                  route == selectedRoute,
                  observation.isProgressAssignmentConfident,
                  progress.currentStepIndex == observation.stepIndex,
                  progress.distanceRemainingOnStepMeters ==
                      observation.distanceRemainingOnStepMeters,
                  progress.distanceRemainingOnRouteMeters ==
                      observation.distanceRemainingOnRouteMeters,
                  route.steps.indices.contains(progress.currentStepIndex),
                  progress.currentStep == route.steps[progress.currentStepIndex] else {
                throw NavigationArrivalEvidenceError.observationStateMismatch
            }

            let isFinalStep = progress.currentStepIndex == route.steps.index(before: route.steps.endIndex)
            return isFinalStep &&
                progress.distanceRemainingOnStepMeters <=
                    policy.maximumFinalStepDistanceRemainingMeters &&
                progress.distanceRemainingOnRouteMeters <=
                    policy.maximumRouteDistanceRemainingMeters
        }
    }
}
