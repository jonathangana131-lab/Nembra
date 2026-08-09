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
/// Accepted speed evidence enters through `SpeedTelemetrySample`. High-frequency
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

    /// Narrow test/legacy seam for a caller that already owns raw-stream
    /// continuity. The Dashboard itself intentionally does not subscribe here:
    /// its positive authority is the source-qualified `SpeedEvidenceAvailability`
    /// stream exposed by `VehicleStore`.
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
        // Leaving the surface ends this model's presentation continuity.
        // Source-owned availability may still retain the latest accepted value,
        // but no old raw/interpolated anchor is allowed to survive view teardown.
        clearRawPresentationContinuity()
    }

    /// Opens or closes speed presentation continuity for the currently confirmed
    /// vehicle connection.
    ///
    /// Connection loss is an immediate fail-closed boundary. Reconnection alone
    /// intentionally does not restore `permitsLiveConfirmedFallback`; the
    /// source-owned evidence provider must publish a new `.live` observation.
    /// This method remains as a defensive transport boundary and as a narrow
    /// test seam; the Dashboard's positive currentness authority is
    /// `setSpeedEvidenceAvailability(_:)` below.
    func setConnectionContinuityActive(_ isActive: Bool) {
        acceptsTelemetryForCurrentConnection = isActive
        guard !isActive else { return }

        permitsLiveConfirmedFallback = false
        clearRawPresentationContinuity()
    }

    /// Consumes source-owned field currentness without inventing a cadence or
    /// timeout. `.retained` and `.unavailable` immediately retire interpolated
    /// presentation even when aggregate transport remains connected. `.live`
    /// reopens presentation only because the provider supplies the exact accepted
    /// absolute sample that established current field continuity.
    ///
    /// The Dashboard drives this method from the provider's newest-current-state
    /// availability stream instead of a second non-tokenized raw stream. This
    /// prevents a delayed pre-gap raw packet from racing the currentness demotion,
    /// and it intentionally allows slow consumers to skip obsolete intermediate
    /// display targets and retarget to the newest accepted sample.
    func setSpeedEvidenceAvailability(_ availability: SpeedEvidenceAvailability) {
        switch availability {
        case .unavailable, .retained:
            acceptsTelemetryForCurrentConnection = false
            permitsLiveConfirmedFallback = false
            clearRawPresentationContinuity()

        case let .live(sample):
            acceptsTelemetryForCurrentConnection = true
            permitsLiveConfirmedFallback = false
            accept(sample)
        }
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

    /// Returns a render-only frame. The fallback is a caller-owned accepted
    /// source value; the Dashboard supplies it from `SpeedEvidenceAvailability`
    /// rather than treating cached `VehicleState.speed` as field-current authority.
    /// It is never converted into a telemetry sample internally.
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
/// persistence, distance, and safety continue to consume accepted domain/source
/// state rather than the rendered interpolation frame.
@MainActor
struct DashboardSpeedInstrumentView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = SpeedInstrumentModel()

    let modePersonality: DashboardModePersonality

    var body: some View {
        let speedAvailability = vehicle.speedEvidenceAvailability
        let isRetained = Self.isRetainedSpeedEvidence(speedAvailability)
        let fallbackAcceptedKilometersPerHour = Self.evidenceBackedFallback(
            speedAvailability
        )
        let usesMetric = VehicleDisplayFormatting.usesMetric
        let authoritativeKilometersPerHour = Self.validatedKilometersPerHour(
            model.latestMeasuredKilometersPerHour
        ) ?? fallbackAcceptedKilometersPerHour

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            speedReadout(
                fallbackAcceptedKilometersPerHour: fallbackAcceptedKilometersPerHour,
                usesMetric: usesMetric
            )
            .frame(maxWidth: .infinity)
            .scaleEffect(modePersonality.speedScale)
            .animation(modeAnimation, value: modePersonality.speedScale)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Speed")
            // VoiceOver stays anchored to the newest source-owned accepted speed,
            // never a 60 Hz visual interpolation midpoint or cached VehicleState.
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
                } else if Self.isLiveSpeedEvidence(speedAvailability) {
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
            // Initialize from source-owned field currentness. Positive speed
            // presentation authority is intentionally not sourced from the
            // separate raw stream because that stream carries no continuity token.
            model.setSpeedEvidenceAvailability(vehicle.speedEvidenceAvailability)
        }
        .onChange(of: vehicle.speedEvidenceAvailability, initial: true) { _, availability in
            model.setSpeedEvidenceAvailability(availability)
        }
        .onChange(of: vehicle.state.connection, initial: true) { _, connection in
            // Transport may retire authority immediately; it can never restore
            // authority here. Positive currentness comes only from `.live` source
            // evidence above.
            if connection != .connected {
                model.setConnectionContinuityActive(false)
            }
        }
        .onDisappear {
            model.stop()
        }
    }

    private func speedReadout(
        fallbackAcceptedKilometersPerHour: Double?,
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
                fallbackConfirmedKilometersPerHour: fallbackAcceptedKilometersPerHour,
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

    /// Presentation fallback is source-owned accepted speed only. Aggregate
    /// `VehicleState.dataAvailability` and cached speed are deliberately excluded
    /// because a field-specific speed gap can occur while the rest of the vehicle
    /// state and transport remain current.
    static func evidenceBackedFallback(
        _ availability: SpeedEvidenceAvailability
    ) -> Double? {
        validatedKilometersPerHour(availability.lastAcceptedSample?.kilometersPerHour)
    }

    static func isRetainedSpeedEvidence(_ availability: SpeedEvidenceAvailability) -> Bool {
        if case .retained = availability { return true }
        return false
    }

    static func isLiveSpeedEvidence(_ availability: SpeedEvidenceAvailability) -> Bool {
        if case .live = availability { return true }
        return false
    }

    /// Kept as a narrow compatibility/test helper for callers that need to
    /// reason about legacy confirmed-state presentation. The Dashboard itself no
    /// longer uses this helper as positive speed-currentness authority.
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
