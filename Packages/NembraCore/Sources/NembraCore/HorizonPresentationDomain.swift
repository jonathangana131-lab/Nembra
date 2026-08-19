import Foundation

// MARK: - Truth-bearing metrics

/// The domain that supplied a value shown by Horizon.
///
/// This is provenance for an already-authorized presentation value. It does not
/// promote a display value into telemetry, accepted ride evidence, navigation
/// authority, or verified road coverage.
public enum HorizonMetricAuthority: String, Codable, Equatable, Sendable {
    case vehicleTelemetry
    case acceptedRideLedger
    case persistedVehicleRecord
    case rangeModel
    case navigationProvider
    case verifiedRoadCoverage
}

public enum HorizonMetricUnavailableReason: String, Codable, Equatable, Sendable {
    case noEvidence
    case notYetAvailable
    case stale
    case conflictingEvidence
    case permissionDenied
    case offline
    case unsupported
    case notApplicable
    case requiresReprocessing
}

/// A presentation boundary that makes absence explicit instead of substituting
/// zero, cached placeholder data, or design-reference values.
public enum HorizonMetricPresentation<Value>: Codable, Equatable, Sendable
where Value: Codable & Equatable & Sendable {
    case authoritative(value: Value, authority: HorizonMetricAuthority)
    case unavailable(reason: HorizonMetricUnavailableReason)

    public var authoritativeValue: Value? {
        guard case let .authoritative(value, _) = self else { return nil }
        return value
    }

    public var authority: HorizonMetricAuthority? {
        guard case let .authoritative(_, authority) = self else { return nil }
        return authority
    }

    public var unavailableReason: HorizonMetricUnavailableReason? {
        guard case let .unavailable(reason) = self else { return nil }
        return reason
    }
}

// MARK: - Drive / Navigation / Explore reflow

public enum HorizonCockpitMode: String, Codable, CaseIterable, Equatable, Sendable {
    case drive
    case navigation
    case explore
}

/// Semantic speed placement. Concrete geometry belongs to the SwiftUI layout.
public enum HorizonSpeedReflowRole: String, Codable, Equatable, Sendable {
    case dominantCentered
    case compactLeadingPersistent
}

/// Semantic road-world presentation. This carries no renderer, color, or size.
public enum HorizonRoadWorldReflowRole: String, Codable, Equatable, Sendable {
    case perspectiveDrive
    case expandedNavigation
    case expandedExploration
}

public enum HorizonTransientControlRole: String, Codable, Equatable, Sendable {
    case none
    case maneuver
    case roadDiscovery
}

public struct HorizonCockpitReflow: Codable, Equatable, Sendable {
    public let mode: HorizonCockpitMode
    public let speedRole: HorizonSpeedReflowRole
    public let roadWorldRole: HorizonRoadWorldReflowRole
    public let transientControlRole: HorizonTransientControlRole

    public init(mode: HorizonCockpitMode) {
        self.mode = mode
        switch mode {
        case .drive:
            speedRole = .dominantCentered
            roadWorldRole = .perspectiveDrive
            transientControlRole = .none
        case .navigation:
            speedRole = .compactLeadingPersistent
            roadWorldRole = .expandedNavigation
            transientControlRole = .maneuver
        case .explore:
            speedRole = .compactLeadingPersistent
            roadWorldRole = .expandedExploration
            transientControlRole = .roadDiscovery
        }
    }
}

public enum HorizonModeSelectionResult: Codable, Equatable, Sendable {
    case unchanged(HorizonCockpitReflow)
    case changed(from: HorizonCockpitMode, to: HorizonCockpitMode, reflow: HorizonCockpitReflow)
}

// MARK: - Persistent lower-rail facts

public enum HorizonAutomaticRecordingState: Codable, Equatable, Sendable {
    case readyWhenMoving
    case candidate(candidateID: UUID)
    case recording(rideSessionID: UUID)
    case temporaryGap(rideSessionID: UUID)
    case endingCandidate(rideSessionID: UUID)
    case actionRequired
    case disabled
}

public struct HorizonTodayFacts: Codable, Equatable, Sendable {
    public let localDay: RideLocalDay
    public let distanceMeters: HorizonMetricPresentation<Double>
    public let durationSeconds: HorizonMetricPresentation<Double>
    public let containsRecoveredRideEvidence: Bool

    public init(
        localDay: RideLocalDay,
        distanceMeters: HorizonMetricPresentation<Double>,
        durationSeconds: HorizonMetricPresentation<Double>,
        containsRecoveredRideEvidence: Bool
    ) {
        self.localDay = localDay
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.containsRecoveredRideEvidence = containsRecoveredRideEvidence
    }
}

/// Deliberately separate from `HorizonTodayFacts`: current-ride metrics may
/// reset at a ride boundary while the accepted local-day aggregate may not.
public enum HorizonCurrentRideFacts: Codable, Equatable, Sendable {
    case noCurrentRide
    case current(
        rideSessionID: UUID,
        distanceMeters: HorizonMetricPresentation<Double>,
        durationSeconds: HorizonMetricPresentation<Double>
    )
}

public struct HorizonCityCoverageFacts: Codable, Equatable, Sendable {
    public let evidenceState: RoadCoverageEvidenceState
    public let progressFraction: HorizonMetricPresentation<Double>
    public let verifiedCoveredLengthMeters: HorizonMetricPresentation<Double>
    public let eligibleLengthMeters: HorizonMetricPresentation<Double>
    public let remainingEligibleLengthMeters: HorizonMetricPresentation<Double>

    public init(
        evidenceState: RoadCoverageEvidenceState,
        progressFraction: HorizonMetricPresentation<Double>,
        verifiedCoveredLengthMeters: HorizonMetricPresentation<Double>,
        eligibleLengthMeters: HorizonMetricPresentation<Double>,
        remainingEligibleLengthMeters: HorizonMetricPresentation<Double>
    ) {
        self.evidenceState = evidenceState
        self.progressFraction = progressFraction
        self.verifiedCoveredLengthMeters = verifiedCoveredLengthMeters
        self.eligibleLengthMeters = eligibleLengthMeters
        self.remainingEligibleLengthMeters = remainingEligibleLengthMeters
    }
}

public struct HorizonLowerRailFacts: Codable, Equatable, Sendable {
    public let automaticRecording: HorizonAutomaticRecordingState
    public let today: HorizonTodayFacts
    public let currentRide: HorizonCurrentRideFacts
    public let odometerMeters: HorizonMetricPresentation<Double>
    public let cityCoverage: HorizonCityCoverageFacts

    public init(
        automaticRecording: HorizonAutomaticRecordingState,
        today: HorizonTodayFacts,
        currentRide: HorizonCurrentRideFacts,
        odometerMeters: HorizonMetricPresentation<Double>,
        cityCoverage: HorizonCityCoverageFacts
    ) {
        self.automaticRecording = automaticRecording
        self.today = today
        self.currentRide = currentRide
        self.odometerMeters = odometerMeters
        self.cityCoverage = cityCoverage
    }
}

// MARK: - Navigation overlay

/// Opaque identity for geometry retained by the navigation/MapKit adapter.
/// HorizonCore never fabricates, interpolates, or persists route geometry.
public struct HorizonNavigationRouteReference: Codable, Equatable, Sendable {
    public let providerRouteID: String
    public let geometryRevision: UInt64
    public let updatedAtDate: Date

    public init(providerRouteID: String, geometryRevision: UInt64, updatedAtDate: Date) {
        self.providerRouteID = providerRouteID
        self.geometryRevision = geometryRevision
        self.updatedAtDate = updatedAtDate
    }
}

public struct HorizonNavigationManeuverFacts: Codable, Equatable, Sendable {
    public let instruction: HorizonMetricPresentation<String>
    public let roadName: HorizonMetricPresentation<String>
    public let distanceMeters: HorizonMetricPresentation<Double>
    public let followingManeuverDistanceMeters: HorizonMetricPresentation<Double>

    public init(
        instruction: HorizonMetricPresentation<String>,
        roadName: HorizonMetricPresentation<String>,
        distanceMeters: HorizonMetricPresentation<Double>,
        followingManeuverDistanceMeters: HorizonMetricPresentation<Double>
    ) {
        self.instruction = instruction
        self.roadName = roadName
        self.distanceMeters = distanceMeters
        self.followingManeuverDistanceMeters = followingManeuverDistanceMeters
    }
}

public struct HorizonNavigationArrivalFacts: Codable, Equatable, Sendable {
    public let expectedArrivalDate: HorizonMetricPresentation<Date>
    public let remainingDurationSeconds: HorizonMetricPresentation<Double>
    public let remainingDistanceMeters: HorizonMetricPresentation<Double>

    public init(
        expectedArrivalDate: HorizonMetricPresentation<Date>,
        remainingDurationSeconds: HorizonMetricPresentation<Double>,
        remainingDistanceMeters: HorizonMetricPresentation<Double>
    ) {
        self.expectedArrivalDate = expectedArrivalDate
        self.remainingDurationSeconds = remainingDurationSeconds
        self.remainingDistanceMeters = remainingDistanceMeters
    }
}

public struct HorizonNavigationOverlaySnapshot: Codable, Equatable, Sendable {
    public let route: HorizonNavigationRouteReference
    public let currentPositionSampleID: UUID?
    public let maneuver: HorizonNavigationManeuverFacts
    public let arrival: HorizonNavigationArrivalFacts

    public init(
        route: HorizonNavigationRouteReference,
        currentPositionSampleID: UUID?,
        maneuver: HorizonNavigationManeuverFacts,
        arrival: HorizonNavigationArrivalFacts
    ) {
        self.route = route
        self.currentPositionSampleID = currentPositionSampleID
        self.maneuver = maneuver
        self.arrival = arrival
    }
}

public enum HorizonNavigationOverlayPresentation: Codable, Equatable, Sendable {
    case authoritative(HorizonNavigationOverlaySnapshot)
    case unavailable(HorizonMetricUnavailableReason)
}

// MARK: - Exploration overlay

public enum HorizonVisibleRoadSegmentRole: String, Codable, Equatable, Sendable {
    case eligibleUnexplored
    case acceptedHistoricalCoverage
    case currentDiscovery
}

/// Semantic roles and normalized accepted intervals for a currently visible
/// road. The spatial provider resolves the versioned segment ID to geometry.
public struct HorizonVisibleRoadSegmentOverlay: Codable, Equatable, Sendable {
    public let segmentID: RoadSegmentID
    public let role: HorizonVisibleRoadSegmentRole
    public let intervals: [RoadCoverageInterval]

    public init(
        segmentID: RoadSegmentID,
        role: HorizonVisibleRoadSegmentRole,
        intervals: [RoadCoverageInterval]
    ) {
        self.segmentID = segmentID
        self.role = role
        self.intervals = intervals
    }
}

/// One-shot presentation notice backed directly by a verified ledger delta.
/// The credited distance is `event.newlyVerifiedLengthMeters`; there is no
/// separate display-owned distance that could diverge from accepted evidence.
public struct HorizonTransientRoadDiscoveryNotice: Codable, Equatable, Sendable {
    public let event: RoadDiscoveryEvent
    public let roadName: HorizonMetricPresentation<String>
    public let issuedAtDate: Date

    public init(
        event: RoadDiscoveryEvent,
        roadName: HorizonMetricPresentation<String>,
        issuedAtDate: Date
    ) {
        self.event = event
        self.roadName = roadName
        self.issuedAtDate = issuedAtDate
    }
}

public struct HorizonExplorationOverlaySnapshot: Codable, Equatable, Sendable {
    public let datasetKey: RoadDatasetKey
    public let visibleSegments: [HorizonVisibleRoadSegmentOverlay]
    public let cityCoverage: HorizonCityCoverageFacts
    public let discoveryNotice: HorizonTransientRoadDiscoveryNotice?

    public init(
        datasetKey: RoadDatasetKey,
        visibleSegments: [HorizonVisibleRoadSegmentOverlay],
        cityCoverage: HorizonCityCoverageFacts,
        discoveryNotice: HorizonTransientRoadDiscoveryNotice?
    ) {
        self.datasetKey = datasetKey
        self.visibleSegments = visibleSegments
        self.cityCoverage = cityCoverage
        self.discoveryNotice = discoveryNotice
    }
}

public enum HorizonExplorationOverlayPresentation: Codable, Equatable, Sendable {
    case authoritative(HorizonExplorationOverlaySnapshot)
    case unavailable(HorizonMetricUnavailableReason)
}

// MARK: - Async overlay request fencing

public enum HorizonOverlayKind: String, Codable, Equatable, Sendable {
    case navigation
    case exploration

    public var requiredMode: HorizonCockpitMode {
        switch self {
        case .navigation: .navigation
        case .exploration: .explore
        }
    }
}

public struct HorizonOverlayRequestToken: Codable, Equatable, Hashable, Sendable {
    public let presentationContextID: UUID
    public let kind: HorizonOverlayKind
    public let modeRevision: UInt64
    public let sequence: UInt64

    public init(
        presentationContextID: UUID,
        kind: HorizonOverlayKind,
        modeRevision: UInt64,
        sequence: UInt64
    ) {
        self.presentationContextID = presentationContextID
        self.kind = kind
        self.modeRevision = modeRevision
        self.sequence = sequence
    }
}

public struct HorizonNavigationOverlayUpdate: Codable, Equatable, Sendable {
    public let request: HorizonOverlayRequestToken
    public let presentation: HorizonNavigationOverlayPresentation

    public init(
        request: HorizonOverlayRequestToken,
        presentation: HorizonNavigationOverlayPresentation
    ) {
        self.request = request
        self.presentation = presentation
    }
}

public struct HorizonExplorationOverlayUpdate: Codable, Equatable, Sendable {
    public let request: HorizonOverlayRequestToken
    public let presentation: HorizonExplorationOverlayPresentation

    public init(
        request: HorizonOverlayRequestToken,
        presentation: HorizonExplorationOverlayPresentation
    ) {
        self.request = request
        self.presentation = presentation
    }
}

public enum HorizonOverlayApplyResult: String, Codable, Equatable, Sendable {
    case applied
    case rejectedStale
}

public enum HorizonPresentationDomainError: Error, Codable, Equatable, Sendable {
    case modeRevisionExhausted
    case requestSequenceExhausted
    case requestRequiresActiveMode(expected: HorizonCockpitMode, actual: HorizonCockpitMode)
}

/// Pure presentation coordinator. It selects semantic reflow, persists the one
/// shared battery-primary preference, and fences asynchronous overlay results.
/// It neither obtains nor synthesizes telemetry, routes, ride totals, or road
/// coverage.
public struct HorizonPresentationCoordinator: Codable, Equatable, Sendable {
    public private(set) var mode: HorizonCockpitMode
    public private(set) var batteryPrimaryReadoutState: BatteryPrimaryReadoutState
    public private(set) var navigationOverlay: HorizonNavigationOverlayPresentation?
    public private(set) var explorationOverlay: HorizonExplorationOverlayPresentation?

    public let presentationContextID: UUID
    public private(set) var modeRevision: UInt64

    private var lastRequestSequence: UInt64
    private var latestNavigationRequest: HorizonOverlayRequestToken?
    private var latestExplorationRequest: HorizonOverlayRequestToken?

    public var reflow: HorizonCockpitReflow {
        HorizonCockpitReflow(mode: mode)
    }

    public init(
        presentationContextID: UUID,
        initialMode: HorizonCockpitMode = .drive,
        batteryPrimaryReadoutState: BatteryPrimaryReadoutState = .init(),
        initialRequestSequence: UInt64 = 0
    ) {
        self.presentationContextID = presentationContextID
        mode = initialMode
        self.batteryPrimaryReadoutState = batteryPrimaryReadoutState
        navigationOverlay = nil
        explorationOverlay = nil
        modeRevision = 0
        lastRequestSequence = initialRequestSequence
        latestNavigationRequest = nil
        latestExplorationRequest = nil
    }

    @discardableResult
    public mutating func selectMode(
        _ selectedMode: HorizonCockpitMode
    ) throws -> HorizonModeSelectionResult {
        guard selectedMode != mode else {
            return .unchanged(reflow)
        }
        guard modeRevision < UInt64.max else {
            throw HorizonPresentationDomainError.modeRevisionExhausted
        }

        let priorMode = mode
        mode = selectedMode
        modeRevision += 1

        // Results started for any previous visual world may no longer mutate
        // the selected one, even if their provider work finishes later.
        latestNavigationRequest = nil
        latestExplorationRequest = nil
        navigationOverlay = nil
        explorationOverlay = nil

        return .changed(from: priorMode, to: selectedMode, reflow: reflow)
    }

    @discardableResult
    public mutating func toggleBatteryPrimaryReadout() -> BatteryPrimaryReadoutMode {
        batteryPrimaryReadoutState.toggle()
        return batteryPrimaryReadoutState.mode
    }

    public mutating func beginOverlayRequest(
        for kind: HorizonOverlayKind
    ) throws -> HorizonOverlayRequestToken {
        guard mode == kind.requiredMode else {
            throw HorizonPresentationDomainError.requestRequiresActiveMode(
                expected: kind.requiredMode,
                actual: mode
            )
        }
        guard lastRequestSequence < UInt64.max else {
            throw HorizonPresentationDomainError.requestSequenceExhausted
        }

        lastRequestSequence += 1
        let request = HorizonOverlayRequestToken(
            presentationContextID: presentationContextID,
            kind: kind,
            modeRevision: modeRevision,
            sequence: lastRequestSequence
        )
        switch kind {
        case .navigation:
            latestNavigationRequest = request
        case .exploration:
            latestExplorationRequest = request
        }
        return request
    }

    @discardableResult
    public mutating func applyNavigationUpdate(
        _ update: HorizonNavigationOverlayUpdate
    ) -> HorizonOverlayApplyResult {
        guard mode == .navigation,
              update.request.presentationContextID == presentationContextID,
              update.request.kind == .navigation,
              update.request.modeRevision == modeRevision,
              update.request == latestNavigationRequest else {
            return .rejectedStale
        }

        navigationOverlay = update.presentation
        latestNavigationRequest = nil
        return .applied
    }

    @discardableResult
    public mutating func applyExplorationUpdate(
        _ update: HorizonExplorationOverlayUpdate
    ) -> HorizonOverlayApplyResult {
        guard mode == .explore,
              update.request.presentationContextID == presentationContextID,
              update.request.kind == .exploration,
              update.request.modeRevision == modeRevision,
              update.request == latestExplorationRequest else {
            return .rejectedStale
        }

        explorationOverlay = update.presentation
        latestExplorationRequest = nil
        return .applied
    }
}
