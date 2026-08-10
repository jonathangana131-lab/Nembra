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

/// One synthetic power observation minted by the Simulator source itself.
///
/// The receipt identity and monotonic receipt clock belong to the power source;
/// consumers must not substitute a speed receipt, aggregate `VehicleState`
/// timestamp, render clock, or view-lifecycle time. The initializer is internal so
/// external app code cannot manufacture Simulator power authority from a cached
/// watt number.
public struct SimulatorPowerEvidenceSample: Equatable, Sendable {
    public let watts: Double
    public let receivedAtUptimeNanoseconds: UInt64
    public let receiptID: UUID

    init?(
        watts: Double,
        receivedAtUptimeNanoseconds: UInt64,
        receiptID: UUID = UUID()
    ) {
        guard watts.isFinite,
              watts >= 0,
              receivedAtUptimeNanoseconds > 0 else {
            return nil
        }
        self.watts = watts
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.receiptID = receiptID
    }
}

/// Simulator-only field currentness for synthetic power QA.
///
/// `retained` preserves the last legitimate synthetic observation across a known
/// gap without claiming it is current. `unavailable` carries no numeric authority.
/// This type is never physical ES80 power evidence.
public enum SimulatorPowerEvidenceAvailability: Equatable, Sendable {
    case live(SimulatorPowerEvidenceSample)
    case retained(SimulatorPowerEvidenceSample)
    case unavailable
}

/// Optional source-owned Simulator power projection.
///
/// This deliberately does not define a generic production power provider. It is
/// only the software QA seam needed to exercise Dashboard propulsion presentation
/// without promoting cached aggregate watts or another field's freshness.
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
