import Foundation

public enum RideLocationEvidenceError: Error, Equatable, Sendable {
    case invalidSample
    case invalidPolicy
}

/// One raw phone-location observation before Nembra decides whether it is safe
/// to use as route or GPS-distance evidence.
///
/// The source measurement date remains wall-clock metadata. Process-local
/// reception uptime is the ordering authority while the app process is alive;
/// it is never persisted across a relaunch or reboot as if the clock domain
/// remained comparable.
public struct RideLocationSample: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let sourceMeasurementDate: Date
    public let receivedAtDate: Date
    public let receivedAtUptimeNanoseconds: UInt64
    public let horizontalAccuracyMeters: Double
    public let isSimulatedBySoftware: Bool

    public init(
        latitude: Double,
        longitude: Double,
        sourceMeasurementDate: Date,
        receivedAtDate: Date,
        receivedAtUptimeNanoseconds: UInt64,
        horizontalAccuracyMeters: Double,
        isSimulatedBySoftware: Bool
    ) throws {
        guard latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude),
              sourceMeasurementDate.timeIntervalSinceReferenceDate.isFinite,
              receivedAtDate.timeIntervalSinceReferenceDate.isFinite,
              horizontalAccuracyMeters.isFinite,
              horizontalAccuracyMeters >= 0 else {
            throw RideLocationEvidenceError.invalidSample
        }

        self.latitude = latitude
        self.longitude = longitude
        self.sourceMeasurementDate = sourceMeasurementDate
        self.receivedAtDate = receivedAtDate
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.isSimulatedBySoftware = isSimulatedBySoftware
    }
}

/// Location-quality thresholds are injected. Nembra deliberately has no
/// MAXSHOT/production default until outdoor traces on the target iPhone justify
/// accuracy, staleness, continuity-gap, and implausible-jump limits.
public struct RideLocationQualityPolicy: Equatable, Sendable {
    public let maximumHorizontalAccuracyMeters: Double
    public let maximumMeasurementAgeSeconds: TimeInterval
    public let maximumFutureMeasurementSkewSeconds: TimeInterval
    public let maximumContinuityGapNanoseconds: UInt64
    public let maximumImpliedSpeedMetersPerSecond: Double
    public let allowsSoftwareSimulatedLocations: Bool

    public init(
        maximumHorizontalAccuracyMeters: Double,
        maximumMeasurementAgeSeconds: TimeInterval,
        maximumFutureMeasurementSkewSeconds: TimeInterval,
        maximumContinuityGapNanoseconds: UInt64,
        maximumImpliedSpeedMetersPerSecond: Double,
        allowsSoftwareSimulatedLocations: Bool
    ) throws {
        guard maximumHorizontalAccuracyMeters.isFinite,
              maximumHorizontalAccuracyMeters > 0,
              maximumMeasurementAgeSeconds.isFinite,
              maximumMeasurementAgeSeconds >= 0,
              maximumFutureMeasurementSkewSeconds.isFinite,
              maximumFutureMeasurementSkewSeconds >= 0,
              maximumContinuityGapNanoseconds > 0,
              maximumImpliedSpeedMetersPerSecond.isFinite,
              maximumImpliedSpeedMetersPerSecond > 0 else {
            throw RideLocationEvidenceError.invalidPolicy
        }

        self.maximumHorizontalAccuracyMeters = maximumHorizontalAccuracyMeters
        self.maximumMeasurementAgeSeconds = maximumMeasurementAgeSeconds
        self.maximumFutureMeasurementSkewSeconds = maximumFutureMeasurementSkewSeconds
        self.maximumContinuityGapNanoseconds = maximumContinuityGapNanoseconds
        self.maximumImpliedSpeedMetersPerSecond = maximumImpliedSpeedMetersPerSecond
        self.allowsSoftwareSimulatedLocations = allowsSoftwareSimulatedLocations
    }

    /// Deterministic Simulator-only policy for exercising the software path.
    /// These values are QA fixtures, not claims about real outdoor GPS quality.
    public static func simulatorQA() throws -> RideLocationQualityPolicy {
        try RideLocationQualityPolicy(
            maximumHorizontalAccuracyMeters: 50,
            maximumMeasurementAgeSeconds: 5,
            maximumFutureMeasurementSkewSeconds: 1,
            maximumContinuityGapNanoseconds: 5_000_000_000,
            maximumImpliedSpeedMetersPerSecond: 25,
            allowsSoftwareSimulatedLocations: true
        )
    }
}

public enum RideLocationRejectionReason: Equatable, Sendable {
    case softwareSimulationNotAllowed
    case accuracyTooLow
    case staleMeasurement
    case futureDatedMeasurement
    case nonMonotonicReception
    case implausibleJump
}

/// One coordinate that passed the injected quality policy.
///
/// `distanceDeltaMeters` is present only when Nembra has continuous accepted
/// coverage from the immediately previous accepted coordinate. A new route
/// segment deliberately has no distance delta across the missing interval.
public struct QualityScreenedRideLocation: Equatable, Sendable {
    public let sample: RideLocationSample
    public let distanceDeltaMeters: Double?
    public let startsNewRouteSegment: Bool

    public init(
        sample: RideLocationSample,
        distanceDeltaMeters: Double?,
        startsNewRouteSegment: Bool
    ) {
        self.sample = sample
        self.distanceDeltaMeters = distanceDeltaMeters
        self.startsNewRouteSegment = startsNewRouteSegment
    }
}

public enum RideLocationScreeningResult: Equatable, Sendable {
    case accepted(QualityScreenedRideLocation)
    case rejected(RideLocationRejectionReason)
}

/// Stateful, deterministic location-quality screen shared by Core Location and
/// injected QA sources.
///
/// Rejections are transactional: an unusable sample never advances the accepted
/// coordinate baseline. A caller may explicitly mark a known coverage gap after
/// authorization loss, process recovery, or another discontinuity; the next
/// accepted sample then starts a new route segment and contributes no invented
/// distance across the gap.
public struct RideLocationQualityScreen: Sendable {
    private let policy: RideLocationQualityPolicy
    private var previousAcceptedSample: RideLocationSample?
    private var forceNextAcceptedSampleToStartSegment = false

    public init(policy: RideLocationQualityPolicy) {
        self.policy = policy
    }

    public mutating func markKnownCoverageGap() {
        if previousAcceptedSample != nil {
            forceNextAcceptedSampleToStartSegment = true
        }
    }

    public mutating func reset() {
        previousAcceptedSample = nil
        forceNextAcceptedSampleToStartSegment = false
    }

    public mutating func screen(_ sample: RideLocationSample) -> RideLocationScreeningResult {
        if sample.isSimulatedBySoftware,
           !policy.allowsSoftwareSimulatedLocations {
            return .rejected(.softwareSimulationNotAllowed)
        }

        guard sample.horizontalAccuracyMeters <= policy.maximumHorizontalAccuracyMeters else {
            return .rejected(.accuracyTooLow)
        }

        let measurementAge = sample.receivedAtDate.timeIntervalSince(sample.sourceMeasurementDate)
        guard measurementAge.isFinite else {
            return .rejected(.staleMeasurement)
        }
        if measurementAge > policy.maximumMeasurementAgeSeconds {
            return .rejected(.staleMeasurement)
        }
        if measurementAge < -policy.maximumFutureMeasurementSkewSeconds {
            return .rejected(.futureDatedMeasurement)
        }

        guard let previousAcceptedSample else {
            let accepted = QualityScreenedRideLocation(
                sample: sample,
                distanceDeltaMeters: nil,
                startsNewRouteSegment: false
            )
            self.previousAcceptedSample = sample
            forceNextAcceptedSampleToStartSegment = false
            return .accepted(accepted)
        }

        guard sample.receivedAtUptimeNanoseconds > previousAcceptedSample.receivedAtUptimeNanoseconds else {
            return .rejected(.nonMonotonicReception)
        }

        let uptimeDeltaNanoseconds = sample.receivedAtUptimeNanoseconds
            - previousAcceptedSample.receivedAtUptimeNanoseconds
        let continuityExpired = uptimeDeltaNanoseconds > policy.maximumContinuityGapNanoseconds
        let startsNewSegment = forceNextAcceptedSampleToStartSegment || continuityExpired

        let distanceMeters = Self.distanceMeters(
            latitude1: previousAcceptedSample.latitude,
            longitude1: previousAcceptedSample.longitude,
            latitude2: sample.latitude,
            longitude2: sample.longitude
        )

        if !startsNewSegment {
            let elapsedSeconds = Double(uptimeDeltaNanoseconds) / 1_000_000_000
            let impliedSpeedMetersPerSecond = distanceMeters / elapsedSeconds
            guard impliedSpeedMetersPerSecond.isFinite,
                  impliedSpeedMetersPerSecond <= policy.maximumImpliedSpeedMetersPerSecond else {
                return .rejected(.implausibleJump)
            }
        }

        let accepted = QualityScreenedRideLocation(
            sample: sample,
            distanceDeltaMeters: startsNewSegment ? nil : distanceMeters,
            startsNewRouteSegment: startsNewSegment
        )
        self.previousAcceptedSample = sample
        forceNextAcceptedSampleToStartSegment = false
        return .accepted(accepted)
    }

    /// Great-circle distance on WGS 84 coordinates. This is used only between
    /// accepted adjacent observations and never to reconstruct a missing route
    /// segment or infer scooter odometer travel.
    private static func distanceMeters(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double
    ) -> Double {
        let earthRadiusMeters = 6_371_008.8
        let degreesToRadians = Double.pi / 180
        let phi1 = latitude1 * degreesToRadians
        let phi2 = latitude2 * degreesToRadians
        let deltaPhi = (latitude2 - latitude1) * degreesToRadians
        let deltaLambda = (longitude2 - longitude1) * degreesToRadians

        let sineHalfLatitude = sin(deltaPhi / 2)
        let sineHalfLongitude = sin(deltaLambda / 2)
        let a = sineHalfLatitude * sineHalfLatitude
            + cos(phi1) * cos(phi2) * sineHalfLongitude * sineHalfLongitude
        let clampedA = min(1, max(0, a))
        return earthRadiusMeters * 2 * atan2(sqrt(clampedA), sqrt(1 - clampedA))
    }
}
