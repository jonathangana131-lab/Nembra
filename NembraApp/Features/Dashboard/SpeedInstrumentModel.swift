import Dispatch
import Foundation
import Observation
import SwiftUI

enum SpeedInstrumentDisplayOrigin: Equatable {
    /// Exact accepted source evidence used directly because no matching render-clock frame is safe.
    case acceptedSourceFallback
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

    @ObservationIgnored private var interpolator = SpeedDisplayInterpolator()
    @ObservationIgnored private var latestAcceptedSample: SpeedTelemetrySample?
    @ObservationIgnored private var previousMeasurementUptimeNanoseconds: UInt64?
    @ObservationIgnored private var interpolationPolicy: SpeedInstrumentInterpolationPolicy = .disabled
    @ObservationIgnored private var animationEndTask: Task<Void, Never>?

    deinit {
        animationEndTask?.cancel()
    }

    /// Policy must be chosen by app bootstrap, not inferred from the vehicle
    /// model. Production remains disabled until real AOVOPRO ES80 cadence is measured.
    func configureInterpolationPolicy(_ policy: SpeedInstrumentInterpolationPolicy) {
        guard measurementRevision == 0 else { return }
        interpolationPolicy = policy
    }

    func stop() {
        clearPresentationContinuity()
    }

    /// Source-owned speed currentness is the Dashboard's positive presentation
    /// authority. Retained/unavailable immediately retire interpolation. A new
    /// live sample can reopen motion without guessing a freshness timeout.
    func setSpeedEvidenceAvailability(_ availability: SpeedEvidenceAvailability) {
        switch availability {
        case .unavailable, .retained:
            clearPresentationContinuity()
        case let .live(sample):
            accept(sample)
        }
    }

    /// Internal test seam for the interpolation primitive. Production Dashboard
    /// code admits samples only through `setSpeedEvidenceAvailability(_:)` so
    /// currentness remains source-owned rather than recreated from a raw stream.
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

        latestAcceptedSample = sample
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

    /// Returns the only numeric frame eligible for the current source-owned field state.
    ///
    /// This gate is deliberately synchronous. SwiftUI may render a newly demoted or newly live
    /// `SpeedEvidenceAvailability` before the `.onChange` side effect has updated this model. A
    /// stale interpolation frame must never survive that ordering window:
    /// - unavailable renders no number;
    /// - retained renders the exact accepted retained sample, never interpolation;
    /// - live may use interpolation only when the model is already bound to that exact sample.
    ///
    /// The later `setSpeedEvidenceAvailability(_:)` call still clears/retargets model state, but
    /// visual truth does not depend on callback scheduling.
    func frame(
        for availability: SpeedEvidenceAvailability,
        atUptimeNanoseconds uptimeNanoseconds: UInt64,
        prefersReducedMotion: Bool = false
    ) -> SpeedInstrumentDisplayFrame? {
        switch availability {
        case .unavailable:
            return nil

        case let .retained(sample):
            return acceptedSourceFallbackFrame(sample)

        case let .live(sample):
            guard sample.isAuthoritativeMeasurement else { return nil }

            // A new source-owned sample can become visible before `.onChange` admits it into the
            // render clock. Until the model carries that exact sample, show exact accepted truth
            // rather than a frame derived from an older connection/continuity segment.
            guard latestAcceptedSample == sample else {
                return acceptedSourceFallbackFrame(sample)
            }

            return frame(
                atUptimeNanoseconds: uptimeNanoseconds,
                fallbackAcceptedKilometersPerHour: sample.kilometersPerHour,
                prefersReducedMotion: prefersReducedMotion
            )
        }
    }

    /// Returns a render-only frame from the model's currently admitted live sample. The fallback
    /// is caller-owned accepted source evidence, never cached aggregate vehicle state.
    ///
    /// Reduce Motion changes presentation only: when an interpolation frame is active, the display
    /// snaps to the latest authoritative measurement that the interpolator already carries. No
    /// measurement, telemetry, or interpolation state is mutated by this preference.
    func frame(
        atUptimeNanoseconds uptimeNanoseconds: UInt64,
        fallbackAcceptedKilometersPerHour: Double?,
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

        guard let fallbackAcceptedKilometersPerHour,
              fallbackAcceptedKilometersPerHour.isFinite,
              fallbackAcceptedKilometersPerHour >= 0 else {
            return nil
        }

        return SpeedInstrumentDisplayFrame(
            kilometersPerHour: fallbackAcceptedKilometersPerHour,
            latestMeasuredKilometersPerHour: nil,
            origin: .acceptedSourceFallback
        )
    }

    /// Exact source-owned evidence used when render-clock state is not eligible for the current
    /// semantic availability. This helper intentionally does not read or mutate the interpolator.
    private func acceptedSourceFallbackFrame(
        _ sample: SpeedTelemetrySample
    ) -> SpeedInstrumentDisplayFrame? {
        guard sample.isAuthoritativeMeasurement,
              sample.kilometersPerHour.isFinite,
              sample.kilometersPerHour >= 0 else {
            return nil
        }

        return SpeedInstrumentDisplayFrame(
            kilometersPerHour: sample.kilometersPerHour,
            latestMeasuredKilometersPerHour: nil,
            origin: .acceptedSourceFallback
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

    private func clearPresentationContinuity() {
        animationEndTask?.cancel()
        animationEndTask = nil
        isAnimationActive = false
        interpolator = SpeedDisplayInterpolator()
        latestAcceptedSample = nil
        previousMeasurementUptimeNanoseconds = nil
        latestMeasurementSource = nil
        latestMeasuredKilometersPerHour = nil
    }
}

/// A deliberately narrow high-frequency subtree for the landscape cockpit.
///
/// Only this view redraws on SwiftUI's animation timeline. Vehicle controls,
/// ride detection, persistence, distance, and safety continue to consume the
/// accepted domain/source state rather than the rendered interpolation frame.
@MainActor
struct DashboardSpeedInstrumentView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = SpeedInstrumentModel()

    let modePersonality: DashboardModePersonality

    var body: some View {
        let speedAvailability = vehicle.speedEvidenceAvailability
        let hasLiveSpeedEvidence: Bool
        switch speedAvailability {
        case .live:
            hasLiveSpeedEvidence = true
        case .retained, .unavailable:
            hasLiveSpeedEvidence = false
        }

        TimelineView(
            .animation(
                minimumInterval: 1.0 / 60.0,
                paused: reduceMotion || !hasLiveSpeedEvidence || !model.isAnimationActive
            )
        ) { _ in
            let frame = model.frame(
                for: speedAvailability,
                atUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                prefersReducedMotion: reduceMotion
            )

            instrumentContent(frame: frame, speedAvailability: speedAvailability)
        }
        .task {
            model.configureInterpolationPolicy(vehicle.speedInstrumentInterpolationPolicy)
            model.setSpeedEvidenceAvailability(vehicle.speedEvidenceAvailability)
        }
        .onChange(of: vehicle.speedEvidenceAvailability) { _, availability in
            model.setSpeedEvidenceAvailability(availability)
        }
        .onDisappear {
            model.stop()
        }
    }

    private func instrumentContent(
        frame: SpeedInstrumentDisplayFrame?,
        speedAvailability: SpeedEvidenceAvailability
    ) -> some View {
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
            // VoiceOver consumes the same field-specific accepted speed state,
            // never a 60 Hz render midpoint or cached aggregate speed as fresh truth.
            .accessibilityValue(accessibilitySpeed(speedAvailability))
            .accessibilityIdentifier("dashboard.speed")

            Group {
                switch speedAvailability {
                case .retained:
                    Label("LAST KNOWN", systemImage: "clock.arrow.circlepath")
                case let .live(sample):
                    Text(sample.kilometersPerHour >= 0.5 ? "RIDING" : "READY")
                case .unavailable:
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
        guard let kilometersPerHour,
              kilometersPerHour.isFinite,
              kilometersPerHour >= 0 else {
            return nil
        }
        let normalized = kilometersPerHour == 0 ? 0 : kilometersPerHour
        return VehicleDisplayFormatting.usesMetric ? normalized : normalized * 0.621_371
    }

    private func accessibilitySpeed(_ availability: SpeedEvidenceAvailability) -> String {
        switch availability {
        case .unavailable:
            return "Unavailable"
        case let .retained(sample):
            return "Last known, \(VehicleDisplayFormatting.speed(kilometersPerHour: sample.kilometersPerHour))"
        case let .live(sample):
            return VehicleDisplayFormatting.speed(kilometersPerHour: sample.kilometersPerHour)
        }
    }

    private var speedUnitText: String {
        VehicleDisplayFormatting.usesMetric ? "KM/H" : "MPH"
    }

    private var modeAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.26)
    }
}
