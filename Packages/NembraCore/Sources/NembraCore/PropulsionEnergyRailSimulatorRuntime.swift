import Foundation

/// Display-clock scheduling metadata for Simulator-only Energy Rail product QA.
///
/// This is presentation state, not telemetry. It may tell SwiftUI when render-only
/// interpolation needs continuous frames or when a future presentation transition
/// needs one wake-up. It never creates an accepted propulsion observation, refreshes
/// measurement currentness, changes receipt chronology, or carries physical authority.
public struct PropulsionEnergyRailDisplaySchedule: Equatable, Sendable {
    /// True only while the canonical package model is actually between accepted
    /// display targets. Settled live geometry does not require a 60 Hz clock.
    public let requiresContinuousFrames: Bool

    /// Earliest monotonic uptime at which presentation can change without a new
    /// source observation: interpolation settlement, accepted-peak expiry, or
    /// freshness demotion. `nil` means no timer-driven presentation transition remains.
    public let nextTransitionUptimeNanoseconds: UInt64?

    fileprivate init(
        requiresContinuousFrames: Bool,
        nextTransitionUptimeNanoseconds: UInt64?
    ) {
        self.requiresContinuousFrames = requiresContinuousFrames
        self.nextTransitionUptimeNanoseconds = nextTransitionUptimeNanoseconds
    }

    fileprivate static let inactive = Self(
        requiresContinuousFrames: false,
        nextTransitionUptimeNanoseconds: nil
    )
}

/// Simulator-only source/runtime owner for Energy Rail product QA.
///
/// This type deliberately cannot mint verified-vehicle propulsion authority. Every
/// accepted sample uses `PropulsionPowerSample.simulator`, every presentation scale
/// uses `.simulator`, and the runtime is named explicitly so app integration cannot
/// mistake its values for ES80 hardware evidence.
///
/// The runtime owns synthetic chronology at the **measurement clock**. Repeated calls
/// carrying the same connected watt value do not mint new accepted receipts merely
/// because a renderer asked for another frame. A caller that has a real source-owned
/// Simulator observation may additionally provide its monotonic
/// `sourceObservationRevision`; a strictly newer revision is allowed to refresh an
/// unchanged watt value because that is new source evidence rather than render polling.
/// Display interpolation and scheduling remain presentation-only inside
/// `PropulsionGaugeSourceSession` / this adapter.
public struct PropulsionEnergyRailSimulatorRuntime: Sendable {
    /// Synthetic visual ceiling chosen only because `SimulatedScooterService`
    /// currently caps generated QA power at 620 W. This is not a rated motor,
    /// controller maximum, observed physical ceiling, or ES80 claim.
    public static let defaultPresentationCeilingWatts: Double = 650

    /// Synthetic currentness window for deterministic Simulator UI sessions.
    /// This is not a claim about any physical BLE publication cadence.
    public static let defaultFreshnessNanoseconds: UInt64 = 30_000_000_000

    private let vehicleID: String
    private let presentationCeilingWatts: Double
    private let animationPolicy: PropulsionGaugeAnimationPolicy
    private let freshnessPolicy: PropulsionGaugeFreshnessPolicy

    private var session: PropulsionGaugeSourceSession
    private var scale: PropulsionGaugeScale
    private var activeModeKey: String?
    private var continuityGeneration: UInt64 = 1
    private var nextReceiptSequenceNumber: UInt64 = 1
    private var lastAcceptedWatts: Double?
    private var lastAcceptedUptimeNanoseconds: UInt64?

    /// Opaque source-owned chronology. Once source revisions are used, legacy
    /// no-revision calls are no longer allowed to regain positive authority. The
    /// floor deliberately survives local lifecycle retirement so a delayed pre-gap
    /// source receipt cannot revive cached power after reconnect.
    private var lastAcceptedSourceObservationRevision: UInt64?
    private var lastAcceptedSourceObservationUptimeNanoseconds: UInt64?

    private var requiresNewGeneration = false

    /// Source-owned RETAINED state is an authority-lowering override of an exact
    /// sealed package projection. The underlying session is retired at the same
    /// boundary so a later LIVE receipt always starts a new presentation generation
    /// and cannot interpolate across a disconnect/data gap.
    private var retainedProjection: PropulsionEnergyRailAppProjection?
    private var retainedSourceObservationRevision: UInt64?

    // These mirrors schedule presentation-only wake-ups. They are deliberately
    // downstream of successfully accepted package measurements and never feed
    // back into `session`, accepted samples, telemetry, history, or persistence.
    private var presentationTransitionEndUptimeNanoseconds: UInt64?
    private var presentationPeakWatts: Double?
    private var presentationPeakUptimeNanoseconds: UInt64?

    public var identity: PropulsionGaugeIdentity { session.identity }

    public init(
        vehicleID: String = "nembra-simulator",
        presentationCeilingWatts: Double = PropulsionEnergyRailSimulatorRuntime.defaultPresentationCeilingWatts,
        freshnessNanoseconds: UInt64 = PropulsionEnergyRailSimulatorRuntime.defaultFreshnessNanoseconds
    ) throws {
        let animationPolicy = try PropulsionGaugeAnimationPolicy(
            riseSettlingDurationNanoseconds: 220_000_000,
            fallSettlingDurationNanoseconds: 150_000_000,
            acceptedPeakHoldNanoseconds: 2_000_000_000
        )
        let freshnessPolicy = try PropulsionGaugeFreshnessPolicy(
            staleAfterNanoseconds: freshnessNanoseconds
        )
        let identity = try PropulsionGaugeIdentity(vehicleID: vehicleID)
        let scale = try PropulsionGaugeScale.simulator(
            identity: identity,
            ceilingWatts: presentationCeilingWatts
        )

        self.vehicleID = vehicleID
        self.presentationCeilingWatts = presentationCeilingWatts
        self.animationPolicy = animationPolicy
        self.freshnessPolicy = freshnessPolicy
        self.session = PropulsionGaugeSourceSession(
            identity: identity,
            animationPolicy: animationPolicy,
            freshnessPolicy: freshnessPolicy
        )
        self.scale = scale
        self.activeModeKey = nil
    }

    /// Admits one Simulator source state change.
    ///
    /// Legacy isolated callers may omit `sourceObservationRevision`; unchanged watts
    /// then remain de-duplicated so render polling cannot become telemetry. Product
    /// integration with `SimulatorPowerEvidenceProvider` must pass the provider's
    /// immutable receipt sequence plus its original monotonic receipt uptime.
    ///
    /// Once a source-owned revision has been accepted, revision-less calls can never
    /// regain positive authority. A strictly newer source revision may refresh equal
    /// watts. An equal revision may only replay the exact same watts/mode/uptime tuple.
    /// Lower revisions are stale and ignored without erasing newer evidence.
    @discardableResult
    public mutating func observe(
        connected: Bool,
        watts: Double?,
        modeKey: String?,
        sourceObservationRevision: UInt64? = nil,
        receivedAtUptimeNanoseconds: UInt64
    ) -> Bool {
        guard connected,
              let watts,
              watts.isFinite,
              watts >= 0 else {
            retireCurrentGenerationAsUnavailable()
            return false
        }

        let normalizedModeKey = normalizedMode(modeKey)

        if lastAcceptedSourceObservationRevision != nil,
           sourceObservationRevision == nil {
            // Once the stronger source clock exists, a legacy call cannot bypass it.
            return false
        }

        if let sourceObservationRevision {
            guard sourceObservationRevision > 0 else {
                retireCurrentGenerationAsUnavailable()
                return false
            }

            if let lastRevision = lastAcceptedSourceObservationRevision {
                if sourceObservationRevision < lastRevision {
                    // Delayed old source evidence is non-authoritative, but it must
                    // not erase the newer accepted/retained state already held.
                    return false
                }

                if sourceObservationRevision == lastRevision {
                    let sameUptime = lastAcceptedSourceObservationUptimeNanoseconds
                        == receivedAtUptimeNanoseconds
                    let sameTuple = normalizedModeKey == activeModeKey
                        && lastAcceptedWatts == watts
                        && sameUptime

                    if sameTuple {
                        // Exact source replay is idempotent. If the receipt has
                        // already been demoted to RETAINED, replay does not promote it.
                        return true
                    }

                    // One immutable source revision cannot name two semantic tuples.
                    retireCurrentGenerationAsUnavailable()
                    return false
                }

                if let lastSourceUptime = lastAcceptedSourceObservationUptimeNanoseconds,
                   receivedAtUptimeNanoseconds <= lastSourceUptime {
                    // A newer source sequence with non-increasing source receipt time
                    // contradicts the provider contract. Fail closed rather than
                    // re-dating the measurement locally.
                    retireCurrentGenerationAsUnavailable()
                    return false
                }
            } else if let localUptime = lastAcceptedUptimeNanoseconds,
                      receivedAtUptimeNanoseconds <= localUptime {
                // Transitioning from the legacy isolated path to source-owned
                // chronology cannot move the accepted measurement clock backwards.
                retireCurrentGenerationAsUnavailable()
                return false
            }
        }

        if normalizedModeKey != activeModeKey {
            guard rebuildSession(modeKey: normalizedModeKey) else {
                retireCurrentGenerationAsUnavailable()
                return false
            }
        } else if requiresNewGeneration {
            guard continuityGeneration < UInt64.max else {
                retireCurrentGenerationAsUnavailable()
                return false
            }
            continuityGeneration &+= 1
            nextReceiptSequenceNumber = 1
            lastAcceptedWatts = nil
            lastAcceptedUptimeNanoseconds = nil
            retainedProjection = nil
            retainedSourceObservationRevision = nil
            resetPresentationSchedule()
            requiresNewGeneration = false
        }

        // Without a source revision, preserve the original safe polling behavior:
        // an unchanged value is not a new accepted measurement. A strictly newer
        // source revision, however, is genuine source evidence even when watts match.
        if sourceObservationRevision == nil,
           lastAcceptedWatts == watts {
            return true
        }

        let admittedUptime: UInt64
        if sourceObservationRevision != nil {
            // The immutable provider receipt already owns this clock. Never replace
            // it with render time, callback time, speed time, or aggregate lastUpdated.
            admittedUptime = receivedAtUptimeNanoseconds
        } else {
            guard let increasing = strictlyIncreasingUptime(
                receivedAtUptimeNanoseconds
            ) else {
                retireCurrentGenerationAsUnavailable()
                return false
            }
            admittedUptime = increasing
        }

        let sharesPresentationContinuity: Bool
        if let previousUptime = lastAcceptedUptimeNanoseconds,
           admittedUptime > previousUptime {
            let gap = admittedUptime - previousUptime
            sharesPresentationContinuity = gap <= freshnessPolicy.staleAfterNanoseconds
        } else {
            sharesPresentationContinuity = false
        }

        do {
            let sample = try PropulsionPowerSample.simulator(
                identity: session.identity,
                watts: watts,
                receiptSequenceNumber: nextReceiptSequenceNumber,
                receivedAtUptimeNanoseconds: admittedUptime,
                continuityGeneration: continuityGeneration
            )
            try session.accept(sample)
        } catch {
            retireCurrentGenerationAsUnavailable()
            return false
        }

        retainedProjection = nil
        retainedSourceObservationRevision = nil
        updatePresentationScheduleAfterAcceptedSample(
            watts: watts,
            receivedAtUptimeNanoseconds: admittedUptime,
            sharesContinuity: sharesPresentationContinuity
        )

        lastAcceptedWatts = watts == 0 ? 0 : watts
        lastAcceptedUptimeNanoseconds = admittedUptime
        if let sourceObservationRevision {
            lastAcceptedSourceObservationRevision = sourceObservationRevision
            lastAcceptedSourceObservationUptimeNanoseconds = admittedUptime
        }
        if nextReceiptSequenceNumber < UInt64.max {
            nextReceiptSequenceNumber &+= 1
        }
        return true
    }

    /// Immediately lowers the exact newest source-owned accepted receipt to
    /// RETAINED. This is the package bridge for an explicit source currentness
    /// transition such as Simulator disconnect/reconnect.
    ///
    /// The source revision must exactly match the newest accepted source receipt.
    /// This method never creates a new receipt, never changes accepted watts or
    /// accepted revision, and never supplies a local timestamp. It removes live
    /// rail/peak/target geometry and motion, retires the underlying local generation,
    /// and leaves the source revision floor intact so a pre-gap receipt cannot revive.
    @discardableResult
    public mutating func retain(
        sourceObservationRevision: UInt64
    ) -> Bool {
        guard sourceObservationRevision > 0,
              sourceObservationRevision == lastAcceptedSourceObservationRevision,
              let lastAcceptedWatts,
              let lastAcceptedUptimeNanoseconds else {
            return false
        }

        if let retainedProjection,
           retainedSourceObservationRevision == sourceObservationRevision,
           retainedProjection.acceptedWatts == lastAcceptedWatts {
            return true
        }

        let accepted = session.energyRailAppProjection(
            atUptimeNanoseconds: lastAcceptedUptimeNanoseconds,
            scale: scale
        )
        guard accepted.currentness != .unavailable,
              accepted.acceptedWatts == lastAcceptedWatts,
              accepted.acceptedMeasurement?.authority == .simulator,
              accepted.acceptedMeasurement?.continuityGeneration == continuityGeneration,
              accepted.acceptedMeasurement?.receivedAtUptimeNanoseconds
                == lastAcceptedUptimeNanoseconds else {
            return false
        }

        let retained = accepted.retainedWithoutNewMeasurement()
        guard retained.currentness == .retained,
              retained.acceptedMeasurement == accepted.acceptedMeasurement,
              retained.accessibilityPresentation.acceptedRevision
                == accepted.accessibilityPresentation.acceptedRevision else {
            return false
        }

        _ = session.markUnavailable(
            authority: .simulator,
            continuityGeneration: continuityGeneration
        )
        retainedProjection = retained
        retainedSourceObservationRevision = sourceObservationRevision
        requiresNewGeneration = true
        resetPresentationSchedule()
        return true
    }

    /// Canonical sealed app projection at the display clock.
    /// Intermediate values remain render-only inside the returned projection.
    public func projection(
        atUptimeNanoseconds now: UInt64
    ) -> PropulsionEnergyRailAppProjection {
        if let retainedProjection {
            return retainedProjection
        }
        return session.energyRailAppProjection(
            atUptimeNanoseconds: now,
            scale: scale
        )
    }

    /// Presentation-only scheduler for the app's localized display clock.
    ///
    /// The package projection remains the visual source of truth. This method only
    /// reports when that projection can change with no new source observation:
    /// - continuous frames while the canonical frame is actually interpolating;
    /// - one wake at interpolation settlement;
    /// - one wake at accepted-peak marker expiry;
    /// - one wake when live currentness becomes retained.
    ///
    /// Calling this method never mutates the runtime or accepted chronology.
    public func displaySchedule(
        atUptimeNanoseconds now: UInt64
    ) -> PropulsionEnergyRailDisplaySchedule {
        if retainedProjection != nil {
            return .inactive
        }

        let frame = session.frame(
            atUptimeNanoseconds: now,
            scale: scale
        )

        guard frame.availability == .live else {
            return .inactive
        }

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

        return PropulsionEnergyRailDisplaySchedule(
            requiresContinuousFrames: requiresContinuousFrames,
            nextTransitionUptimeNanoseconds: nextTransition
        )
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

    private mutating func retireCurrentGenerationAsUnavailable() {
        _ = session.markUnavailable(
            authority: .simulator,
            continuityGeneration: continuityGeneration
        )
        requiresNewGeneration = true
        lastAcceptedWatts = nil
        lastAcceptedUptimeNanoseconds = nil
        retainedProjection = nil
        retainedSourceObservationRevision = nil
        resetPresentationSchedule()
        // Deliberately preserve source revision + source uptime floors. A callback
        // from before this lifecycle boundary must remain stale after it.
    }

    private mutating func rebuildSession(modeKey: String?) -> Bool {
        do {
            let identity = try PropulsionGaugeIdentity(
                vehicleID: vehicleID,
                modeKey: modeKey
            )
            let scale = try PropulsionGaugeScale.simulator(
                identity: identity,
                ceilingWatts: presentationCeilingWatts
            )

            session = PropulsionGaugeSourceSession(
                identity: identity,
                animationPolicy: animationPolicy,
                freshnessPolicy: freshnessPolicy
            )
            self.scale = scale
            activeModeKey = modeKey
            continuityGeneration = 1
            nextReceiptSequenceNumber = 1
            lastAcceptedWatts = nil
            lastAcceptedUptimeNanoseconds = nil
            retainedProjection = nil
            retainedSourceObservationRevision = nil
            resetPresentationSchedule()
            requiresNewGeneration = false
            // Keep cross-mode source chronology floors. A mode rebinding changes
            // presentation identity; it does not erase caller source chronology.
            return true
        } catch {
            return false
        }
    }

    private mutating func resetPresentationSchedule() {
        presentationTransitionEndUptimeNanoseconds = nil
        presentationPeakWatts = nil
        presentationPeakUptimeNanoseconds = nil
    }

    private func normalizedMode(_ modeKey: String?) -> String? {
        guard let modeKey else { return nil }
        let trimmed = modeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func strictlyIncreasingUptime(_ proposed: UInt64) -> UInt64? {
        guard let previous = lastAcceptedUptimeNanoseconds else {
            return proposed
        }
        guard proposed > previous else { return nil }
        return proposed
    }

    private func deadline(after start: UInt64, interval: UInt64) -> UInt64? {
        let (value, overflow) = start.addingReportingOverflow(interval)
        return overflow ? nil : value
    }

    /// Currentness/peak transitions are defined by `age > interval`, so wake one
    /// nanosecond after the inclusive boundary. If arithmetic cannot represent a
    /// future deadline, there is no reachable UInt64 uptime at which to schedule it.
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
