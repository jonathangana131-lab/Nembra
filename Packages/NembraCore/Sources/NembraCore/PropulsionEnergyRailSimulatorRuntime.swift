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
/// The runtime supports two mutually exclusive chronology modes:
/// - the legacy value-change adapter used by isolated package fixtures; and
/// - exact source-owned receipt admission used by the real app Simulator bridge.
///
/// Once exact source-owned chronology is admitted, legacy observation calls fail
/// closed so presentation code cannot mix a second synthetic receipt namespace into
/// the accepted source sequence.
public struct PropulsionEnergyRailSimulatorRuntime: Sendable {
    /// Synthetic visual ceiling chosen only because `SimulatedScooterService`
    /// currently caps generated QA power at 620 W. This is not a rated motor,
    /// controller maximum, observed physical ceiling, or ES80 claim.
    public static let defaultPresentationCeilingWatts: Double = 650

    /// Synthetic currentness window for deterministic legacy Simulator UI sessions.
    /// This is not a claim about any physical BLE publication cadence.
    public static let defaultFreshnessNanoseconds: UInt64 = 30_000_000_000

    /// Exact source-owned app sessions do not infer currentness from an arbitrary
    /// package timeout. Their `.live/.retained/.unavailable` state comes from the
    /// accepted Simulator source owner. `UInt64.max` makes the package timeout
    /// unreachable in ordinary monotonic runtime and source currentness can only
    /// demote the sealed projection through `constrained(toSourceCurrentness:)`.
    public static let sourceOwnedFreshnessNanoseconds: UInt64 = .max

    private let vehicleID: String
    private let presentationCeilingWatts: Double
    private let animationPolicy: PropulsionGaugeAnimationPolicy
    private let freshnessPolicy: PropulsionGaugeFreshnessPolicy

    private var session: PropulsionGaugeSourceSession
    private var scale: PropulsionGaugeScale
    private var activeModeKey: String?

    // Legacy isolated-fixture chronology. This namespace is never used after an
    // exact source-owned receipt has been accepted.
    private var continuityGeneration: UInt64 = 1
    private var nextReceiptSequenceNumber: UInt64 = 1
    private var requiresNewGeneration = false

    private var lastAcceptedWatts: Double?
    private var lastAcceptedUptimeNanoseconds: UInt64?

    // Exact source-owned chronology markers. The canonical session remains the
    // chronology enforcer; these mirrors are used only for presentation continuity
    // and to prevent the legacy adapter from becoming a second receipt minter.
    private var sourceOwnedChronologyActive = false
    private var lastAcceptedSourceContinuityGeneration: UInt64?
    private var lastAcceptedSourceReceiptSequenceNumber: UInt64?

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

    /// Preferred runtime for app integration with `SimulatorPowerEvidenceProvider`.
    /// Source lifecycle owns currentness, so package freshness is intentionally not
    /// guessed from Simulator cadence.
    public static func sourceOwned(
        vehicleID: String = "nembra-simulator",
        presentationCeilingWatts: Double = PropulsionEnergyRailSimulatorRuntime.defaultPresentationCeilingWatts
    ) throws -> PropulsionEnergyRailSimulatorRuntime {
        try PropulsionEnergyRailSimulatorRuntime(
            vehicleID: vehicleID,
            presentationCeilingWatts: presentationCeilingWatts,
            freshnessNanoseconds: sourceOwnedFreshnessNanoseconds
        )
    }

    /// Legacy isolated-fixture adapter. The real app must use
    /// `observeSourceOwned(...)` so equal-watt genuine receipts retain their exact
    /// source chronology instead of being de-duplicated by semantic value.
    @discardableResult
    public mutating func observe(
        connected: Bool,
        watts: Double?,
        modeKey: String?,
        receivedAtUptimeNanoseconds: UInt64
    ) -> Bool {
        guard !sourceOwnedChronologyActive else { return false }

        guard connected,
              let watts,
              watts.isFinite,
              watts >= 0 else {
            retireCurrentGeneration()
            return false
        }

        let normalizedModeKey = normalizedMode(modeKey)
        if normalizedModeKey != activeModeKey {
            guard rebuildSession(modeKey: normalizedModeKey) else {
                retireCurrentGeneration()
                return false
            }
        } else if requiresNewGeneration {
            guard continuityGeneration < UInt64.max else {
                retireCurrentGeneration()
                return false
            }
            continuityGeneration &+= 1
            nextReceiptSequenceNumber = 1
            lastAcceptedWatts = nil
            lastAcceptedUptimeNanoseconds = nil
            resetPresentationSchedule()
            requiresNewGeneration = false
        }

        // A render tick or unrelated Simulator state publication must not become a
        // new accepted power observation when the legacy source's semantic watt
        // value did not change inside the same continuity generation.
        guard lastAcceptedWatts != watts else {
            return true
        }

        guard let admittedUptime = strictlyIncreasingUptime(
            receivedAtUptimeNanoseconds
        ) else {
            retireCurrentGeneration()
            return false
        }

        let sharesPresentationContinuity: Bool
        if let previousUptime = lastAcceptedUptimeNanoseconds {
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
            retireCurrentGeneration()
            return false
        }

        updatePresentationScheduleAfterAcceptedSample(
            watts: watts,
            receivedAtUptimeNanoseconds: admittedUptime,
            sharesContinuity: sharesPresentationContinuity
        )

        lastAcceptedWatts = watts == 0 ? 0 : watts
        lastAcceptedUptimeNanoseconds = admittedUptime
        if nextReceiptSequenceNumber < UInt64.max {
            nextReceiptSequenceNumber &+= 1
        }
        return true
    }

    /// Admits one immutable Simulator source receipt exactly as issued by the
    /// source owner. Receipt sequence, source uptime, and continuity generation are
    /// copied into the package-sealed accepted measurement; SwiftUI contributes none
    /// of them. Equal-watt newer receipts therefore remain distinct real source
    /// observations and refresh currentness without fabricating a value change.
    ///
    /// Stale/duplicate/malformed receipts fail closed without retiring the newest
    /// already-accepted measurement. Source lifecycle currentness is applied later
    /// as a one-way projection constraint.
    @discardableResult
    public mutating func observeSourceOwned(
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) -> Bool {
        guard watts.isFinite,
              watts >= 0,
              receiptSequenceNumber > 0,
              continuityGeneration > 0,
              activeModeKey == nil else {
            return false
        }

        let sharesPresentationContinuity: Bool
        if let previousUptime = lastAcceptedUptimeNanoseconds,
           let previousGeneration = lastAcceptedSourceContinuityGeneration,
           continuityGeneration == previousGeneration,
           receivedAtUptimeNanoseconds >= previousUptime {
            let gap = receivedAtUptimeNanoseconds - previousUptime
            sharesPresentationContinuity = gap <= freshnessPolicy.staleAfterNanoseconds
        } else {
            sharesPresentationContinuity = false
        }

        do {
            let sample = try PropulsionPowerSample.simulator(
                identity: session.identity,
                watts: watts,
                receiptSequenceNumber: receiptSequenceNumber,
                receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
                continuityGeneration: continuityGeneration
            )
            try session.accept(sample)
        } catch {
            return false
        }

        sourceOwnedChronologyActive = true
        lastAcceptedSourceContinuityGeneration = continuityGeneration
        lastAcceptedSourceReceiptSequenceNumber = receiptSequenceNumber

        updatePresentationScheduleAfterAcceptedSample(
            watts: watts,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            sharesContinuity: sharesPresentationContinuity
        )

        lastAcceptedWatts = watts == 0 ? 0 : watts
        lastAcceptedUptimeNanoseconds = receivedAtUptimeNanoseconds
        requiresNewGeneration = false
        return true
    }

    /// Canonical sealed app projection at the display clock.
    /// Intermediate values remain render-only inside the returned projection.
    public func projection(
        atUptimeNanoseconds now: UInt64
    ) -> PropulsionEnergyRailAppProjection {
        session.energyRailAppProjection(
            atUptimeNanoseconds: now,
            scale: scale
        )
    }

    /// Source-owned app projection. Source currentness can only constrain the
    /// package projection; it cannot mint or upgrade accepted measurement truth.
    public func projection(
        atUptimeNanoseconds now: UInt64,
        sourceCurrentness: PropulsionEnergyRailCurrentness
    ) -> PropulsionEnergyRailAppProjection {
        projection(atUptimeNanoseconds: now)
            .constrained(toSourceCurrentness: sourceCurrentness)
    }

    /// Presentation-only scheduler for the app's localized display clock.
    ///
    /// The package projection remains the visual source of truth. This method only
    /// reports when that projection can change with no new source observation:
    /// - continuous frames while the canonical frame is actually interpolating;
    /// - one wake at interpolation settlement;
    /// - one wake at accepted-peak marker expiry;
    /// - one wake when legacy timeout currentness becomes retained.
    ///
    /// Calling this method never mutates the runtime or accepted chronology.
    public func displaySchedule(
        atUptimeNanoseconds now: UInt64
    ) -> PropulsionEnergyRailDisplaySchedule {
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

    /// Source-owned currentness disables all render scheduling once evidence is
    /// retained or unavailable. A live source may still request interpolation or
    /// accepted-peak wake-ups, but source-owned sessions use an unreachable package
    /// freshness timeout so no guessed cadence transition is scheduled.
    public func displaySchedule(
        atUptimeNanoseconds now: UInt64,
        sourceCurrentness: PropulsionEnergyRailCurrentness
    ) -> PropulsionEnergyRailDisplaySchedule {
        guard sourceCurrentness == .live else { return .inactive }
        return displaySchedule(atUptimeNanoseconds: now)
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

    private mutating func retireCurrentGeneration() {
        _ = session.markUnavailable(
            authority: .simulator,
            continuityGeneration: continuityGeneration
        )
        requiresNewGeneration = true
        lastAcceptedWatts = nil
        lastAcceptedUptimeNanoseconds = nil
        resetPresentationSchedule()
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
            lastAcceptedSourceContinuityGeneration = nil
            lastAcceptedSourceReceiptSequenceNumber = nil
            sourceOwnedChronologyActive = false
            resetPresentationSchedule()
            requiresNewGeneration = false
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