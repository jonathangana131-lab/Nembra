/// App-session projection of the sealed Simulator propulsion source.
///
/// This is deliberately distinct from `SimulatorPowerEvidenceAvailability`: the
/// source owns positive LIVE/RETAINED currentness, while the app session may apply
/// additional one-way negative vetoes (for example transport becoming disconnected)
/// before SwiftUI can observe a live presentation claim. The immutable source
/// observation is always preserved byte-for-byte; this layer cannot mint one.
enum SimulatorPowerStoreCurrentness: Equatable, Sendable {
    case unavailable
    case retained
    case live
}

struct SimulatorPowerStoreProjection: Equatable, Sendable {
    let currentness: SimulatorPowerStoreCurrentness
    let observation: SimulatorPowerObservation?

    static let unavailable = SimulatorPowerStoreProjection(
        currentness: .unavailable,
        observation: nil
    )

    fileprivate static func retained(
        _ observation: SimulatorPowerObservation
    ) -> SimulatorPowerStoreProjection {
        SimulatorPowerStoreProjection(
            currentness: .retained,
            observation: observation
        )
    }

    fileprivate static func live(
        _ observation: SimulatorPowerObservation
    ) -> SimulatorPowerStoreProjection {
        SimulatorPowerStoreProjection(
            currentness: .live,
            observation: observation
        )
    }

    private init(
        currentness: SimulatorPowerStoreCurrentness,
        observation: SimulatorPowerObservation?
    ) {
        self.currentness = currentness
        self.observation = observation
    }
}

/// Mechanical custody for the Store-facing Simulator power projection.
///
/// Positive authority can enter only through the source-file-sealed
/// `SimulatorPowerEvidenceAvailability` emitted by `SimulatedScooterService`.
/// Aggregate connection state is accepted only as a negative veto and therefore
/// can demote LIVE -> RETAINED but can never promote RETAINED -> LIVE.
///
/// A transport or provider demotion also fences the exact source receipt that lost
/// live authority. Aggregate reconnect does not clear that fence. The same or an
/// older source LIVE receipt stays retained/unavailable; only a strictly newer source
/// receipt can reopen LIVE. This prevents delayed pre-disconnect callbacks/snapshots
/// from resurrecting propulsion currentness.
struct SimulatorPowerStoreAuthority: Sendable {
    private struct SourceIdentity: Equatable, Sendable {
        let continuityGeneration: UInt64
        let receiptSequenceNumber: UInt64
        let receivedAtUptimeNanoseconds: UInt64

        init(_ observation: SimulatorPowerObservation) {
            continuityGeneration = observation.continuityGeneration
            receiptSequenceNumber = observation.receiptSequenceNumber
            receivedAtUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
        }
    }

    private enum IdentityComparison {
        case older
        case identical
        case contradictory
        case newer
    }

    private(set) var projection: SimulatorPowerStoreProjection = .unavailable
    private var newestSourceObservation: SimulatorPowerObservation?
    private var negativeAuthorityFenceIdentity: SourceIdentity?
    private var sourceProviderIsAvailable = true

    /// Applies source-owned availability after a provider wake-up or explicit
    /// snapshot refresh. Malformed source shape fails closed even though the source
    /// seal mechanically prevents normal callers from constructing positive cases.
    mutating func applySource(
        _ sourceAvailability: SimulatorPowerEvidenceAvailability,
        transportIsConnected: Bool
    ) {
        switch sourceAvailability.currentness {
        case .unavailable:
            guard sourceAvailability.observation == nil else {
                failClosed()
                return
            }
            failClosed()

        case .retained:
            guard let observation = sourceAvailability.observation else {
                failClosed()
                return
            }
            applyRetainedSource(observation)

        case .live:
            guard let observation = sourceAvailability.observation else {
                failClosed()
                return
            }
            applyLiveSource(observation, transportIsConnected: transportIsConnected)
        }
    }

    /// Synchronous transport veto. Call this before publishing any aggregate state
    /// whose connection is no longer `.connected`, so Store observers can never see
    /// disconnected transport paired with a live propulsion claim.
    mutating func transportBecameUnavailable() {
        guard projection.currentness == .live,
              let observation = projection.observation else {
            return
        }
        rememberNegativeFence(for: observation)
        projection = .retained(observation)
    }

    /// Stream/provider termination cannot preserve live authority. The last accepted
    /// source receipt is fenced before projection becomes unavailable, so an already
    /// queued old callback cannot reopen LIVE after termination. A Store that obtains
    /// a genuinely new provider must explicitly re-enable provider admission first.
    mutating func sourceBecameUnavailable() {
        sourceProviderIsAvailable = false
        failClosed()
    }

    /// Explicitly reopens *provider admission*, not propulsion LIVE authority. The
    /// negative receipt fence remains. Only a subsequently applied strictly newer
    /// source LIVE receipt can reopen presentation currentness.
    mutating func sourceProviderBecameAvailable() {
        sourceProviderIsAvailable = true
    }

    private mutating func applyRetainedSource(_ observation: SimulatorPowerObservation) {
        guard sourceProviderIsAvailable else { return }

        switch compare(observation, to: newestSourceObservation) {
        case .older:
            return
        case .contradictory:
            failClosed()
            return
        case .identical:
            projection = .retained(observation)
            rememberNegativeFence(for: observation)
        case .newer:
            newestSourceObservation = observation
            projection = .retained(observation)
            rememberNegativeFence(for: observation)
        }
    }

    private mutating func applyLiveSource(
        _ observation: SimulatorPowerObservation,
        transportIsConnected: Bool
    ) {
        guard sourceProviderIsAvailable else { return }

        let sourceComparison = compare(observation, to: newestSourceObservation)
        switch sourceComparison {
        case .older:
            return
        case .contradictory:
            failClosed()
            return
        case .identical:
            break
        case .newer:
            newestSourceObservation = observation
        }

        guard transportIsConnected else {
            projection = .retained(observation)
            rememberNegativeFence(for: observation)
            return
        }

        if let fence = negativeAuthorityFenceIdentity {
            switch compare(SourceIdentity(observation), to: fence) {
            case .older, .identical:
                if projection.currentness != .unavailable {
                    projection = .retained(observation)
                }
                return
            case .contradictory:
                failClosed()
                return
            case .newer:
                negativeAuthorityFenceIdentity = nil
            }
        }

        projection = .live(observation)
    }

    private mutating func rememberNegativeFence(for observation: SimulatorPowerObservation) {
        let candidate = SourceIdentity(observation)
        guard let current = negativeAuthorityFenceIdentity else {
            negativeAuthorityFenceIdentity = candidate
            return
        }

        switch compare(candidate, to: current) {
        case .newer:
            negativeAuthorityFenceIdentity = candidate
        case .older, .identical:
            break
        case .contradictory:
            projection = .unavailable
        }
    }

    private mutating func failClosed() {
        fenceNewestObservationWithoutRecursion()
        projection = .unavailable
    }

    private mutating func fenceNewestObservationWithoutRecursion() {
        guard let observation = newestSourceObservation else { return }
        let candidate = SourceIdentity(observation)
        guard let current = negativeAuthorityFenceIdentity else {
            negativeAuthorityFenceIdentity = candidate
            return
        }
        if case .newer = compare(candidate, to: current) {
            negativeAuthorityFenceIdentity = candidate
        }
    }

    private func compare(
        _ observation: SimulatorPowerObservation,
        to previous: SimulatorPowerObservation?
    ) -> IdentityComparison {
        guard let previous else { return .newer }

        let identityComparison = compare(SourceIdentity(observation), to: SourceIdentity(previous))
        if case .identical = identityComparison,
           observation != previous {
            return .contradictory
        }
        return identityComparison
    }

    private func compare(
        _ incoming: SourceIdentity,
        to previous: SourceIdentity
    ) -> IdentityComparison {
        if incoming.continuityGeneration < previous.continuityGeneration {
            return .older
        }
        if incoming.continuityGeneration > previous.continuityGeneration {
            return .newer
        }

        if incoming.receiptSequenceNumber < previous.receiptSequenceNumber {
            return .older
        }
        if incoming.receiptSequenceNumber > previous.receiptSequenceNumber {
            return incoming.receivedAtUptimeNanoseconds > previous.receivedAtUptimeNanoseconds
                ? .newer
                : .contradictory
        }

        if incoming.receivedAtUptimeNanoseconds == previous.receivedAtUptimeNanoseconds {
            return .identical
        }
        return .contradictory
    }
}
