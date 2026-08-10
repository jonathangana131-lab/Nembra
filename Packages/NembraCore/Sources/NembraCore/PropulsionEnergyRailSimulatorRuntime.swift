import Foundation

/// Source-owned currentness presented to the Simulator Energy Rail adapter.
///
/// This enum contains no numeric evidence. The accepted watts/receipt/generation
/// tuple is supplied separately from the source-owned observation and remains
/// Simulator authority only.
public enum PropulsionEnergyRailSimulatorSourceCurrentness: Equatable, Sendable {
    case live
    case retained
    case unavailable
}

/// Simulator-only source/runtime owner for Energy Rail product QA.
///
/// This type deliberately cannot mint verified-vehicle propulsion authority. Every
/// accepted sample uses `PropulsionPowerSample.simulator`, every presentation scale
/// uses `.simulator`, and the runtime is named explicitly so app integration cannot
/// mistake its values for ES80 hardware evidence.
///
/// Source-owned integration should call `observeSource(...)` with the exact receipt,
/// uptime, and continuity generation from the Simulator power provider. The legacy
/// `observe(...)` entry point remains for isolated package fixtures that do not own a
/// source receipt; it continues to de-duplicate equal-watt render polling.
public struct PropulsionEnergyRailSimulatorRuntime: Sendable {
    /// Synthetic visual ceiling chosen only because `SimulatedScooterService`
    /// currently caps generated QA power at 620 W. This is not a rated motor,
    /// controller maximum, observed physical ceiling, or ES80 claim.
    public static let defaultPresentationCeilingWatts: Double = 650

    /// Synthetic currentness window for deterministic Simulator UI sessions.
    /// This is not a claim about any physical BLE publication cadence. Explicit
    /// source retention/unavailability overrides this window immediately.
    public static let defaultFreshnessNanoseconds: UInt64 = 30_000_000_000

    private struct SourceReceipt: Equatable, Sendable {
        let watts: Double
        let receiptSequenceNumber: UInt64
        let receivedAtUptimeNanoseconds: UInt64
        let continuityGeneration: UInt64
    }

    private let vehicleID: String
    private let presentationCeilingWatts: Double
    private let animationPolicy: PropulsionGaugeAnimationPolicy
    private let freshnessPolicy: PropulsionGaugeFreshnessPolicy

    private var session: PropulsionGaugeSourceSession
    private var scale: PropulsionGaugeScale
    private var activeModeKey: String?

    // Legacy synthetic-fixture chronology. Source-owned app integration does not use
    // these counters and therefore never rewrites source receipt identity.
    private var continuityGeneration: UInt64 = 1
    private var nextReceiptSequenceNumber: UInt64 = 1
    private var lastAcceptedWatts: Double?
    private var lastAcceptedUptimeNanoseconds: UInt64?
    private var lastAcceptedSourceObservationRevision: UInt64?
    private var requiresNewGeneration = false

    // Source-owned app chronology/currentness. `nil` means the legacy fixture path
    // owns presentation. Once source mode is entered, projection currentness is
    // constrained by this state until a legacy call explicitly takes ownership back.
    private var latestSourceReceipt: SourceReceipt?
    private var sourceCurrentness: PropulsionEnergyRailSimulatorSourceCurrentness?

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

    /// Admits exact source-owned Simulator propulsion evidence.
    ///
    /// `live` and `retained` require the exact source observation tuple. A retained
    /// transition may reuse the exact newest accepted receipt and changes currentness
    /// without inventing another measurement. The same retained receipt can never be
    /// relabeled live later; a live recovery requires a genuinely newer source receipt
    /// (and, after explicit unavailability, the source session's generation fence also
    /// requires a non-retired continuity generation).
    ///
    /// Stale/contradictory callbacks fail without erasing newer accepted evidence.
    @discardableResult
    public mutating func observeSource(
        currentness: PropulsionEnergyRailSimulatorSourceCurrentness,
        watts: Double? = nil,
        receiptSequenceNumber: UInt64? = nil,
        receivedAtUptimeNanoseconds: UInt64? = nil,
        continuityGeneration: UInt64? = nil
    ) -> Bool {
        sourceCurrentness = sourceCurrentness ?? .unavailable

        guard currentness != .unavailable else {
            if let latestSourceReceipt {
                _ = session.markUnavailable(
                    authority: .simulator,
                    continuityGeneration: latestSourceReceipt.continuityGeneration
                )
            }
            sourceCurrentness = .unavailable
            return false
        }

        guard let watts,
              watts.isFinite,
              watts >= 0,
              let receiptSequenceNumber,
              receiptSequenceNumber > 0,
              let receivedAtUptimeNanoseconds,
              let continuityGeneration,
              continuityGeneration > 0 else {
            // Malformed source input cannot keep an older measurement visually live.
            if let latestSourceReceipt {
                _ = session.markUnavailable(
                    authority: .simulator,
                    continuityGeneration: latestSourceReceipt.continuityGeneration
                )
            }
            sourceCurrentness = .unavailable
            return false
        }

        let candidate = SourceReceipt(
            watts: watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration
        )

        if let latestSourceReceipt {
            if candidate.continuityGeneration < latestSourceReceipt.continuityGeneration {
                return false
            }

            if candidate.continuityGeneration == latestSourceReceipt.continuityGeneration {
                if candidate.receiptSequenceNumber < latestSourceReceipt.receiptSequenceNumber {
                    return false
                }

                if candidate.receiptSequenceNumber == latestSourceReceipt.receiptSequenceNumber {
                    guard candidate == latestSourceReceipt else {
                        return false
                    }

                    // Currentness can only move live -> retained for one exact receipt.
                    // Re-promoting retained -> live would let a caller relabel cached
                    // source evidence without a new observation.
                    if sourceCurrentness == .retained, currentness == .live {
                        return false
                    }
                    sourceCurrentness = currentness
                    return true
                }

                guard candidate.receivedAtUptimeNanoseconds >= latestSourceReceipt.receivedAtUptimeNanoseconds else {
                    return false
                }
            }
        }

        do {
            let sample = try PropulsionPowerSample.simulator(
                identity: session.identity,
                watts: candidate.watts,
                receiptSequenceNumber: candidate.receiptSequenceNumber,
                receivedAtUptimeNanoseconds: candidate.receivedAtUptimeNanoseconds,
                continuityGeneration: candidate.continuityGeneration
            )
            try session.accept(sample)
        } catch {
            return false
        }

        latestSourceReceipt = candidate
        sourceCurrentness = currentness
        return true
    }

    /// Legacy Simulator-fixture admission path.
    ///
    /// Call this when the synthetic fixture itself does not expose source receipt
    /// chronology. `sourceObservationRevision` distinguishes genuine fixture changes
    /// from repeated render polling while local counters remain explicitly Simulator
    /// only. App integration should prefer `observeSource(...)`.
    @discardableResult
    public mutating func observe(
        connected: Bool,
        watts: Double?,
        modeKey: String?,
        sourceObservationRevision: UInt64? = nil,
        receivedAtUptimeNanoseconds: UInt64
    ) -> Bool {
        // An explicit legacy call takes ownership back from source mode. This is used
        // only by isolated fixtures/tests and prevents a stale source-currentness
        // override from affecting their expected projection semantics.
        sourceCurrentness = nil
        latestSourceReceipt = nil

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
                return false
            }

            if sourceObservationRevision == lastAcceptedSourceObservationRevision {
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
        let base = session.energyRailAppProjection(
            atUptimeNanoseconds: now,
            scale: scale
        )

        switch sourceCurrentness {
        case .retained:
            return base.retainedBySource()
        case .unavailable:
            // `observeSource(.unavailable)` already retires the package session.
            // Returning the canonical base preserves fail-closed package behavior.
            return base
        case .live, .none:
            return base
        }
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
