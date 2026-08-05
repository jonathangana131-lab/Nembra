import Foundation

/// Safe placeholder used until a real scooter Bluetooth configuration has been
/// verified for the selected vehicle profile.
///
/// This service intentionally cannot synthesize a successful connection or any
/// vehicle telemetry. It keeps ordinary app launches truthful while the
/// production Bluetooth implementation is still hardware-gated.
public actor UnverifiedScooterService: ScooterService {
    public nonisolated let profile: VehicleProfile

    private var state: VehicleState
    private var continuations: [UUID: AsyncStream<VehicleState>.Continuation] = [:]

    public init(profile: VehicleProfile = .maxshotV1SPro) {
        self.profile = profile
        self.state = Self.initialState()
    }

    public static func initialState() -> VehicleState {
        VehicleState(
            connection: .disconnected,
            connectionIssue: .unsupportedConfiguration,
            batteryPercent: nil,
            speedKilometersPerHour: nil,
            odometerKilometers: nil,
            tripKilometers: nil,
            rideMode: nil,
            startMode: nil,
            speedLimitsKilometersPerHour: [:],
            isLocked: nil,
            isHeadlightOn: nil,
            isCruiseEnabled: nil,
            powerWatts: nil,
            currentAmps: nil
        )
    }

    public func stateUpdates() -> AsyncStream<VehicleState> {
        let id = UUID()
        let current = state
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    /// There is no verified raw telemetry source yet, so the stream completes
    /// immediately instead of fabricating cached or simulated samples.
    public func speedTelemetryUpdates() -> AsyncStream<SpeedTelemetrySample> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    public func snapshot() -> VehicleState { state }

    /// A connection attempt cannot be made until hardware/protocol identity is
    /// verified. Re-publish the current state rather than faking progress.
    public func connect() async {
        publish()
    }

    public func disconnect() async {
        state.connection = .disconnected
        publish()
    }

    public func setHeadlight(_ enabled: Bool) async throws { throw ScooterCommandError.disconnected }
    public func setLocked(_ locked: Bool) async throws { throw ScooterCommandError.disconnected }
    public func setCruise(_ enabled: Bool) async throws { throw ScooterCommandError.disconnected }
    public func setRideMode(_ mode: RideMode) async throws { throw ScooterCommandError.disconnected }
    public func setStartMode(_ mode: StartMode) async throws { throw ScooterCommandError.disconnected }
    public func setSpeedLimit(kilometersPerHour: Int, slot: SpeedLimitSlot) async throws { throw ScooterCommandError.disconnected }

    private func publish() {
        state.lastUpdated = .now
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}
