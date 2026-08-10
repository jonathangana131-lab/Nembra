import Foundation

/// Display-clock scheduling metadata owned by the source-receipt Energy Rail adapter.
///
/// This is presentation state only. It never creates source receipts, changes accepted
/// chronology, refreshes measurement currentness, or becomes telemetry/history evidence.
public struct PropulsionEnergyRailSourceReceiptDisplaySchedule: Equatable, Sendable {
    public let requiresContinuousFrames: Bool
    public let nextTransitionUptimeNanoseconds: UInt64?

    public init(
        requiresContinuousFrames: Bool,
        nextTransitionUptimeNanoseconds: UInt64?
    ) {
        self.requiresContinuousFrames = requiresContinuousFrames
        self.nextTransitionUptimeNanoseconds = nextTransitionUptimeNanoseconds
    }

    public static let inactive = Self(
        requiresContinuousFrames: false,
        nextTransitionUptimeNanoseconds: nil
    )
}

/// Receipt-aware Simulator presentation runtime for the Energy Rail.
///
/// This type is deliberately a **presentation sink**, not a source of propulsion
/// authority. App integration must obtain the four receipt primitives from the
/// app-owned, exact `SimulatedScooterService` custody boundary. The runtime then
/// preserves those primitives mechanically instead of inventing sequence numbers,
/// continuity generations, or measurement timestamps from view/render/state clocks.
///
/// The source and package are currently compiled through different module paths in
/// Nembra.app, so the app cannot pass the source's concrete observation type across
/// this boundary directly. Loose primitives are therefore accepted here only as an
/// integration transport; callers do not gain source authority by calling this API.
public struct PropulsionEnergyRailSourceReceiptRuntime: Sendable {
    private enum SourceCurrentness: Equatable, Sendable {
        case live
        case retained(retainedProjectionUptimeNanoseconds: UInt64)
        case unavailable
    }

    private struct Receipt: Equatable, Sendable {
        let watts: Double
        let receiptSequenceNumber: UInt64
        let receivedAtUptimeNanoseconds: UInt64
        let continuityGeneration: UInt64
    }

    private let animationPolicy: PropulsionGaugeAnimationPolicy
    private let freshnessPolicy: PropulsionGaugeFreshnessPolicy
    private var session: PropulsionGaugeSourceSession
    private let scale: PropulsionGaugeScale

    private var sourceCurrentness: SourceCurrentness = .unavailable
    private var latestAcceptedReceipt: Receipt?

    // Presentation-only scheduling mirrors. These are downstream of accepted
    // source receipts and never feed back into source chronology or evidence.
    private var presentationTransitionEndUptimeNanoseconds: UInt64?
    private var presentationPeakWatts: Double?
    private var presentationPeakUptimeNanoseconds: UInt64?

    public var identity: PropulsionGaugeIdentity { session.identity }

    public init(
        vehicleID: String = "nembra-simulator",
        presentationCeilingWatts: Double = PropulsionEnergyRailSimulatorRuntime.defaultPresentationCeilingWatts,
        freshnessNanoseconds: UInt64 = PropulsionEnergyRailSimulatorRuntime.defaultFreshnessNanoseconds
    ) throws {
        let identity = try PropulsionGaugeIdentity(vehicleID: vehicleID)
        let animationPolicy = try PropulsionGaugeAnimationPolicy(
            riseSettlingDurationNanoseconds: 220_000_000,
            fallSettlingDurationNanoseconds: 150_000_000,
            acceptedPeakHoldNanoseconds: 2_000_000_000
        )
        let freshnessPolicy = try PropulsionGaugeFreshnessPolicy(
            staleAfterNanoseconds: freshnessNanoseconds
        )

        self.animationPolicy = animationPolicy
        self.freshnessPolicy = freshnessPolicy
        self.session = PropulsionGaugeSourceSession(
            identity: identity,
            animationPolicy: animationPolicy,
            freshnessPolicy: freshnessPolicy
        )
        self.scale = try PropulsionGaugeScale.simulator(
            identity: identity,
            ceilingWatts: presentationCeilingWatts
        )
    }

    /// Applies one source-issued LIVE Simulator observation.
    ///
    /// A byte-for-byte replay is idempotent only while the runtime already regards
    /// that exact receipt as live. A retained receipt cannot be re-promoted merely by
    /// rewrapping the same receipt as live; source recovery must arrive with a newer
    /// source-issued receipt identity.
    @discardableResult
    public mutating func ingestLive(
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) -> Bool {
        guard let incoming = validatedReceipt(
            watts: watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration
        ) else {
            failClosedUnavailable()
            return false
        }

        if incoming == latestAcceptedReceipt {
            guard sourceCurrentness == .live else {
                // Currentness cannot be upgraded by relabeling the same immutable
                // receipt after the source already retired it.
                return false
            }
            return true
        }

        guard accept(incoming) else {
            failClosedUnavailable()
            return false
        }

        sourceCurrentness = .live
        return true
    }

    /// Applies one source-issued RETAINED Simulator observation.
    ///
    /// A fresh SwiftUI/runtime lifetime may first encounter a retained observation
    /// without ever seeing its earlier live event. In that case the exact immutable
    /// receipt is accepted once into the canonical package model, then projection is
    /// forced past the package freshness boundary before anything becomes visible.
    /// The first observable state is therefore retained/static; no live animation,
    /// peak promotion, new receipt, or freshness refresh is created by remount.
    @discardableResult
    public mutating func ingestRetained(
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) -> Bool {
        guard let incoming = validatedReceipt(
            watts: watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration
        ),
        let retainedProjectionUptime = exclusiveDeadline(
            after: incoming.receivedAtUptimeNanoseconds,
            interval: freshnessPolicy.staleAfterNanoseconds
        ) else {
            failClosedUnavailable()
            return false
        }

        if incoming != latestAcceptedReceipt {
            guard accept(incoming) else {
                failClosedUnavailable()
                return false
            }
        }

        sourceCurrentness = .retained(
            retainedProjectionUptimeNanoseconds: retainedProjectionUptime
        )
        resetPresentationSchedule()
        return true
    }

    /// Applies source-owned complete unavailability. No zero-watt sample is created.
    /// If a legitimate receipt was previously accepted, its exact source continuity
    /// generation is retired; a later live sample must therefore belong to a newer
    /// source generation under `PropulsionGaugeSourceSession` chronology rules.
    public mutating func ingestUnavailable() {
        failClosedUnavailable()
    }

    /// Canonical sealed app projection. Source-retained currentness is stronger than
    /// the generic package freshness timer: retained input is projected at a
    /// deterministic uptime strictly beyond the accepted sample's freshness boundary.
    /// This is presentation-time selection only and cannot change the accepted receipt.
    public func projection(
        atUptimeNanoseconds now: UInt64
    ) -> PropulsionEnergyRailAppProjection {
        switch sourceCurrentness {
        case .live:
            return session.energyRailAppProjection(
                atUptimeNanoseconds: now,
                scale: scale
            )

        case let .retained(retainedProjectionUptimeNanoseconds):
            return session.energyRailAppProjection(
                atUptimeNanoseconds: max(now, retainedProjectionUptimeNanoseconds),
                scale: scale
            )

        case .unavailable:
            return session.energyRailAppProjection(
                atUptimeNanoseconds: now,
                scale: scale
            )
        }
    }

    /// Display-only scheduling derived from already-accepted source receipts.
    /// Retained/unavailable source state is intentionally quiescent.
    public func displaySchedule(
        atUptimeNanoseconds now: UInt64
    ) -> PropulsionEnergyRailSourceReceiptDisplaySchedule {
        guard sourceCurrentness == .live else { return .inactive }

        let frame = session.frame(
            atUptimeNanoseconds: now,
            scale: scale
        )
        guard frame.availability == .live else { return .inactive }

        let requiresContinuousFrames = frame.origin == .visuallyInterpolated
        var nextTransition: UInt64?

        if requiresContinuousFrames,
           let transitionEnd = presentationTransitionEndUptimeNanoseconds {
            nextTransition = earlierFutureTransition(
                nextTransition,
                transitionEnd,
                after: now
            )
        }

        if frame.acceptedPeakNormalized != nil,
           let peakUptime = presentationPeakUptimeNanoseconds,
           let peakExpiry = exclusiveDeadline(
               after: peakUptime,
               interval: animationPolicy.acceptedPeakHoldNanoseconds
           ) {
            nextTransition = earlierFutureTransition(
                nextTransition,
                peakExpiry,
                after: now
            )
        }

        if let acceptedUptime = frame.latestAcceptedUptimeNanoseconds,
           let freshnessExpiry = exclusiveDeadline(
               after: acceptedUptime,
               interval: freshnessPolicy.staleAfterNanoseconds
           ) {
            nextTransition = earlierFutureTransition(
                nextTransition,
                freshnessExpiry,
                after: now
            )
        }

        return PropulsionEnergyRailSourceReceiptDisplaySchedule(
            requiresContinuousFrames: requiresContinuousFrames,
            nextTransitionUptimeNanoseconds: nextTransition
        )
    }

    private func validatedReceipt(
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) -> Receipt? {
        guard watts.isFinite,
              watts >= 0,
              receiptSequenceNumber > 0,
              receivedAtUptimeNanoseconds > 0,
              continuityGeneration > 0 else {
            return nil
        }
        return Receipt(
            watts: watts == 0 ? 0 : watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration
        )
    }

    private mutating func accept(_ receipt: Receipt) -> Bool {
        let previous = latestAcceptedReceipt

        do {
            let sample = try PropulsionPowerSample.simulator(
                identity: session.identity,
                watts: receipt.watts,
                receiptSequenceNumber: receipt.receiptSequenceNumber,
                receivedAtUptimeNanoseconds: receipt.receivedAtUptimeNanoseconds,
                continuityGeneration: receipt.continuityGeneration
            )
            try session.accept(sample)
        } catch {
            return false
        }

        let sharesPresentationContinuity: Bool
        if let previous,
           previous.continuityGeneration == receipt.continuityGeneration,
           receipt.receivedAtUptimeNanoseconds >= previous.receivedAtUptimeNanoseconds {
            sharesPresentationContinuity = receipt.receivedAtUptimeNanoseconds
                - previous.receivedAtUptimeNanoseconds
                <= freshnessPolicy.staleAfterNanoseconds
        } else {
            sharesPresentationContinuity = false
        }

        updatePresentationScheduleAfterAcceptedSample(
            watts: receipt.watts,
            receivedAtUptimeNanoseconds: receipt.receivedAtUptimeNanoseconds,
            sharesContinuity: sharesPresentationContinuity
        )
        latestAcceptedReceipt = receipt
        return true
    }

    private mutating func failClosedUnavailable() {
        if let latestAcceptedReceipt {
            _ = session.markUnavailable(
                authority: .simulator,
                continuityGeneration: latestAcceptedReceipt.continuityGeneration
            )
        }
        sourceCurrentness = .unavailable
        resetPresentationSchedule()
    }

    private mutating func updatePresentationScheduleAfterAcceptedSample(
        watts: Double,
        receivedAtUptimeNanoseconds uptime: UInt64,
        sharesContinuity: Bool
    ) {
        if presentationPeakWatts == nil
            || !sharesContinuity
            || peakExpiredBeforeObservation(atUptimeNanoseconds: uptime) {
            presentationPeakWatts = watts
            presentationPeakUptimeNanoseconds = uptime
        } else if let presentationPeakWatts,
                  watts >= presentationPeakWatts {
            self.presentationPeakWatts = watts
            presentationPeakUptimeNanoseconds = uptime
        }

        let frame = session.frame(
            atUptimeNanoseconds: uptime,
            scale: scale
        )
        guard frame.origin == .visuallyInterpolated,
              let displayWatts = frame.displayWatts,
              let acceptedWatts = frame.latestAcceptedWatts,
              displayWatts.isFinite,
              acceptedWatts.isFinite,
              displayWatts != acceptedWatts else {
            presentationTransitionEndUptimeNanoseconds = nil
            return
        }

        let duration = acceptedWatts >= displayWatts
            ? animationPolicy.riseSettlingDurationNanoseconds
            : animationPolicy.fallSettlingDurationNanoseconds
        presentationTransitionEndUptimeNanoseconds = deadline(
            after: uptime,
            interval: duration
        )
    }

    private func peakExpiredBeforeObservation(atUptimeNanoseconds uptime: UInt64) -> Bool {
        guard let peakUptime = presentationPeakUptimeNanoseconds,
              uptime >= peakUptime else {
            return true
        }
        return uptime - peakUptime > animationPolicy.acceptedPeakHoldNanoseconds
    }

    private mutating func resetPresentationSchedule() {
        presentationTransitionEndUptimeNanoseconds = nil
        presentationPeakWatts = nil
        presentationPeakUptimeNanoseconds = nil
    }

    private func deadline(after start: UInt64, interval: UInt64) -> UInt64? {
        let (value, overflow) = start.addingReportingOverflow(interval)
        return overflow ? nil : value
    }

    private func exclusiveDeadline(after start: UInt64, interval: UInt64) -> UInt64? {
        guard let inclusive = deadline(after: start, interval: interval) else {
            return nil
        }
        let (exclusive, overflow) = inclusive.addingReportingOverflow(1)
        return overflow ? nil : exclusive
    }

    private func earlierFutureTransition(
        _ current: UInt64?,
        _ candidate: UInt64,
        after now: UInt64
    ) -> UInt64? {
        guard candidate > now else { return current }
        guard let current else { return candidate }
        return min(current, candidate)
    }
}
