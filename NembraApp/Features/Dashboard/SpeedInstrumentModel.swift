import Dispatch
import Foundation
import NembraCore
import Observation
import SwiftUI

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

private enum DashboardEnergyRailCurrentness: Equatable {
    case live
    case retained
    case unavailable
}

private struct DashboardEnergyRailVisualState: Equatable {
    let currentness: DashboardEnergyRailCurrentness
    let acceptedWatts: Double?
    let railFraction: Double?
    let acceptedPeakMarkerFraction: Double?

    static let unavailable = DashboardEnergyRailVisualState(
        currentness: .unavailable,
        acceptedWatts: nil,
        railFraction: nil,
        acceptedPeakMarkerFraction: nil
    )
}

/// App-side custody for the package-owned propulsion presentation model.
///
/// The only positive input is `VehicleStore.simulatorPowerStoreProjection`, which
/// already joins an exact source-owned Simulator receipt with aggregate transport
/// currentness. This model copies that immutable receipt into NembraCore's explicit
/// Simulator factory, then consumes NembraCore's canonical Energy Rail projection.
/// The typed cockpit measurement is still rebound to the exact Store receipt before
/// accepted watts can escape this model. It has no production measurement factory and
/// no path back into vehicle state, persistence, rides, battery learning, protocol
/// evidence, or physical ES80 claims.
@MainActor
@Observable
private final class DashboardEnergyRailModel {
    private enum Timing {
        static let riseNanoseconds: UInt64 = 220_000_000
        static let fallNanoseconds: UInt64 = 150_000_000
        // NembraCore still owns accepted-peak bookkeeping internally. The first
        // app-visible Energy Rail deliberately does not render a peak marker, so
        // the Dashboard never mirrors or reschedules that optional peak authority.
        static let peakHoldNanoseconds: UInt64 = 2_000_000_000
        static let freshnessNanoseconds: UInt64 = 30_000_000_000
    }

    private struct Receipt: Equatable {
        let watts: Double
        let receiptSequenceNumber: UInt64
        let receivedAtUptimeNanoseconds: UInt64
        let continuityGeneration: UInt64
    }

    private(set) var revision: UInt64 = 0
    private(set) var shouldTick = false

    @ObservationIgnored private var projection: SimulatorPowerStoreProjection = .unavailable
    @ObservationIgnored private var gauge: NembraCore.PropulsionGaugeDisplayModel?
    @ObservationIgnored private var scale: NembraCore.PropulsionGaugeScale?
    @ObservationIgnored private var acceptedReceipt: Receipt?
    @ObservationIgnored private var rejectedCurrentReceipt = false
    @ObservationIgnored private var animationEndTask: Task<Void, Never>?
    @ObservationIgnored private var peakEndTask: Task<Void, Never>?
    @ObservationIgnored private var freshnessTask: Task<Void, Never>?

    init() {
        rebuildPresentationModel()
    }

    deinit {
        animationEndTask?.cancel()
        peakEndTask?.cancel()
        freshnessTask?.cancel()
    }

    func stop() {
        cancelScheduledWakes()
        projection = .unavailable
        acceptedReceipt = nil
        rejectedCurrentReceipt = false
        rebuildPresentationModel()
        revision &+= 1
    }

    func synchronize(
        _ incoming: SimulatorPowerStoreProjection,
        sourceCapabilityIsOwned: Bool
    ) {
        guard sourceCapabilityIsOwned else {
            stop()
            return
        }

        projection = incoming

        switch incoming.currentness {
        case .unavailable:
            // Source unavailability closes the local presentation segment. Rebuild
            // rather than calling the package's production-style generation retire
            // API: a later Store-authorized Simulator receipt may legitimately keep
            // the same synthetic continuity generation after a transport exercise.
            guard incoming.observation == nil else {
                failClosedForCurrentProjection()
                return
            }
            cancelScheduledWakes()
            acceptedReceipt = nil
            rejectedCurrentReceipt = false
            rebuildPresentationModel()
            revision &+= 1

        case .retained, .live:
            guard let observation = incoming.observation,
                  let receipt = validReceipt(observation) else {
                failClosedForCurrentProjection()
                return
            }

            var animationDuration: UInt64 = 0
            if acceptedReceipt != receipt {
                guard let acceptedAnimationDuration = accept(receipt) else {
                    failClosedForCurrentProjection()
                    return
                }
                acceptedReceipt = receipt
                animationDuration = acceptedAnimationDuration
            }

            rejectedCurrentReceipt = false
            if incoming.currentness == .live {
                scheduleLivePresentationWakes(
                    for: receipt,
                    animationDurationNanoseconds: animationDuration
                )
            } else {
                cancelScheduledWakes()
            }
            revision &+= 1
        }
    }

    func presentation(
        atUptimeNanoseconds uptimeNanoseconds: UInt64,
        prefersReducedMotion: Bool
    ) -> DashboardEnergyRailVisualState {
        _ = revision

        guard !rejectedCurrentReceipt,
              let observation = projection.observation,
              let receipt = validReceipt(observation),
              receipt == acceptedReceipt,
              let gauge,
              let scale else {
            return .unavailable
        }

        let snapshot = gauge.cockpitSnapshot(
            atUptimeNanoseconds: uptimeNanoseconds,
            scale: scale
        )
        let rail = snapshot.energyRailPresentation
        guard snapshot.identity == gauge.identity,
              rail.identity == gauge.identity else {
            return .unavailable
        }

        if projection.currentness == .retained {
            guard let accepted = validatedAcceptedMeasurement(
                snapshot.measurement,
                receipt: receipt,
                expectedIdentity: gauge.identity
            ) else {
                return .unavailable
            }
            return DashboardEnergyRailVisualState(
                currentness: .retained,
                acceptedWatts: accepted.watts,
                railFraction: nil,
                acceptedPeakMarkerFraction: nil
            )
        }

        guard projection.currentness == .live else {
            return .unavailable
        }

        switch rail.currentness {
        case .unavailable:
            return .unavailable

        case .retained:
            // NembraCore may be more conservative than Store truth. Preserve its
            // typed retained state rather than promoting it back to LIVE.
            guard let accepted = validatedAcceptedMeasurement(
                snapshot.measurement,
                receipt: receipt,
                expectedIdentity: gauge.identity
            ), rail.acceptedWatts == accepted.watts else {
                return .unavailable
            }
            return DashboardEnergyRailVisualState(
                currentness: .retained,
                acceptedWatts: accepted.watts,
                railFraction: nil,
                acceptedPeakMarkerFraction: nil
            )

        case .live:
            guard let accepted = validatedAcceptedMeasurement(
                snapshot.measurement,
                receipt: receipt,
                expectedIdentity: gauge.identity
            ), rail.acceptedWatts == accepted.watts else {
                return .unavailable
            }

            let railFraction = prefersReducedMotion
                ? acceptedTargetFraction(accepted.watts, ceilingWatts: scale.ceilingWatts)
                : rail.railFraction

            if railFraction != nil, rail.scaleOrigin != .simulator {
                return .unavailable
            }

            return DashboardEnergyRailVisualState(
                currentness: .live,
                acceptedWatts: accepted.watts,
                railFraction: railFraction,
                acceptedPeakMarkerFraction: rail.acceptedPeakMarkerFraction
            )
        }
    }

    private func rebuildPresentationModel() {
        do {
            let identity = try NembraCore.PropulsionGaugeIdentity(
                vehicleID: "nembra-simulator-dashboard"
            )
            let animationPolicy = try NembraCore.PropulsionGaugeAnimationPolicy(
                riseSettlingDurationNanoseconds: Timing.riseNanoseconds,
                fallSettlingDurationNanoseconds: Timing.fallNanoseconds,
                acceptedPeakHoldNanoseconds: Timing.peakHoldNanoseconds
            )
            let freshnessPolicy = try NembraCore.PropulsionGaugeFreshnessPolicy(
                staleAfterNanoseconds: Timing.freshnessNanoseconds
            )
            gauge = NembraCore.PropulsionGaugeDisplayModel(
                identity: identity,
                animationPolicy: animationPolicy,
                freshnessPolicy: freshnessPolicy
            )
            scale = try NembraCore.PropulsionGaugeScale.simulator(
                identity: identity,
                ceilingWatts: 650
            )
        } catch {
            gauge = nil
            scale = nil
        }
    }

    private func validReceipt(_ observation: SimulatorPowerObservation) -> Receipt? {
        guard observation.watts.isFinite, observation.watts >= 0 else { return nil }
        return Receipt(
            watts: observation.watts == 0 ? 0 : observation.watts,
            receiptSequenceNumber: observation.receiptSequenceNumber,
            receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
            continuityGeneration: observation.continuityGeneration
        )
    }

    /// Returns the exact display-clock window created by this accepted receipt.
    /// `frame.displayWatts` is consulted only to determine which bounded animation
    /// duration to schedule; it is never exposed as the cockpit numeric value.
    private func accept(_ receipt: Receipt) -> UInt64? {
        guard var gauge else { return nil }

        do {
            let sample = try NembraCore.PropulsionPowerSample.simulator(
                identity: gauge.identity,
                watts: receipt.watts,
                receiptSequenceNumber: receipt.receiptSequenceNumber,
                receivedAtUptimeNanoseconds: receipt.receivedAtUptimeNanoseconds,
                continuityGeneration: receipt.continuityGeneration
            )
            try gauge.accept(sample)
            let frame = gauge.frame(
                atUptimeNanoseconds: receipt.receivedAtUptimeNanoseconds,
                scale: scale
            )
            self.gauge = gauge

            guard frame.origin == .visuallyInterpolated,
                  let displayWatts = frame.displayWatts,
                  let acceptedWatts = frame.latestAcceptedWatts else {
                return 0
            }
            return acceptedWatts >= displayWatts
                ? Timing.riseNanoseconds
                : Timing.fallNanoseconds
        } catch {
            return nil
        }
    }

    private func validatedAcceptedMeasurement(
        _ measurement: NembraCore.PropulsionGaugeCockpitMeasurement,
        receipt: Receipt,
        expectedIdentity: NembraCore.PropulsionGaugeIdentity
    ) -> NembraCore.PropulsionGaugeCockpitAcceptedMeasurement? {
        let accepted: NembraCore.PropulsionGaugeCockpitAcceptedMeasurement
        switch measurement {
        case let .live(value), let .retained(value):
            accepted = value
        case .unavailable:
            return nil
        }

        guard accepted.identity == expectedIdentity,
              accepted.authority == .simulator,
              accepted.watts == receipt.watts,
              accepted.receiptSequenceNumber == receipt.receiptSequenceNumber,
              accepted.receivedAtUptimeNanoseconds == receipt.receivedAtUptimeNanoseconds,
              accepted.continuityGeneration == receipt.continuityGeneration else {
            return nil
        }
        return accepted
    }

    private func scheduleLivePresentationWakes(
        for receipt: Receipt,
        animationDurationNanoseconds: UInt64
    ) {
        cancelScheduledWakes()
        shouldTick = animationDurationNanoseconds > 0

        if animationDurationNanoseconds > 0 {
            animationEndTask = scheduleWake(afterNanoseconds: animationDurationNanoseconds) { model in
                model.shouldTick = false
                model.animationEndTask = nil
                model.revision &+= 1
            }
        }

        if let peakDelay = delayFromReceipt(
            receipt,
            offsetNanoseconds: Timing.peakHoldNanoseconds
        ) {
            peakEndTask = scheduleWake(afterNanoseconds: peakDelay) { model in
                model.peakEndTask = nil
                model.revision &+= 1
            }
        }

        if let delay = delayFromReceipt(
            receipt,
            offsetNanoseconds: Timing.freshnessNanoseconds
        ) {
            freshnessTask = scheduleWake(afterNanoseconds: delay) { model in
                model.shouldTick = false
                model.freshnessTask = nil
                model.revision &+= 1
            }
        }
    }

    private func scheduleWake(
        afterNanoseconds delayNanoseconds: UInt64,
        action: @escaping @MainActor (DashboardEnergyRailModel) -> Void
    ) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                if delayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            action(self)
        }
    }

    private func delayFromReceipt(
        _ receipt: Receipt,
        offsetNanoseconds: UInt64
    ) -> UInt64? {
        guard receipt.receivedAtUptimeNanoseconds <= UInt64.max - offsetNanoseconds - 1 else {
            return nil
        }
        let deadline = receipt.receivedAtUptimeNanoseconds + offsetNanoseconds + 1
        let now = DispatchTime.now().uptimeNanoseconds
        return deadline > now ? deadline - now : 0
    }

    private func cancelScheduledWakes() {
        animationEndTask?.cancel()
        peakEndTask?.cancel()
        freshnessTask?.cancel()
        animationEndTask = nil
        peakEndTask = nil
        freshnessTask = nil
        shouldTick = false
    }

    private func failClosedForCurrentProjection() {
        cancelScheduledWakes()
        rejectedCurrentReceipt = true
        revision &+= 1
    }

    /// Reduce Motion uses a stable Simulator presentation target rather than a
    /// display-clock midpoint. This ratio is presentation geometry only and the
    /// ceiling is the explicit synthetic scale above, not a motor/controller claim.
    private func acceptedTargetFraction(
        _ watts: Double,
        ceilingWatts: Double
    ) -> Double? {
        guard watts.isFinite,
              watts >= 0,
              ceilingWatts.isFinite,
              ceilingWatts > 0 else {
            return nil
        }
        return min(max(watts / ceilingWatts, 0), 1)
    }
}

struct DashboardPropulsionGeometry {
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint

    init(size: CGSize) {
        let horizontalInset = max(18, min(28, size.width * 0.032))
        let endpointY = size.height * 0.90
        // A symmetric quadratic reaches the midpoint between its endpoint and
        // control-point Y values at t = 0.5. Define the rendered apex first,
        // then derive the control point so the selected V4 rise is intentional
        // rather than an accidental shallow midpoint.
        let renderedApexY = max(18, size.height * 0.14)
        let controlY = renderedApexY * 2 - endpointY
        start = CGPoint(x: horizontalInset, y: endpointY)
        control = CGPoint(x: size.width / 2, y: controlY)
        end = CGPoint(x: size.width - horizontalInset, y: endpointY)
    }

    var path: Path {
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }

    func point(at rawProgress: Double) -> CGPoint {
        let t = min(max(rawProgress, 0), 1)
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
        )
    }

    func outwardNormal(at rawProgress: Double) -> CGVector {
        let t = min(max(rawProgress, 0), 1)
        let dx = 2 * (1 - t) * (control.x - start.x) + 2 * t * (end.x - control.x)
        let dy = 2 * (1 - t) * (control.y - start.y) + 2 * t * (end.y - control.y)
        let length = max(0.001, hypot(dx, dy))
        return CGVector(dx: dy / length, dy: -dx / length)
    }
}

private struct DashboardRollingPowerValueView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Double

    var body: some View {
        Text(validatedText)
            .font(.title3.weight(.semibold).monospacedDigit())
            .contentTransition(reduceMotion ? .identity : .numericText(value: value))
            .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: validatedText)
    }

    private var validatedText: String {
        guard value.isFinite, value >= 0, value <= 99_999 else { return "—" }
        return String(Int(value.rounded(.toNearestOrAwayFromZero)))
    }
}

private struct DashboardEnergyRailView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let state: DashboardEnergyRailVisualState

    var body: some View {
        GeometryReader { proxy in
            let geometry = DashboardPropulsionGeometry(size: proxy.size)

            ZStack {
                Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                    drawTicks(context: &context, geometry: geometry)
                    drawRail(context: &context, geometry: geometry)
                    drawMarkers(context: &context, geometry: geometry)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                powerReadout
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.74)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Propulsion power")
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("dashboard.energy-rail")
    }

    private func drawTicks(
        context: inout GraphicsContext,
        geometry: DashboardPropulsionGeometry
    ) {
        var ticks = Path()
        for index in 0...32 {
            let progress = Double(index) / 32
            let point = geometry.point(at: progress)
            let normal = geometry.outwardNormal(at: progress)
            let isMajor = index.isMultiple(of: 4)
            let startOffset: CGFloat = 7
            let length: CGFloat = isMajor ? 8 : 4
            let start = CGPoint(
                x: point.x + normal.dx * startOffset,
                y: point.y + normal.dy * startOffset
            )
            let end = CGPoint(
                x: point.x + normal.dx * (startOffset + length),
                y: point.y + normal.dy * (startOffset + length)
            )
            ticks.move(to: start)
            ticks.addLine(to: end)
        }
        context.stroke(
            ticks,
            with: .color(Color.white.opacity(colorSchemeContrast == .increased ? 0.42 : 0.24)),
            style: StrokeStyle(lineWidth: colorSchemeContrast == .increased ? 1.4 : 0.8, lineCap: .round)
        )
    }

    private func drawRail(
        context: inout GraphicsContext,
        geometry: DashboardPropulsionGeometry
    ) {
        if state.currentness == .live,
           let fraction = validFraction(state.railFraction) {
            let activePath = geometry.path.trimmedPath(from: 0, to: fraction)
            if !reduceTransparency {
                context.stroke(
                    activePath,
                    with: .color(NembraColor.gold.opacity(0.16)),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round)
                )
                context.stroke(
                    activePath,
                    with: .color(NembraColor.activeGold.opacity(0.46)),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
                )
            } else {
                context.stroke(
                    activePath,
                    with: .color(NembraColor.gold),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                )
            }
        }

        context.stroke(
            geometry.path,
            with: .color(Color.white.opacity(colorSchemeContrast == .increased ? 1 : 0.92)),
            style: StrokeStyle(
                lineWidth: colorSchemeContrast == .increased ? 3.5 : 2.4,
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    private func drawMarkers(
        context: inout GraphicsContext,
        geometry: DashboardPropulsionGeometry
    ) {
        guard state.currentness == .live else { return }

        if let peak = validFraction(state.acceptedPeakMarkerFraction) {
            let center = geometry.point(at: peak)
            let rect = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: rect), with: .color(NembraColor.baseBlack))
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(NembraColor.gold.opacity(0.86)),
                style: StrokeStyle(lineWidth: 2)
            )
        }

        if let live = validFraction(state.railFraction) {
            let center = geometry.point(at: live)
            let outer = CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)
            let inner = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: outer), with: .color(NembraColor.gold))
            context.stroke(
                Path(ellipseIn: outer),
                with: .color(Color.white.opacity(0.95)),
                style: StrokeStyle(lineWidth: 2)
            )
            context.fill(Path(ellipseIn: inner), with: .color(Color.white.opacity(0.92)))
        }
    }

    private var powerReadout: some View {
        VStack(spacing: 2) {
            Text("PROPULSION")
                .font(.system(size: 9, weight: .bold))
                .tracking(2.1)
                .foregroundStyle(NembraColor.secondaryText.opacity(0.76))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let watts = state.acceptedWatts {
                    DashboardRollingPowerValueView(value: watts)
                } else {
                    Text("—")
                        .font(.title3.weight(.semibold))
                }
                Text("W")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(NembraColor.secondaryText)
            }

            Text(currentnessLabel)
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(currentnessColor)
        }
    }

    private var currentnessLabel: String {
        switch state.currentness {
        case .live: state.acceptedWatts == nil ? "UNAVAILABLE" : "ACCEPTED LIVE POWER"
        case .retained: state.acceptedWatts == nil ? "UNAVAILABLE" : "LAST KNOWN POWER"
        case .unavailable: "POWER UNAVAILABLE"
        }
    }

    private var currentnessColor: Color {
        switch state.currentness {
        case .live where state.acceptedWatts != nil: NembraColor.gold.opacity(0.82)
        case .retained where state.acceptedWatts != nil: NembraColor.secondaryText.opacity(0.72)
        default: NembraColor.secondaryText.opacity(0.48)
        }
    }

    private var accessibilityValue: String {
        switch state.currentness {
        case .unavailable:
            return "Unavailable"
        case .retained:
            guard let watts = state.acceptedWatts else { return "Unavailable" }
            return "Last known, \(Int(watts.rounded())) watts"
        case .live:
            guard let watts = state.acceptedWatts else { return "Unavailable" }
            return "\(Int(watts.rounded())) accepted watts"
        }
    }

    private func validFraction(_ value: Double?) -> CGFloat? {
        guard let value, value.isFinite, (0...1).contains(value) else { return nil }
        return CGFloat(value)
    }
}

/// Narrow high-frequency render island for speed and propulsion motion. The
/// animation timeline exists only while an accepted projection is visually
/// settling; the steady-state instrument has no animation schedule to keep the
/// app or UI automation artificially busy.
/// Display frames are never written into evidence, persistence, or `VehicleStore`.
@MainActor
struct DashboardSpeedInstrumentView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var model = SpeedInstrumentModel()
    @State private var energyRailModel = DashboardEnergyRailModel()

    var body: some View {
        let allowsSimulatorQA = vehicle.profile == .simulatorQA
        let rawSpeedAvailability = vehicle.speedEvidenceAvailability
        let speedAvailability = rawSpeedAvailability.dashboardPresentationAvailability(
            allowsSimulatorQA: allowsSimulatorQA
        )
        let ownsSimulatorPowerSource = vehicle.profile == .simulatorQA
            && vehicle.profile.capabilities.supportsPowerWatts
            && vehicle.hasSimulatorPowerEvidenceSource
        let simulatorPowerProjection = ownsSimulatorPowerSource
            ? vehicle.simulatorPowerStoreProjection
            : .unavailable
        let speedShouldTick = !reduceMotion
            && model.isAnimationActive
            && isLivePresentation(speedAvailability)
        let energyRailShouldTick = !reduceMotion
            && ownsSimulatorPowerSource
            && energyRailModel.shouldTick
        let shouldTick = speedShouldTick || energyRailShouldTick

        Group {
            if shouldTick {
                TimelineView(.animation(minimumInterval: nil, paused: false)) { _ in
                    instrumentContent(
                        atUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                        rawSpeedAvailability: rawSpeedAvailability,
                        speedAvailability: speedAvailability,
                        allowsSimulatorQA: allowsSimulatorQA,
                        ownsSimulatorPowerSource: ownsSimulatorPowerSource
                    )
                }
            } else {
                instrumentContent(
                    atUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                    rawSpeedAvailability: rawSpeedAvailability,
                    speedAvailability: speedAvailability,
                    allowsSimulatorQA: allowsSimulatorQA,
                    ownsSimulatorPowerSource: ownsSimulatorPowerSource
                )
            }
        }
        .task {
            model.configureInterpolationPolicy(vehicle.speedInstrumentInterpolationPolicy)
            model.setSpeedEvidenceAvailability(
                rawSpeedAvailability,
                allowsSimulatorQA: allowsSimulatorQA
            )
            energyRailModel.synchronize(
                simulatorPowerProjection,
                sourceCapabilityIsOwned: ownsSimulatorPowerSource
            )
        }
        .onChange(of: vehicle.speedEvidenceAvailability) { _, availability in
            model.setSpeedEvidenceAvailability(
                availability,
                allowsSimulatorQA: vehicle.profile == .simulatorQA
            )
        }
        .onChange(of: vehicle.simulatorPowerStoreProjection) { _, projection in
            energyRailModel.synchronize(
                projection,
                sourceCapabilityIsOwned: ownsSimulatorPowerSource
            )
        }
        .onDisappear {
            model.stop()
            energyRailModel.stop()
        }
    }

    private func instrumentContent(
        atUptimeNanoseconds uptimeNanoseconds: UInt64,
        rawSpeedAvailability: SpeedEvidenceAvailability,
        speedAvailability: SpeedEvidenceAvailability,
        allowsSimulatorQA: Bool,
        ownsSimulatorPowerSource: Bool
    ) -> some View {
        let frame = model.presentationFrame(
            for: rawSpeedAvailability,
            atUptimeNanoseconds: uptimeNanoseconds,
            prefersReducedMotion: reduceMotion,
            allowsSimulatorQA: allowsSimulatorQA
        )
        let energyRailState = ownsSimulatorPowerSource
            ? energyRailModel.presentation(
                atUptimeNanoseconds: uptimeNanoseconds,
                prefersReducedMotion: reduceMotion
            )
            : .unavailable

        return instrumentContent(
            frame: frame,
            speedAvailability: speedAvailability,
            energyRailState: energyRailState
        )
    }

    private func instrumentContent(
        frame: SpeedInstrumentDisplayFrame?,
        speedAvailability: SpeedEvidenceAvailability,
        energyRailState: DashboardEnergyRailVisualState
    ) -> some View {
        GeometryReader { proxy in
            let integerSize = max(92, min(146, min(proxy.size.width * 0.19, proxy.size.height * 0.39)))
            let fractionSize = max(38, integerSize * 0.40)
            let gaugeHeight = max(112, min(156, proxy.size.height * 0.36))
            let gaugeCenterY = proxy.size.height * 0.69

            ZStack {
                speedReadout(
                    frame: frame,
                    availability: speedAvailability,
                    integerSize: integerSize,
                    fractionSize: fractionSize
                )
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.35)

                Text("DRIVE")
                    .font(.caption.weight(.bold))
                    .tracking(3.2)
                    .foregroundStyle(NembraColor.gold.opacity(0.92))
                    .position(x: proxy.size.width / 2, y: gaugeCenterY - gaugeHeight * 0.58)
                    .accessibilityHidden(true)

                DashboardEnergyRailView(state: energyRailState)
                    .frame(width: proxy.size.width, height: gaugeHeight)
                    .position(x: proxy.size.width / 2, y: gaugeCenterY)
            }
        }
    }

    private func speedReadout(
        frame: SpeedInstrumentDisplayFrame?,
        availability: SpeedEvidenceAvailability,
        integerSize: CGFloat,
        fractionSize: CGFloat
    ) -> some View {
        VStack(spacing: -2) {
            RollingSpeedValueView(
                value: displayedValue(kilometersPerHour: frame?.kilometersPerHour),
                integerPointSize: integerSize,
                fractionPointSize: fractionSize
            )
            .lineLimit(1)
            .accessibilityHidden(true)

            Text(speedUnitText)
                .font(.caption.weight(.bold))
                .tracking(3.2)
                .foregroundStyle(NembraColor.secondaryText.opacity(0.82))
                .accessibilityHidden(true)

            Text(speedCurrentnessText(availability))
                .font(.system(size: 8, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(speedCurrentnessColor(availability))
                .padding(.top, 3)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speed")
        .accessibilityValue(accessibilitySpeed(availability))
        .accessibilityIdentifier("dashboard.speed")
    }

    private func isLivePresentation(_ availability: SpeedEvidenceAvailability) -> Bool {
        if case .live = availability { return true }
        return false
    }

    private func displayedValue(kilometersPerHour: Double?) -> Double? {
        guard let kilometersPerHour,
              kilometersPerHour.isFinite,
              kilometersPerHour >= 0 else { return nil }
        let normalized = kilometersPerHour == 0 ? 0 : kilometersPerHour
        return VehicleDisplayFormatting.usesMetric ? normalized : normalized * 0.621_371
    }

    private func accessibilitySpeed(_ availability: SpeedEvidenceAvailability) -> String {
        let prefix = vehicle.profile == .simulatorQA
            ? "Simulator QA synthetic evidence, not physical scooter truth. "
            : ""
        return prefix + {
            switch availability {
            case .unavailable:
                return "Unavailable"
            case let .retained(sample):
                return "Last known, \(VehicleDisplayFormatting.speed(kilometersPerHour: sample.kilometersPerHour, decimals: 1))"
            case let .live(sample):
                return VehicleDisplayFormatting.speed(kilometersPerHour: sample.kilometersPerHour, decimals: 1)
            }
        }()
    }

    private func speedCurrentnessText(_ availability: SpeedEvidenceAvailability) -> String {
        switch availability {
        case .live: "LIVE SPEED"
        case .retained: "LAST KNOWN SPEED"
        case .unavailable: "SPEED UNAVAILABLE"
        }
    }

    private func speedCurrentnessColor(_ availability: SpeedEvidenceAvailability) -> Color {
        switch availability {
        case .live: colorSchemeContrast == .increased ? .white : NembraColor.primaryText.opacity(0.68)
        case .retained: NembraColor.secondaryText.opacity(0.72)
        case .unavailable: NembraColor.secondaryText.opacity(0.48)
        }
    }

    private var speedUnitText: String {
        VehicleDisplayFormatting.usesMetric ? "KM/H" : "MPH"
    }
}
