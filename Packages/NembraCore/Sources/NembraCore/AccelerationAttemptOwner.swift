public struct AccelerationAttemptGeneration: RawRepresentable, Hashable, Comparable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (
        lhs: AccelerationAttemptGeneration,
        rhs: AccelerationAttemptGeneration
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum AccelerationAttemptOwnerError: Error, Equatable, Sendable {
    case attemptStillActive(AccelerationAttemptGeneration)
    case nonMonotonicAttemptStart(previous: UInt64, proposed: UInt64)
    case generationExhausted
}

public struct AccelerationAttemptSnapshot: Equatable, Sendable {
    public let generation: AccelerationAttemptGeneration
    public let startedAtUptimeNanoseconds: UInt64
    public let evidence: AccelerationEvidenceSessionSnapshot

    public var readiness: AccelerationEvidenceReadiness {
        evidence.readiness()
    }

    /// Terminal means this exact attempt can no longer accept evidence. A known
    /// continuity break is terminal even when the underlying run evaluator was
    /// still waiting for a usable standstill anchor.
    public var isTerminal: Bool {
        if evidence.continuityWasBroken {
            return true
        }

        switch evidence.runState {
        case .completed, .invalidated:
            return true
        case .waitingForStandstill, .armed, .running:
            return false
        }
    }
}

public enum AccelerationAttemptRecordResult: Equatable, Sendable {
    case ignoredNoAttempt
    case ignoredStaleGeneration(
        expected: AccelerationAttemptGeneration,
        actual: AccelerationAttemptGeneration
    )
    case ignoredAtOrBeforeAttemptStart(startedAt: UInt64, sampleAt: UInt64)
    case session(AccelerationEvidenceSessionRecordResult)
}

public enum AccelerationAttemptInterruptionResult: Equatable, Sendable {
    case ignoredNoAttempt
    case ignoredStaleGeneration(
        expected: AccelerationAttemptGeneration,
        actual: AccelerationAttemptGeneration
    )
    case ignoredAfterTerminalEvidence
    case applied(runState: AccelerationRunState)
}

/// Application-lifecycle owner for acceleration evidence attempts.
///
/// The lower-level `AccelerationEvidenceSession` proves same-attempt timing and
/// telemetry-quality ownership. This type adds the missing application boundary:
/// one explicit generation per user/application attempt, a monotonic start fence,
/// and generation-scoped recording/interruption calls so delayed callbacks from a
/// superseded task cannot mutate a newer attempt.
///
/// This owner deliberately chooses no AOVOPRO ES80 source or quality thresholds.
/// Production callers must inject an evidence-driven
/// `AccelerationEvidenceSessionPolicy`; Simulator policies remain Simulator-only.
public struct AccelerationAttemptOwner: Sendable {
    private struct Attempt: Sendable {
        let generation: AccelerationAttemptGeneration
        let startedAtUptimeNanoseconds: UInt64
        var session: AccelerationEvidenceSession

        var snapshot: AccelerationAttemptSnapshot {
            AccelerationAttemptSnapshot(
                generation: generation,
                startedAtUptimeNanoseconds: startedAtUptimeNanoseconds,
                evidence: session.snapshot
            )
        }
    }

    private var current: Attempt?
    private var lastIssuedGenerationRawValue: UInt64 = 0
    private var lastAttemptStartUptimeNanoseconds: UInt64?

    public init() {}

    public var currentGeneration: AccelerationAttemptGeneration? {
        current?.generation
    }

    public var currentSnapshot: AccelerationAttemptSnapshot? {
        current?.snapshot
    }

    /// Begins a new attempt only when there is no active mutable attempt.
    ///
    /// `startedAtUptimeNanoseconds` must come from the same process-local
    /// monotonic time domain as `SpeedTelemetrySample.receivedAtUptimeNanoseconds`.
    /// Samples observed at or before this fence are ignored rather than being
    /// allowed to arm a newly created attempt from queued pre-attempt traffic.
    @discardableResult
    public mutating func begin(
        policy: AccelerationEvidenceSessionPolicy,
        startedAtUptimeNanoseconds: UInt64
    ) throws -> AccelerationAttemptGeneration {
        if let current, !current.snapshot.isTerminal {
            throw AccelerationAttemptOwnerError.attemptStillActive(current.generation)
        }

        if let previous = lastAttemptStartUptimeNanoseconds,
           startedAtUptimeNanoseconds <= previous {
            throw AccelerationAttemptOwnerError.nonMonotonicAttemptStart(
                previous: previous,
                proposed: startedAtUptimeNanoseconds
            )
        }

        guard lastIssuedGenerationRawValue < UInt64.max else {
            throw AccelerationAttemptOwnerError.generationExhausted
        }

        let generation = AccelerationAttemptGeneration(
            rawValue: lastIssuedGenerationRawValue + 1
        )
        lastIssuedGenerationRawValue = generation.rawValue
        lastAttemptStartUptimeNanoseconds = startedAtUptimeNanoseconds
        current = Attempt(
            generation: generation,
            startedAtUptimeNanoseconds: startedAtUptimeNanoseconds,
            session: AccelerationEvidenceSession(policy: policy)
        )
        return generation
    }

    /// Offers one authoritative raw speed callback to exactly one attempt
    /// generation. The generation token is intentionally required so an async
    /// task retained from a previous attempt cannot feed a newly started one.
    @discardableResult
    public mutating func record(
        _ sample: SpeedTelemetrySample,
        for generation: AccelerationAttemptGeneration
    ) -> AccelerationAttemptRecordResult {
        guard var attempt = current else {
            return .ignoredNoAttempt
        }
        guard generation == attempt.generation else {
            return .ignoredStaleGeneration(
                expected: attempt.generation,
                actual: generation
            )
        }
        guard sample.receivedAtUptimeNanoseconds > attempt.startedAtUptimeNanoseconds else {
            return .ignoredAtOrBeforeAttemptStart(
                startedAt: attempt.startedAtUptimeNanoseconds,
                sampleAt: sample.receivedAtUptimeNanoseconds
            )
        }

        let result = attempt.session.record(sample)
        current = attempt
        return .session(result)
    }

    /// Maps a real connection/lifecycle/operator interruption onto exactly one
    /// attempt generation. Stale interruption callbacks are ignored rather than
    /// terminating a newer attempt.
    @discardableResult
    public mutating func interrupt(
        _ interruption: AccelerationRunInterruption,
        for generation: AccelerationAttemptGeneration
    ) -> AccelerationAttemptInterruptionResult {
        guard var attempt = current else {
            return .ignoredNoAttempt
        }
        guard generation == attempt.generation else {
            return .ignoredStaleGeneration(
                expected: attempt.generation,
                actual: generation
            )
        }
        guard !attempt.snapshot.isTerminal else {
            return .ignoredAfterTerminalEvidence
        }

        attempt.session.interrupt(interruption)
        let runState = attempt.session.state
        current = attempt
        return .applied(runState: runState)
    }
}
