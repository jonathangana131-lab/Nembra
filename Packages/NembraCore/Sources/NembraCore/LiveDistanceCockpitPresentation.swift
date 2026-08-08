import Foundation

/// Product-facing meaning of one process-local live-distance integration segment.
///
/// `observedNoRecordedGap` means the supplied snapshot contains accepted distance
/// evidence and no gap has been recorded *inside that snapshot*. It deliberately
/// does not mean the whole ride is complete, that no earlier/later gap exists, or
/// that this value is a reconciled final ride distance.
///
/// `partialObserved` preserves the accepted distance subtotal while making a
/// known observation gap explicit. A partial subtotal must never be relabeled as
/// complete trip distance by a consumer.
public enum LiveDistanceCockpitDisplayRole: Equatable, Sendable {
    case observedNoRecordedGap
    case partialObserved
}

/// Truth-preserving distance suitable for a live cockpit presentation layer.
///
/// The exact accepted meter value remains beside the source/method and evidence
/// counts so UI formatting never has to reinterpret provenance. This value is a
/// presentation projection only; it must never be written back into telemetry,
/// persistence, peak evidence, or adaptive-range learning as a new measurement.
public struct LiveDistanceCockpitValue: Equatable, Sendable {
    public let source: SpeedTelemetrySource
    public let method: LiveDistanceIntegrationMethod
    public let distanceMeters: Double
    public let acceptedSampleCount: Int
    public let integratedIntervalCount: Int
    public let knownCoverageGapCount: Int
    public let role: LiveDistanceCockpitDisplayRole

    fileprivate init(
        source: SpeedTelemetrySource,
        method: LiveDistanceIntegrationMethod,
        distanceMeters: Double,
        acceptedSampleCount: Int,
        integratedIntervalCount: Int,
        knownCoverageGapCount: Int,
        role: LiveDistanceCockpitDisplayRole
    ) {
        self.source = source
        self.method = method
        self.distanceMeters = distanceMeters
        self.acceptedSampleCount = acceptedSampleCount
        self.integratedIntervalCount = integratedIntervalCount
        self.knownCoverageGapCount = knownCoverageGapCount
        self.role = role
    }
}

/// Fail-closed primary presentation state for one live distance segment.
///
/// An anchor alone is not distance evidence, so it remains unavailable instead
/// of becoming a synthetic zero. A real zero-meter value becomes observable only
/// after at least one accepted measurement interval has actually been integrated.
///
/// This projection intentionally consumes `LiveDistanceSegmentSnapshot`, whose
/// source comments forbid treating in-progress evidence as finalized coverage.
/// Therefore even `.observedNoRecordedGap` is only an observed live subtotal;
/// ride-level completion/recovery still belongs to finalized segment aggregation
/// and distance reconciliation.
public enum LiveDistanceCockpitState: Equatable, Sendable {
    case unavailable
    case observed(LiveDistanceCockpitValue)

    public init(snapshot: LiveDistanceSegmentSnapshot) {
        guard snapshot.source != .motionAssist,
              snapshot.acceptedSampleCount >= 0,
              snapshot.integratedIntervalCount >= 0,
              snapshot.knownCoverageGapCount >= 0,
              snapshot.hasKnownCoverageGap == (snapshot.knownCoverageGapCount > 0)
        else {
            self = .unavailable
            return
        }

        let maximumPossibleIntegratedIntervals = max(snapshot.acceptedSampleCount - 1, 0)
        guard snapshot.integratedIntervalCount <= maximumPossibleIntegratedIntervals else {
            self = .unavailable
            return
        }

        let missingAcceptedIntervals =
            maximumPossibleIntegratedIntervals - snapshot.integratedIntervalCount
        guard snapshot.knownCoverageGapCount >= missingAcceptedIntervals else {
            // Every accepted-sample adjacency that was not integrated represents
            // missing observation coverage. A snapshot cannot honestly claim a
            // gap-free role while silently omitting one of those intervals.
            self = .unavailable
            return
        }

        switch snapshot.acceptedSampleCount {
        case 0:
            guard snapshot.firstAcceptedSampleUptimeNanoseconds == nil,
                  snapshot.lastAcceptedSampleUptimeNanoseconds == nil,
                  snapshot.integratedIntervalCount == 0,
                  snapshot.distanceMeters == nil,
                  snapshot.knownCoverageGapCount == 0
            else {
                self = .unavailable
                return
            }
            self = .unavailable
            return

        default:
            guard let firstAcceptedSampleUptimeNanoseconds =
                    snapshot.firstAcceptedSampleUptimeNanoseconds,
                  let lastAcceptedSampleUptimeNanoseconds =
                    snapshot.lastAcceptedSampleUptimeNanoseconds,
                  firstAcceptedSampleUptimeNanoseconds >= snapshot.segmentStartUptimeNanoseconds,
                  lastAcceptedSampleUptimeNanoseconds >= firstAcceptedSampleUptimeNanoseconds
            else {
                self = .unavailable
                return
            }

            if snapshot.acceptedSampleCount == 1 {
                guard firstAcceptedSampleUptimeNanoseconds == lastAcceptedSampleUptimeNanoseconds else {
                    self = .unavailable
                    return
                }
            } else {
                guard lastAcceptedSampleUptimeNanoseconds > firstAcceptedSampleUptimeNanoseconds else {
                    self = .unavailable
                    return
                }
            }

            // A leading hole before the first accepted sample is a distinct
            // coverage event from every accepted-sample adjacency that could not
            // be integrated. Do not let one recorded leading gap conceal a later
            // missing accepted interval (or vice versa).
            let leadingGapCount = firstAcceptedSampleUptimeNanoseconds > snapshot.segmentStartUptimeNanoseconds
                ? 1
                : 0
            let minimumKnownCoverageGapCount = missingAcceptedIntervals + leadingGapCount
            guard snapshot.knownCoverageGapCount >= minimumKnownCoverageGapCount else {
                self = .unavailable
                return
            }
        }

        guard snapshot.integratedIntervalCount > 0,
              let distanceMeters = snapshot.distanceMeters,
              distanceMeters.isFinite,
              distanceMeters >= 0
        else {
            self = .unavailable
            return
        }

        let role: LiveDistanceCockpitDisplayRole = snapshot.hasKnownCoverageGap
            ? .partialObserved
            : .observedNoRecordedGap

        self = .observed(
            LiveDistanceCockpitValue(
                source: snapshot.source,
                method: snapshot.method,
                distanceMeters: distanceMeters,
                acceptedSampleCount: snapshot.acceptedSampleCount,
                integratedIntervalCount: snapshot.integratedIntervalCount,
                knownCoverageGapCount: snapshot.knownCoverageGapCount,
                role: role
            )
        )
    }
}
