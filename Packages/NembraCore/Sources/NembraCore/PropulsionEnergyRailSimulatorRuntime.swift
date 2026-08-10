import Foundation

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
/// Positive authority enters only through an immutable source-owned Simulator power
/// receipt tuple. Aggregate vehicle state, speed chronology, mode callbacks, SwiftUI
/// lifecycle, and display clocks have no API capable of minting or refreshing watts.
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

    /// Admits one exact source-owned LIVE Simulator power observation.
    ///
    /// There is intentionally no overload without source receipt identity. A genuine
    /// equal-watt observation refreshes currentness only when its source tuple is newer.
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
        updatePresentationScheduleAfterAcceptedSample(
            watts: incoming.watts,
            receivedAtUptimeNanoseconds: incoming.receivedAtUptimeNanoseconds,
            sharesContinuity: sharesPresentationContinuity
        )
        return true
    }

    /// Immediately lowers one exact source-owned receipt to RETAINED.
    ///
    /// If the runtime already accepted this receipt live, its sealed projection is
    /// authority-lowered without changing measurement identity. On a cold remount,
    /// the complete source tuple may be admitted once as already-retained evidence;
    /// no render timestamp is used to manufacture staleness.
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
            case let .live(current) where current == incoming:
                _ = session.markUnavailable(
                    authority: .simulator,
                    continuityGeneration: incoming.continuityGeneration
                )
                disposition = .retained(incoming)
                resetPresentationSchedule()
                return true

            case let .retained(current) where current == incoming:
                return true

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
