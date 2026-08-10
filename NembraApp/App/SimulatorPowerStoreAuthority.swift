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
/// can demote LIVE -> RETAINED but can never promote RETAINED -> LIVE. A reconnect
/// without a fresh source-issued LIVE availability consequently leaves the exact
/// last source receipt retained.
struct SimulatorPowerStoreAuthority: Sendable {
    private(set) var projection: SimulatorPowerStoreProjection = .unavailable

    /// Applies the newest source-owned availability after a provider wake-up or
    /// explicit snapshot refresh. Malformed source shape fails closed even though
    /// #1942 mechanically prevents normal callers from constructing positive cases.
    mutating func applySource(
        _ sourceAvailability: SimulatorPowerEvidenceAvailability,
        transportIsConnected: Bool
    ) {
        switch sourceAvailability.currentness {
        case .unavailable:
            guard sourceAvailability.observation == nil else {
                projection = .unavailable
                return
            }
            projection = .unavailable

        case .retained:
            guard let observation = sourceAvailability.observation else {
                projection = .unavailable
                return
            }
            projection = .retained(observation)

        case .live:
            guard let observation = sourceAvailability.observation else {
                projection = .unavailable
                return
            }
            projection = transportIsConnected
                ? .live(observation)
                : .retained(observation)
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
        projection = .retained(observation)
    }

    /// Stream/provider termination cannot preserve live authority. This is stronger
    /// than a transport veto because the app no longer has a source-currentness owner
    /// to re-snapshot, so presentation fails completely closed.
    mutating func sourceBecameUnavailable() {
        projection = .unavailable
    }
}
