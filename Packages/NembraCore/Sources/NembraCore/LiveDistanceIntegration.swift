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

/// Policy is deliberately injected. Nembra has no production MAXSHOT cadence
/// threshold until real BLE telemetry benchmarking establishes one.
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
    /// The two valid samples were too far apart to integrate honestly. The new
    /// sample becomes the next anchor, but no distance is invented across the gap.
    case gapDetected(intervalNanoseconds: UInt64)
    /// Invalid evidence never mutates the accumulator.
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

        guard let previous = lastAcceptedSample else {
            firstAcceptedSample = sample
            lastAcceptedSample = sample
            acceptedSampleCount = 1
            if sample.receivedAtUptimeNanoseconds > segmentStartUptimeNanoseconds {
                knownCoverageGapCount = 1
            }
            return .anchored
        }

        guard sample.receivedAtUptimeNanoseconds > previous.receivedAtUptimeNanoseconds else {
            return .rejected(.nonIncreasingTimestamp)
        }

        let intervalNanoseconds =
            sample.receivedAtUptimeNanoseconds - previous.receivedAtUptimeNanoseconds
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
        if let lastAcceptedSample,
            segmentEndUptimeNanoseconds < lastAcceptedSample.receivedAtUptimeNanoseconds
        {
            throw LiveDistanceIntegrationError.invalidSegmentEnd
        }

        let hasTrailingGap: Bool
        if let lastAcceptedSample {
            hasTrailingGap = segmentEndUptimeNanoseconds > lastAcceptedSample.receivedAtUptimeNanoseconds
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
