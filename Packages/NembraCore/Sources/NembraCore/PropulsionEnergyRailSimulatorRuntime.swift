import Foundation

#if !SWIFT_PACKAGE
import NembraCore
#endif

/// Display-clock scheduling metadata for Simulator-only Energy Rail product QA.
///
/// This is presentation state, not telemetry. It may tell SwiftUI when render-only
/// interpolation needs continuous frames or when a future presentation transition
/// needs one wake-up. It never creates an accepted propulsion observation, refreshes
/// measurement currentness, changes receipt chronology, or carries physical authority.
public struct PropulsionEnergyRailDisplaySchedule: Equatable, Sendable {
    public let requiresContinuousFrames: Bool
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
/// Positive authority enters only through `SimulatorPowerEvidenceAvailability`, whose
/// positive states and receipt construction are source-file sealed by the Simulator
/// source actor. Aggregate vehicle state, speed chronology, mode callbacks, SwiftUI
/// lifecycle, display clocks, and arbitrary NembraCore importers have no public API
/// capable of minting or refreshing watts from caller-provided receipt fields.
///
/// The app target intentionally compiles this exact source alongside its directly
/// compiled Simulator source. Presentation primitives remain imported from NembraCore,
/// while `SimulatorPowerEvidenceAvailability` resolves to the app-local sealed source
/// type. That keeps positive admission mechanically tied to source custody instead of
/// bridging raw receipt scalars across module identities.
/// The display scheduler is downstream presentation state only.
public struct PropulsionEnergyRailSimulatorRuntime: Sendable {
    public static let defaultPresentationCeilingWatts: Double = 650
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

    private enum SourceComparison {
        case stale
        case identical
        case contradictory
        case newer
    }

    private let animationPolicy: PropulsionGaugeAnimationPolicy
    private let freshnessPolicy: PropulsionGaugeFreshnessPolicy
    private var session: PropulsionGaugeSourceSession
    private var scale: PropulsionGaugeScale
    private var disposition: SourceDisposition = .unavailable
    private var newestAcceptedSourceObservation: SourceObservation?
    /// Exact accepted projection lowered only after a sealed source receipt has been
    /// admitted through the canonical gauge session. This is retained presentation,
    /// not a second measurement constructor.
    private var retainedProjection: PropulsionEnergyRailAppProjection?

    // Presentation-only scheduling mirrors. These are updated only after the package
    // accepts an immutable source observation and never feed back into evidence.
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

        self.animationPolicy = animationPolicy
        self.freshnessPolicy = freshnessPolicy
        self.session = PropulsionGaugeSourceSession(
            identity: identity,
            animationPolicy: animationPolicy,
            freshnessPolicy: freshnessPolicy
        )
        self.scale = scale
    }

    /// The sole public positive-admission boundary.
    ///
    /// Callers may inspect `SimulatorPowerEvidenceAvailability`, but they cannot
    /// construct `.live` / `.retained` values or their observations. Therefore every
    /// positive admission below is mechanically bound to genuine Simulator source
    /// custody instead of caller-supplied watts, sequence, uptime, or generation.
    @discardableResult
    public mutating func synchronizeSource(
        _ availability: SimulatorPowerEvidenceAvailability
    ) -> Bool {
        switch availability.currentness {
        case .unavailable:
            guard availability.observation == nil else {
                markUnavailable()
                return false
            }
            markUnavailable()
            return true

        case .retained:
            guard let observation = availability.observation else {
                markUnavailable()
                return false
            }
            return retainSealedSource(observation)

        case .live:
            guard let observation = availability.observation else {
                markUnavailable()
                return false
            }
            return acceptSealedLiveSource(observation)
        }
    }

    /// Negative-only app lifecycle veto for the already-admitted exact source receipt.
    ///
    /// This cannot cold-admit a receipt, invent watts, or promote retained/unavailable
    /// authority. It exists so Store transport fencing can immediately lower a genuine
    /// source LIVE receipt before the Simulator source actor publishes its own retained
    /// state, without creating a second positive-authority construction API.
    @discardableResult
    public mutating func retainCurrentSource() -> Bool {
        guard let observation = newestAcceptedSourceObservation else {
            markUnavailable()
            return false
        }

        switch disposition {
        case let .live(current) where current == observation:
            guard captureRetainedProjection(for: observation) else {
                markUnavailable()
                return false
            }
            _ = session.markUnavailable(
                authority: .simulator,
                continuityGeneration: observation.continuityGeneration
            )
            disposition = .retained(observation)
            resetPresentationSchedule()
            return true

        case let .retained(current) where current == observation:
            return retainedProjectionMatches(observation)

        case .unavailable, .live, .retained:
            return false
        }
    }

#if SWIFT_PACKAGE
    /// Package-only chronology primitive used by focused package tests. Production
    /// app integration does not compile this raw-scalar entry point; its only positive
    /// boundary is `synchronizeSource(_:)` with source-sealed availability.
    @discardableResult
    package mutating func acceptLiveSource(
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) -> Bool {
        acceptLiveSourceTuple(
            watts: watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration
        )
    }

    /// Package-only retained chronology primitive for focused tests. It is omitted
    /// from the directly compiled app runtime, so app/UI code cannot cold-admit a raw
    /// retained tuple.
    @discardableResult
    package mutating func retainSource(
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) -> Bool {
        retainSourceTuple(
            watts: watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration
        )
    }
#endif

    private mutating func acceptSealedLiveSource(
        _ observation: SimulatorPowerObservation
    ) -> Bool {
        acceptLiveSourceTuple(
            watts: observation.watts,
            receiptSequenceNumber: observation.receiptSequenceNumber,
            receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
            continuityGeneration: observation.continuityGeneration
        )
    }

    private mutating func retainSealedSource(
        _ observation: SimulatorPowerObservation
    ) -> Bool {
        retainSourceTuple(
            watts: observation.watts,
            receiptSequenceNumber: observation.receiptSequenceNumber,
            receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
            continuityGeneration: observation.continuityGeneration
        )
    }

    @discardableResult
    private mutating func acceptLiveSourceTuple(
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
            // Delayed older evidence cannot erase newer live/retained truth.
            return false

        case .identical:
            if case let .live(current) = disposition, current == incoming {
                return true
            }
            // An exact receipt already lowered to retained/unavailable cannot regain
            // positive authority by being replayed.
            return false

        case .contradictory:
            markUnavailable()
            return false

        case .newer:
            break
        }

        let sharesPresentationContinuity = sharesPresentationContinuity(with: incoming)

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
        retainedProjection = nil
        updatePresentationScheduleAfterAcceptedSample(
            watts: incoming.watts,
            receivedAtUptimeNanoseconds: incoming.receivedAtUptimeNanoseconds,
            sharesContinuity: sharesPresentationContinuity
        )
        return true
    }

    @discardableResult
    private mutating func retainSourceTuple(
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
            case let .live(current) where current == incoming:
                guard captureRetainedProjection(for: incoming) else {
                    markUnavailable()
                    return false
                }
                _ = session.markUnavailable(
                    authority: .simulator,
                    continuityGeneration: incoming.continuityGeneration
                )
                disposition = .retained(incoming)
                resetPresentationSchedule()
                return true

            case let .retained(current) where current == incoming:
                return retainedProjectionMatches(incoming)

            case .unavailable, .live, .retained:
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
        guard captureRetainedProjection(for: incoming) else {
            markUnavailable()
            return false
        }
        _ = session.markUnavailable(
            authority: .simulator,
            continuityGeneration: incoming.continuityGeneration
        )
        disposition = .retained(incoming)
        resetPresentationSchedule()
        return true
    }

    /// Ends current source availability without manufacturing zero or retained power.
    /// A source receipt already seen by this runtime cannot later reopen live authority.
    public mutating func markUnavailable() {
        if let newestAcceptedSourceObservation {
            _ = session.markUnavailable(
                authority: .simulator,
                continuityGeneration: newestAcceptedSourceObservation.continuityGeneration
            )
        }
        disposition = .unavailable
        retainedProjection = nil
        resetPresentationSchedule()
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
            guard retainedProjectionMatches(observation),
                  let retainedProjection else {
                // Fail closed. The session has already been retired, so its projection
                // is unavailable rather than a fabricated retained measurement.
                return session.energyRailAppProjection(
                    atUptimeNanoseconds: now,
                    scale: scale
                )
            }
            return retainedProjection

        case .unavailable:
            return session.energyRailAppProjection(
                atUptimeNanoseconds: now,
                scale: scale
            )
        }
    }

    /// Presentation-only scheduler for the app's localized display clock.
    ///
    /// Continuous frames are requested only while canonical interpolation is active.
    /// One-shot wakes cover interpolation settlement, accepted-peak expiry, and live
    /// freshness demotion. Retained/unavailable states are fully quiescent.
    public func displaySchedule(
        atUptimeNanoseconds now: UInt64
    ) -> PropulsionEnergyRailDisplaySchedule {
        guard case .live = disposition else { return .inactive }

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

        return PropulsionEnergyRailDisplaySchedule(
            requiresContinuousFrames: requiresContinuousFrames,
            nextTransitionUptimeNanoseconds: nextTransition
        )
    }

    private mutating func captureRetainedProjection(
        for observation: SourceObservation
    ) -> Bool {
        let liveProjection = session.energyRailAppProjection(
            atUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
            scale: scale
        )
        guard liveProjection.currentness == .live,
              let accepted = liveProjection.acceptedMeasurement,
              accepted.authority == .simulator,
              accepted.watts == observation.watts,
              accepted.receiptSequenceNumber == observation.receiptSequenceNumber,
              accepted.receivedAtUptimeNanoseconds == observation.receivedAtUptimeNanoseconds,
              accepted.continuityGeneration == observation.continuityGeneration else {
            retainedProjection = nil
            return false
        }

        let lowered = liveProjection.retainedWithoutNewMeasurement()
        guard lowered.currentness == .retained,
              lowered.acceptedMeasurement == accepted,
              lowered.acceptedWatts == accepted.watts,
              lowered.allowsLiveMotion == false else {
            retainedProjection = nil
            return false
        }
        retainedProjection = lowered
        return true
    }

    private func retainedProjectionMatches(
        _ observation: SourceObservation
    ) -> Bool {
        guard let retainedProjection,
              retainedProjection.currentness == .retained,
              let accepted = retainedProjection.acceptedMeasurement else {
            return false
        }
        return accepted.authority == .simulator
            && accepted.watts == observation.watts
            && accepted.receiptSequenceNumber == observation.receiptSequenceNumber
            && accepted.receivedAtUptimeNanoseconds == observation.receivedAtUptimeNanoseconds
            && accepted.continuityGeneration == observation.continuityGeneration
            && retainedProjection.acceptedWatts == observation.watts
            && retainedProjection.allowsLiveMotion == false
    }

    private func sharesPresentationContinuity(with incoming: SourceObservation) -> Bool {
        guard case .live = disposition,
              let previous = newestAcceptedSourceObservation,
              incoming.continuityGeneration == previous.continuityGeneration,
              incoming.receivedAtUptimeNanoseconds > previous.receivedAtUptimeNanoseconds else {
            return false
        }
        return incoming.receivedAtUptimeNanoseconds - previous.receivedAtUptimeNanoseconds
            <= freshnessPolicy.staleAfterNanoseconds
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
              receivedAtUptimeNanoseconds > 0,
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
