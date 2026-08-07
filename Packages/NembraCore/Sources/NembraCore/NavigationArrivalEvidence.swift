public enum NavigationArrivalEvidenceError: Error, Equatable, Sendable {
    case invalidPolicy
    case selectionIdentityMismatch
    case observationWithoutSelectedRoute
    case observationForFutureSelection
    case observationStateMismatch
    case nonMonotonicObservation
    case observationCountExhausted
}

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

/// Process-local, fail-closed destination-arrival evidence for one selected
/// navigation route generation. This reducer never completes rides, mutates
/// measured distance, or converts provider route distance into vehicle telemetry.
public struct NavigationArrivalEvidenceTracker: Sendable {
    public private(set) var state: NavigationArrivalEvidenceState = .idle

    private let policy: NavigationArrivalEvidencePolicy
    private var selectedToken: NavigationGuidanceSelectionToken?
    private var selectedRoute: NavigationRouteSnapshot?
    private var lastAcceptedObservationUptimeNanoseconds: UInt64?

    public init(policy: NavigationArrivalEvidencePolicy) {
        self.policy = policy
    }

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
            let (nextCount, overflow) = existing.qualifyingObservationCount.addingReportingOverflow(1)
            guard !overflow else {
                throw NavigationArrivalEvidenceError.observationCountExhausted
            }
            candidate = NavigationArrivalCandidateEvidence(
                selectionToken: selectedToken,
                firstQualifyingObservationUptimeNanoseconds: existing.firstQualifyingObservationUptimeNanoseconds,
                latestQualifyingObservationUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
                qualifyingObservationCount: nextCount
            )

        case .idle, .awaitingEvidence, .arrived:
            candidate = NavigationArrivalCandidateEvidence(
                selectionToken: selectedToken,
                firstQualifyingObservationUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
                latestQualifyingObservationUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
                qualifyingObservationCount: 1
            )
        }

        let sustainedDuration = candidate.latestQualifyingObservationUptimeNanoseconds - candidate.firstQualifyingObservationUptimeNanoseconds
        lastAcceptedObservationUptimeNanoseconds = observation.receivedAtUptimeNanoseconds

        guard candidate.qualifyingObservationCount >= policy.minimumQualifyingObservationCount,
              sustainedDuration >= policy.minimumSustainedDurationNanoseconds else {
            state = .candidate(candidate)
            return .candidate
        }

        state = .arrived(
            NavigationArrivalConfirmedEvidence(
                selectionToken: selectedToken,
                firstQualifyingObservationUptimeNanoseconds: candidate.firstQualifyingObservationUptimeNanoseconds,
                confirmedAtUptimeNanoseconds: candidate.latestQualifyingObservationUptimeNanoseconds,
                qualifyingObservationCount: candidate.qualifyingObservationCount
            )
        )
        return .arrived
    }

    public mutating func markKnownContinuityGap() {
        guard let selectedToken else { return }
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
                  progress.distanceRemainingOnStepMeters == observation.distanceRemainingOnStepMeters,
                  progress.distanceRemainingOnRouteMeters == observation.distanceRemainingOnRouteMeters,
                  route.steps.indices.contains(progress.currentStepIndex),
                  progress.currentStep == route.steps[progress.currentStepIndex] else {
                throw NavigationArrivalEvidenceError.observationStateMismatch
            }

            let isFinalStep = progress.currentStepIndex == route.steps.index(before: route.steps.endIndex)
            return isFinalStep &&
                progress.distanceRemainingOnStepMeters <= policy.maximumFinalStepDistanceRemainingMeters &&
                progress.distanceRemainingOnRouteMeters <= policy.maximumRouteDistanceRemainingMeters
        }
    }
}
