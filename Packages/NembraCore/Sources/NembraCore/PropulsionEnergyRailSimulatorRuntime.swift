import Foundation

/// Simulator-only source/runtime owner for Energy Rail product QA.
///
/// This runtime never derives measurement authority from aggregate vehicle state,
/// SwiftUI lifecycle, a display clock, or a speed receipt. Every live/retained value
/// must carry the exact source-owned Simulator power receipt tuple that crossed the
/// app-session custody boundary. Render interpolation remains package-owned and can
/// never mint or refresh that tuple.
public struct PropulsionEnergyRailSimulatorRuntime: Sendable {
    /// Synthetic visual ceiling chosen only because `SimulatedScooterService`
    /// currently caps generated QA power at 620 W. This is not a rated motor,
    /// controller maximum, observed physical ceiling, or ES80 claim.
    public static let defaultPresentationCeilingWatts: Double = 650

    /// Synthetic currentness window for deterministic Simulator UI sessions.
    /// This is not a claim about any physical BLE publication cadence.
    public static let defaultFreshnessNanoseconds: UInt64 = 30_000_000_000

    private struct SourceObservation: Equatable, Sendable {
        let watts: Double
        let receiptSequenceNumber: UInt64
        let receivedAtUptimeNanoseconds: UInt64
        let continuityGeneration: UInt64
    }

    private enum SourceDisposition: Equatable, Sendable {
        case unavailable
        case retained(SourceObservation)
        case live(SourceObservation)
    }

    private let animationPolicy: PropulsionGaugeAnimationPolicy
    private let freshnessPolicy: PropulsionGaugeFreshnessPolicy
    private var session: PropulsionGaugeSourceSession
    private var scale: PropulsionGaugeScale
    private var disposition: SourceDisposition = .unavailable
    private var newestAcceptedSourceObservation: SourceObservation?

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

        self.animationPolicy = animationPolicy
        self.freshnessPolicy = freshnessPolicy
        self.session = PropulsionGaugeSourceSession(
            identity: identity,
            animationPolicy: animationPolicy,
            freshnessPolicy: freshnessPolicy
        )
        self.scale = scale
    }

    /// Admits one source-owned LIVE Simulator power observation.
    ///
    /// There is intentionally no compatibility overload without a receipt/generation.
    /// A view callback holding cached watts therefore has no API capable of opening a
    /// live Energy Rail generation. Equal watts are refreshed only when the source
    /// supplies a strictly newer receipt (or a newer continuity generation).
    @discardableResult
    public mutating func acceptLiveSource(
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) -> Bool {
        guard let incoming = validatedSourceObservation(
            watts: watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration
        ) else {
            markUnavailable()
            return false
        }

        switch compare(incoming, to: newestAcceptedSourceObservation) {
        case .stale:
            // A delayed older source receipt cannot hide or replace newer accepted
            // presentation. Ignore it without mutating current state.
            return false

        case .identical:
            // Idempotent replay is harmless only while this exact source receipt is
            // already live. A receipt that was retained/unavailable cannot be
            // re-labelled live without a newer source observation.
            if case .live(incoming) = disposition {
                return true
            }
            return false

        case .contradictory:
            // One source receipt identity cannot describe two semantic tuples.
            markUnavailable()
            return false

        case .newer:
            break
        }

        do {
            let sample = try PropulsionPowerSample.simulator(
                identity: session.identity,
                watts: incoming.watts,
                receiptSequenceNumber: incoming.receiptSequenceNumber,
                receivedAtUptimeNanoseconds: incoming.receivedAtUptimeNanoseconds,
                continuityGeneration: incoming.continuityGeneration
            )
            try session.accept(sample)
        } catch {
            markUnavailable()
            return false
        }

        newestAcceptedSourceObservation = incoming
        disposition = .live(incoming)
        return true
    }

    /// Projects one exact source-owned observation as RETAINED immediately.
    ///
    /// This is used when source custody already knows a legitimate last observation
    /// is no longer live (for example after disconnect), including a fresh Dashboard
    /// mount that never saw the prior LIVE callback. The source tuple is accepted as
    /// evidence exactly once, then its generation is retired in the canonical session;
    /// no render time is advanced to manufacture staleness.
    @discardableResult
    public mutating func retainSource(
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) -> Bool {
        guard let incoming = validatedSourceObservation(
            watts: watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration
        ) else {
            markUnavailable()
            return false
        }

        switch compare(incoming, to: newestAcceptedSourceObservation) {
        case .stale:
            return false

        case .identical:
            switch disposition {
            case .live:
                _ = session.markUnavailable(
                    authority: .simulator,
                    continuityGeneration: incoming.continuityGeneration
                )
                disposition = .retained(incoming)
                return true
            case .retained:
                return true
            case .unavailable:
                // Once this exact receipt was explicitly made unavailable, replaying
                // it cannot weaken that state back to retained.
                return false
            }

        case .contradictory:
            markUnavailable()
            return false

        case .newer:
            break
        }

        do {
            let sample = try PropulsionPowerSample.simulator(
                identity: session.identity,
                watts: incoming.watts,
                receiptSequenceNumber: incoming.receiptSequenceNumber,
                receivedAtUptimeNanoseconds: incoming.receivedAtUptimeNanoseconds,
                continuityGeneration: incoming.continuityGeneration
            )
            try session.accept(sample)
        } catch {
            markUnavailable()
            return false
        }

        newestAcceptedSourceObservation = incoming
        _ = session.markUnavailable(
            authority: .simulator,
            continuityGeneration: incoming.continuityGeneration
        )
        disposition = .retained(incoming)
        return true
    }

    /// Ends source availability without manufacturing a zero or a retained value.
    /// A later callback from the same/older receipt cannot reopen authority; only a
    /// genuinely newer source generation/receipt may become live again.
    public mutating func markUnavailable() {
        if let newestAcceptedSourceObservation {
            _ = session.markUnavailable(
                authority: .simulator,
                continuityGeneration: newestAcceptedSourceObservation.continuityGeneration
            )
        }
        disposition = .unavailable
    }

    /// Canonical sealed app projection at the display clock.
    /// Intermediate values remain render-only inside the returned projection.
    public func projection(
        atUptimeNanoseconds now: UInt64
    ) -> PropulsionEnergyRailAppProjection {
        switch disposition {
        case .live:
            return session.energyRailAppProjection(
                atUptimeNanoseconds: now,
                scale: scale
            )

        case let .retained(observation):
            return PropulsionEnergyRailAppProjection.retainedSimulatorSource(
                identity: session.identity,
                watts: observation.watts,
                receiptSequenceNumber: observation.receiptSequenceNumber,
                receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
                continuityGeneration: observation.continuityGeneration
            ) ?? session.energyRailAppProjection(
                atUptimeNanoseconds: now,
                scale: scale
            )

        case .unavailable:
            return session.energyRailAppProjection(
                atUptimeNanoseconds: now,
                scale: scale
            )
        }
    }

    private enum SourceComparison {
        case stale
        case identical
        case contradictory
        case newer
    }

    private func compare(
        _ incoming: SourceObservation,
        to previous: SourceObservation?
    ) -> SourceComparison {
        guard let previous else { return .newer }

        if incoming.continuityGeneration < previous.continuityGeneration {
            return .stale
        }
        if incoming.continuityGeneration > previous.continuityGeneration {
            return .newer
        }

        if incoming.receiptSequenceNumber < previous.receiptSequenceNumber {
            return .stale
        }
        if incoming.receiptSequenceNumber > previous.receiptSequenceNumber {
            // Inside one source generation the receipt clock and receive uptime are
            // both monotonic. Reject a newer identity carrying a non-newer source
            // uptime as a contradiction rather than accepting rewritten chronology.
            return incoming.receivedAtUptimeNanoseconds > previous.receivedAtUptimeNanoseconds
                ? .newer
                : .contradictory
        }

        return incoming == previous ? .identical : .contradictory
    }

    private func validatedSourceObservation(
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) -> SourceObservation? {
        guard watts.isFinite,
              watts >= 0,
              receiptSequenceNumber > 0,
              continuityGeneration > 0 else {
            return nil
        }
        return SourceObservation(
            watts: watts == 0 ? 0 : watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration
        )
    }
}
