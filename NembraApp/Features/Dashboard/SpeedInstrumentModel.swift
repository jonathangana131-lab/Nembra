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

enum DashboardSpeedDisplayPolicy {
    /// Presentation capacity only, not a claim about ES80 performance. A future
    /// physical/GPS source still requires its own evidence-backed plausibility,
    /// accuracy, latency, and precision policy before positive wiring is enabled.
    static let maximumCanonicalKilometersPerHour = 999.94

    static func admitsCanonicalKilometersPerHour(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= maximumCanonicalKilometersPerHour
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
            guard sample.isAuthoritativeMeasurement,
                  DashboardSpeedDisplayPolicy.admitsCanonicalKilometersPerHour(
                    sample.kilometersPerHour
                  ) else { return false }
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

enum DashboardEnergyRailCurrentness: Equatable {
    case live
    case retained
    case unavailable
}

struct DashboardEnergyRailVisualState: Equatable {
    static let maximumDisplayWatts = 99_999.0
    static let fractionConsistencyTolerance = 0.001

    let currentness: DashboardEnergyRailCurrentness
    let acceptedWatts: Double?
    /// Canonical accepted-measurement position. This is the sole NOW locator.
    let acceptedCurrentFraction: Double?
    /// Render-only active-segment position. It may settle between accepted
    /// measurements and must never be labeled NOW or announced as telemetry.
    let illuminatedFraction: Double?
    /// Historical accepted peak marker inside the package-owned hold window.
    let acceptedPeakFraction: Double?
    let scaleOrigin: NembraCore.PropulsionGaugeScaleOrigin?
    let scaleCeilingWatts: Double?

    static let unavailable = DashboardEnergyRailVisualState(
        currentness: .unavailable,
        acceptedWatts: nil,
        acceptedCurrentFraction: nil,
        illuminatedFraction: nil,
        acceptedPeakFraction: nil,
        scaleOrigin: nil,
        scaleCeilingWatts: nil
    )

    /// One fail-closed projection shared by pixels and accessibility. This keeps
    /// malformed caller-constructed states from trapping during numeric
    /// conversion or announcing a NOW value whose marker cannot be rendered.
    var validatedForPresentation: DashboardEnergyRailVisualState {
        func validWatts(_ value: Double?) -> Double? {
            guard let value,
                  value.isFinite,
                  value >= 0,
                  value <= Self.maximumDisplayWatts else { return nil }
            return value == 0 ? 0 : value
        }
        func validFraction(_ value: Double?) -> Double? {
            guard let value, value.isFinite, (0...1).contains(value) else { return nil }
            return value
        }

        switch currentness {
        case .unavailable:
            return .unavailable

        case .retained:
            guard let acceptedWatts = validWatts(acceptedWatts),
                  acceptedCurrentFraction == nil,
                  illuminatedFraction == nil,
                  acceptedPeakFraction == nil,
                  scaleOrigin == nil,
                  scaleCeilingWatts == nil else {
                return .unavailable
            }
            return DashboardEnergyRailVisualState(
                currentness: .retained,
                acceptedWatts: acceptedWatts,
                acceptedCurrentFraction: nil,
                illuminatedFraction: nil,
                acceptedPeakFraction: nil,
                scaleOrigin: nil,
                scaleCeilingWatts: nil
            )

        case .live:
            guard let acceptedWatts = validWatts(acceptedWatts),
                  let acceptedCurrentFraction = validFraction(acceptedCurrentFraction),
                  let illuminatedFraction = validFraction(illuminatedFraction),
                  let scaleOrigin,
                  let scaleCeilingWatts = validWatts(scaleCeilingWatts),
                  scaleCeilingWatts > 0 else {
                return .unavailable
            }
            let expectedAcceptedFraction = min(1, acceptedWatts / scaleCeilingWatts)
            guard abs(acceptedCurrentFraction - expectedAcceptedFraction)
                    <= Self.fractionConsistencyTolerance else {
                // NOW is accepted telemetry, not an arbitrary caller-supplied
                // marker. Preserve above-envelope watts by saturating at one,
                // but reject a position that contradicts the admitted scale.
                return .unavailable
            }
            return DashboardEnergyRailVisualState(
                currentness: .live,
                acceptedWatts: acceptedWatts,
                acceptedCurrentFraction: acceptedCurrentFraction,
                illuminatedFraction: illuminatedFraction,
                acceptedPeakFraction: validFraction(acceptedPeakFraction),
                scaleOrigin: scaleOrigin,
                scaleCeilingWatts: scaleCeilingWatts
            )
        }
    }
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
final class DashboardEnergyRailModel {
    private enum Timing {
        static let riseNanoseconds: UInt64 = 220_000_000
        static let fallNanoseconds: UInt64 = 150_000_000
        // NembraCore owns accepted-peak bookkeeping. The app schedules redraws at
        // receipt-derived candidate expiry boundaries, then asks the package whether
        // the held peak still exists. Candidate wakes never become peak evidence.
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
    @ObservationIgnored private var peakWakeDeadlines: [UInt64] = []
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
                acceptedCurrentFraction: nil,
                illuminatedFraction: nil,
                acceptedPeakFraction: nil,
                scaleOrigin: nil,
                scaleCeilingWatts: nil
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
                acceptedCurrentFraction: nil,
                illuminatedFraction: nil,
                acceptedPeakFraction: nil,
                scaleOrigin: nil,
                scaleCeilingWatts: nil
            )

        case .live:
            guard let accepted = validatedAcceptedMeasurement(
                snapshot.measurement,
                receipt: receipt,
                expectedIdentity: gauge.identity
            ), rail.acceptedWatts == accepted.watts else {
                return .unavailable
            }

            let accessibility = gauge.accessibilitySnapshot(
                atUptimeNanoseconds: uptimeNanoseconds,
                scale: scale
            )
            guard accessibility.availability == .live,
                  accessibility.latestAcceptedWatts == accepted.watts,
                  accessibility.latestAcceptedReceiptSequenceNumber == accepted.receiptSequenceNumber,
                  accessibility.latestAcceptedUptimeNanoseconds == accepted.receivedAtUptimeNanoseconds,
                  accessibility.latestAuthority == .simulator,
                  let acceptedFraction = accessibility.acceptedObservedScaleFraction,
                  accessibility.scaleOrigin == .simulator,
                  rail.scaleOrigin == .simulator else {
                return .unavailable
            }

            let illuminatedFraction = prefersReducedMotion
                ? acceptedFraction
                : rail.railFraction

            return DashboardEnergyRailVisualState(
                currentness: .live,
                acceptedWatts: accepted.watts,
                acceptedCurrentFraction: acceptedFraction,
                illuminatedFraction: illuminatedFraction,
                acceptedPeakFraction: rail.acceptedPeakMarkerFraction,
                scaleOrigin: accessibility.scaleOrigin,
                scaleCeilingWatts: scale.ceilingWatts
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
        cancelAnimationAndFreshnessWakes()
        shouldTick = animationDurationNanoseconds > 0

        if animationDurationNanoseconds > 0 {
            animationEndTask = scheduleWake(afterNanoseconds: animationDurationNanoseconds) { model in
                model.shouldTick = false
                model.animationEndTask = nil
                model.revision &+= 1
            }
        }

        enqueuePeakCandidate(for: receipt)

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

    /// Every accepted receipt contributes only a candidate peak-expiry boundary.
    /// The app never decides which receipt owns the peak. The earliest outstanding
    /// candidate wake is preserved across lower receipts; when it fires, NembraCore
    /// is queried for the actual held peak. If the package still holds a newer peak,
    /// the next candidate is scheduled. When the package removes the marker, all
    /// later candidates are discarded. This keeps the package the sole peak authority
    /// without one sleeping task per telemetry callback.
    private func enqueuePeakCandidate(for receipt: Receipt) {
        guard let deadline = deadlineFromReceipt(
            receipt,
            offsetNanoseconds: Timing.peakHoldNanoseconds
        ) else { return }

        if !peakWakeDeadlines.contains(deadline) {
            peakWakeDeadlines.append(deadline)
            peakWakeDeadlines.sort()
        }
        scheduleNextPeakWakeIfNeeded()
    }

    private func scheduleNextPeakWakeIfNeeded() {
        guard peakEndTask == nil, let deadline = peakWakeDeadlines.first else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let delay = deadline > now ? deadline - now : 0

        peakEndTask = scheduleWake(afterNanoseconds: delay) { model in
            model.peakEndTask = nil
            let wakeUptime = DispatchTime.now().uptimeNanoseconds
            model.peakWakeDeadlines.removeAll { $0 <= wakeUptime }
            model.revision &+= 1

            guard let gauge = model.gauge,
                  let scale = model.scale,
                  gauge.cockpitSnapshot(
                    atUptimeNanoseconds: wakeUptime,
                    scale: scale
                  ).energyRailPresentation.acceptedPeakMarkerFraction != nil else {
                model.peakWakeDeadlines.removeAll()
                return
            }

            model.scheduleNextPeakWakeIfNeeded()
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

    private func deadlineFromReceipt(
        _ receipt: Receipt,
        offsetNanoseconds: UInt64
    ) -> UInt64? {
        guard receipt.receivedAtUptimeNanoseconds <= UInt64.max - offsetNanoseconds - 1 else {
            return nil
        }
        return receipt.receivedAtUptimeNanoseconds + offsetNanoseconds + 1
    }

    private func delayFromReceipt(
        _ receipt: Receipt,
        offsetNanoseconds: UInt64
    ) -> UInt64? {
        guard let deadline = deadlineFromReceipt(receipt, offsetNanoseconds: offsetNanoseconds) else {
            return nil
        }
        let now = DispatchTime.now().uptimeNanoseconds
        return deadline > now ? deadline - now : 0
    }

    private func cancelAnimationAndFreshnessWakes() {
        animationEndTask?.cancel()
        freshnessTask?.cancel()
        animationEndTask = nil
        freshnessTask = nil
        shouldTick = false
    }

    private func cancelScheduledWakes() {
        cancelAnimationAndFreshnessWakes()
        peakEndTask?.cancel()
        peakEndTask = nil
        peakWakeDeadlines.removeAll()
    }

    private func failClosedForCurrentProjection() {
        cancelScheduledWakes()
        rejectedCurrentReceipt = true
        revision &+= 1
    }
}

struct DashboardPropulsionGeometry {
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint

    init(size: CGSize) {
        let horizontalInset = max(18, min(28, size.width * 0.032))
        let endpointY = size.height * 0.58
        // The post-V4 instrument is a shallow precision horizon, not a scenic
        // arch. The quadratic stays symmetric while leaving clear label space
        // above and below every marker.
        let renderedApexY = endpointY - min(10, size.height * 0.10)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var scaledPointSize: CGFloat = 18

    let value: Double

    var body: some View {
        Text(validatedText)
            .font(
                .system(
                    size: min(scaledPointSize, dynamicTypeSize.isAccessibilitySize ? 28 : 20),
                    weight: .semibold,
                    design: .default
                )
            )
            .fontWidth(.expanded)
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText(value: value))
    }

    private var validatedText: String {
        guard value.isFinite, value >= 0, value <= 99_999 else { return "—" }
        return String(Int(value.rounded(.toNearestOrAwayFromZero)))
    }
}

struct DashboardPowerInstrumentSemantics: Equatable {
    let currentnessText: String
    let scaleText: String?
    let accessibilityValue: String

    init(state: DashboardEnergyRailVisualState, isSimulatorQA: Bool) {
        let state = state.validatedForPresentation
        let qaPrefix = isSimulatorQA
            ? "Simulator QA synthetic evidence, not physical scooter truth. "
            : ""
        let scaleText: String? = {
            guard let ceiling = state.scaleCeilingWatts,
                  ceiling.isFinite,
                  ceiling > 0 else { return nil }
            let value = Int(ceiling.rounded())
            return switch state.scaleOrigin {
            case .simulator: "QA SCALE · \(value) W"
            case .verifiedObservedEnvelope: "OBSERVED RANGE · \(value) W"
            case nil: nil
            }
        }()
        self.scaleText = scaleText

        switch state.currentness {
        case .unavailable:
            currentnessText = "POWER UNAVAILABLE"
            accessibilityValue = qaPrefix + "Propulsion power unavailable. No zero value or position is inferred."

        case .retained:
            guard let watts = state.acceptedWatts else {
                currentnessText = "POWER UNAVAILABLE"
                accessibilityValue = qaPrefix + "Propulsion power unavailable. No zero value or position is inferred."
                return
            }
            let accepted = Int(watts.rounded())
            currentnessText = "LAST KNOWN"
            accessibilityValue = qaPrefix
                + "Last known propulsion power, \(accepted) watts. No live position or motion is shown."

        case .live:
            guard let watts = state.acceptedWatts,
                  state.acceptedCurrentFraction != nil else {
                currentnessText = "POWER UNAVAILABLE"
                accessibilityValue = qaPrefix + "Propulsion power unavailable. No zero value or position is inferred."
                return
            }
            let accepted = Int(watts.rounded())
            currentnessText = "ACCEPTED LIVE POWER"
            let peak = DashboardPowerPeakMarkerPolicy.visiblePeakFraction(
                current: state.acceptedCurrentFraction,
                peak: state.acceptedPeakFraction
            ) == nil
                ? ""
                : " A hollow marker shows the recent accepted peak."
            let scale = scaleText.map { " Presentation scale: \($0.lowercased())." } ?? ""
            accessibilityValue = qaPrefix
                + "NOW, \(accepted) accepted watts, positioned from zero toward positive propulsion."
                + peak
                + scale
        }
    }
}

enum DashboardPowerPeakMarkerPolicy {
    static let minimumSeparation = 0.025

    static func visiblePeakFraction(current: Double?, peak: Double?) -> Double? {
        guard let current,
              let peak,
              current.isFinite,
              peak.isFinite,
              (0...1).contains(current),
              (0...1).contains(peak),
              peak - current >= minimumSeparation else {
            return nil
        }
        return peak
    }
}

private struct DashboardEnergyRailView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var scaledMicroLabelSize: CGFloat = 8
    @ScaledMetric(relativeTo: .caption) private var scaledSmallLabelSize: CGFloat = 9

    let state: DashboardEnergyRailVisualState
    let isSimulatorQA: Bool

    init(state: DashboardEnergyRailVisualState, isSimulatorQA: Bool) {
        self.state = state.validatedForPresentation
        self.isSimulatorQA = isSimulatorQA
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = DashboardPropulsionGeometry(size: proxy.size)
            let semantics = DashboardPowerInstrumentSemantics(
                state: state,
                isSimulatorQA: isSimulatorQA
            )

            ZStack {
                Canvas(opaque: false, rendersAsynchronously: true) { context, _ in
                    drawIllumination(context: &context, geometry: geometry)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                DashboardEnergyRailStaticTrack(
                    size: proxy.size,
                    increasedContrast: colorSchemeContrast == .increased
                )
                .equatable()

                Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
                    drawMarkers(context: &context, geometry: geometry)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                liveLabels(geometry: geometry, size: proxy.size)

                if state.currentness != .live || state.acceptedCurrentFraction == nil {
                    statusReadout(semantics: semantics)
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.30)
                }

                Text("0")
                    .font(.system(size: smallLabelSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NembraColor.secondaryText.opacity(0.88))
                    .position(x: geometry.start.x, y: geometry.start.y + 17)
                    .accessibilityHidden(true)

                Text("PROPULSION  →")
                    .font(.system(size: smallLabelSize, weight: .bold, design: .default))
                    .tracking(1.5)
                    .foregroundStyle(NembraColor.secondaryText.opacity(0.88))
                    .position(x: proxy.size.width * 0.24, y: proxy.size.height * 0.90)
                    .accessibilityHidden(true)

                if let scaleText = semantics.scaleText {
                    Text(scaleText)
                        .font(.system(size: microLabelSize, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(NembraColor.secondaryText.opacity(0.88))
                        .position(x: proxy.size.width * 0.78, y: proxy.size.height * 0.90)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Propulsion power")
        .accessibilityValue(
            DashboardPowerInstrumentSemantics(state: state, isSimulatorQA: isSimulatorQA)
                .accessibilityValue
        )
        .accessibilityIdentifier("dashboard.energy-rail")
    }

    @ViewBuilder
    private func liveLabels(
        geometry: DashboardPropulsionGeometry,
        size: CGSize
    ) -> some View {
        if state.currentness == .live,
           let current = validFraction(state.acceptedCurrentFraction),
           let watts = state.acceptedWatts {
            let point = geometry.point(at: Double(current))
            let labelX = min(max(point.x, 62), size.width - 62)

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("NOW")
                        .font(.system(size: microLabelSize, weight: .black, design: .default))
                        .tracking(1.1)
                        .foregroundStyle(NembraColor.gold)
                    DashboardRollingPowerValueView(value: watts)
                    Text("W")
                        .font(.system(size: smallLabelSize, weight: .bold, design: .default))
                        .foregroundStyle(NembraColor.secondaryText)
                }
                Text("ACCEPTED")
                    .font(.system(size: microLabelSize, weight: .bold, design: .default))
                    .tracking(0.8)
                    .foregroundStyle(NembraColor.secondaryText.opacity(0.88))
            }
            .position(
                x: labelX,
                y: max(dynamicTypeSize.isAccessibilitySize ? 22 : 15, point.y - (dynamicTypeSize.isAccessibilitySize ? 33 : 27))
            )
            .accessibilityHidden(true)

            if let peak = distinctPeakFraction(from: current) {
                let peakPoint = geometry.point(at: Double(peak))
                Text("RECENT PEAK")
                    .font(.system(size: microLabelSize, weight: .bold, design: .default))
                    .tracking(0.8)
                    .foregroundStyle(NembraColor.secondaryText.opacity(0.88))
                    .position(
                        x: min(max(peakPoint.x, 42), size.width - 42),
                        y: peakPoint.y + (dynamicTypeSize.isAccessibilitySize ? 25 : 21)
                    )
                    .accessibilityHidden(true)
            }
        }
    }

    private var microLabelSize: CGFloat {
        min(scaledMicroLabelSize, dynamicTypeSize.isAccessibilitySize ? 13 : 10)
    }

    private var smallLabelSize: CGFloat {
        min(scaledSmallLabelSize, dynamicTypeSize.isAccessibilitySize ? 15 : 11)
    }

    private func drawIllumination(
        context: inout GraphicsContext,
        geometry: DashboardPropulsionGeometry
    ) {
        if state.currentness == .live,
           let fraction = validFraction(state.illuminatedFraction) {
            let activePath = geometry.path.trimmedPath(from: 0, to: fraction)
            if !reduceTransparency {
                context.stroke(
                    activePath,
                    with: .color(NembraColor.gold.opacity(0.13)),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round)
                )
                context.stroke(
                    activePath,
                    with: .linearGradient(
                        Gradient(colors: [NembraColor.deepGold, NembraColor.gold]),
                        startPoint: geometry.start,
                        endPoint: geometry.end
                    ),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                )
            } else {
                context.stroke(
                    activePath,
                    with: .color(NembraColor.gold),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private func drawMarkers(
        context: inout GraphicsContext,
        geometry: DashboardPropulsionGeometry
    ) {
        guard state.currentness == .live else { return }

        if let current = validFraction(state.acceptedCurrentFraction),
           let peak = distinctPeakFraction(from: current) {
            let center = geometry.point(at: Double(peak))
            let rect = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: rect), with: .color(NembraColor.baseBlack))
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(Color.white.opacity(0.78)),
                style: StrokeStyle(lineWidth: 1.6)
            )
            var peakStem = Path()
            peakStem.move(to: CGPoint(x: center.x, y: center.y + 6))
            peakStem.addLine(to: CGPoint(x: center.x, y: center.y + 14))
            context.stroke(
                peakStem,
                with: .color(Color.white.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 2])
            )
        }

        if let current = validFraction(state.acceptedCurrentFraction) {
            let center = geometry.point(at: Double(current))
            let totalWidth = geometry.start.x + geometry.end.x
            let labelX = min(max(center.x, 62), totalWidth - 62)
            var stem = Path()
            stem.move(to: CGPoint(x: center.x, y: center.y - 5))
            stem.addLine(to: CGPoint(x: center.x, y: center.y - 14))
            if abs(labelX - center.x) > 0.5 {
                stem.addLine(to: CGPoint(x: labelX, y: center.y - 14))
            }
            context.stroke(
                stem,
                with: .color(Color.white.opacity(0.92)),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )

            let radius: CGFloat = differentiateWithoutColor ? 8 : 7
            var diamond = Path()
            diamond.move(to: CGPoint(x: center.x, y: center.y - radius))
            diamond.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            diamond.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            diamond.addLine(to: CGPoint(x: center.x - radius, y: center.y))
            diamond.closeSubpath()
            context.fill(diamond, with: .color(NembraColor.gold))
            context.stroke(
                diamond,
                with: .color(Color.white.opacity(0.98)),
                style: StrokeStyle(lineWidth: differentiateWithoutColor ? 2.4 : 1.8, lineJoin: .round)
            )
        }
    }

    private func statusReadout(
        semantics: DashboardPowerInstrumentSemantics
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let watts = state.acceptedWatts {
                DashboardRollingPowerValueView(value: watts)
                Text("W")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(NembraColor.secondaryText)
            } else {
                Text("—")
                    .font(.system(size: 18, weight: .light, design: .default))
            }
            Text(semantics.currentnessText)
                .font(.system(size: 8, weight: .semibold, design: .default))
                .tracking(0.7)
                .foregroundStyle(currentnessColor)
        }
    }

    private var currentnessColor: Color {
        switch state.currentness {
        case .live where state.acceptedWatts != nil: NembraColor.gold.opacity(0.82)
        case .retained where state.acceptedWatts != nil: NembraColor.secondaryText.opacity(0.88)
        default: NembraColor.secondaryText.opacity(0.88)
        }
    }

    private func distinctPeakFraction(from current: CGFloat) -> CGFloat? {
        DashboardPowerPeakMarkerPolicy.visiblePeakFraction(
            current: Double(current),
            peak: state.acceptedPeakFraction
        ).map { CGFloat($0) }
    }

    private func validFraction(_ value: Double?) -> CGFloat? {
        guard let value, value.isFinite, (0...1).contains(value) else { return nil }
        return CGFloat(value)
    }
}

@MainActor
private struct DashboardEnergyRailStaticTrack: View, @MainActor Equatable {
    let size: CGSize
    let increasedContrast: Bool

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            let geometry = DashboardPropulsionGeometry(size: size)
            context.stroke(
                geometry.path,
                with: .color(Color.white.opacity(increasedContrast ? 1 : 0.92)),
                style: StrokeStyle(
                    lineWidth: increasedContrast ? 3.4 : 2.2,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            var zero = Path()
            zero.move(to: CGPoint(x: geometry.start.x, y: geometry.start.y - 6))
            zero.addLine(to: CGPoint(x: geometry.start.x, y: geometry.start.y + 6))
            context.stroke(
                zero,
                with: .color(Color.white.opacity(0.95)),
                style: StrokeStyle(lineWidth: increasedContrast ? 2.4 : 1.7, lineCap: .round)
            )

            let tip = geometry.end
            var arrow = Path()
            arrow.move(to: CGPoint(x: tip.x - 7, y: tip.y - 4))
            arrow.addLine(to: tip)
            arrow.addLine(to: CGPoint(x: tip.x - 7, y: tip.y + 4))
            context.stroke(
                arrow,
                with: .color(Color.white.opacity(0.95)),
                style: StrokeStyle(lineWidth: increasedContrast ? 2.4 : 1.7, lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum DashboardInstrumentRenderSchedule: Equatable {
    case timeline
    case staticFrame

    static func resolve(
        prefersReducedMotion: Bool,
        hasLiveSpeed: Bool,
        speedIsSettling: Bool,
        ownsLivePowerSource: Bool,
        powerIsSettling: Bool
    ) -> Self {
        guard !prefersReducedMotion else { return .staticFrame }
        if hasLiveSpeed && speedIsSettling { return .timeline }
        if ownsLivePowerSource && powerIsSettling { return .timeline }
        return .staticFrame
    }
}

enum DashboardSpeedUnitPresentation {
    static func usesMetric(preferenceRawValue: String, systemUsesMetric: Bool) -> Bool {
        switch NembraUnitsPreference(rawValue: preferenceRawValue) ?? .system {
        case .system: systemUsesMetric
        case .miles: false
        case .metric: true
        }
    }
}

/// Deterministic, non-overlapping cockpit instrument bands. In compact landscape
/// space the primary speed instrument wins: internal clearances shrink first and
/// then the Energy Rail may compress before the readable speed band is starved.
/// This is presentation geometry only; no telemetry or evidence authority lives here.
struct DashboardInstrumentVerticalLayout: Equatable {
    let speedFrame: CGRect
    let energyRailFrame: CGRect

    init(size: CGSize, usesAccessibilityLayout: Bool) {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            speedFrame = .zero
            energyRailFrame = .zero
            return
        }

        let desiredTopClearance = usesAccessibilityLayout ? 86.0 : 54.0
        let desiredBottomClearance = usesAccessibilityLayout ? 108.0 : 62.0
        let minimumSpeedHeight = usesAccessibilityLayout ? 92.0 : 112.0
        let compactRailFloor = usesAccessibilityLayout ? 44.0 : 64.0
        let desiredGap = usesAccessibilityLayout ? 8.0 : 10.0
        let minimumContentHeight = minimumSpeedHeight + compactRailFloor + desiredGap
        let desiredTotalClearance = desiredTopClearance + desiredBottomClearance
        let maximumTotalClearance = max(0, size.height - minimumContentHeight)
        let clearanceScale = desiredTotalClearance > 0
            ? min(1, maximumTotalClearance / desiredTotalClearance)
            : 0
        let topClearance = desiredTopClearance * clearanceScale
        let bottomClearance = desiredBottomClearance * clearanceScale
        let availableHeight = max(0, size.height - topClearance - bottomClearance)
        let speedReservation = min(minimumSpeedHeight, availableHeight)
        let gapCapacity = max(0, availableHeight - speedReservation)
        let gap = min(desiredGap, gapCapacity)
        let maximumRailHeightForSpeed = max(0, availableHeight - gap - speedReservation)
        let desiredRailHeight = usesAccessibilityLayout ? 74.0 : 98.0
        let proportionalRailHeight = availableHeight * (usesAccessibilityLayout ? 0.36 : 0.39)
        let preferredRailHeight = min(
            desiredRailHeight,
            max(compactRailFloor, proportionalRailHeight)
        )
        let railHeight = min(maximumRailHeightForSpeed, preferredRailHeight)
        let speedHeight = max(0, availableHeight - gap - railHeight)

        speedFrame = CGRect(
            x: 0,
            y: topClearance,
            width: size.width,
            height: speedHeight
        )
        energyRailFrame = CGRect(
            x: 0,
            y: speedFrame.maxY + gap,
            width: size.width,
            height: railHeight
        )
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @AppStorage(NembraPreferenceKey.units) private var unitsPreferenceRawValue = ""
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
        let usesMetric = DashboardSpeedUnitPresentation.usesMetric(
            preferenceRawValue: unitsPreferenceRawValue,
            systemUsesMetric: locale.measurementSystem == .metric
        )
        let renderSchedule = DashboardInstrumentRenderSchedule.resolve(
            prefersReducedMotion: reduceMotion,
            hasLiveSpeed: isLivePresentation(speedAvailability),
            speedIsSettling: speedShouldTick,
            ownsLivePowerSource: ownsSimulatorPowerSource,
            powerIsSettling: energyRailShouldTick
        )

        Group {
            if renderSchedule == .timeline {
                TimelineView(.animation(minimumInterval: nil, paused: false)) { _ in
                    instrumentContent(
                        atUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                        rawSpeedAvailability: rawSpeedAvailability,
                        speedAvailability: speedAvailability,
                        allowsSimulatorQA: allowsSimulatorQA,
                        ownsSimulatorPowerSource: ownsSimulatorPowerSource,
                        usesMetric: usesMetric
                    )
                }
            } else {
                instrumentContent(
                    atUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                    rawSpeedAvailability: rawSpeedAvailability,
                    speedAvailability: speedAvailability,
                    allowsSimulatorQA: allowsSimulatorQA,
                    ownsSimulatorPowerSource: ownsSimulatorPowerSource,
                    usesMetric: usesMetric
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
        ownsSimulatorPowerSource: Bool,
        usesMetric: Bool
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
            energyRailState: energyRailState,
            usesMetric: usesMetric
        )
    }

    private func instrumentContent(
        frame: SpeedInstrumentDisplayFrame?,
        speedAvailability: SpeedEvidenceAvailability,
        energyRailState: DashboardEnergyRailVisualState,
        usesMetric: Bool
    ) -> some View {
        GeometryReader { proxy in
            let layout = DashboardInstrumentVerticalLayout(
                size: proxy.size,
                usesAccessibilityLayout: dynamicTypeSize.isAccessibilitySize
            )
            let integerSize = if dynamicTypeSize.isAccessibilitySize {
                min(96, max(68, layout.speedFrame.height * 0.60))
            } else {
                min(126, max(84, layout.speedFrame.height * 0.72))
            }
            let fractionSize = max(dynamicTypeSize.isAccessibilitySize ? 24 : 30, integerSize * 0.34)

            ZStack {
                speedReadout(
                    frame: frame,
                    availability: speedAvailability,
                    integerSize: integerSize,
                    fractionSize: fractionSize,
                    usesMetric: usesMetric
                )
                .frame(
                    width: layout.speedFrame.width,
                    height: layout.speedFrame.height
                )
                .position(x: layout.speedFrame.midX, y: layout.speedFrame.midY)

                DashboardEnergyRailView(
                    state: energyRailState,
                    isSimulatorQA: vehicle.profile == .simulatorQA
                )
                    .frame(
                        width: layout.energyRailFrame.width,
                        height: layout.energyRailFrame.height
                    )
                    .position(
                        x: layout.energyRailFrame.midX,
                        y: layout.energyRailFrame.midY
                    )
            }
        }
    }

    private func speedReadout(
        frame: SpeedInstrumentDisplayFrame?,
        availability: SpeedEvidenceAvailability,
        integerSize: CGFloat,
        fractionSize: CGFloat,
        usesMetric: Bool
    ) -> some View {
        VStack(spacing: -2) {
            RollingSpeedValueView(
                value: displayedValue(
                    kilometersPerHour: frame?.kilometersPerHour,
                    usesMetric: usesMetric
                ),
                integerPointSize: integerSize,
                fractionPointSize: fractionSize
            )
            .lineLimit(1)
            .accessibilityHidden(true)

            HStack(spacing: 9) {
                Text(speedUnitText(usesMetric: usesMetric))
                    .tracking(3.2)
                    .foregroundStyle(NembraColor.secondaryText.opacity(0.92))

                Text("·")
                    .foregroundStyle(NembraColor.secondaryText.opacity(0.86))

                Text(speedCurrentnessText(availability))
                    .tracking(1.5)
                    .foregroundStyle(speedCurrentnessColor(availability))
            }
            .font(.caption2.weight(.bold))
            .padding(.top, 2)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speed")
        .accessibilityValue(accessibilitySpeed(availability, usesMetric: usesMetric))
        .accessibilityIdentifier("dashboard.speed")
    }

    private func isLivePresentation(_ availability: SpeedEvidenceAvailability) -> Bool {
        if case .live = availability { return true }
        return false
    }

    private func displayedValue(kilometersPerHour: Double?, usesMetric: Bool) -> Double? {
        guard let kilometersPerHour,
              DashboardSpeedDisplayPolicy.admitsCanonicalKilometersPerHour(
                kilometersPerHour
              ) else { return nil }
        let normalized = kilometersPerHour == 0 ? 0 : kilometersPerHour
        return usesMetric ? normalized : normalized * 0.621_371
    }

    private func accessibilitySpeed(
        _ availability: SpeedEvidenceAvailability,
        usesMetric: Bool
    ) -> String {
        let prefix = vehicle.profile == .simulatorQA
            ? "Simulator QA synthetic evidence, not physical scooter truth. "
            : ""
        return prefix + {
            switch availability {
            case .unavailable:
                return "Unavailable"
            case let .retained(sample):
                let value = displayedValue(
                    kilometersPerHour: sample.kilometersPerHour,
                    usesMetric: usesMetric
                )
                guard RollingSpeedValueView.supports(value) else {
                    return "Last known speed unavailable because the accepted value exceeds the display safety bound"
                }
                return "Last known, \(formattedSpeed(sample.kilometersPerHour, usesMetric: usesMetric))"
            case let .live(sample):
                let value = displayedValue(
                    kilometersPerHour: sample.kilometersPerHour,
                    usesMetric: usesMetric
                )
                guard RollingSpeedValueView.supports(value) else {
                    return "Unavailable because the accepted speed exceeds the display safety bound"
                }
                return formattedSpeed(sample.kilometersPerHour, usesMetric: usesMetric)
            }
        }()
    }

    private func speedCurrentnessText(_ availability: SpeedEvidenceAvailability) -> String {
        switch availability {
        case .live: "LIVE"
        case .retained: "LAST KNOWN"
        case .unavailable: "UNAVAILABLE"
        }
    }

    private func speedCurrentnessColor(_ availability: SpeedEvidenceAvailability) -> Color {
        switch availability {
        case .live: colorSchemeContrast == .increased ? .white : NembraColor.primaryText.opacity(0.68)
        case .retained: NembraColor.secondaryText.opacity(0.88)
        case .unavailable: NembraColor.secondaryText.opacity(0.88)
        }
    }

    private func formattedSpeed(_ kilometersPerHour: Double, usesMetric: Bool) -> String {
        let value = usesMetric ? kilometersPerHour : kilometersPerHour * 0.621_371
        let unit = usesMetric ? "km/h" : "mph"
        return String(format: "%.1f %@", locale: locale, value, unit)
    }

    private func speedUnitText(usesMetric: Bool) -> String {
        usesMetric ? "KM/H" : "MPH"
    }
}
