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

/// One source-owned synthetic propulsion observation used only by Simulator QA.
///
/// This is deliberately not a physical scooter power type. It exists so the app
/// can exercise the canonical propulsion presentation with real source chronology
/// instead of inferring power receipts from `VehicleState` value changes, speed
/// callbacks, command publishes, or the 60 Hz display clock.
public struct SimulatorPropulsionPowerSample: Equatable, Sendable {
    public let watts: Double
    public let receiptSequenceNumber: UInt64
    public let receivedAtUptimeNanoseconds: UInt64
    public let continuityGeneration: UInt64

    init?(
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) {
        guard watts.isFinite,
              watts >= 0,
              receiptSequenceNumber > 0,
              receivedAtUptimeNanoseconds > 0,
              continuityGeneration > 0 else {
            return nil
        }
        self.watts = watts == 0 ? 0 : watts
        self.receiptSequenceNumber = receiptSequenceNumber
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.continuityGeneration = continuityGeneration
    }
}

/// Current Simulator-only propulsion evidence. Retained preserves the last
/// legitimate synthetic observation without pretending it is still live;
/// unavailable carries no numeric power authority.
public enum SimulatorPropulsionPowerAvailability: Equatable, Sendable {
    case live(SimulatorPropulsionPowerSample)
    case retained(SimulatorPropulsionPowerSample)
    case unavailable
}

/// Optional source-owned Simulator propulsion projection.
///
/// Like `SpeedEvidenceProvider`, availability is current state rather than an
/// event log: registration and initial replay must be atomic and slow consumers
/// must not be allowed to resurrect obsolete `.live` state. Crucially, a provider
/// must issue a distinct source receipt for every legitimate synthetic propulsion
/// observation even when the numeric watt value is unchanged. Connection state,
/// speed receipts, mode changes, and unrelated `VehicleState` publishes are not
/// substitute propulsion receipts.
public protocol SimulatorPropulsionPowerEvidenceProvider: Sendable {
    func simulatorPropulsionPowerEvidenceUpdates() async -> AsyncStream<SimulatorPropulsionPowerAvailability>
    func simulatorPropulsionPowerEvidenceSnapshot() async -> SimulatorPropulsionPowerAvailability
}

public extension SimulatorPropulsionPowerEvidenceProvider {
    func simulatorPropulsionPowerEvidenceSnapshot() async -> SimulatorPropulsionPowerAvailability {
        let stream = await simulatorPropulsionPowerEvidenceUpdates()
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
