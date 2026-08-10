import Dispatch
import Foundation
import Observation
import SwiftUI
import struct NembraCore.PropulsionEnergyRailAppProjection
import struct NembraCore.PropulsionEnergyRailSimulatorRuntime

enum SpeedInstrumentDisplayOrigin: Equatable {
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

extension SpeedEvidenceAvailability {
    /// Strict production-default sanitizer. Simulator evidence is unavailable
    /// unless an explicit Simulator profile opts in through the function below.
    var dashboardPresentationAvailability: SpeedEvidenceAvailability {
        dashboardPresentationAvailability(allowsSimulatorQA: false)
    }

    /// Dashboard presentation accepts only absolute-measurement speed evidence
    /// whose source is permitted for the active app profile.
    ///
    /// `SpeedEvidenceAvailability` and `SpeedTelemetrySample` are public/caller-
    /// constructible, so neither the enum wrapper nor absolute provenance alone
    /// proves that a buggy provider preserved the accepted source contract.
    /// Synthetic `.simulatorQA` evidence is eligible only when the app explicitly
    /// owns the Simulator QA profile. Physical/unverified profiles therefore
    /// cannot borrow synthetic speed by wrapping it as `.live` or `.retained`.
    func dashboardPresentationAvailability(
        allowsSimulatorQA: Bool
    ) -> SpeedEvidenceAvailability {
        func admits(_ sample: SpeedTelemetrySample) -> Bool {
            guard sample.isAuthoritativeMeasurement else { return false }
            return sample.source != .simulatorQA || allowsSimulatorQA
        }

        switch self {
        case .unavailable:
            return .unavailable
        case let .retained(sample):
            return admits(sample) ? .retained(sample) : .unavailable
        case let .live(sample):
            return admits(sample) ? .live(sample) : .unavailable
        }
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
    private(set) var latestMeasurementUptimeNanoseconds: UInt64?
    private(set) var latestAcceptedSample: SpeedTelemetrySample?
    private(set) var isAnimationActive = false

    @ObservationIgnored private var interpolator = SpeedDisplayInterpolator()
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
    /// live absolute measurement can reopen motion without guessing a freshness timeout.
    func setSpeedEvidenceAvailability(
        _ availability: SpeedEvidenceAvailability,
        allowsSimulatorQA: Bool = false
    ) {
        switch availability.dashboardPresentationAvailability(allowsSimulatorQA: allowsSimulatorQA) {
        case .unavailable, .retained:
            clearPresentationContinuity()
        case let .live(sample):
            accept(sample)
        }
    }

    /// Internal test seam for the interpolation primitive. Production Dashboard
    /// code admits samples only through `setSpeedEvidenceAvailability` so
    /// currentness and source eligibility remain app-owned rather than recreated
    /// from a raw stream.
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
        latestMeasuredKilometersPerHour = sample.kilometersPerHour
        latestMeasurementUptimeNanoseconds = sample.receivedAtUptimeNanoseconds
        latestAcceptedSample = sample
        measurementRevision &+= 1

        let startsInterpolating = interpolator
            .frame(atUptimeNanoseconds: sample.receivedAtUptimeNanoseconds)?
            .isInterpolated == true
        scheduleAnimationWindow(
            active: startsInterpolating,
            durationNanoseconds: transitionDuration
        )
    }

    /// Returns a render-only frame. The fallback is caller-owned accepted source
    /// evidence and is never promoted into telemetry by this model.
    ///
    /// Reduce Motion changes presentation only: when an interpolation frame is
    /// active, the display snaps to the latest authoritative measurement that
    /// the interpolator already carries. No measurement, telemetry, or
    /// interpolation state is mutated by this preference.
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

        return acceptedSourceFallbackFrame(
            kilometersPerHour: fallbackAcceptedKilometersPerHour
        )
    }

    /// Synchronous visual truth boundary for the current field-specific source state.
    ///
    /// SwiftUI may render a newly observed availability value before `.onChange`
    /// retires or retargets the local interpolator. Do not let callback scheduling
    /// decide what numeric truth is visible during that render:
    /// - unavailable, non-authoritative, or source-ineligible evidence renders no
    ///   number immediately;
    /// - retained renders exactly its accepted last-known sample;
    /// - live may consume local interpolation only when that interpolation already
    ///   targets the exact current accepted sample. Otherwise it snaps to current
    ///   source truth until lifecycle cleanup/retargeting catches up.
    func presentationFrame(
        for availability: SpeedEvidenceAvailability,
        atUptimeNanoseconds uptimeNanoseconds: UInt64,
        prefersReducedMotion: Bool = false,
        allowsSimulatorQA: Bool = false
    ) -> SpeedInstrumentDisplayFrame? {
        switch availability.dashboardPresentationAvailability(allowsSimulatorQA: allowsSimulatorQA) {
        case .unavailable:
            return nil

        case let .retained(sample):
            return acceptedSourceFallbackFrame(
                kilometersPerHour: sample.kilometersPerHour
            )

        case let .live(sample):
            // `SpeedTelemetrySample` carries the complete accepted display-target
            // identity used here: source, provenance, value, receipt clocks,
            // optional measurement clock, and optional accuracy. Partial matching
            // can collide with a distinct accepted sample and replay an old target.
            guard latestAcceptedSample == sample else {
                return acceptedSourceFallbackFrame(
                    kilometersPerHour: sample.kilometersPerHour
                )
            }

            return frame(
                atUptimeNanoseconds: uptimeNanoseconds,
                fallbackAcceptedKilometersPerHour: sample.kilometersPerHour,
                prefersReducedMotion: prefersReducedMotion
            )
        }
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

    private func acceptedSourceFallbackFrame(
        kilometersPerHour: Double?
    ) -> SpeedInstrumentDisplayFrame? {
        guard let kilometersPerHour,
              kilometersPerHour.isFinite,
              kilometersPerHour >= 0 else {
            return nil
        }

        return SpeedInstrumentDisplayFrame(
            kilometersPerHour: kilometersPerHour,
            latestMeasuredKilometersPerHour: nil,
            origin: .acceptedSourceFallback
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
        previousMeasurementUptimeNanoseconds = nil
        latestMeasurementSource = nil
        latestMeasuredKilometersPerHour = nil
        latestMeasurementUptimeNanoseconds = nil
        latestAcceptedSample = nil
    }
}

/// A deliberately narrow high-frequency subtree for the landscape cockpit.
///
/// Only this view redraws on the animation timeline. Vehicle controls, ride
/// detection, persistence, distance, and safety continue to consume accepted
/// domain/source state rather than rendered speed or Energy Rail frames.
/// Propulsion authority enters only through `VehicleStore.simulatorPowerStoreProjection`.
/// Aggregate watts, speed receipts, ride mode, view lifecycle, and display clocks
/// can only affect presentation, never mint a propulsion measurement.
@MainActor
struct DashboardSpeedInstrumentView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = SpeedInstrumentModel()
    @State private var energyRailRuntime: PropulsionEnergyRailSimulatorRuntime? = try? PropulsionEnergyRailSimulatorRuntime()
    @State private var energyRailNextTransitionUptimeNanoseconds: UInt64? = nil
    @State private var energyRailPresentationRevision: UInt64 = 0

    let modePersonality: DashboardModePersonality

    var body: some View {
        let allowsSimulatorQA = vehicle.profile == .simulatorQA
        let rawSpeedAvailability = vehicle.speedEvidenceAvailability
        let speedAvailability = rawSpeedAvailability.dashboardPresentationAvailability(
            allowsSimulatorQA: allowsSimulatorQA
        )
        let sourceCapability = hasEnergyRailSourceCapability
        let storeProjection = energyRailStoreProjection
        let scheduleNow = DispatchTime.now().uptimeNanoseconds
        let speedShouldTick = !reduceMotion
            && model.isAnimationActive
            && isLivePresentation(speedAvailability)
        let energyRailShouldTick: Bool
        if !reduceMotion,
           sourceCapability,
           storeProjection.currentness == .live,
           let energyRailRuntime,
           projectionMatchesStore(
               energyRailRuntime.projection(atUptimeNanoseconds: scheduleNow),
               storeProjection: storeProjection
           ) {
            energyRailShouldTick = energyRailRuntime.displaySchedule(
                atUptimeNanoseconds: scheduleNow
            ).requiresContinuousFrames
        } else {
            energyRailShouldTick = false
        }

        TimelineView(
            .animation(
                minimumInterval: 1.0 / 60.0,
                paused: !(speedShouldTick || energyRailShouldTick)
            )
        ) { _ in
            let now = DispatchTime.now().uptimeNanoseconds
            let frame = model.presentationFrame(
                for: rawSpeedAvailability,
                atUptimeNanoseconds: now,
                prefersReducedMotion: reduceMotion,
                allowsSimulatorQA: allowsSimulatorQA
            )
            let energyRailState = energyRailVisualState(
                atUptimeNanoseconds: now,
                sourceCapability: sourceCapability,
                storeProjection: storeProjection,
                presentationRevision: energyRailPresentationRevision
            )

            instrumentContent(
                frame: frame,
                speedAvailability: speedAvailability,
                energyRailState: energyRailState
            )
        }
        .task {
            model.configureInterpolationPolicy(vehicle.speedInstrumentInterpolationPolicy)
            model.setSpeedEvidenceAvailability(
                vehicle.speedEvidenceAvailability,
                allowsSimulatorQA: vehicle.profile == .simulatorQA
            )
            synchronizeEnergyRailStoreProjection(energyRailStoreProjection)
        }
        .task(id: energyRailNextTransitionUptimeNanoseconds) {
            await waitForEnergyRailPresentationTransition()
        }
        .onChange(of: vehicle.speedEvidenceAvailability) { _, availability in
            model.setSpeedEvidenceAvailability(
                availability,
                allowsSimulatorQA: vehicle.profile == .simulatorQA
            )
        }
        .onChange(of: vehicle.simulatorPowerStoreProjection) { _, projection in
            synchronizeEnergyRailStoreProjection(projection)
        }
        .onChange(of: reduceMotion) { _, _ in
            refreshEnergyRailPresentationSchedule()
        }
        .onDisappear {
            model.stop()
            // View lifetime is not source lifetime. Do not mutate source or package
            // receipt chronology merely because SwiftUI removed this subtree.
            energyRailNextTransitionUptimeNanoseconds = nil
        }
    }

    private var hasEnergyRailSourceCapability: Bool {
        vehicle.profile == .simulatorQA
            && vehicle.profile.capabilities.supportsPowerWatts
            && vehicle.hasSimulatorPowerEvidenceSource
    }

    private var energyRailStoreProjection: SimulatorPowerStoreProjection {
        hasEnergyRailSourceCapability
            ? vehicle.simulatorPowerStoreProjection
            : .unavailable
    }

    /// Copies only the exact receipt already sealed by the source and joined by the
    /// Store with transport currentness. No local timestamp or replacement receipt
    /// exists at this boundary.
    private func synchronizeEnergyRailStoreProjection(
        _ projection: SimulatorPowerStoreProjection
    ) {
        guard hasEnergyRailSourceCapability else {
            energyRailRuntime = nil
            energyRailNextTransitionUptimeNanoseconds = nil
            return
        }

        if energyRailRuntime == nil {
            energyRailRuntime = try? PropulsionEnergyRailSimulatorRuntime()
        }

        guard var runtime = energyRailRuntime else {
            energyRailNextTransitionUptimeNanoseconds = nil
            return
        }

        switch projection.currentness {
        case .unavailable:
            guard projection.observation == nil else {
                runtime.markUnavailable()
                energyRailRuntime = runtime
                refreshEnergyRailPresentationSchedule()
                return
            }
            runtime.markUnavailable()

        case .retained:
            guard let observation = projection.observation else {
                runtime.markUnavailable()
                energyRailRuntime = runtime
                refreshEnergyRailPresentationSchedule()
                return
            }
            _ = runtime.retainSource(
                watts: observation.watts,
                receiptSequenceNumber: observation.receiptSequenceNumber,
                receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
                continuityGeneration: observation.continuityGeneration
            )

        case .live:
            guard let observation = projection.observation else {
                runtime.markUnavailable()
                energyRailRuntime = runtime
                refreshEnergyRailPresentationSchedule()
                return
            }
            _ = runtime.acceptLiveSource(
                watts: observation.watts,
                receiptSequenceNumber: observation.receiptSequenceNumber,
                receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
                continuityGeneration: observation.continuityGeneration
            )
        }

        energyRailRuntime = runtime
        energyRailPresentationRevision &+= 1
        refreshEnergyRailPresentationSchedule()
    }

    private func refreshEnergyRailPresentationSchedule() {
        guard !reduceMotion,
              hasEnergyRailSourceCapability,
              energyRailStoreProjection.currentness == .live,
              let energyRailRuntime else {
            energyRailNextTransitionUptimeNanoseconds = nil
            return
        }

        let now = DispatchTime.now().uptimeNanoseconds
        let packageProjection = energyRailRuntime.projection(atUptimeNanoseconds: now)
        guard projectionMatchesStore(
            packageProjection,
            storeProjection: energyRailStoreProjection
        ) else {
            energyRailNextTransitionUptimeNanoseconds = nil
            return
        }

        energyRailNextTransitionUptimeNanoseconds = energyRailRuntime.displaySchedule(
            atUptimeNanoseconds: now
        ).nextTransitionUptimeNanoseconds
    }

    private func waitForEnergyRailPresentationTransition() async {
        guard let deadline = energyRailNextTransitionUptimeNanoseconds else {
            return
        }

        let now = DispatchTime.now().uptimeNanoseconds
        if deadline > now {
            do {
                try await Task.sleep(nanoseconds: deadline - now)
            } catch {
                return
            }
        }
        guard !Task.isCancelled else { return }

        // Recompose only presentation at a package-owned deadline. Source/store
        // receipt identity and measurement chronology remain unchanged.
        energyRailPresentationRevision &+= 1
        refreshEnergyRailPresentationSchedule()
    }

    private func energyRailVisualState(
        atUptimeNanoseconds uptimeNanoseconds: UInt64,
        sourceCapability: Bool,
        storeProjection: SimulatorPowerStoreProjection,
        presentationRevision: UInt64
    ) -> NembraEnergyRailVisualState? {
        _ = presentationRevision

        guard sourceCapability,
              let energyRailRuntime else {
            return nil
        }

        let packageProjection = energyRailRuntime.projection(
            atUptimeNanoseconds: uptimeNanoseconds
        )

        // This synchronous compare closes the SwiftUI observation -> onChange seam:
        // a just-demoted Store receipt can never render one stale LIVE package frame.
        guard projectionMatchesStore(
            packageProjection,
            storeProjection: storeProjection
        ) else {
            return .unavailable
        }

        return NembraEnergyRailVisualState(projection: packageProjection)
    }

    private func projectionMatchesStore(
        _ packageProjection: PropulsionEnergyRailAppProjection,
        storeProjection: SimulatorPowerStoreProjection
    ) -> Bool {
        switch storeProjection.currentness {
        case .unavailable:
            return storeProjection.observation == nil
                && packageProjection.currentness == .unavailable
                && packageProjection.acceptedMeasurement == nil

        case .retained:
            guard let source = storeProjection.observation,
                  packageProjection.currentness == .retained,
                  let accepted = packageProjection.acceptedMeasurement else {
                return false
            }
            return accepted.authority == .simulator
                && accepted.watts == source.watts
                && accepted.receiptSequenceNumber == source.receiptSequenceNumber
                && accepted.receivedAtUptimeNanoseconds == source.receivedAtUptimeNanoseconds
                && accepted.continuityGeneration == source.continuityGeneration

        case .live:
            guard let source = storeProjection.observation,
                  packageProjection.currentness == .live,
                  let accepted = packageProjection.acceptedMeasurement else {
                return false
            }
            return accepted.authority == .simulator
                && accepted.watts == source.watts
                && accepted.receiptSequenceNumber == source.receiptSequenceNumber
                && accepted.receivedAtUptimeNanoseconds == source.receivedAtUptimeNanoseconds
                && accepted.continuityGeneration == source.continuityGeneration
        }
    }

    private func isLivePresentation(_ availability: SpeedEvidenceAvailability) -> Bool {
        if case .live = availability {
            return true
        }
        return false
    }

    private func instrumentContent(
        frame: SpeedInstrumentDisplayFrame?,
        speedAvailability: SpeedEvidenceAvailability,
        energyRailState: NembraEnergyRailVisualState?
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
            // VoiceOver consumes sanitized field-specific speed truth, never a
            // 60 Hz render midpoint or Energy Rail display-clock state.
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

            Spacer(minLength: energyRailState == nil ? 0 : 6)

            if let energyRailState {
                NembraEnergyRailView(state: energyRailState)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
            } else {
                Spacer(minLength: 0)
            }
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
