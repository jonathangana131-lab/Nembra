import Foundation

/// Simulator-only source/runtime owner for Energy Rail product QA.
///
/// This type deliberately cannot mint verified-vehicle propulsion authority. Every
/// accepted sample uses `PropulsionPowerSample.simulator`, every presentation scale
/// uses `.simulator`, and the runtime is named explicitly so app integration cannot
/// mistake its values for ES80 hardware evidence.
///
/// The runtime owns synthetic chronology at the **measurement clock**. Repeated calls
/// carrying the same connected watt value do not mint new accepted receipts merely
/// because a 60 Hz renderer asked for another frame. A caller that has a real
/// source-owned Simulator observation may additionally provide its monotonic
/// `sourceObservationRevision`; a strictly newer revision is allowed to refresh an
/// unchanged watt value because that is new source evidence rather than render polling.
/// Display interpolation remains inside `PropulsionGaugeSourceSession` /
/// `PropulsionGaugeDisplayModel`.
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
    /// Opaque caller-owned source revision used only to distinguish a genuine
    /// synthetic observation from repeated presentation polling. It intentionally
    /// survives local lifecycle retirement so a delayed pre-gap revision cannot
    /// revive cached power after reconnect.
    private var lastAcceptedSourceObservationRevision: UInt64?
    private var requiresNewGeneration = false

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

    /// Admits one source-owned Simulator state change.
    ///
    /// Call this when the synthetic source changes, not on every render frame.
    /// `connected == false`, missing/invalid power, or a contradictory reuse of one
    /// source observation revision makes the active generation unavailable without
    /// manufacturing a zero-watt sample. A later valid observation starts a strictly
    /// newer synthetic generation after lifecycle retirement.
    ///
    /// `sourceObservationRevision` is optional for compatibility with older isolated
    /// callers. When supplied it must be a source-owned monotonic observation identity,
    /// never a display-clock counter. A newer revision may carry the same watts and
    /// still refresh accepted currentness; an equal revision may only replay the exact
    /// same watts + mode tuple. A lower revision is stale and ignored without hiding
    /// newer accepted evidence.
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
            retireCurrentGeneration()
            return false
        }

        let normalizedModeKey = normalizedMode(modeKey)

        if let sourceObservationRevision,
           let lastAcceptedSourceObservationRevision {
            if sourceObservationRevision < lastAcceptedSourceObservationRevision {
                // Delayed old source evidence is non-authoritative for the current
                // presentation, but it must not erase a newer accepted observation.
                return false
            }

            if sourceObservationRevision == lastAcceptedSourceObservationRevision {
                // One source observation has exactly one semantic tuple. A replay of
                // that tuple is harmless; any changed watts/mode under the same
                // revision is a caller/source contradiction and fails closed.
                if normalizedModeKey == activeModeKey,
                   lastAcceptedWatts == watts,
                   !requiresNewGeneration {
                    return true
                }

                retireCurrentGeneration()
                return false
            }
        }

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
            requiresNewGeneration = false
        }

        // Without a source revision, preserve the original safe polling behavior:
        // an unchanged value is not a new accepted measurement. With a strictly
        // newer source revision, equal watts are real new synthetic evidence and
        // must refresh accepted currentness/assistive semantic chronology.
        if sourceObservationRevision == nil,
           lastAcceptedWatts == watts {
            return true
        }

        guard let admittedUptime = strictlyIncreasingUptime(
            receivedAtUptimeNanoseconds
        ) else {
            retireCurrentGeneration()
            return false
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

        lastAcceptedWatts = watts == 0 ? 0 : watts
        lastAcceptedUptimeNanoseconds = admittedUptime
        if let sourceObservationRevision {
            lastAcceptedSourceObservationRevision = sourceObservationRevision
        }
        if nextReceiptSequenceNumber < UInt64.max {
            nextReceiptSequenceNumber &+= 1
        }
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

    private mutating func retireCurrentGeneration() {
        _ = session.markUnavailable(
            authority: .simulator,
            continuityGeneration: continuityGeneration
        )
        requiresNewGeneration = true
        lastAcceptedWatts = nil
        lastAcceptedUptimeNanoseconds = nil
        // Deliberately preserve `lastAcceptedSourceObservationRevision`. A source
        // callback from before this lifecycle boundary must remain stale after it.
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
            requiresNewGeneration = false
            // Keep the cross-mode source-revision floor. A mode rebinding changes
            // presentation identity; it does not erase caller source chronology.
            return true
        } catch {
            return false
        }
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
}
