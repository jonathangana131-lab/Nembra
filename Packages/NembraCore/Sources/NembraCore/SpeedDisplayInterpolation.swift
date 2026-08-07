import Foundation

public enum SpeedDisplayInterpolationError: Error, Equatable, Sendable {
    case nonAuthoritativeInput
    case nonFiniteDisplaySpeed
    case nonMonotonicMeasurement
}

public enum SpeedDisplayFrameOrigin: String, Equatable, Codable, Sendable {
    /// The rendered value exactly equals the latest authoritative measurement.
    case measured
    /// The rendered value exists only for visual continuity between the prior
    /// displayed value and the latest authoritative measurement.
    case visuallyInterpolated
}

/// A render-only result. This deliberately is not a `SpeedTelemetrySample` and
/// carries the latest measurement alongside the visual value so downstream
/// persistence cannot accidentally treat an animation frame as sensor evidence.
public struct SpeedDisplayFrame: Equatable, Sendable {
    public let kilometersPerHour: Double
    public let latestMeasuredKilometersPerHour: Double
    public let latestMeasurementSource: SpeedTelemetrySource
    public let latestMeasurementUptimeNanoseconds: UInt64
    public let origin: SpeedDisplayFrameOrigin
    public let transitionProgress: Double

    public var isInterpolated: Bool {
        origin == .visuallyInterpolated
    }
}

/// Interpolates only *after* a trustworthy absolute speed measurement arrives.
/// It never predicts future speed and never emits telemetry evidence.
///
/// Final visual timing is intentionally injected by the caller. Nembra will
/// tune it from real AOVOPRO ES80 cadence + Simulator/device QA instead of
/// assuming a fictional BLE notification rate in core logic.
public struct SpeedDisplayInterpolator: Sendable {
    private var hasMeasurement = false
    private var anchorKilometersPerHour = 0.0
    private var targetKilometersPerHour = 0.0
    private var transitionStartUptimeNanoseconds: UInt64 = 0
    private var transitionDurationNanoseconds: UInt64 = 0
    private var latestMeasurementSource: SpeedTelemetrySource = .scooterBluetooth
    private var latestMeasurementUptimeNanoseconds: UInt64 = 0
    private var latestAuthoritativeObservationUptimeNanoseconds: UInt64?

    public init() {}

    /// Accepts a new absolute measurement. If a previous visual transition is
    /// still running, the new transition starts from the exact currently
    /// rendered value, preventing jumps when samples arrive rapidly.
    public mutating func accept(
        _ sample: SpeedTelemetrySample,
        transitionDurationNanoseconds: UInt64
    ) throws {
        guard sample.isAuthoritativeMeasurement else {
            throw SpeedDisplayInterpolationError.nonAuthoritativeInput
        }
        if let latestAuthoritativeObservationUptimeNanoseconds,
           sample.receivedAtUptimeNanoseconds <= latestAuthoritativeObservationUptimeNanoseconds {
            throw SpeedDisplayInterpolationError.nonMonotonicMeasurement
        }

        // Ordering is evidence about callback chronology, not about whether a
        // value is numerically renderable. Advance this watermark for every
        // fresh authoritative observation so a rejected display value cannot
        // later make an older callback look new.
        latestAuthoritativeObservationUptimeNanoseconds = sample.receivedAtUptimeNanoseconds

        // `SpeedTelemetrySample` validates the raw m/s value, but multiplying a
        // very large finite value by 3.6 can overflow the derived km/h display
        // unit. Reject that derived value before it can enter interpolation math
        // (`infinity - infinity` would otherwise produce a NaN render frame).
        let newTarget = sample.kilometersPerHour
        guard newTarget.isFinite, newTarget >= 0 else {
            throw SpeedDisplayInterpolationError.nonFiniteDisplaySpeed
        }

        let hadMeasurement = hasMeasurement
        let currentVisualValue: Double
        if hadMeasurement {
            currentVisualValue = frame(atUptimeNanoseconds: sample.receivedAtUptimeNanoseconds)?.kilometersPerHour ?? targetKilometersPerHour
        } else {
            currentVisualValue = newTarget
        }

        hasMeasurement = true
        anchorKilometersPerHour = currentVisualValue
        targetKilometersPerHour = newTarget
        transitionStartUptimeNanoseconds = sample.receivedAtUptimeNanoseconds
        let hasVisualDistance = abs(newTarget - currentVisualValue) > 1e-9
        self.transitionDurationNanoseconds = hadMeasurement && hasVisualDistance
            ? transitionDurationNanoseconds
            : 0
        latestMeasurementSource = sample.source
        latestMeasurementUptimeNanoseconds = sample.receivedAtUptimeNanoseconds
    }

    public func frame(atUptimeNanoseconds now: UInt64) -> SpeedDisplayFrame? {
        guard hasMeasurement else { return nil }

        let hasVisualDistance = abs(targetKilometersPerHour - anchorKilometersPerHour) > 1e-9
        let progress: Double
        if !hasVisualDistance || transitionDurationNanoseconds == 0 {
            progress = 1
        } else if now <= transitionStartUptimeNanoseconds {
            progress = 0
        } else {
            let elapsed = now - transitionStartUptimeNanoseconds
            progress = min(1, Double(elapsed) / Double(transitionDurationNanoseconds))
        }

        let visualValue = anchorKilometersPerHour
            + (targetKilometersPerHour - anchorKilometersPerHour) * progress
        let isAtMeasurement = progress >= 1 || abs(visualValue - targetKilometersPerHour) <= 1e-9

        return SpeedDisplayFrame(
            kilometersPerHour: visualValue,
            latestMeasuredKilometersPerHour: targetKilometersPerHour,
            latestMeasurementSource: latestMeasurementSource,
            latestMeasurementUptimeNanoseconds: latestMeasurementUptimeNanoseconds,
            origin: isAtMeasurement ? .measured : .visuallyInterpolated,
            transitionProgress: progress
        )
    }
}
