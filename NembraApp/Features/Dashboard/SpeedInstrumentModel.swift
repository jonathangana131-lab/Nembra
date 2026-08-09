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
    private(set) var latestMeasuredKilometersPerHour: Double?
    private(set) var isAnimationActive = false
    private(set) var permitsLiveConfirmedFallback = true

    @ObservationIgnored private var interpolator = SpeedDisplayInterpolator()
    @ObservationIgnored private var previousMeasurementUptimeNanoseconds: UInt64?
    @ObservationIgnored private var interpolationPolicy: SpeedInstrumentInterpolationPolicy = .disabled
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var animationEndTask: Task<Void, Never>?
    @ObservationIgnored private var acceptsTelemetryForCurrentConnection = true

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
        // Leaving the surface ends this model's raw observation continuity.
        // VehicleStore may keep receiving confirmed state globally, so preserve
        // fallback eligibility while dropping raw/interpolated anchors that can
        // no longer be known current when the view returns.
        clearRawPresentationContinuity()
    }

    /// Opens or closes raw-speed presentation continuity for the currently
    /// confirmed vehicle connection.
    ///
    /// A disconnect/reconnecting/connecting boundary is authoritative evidence
    /// of a presentation gap even though it says nothing about the scooter's
    /// physical speed. Old raw samples therefore stop driving the live readout,
    /// and samples delivered during the gap are ignored. Reconnection starts a
    /// new presentation continuity without inventing a cadence-based timeout.
    ///
    /// Once a gap has been observed, a cached `VehicleState` speed must also not
    /// regain live meaning merely because transport becomes connected again.
    /// Retained presentation may still show that cached value explicitly as last
    /// known; the live cockpit waits for a new accepted raw sample instead.
    func setConnectionContinuityActive(_ isActive: Bool) {
        acceptsTelemetryForCurrentConnection = isActive
        guard !isActive else { return }

        permitsLiveConfirmedFallback = false
        clearRawPresentationContinuity()
    }

    /// Internal so the iOS test target can prove display semantics without a
    /// scheduler-sensitive fake stream.
    func accept(_ sample: SpeedTelemetrySample) {
        guard acceptsTelemetryForCurrentConnection,
              sample.isAuthoritativeMeasurement else { return }

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
        latestMeasuredKilometersPerHour = sample.kilometersPerHour
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
    /// confirmed in `VehicleState`; the caller decides whether that fallback is
    /// still eligible for the current presentation continuity. It is never
    /// converted into a telemetry sample internally.
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

    private func clearRawPresentationContinuity() {
        animationEndTask?.cancel()
        animationEndTask = nil
        isAnimationActive = false
        interpolator = SpeedDisplayInterpolator()
        previousMeasurementUptimeNanoseconds = nil
        latestMeasurementSource = nil
        latestMeasuredKilometersPerHour = nil
    }
}

/// A deliberately narrow high-frequency subtree for the landscape cockpit.
///
/// Only the rolling speed readout redraws on SwiftUI's animation timeline.
/// Status, accessibility formatting, vehicle controls, ride detection,
/// persistence, distance, and safety continue to consume confirmed/raw domain
/// state rather than the rendered interpolation frame.
@MainActor
struct DashboardSpeedInstrumentView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = SpeedInstrumentModel()

    let modePersonality: DashboardModePersonality

    var body: some View {
        let isRetained = vehicle.state.dataAvailability == .retained
        let fallbackConfirmedKilometersPerHour = Self.confirmedFallbackForPresentation(
            kilometersPerHour: vehicle.state.speedKilometersPerHour,
            isRetained: isRetained,
            isConnected: vehicle.state.connection == .connected,
            permitsLiveConfirmedFallback: model.permitsLiveConfirmedFallback
        )
        let usesMetric = VehicleDisplayFormatting.usesMetric
        let authoritativeKilometersPerHour = Self.validatedKilometersPerHour(
            model.latestMeasuredKilometersPerHour
        ) ?? fallbackConfirmedKilometersPerHour

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            speedReadout(
                fallbackConfirmedKilometersPerHour: fallbackConfirmedKilometersPerHour,
                usesMetric: usesMetric
            )
            .frame(maxWidth: .infinity)
            .scaleEffect(modePersonality.speedScale)
            .animation(modeAnimation, value: modePersonality.speedScale)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Speed")
            // VoiceOver stays anchored to the newest authoritative/raw speed,
            // never a 60 Hz visual interpolation midpoint or malformed value.
            // Retained values carry their last-known qualifier on the speed
            // element itself so focus order cannot make cached evidence sound live.
            .accessibilityValue(
                Self.accessibilitySpeedValue(
                    kilometersPerHour: authoritativeKilometersPerHour,
                    isRetained: isRetained
                )
            )
            .accessibilityIdentifier("dashboard.speed")

            Group {
                if isRetained, authoritativeKilometersPerHour != nil {
                    Label("LAST KNOWN", systemImage: "clock.arrow.circlepath")
                } else if vehicle.state.connection == .connected {
                    Text(Self.liveSpeedStatusText(
                        kilometersPerHour: authoritativeKilometersPerHour
                    ))
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
        .task {
            model.configureInterpolationPolicy(vehicle.speedInstrumentInterpolationPolicy)
            // Initialize the connection gate before subscribing so raw evidence
            // cannot be accepted based on SwiftUI modifier callback ordering.
            model.setConnectionContinuityActive(vehicle.state.connection == .connected)
            let stream = await vehicle.speedTelemetryUpdates()
            model.start(stream: stream)
        }
        .onChange(of: vehicle.state.connection, initial: true) { _, connection in
            model.setConnectionContinuityActive(connection == .connected)
        }
        .onDisappear {
            model.stop()
        }
    }

    private func speedReadout(
        fallbackConfirmedKilometersPerHour: Double?,
        usesMetric: Bool
    ) -> some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 60.0,
                paused: reduceMotion || !model.isAnimationActive
            )
        ) { _ in
            let frame = model.frame(
                atUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                fallbackConfirmedKilometersPerHour: fallbackConfirmedKilometersPerHour,
                prefersReducedMotion: reduceMotion
            )

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                RollingSpeedValueView(
                    value: Self.displayedValue(
                        kilometersPerHour: frame?.kilometersPerHour,
                        usesMetric: usesMetric
                    )
                )
                .font(.system(size: 148, weight: .medium, design: .rounded))
                .monospacedDigit()
                .tracking(-7)
                .lineLimit(1)
                .minimumScaleFactor(0.58)

                Text(usesMetric ? "KM/H" : "MPH")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 18)
            }
            .accessibilityHidden(true)
        }
    }

    static func displayedValue(
        kilometersPerHour: Double?,
        usesMetric: Bool
    ) -> Double? {
        guard let kilometersPerHour = validatedKilometersPerHour(kilometersPerHour) else {
            return nil
        }
        return usesMetric ? kilometersPerHour : kilometersPerHour * 0.621_371
    }

    static func confirmedFallbackForPresentation(
        kilometersPerHour: Double?,
        isRetained: Bool,
        isConnected: Bool,
        permitsLiveConfirmedFallback: Bool
    ) -> Double? {
        guard let kilometersPerHour = validatedKilometersPerHour(kilometersPerHour) else {
            return nil
        }
        if isRetained { return kilometersPerHour }
        guard isConnected, permitsLiveConfirmedFallback else { return nil }
        return kilometersPerHour
    }

    static func accessibilitySpeedValue(
        kilometersPerHour: Double?,
        isRetained: Bool
    ) -> String {
        VehicleDisplayFormatting.accessibilitySpeed(
            kilometersPerHour: validatedKilometersPerHour(kilometersPerHour),
            isRetained: isRetained
        )
    }

    static func liveSpeedStatusText(kilometersPerHour: Double?) -> String {
        guard let kilometersPerHour = validatedKilometersPerHour(kilometersPerHour) else {
            return "NO LIVE SPEED"
        }
        return kilometersPerHour >= 0.5 ? "RIDING" : "READY"
    }

    static func validatedKilometersPerHour(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value == 0 ? 0 : value
    }

    private var modeAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.26)
    }
}
