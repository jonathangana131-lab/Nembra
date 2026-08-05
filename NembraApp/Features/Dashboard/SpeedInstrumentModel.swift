import Foundation
import Observation

enum SpeedInstrumentDisplayOrigin: Equatable {
    /// A confirmed value from the latest vehicle state before a fresh raw speed
    /// sample has arrived in this process. This is not synthesized telemetry.
    case confirmedVehicleState
    /// The rendered value exactly equals the latest authoritative raw sample.
    case measuredTelemetry
    /// The rendered value exists only between authoritative raw samples.
    case visuallyInterpolated
}

struct SpeedInstrumentDisplayFrame: Equatable {
    let kilometersPerHour: Double
    let latestMeasuredKilometersPerHour: Double?
    let origin: SpeedInstrumentDisplayOrigin

    var isInterpolated: Bool {
        origin == .visuallyInterpolated
    }
}

/// Main-actor presentation state for the landscape speed instrument.
///
/// Raw evidence enters only through `SpeedTelemetrySample`. The high-frequency
/// render loop asks for a `SpeedInstrumentDisplayFrame` and never publishes its
/// interpolated values back into `VehicleState`, ride history, distance, stats,
/// or protocol diagnostics.
@MainActor
@Observable
final class SpeedInstrumentModel {
    private(set) var measurementRevision: UInt64 = 0
    private(set) var latestMeasurementSource: SpeedTelemetrySource?

    @ObservationIgnored private var interpolator = SpeedDisplayInterpolator()
    @ObservationIgnored private var previousMeasurementUptimeNanoseconds: UInt64?
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    deinit {
        streamTask?.cancel()
    }

    func start(stream: AsyncStream<SpeedTelemetrySample>) {
        guard streamTask == nil else { return }

        streamTask = Task { [weak self] in
            for await sample in stream {
                guard !Task.isCancelled, let self else { break }
                self.accept(sample)
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
    }

    /// Internal so the iOS test target can prove display semantics without a
    /// scheduler-sensitive fake stream.
    func accept(_ sample: SpeedTelemetrySample) {
        guard sample.isAuthoritativeMeasurement else { return }

        let transitionDuration = transitionDurationNanoseconds(for: sample)
        do {
            try interpolator.accept(
                sample,
                transitionDurationNanoseconds: transitionDuration
            )
        } catch {
            // Stale/non-authoritative samples never move presentation state.
            return
        }

        previousMeasurementUptimeNanoseconds = sample.receivedAtUptimeNanoseconds
        latestMeasurementSource = sample.source
        measurementRevision &+= 1
    }

    /// Returns a render-only frame. `fallbackConfirmedKilometersPerHour` is the
    /// latest value already present in confirmed `VehicleState`; it is used only
    /// until a fresh raw sample arrives and is never converted into a telemetry
    /// sample internally.
    func frame(
        atUptimeNanoseconds uptimeNanoseconds: UInt64,
        fallbackConfirmedKilometersPerHour: Double?
    ) -> SpeedInstrumentDisplayFrame? {
        _ = measurementRevision

        if let frame = interpolator.frame(atUptimeNanoseconds: uptimeNanoseconds) {
            return SpeedInstrumentDisplayFrame(
                kilometersPerHour: frame.kilometersPerHour,
                latestMeasuredKilometersPerHour: frame.latestMeasuredKilometersPerHour,
                origin: frame.isInterpolated ? .visuallyInterpolated : .measuredTelemetry
            )
        }

        guard let fallbackConfirmedKilometersPerHour,
              fallbackConfirmedKilometersPerHour.isFinite,
              fallbackConfirmedKilometersPerHour >= 0 else {
            return nil
        }

        return SpeedInstrumentDisplayFrame(
            kilometersPerHour: fallbackConfirmedKilometersPerHour,
            latestMeasuredKilometersPerHour: nil,
            origin: .confirmedVehicleState
        )
    }

    /// Transition timing follows the cadence we actually observe. We aim to
    /// settle shortly before the next similarly spaced measurement, while
    /// bounding animation duration so a long packet gap never creates a slow,
    /// predictive-looking speed ramp.
    private func transitionDurationNanoseconds(for sample: SpeedTelemetrySample) -> UInt64 {
        guard let previousMeasurementUptimeNanoseconds,
              sample.receivedAtUptimeNanoseconds > previousMeasurementUptimeNanoseconds else {
            return 0
        }

        let interval = sample.receivedAtUptimeNanoseconds - previousMeasurementUptimeNanoseconds
        let eightyPercent = (interval / 5) * 4
        let minimum: UInt64 = 50_000_000
        let maximum: UInt64 = 300_000_000
        return min(max(eightyPercent, minimum), maximum)
    }
}
