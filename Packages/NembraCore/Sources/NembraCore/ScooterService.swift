import Foundation

public enum ScooterCommandError: Error, Equatable, Sendable {
    case disconnected
    case unsupportedCapability
    case unsupportedMode(RideMode)
    case unsupportedSpeedLimitSlot(SpeedLimitSlot)
    case valueOutOfRange
    case commandRejected
    case commandInProgress
}

/// Optional field-specific currentness projection supplied by a telemetry source
/// that can attribute samples at its acquisition boundary.
///
/// Raw telemetry remains available separately through `SpeedTelemetryProvider`
/// for rendering and diagnostics. Consumers that need current physical/control
/// truth use this projection instead of guessing freshness from cached
/// `VehicleState.speedKilometersPerHour`.
public protocol SpeedEvidenceProvider: Sendable {
    func speedEvidenceUpdates() async -> AsyncStream<SpeedEvidenceAvailability>
    func speedEvidenceSnapshot() async -> SpeedEvidenceAvailability
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
