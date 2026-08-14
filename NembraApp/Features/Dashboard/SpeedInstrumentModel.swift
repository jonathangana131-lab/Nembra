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
    let displayWatts: Double?
    let railFraction: Double?
    let peakMarkerFraction: Double?

    static let unavailable = DashboardEnergyRailVisualState(
        currentness: .unavailable,
        acceptedWatts: nil,
        displayWatts: nil,
        railFraction: nil,
        peakMarkerFraction: nil
    )
}

/// App-side custody for the package-owned propulsion presentation model.
///
/// The only positive input is `VehicleStore.simulatorPowerStoreProjection`, which
/// already joins an exact source-owned Simulator receipt with aggregate transport
/// currentness. This model copies that immutable receipt into NembraCore's explicit
/// Simulator factory and then consumes render-only frames. It has no production
/// measurement factory and no path back into vehicle state, persistence, rides,
/// battery learning, protocol evidence, or physical ES80 claims.
@MainActor
@Observable
private final class DashboardEnergyRailModel {
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

    init() {
        rebuildPresentationModel()
    }

    func stop() {
        projection = .unavailable
        shouldTick = false
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
            shouldTick = false
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

            if acceptedReceipt != receipt {
                guard accept(receipt) else {
                    failClosedForCurrentProjection()
                    return
                }
                acceptedReceipt = receipt
            }

            rejectedCurrentReceipt = false
            shouldTick = incoming.currentness == .live
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

        let frame = gauge.frame(
            atUptimeNanoseconds: uptimeNanoseconds,
            scale: scale
        )

        // Every positive frame must still name the exact Store-authorized receipt.
        // Display interpolation may change `displayWatts` and rail geometry only;
        // it may never change or substitute the accepted measurement identity.
        guard frame.latestAuthority == .simulator,
              frame.latestAcceptedWatts == receipt.watts,
              frame.latestAcceptedReceiptSequenceNumber == receipt.receiptSequenceNumber,
              frame.latestAcceptedUptimeNanoseconds == receipt.receivedAtUptimeNanoseconds,
              frame.latestAcceptedContinuityGeneration == receipt.continuityGeneration else {
            return .unavailable
        }

        if projection.currentness == .retained {
            return DashboardEnergyRailVisualState(
                currentness: .retained,
                acceptedWatts: receipt.watts,
                displayWatts: receipt.watts,
                railFraction: nil,
                peakMarkerFraction: nil
            )
        }

        guard projection.currentness == .live else {
            return .unavailable
        }

        switch frame.availability {
        case .unavailable:
            return .unavailable

        case .retained:
            // NembraCore is allowed to be more conservative than Store truth. A
            // package freshness demotion never gets promoted back to LIVE here.
            return DashboardEnergyRailVisualState(
                currentness: .retained,
                acceptedWatts: receipt.watts,
                displayWatts: receipt.watts,
                railFraction: nil,
                peakMarkerFraction: nil
            )

        case .live:
            let displayWatts = prefersReducedMotion
                ? receipt.watts
                : sanitizedWatts(frame.displayWatts) ?? receipt.watts
            let railFraction = prefersReducedMotion
                ? acceptedTargetFraction(receipt.watts, ceilingWatts: scale.ceilingWatts)
                : sanitizedFraction(frame.normalizedPropulsion)
            let peakMarker = prefersReducedMotion
                ? nil
                : sanitizedFraction(frame.acceptedPeakNormalized)

            return DashboardEnergyRailVisualState(
                currentness: .live,
                acceptedWatts: receipt.watts,
                displayWatts: displayWatts,
                railFraction: railFraction,
                peakMarkerFraction: railFraction == nil ? nil : peakMarker
            )
        }
    }

    private func rebuildPresentationModel() {
        do {
            let identity = try NembraCore.PropulsionGaugeIdentity(
                vehicleID: "nembra-simulator-dashboard"
            )
            let animationPolicy = try NembraCore.PropulsionGaugeAnimationPolicy(
                riseSettlingDurationNanoseconds: 220_000_000,
                fallSettlingDurationNanoseconds: 150_000_000,
                acceptedPeakHoldNanoseconds: 2_000_000_000
            )
            let freshnessPolicy = try NembraCore.PropulsionGaugeFreshnessPolicy(
                staleAfterNanoseconds: 30_000_000_000
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

    private func accept(_ receipt: Receipt) -> Bool {
        guard var gauge else { return false }

        do {
            let sample = try NembraCore.PropulsionPowerSample.simulator(
                identity: gauge.identity,
                watts: receipt.watts,
                receiptSequenceNumber: receipt.receiptSequenceNumber,
                receivedAtUptimeNanoseconds: receipt.receivedAtUptimeNanoseconds,
                continuityGeneration: receipt.continuityGeneration
            )
            try gauge.accept(sample)
            self.gauge = gauge
            return true
        } catch {
            return false
        }
    }

    private func failClosedForCurrentProjection() {
        shouldTick = false
        rejectedCurrentReceipt = true
        revision &+= 1
    }

    private func sanitizedWatts(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value == 0 ? 0 : value
    }

    private func sanitizedFraction(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= 1 else { return nil }
        return value
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

private struct DashboardEnergyRailArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseline = rect.height * 0.88
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + baseline))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + baseline),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.16)
        )
        return path
    }
}

private struct DashboardRollingPowerValueView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Double

    private static let numberModel: RollingNumberModel? = {
        guard let layout = try? RollingNumberLayout(integerDigits: 4) else { return nil }
        return try? RollingNumberModel(layout: layout)
    }()

    var body: some View {
        if let numberModel = Self.numberModel,
           let snapshot = try? numberModel.snapshot(for: value) {
            HStack(spacing: -4) {
                ForEach(snapshot.digits.indices, id: \.self) { index in
                    let digit = snapshot.digits[index]
                    Text(String(digit.digit))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .opacity(digit.isVisible ? 1 : 0)
                        .contentTransition(
                            reduceMotion ? .identity : .numericText(value: value)
                        )
                        .animation(
                            reduceMotion ? nil : .snappy(duration: 0.10),
                            value: digit.digit
                        )
                        .clipped()
                }
            }
        } else {
            Text(fallbackText)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var fallbackText: String {
        guard value.isFinite, value >= 0, value <= 99_999 else { return "—" }
        return String(Int(value.rounded(.toNearestOrAwayFromZero)))
    }
}

private struct DashboardEnergyRailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let state: DashboardEnergyRailVisualState

    var body: some View {
        ZStack(alignment: .top) {
            railLayer
                .frame(height: 70)
                .padding(.top, dynamicTypeSize.isAccessibilitySize ? 72 : 22)

            powerReadout
        }
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 150 : 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Propulsion power")
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("dashboard.energy-rail")
    }

    private var railLayer: some View {
        GeometryReader { proxy in
            ZStack {
                DashboardEnergyRailArc()
                    .stroke(
                        Color.primary.opacity(colorSchemeContrast == .increased ? 0.28 : 0.14),
                        style: StrokeStyle(
                            lineWidth: colorSchemeContrast == .increased ? 3.5 : 2.5,
                            lineCap: .round
                        )
                    )

                if let fraction = state.railFraction {
                    if !reduceTransparency {
                        DashboardEnergyRailArc()
                            .trim(from: 0, to: CGFloat(fraction))
                            .stroke(
                                Color.primary.opacity(0.24),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                    }

                    DashboardEnergyRailArc()
                        .trim(from: 0, to: CGFloat(fraction))
                        .stroke(
                            Color.primary,
                            style: StrokeStyle(
                                lineWidth: colorSchemeContrast == .increased ? 7 : 5.5,
                                lineCap: .round
                            )
                        )

                    if !reduceMotion,
                       let peakMarkerFraction = state.peakMarkerFraction {
                        peakMarker(
                            at: CGFloat(peakMarkerFraction),
                            in: proxy.size
                        )
                    }
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var powerReadout: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let watts = state.displayWatts {
                    DashboardRollingPowerValueView(value: watts)
                } else {
                    Text("—")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                }

                Text("W")
                    .font(dynamicTypeSize.isAccessibilitySize ? .body.weight(.bold) : .caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text(currentnessLabel)
                .font(dynamicTypeSize.isAccessibilitySize ? .caption.weight(.bold) : .caption2.weight(.bold))
                .tracking(dynamicTypeSize.isAccessibilitySize ? 0.4 : 1.2)
                .foregroundStyle(currentnessForeground)
        }
    }

    private var currentnessLabel: String {
        switch state.currentness {
        case .live:
            return state.acceptedWatts == nil ? "POWER UNAVAILABLE" : "LIVE POWER"
        case .retained:
            return state.acceptedWatts == nil ? "POWER UNAVAILABLE" : "LAST KNOWN POWER"
        case .unavailable:
            return "POWER UNAVAILABLE"
        }
    }

    private var currentnessForeground: Color {
        switch state.currentness {
        case .live where state.acceptedWatts != nil:
            return Color.primary.opacity(colorSchemeContrast == .increased ? 0.88 : 0.68)
        case .retained where state.acceptedWatts != nil:
            return Color.primary.opacity(colorSchemeContrast == .increased ? 0.66 : 0.50)
        default:
            return Color.primary.opacity(colorSchemeContrast == .increased ? 0.50 : 0.32)
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
            return "\(Int(watts.rounded())) watts"
        }
    }

    @ViewBuilder
    private func peakMarker(at fraction: CGFloat, in size: CGSize) -> some View {
        let inverse = 1 - fraction
        let baseline = size.height * 0.88
        let controlY = size.height * 0.16
        let y = inverse * inverse * baseline
            + 2 * inverse * fraction * controlY
            + fraction * fraction * baseline

        Capsule(style: .continuous)
            .fill(Color.primary)
            .frame(width: 2, height: colorSchemeContrast == .increased ? 13 : 10)
            .position(x: size.width * fraction, y: y)
            .accessibilityHidden(true)
    }
}

/// A deliberately narrow high-frequency subtree for the landscape cockpit.
///
/// Only this view redraws on SwiftUI's animation timeline. Vehicle controls,
/// ride detection, persistence, distance, and safety continue to consume the
/// accepted domain/source state rather than rendered interpolation frames. The
/// Energy Rail is additionally capability-gated to the exact Simulator power
/// source; current physical ES80 builds therefore cannot manufacture a watt value.
@MainActor
struct DashboardSpeedInstrumentView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = SpeedInstrumentModel()
    @State private var energyRailModel = DashboardEnergyRailModel()

    let modePersonality: DashboardModePersonality

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
            let energyRailState = ownsSimulatorPowerSource
                ? energyRailModel.presentation(
                    atUptimeNanoseconds: now,
                    prefersReducedMotion: reduceMotion
                )
                : nil

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

    private func isLivePresentation(_ availability: SpeedEvidenceAvailability) -> Bool {
        if case .live = availability {
            return true
        }
        return false
    }

    private func instrumentContent(
        frame: SpeedInstrumentDisplayFrame?,
        speedAvailability: SpeedEvidenceAvailability,
        energyRailState: DashboardEnergyRailVisualState?
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
            // VoiceOver consumes the same sanitized field-specific speed state,
            // never a 60 Hz render midpoint, estimate, cached aggregate speed, or
            // synthetic sample ineligible for the active vehicle profile.
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

            if let energyRailState {
                Spacer(minLength: 6)
                DashboardEnergyRailView(state: energyRailState)
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