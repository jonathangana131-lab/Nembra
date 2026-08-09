import Dispatch
import Foundation
import Observation
import SwiftUI

enum SpeedInstrumentDisplayOrigin: Equatable {
    case confirmedVehicleState
    case measuredTelemetry
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
/// Raw evidence enters only through `SpeedTelemetrySample`. High-frequency
/// render frames never flow back into `VehicleState`, ride history, distance,
/// stats, or protocol diagnostics.
@MainActor
@Observable
final class SpeedInstrumentModel {
    private(set) var measurementRevision: UInt64 = 0
    private(set) var latestMeasurementSource: SpeedTelemetrySource?
    private(set) var isAnimationActive = false

    @ObservationIgnored private var interpolator = SpeedDisplayInterpolator()
    @ObservationIgnored private var previousMeasurementUptimeNanoseconds: UInt64?
    @ObservationIgnored private var interpolationPolicy: SpeedInstrumentInterpolationPolicy = .disabled
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var animationEndTask: Task<Void, Never>?

    deinit {
        streamTask?.cancel()
        animationEndTask?.cancel()
    }

    /// Policy must be chosen by app bootstrap, not inferred from the vehicle
    /// model. Production remains disabled until real AOVOPRO ES80 cadence is measured.
    func configureInterpolationPolicy(_ policy: SpeedInstrumentInterpolationPolicy) {
        guard measurementRevision == 0 else { return }
        interpolationPolicy = policy
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
        animationEndTask?.cancel()
        animationEndTask = nil
        isAnimationActive = false
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

        let startsInterpolating = interpolator
            .frame(atUptimeNanoseconds: sample.receivedAtUptimeNanoseconds)?
            .isInterpolated == true
        scheduleAnimationWindow(
            active: startsInterpolating,
            durationNanoseconds: transitionDuration
        )
    }

    /// Returns a render-only frame. The fallback is the latest value already
    /// confirmed in `VehicleState`; it is used only until fresh raw telemetry
    /// arrives and is never converted into a telemetry sample internally.
    ///
    /// Reduce Motion changes presentation only: when an interpolation frame is
    /// active, the display snaps to the latest authoritative measurement that
    /// the interpolator already carries. No measurement, telemetry, or
    /// interpolation state is mutated by this preference.
    func frame(
        atUptimeNanoseconds uptimeNanoseconds: UInt64,
        fallbackConfirmedKilometersPerHour: Double?,
        prefersReducedMotion: Bool = false
    ) -> SpeedInstrumentDisplayFrame? {
        _ = measurementRevision

        if let frame = interpolator.frame(atUptimeNanoseconds: uptimeNanoseconds) {
            if prefersReducedMotion {
                return SpeedInstrumentDisplayFrame(
                    kilometersPerHour: frame.latestMeasuredKilometersPerHour,
                    latestMeasuredKilometersPerHour: frame.latestMeasuredKilometersPerHour,
                    origin: .measuredTelemetry
                )
            }

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

    /// Duration is derived only when an injected policy enables interpolation.
    /// The production policy is disabled until real hardware cadence is measured.
    private func transitionDurationNanoseconds(for sample: SpeedTelemetrySample) -> UInt64 {
        let policy = interpolationPolicy
        guard policy.isEnabled,
              let previousMeasurementUptimeNanoseconds,
              sample.receivedAtUptimeNanoseconds > previousMeasurementUptimeNanoseconds else {
            return 0
        }

        let interval = sample.receivedAtUptimeNanoseconds - previousMeasurementUptimeNanoseconds
        guard interval <= policy.maximumContinuousSampleIntervalNanoseconds else {
            return 0
        }

        let requested = UInt64(Double(interval) * policy.intervalFraction)
        return min(
            max(requested, policy.minimumTransitionNanoseconds),
            policy.maximumContinuousSampleIntervalNanoseconds
        )
    }

    private func scheduleAnimationWindow(active: Bool, durationNanoseconds: UInt64) {
        animationEndTask?.cancel()
        animationEndTask = nil
        isAnimationActive = active && durationNanoseconds > 0

        guard isAnimationActive else { return }

        animationEndTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: durationNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.isAnimationActive = false
            self?.animationEndTask = nil
        }
    }
}

/// A deliberately narrow high-frequency subtree for the landscape cockpit.
///
/// Only this view redraws on SwiftUI's animation timeline. Vehicle controls,
/// ride detection, persistence, distance, and safety continue to consume the
/// confirmed/raw domain state rather than the rendered interpolation frame.
@MainActor
struct DashboardSpeedInstrumentView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = SpeedInstrumentModel()

    let modePersonality: DashboardModePersonality

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 60.0,
                paused: reduceMotion || !model.isAnimationActive
            )
        ) { _ in
            let frame = model.frame(
                atUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                fallbackConfirmedKilometersPerHour: vehicle.state.speedKilometersPerHour,
                prefersReducedMotion: reduceMotion
            )

            instrumentContent(frame: frame)
        }
        .task {
            model.configureInterpolationPolicy(vehicle.speedInstrumentInterpolationPolicy)
            let stream = await vehicle.speedTelemetryUpdates()
            model.start(stream: stream)
        }
        .onDisappear {
            model.stop()
        }
    }

    private func instrumentContent(frame: SpeedInstrumentDisplayFrame?) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                RollingSpeedValueView(value: displayedValue(kilometersPerHour: frame?.kilometersPerHour))
                    .font(.system(size: 148, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .tracking(-7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .accessibilityHidden(true)

                Text(speedUnitText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 18)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .scaleEffect(modePersonality.speedScale)
            .animation(modeAnimation, value: modePersonality.speedScale)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Speed")
            // VoiceOver announces accepted semantic truth rather than a visual
            // midpoint or punctuation-only placeholder.
            .accessibilityValue(accessibilitySpeed(frame: frame))
            .accessibilityIdentifier("dashboard.speed")

            Group {
                if vehicle.state.dataAvailability == .retained {
                    Label("LAST KNOWN", systemImage: "clock.arrow.circlepath")
                } else if vehicle.state.connection == .connected {
                    Text(isVehicleMoving ? "RIDING" : "READY")
                } else {
                    Text("NO LIVE SPEED")
                }
            }
            .font(.caption2.weight(.bold))
            .tracking(2.2)
            .foregroundStyle(Color.white.opacity(modePersonality.statusOpacity))
            .animation(modeAnimation, value: modePersonality.statusOpacity)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
    }

    private func displayedValue(kilometersPerHour: Double?) -> Double? {
        guard let kilometersPerHour else { return nil }
        let nonnegative = max(0, kilometersPerHour)
        return VehicleDisplayFormatting.usesMetric ? nonnegative : nonnegative * 0.621_371
    }

    private func accessibilitySpeed(frame: SpeedInstrumentDisplayFrame?) -> String {
        // Whole-vehicle unavailability is an explicit semantic stop: a stale
        // render frame must not remain VoiceOver authority after evidence is gone.
        if vehicle.state.dataAvailability == .unavailable {
            return "Unavailable"
        }

        let authoritativeKilometersPerHour = frame?.latestMeasuredKilometersPerHour
            ?? vehicle.state.speedKilometersPerHour
        guard let authoritativeKilometersPerHour,
              authoritativeKilometersPerHour.isFinite,
              authoritativeKilometersPerHour >= 0 else {
            return "Unavailable"
        }

        let formatted = VehicleDisplayFormatting.speed(
            kilometersPerHour: authoritativeKilometersPerHour
        )
        guard formatted != "—" else { return "Unavailable" }

        if vehicle.state.dataAvailability == .retained {
            return "Last known, \(formatted)"
        }
        return formatted
    }

    private var speedUnitText: String {
        VehicleDisplayFormatting.usesMetric ? "KM/H" : "MPH"
    }

    private var isVehicleMoving: Bool {
        (vehicle.state.speedKilometersPerHour ?? 0) >= 0.5
    }

    private var modeAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.26)
    }
}
