import Foundation

public enum LiveDistanceIntegrationMethod: String, Codable, Equatable, Sendable {
    /// Numerical integration of two consecutive authoritative speed samples.
    /// This estimates area under the measured speed curve; it is not the
    /// render-only interpolation used by the dashboard.
    case trapezoidalBetweenMeasurements
}

public enum LiveDistanceIntegrationError: Error, Equatable, Sendable {
    case invalidPolicy
    case invalidSegmentEnd
}

public enum LiveDistanceSampleRejection: Error, Equatable, Sendable {
    case nonAuthoritativeSample
    case sourceMismatch
    case beforeSegmentStart
    case nonIncreasingTimestamp
    case distanceOverflow
}

/// Policy is deliberately injected. Nembra has no production AOVOPRO ES80
/// cadence threshold until real BLE telemetry benchmarking establishes one.
public struct LiveDistanceIntegrationPolicy: Equatable, Sendable {
    public let source: SpeedTelemetrySource
    public let maximumIntegrationIntervalNanoseconds: UInt64
    public let method: LiveDistanceIntegrationMethod

    public init(
        source: SpeedTelemetrySource,
        maximumIntegrationIntervalNanoseconds: UInt64,
        method: LiveDistanceIntegrationMethod
    ) throws {
        guard source != .motionAssist,
            maximumIntegrationIntervalNanoseconds > 0
        else {
            throw LiveDistanceIntegrationError.invalidPolicy
        }

        self.source = source
        self.maximumIntegrationIntervalNanoseconds = maximumIntegrationIntervalNanoseconds
        self.method = method
    }
}

public enum LiveDistanceRecordResult: Equatable, Sendable {
    /// First usable sample became the integration anchor. No distance is
    /// fabricated before there are two authoritative endpoints.
    case anchored
    /// One measured interval was integrated successfully.
    case integrated(addedMeters: Double)
    /// The interval cannot be integrated honestly. This can be caused either by
    /// an oversized accepted-sample interval or by an unusable selected
    /// authoritative measurement inside the interval. The new usable sample
    /// becomes the next anchor, but no distance is invented across the gap.
    case gapDetected(intervalNanoseconds: UInt64)
    /// Rejection never rewrites accepted distance/anchor evidence. A fresh
    /// source-selected authoritative callback may still consume chronology and,
    /// when numeric evidence is unusable, mark a real coverage interruption.
    case rejected(LiveDistanceSampleRejection)
}

/// A read-only summary of measured-speed integration for one monotonic segment.
///
/// `distanceMeters == nil` means no interval has been integrated yet. This is
/// intentionally different from a measured zero-meter interval.
public struct LiveDistanceSegmentSnapshot: Equatable, Sendable {
    public let source: SpeedTelemetrySource
    public let method: LiveDistanceIntegrationMethod
    public let segmentStartUptimeNanoseconds: UInt64
    public let firstAcceptedSampleUptimeNanoseconds: UInt64?
    public let lastAcceptedSampleUptimeNanoseconds: UInt64?
    public let distanceMeters: Double?
    public let hasKnownCoverageGap: Bool
    public let acceptedSampleCount: Int
    public let integratedIntervalCount: Int
    public let knownCoverageGapCount: Int

#if SWIFT_PACKAGE
    /// Package-only construction keeps deterministic NembraCore fixtures able to
    /// model malformed projection inputs without exposing an authority-minting
    /// initializer to normal package clients.
    package init(
        source: SpeedTelemetrySource,
        method: LiveDistanceIntegrationMethod,
        segmentStartUptimeNanoseconds: UInt64,
        firstAcceptedSampleUptimeNanoseconds: UInt64?,
        lastAcceptedSampleUptimeNanoseconds: UInt64?,
        distanceMeters: Double?,
        hasKnownCoverageGap: Bool,
        acceptedSampleCount: Int,
        integratedIntervalCount: Int,
        knownCoverageGapCount: Int
    ) {
        self.source = source
        self.method = method
        self.segmentStartUptimeNanoseconds = segmentStartUptimeNanoseconds
        self.firstAcceptedSampleUptimeNanoseconds = firstAcceptedSampleUptimeNanoseconds
        self.lastAcceptedSampleUptimeNanoseconds = lastAcceptedSampleUptimeNanoseconds
        self.distanceMeters = distanceMeters
        self.hasKnownCoverageGap = hasKnownCoverageGap
        self.acceptedSampleCount = acceptedSampleCount
        self.integratedIntervalCount = integratedIntervalCount
        self.knownCoverageGapCount = knownCoverageGapCount
    }
#else
    /// This source is also compiled directly into Nembra.app. Keep provisional
    /// snapshot construction file-owned there so same-module UI/app code cannot
    /// manufacture accepted live-distance evidence by using an otherwise
    /// synthesized internal memberwise initializer.
    fileprivate init(
        source: SpeedTelemetrySource,
        method: LiveDistanceIntegrationMethod,
        segmentStartUptimeNanoseconds: UInt64,
        firstAcceptedSampleUptimeNanoseconds: UInt64?,
        lastAcceptedSampleUptimeNanoseconds: UInt64?,
        distanceMeters: Double?,
        hasKnownCoverageGap: Bool,
        acceptedSampleCount: Int,
        integratedIntervalCount: Int,
        knownCoverageGapCount: Int
    ) {
        self.source = source
        self.method = method
        self.segmentStartUptimeNanoseconds = segmentStartUptimeNanoseconds
        self.firstAcceptedSampleUptimeNanoseconds = firstAcceptedSampleUptimeNanoseconds
        self.lastAcceptedSampleUptimeNanoseconds = lastAcceptedSampleUptimeNanoseconds
        self.distanceMeters = distanceMeters
        self.hasKnownCoverageGap = hasKnownCoverageGap
        self.acceptedSampleCount = acceptedSampleCount
        self.integratedIntervalCount = integratedIntervalCount
        self.knownCoverageGapCount = knownCoverageGapCount
    }
#endif
}

/// Full evidence for one monotonic integration segment after its end boundary is
/// known. Only this finalized type carries `RideDistanceCoverage`, preventing an
/// in-progress snapshot from being mistaken for complete ride evidence.
public struct FinalizedLiveDistanceSegment: Equatable, Sendable {
    public let source: SpeedTelemetrySource
    public let method: LiveDistanceIntegrationMethod
    public let segmentStartUptimeNanoseconds: UInt64
    public let segmentEndUptimeNanoseconds: UInt64
    public let firstAcceptedSampleUptimeNanoseconds: UInt64?
    public let lastAcceptedSampleUptimeNanoseconds: UInt64?
    public let distanceMeters: Double?
    public let coverage: RideDistanceCoverage
    public let acceptedSampleCount: Int
    public let integratedIntervalCount: Int
    public let knownCoverageGapCount: Int

#if SWIFT_PACKAGE
    /// Package-only construction keeps deterministic NembraCore fixtures able to
    /// model finalized evidence while preventing normal package clients from
    /// minting it directly.
    package init(
        source: SpeedTelemetrySource,
        method: LiveDistanceIntegrationMethod,
        segmentStartUptimeNanoseconds: UInt64,
        segmentEndUptimeNanoseconds: UInt64,
        firstAcceptedSampleUptimeNanoseconds: UInt64?,
        lastAcceptedSampleUptimeNanoseconds: UInt64?,
        distanceMeters: Double?,
        coverage: RideDistanceCoverage,
        acceptedSampleCount: Int,
        integratedIntervalCount: Int,
        knownCoverageGapCount: Int
    ) {
        self.source = source
        self.method = method
        self.segmentStartUptimeNanoseconds = segmentStartUptimeNanoseconds
        self.segmentEndUptimeNanoseconds = segmentEndUptimeNanoseconds
        self.firstAcceptedSampleUptimeNanoseconds = firstAcceptedSampleUptimeNanoseconds
        self.lastAcceptedSampleUptimeNanoseconds = lastAcceptedSampleUptimeNanoseconds
        self.distanceMeters = distanceMeters
        self.coverage = coverage
        self.acceptedSampleCount = acceptedSampleCount
        self.integratedIntervalCount = integratedIntervalCount
        self.knownCoverageGapCount = knownCoverageGapCount
    }
#else
    /// `LiveDistanceIntegration.swift` is also compiled directly into Nembra.app.
    /// Keep finalized distance evidence file-owned there so same-module UI/app
    /// code cannot bypass `LiveDistanceSegmentAccumulator.finalize` by using an
    /// otherwise synthesized internal memberwise initializer.
    fileprivate init(
        source: SpeedTelemetrySource,
        method: LiveDistanceIntegrationMethod,
        segmentStartUptimeNanoseconds: UInt64,
        segmentEndUptimeNanoseconds: UInt64,
        firstAcceptedSampleUptimeNanoseconds: UInt64?,
        lastAcceptedSampleUptimeNanoseconds: UInt64?,
        distanceMeters: Double?,
        coverage: RideDistanceCoverage,
        acceptedSampleCount: Int,
        integratedIntervalCount: Int,
        knownCoverageGapCount: Int
    ) {
        self.source = source
        self.method = method
        self.segmentStartUptimeNanoseconds = segmentStartUptimeNanoseconds
        self.segmentEndUptimeNanoseconds = segmentEndUptimeNanoseconds
        self.firstAcceptedSampleUptimeNanoseconds = firstAcceptedSampleUptimeNanoseconds
        self.lastAcceptedSampleUptimeNanoseconds = lastAcceptedSampleUptimeNanoseconds
        self.distanceMeters = distanceMeters
        self.coverage = coverage
        self.acceptedSampleCount = acceptedSampleCount
        self.integratedIntervalCount = integratedIntervalCount
        self.knownCoverageGapCount = knownCoverageGapCount
    }
#endif
}

/// Integrates one explicitly selected authoritative speed source without ever
/// using display interpolation or motion-assisted estimates as mileage evidence.
///
/// The accumulator is session-local because monotonic uptime cannot be resumed
/// across a process restart/reboot. A recovered ride must begin a new integration
/// segment and let ODO/reconciliation account for any missing distance.
public struct LiveDistanceSegmentAccumulator: Sendable {
    public let policy: LiveDistanceIntegrationPolicy
    public let segmentStartUptimeNanoseconds: UInt64

    private var firstAcceptedSample: SpeedTelemetrySample?
    private var lastAcceptedSample: SpeedTelemetrySample?
    /// Monotonic chronology of source-selected authoritative callbacks is kept
    /// separately from accepted integration anchors. Numeric rejection must not
    /// reopen the stream to an older delayed callback.
    private var lastSeenAuthoritativeSampleUptimeNanoseconds: UInt64?
    /// A selected authoritative measurement was chronologically valid but could
    /// not participate in distance arithmetic. The next usable measurement must
    /// re-anchor instead of integrating through that known evidence hole.
    private var integrationContinuityInterrupted = false
    private var accumulatedDistanceMeters = 0.0
    private var acceptedSampleCount = 0
    private var integratedIntervalCount = 0
    private var knownCoverageGapCount = 0

    public init(
        policy: LiveDistanceIntegrationPolicy,
        segmentStartUptimeNanoseconds: UInt64
    ) {
        self.policy = policy
        self.segmentStartUptimeNanoseconds = segmentStartUptimeNanoseconds
    }

    @discardableResult
    public mutating func record(_ sample: SpeedTelemetrySample) -> LiveDistanceRecordResult {
        guard sample.isAuthoritativeMeasurement else {
            return .rejected(.nonAuthoritativeSample)
        }
        guard sample.source == policy.source else {
            return .rejected(.sourceMismatch)
        }
        guard sample.receivedAtUptimeNanoseconds >= segmentStartUptimeNanoseconds else {
            return .rejected(.beforeSegmentStart)
        }
        if let lastSeenAuthoritativeSampleUptimeNanoseconds,
           sample.receivedAtUptimeNanoseconds <= lastSeenAuthoritativeSampleUptimeNanoseconds {
            return .rejected(.nonIncreasingTimestamp)
        }

        // Once a fresh callback belongs to this selected authoritative stream,
        // consume its immutable chronology before numeric integration. If the
        // interval later overflows, that callback remains seen; an older delayed
        // callback cannot be admitted by falling back to the last accepted anchor.
        lastSeenAuthoritativeSampleUptimeNanoseconds = sample.receivedAtUptimeNanoseconds

        guard let previous = lastAcceptedSample else {
            firstAcceptedSample = sample
            lastAcceptedSample = sample
            acceptedSampleCount = 1
            if sample.receivedAtUptimeNanoseconds > segmentStartUptimeNanoseconds {
                knownCoverageGapCount = 1
            }
            return .anchored
        }

        let intervalNanoseconds =
            sample.receivedAtUptimeNanoseconds - previous.receivedAtUptimeNanoseconds

        if integrationContinuityInterrupted {
            integrationContinuityInterrupted = false
            lastAcceptedSample = sample
            acceptedSampleCount += 1
            return .gapDetected(intervalNanoseconds: intervalNanoseconds)
        }

        if intervalNanoseconds > policy.maximumIntegrationIntervalNanoseconds {
            lastAcceptedSample = sample
            acceptedSampleCount += 1
            knownCoverageGapCount += 1
            return .gapDetected(intervalNanoseconds: intervalNanoseconds)
        }

        let addedMeters: Double
        switch policy.method {
        case .trapezoidalBetweenMeasurements:
            let intervalSeconds = Double(intervalNanoseconds) / 1_000_000_000
            // Halve before adding to avoid an unnecessary intermediate overflow
            // when both finite endpoint speeds are near Double.greatestFiniteMagnitude.
            let meanSpeed = previous.metersPerSecond / 2 + sample.metersPerSecond / 2
            addedMeters = meanSpeed * intervalSeconds
        }

        guard addedMeters.isFinite,
            addedMeters >= 0,
            (accumulatedDistanceMeters + addedMeters).isFinite
        else {
            if !integrationContinuityInterrupted {
                integrationContinuityInterrupted = true
                knownCoverageGapCount += 1
            }
            return .rejected(.distanceOverflow)
        }

        accumulatedDistanceMeters += addedMeters
        lastAcceptedSample = sample
        acceptedSampleCount += 1
        integratedIntervalCount += 1
        return .integrated(addedMeters: addedMeters)
    }

    /// Live/provisional state through the latest accepted sample. It deliberately
    /// does not expose `RideDistanceCoverage`; full segment coverage cannot be
    /// known until an end boundary is supplied.
    public var snapshot: LiveDistanceSegmentSnapshot {
        LiveDistanceSegmentSnapshot(
            source: policy.source,
            method: policy.method,
            segmentStartUptimeNanoseconds: segmentStartUptimeNanoseconds,
            firstAcceptedSampleUptimeNanoseconds: firstAcceptedSample?.receivedAtUptimeNanoseconds,
            lastAcceptedSampleUptimeNanoseconds: lastAcceptedSample?.receivedAtUptimeNanoseconds,
            distanceMeters: integratedIntervalCount == 0 ? nil : accumulatedDistanceMeters,
            hasKnownCoverageGap: knownCoverageGapCount > 0,
            acceptedSampleCount: acceptedSampleCount,
            integratedIntervalCount: integratedIntervalCount,
            knownCoverageGapCount: knownCoverageGapCount
        )
    }

    /// Finalizes one process-local monotonic integration segment without
    /// extrapolating beyond the last raw measurement. A nonzero segment tail
    /// after the last accepted sample makes integrated evidence partial. If no
    /// interval was ever integrated, distance remains unavailable and coverage
    /// remains unknown.
    public func finalize(
        segmentEndUptimeNanoseconds: UInt64
    ) throws -> FinalizedLiveDistanceSegment {
        guard segmentEndUptimeNanoseconds >= segmentStartUptimeNanoseconds else {
            throw LiveDistanceIntegrationError.invalidSegmentEnd
        }
        if let lastSeenAuthoritativeSampleUptimeNanoseconds,
           segmentEndUptimeNanoseconds < lastSeenAuthoritativeSampleUptimeNanoseconds
        {
            throw LiveDistanceIntegrationError.invalidSegmentEnd
        }

        let hasTrailingGap: Bool
        if let lastAcceptedSample {
            // If numeric rejection already opened a known continuity gap, any
            // still-unobserved tail is contiguous with that same gap and must not
            // be double-counted merely because no new usable anchor arrived.
            hasTrailingGap = !integrationContinuityInterrupted
                && segmentEndUptimeNanoseconds > lastAcceptedSample.receivedAtUptimeNanoseconds
        } else {
            hasTrailingGap = false
        }
        let totalKnownGaps = knownCoverageGapCount + (hasTrailingGap ? 1 : 0)

        let distance: Double?
        let coverage: RideDistanceCoverage
        if integratedIntervalCount == 0 {
            distance = nil
            coverage = .unknown
        } else {
            distance = accumulatedDistanceMeters
            coverage = totalKnownGaps == 0 ? .complete : .partial
        }

        return FinalizedLiveDistanceSegment(
            source: policy.source,
            method: policy.method,
            segmentStartUptimeNanoseconds: segmentStartUptimeNanoseconds,
            segmentEndUptimeNanoseconds: segmentEndUptimeNanoseconds,
            firstAcceptedSampleUptimeNanoseconds: firstAcceptedSample?.receivedAtUptimeNanoseconds,
            lastAcceptedSampleUptimeNanoseconds: lastAcceptedSample?.receivedAtUptimeNanoseconds,
            distanceMeters: distance,
            coverage: coverage,
            acceptedSampleCount: acceptedSampleCount,
            integratedIntervalCount: integratedIntervalCount,
            knownCoverageGapCount: totalKnownGaps
        )
    }
}

public enum RideLiveDistanceAggregationError: Error, Equatable, Sendable {
    case invalidSegmentEvidence
    case invalidExpectedSource
    case mismatchedRideSession
    case mismatchedSource
    case mismatchedMethod
    case conflictingSegment(UUID)
    case conflictingProcessSegmentSequence(UInt64)
    case nonContiguousProcessSegmentSequence(expected: UInt64, actual: UInt64)
    case distanceOverflow
    case gapCountOverflow
}

/// Durable, process-agnostic projection of one finalized live-distance segment.
///
/// Monotonic uptime is deliberately omitted: uptime from one process/boot must
/// never be compared with uptime restored from another. `segmentID` is a durable
/// idempotency key. `processSegmentSequence` is ride-scoped chronology assigned
/// by the ride/recovery layer: zero is the original process segment and each
/// subsequent value represents a new monotonic epoch after an unobserved process
/// boundary. The sequence is evidence; UUID ordering is not.
public struct RideLiveDistanceSegmentEvidence: Codable, Equatable, Sendable {
    public let rideSessionID: UUID
    public let segmentID: UUID
    public let processSegmentSequence: UInt64
    public let source: SpeedTelemetrySource
    public let method: LiveDistanceIntegrationMethod
    public let distanceMeters: Double?
    public let coverage: RideDistanceCoverage
    public let knownCoverageGapCount: Int

    private enum CodingKeys: String, CodingKey {
        case rideSessionID
        case segmentID
        case processSegmentSequence
        case source
        case method
        case distanceMeters
        case coverage
        case knownCoverageGapCount
    }

    public init(
        rideSessionID: UUID,
        segmentID: UUID,
        processSegmentSequence: UInt64,
        finalizedSegment: FinalizedLiveDistanceSegment
    ) throws {
        try self.init(
            rideSessionID: rideSessionID,
            segmentID: segmentID,
            processSegmentSequence: processSegmentSequence,
            source: finalizedSegment.source,
            method: finalizedSegment.method,
            distanceMeters: finalizedSegment.distanceMeters,
            coverage: finalizedSegment.coverage,
            knownCoverageGapCount: finalizedSegment.knownCoverageGapCount
        )
    }

    private init(
        rideSessionID: UUID,
        segmentID: UUID,
        processSegmentSequence: UInt64,
        source: SpeedTelemetrySource,
        method: LiveDistanceIntegrationMethod,
        distanceMeters: Double?,
        coverage: RideDistanceCoverage,
        knownCoverageGapCount: Int
    ) throws {
        guard source != .motionAssist,
              knownCoverageGapCount >= 0 else {
            throw RideLiveDistanceAggregationError.invalidSegmentEvidence
        }

        switch (distanceMeters, coverage) {
        case (nil, .unknown):
            break
        case let (.some(distance), .complete):
            guard distance.isFinite,
                  distance >= 0,
                  knownCoverageGapCount == 0 else {
                throw RideLiveDistanceAggregationError.invalidSegmentEvidence
            }
        case let (.some(distance), .partial):
            guard distance.isFinite,
                  distance >= 0,
                  knownCoverageGapCount > 0 else {
                throw RideLiveDistanceAggregationError.invalidSegmentEvidence
            }
        default:
            throw RideLiveDistanceAggregationError.invalidSegmentEvidence
        }

        self.rideSessionID = rideSessionID
        self.segmentID = segmentID
        self.processSegmentSequence = processSegmentSequence
        self.source = source
        self.method = method
        self.distanceMeters = distanceMeters
        self.coverage = coverage
        self.knownCoverageGapCount = knownCoverageGapCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            rideSessionID: container.decode(UUID.self, forKey: .rideSessionID),
            segmentID: container.decode(UUID.self, forKey: .segmentID),
            processSegmentSequence: container.decode(UInt64.self, forKey: .processSegmentSequence),
            source: container.decode(SpeedTelemetrySource.self, forKey: .source),
            method: container.decode(LiveDistanceIntegrationMethod.self, forKey: .method),
            distanceMeters: container.decodeIfPresent(Double.self, forKey: .distanceMeters),
            coverage: container.decode(RideDistanceCoverage.self, forKey: .coverage),
            knownCoverageGapCount: container.decode(Int.self, forKey: .knownCoverageGapCount)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rideSessionID, forKey: .rideSessionID)
        try container.encode(segmentID, forKey: .segmentID)
        try container.encode(processSegmentSequence, forKey: .processSegmentSequence)
        try container.encode(source, forKey: .source)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(distanceMeters, forKey: .distanceMeters)
        try container.encode(coverage, forKey: .coverage)
        try container.encode(knownCoverageGapCount, forKey: .knownCoverageGapCount)
    }
}

/// Reconciled live-distance evidence for one ride across any number of finalized
/// process-local segments. The sum contains only distance that was actually
/// integrated inside segments. Every process-segment transition is inherently an
/// unobserved interval, so multi-segment rides are partial by construction rather
/// than relying on a caller to remember a gap flag. Equivalent durable replay is
/// ignored idempotently.
public struct RideLiveDistanceAggregate: Equatable, Sendable {
    public let rideSessionID: UUID
    public let source: SpeedTelemetrySource
    public let method: LiveDistanceIntegrationMethod
    public let distanceMeters: Double?
    public let coverage: RideDistanceCoverage
    public let uniqueSegmentCount: Int
    public let duplicateRecordCount: Int
    public let distanceEvidenceSegmentCount: Int
    public let knownCoverageGapCount: Int
    public let unobservedIntervalCount: Int

    /// Aggregate truth can only be minted by `RideLiveDistanceAggregator` in this
    /// file. This stays sealed even when this source is compiled directly into the
    /// app target, where a normal internal memberwise initializer would otherwise
    /// let same-module callers bypass the aggregation invariants.
    fileprivate init(
        rideSessionID: UUID,
        source: SpeedTelemetrySource,
        method: LiveDistanceIntegrationMethod,
        distanceMeters: Double?,
        coverage: RideDistanceCoverage,
        uniqueSegmentCount: Int,
        duplicateRecordCount: Int,
        distanceEvidenceSegmentCount: Int,
        knownCoverageGapCount: Int,
        unobservedIntervalCount: Int
    ) {
        self.rideSessionID = rideSessionID
        self.source = source
        self.method = method
        self.distanceMeters = distanceMeters
        self.coverage = coverage
        self.uniqueSegmentCount = uniqueSegmentCount
        self.duplicateRecordCount = duplicateRecordCount
        self.distanceEvidenceSegmentCount = distanceEvidenceSegmentCount
        self.knownCoverageGapCount = knownCoverageGapCount
        self.unobservedIntervalCount = unobservedIntervalCount
    }
}

public enum RideLiveDistanceAggregator {
    public static func aggregate(
        rideSessionID: UUID,
        source: SpeedTelemetrySource,
        method: LiveDistanceIntegrationMethod,
        records: [RideLiveDistanceSegmentEvidence]
    ) throws -> RideLiveDistanceAggregate {
        guard source != .motionAssist else {
            throw RideLiveDistanceAggregationError.invalidExpectedSource
        }

        var uniqueBySegmentID: [UUID: RideLiveDistanceSegmentEvidence] = [:]
        var duplicateRecordCount = 0

        for record in records {
            guard record.rideSessionID == rideSessionID else {
                throw RideLiveDistanceAggregationError.mismatchedRideSession
            }
            guard record.source == source else {
                throw RideLiveDistanceAggregationError.mismatchedSource
            }
            guard record.method == method else {
                throw RideLiveDistanceAggregationError.mismatchedMethod
            }

            if let existing = uniqueBySegmentID[record.segmentID] {
                guard existing == record else {
                    throw RideLiveDistanceAggregationError.conflictingSegment(record.segmentID)
                }
                duplicateRecordCount += 1
            } else {
                uniqueBySegmentID[record.segmentID] = record
            }
        }

        var segmentIDBySequence: [UInt64: UUID] = [:]
        for record in uniqueBySegmentID.values {
            if let existingID = segmentIDBySequence[record.processSegmentSequence],
               existingID != record.segmentID {
                throw RideLiveDistanceAggregationError.conflictingProcessSegmentSequence(
                    record.processSegmentSequence
                )
            }
            segmentIDBySequence[record.processSegmentSequence] = record.segmentID
        }

        let orderedRecords = uniqueBySegmentID.values.sorted {
            $0.processSegmentSequence < $1.processSegmentSequence
        }
        for (offset, record) in orderedRecords.enumerated() {
            let expected = UInt64(offset)
            guard record.processSegmentSequence == expected else {
                throw RideLiveDistanceAggregationError.nonContiguousProcessSegmentSequence(
                    expected: expected,
                    actual: record.processSegmentSequence
                )
            }
        }

        var accumulatedDistanceMeters = 0.0
        var distanceEvidenceSegmentCount = 0
        var knownCoverageGapCount = 0
        var hasIncompleteCoverage = orderedRecords.count > 1

        for record in orderedRecords {
            if let distanceMeters = record.distanceMeters {
                let candidate = accumulatedDistanceMeters + distanceMeters
                guard candidate.isFinite, candidate >= 0 else {
                    throw RideLiveDistanceAggregationError.distanceOverflow
                }
                accumulatedDistanceMeters = candidate
                distanceEvidenceSegmentCount += 1
            } else {
                hasIncompleteCoverage = true
            }

            if record.coverage != .complete {
                hasIncompleteCoverage = true
            }

            let gapAddition = knownCoverageGapCount.addingReportingOverflow(record.knownCoverageGapCount)
            guard !gapAddition.overflow else {
                throw RideLiveDistanceAggregationError.gapCountOverflow
            }
            knownCoverageGapCount = gapAddition.partialValue
        }

        let unobservedIntervalCount = max(orderedRecords.count - 1, 0)
        let processGapAddition = knownCoverageGapCount.addingReportingOverflow(unobservedIntervalCount)
        guard !processGapAddition.overflow else {
            throw RideLiveDistanceAggregationError.gapCountOverflow
        }
        knownCoverageGapCount = processGapAddition.partialValue

        let distanceMeters: Double?
        let coverage: RideDistanceCoverage
        if distanceEvidenceSegmentCount == 0 {
            distanceMeters = nil
            coverage = .unknown
        } else {
            distanceMeters = accumulatedDistanceMeters
            coverage = hasIncompleteCoverage ? .partial : .complete
        }

        return RideLiveDistanceAggregate(
            rideSessionID: rideSessionID,
            source: source,
            method: method,
            distanceMeters: distanceMeters,
            coverage: coverage,
            uniqueSegmentCount: orderedRecords.count,
            duplicateRecordCount: duplicateRecordCount,
            distanceEvidenceSegmentCount: distanceEvidenceSegmentCount,
            knownCoverageGapCount: knownCoverageGapCount,
            unobservedIntervalCount: unobservedIntervalCount
        )
    }
}
