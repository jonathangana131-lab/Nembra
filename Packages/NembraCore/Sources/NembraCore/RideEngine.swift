import Foundation

public enum RideEngineError: Error, Equatable, Sendable {
    case invalidPolicy
    case invalidObservation
    case invalidRecovery
    case nonMonotonicObservation
}

/// Detection constants are injected. There is deliberately no MAXSHOT-specific
/// default until real hardware traces justify one.
public struct RideDetectionPolicy: Equatable, Sendable {
    public let candidateSpeedKilometersPerHour: Double
    public let confirmationSpeedKilometersPerHour: Double
    public let confirmationDurationNanoseconds: UInt64
    public let confirmationOdometerDeltaKilometers: Double
    public let confirmationGPSDistanceMeters: Double
    public let endingDurationNanoseconds: UInt64
    public let maximumSpeedSampleAgeNanoseconds: UInt64

    public init(
        candidateSpeedKilometersPerHour: Double,
        confirmationSpeedKilometersPerHour: Double,
        confirmationDurationNanoseconds: UInt64,
        confirmationOdometerDeltaKilometers: Double,
        confirmationGPSDistanceMeters: Double,
        endingDurationNanoseconds: UInt64,
        maximumSpeedSampleAgeNanoseconds: UInt64
    ) throws {
        guard candidateSpeedKilometersPerHour.isFinite,
              confirmationSpeedKilometersPerHour.isFinite,
              confirmationOdometerDeltaKilometers.isFinite,
              confirmationGPSDistanceMeters.isFinite,
              candidateSpeedKilometersPerHour > 0,
              confirmationSpeedKilometersPerHour >= candidateSpeedKilometersPerHour,
              confirmationOdometerDeltaKilometers > 0,
              confirmationGPSDistanceMeters > 0,
              endingDurationNanoseconds > 0,
              maximumSpeedSampleAgeNanoseconds > 0 else {
            throw RideEngineError.invalidPolicy
        }

        self.candidateSpeedKilometersPerHour = candidateSpeedKilometersPerHour
        self.confirmationSpeedKilometersPerHour = confirmationSpeedKilometersPerHour
        self.confirmationDurationNanoseconds = confirmationDurationNanoseconds
        self.confirmationOdometerDeltaKilometers = confirmationOdometerDeltaKilometers
        self.confirmationGPSDistanceMeters = confirmationGPSDistanceMeters
        self.endingDurationNanoseconds = endingDurationNanoseconds
        self.maximumSpeedSampleAgeNanoseconds = maximumSpeedSampleAgeNanoseconds
    }
}

/// One quality-screened input point for the automatic ride state machine.
///
/// `speedSample` may come from BLE, GPS, or motion assist. Only fresh absolute
/// BLE/GPS measurements are allowed to confirm or sustain a ride. Motion may
/// wake a candidate but cannot establish absolute vehicle speed on its own.
///
/// `qualityScreenedGPSDistanceDeltaMeters` is an incremental route-distance
/// delta since the previous observation, after the location layer has rejected
/// unusable points. The ride engine accumulates these deltas itself so a single
/// location update can never masquerade as the entire route distance.
public struct RideObservation: Equatable, Sendable {
    public let receivedAtUptimeNanoseconds: UInt64
    public let receivedAtDate: Date
    public let connection: VehicleConnectionState
    public let speedSample: SpeedTelemetrySample?
    public let odometerKilometers: Double?
    public let qualityScreenedGPSDistanceDeltaMeters: Double?
    public let motionIndicatesMovement: Bool

    public init(
        receivedAtUptimeNanoseconds: UInt64,
        receivedAtDate: Date,
        connection: VehicleConnectionState,
        speedSample: SpeedTelemetrySample? = nil,
        odometerKilometers: Double? = nil,
        qualityScreenedGPSDistanceDeltaMeters: Double? = nil,
        motionIndicatesMovement: Bool = false
    ) throws {
        guard receivedAtDate.timeIntervalSinceReferenceDate.isFinite else {
            throw RideEngineError.invalidObservation
        }
        if let odometerKilometers {
            guard odometerKilometers.isFinite, odometerKilometers >= 0 else {
                throw RideEngineError.invalidObservation
            }
        }
        if let qualityScreenedGPSDistanceDeltaMeters {
            guard qualityScreenedGPSDistanceDeltaMeters.isFinite,
                  qualityScreenedGPSDistanceDeltaMeters >= 0 else {
                throw RideEngineError.invalidObservation
            }
        }
        if let speedSample,
           speedSample.receivedAtUptimeNanoseconds > receivedAtUptimeNanoseconds {
            throw RideEngineError.invalidObservation
        }

        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.receivedAtDate = receivedAtDate
        self.connection = connection
        self.speedSample = speedSample
        self.odometerKilometers = odometerKilometers
        self.qualityScreenedGPSDistanceDeltaMeters = qualityScreenedGPSDistanceDeltaMeters
        self.motionIndicatesMovement = motionIndicatesMovement
    }

    public var isVehicleConnected: Bool {
        connection == .connected
    }
}

public struct RideCandidate: Equatable, Sendable {
    public let beganAtUptimeNanoseconds: UInt64
    public let beganAtDate: Date
    /// The first odometer value actually observed during this candidate.
    /// It may be established after the candidate starts; it is never backfilled
    /// to pretend mileage was observed before it really was.
    public var startingOdometerKilometers: Double?
    public var latestOdometerKilometers: Double?
    public var accumulatedGPSDistanceMeters: Double

    public init(
        beganAtUptimeNanoseconds: UInt64,
        beganAtDate: Date,
        startingOdometerKilometers: Double?,
        latestOdometerKilometers: Double?,
        accumulatedGPSDistanceMeters: Double
    ) {
        self.beganAtUptimeNanoseconds = beganAtUptimeNanoseconds
        self.beganAtDate = beganAtDate
        self.startingOdometerKilometers = startingOdometerKilometers
        self.latestOdometerKilometers = latestOdometerKilometers
        self.accumulatedGPSDistanceMeters = accumulatedGPSDistanceMeters
    }
}

public enum RideSessionContinuity: String, Codable, Equatable, Sendable {
    case uninterruptedProcess
    case recoveredCheckpoint
}

public struct ActiveRideSession: Equatable, Sendable {
    public let id: UUID
    /// Process-local monotonic timestamps exist only for sessions observed in
    /// this runtime. They are nil after checkpoint recovery because an uptime
    /// value from another process/boot epoch cannot be represented truthfully.
    public let beganAtUptimeNanoseconds: UInt64?
    public let beganAtDate: Date
    public let confirmedAtUptimeNanoseconds: UInt64?
    public let confirmedAtDate: Date
    /// First odometer actually observed while this ride was being tracked.
    /// This can be established after confirmation if earlier samples were absent.
    public var startingOdometerKilometers: Double?
    public var latestOdometerKilometers: Double?
    /// Accumulated quality-screened GPS route distance. This remains evidence,
    /// not the final reconciled ride distance.
    public var accumulatedGPSDistanceMeters: Double
    /// Whether the session has remained in one process/boot epoch or was
    /// reconstructed from a durable wall-clock checkpoint.
    public let continuity: RideSessionContinuity

    public init(
        id: UUID,
        beganAtUptimeNanoseconds: UInt64?,
        beganAtDate: Date,
        confirmedAtUptimeNanoseconds: UInt64?,
        confirmedAtDate: Date,
        startingOdometerKilometers: Double?,
        latestOdometerKilometers: Double?,
        accumulatedGPSDistanceMeters: Double,
        continuity: RideSessionContinuity = .uninterruptedProcess
    ) {
        self.id = id
        self.beganAtUptimeNanoseconds = beganAtUptimeNanoseconds
        self.beganAtDate = beganAtDate
        self.confirmedAtUptimeNanoseconds = confirmedAtUptimeNanoseconds
        self.confirmedAtDate = confirmedAtDate
        self.startingOdometerKilometers = startingOdometerKilometers
        self.latestOdometerKilometers = latestOdometerKilometers
        self.accumulatedGPSDistanceMeters = accumulatedGPSDistanceMeters
        self.continuity = continuity
    }
}

public struct TemporarilyDisconnectedRide: Equatable, Sendable {
    public var session: ActiveRideSession
    public let disconnectedAtUptimeNanoseconds: UInt64
    public let disconnectedAtDate: Date
}

public struct RideEndingCandidate: Equatable, Sendable {
    public var session: ActiveRideSession
    public let beganAtUptimeNanoseconds: UInt64
    public let beganAtDate: Date
}

public enum RideEnginePhase: Equatable, Sendable {
    case idle
    case candidate(RideCandidate)
    case active(ActiveRideSession)
    case temporarilyDisconnected(TemporarilyDisconnectedRide)
    case endingCandidate(RideEndingCandidate)
}

public enum CompletedRideEvidenceError: Error, Equatable, Sendable {
    case invalidEvidence
}

public struct CompletedRideEvidence: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let beganAtDate: Date
    public let confirmedAtDate: Date
    public let endedAtDate: Date
    public let startingOdometerKilometers: Double?
    public let endingOdometerKilometers: Double?
    public let qualityScreenedGPSDistanceMeters: Double
    public let continuity: RideSessionContinuity
    /// Durable transport-continuity provenance for the confirmed ride interval.
    /// This is deliberately not collapsed to a Bool because old/recovered
    /// evidence may be unable to prove whether a disconnect occurred.
    public let transportGapEvidence: RideTransportGapEvidence

    /// Completed evidence validates durable numeric invariants at construction and
    /// decoding boundaries. Wall-clock ordering is intentionally not enforced:
    /// the system clock can legitimately move while a ride is active, while the
    /// ride engine uses monotonic uptime for in-process ordering.
    public init(
        sessionID: UUID,
        beganAtDate: Date,
        confirmedAtDate: Date,
        endedAtDate: Date,
        startingOdometerKilometers: Double?,
        endingOdometerKilometers: Double?,
        qualityScreenedGPSDistanceMeters: Double,
        continuity: RideSessionContinuity,
        transportGapEvidence: RideTransportGapEvidence = .unknown
    ) throws {
        guard beganAtDate.timeIntervalSinceReferenceDate.isFinite,
              confirmedAtDate.timeIntervalSinceReferenceDate.isFinite,
              endedAtDate.timeIntervalSinceReferenceDate.isFinite,
              qualityScreenedGPSDistanceMeters.isFinite,
              qualityScreenedGPSDistanceMeters >= 0,
              !(continuity == .recoveredCheckpoint && transportGapEvidence == .noneObserved) else {
            // A recovered ride contains a known unobserved process interval, so
            // it cannot truthfully claim whole-ride no-disconnect observation.
            throw CompletedRideEvidenceError.invalidEvidence
        }

        switch (startingOdometerKilometers, endingOdometerKilometers) {
        case (nil, nil):
            break
        case let (.some(start), .some(end)):
            guard start.isFinite, start >= 0, end.isFinite, end >= start else {
                throw CompletedRideEvidenceError.invalidEvidence
            }
        default:
            throw CompletedRideEvidenceError.invalidEvidence
        }

        self.sessionID = sessionID
        self.beganAtDate = beganAtDate
        self.confirmedAtDate = confirmedAtDate
        self.endedAtDate = endedAtDate
        self.startingOdometerKilometers = startingOdometerKilometers
        self.endingOdometerKilometers = endingOdometerKilometers
        self.qualityScreenedGPSDistanceMeters = qualityScreenedGPSDistanceMeters
        self.continuity = continuity
        self.transportGapEvidence = transportGapEvidence
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case beganAtDate
        case confirmedAtDate
        case endedAtDate
        case startingOdometerKilometers
        case endingOdometerKilometers
        case qualityScreenedGPSDistanceMeters
        case continuity
        case transportGapEvidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                sessionID: container.decode(UUID.self, forKey: .sessionID),
                beganAtDate: container.decode(Date.self, forKey: .beganAtDate),
                confirmedAtDate: container.decode(Date.self, forKey: .confirmedAtDate),
                endedAtDate: container.decode(Date.self, forKey: .endedAtDate),
                startingOdometerKilometers: container.decodeIfPresent(Double.self, forKey: .startingOdometerKilometers),
                endingOdometerKilometers: container.decodeIfPresent(Double.self, forKey: .endingOdometerKilometers),
                qualityScreenedGPSDistanceMeters: container.decode(Double.self, forKey: .qualityScreenedGPSDistanceMeters),
                continuity: container.decode(RideSessionContinuity.self, forKey: .continuity),
                transportGapEvidence: try container.decodeIfPresent(
                    RideTransportGapEvidence.self,
                    forKey: .transportGapEvidence
                ) ?? .unknown
            )
        } catch CompletedRideEvidenceError.invalidEvidence {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Completed ride evidence contains invalid durable values."
                )
            )
        }
    }

    public var odometerDeltaKilometers: Double? {
        guard let start = startingOdometerKilometers,
              let end = endingOdometerKilometers,
              end >= start else {
            return nil
        }
        return end - start
    }
}

public enum RideEngineEvent: Equatable, Sendable {
    case candidateStarted
    case candidateCancelled
    case rideStarted(ActiveRideSession)
    case rideTemporarilyDisconnected(UUID)
    case rideResumed(UUID)
    case endingCandidateStarted(UUID)
    case rideEnded(CompletedRideEvidence)
}

public struct RideEngineUpdate: Equatable, Sendable {
    public let phase: RideEnginePhase
    public let events: [RideEngineEvent]
}

/// Deterministic automatic ride state machine for a supplied observation stream.
///
/// The engine owns ride continuity, not a SwiftUI screen. A transport drop after
/// confirmation moves to `temporarilyDisconnected` and never ends the ride by
/// itself. Reconnection either resumes movement or starts an ending candidate.
/// Session identity generation is injected so replay tests can be deterministic.
public struct RideEngine: Sendable {
    public private(set) var phase: RideEnginePhase = .idle

    private let policy: RideDetectionPolicy
    private let makeSessionID: @Sendable () -> UUID
    private var lastObservationUptimeNanoseconds: UInt64?
    private var lastObservationDate: Date?
    /// Session-scoped transport provenance is kept beside the phase rather than
    /// inside UI-facing session identity. It is committed transactionally with
    /// each successful ingest and cleared when the ride completes.
    private var transportGapEvidence: RideTransportGapEvidence?

    public init(
        policy: RideDetectionPolicy,
        makeSessionID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.policy = policy
        self.makeSessionID = makeSessionID
    }

    public mutating func ingest(_ observation: RideObservation) throws -> RideEngineUpdate {
        if let lastObservationUptimeNanoseconds,
           observation.receivedAtUptimeNanoseconds <= lastObservationUptimeNanoseconds {
            throw RideEngineError.nonMonotonicObservation
        }

        var nextPhase = phase
        var events: [RideEngineEvent] = []
        var nextTransportGapEvidence = transportGapEvidence

        switch phase {
        case .idle:
            if observation.isVehicleConnected,
               movementHint(in: observation, previousOdometer: nil, allowMotion: true) {
                let candidate = try makeCandidate(from: observation)
                if policy.confirmationDurationNanoseconds == 0,
                   strongMovement(in: observation, candidate: candidate) {
                    let session = makeSession(from: candidate, confirmation: observation)
                    nextPhase = .active(session)
                    nextTransportGapEvidence = .noneObserved
                    events = [.candidateStarted, .rideStarted(session)]
                } else {
                    nextPhase = .candidate(candidate)
                    events = [.candidateStarted]
                }
            }

        case .candidate(var candidate):
            guard observation.isVehicleConnected else {
                nextPhase = .idle
                events = [.candidateCancelled]
                break
            }

            let previousOdometer = candidate.latestOdometerKilometers
            try updateCandidateEvidence(&candidate, from: observation)

            let hasMovementHint = movementHint(
                in: observation,
                previousOdometer: previousOdometer,
                allowMotion: true
            )
            let hasStrongMovement = strongMovement(in: observation, candidate: candidate)

            guard hasMovementHint || hasStrongMovement else {
                nextPhase = .idle
                events = [.candidateCancelled]
                break
            }

            let elapsed = observation.receivedAtUptimeNanoseconds - candidate.beganAtUptimeNanoseconds
            if elapsed >= policy.confirmationDurationNanoseconds, hasStrongMovement {
                let session = makeSession(from: candidate, confirmation: observation)
                nextPhase = .active(session)
                nextTransportGapEvidence = .noneObserved
                events = [.rideStarted(session)]
            } else {
                nextPhase = .candidate(candidate)
            }

        case .active(var session):
            let previousOdometer = session.latestOdometerKilometers
            try updateSessionEvidence(&session, from: observation)

            if !observation.isVehicleConnected {
                nextTransportGapEvidence = .observed
                nextPhase = .temporarilyDisconnected(
                    TemporarilyDisconnectedRide(
                        session: session,
                        disconnectedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
                        disconnectedAtDate: observation.receivedAtDate
                    )
                )
                events = [.rideTemporarilyDisconnected(session.id)]
            } else if movementHint(
                in: observation,
                previousOdometer: previousOdometer,
                allowMotion: false
            ) {
                nextPhase = .active(session)
            } else {
                nextPhase = .endingCandidate(
                    RideEndingCandidate(
                        session: session,
                        beganAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
                        beganAtDate: observation.receivedAtDate
                    )
                )
                events = [.endingCandidateStarted(session.id)]
            }

        case .temporarilyDisconnected(var disconnected):
            let previousOdometer = disconnected.session.latestOdometerKilometers
            try updateSessionEvidence(&disconnected.session, from: observation)

            guard observation.isVehicleConnected else {
                nextTransportGapEvidence = .observed
                nextPhase = .temporarilyDisconnected(disconnected)
                break
            }

            if movementHint(
                in: observation,
                previousOdometer: previousOdometer,
                allowMotion: false
            ) {
                nextPhase = .active(disconnected.session)
                events = [.rideResumed(disconnected.session.id)]
            } else {
                nextPhase = .endingCandidate(
                    RideEndingCandidate(
                        session: disconnected.session,
                        beganAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
                        beganAtDate: observation.receivedAtDate
                    )
                )
                events = [.endingCandidateStarted(disconnected.session.id)]
            }

        case .endingCandidate(var ending):
            let previousOdometer = ending.session.latestOdometerKilometers
            try updateSessionEvidence(&ending.session, from: observation)

            if !observation.isVehicleConnected {
                nextTransportGapEvidence = .observed
                nextPhase = .temporarilyDisconnected(
                    TemporarilyDisconnectedRide(
                        session: ending.session,
                        disconnectedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
                        disconnectedAtDate: observation.receivedAtDate
                    )
                )
                events = [.rideTemporarilyDisconnected(ending.session.id)]
            } else if movementHint(
                in: observation,
                previousOdometer: previousOdometer,
                allowMotion: false
            ) {
                nextPhase = .active(ending.session)
                events = [.rideResumed(ending.session.id)]
            } else {
                let elapsed = observation.receivedAtUptimeNanoseconds - ending.beganAtUptimeNanoseconds
                if elapsed >= policy.endingDurationNanoseconds {
                    let completed = try CompletedRideEvidence(
                        sessionID: ending.session.id,
                        beganAtDate: ending.session.beganAtDate,
                        confirmedAtDate: ending.session.confirmedAtDate,
                        endedAtDate: observation.receivedAtDate,
                        startingOdometerKilometers: ending.session.startingOdometerKilometers,
                        endingOdometerKilometers: ending.session.latestOdometerKilometers,
                        qualityScreenedGPSDistanceMeters: ending.session.accumulatedGPSDistanceMeters,
                        continuity: ending.session.continuity,
                        transportGapEvidence: nextTransportGapEvidence ?? .unknown
                    )
                    nextPhase = .idle
                    nextTransportGapEvidence = nil
                    events = [.rideEnded(completed)]
                } else {
                    nextPhase = .endingCandidate(ending)
                }
            }
        }

        phase = nextPhase
        transportGapEvidence = nextTransportGapEvidence
        lastObservationUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
        lastObservationDate = observation.receivedAtDate
        return RideEngineUpdate(phase: nextPhase, events: events)
    }

    /// Creates a compact durable checkpoint only for a confirmed ride. Idle and
    /// unconfirmed candidates intentionally return nil.
    public func recoveryCheckpoint(checkpointedAtDate: Date) throws -> RideRecoveryCheckpoint? {
        let session: ActiveRideSession
        let persistedPhase: RideCheckpointPhase
        let phaseBeganAtDate: Date?

        switch phase {
        case .idle, .candidate:
            return nil
        case let .active(active):
            session = active
            persistedPhase = .active
            phaseBeganAtDate = nil
        case let .temporarilyDisconnected(disconnected):
            session = disconnected.session
            persistedPhase = .temporarilyDisconnected
            phaseBeganAtDate = disconnected.disconnectedAtDate
        case let .endingCandidate(ending):
            session = ending.session
            persistedPhase = .endingCandidate
            phaseBeganAtDate = ending.beganAtDate
        }

        return try RideRecoveryCheckpoint(
            sessionID: session.id,
            beganAtDate: session.beganAtDate,
            confirmedAtDate: session.confirmedAtDate,
            persistedPhase: persistedPhase,
            phaseBeganAtDate: phaseBeganAtDate,
            lastObservedAtDate: lastObservationDate ?? session.confirmedAtDate,
            checkpointedAtDate: checkpointedAtDate,
            startingOdometerKilometers: session.startingOdometerKilometers,
            latestOdometerKilometers: session.latestOdometerKilometers,
            accumulatedGPSDistanceMeters: session.accumulatedGPSDistanceMeters,
            transportGapEvidence: transportGapEvidence ?? .unknown
        )
    }

    /// Restores a confirmed ride using durable wall-clock identity while
    /// deliberately establishing a new process-local monotonic epoch.
    ///
    /// Even if the old process was in `active` or `endingCandidate`, recovery is
    /// conservative: the ride returns as temporarily disconnected until a fresh
    /// scooter/GPS observation proves movement or begins a new stop-confirmation
    /// window. Old monotonic timers never survive a process restart.
    public static func restoring(
        from checkpoint: RideRecoveryCheckpoint,
        policy: RideDetectionPolicy,
        recoveredAtUptimeNanoseconds: UInt64,
        recoveredAtDate: Date,
        makeSessionID: @escaping @Sendable () -> UUID = { UUID() }
    ) throws -> RideEngine {
        guard recoveredAtDate.timeIntervalSinceReferenceDate.isFinite else {
            throw RideEngineError.invalidRecovery
        }

        let session = ActiveRideSession(
            id: checkpoint.sessionID,
            beganAtUptimeNanoseconds: nil,
            beganAtDate: checkpoint.beganAtDate,
            confirmedAtUptimeNanoseconds: nil,
            confirmedAtDate: checkpoint.confirmedAtDate,
            startingOdometerKilometers: checkpoint.startingOdometerKilometers,
            latestOdometerKilometers: checkpoint.latestOdometerKilometers,
            accumulatedGPSDistanceMeters: checkpoint.accumulatedGPSDistanceMeters,
            continuity: .recoveredCheckpoint
        )
        let disconnected = TemporarilyDisconnectedRide(
            session: session,
            disconnectedAtUptimeNanoseconds: recoveredAtUptimeNanoseconds,
            disconnectedAtDate: recoveredAtDate
        )

        var engine = RideEngine(policy: policy, makeSessionID: makeSessionID)
        engine.phase = .temporarilyDisconnected(disconnected)
        engine.transportGapEvidence = checkpoint.transportGapEvidence.afterProcessRecovery
        engine.lastObservationUptimeNanoseconds = recoveredAtUptimeNanoseconds
        // Recovery itself is not a vehicle observation. Preserve the durable
        // last-evidence time until a genuinely new observation arrives.
        engine.lastObservationDate = checkpoint.lastObservedAtDate
        return engine
    }

    private func makeCandidate(from observation: RideObservation) throws -> RideCandidate {
        RideCandidate(
            beganAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
            beganAtDate: observation.receivedAtDate,
            startingOdometerKilometers: observation.odometerKilometers,
            latestOdometerKilometers: observation.odometerKilometers,
            accumulatedGPSDistanceMeters: try addingGPSDistance(
                existing: 0,
                delta: observation.qualityScreenedGPSDistanceDeltaMeters
            )
        )
    }

    private func makeSession(from candidate: RideCandidate, confirmation: RideObservation) -> ActiveRideSession {
        ActiveRideSession(
            id: makeSessionID(),
            beganAtUptimeNanoseconds: candidate.beganAtUptimeNanoseconds,
            beganAtDate: candidate.beganAtDate,
            confirmedAtUptimeNanoseconds: confirmation.receivedAtUptimeNanoseconds,
            confirmedAtDate: confirmation.receivedAtDate,
            startingOdometerKilometers: candidate.startingOdometerKilometers,
            latestOdometerKilometers: candidate.latestOdometerKilometers,
            accumulatedGPSDistanceMeters: candidate.accumulatedGPSDistanceMeters
        )
    }

    private func updateCandidateEvidence(
        _ candidate: inout RideCandidate,
        from observation: RideObservation
    ) throws {
        candidate.accumulatedGPSDistanceMeters = try addingGPSDistance(
            existing: candidate.accumulatedGPSDistanceMeters,
            delta: observation.qualityScreenedGPSDistanceDeltaMeters
        )
        updateOdometerEvidence(
            starting: &candidate.startingOdometerKilometers,
            latest: &candidate.latestOdometerKilometers,
            observed: observation.odometerKilometers
        )
    }

    private func updateSessionEvidence(
        _ session: inout ActiveRideSession,
        from observation: RideObservation
    ) throws {
        session.accumulatedGPSDistanceMeters = try addingGPSDistance(
            existing: session.accumulatedGPSDistanceMeters,
            delta: observation.qualityScreenedGPSDistanceDeltaMeters
        )
        updateOdometerEvidence(
            starting: &session.startingOdometerKilometers,
            latest: &session.latestOdometerKilometers,
            observed: observation.odometerKilometers
        )
    }

    private func updateOdometerEvidence(
        starting: inout Double?,
        latest: inout Double?,
        observed: Double?
    ) {
        guard let observed else { return }

        if starting == nil {
            // Establish the first actually observed baseline. Do not treat this
            // first sample as movement and do not backdate it to ride start.
            starting = observed
            latest = observed
            return
        }

        latest = newestOdometer(existing: latest, observed: observed)
    }

    private func addingGPSDistance(existing: Double, delta: Double?) throws -> Double {
        let result = existing + (delta ?? 0)
        guard result.isFinite, result >= 0 else {
            throw RideEngineError.invalidObservation
        }
        return result
    }

    private func movementHint(
        in observation: RideObservation,
        previousOdometer: Double?,
        allowMotion: Bool
    ) -> Bool {
        if let speed = freshAuthoritativeSpeed(in: observation),
           speed.kilometersPerHour >= policy.candidateSpeedKilometersPerHour {
            return true
        }
        if let distanceDelta = observation.qualityScreenedGPSDistanceDeltaMeters,
           distanceDelta > 0 {
            return true
        }
        if let previousOdometer,
           let observedOdometer = observation.odometerKilometers,
           observedOdometer > previousOdometer {
            return true
        }
        if allowMotion, observation.motionIndicatesMovement {
            return true
        }
        return false
    }

    private func strongMovement(in observation: RideObservation, candidate: RideCandidate) -> Bool {
        if let speed = freshAuthoritativeSpeed(in: observation),
           speed.kilometersPerHour >= policy.confirmationSpeedKilometersPerHour {
            return true
        }
        if candidate.accumulatedGPSDistanceMeters >= policy.confirmationGPSDistanceMeters {
            return true
        }
        if let start = candidate.startingOdometerKilometers,
           let current = candidate.latestOdometerKilometers,
           current >= start,
           current - start >= policy.confirmationOdometerDeltaKilometers {
            return true
        }
        return false
    }

    private func freshAuthoritativeSpeed(in observation: RideObservation) -> SpeedTelemetrySample? {
        guard let speedSample = observation.speedSample,
              speedSample.isAuthoritativeMeasurement else {
            return nil
        }

        let age = observation.receivedAtUptimeNanoseconds - speedSample.receivedAtUptimeNanoseconds
        guard age <= policy.maximumSpeedSampleAgeNanoseconds else {
            return nil
        }
        return speedSample
    }

    private func newestOdometer(existing: Double?, observed: Double?) -> Double? {
        guard let observed else { return existing }
        guard let existing else { return observed }
        return max(existing, observed)
    }
}
