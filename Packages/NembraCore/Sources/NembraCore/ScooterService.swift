import Foundation

public enum ScooterCommandError: Error, Equatable, Sendable {
    case disconnected
    /// Nembra deliberately has no verified command implementation for the
    /// selected production scooter configuration yet.
    case unverifiedConfiguration
    case unsupportedCapability
    case unsupportedMode(RideMode)
    case unsupportedSpeedLimitSlot(SpeedLimitSlot)
    case valueOutOfRange
    case commandRejected
    case commandInProgress
}

/// Optional Simulator-only source boundary for consumers that need propulsion
/// receipt/currentness truth rather than aggregate `VehicleState.powerWatts`.
///
/// Implementations must atomically register the stream and replay their current
/// availability as its first element. Availability is state, not an event log, so
/// slow consumers must not receive obsolete queued `.live` states after a newer
/// retained/unavailable transition exists. Genuine equal-valued source observations
/// are allowed and must carry new source receipt identity.
public protocol SimulatorPowerEvidenceProvider: Sendable {
    func simulatorPowerEvidenceUpdates() async -> AsyncStream<SimulatorPowerEvidenceAvailability>
    func simulatorPowerEvidenceSnapshot() async -> SimulatorPowerEvidenceAvailability
}

public extension SimulatorPowerEvidenceProvider {
    func simulatorPowerEvidenceSnapshot() async -> SimulatorPowerEvidenceAvailability {
        let stream = await simulatorPowerEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()
        return await iterator.next() ?? .unavailable
    }
}

#if SWIFT_PACKAGE
/// Package-only legacy consumer projection retained for focused package tests while
/// the app target uses the stronger stateful receipt-fenced Store projection in
/// `VehicleStore.swift`. Keeping this under SwiftPM prevents the direct-compiled app
/// sources from defining two competing `SimulatorPowerStoreProjection` authorities.
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

/// Consumer-side custody for sealed Simulator propulsion evidence.
///
/// Positive authority can enter only through a source-file-sealed availability.
/// Aggregate connection is a one-way negative veto: it may synchronously demote
/// LIVE -> RETAINED while preserving the exact immutable source receipt, but can
/// never promote RETAINED -> LIVE. Source/provider loss fails completely closed.
struct SimulatorPowerEvidenceConsumerAuthority: Sendable {
    private(set) var projection: SimulatorPowerStoreProjection = .unavailable

    mutating func applySource(
        _ sourceAvailability: SimulatorPowerEvidenceAvailability,
        connectionIsConnected: Bool
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
            projection = connectionIsConnected
                ? .live(observation)
                : .retained(observation)
        }
    }

    /// Must be called before publishing aggregate non-connected state. This keeps
    /// last-known presentation available without ever exposing OFFLINE + LIVE.
    mutating func transportBecameUnavailable() {
        guard projection.currentness == .live,
              let observation = projection.observation else {
            return
        }
        projection = .retained(observation)
    }

    mutating func sourceBecameUnavailable() {
        projection = .unavailable
    }
}
#else
/// The app target directly compiles this file while also linking NembraCore. Its
/// Store projection is the stronger stateful authority declared in VehicleStore;
/// alias the historical app-facing name so Dashboard code has one canonical type.
typealias SimulatorPowerStoreProjection = SimulatorPowerStoreFencedProjection
#endif

/// Optional source-owned projection for consumers that require field-specific
/// current speed truth rather than cached `VehicleState` values.
///
/// Implementations must register the returned stream and yield their current
/// `SpeedEvidenceAvailability` as its first element atomically with stream
/// construction. Because availability is current state rather than an event log,
/// providers must also avoid delivering obsolete queued states after newer
/// availability exists (for example with newest-only buffering or equivalent
/// sequencing). Those requirements remove snapshot -> subscribe and slow-consumer
/// races that could otherwise resurrect stale `.live` authority after a disconnect
/// or evidence gap. Raw telemetry remains a separate stream for rendering/
/// diagnostics and is never replayed as a fresh measurement.
public protocol SpeedEvidenceProvider: Sendable {
    func speedEvidenceUpdates() async -> AsyncStream<SpeedEvidenceAvailability>

    /// Returns the provider's current source-owned availability, never the
    /// consumer's last dequeued stream element. Consumers that combine this
    /// field-specific state with another service stream should revalidate through
    /// this snapshot before promoting an event to current app authority.
    ///
    /// The default implementation is deliberately defined in terms of the
    /// protocol's atomic initial-replay contract. Concrete providers may override
    /// it with a more direct actor-owned snapshot when useful.
    func speedEvidenceSnapshot() async -> SpeedEvidenceAvailability
}

public extension SpeedEvidenceProvider {
    func speedEvidenceSnapshot() async -> SpeedEvidenceAvailability {
        let stream = await speedEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()
        return await iterator.next() ?? .unavailable
    }
}

/// Consumer-side admission for one asynchronous refresh of source-owned speed
/// currentness. The opaque token makes supersession mechanical rather than a
/// scheduling assumption: once a connection transition or a newer refresh calls
/// `invalidate()`/`beginRefresh()`, an older suspended refresh can no longer
/// publish authority when it resumes.
///
/// This is intentionally internal. It is app-session coordination, not scooter
/// evidence and not a persisted/protocol-facing authority type.
struct SpeedEvidenceConsumerAuthority {
    struct RefreshToken: Equatable, Sendable {
        fileprivate let identity: UUID
    }

    private var activeRefreshIdentity = UUID()
    private(set) var availability: SpeedEvidenceAvailability = .unavailable

    mutating func invalidate() {
        activeRefreshIdentity = UUID()
        availability = .unavailable
    }

    mutating func beginRefresh() -> RefreshToken {
        invalidate()
        return RefreshToken(identity: activeRefreshIdentity)
    }

    /// Commits only the newest admitted refresh. Connection state is supplied by
    /// the consumer's current service snapshot; a non-connected result remains
    /// unavailable even if the field provider still has retained/live material.
    @discardableResult
    mutating func commit(
        _ candidate: SpeedEvidenceAvailability,
        connectionIsConnected: Bool,
        for token: RefreshToken
    ) -> Bool {
        guard token.identity == activeRefreshIdentity else { return false }
        availability = connectionIsConnected ? candidate : .unavailable
        return true
    }
}

public protocol ScooterService: SpeedTelemetryProvider, Sendable {
    var profile: VehicleProfile { get }

    func stateUpdates() async -> AsyncStream<VehicleState>
    func snapshot() async -> VehicleState
    func connect() async
    func disconnect() async

    func setHeadlight(_ enabled: Bool) async throws
    func setLocked(_ locked: Bool) async throws
    func setCruise(_ enabled: Bool) async throws
    func setRideMode(_ mode: RideMode) async throws
    func setStartMode(_ mode: StartMode) async throws
    func setSpeedLimit(kilometersPerHour: Int, slot: SpeedLimitSlot) async throws
}
