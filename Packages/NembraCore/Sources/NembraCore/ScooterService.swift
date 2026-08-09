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
}

/// One source-issued coherent view of aggregate vehicle presentation state and
/// field-specific speed currentness.
///
/// This snapshot exists because independently scheduled state/evidence streams can
/// otherwise combine a newer reconnect with an older already-dequeued `.live`
/// speed value. Such a cross-stream combination can resurrect stopped authority
/// even when the source has already demoted that evidence. A coherent snapshot is
/// valid only as the paired state emitted by one source turn; it is not protocol or
/// physical scooter evidence by itself.
public struct VehicleSpeedEvidenceSnapshot: Equatable, Sendable {
    public let state: VehicleState
    public let speedEvidenceAvailability: SpeedEvidenceAvailability
}

/// Optional source-owned stream for app consumers that must never assemble speed
/// authority from independently scheduled vehicle/currentness streams.
///
/// Implementations must atomically register and replay the current pair, preserve
/// source emission order, and coalesce obsolete queued snapshots with newest-only
/// semantics. Providers without this stronger contract are intentionally not
/// sufficient to authorize app-level live speed controls.
public protocol VehicleSpeedEvidenceSnapshotProvider: Sendable {
    func vehicleSpeedEvidenceUpdates() async -> AsyncStream<VehicleSpeedEvidenceSnapshot>
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