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
///
/// A stream element that was already handed to a consumer can still be delayed
/// behind another independently consumed vehicle-state stream. Truth-sensitive
/// consumers must therefore re-read `speedEvidenceSnapshot()` at the point where
/// they combine speed currentness with transport state rather than treating an old
/// delivered stream element as present source authority.
public protocol SpeedEvidenceProvider: Sendable {
    func speedEvidenceUpdates() async -> AsyncStream<SpeedEvidenceAvailability>
    func speedEvidenceSnapshot() async -> SpeedEvidenceAvailability
}

public extension SpeedEvidenceProvider {
    /// Reads the provider's current availability through the same atomic initial
    /// replay contract as `speedEvidenceUpdates()`. Providers with a cheaper
    /// source-owned snapshot may override this requirement, while the default
    /// implementation remains correct for state-style streams that satisfy the
    /// protocol contract.
    func speedEvidenceSnapshot() async -> SpeedEvidenceAvailability {
        let stream = await speedEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()
        return await iterator.next() ?? .unavailable
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
