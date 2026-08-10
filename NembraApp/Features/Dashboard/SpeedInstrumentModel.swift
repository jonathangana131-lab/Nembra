import Dispatch
import Foundation
import Observation
import SwiftUI
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
    var dashboardPresentationAvailability: SpeedEvidenceAvailability {
        dashboardPresentationAvailability(allowsSimulatorQA: false)
    }

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

    func configureInterpolationPolicy(_ policy: SpeedInstrumentInterpolationPolicy) {
        guard measurementRevision == 0 else { return }
        interpolationPolicy = policy
    }

    func stop() {
        clearPresentationContinuity()
    }

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

    func accept(_ sample: SpeedTelemetrySample) {
        guard sample.isAuthoritativeMeasurement else { return }

        let transitionDuration = transitionDurationNanoseconds(for: sample)
        do {
            try interpolator.accept(
                sample,
                transitionDurationNanoseconds: transitionDuration
            )
        } catch {
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

/// Narrow high-frequency subtree for the landscape cockpit. Positive propulsion
/// authority enters only through `VehicleStore.simulatorPowerEvidenceAvailability`.
/// The package receives the exact source receipt tuple without any SwiftUI timestamp.
@MainActor
struct DashboardSpeedInstrumentView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = SpeedInstrumentModel()
    @State private var energyRailRuntime: PropulsionEnergyRailSimulatorRuntime?
    @State private var energyRailNextTransitionUptimeNanoseconds: UInt64?
    @State private var energyRailPresentationRevision: UInt64 = 0

    let modePersonality: DashboardModePersonality

    var body: some View {
        let allowsSimulatorQA = vehicle.profile == .simulatorQA
        let rawSpeedAvailability = vehicle.speedEvidenceAvailability
        let speedAvailability = rawSpeedAvailability.dashboardPresentationAvailability(
            allowsSimulatorQA: allowsSimulatorQA
        )
        let sourceCapability = hasEnergyRailSourceCapability
        let sourceAvailability = energyRailSourceAvailability
        let scheduleNow = DispatchTime.now().uptimeNanoseconds
        let speedShouldTick = !reduceMotion
            && model.isAnimationActive
            && isLivePresentation(speedAvailability)
        let energyRailShouldTick: Bool

        if !reduceMotion,
           sourceCapability,
           case .live = sourceAvailability,
           let energyRailRuntime {
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
                sourceAvailability: sourceAvailability,
                sourceCapability: sourceCapability,
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
            synchronizeEnergyRailSource(energyRailSourceAvailability)
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
        .onChange(of: vehicle.simulatorPowerEvidenceAvailability) { _, availability in
            synchronizeEnergyRailSource(
                hasEnergyRailSourceCapability ? availability : .unavailable
            )
        }
        .onChange(of: hasEnergyRailSourceCapability) { _, _ in
            synchronizeEnergyRailSource(energyRailSourceAvailability)
        }
        .onChange(of: reduceMotion) { _, _ in
            refreshEnergyRailPresentationSchedule()
        }
        .onDisappear {
            model.stop()
            // View lifetime is not source lifetime. Local render scheduling stops,
            // but the Store remains the owner of the source receipt/currentness.
            energyRailNextTransitionUptimeNanoseconds = nil
        }
    }

    private var hasEnergyRailSourceCapability: Bool {
        vehicle.profile == .simulatorQA
            && vehicle.profile.capabilities.supportsPowerWatts
            && vehicle.hasSimulatorPowerEvidenceSource
    }

    private var energyRailSourceAvailability: SimulatorPowerEvidenceAvailability {
        hasEnergyRailSourceCapability
            ? vehicle.simulatorPowerEvidenceAvailability
            : .unavailable
    }

    /// Mechanically maps source currentness to the package's sealed lifecycle API.
    /// No aggregate watts, speed receipt, mode, callback time, global lastUpdated,
    /// view lifetime, or render clock can create a positive propulsion receipt here.
    private func synchronizeEnergyRailSource(
        _ availability: SimulatorPowerEvidenceAvailability
    ) {
        guard hasEnergyRailSourceCapability else {
            energyRailRuntime = nil
            energyRailNextTransitionUptimeNanoseconds = nil
            energyRailPresentationRevision &+= 1
            return
        }

        var runtime: PropulsionEnergyRailSimulatorRuntime
        if let existing = energyRailRuntime {
            runtime = existing
        } else if let created = try? PropulsionEnergyRailSimulatorRuntime() {
            runtime = created
        } else {
            energyRailRuntime = nil
            energyRailNextTransitionUptimeNanoseconds = nil
            return
        }

        switch availability {
        case let .live(observation):
            _ = runtime.acceptLiveSource(
                watts: observation.watts,
                receiptSequenceNumber: observation.receiptSequenceNumber,
                receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
                continuityGeneration: observation.continuityGeneration
            )

        case let .retained(observation):
            _ = runtime.retainSource(
                watts: observation.watts,
                receiptSequenceNumber: observation.receiptSequenceNumber,
                receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
                continuityGeneration: observation.continuityGeneration
            )

        case .unavailable:
            runtime.markUnavailable()
        }

        energyRailRuntime = runtime
        energyRailPresentationRevision &+= 1
        refreshEnergyRailPresentationSchedule()
    }

    /// The package owns all timer-driven display transitions. Reduce Motion disables
    /// continuous spatial frames but not this one-shot semantic/freshness clock.
    private func refreshEnergyRailPresentationSchedule() {
        guard hasEnergyRailSourceCapability,
              case .live = energyRailSourceAvailability,
              let energyRailRuntime else {
            energyRailNextTransitionUptimeNanoseconds = nil
            return
        }

        let now = DispatchTime.now().uptimeNanoseconds
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

        energyRailPresentationRevision &+= 1
        refreshEnergyRailPresentationSchedule()
    }

    /// Synchronous correlation gate for SwiftUI callback ordering. If Store
    /// currentness changes before `.onChange` mutates the local runtime, an old LIVE
    /// package projection is never allowed to flash as current. RETAINED/UNAVAILABLE
    /// may temporarily fail closed to unavailable until the package catches up.
    private func energyRailVisualState(
        atUptimeNanoseconds uptimeNanoseconds: UInt64,
        sourceAvailability: SimulatorPowerEvidenceAvailability,
        sourceCapability: Bool,
        presentationRevision: UInt64
    ) -> NembraEnergyRailVisualState? {
        _ = presentationRevision

        guard sourceCapability,
              let energyRailRuntime else {
            return nil
        }

        let projection = energyRailRuntime.projection(
            atUptimeNanoseconds: uptimeNanoseconds
        )

        switch sourceAvailability {
        case .unavailable:
            return .unavailable

        case let .retained(observation):
            guard projection.currentness == .retained,
                  projectionMatchesSourceReceipt(projection.acceptedMeasurement, observation: observation) else {
                return .unavailable
            }

        case let .live(observation):
            guard projection.currentness == .live,
                  projectionMatchesSourceReceipt(projection.acceptedMeasurement, observation: observation) else {
                return .unavailable
            }
        }

        return NembraEnergyRailVisualState(projection: projection)
    }

    private func projectionMatchesSourceReceipt(
        _ accepted: PropulsionGaugeCockpitAcceptedMeasurement?,
        observation: SimulatorPowerObservation
    ) -> Bool {
        guard let accepted else { return false }
        return accepted.authority == .simulator
            && accepted.watts == observation.watts
            && accepted.receiptSequenceNumber == observation.receiptSequenceNumber
            && accepted.receivedAtUptimeNanoseconds == observation.receivedAtUptimeNanoseconds
            && accepted.continuityGeneration == observation.continuityGeneration
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
