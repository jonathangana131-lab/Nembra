import Foundation

public enum ScooterSimulationScenario: String, CaseIterable, Sendable {
    case coldDisconnected = "cold-disconnected"
    case reconnecting
    case connectedStopped = "connected-stopped"
    case connectedSpeedUnknown = "connected-speed-unknown"
    case riding
    case lowBattery = "low-battery"
    case bluetoothOff = "bluetooth-off"
    case permissionDenied = "permission-denied"
    case scooterUnavailable = "scooter-unavailable"
    case unsupportedConfiguration = "unsupported-configuration"

    public var shouldAutoConnectOnLaunch: Bool {
        switch self {
        case .coldDisconnected, .reconnecting, .bluetoothOff, .permissionDenied, .scooterUnavailable, .unsupportedConfiguration:
            false
        case .connectedStopped, .connectedSpeedUnknown, .riding, .lowBattery:
            true
        }
    }
}

public actor SimulatedScooterService: ScooterService {
    public nonisolated let profile: VehicleProfile

    /// Representative values from the verified three-slot schema. These are
    /// simulation fixtures, not a claim that a slot corresponds to a ride mode.
    private static let representativeSpeedLimits: [SpeedLimitSlot: Int] = [
        .limit1: 12,
        .limit2: 18,
        .limit3: 35
    ]

    public static func state(for scenario: ScooterSimulationScenario) -> VehicleState {
        switch scenario {
        case .coldDisconnected:
            VehicleState(
                connection: .disconnected,
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
        case .reconnecting:
            VehicleState(
                connection: .reconnecting,
                batteryPercent: 71,
                speedKilometersPerHour: 0,
                odometerKilometers: 231.4,
                tripKilometers: 4.6,
                rideMode: .drive,
                startMode: .zeroStart,
                speedLimitsKilometersPerHour: representativeSpeedLimits,
                isLocked: false,
                isHeadlightOn: false,
                isCruiseEnabled: false,
                powerWatts: 0,
                currentAmps: 0
            )
        case .connectedStopped:
            VehicleState(
                connection: .connected,
                batteryPercent: 92,
                speedKilometersPerHour: 0,
                odometerKilometers: 231.4,
                tripKilometers: 4.6,
                rideMode: .sport,
                startMode: .zeroStart,
                speedLimitsKilometersPerHour: representativeSpeedLimits,
                isLocked: false,
                isHeadlightOn: false,
                isCruiseEnabled: false,
                powerWatts: 0,
                currentAmps: 0
            )
        case .connectedSpeedUnknown:
            VehicleState(
                connection: .connected,
                batteryPercent: 92,
                speedKilometersPerHour: nil,
                odometerKilometers: 231.4,
                tripKilometers: 4.6,
                rideMode: .sport,
                startMode: .zeroStart,
                speedLimitsKilometersPerHour: representativeSpeedLimits,
                isLocked: false,
                isHeadlightOn: false,
                isCruiseEnabled: false,
                powerWatts: nil,
                currentAmps: nil
            )
        case .riding:
            VehicleState(
                connection: .connected,
                batteryPercent: 68,
                speedKilometersPerHour: 18.4,
                odometerKilometers: 232.0,
                tripKilometers: 5.2,
                rideMode: .drive,
                startMode: .zeroStart,
                speedLimitsKilometersPerHour: representativeSpeedLimits,
                isLocked: false,
                isHeadlightOn: true,
                isCruiseEnabled: false,
                powerWatts: 356,
                currentAmps: 9.9
            )
        case .lowBattery:
            VehicleState(
                connection: .connected,
                batteryPercent: 14,
                speedKilometersPerHour: 0,
                odometerKilometers: 238.8,
                tripKilometers: 3.1,
                rideMode: .eco,
                startMode: .kickStart,
                speedLimitsKilometersPerHour: representativeSpeedLimits,
                isLocked: true,
                isHeadlightOn: false,
                isCruiseEnabled: false,
                powerWatts: 0,
                currentAmps: 0
            )
        case .bluetoothOff:
            VehicleState(
                connection: .disconnected,
                connectionIssue: .bluetoothPoweredOff,
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
        case .permissionDenied:
            VehicleState(
                connection: .disconnected,
                connectionIssue: .bluetoothPermissionDenied,
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
        case .scooterUnavailable:
            VehicleState(
                connection: .disconnected,
                connectionIssue: .scooterUnavailable,
                batteryPercent: 71,
                speedKilometersPerHour: 0,
                odometerKilometers: 231.4,
                tripKilometers: 4.6,
                rideMode: .drive,
                startMode: .zeroStart,
                speedLimitsKilometersPerHour: representativeSpeedLimits,
                isLocked: false,
                isHeadlightOn: false,
                isCruiseEnabled: false,
                powerWatts: 0,
                currentAmps: 0
            )
        case .unsupportedConfiguration:
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
    }

    private var state: VehicleState
    private var continuations: [UUID: AsyncStream<VehicleState>.Continuation] = [:]
    private var speedTelemetryContinuations: [UUID: AsyncStream<SpeedTelemetrySample>.Continuation] = [:]
    private var simulatedUptimeNanoseconds: UInt64 = 1
    private var commandInFlight = false
    private var connectionGeneration: UInt64 = 0
    private let commandLatencyNanoseconds: UInt64
    private let commandAcknowledgementGate: (@Sendable () async throws -> Void)?

    public init(
        profile: VehicleProfile = .maxshotV1SPro,
        initialState: VehicleState? = nil,
        commandLatencyNanoseconds: UInt64 = 120_000_000
    ) {
        self.profile = profile
        self.commandLatencyNanoseconds = commandLatencyNanoseconds
        self.commandAcknowledgementGate = nil
        self.state = initialState ?? Self.defaultInitialState()
    }

    /// Test-only timing injection used to prove command ordering without relying
    /// on scheduler-sensitive wall-clock sleeps. Kept internal so production
    /// callers continue to use the real simulated latency contract above.
    init(
        profile: VehicleProfile = .maxshotV1SPro,
        initialState: VehicleState? = nil,
        commandAcknowledgementGate: @escaping @Sendable () async throws -> Void
    ) {
        self.profile = profile
        self.commandLatencyNanoseconds = 0
        self.commandAcknowledgementGate = commandAcknowledgementGate
        self.state = initialState ?? Self.defaultInitialState()
    }

    private static func defaultInitialState() -> VehicleState {
        VehicleState(
            connection: .disconnected,
            batteryPercent: 92,
            speedKilometersPerHour: 0,
            odometerKilometers: 231.4,
            tripKilometers: 4.6,
            rideMode: .sport,
            startMode: .zeroStart,
            speedLimitsKilometersPerHour: representativeSpeedLimits,
            isLocked: false,
            isHeadlightOn: false,
            isCruiseEnabled: false,
            powerWatts: 0,
            currentAmps: 0
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

    /// Raw telemetry streams do not replay cached state on subscription. A
    /// replay would look like a fresh measurement and corrupt cadence/latency
    /// diagnostics. Consumers receive only samples emitted after subscribing.
    public func speedTelemetryUpdates() -> AsyncStream<SpeedTelemetrySample> {
        let id = UUID()
        return AsyncStream { continuation in
            speedTelemetryContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSpeedTelemetryContinuation(id) }
            }
        }
    }

    public func snapshot() -> VehicleState { state }

    public func connect() async {
        guard state.connection != .connected else { return }
        if state.connectionIssue?.blocksConnectionAttempt == true {
            publish()
            return
        }
        connectionGeneration &+= 1
        let attemptGeneration = connectionGeneration
        state.connectionIssue = nil
        state.connection = .connecting
        publish()
        try? await Task.sleep(nanoseconds: 220_000_000)
        guard connectionGeneration == attemptGeneration, state.connection == .connecting else { return }
        state.connection = .connected
        hydrateMissingVehicleDataAfterSuccessfulConnection()
        state.lastUpdated = .now
        publish()
    }

    public func disconnect() async {
        connectionGeneration &+= 1
        state.connectionIssue = nil
        state.connection = .disconnected
        // A transport disconnect is not a speed/power measurement. Preserve the
        // last confirmed values so callers can present them explicitly as stale
        // rather than manufacturing a zero that the scooter never reported.
        state.lastUpdated = .now
        publish()
    }

    public func setHeadlight(_ enabled: Bool) async throws {
        guard profile.capabilities.supportsHeadlight else { throw ScooterCommandError.unsupportedCapability }
        let generation = try beginCommand()
        defer { finishCommand() }
        try await acknowledgeLatency(expectedConnectionGeneration: generation)
        state.isHeadlightOn = enabled
        publish()
    }

    public func setLocked(_ locked: Bool) async throws {
        guard profile.capabilities.supportsLock else { throw ScooterCommandError.unsupportedCapability }
        let generation = try beginCommand()
        defer { finishCommand() }

        // Locking is safety-sensitive: unknown speed is not the same thing as
        // stopped. Require a fresh, finite stationary value both before and
        // after acknowledgement because the actor can re-enter while waiting
        // for the simulated transport confirmation. Unlocking stays available
        // even when speed is unknown.
        if locked {
            guard let speed = state.speedKilometersPerHour,
                  speed.isFinite,
                  speed >= 0,
                  speed < 0.5 else {
                throw ScooterCommandError.commandRejected
            }
        }

        try await acknowledgeLatency(expectedConnectionGeneration: generation)

        if locked {
            guard let speed = state.speedKilometersPerHour,
                  speed.isFinite,
                  speed >= 0,
                  speed < 0.5 else {
                throw ScooterCommandError.commandRejected
            }
        }

        state.isLocked = locked
        publish()
    }

    public func setCruise(_ enabled: Bool) async throws {
        guard profile.capabilities.supportsCruise else { throw ScooterCommandError.unsupportedCapability }
        let generation = try beginCommand()
        defer { finishCommand() }
        try await acknowledgeLatency(expectedConnectionGeneration: generation)
        state.isCruiseEnabled = enabled
        publish()
    }

    public func setRideMode(_ mode: RideMode) async throws {
        guard profile.capabilities.supportedRideModes.contains(mode) else {
            throw ScooterCommandError.unsupportedMode(mode)
        }
        let generation = try beginCommand()
        defer { finishCommand() }
        try await acknowledgeLatency(expectedConnectionGeneration: generation)
        state.rideMode = mode
        publish()
    }

    public func setStartMode(_ mode: StartMode) async throws {
        guard profile.capabilities.supportsStartMode else { throw ScooterCommandError.unsupportedCapability }
        let generation = try beginCommand()
        defer { finishCommand() }
        try await acknowledgeLatency(expectedConnectionGeneration: generation)
        state.startMode = mode
        publish()
    }

    public func setSpeedLimit(kilometersPerHour: Int, slot: SpeedLimitSlot) async throws {
        guard profile.capabilities.supportsSpeedLimit else { throw ScooterCommandError.unsupportedCapability }
        guard let range = profile.capabilities.speedLimitRangesBySlot[slot] else {
            throw ScooterCommandError.unsupportedSpeedLimitSlot(slot)
        }
        guard range.contains(kilometersPerHour) else {
            throw ScooterCommandError.valueOutOfRange
        }
        let generation = try beginCommand()
        defer { finishCommand() }
        try await acknowledgeLatency(expectedConnectionGeneration: generation)
        state.speedLimitsKilometersPerHour[slot] = kilometersPerHour
        publish()
    }

    // MARK: - QA scenario controls

    public func simulateRide(speedKilometersPerHour: Double, elapsedSeconds: Double) {
        guard state.connection == .connected, state.isLocked != true else { return }
        guard speedKilometersPerHour.isFinite, elapsedSeconds.isFinite, elapsedSeconds >= 0 else { return }

        let speed = max(0, speedKilometersPerHour)
        let distance = speed * elapsedSeconds / 3600
        guard distance.isFinite else { return }
        state.speedKilometersPerHour = speed
        state.tripKilometers = (state.tripKilometers ?? 0) + distance
        state.odometerKilometers = (state.odometerKilometers ?? 0) + distance
        state.powerWatts = speed == 0 ? 0 : Int(min(620, 80 + speed * 15))
        state.currentAmps = state.powerWatts.map { Double($0) / 36.0 }
        if speed > 0, let battery = state.batteryPercent {
            let drain = Int(min(Double(battery), floor(distance / 1.5)))
            state.batteryPercent = max(0, battery - drain)
        }

        let availableNanoseconds = UInt64.max - simulatedUptimeNanoseconds
        let requestedNanoseconds = elapsedSeconds * 1_000_000_000
        let elapsedNanoseconds: UInt64
        if availableNanoseconds == 0 {
            elapsedNanoseconds = 0
        } else if !requestedNanoseconds.isFinite || requestedNanoseconds >= Double(availableNanoseconds) {
            elapsedNanoseconds = availableNanoseconds
        } else {
            elapsedNanoseconds = max(1, UInt64(requestedNanoseconds))
        }
        simulatedUptimeNanoseconds &+= elapsedNanoseconds
        if elapsedNanoseconds > 0, let sample = try? SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: speed / 3.6,
            receivedAtUptimeNanoseconds: simulatedUptimeNanoseconds,
            receivedAtDate: .now
        ) {
            publishSpeedTelemetry(sample)
        }

        state.lastUpdated = .now
        publish()
    }

    public func simulateConnectionIssue(_ issue: VehicleConnectionIssue?) {
        connectionGeneration &+= 1
        state.connectionIssue = issue
        state.connection = .disconnected
        // Connection failures carry no new telemetry evidence. Keep the last
        // confirmed vehicle values intact and let connection state mark them stale.
        publish()
    }

    public func simulateConnectionDrop() {
        connectionGeneration &+= 1
        state.connection = .reconnecting
        state.lastUpdated = .now
        publish()
    }

    public func simulateReconnected() {
        connectionGeneration &+= 1
        state.connectionIssue = nil
        state.connection = .connected
        state.lastUpdated = .now
        publish()
    }

    private func hydrateMissingVehicleDataAfterSuccessfulConnection() {
        let fixture = Self.state(for: .connectedStopped)
        if state.batteryPercent == nil { state.batteryPercent = fixture.batteryPercent }
        if state.speedKilometersPerHour == nil { state.speedKilometersPerHour = fixture.speedKilometersPerHour }
        if state.odometerKilometers == nil { state.odometerKilometers = fixture.odometerKilometers }
        if state.tripKilometers == nil { state.tripKilometers = fixture.tripKilometers }
        if state.rideMode == nil { state.rideMode = fixture.rideMode }
        if state.startMode == nil { state.startMode = fixture.startMode }
        if state.speedLimitsKilometersPerHour.isEmpty {
            state.speedLimitsKilometersPerHour = fixture.speedLimitsKilometersPerHour
        }
        if state.isLocked == nil { state.isLocked = fixture.isLocked }
        if state.isHeadlightOn == nil { state.isHeadlightOn = fixture.isHeadlightOn }
        if state.isCruiseEnabled == nil { state.isCruiseEnabled = fixture.isCruiseEnabled }
        if state.powerWatts == nil { state.powerWatts = fixture.powerWatts }
        if state.currentAmps == nil { state.currentAmps = fixture.currentAmps }
    }

    private func beginCommand() throws -> UInt64 {
        guard !commandInFlight else { throw ScooterCommandError.commandInProgress }
        try ensureConnected()
        commandInFlight = true
        return connectionGeneration
    }

    private func finishCommand() {
        commandInFlight = false
    }

    private func ensureConnected() throws {
        guard state.connection == .connected else { throw ScooterCommandError.disconnected }
    }

    private func acknowledgeLatency(expectedConnectionGeneration: UInt64) async throws {
        if let commandAcknowledgementGate {
            try await commandAcknowledgementGate()
        } else {
            try await Task.sleep(nanoseconds: commandLatencyNanoseconds)
        }
        guard connectionGeneration == expectedConnectionGeneration else {
            throw ScooterCommandError.disconnected
        }
        try ensureConnected()
        state.lastUpdated = .now
    }

    private func publish() {
        state.lastUpdated = .now
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }

    private func publishSpeedTelemetry(_ sample: SpeedTelemetrySample) {
        for continuation in speedTelemetryContinuations.values {
            continuation.yield(sample)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func removeSpeedTelemetryContinuation(_ id: UUID) {
        speedTelemetryContinuations[id] = nil
    }
}
