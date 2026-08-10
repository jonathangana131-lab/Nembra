import Dispatch
import Foundation

public enum ScooterSimulationScenario: String, CaseIterable, Sendable {
    case coldDisconnected = "cold-disconnected"
    case reconnecting
    case connectedStopped = "connected-stopped"
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
        case .connectedStopped, .riding, .lowBattery:
            true
        }
    }
}

/// One synthetic power observation minted by the Simulator source itself.
///
/// Receipt identity and monotonic time belong to power. Consumers must not
/// substitute speed freshness, aggregate vehicle timestamps, render clocks, or
/// view-lifecycle time. Construction is file-private so no other app/package file
/// can manufacture Simulator propulsion authority from a cached watt number.
public struct SimulatorPowerEvidenceSample: Equatable, Sendable {
    public let watts: Double
    public let receivedAtUptimeNanoseconds: UInt64
    public let receiptID: UUID

    fileprivate init?(
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
/// `retained` preserves the last legitimate synthetic observation across a known
/// gap without calling it current. This is never physical ES80 power evidence.
public enum SimulatorPowerEvidenceAvailability: Equatable, Sendable {
    case live(SimulatorPowerEvidenceSample)
    case retained(SimulatorPowerEvidenceSample)
    case unavailable
}

/// Source-owned synthetic-power state used only to exercise truthful Dashboard
/// propulsion presentation. It deliberately does not define production power
/// semantics for any physical scooter profile.
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

public actor SimulatedScooterService: ScooterService, SpeedEvidenceProvider, SimulatorPowerEvidenceProvider {
    public nonisolated let profile: VehicleProfile

    /// Synthetic QA values that exercise all three limiter slots without
    /// attributing their ranges or mode relationship to any physical scooter.
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
    private var speedEvidenceContinuations: [UUID: AsyncStream<SpeedEvidenceAvailability>.Continuation] = [:]
    private var powerEvidenceContinuations: [UUID: AsyncStream<SimulatorPowerEvidenceAvailability>.Continuation] = [:]
    private var speedEvidenceTruth: SpeedEvidenceLiveTruth
    private var powerEvidenceAvailability: SimulatorPowerEvidenceAvailability

    /// Tracks the last raw packet-arrival timestamp only to guarantee strict
    /// monotonic ordering if two simulated packets are emitted in the same tick.
    /// Ride `elapsedSeconds` is distance/time evidence and must not be used as a
    /// fake packet-arrival clock.
    private var lastTelemetryUptimeNanoseconds: UInt64
    /// Power owns an independent receipt clock. A speed receipt or aggregate
    /// vehicle timestamp can never become propulsion freshness authority.
    private var lastPowerUptimeNanoseconds: UInt64
    private var commandInFlight = false
    private var connectionGeneration: UInt64
    private let commandLatencyNanoseconds: UInt64
    private let commandAcknowledgementGate: (@Sendable () async throws -> Void)?

    public init(
        profile: VehicleProfile = .simulatorQA,
        initialState: VehicleState? = nil,
        commandLatencyNanoseconds: UInt64 = 120_000_000
    ) {
        let resolvedState = initialState ?? Self.defaultInitialState()
        let initialEvidence = Self.initialSpeedEvidence(for: resolvedState)
        let initialPowerEvidence = Self.initialPowerEvidence(for: resolvedState, profile: profile)

        self.profile = profile
        self.commandLatencyNanoseconds = commandLatencyNanoseconds
        self.commandAcknowledgementGate = nil
        self.state = resolvedState
        self.speedEvidenceTruth = initialEvidence.truth
        self.powerEvidenceAvailability = initialPowerEvidence.availability
        self.connectionGeneration = initialEvidence.connectionGeneration
        self.lastTelemetryUptimeNanoseconds = initialEvidence.lastTelemetryUptimeNanoseconds
        self.lastPowerUptimeNanoseconds = initialPowerEvidence.lastPowerUptimeNanoseconds
    }

    /// Test-only timing injection used to prove command ordering without relying
    /// on scheduler-sensitive wall-clock sleeps. Kept internal so production
    /// callers continue to use the real simulated latency contract above.
    init(
        profile: VehicleProfile = .simulatorQA,
        initialState: VehicleState? = nil,
        commandAcknowledgementGate: @escaping @Sendable () async throws -> Void
    ) {
        let resolvedState = initialState ?? Self.defaultInitialState()
        let initialEvidence = Self.initialSpeedEvidence(for: resolvedState)
        let initialPowerEvidence = Self.initialPowerEvidence(for: resolvedState, profile: profile)

        self.profile = profile
        self.commandLatencyNanoseconds = 0
        self.commandAcknowledgementGate = commandAcknowledgementGate
        self.state = resolvedState
        self.speedEvidenceTruth = initialEvidence.truth
        self.powerEvidenceAvailability = initialPowerEvidence.availability
        self.connectionGeneration = initialEvidence.connectionGeneration
        self.lastTelemetryUptimeNanoseconds = initialEvidence.lastTelemetryUptimeNanoseconds
        self.lastPowerUptimeNanoseconds = initialPowerEvidence.lastPowerUptimeNanoseconds
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

    private static func initialSpeedEvidence(
        for state: VehicleState
    ) -> (
        truth: SpeedEvidenceLiveTruth,
        connectionGeneration: UInt64,
        lastTelemetryUptimeNanoseconds: UInt64
    ) {
        var truth = SpeedEvidenceLiveTruth()
        let hasSpeed = state.speedKilometersPerHour.map { $0.isFinite && $0 >= 0 } ?? false
        let needsSyntheticContinuity = state.connection == .connected || hasSpeed
        guard needsSyntheticContinuity else {
            return (truth, 0, 0)
        }

        let generation = SpeedEvidenceConnectionGeneration(rawValue: 1)
        guard case .success = truth.beginConnectedGeneration(generation) else {
            return (truth, 0, 0)
        }

        var lastUptime: UInt64 = 0
        if let speed = state.speedKilometersPerHour, speed.isFinite, speed >= 0 {
            let uptime = DispatchTime.now().uptimeNanoseconds
            if let token = truth.activeContinuityToken,
               let sample = try? SpeedTelemetrySample(
                   source: .simulatorQA,
                   provenance: .absoluteMeasurement,
                   metersPerSecond: speed / 3.6,
                   receivedAtUptimeNanoseconds: uptime,
                   receivedAtDate: .now
               ) {
                _ = truth.accept(sample, attributedTo: token)
                lastUptime = uptime
            }
        }

        if state.connection != .connected {
            _ = truth.endConnectedGeneration(generation)
        }

        return (truth, 1, lastUptime)
    }

    private static func initialPowerEvidence(
        for state: VehicleState,
        profile: VehicleProfile
    ) -> (
        availability: SimulatorPowerEvidenceAvailability,
        lastPowerUptimeNanoseconds: UInt64
    ) {
        guard profile == .simulatorQA,
              profile.capabilities.supportsPowerWatts,
              state.connection == .connected,
              let watts = state.powerWatts else {
            return (.unavailable, 0)
        }

        let uptime = DispatchTime.now().uptimeNanoseconds
        guard let sample = SimulatorPowerEvidenceSample(
            watts: Double(watts),
            receivedAtUptimeNanoseconds: uptime
        ) else {
            return (.unavailable, 0)
        }
        return (.live(sample), uptime)
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

    /// Availability is state, not a raw packet stream. Registration and the
    /// initial replay occur in this actor turn, so consumers cannot miss a
    /// demotion in a snapshot -> subscribe gap. Newest-only buffering prevents
    /// a slow consumer from replaying obsolete `.live` state after a newer
    /// retained/unavailable transition already exists at the source.
    public func speedEvidenceUpdates() -> AsyncStream<SpeedEvidenceAvailability> {
        let id = UUID()
        let current = speedEvidenceTruth.availability
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            speedEvidenceContinuations[id] = continuation
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSpeedEvidenceContinuation(id) }
            }
        }
    }

    /// Synthetic power availability is current source-owned state, not an event
    /// replay. A late subscriber receives the exact current live/retained/
    /// unavailable classification with the original power receipt identity.
    public func simulatorPowerEvidenceUpdates() -> AsyncStream<SimulatorPowerEvidenceAvailability> {
        let id = UUID()
        let current = powerEvidenceAvailability
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            powerEvidenceContinuations[id] = continuation
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removePowerEvidenceContinuation(id) }
            }
        }
    }

    public func simulatorPowerEvidenceSnapshot() -> SimulatorPowerEvidenceAvailability {
        powerEvidenceAvailability
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
        do {
            try await Task.sleep(nanoseconds: 220_000_000)
        } catch {
            cancelConnectionAttemptIfCurrent(attemptGeneration)
            return
        }
        guard !Task.isCancelled else {
            cancelConnectionAttemptIfCurrent(attemptGeneration)
            return
        }
        guard connectionGeneration == attemptGeneration, state.connection == .connecting else { return }
        state.connection = .connected
        hydrateMissingVehicleDataAfterSuccessfulConnection()
        beginSpeedEvidenceForConnectedGeneration(attemptGeneration)
        if let speed = state.speedKilometersPerHour {
            recordSyntheticSpeedObservation(speed, publishRawTelemetry: true)
        }
        if let watts = state.powerWatts {
            recordSyntheticPowerObservation(Double(watts))
        }
        state.lastUpdated = .now
        publish()
    }

    public func disconnect() async {
        demoteSpeedEvidenceForConnectionLoss()
        demotePowerEvidenceForConnectionLoss()
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
        try ensureQualifiedLiveStoppedSpeed()
        try await acknowledgeLatency(expectedConnectionGeneration: generation)
        try ensureQualifiedLiveStoppedSpeed()
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
        guard speedKilometersPerHour.isFinite,
              speedKilometersPerHour >= 0,
              elapsedSeconds.isFinite,
              elapsedSeconds >= 0 else { return }

        let speed = speedKilometersPerHour
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

        recordSyntheticSpeedObservation(speed, publishRawTelemetry: true)
        if let watts = state.powerWatts {
            recordSyntheticPowerObservation(Double(watts))
        }
        state.lastUpdated = .now
        publish()
    }

    /// Explicit Simulator-only loss of speed observation continuity. The cached
    /// `VehicleState` speed remains available as retained presentation data, but
    /// stopped-only authority is retired until a new synthetic observation.
    public func simulateSpeedEvidenceGap() {
        guard let token = speedEvidenceTruth.activeContinuityToken else { return }
        guard case .success = speedEvidenceTruth.markEvidenceGap(after: token) else { return }
        publishSpeedEvidenceAvailability()
    }

    /// Explicit Simulator-only power observation gap. Cached aggregate watts are
    /// left untouched, while field currentness is demoted until the source itself
    /// records another synthetic power observation.
    public func simulatePowerEvidenceGap() {
        demotePowerEvidenceForConnectionLoss()
    }

    public func simulateConnectionIssue(_ issue: VehicleConnectionIssue?) {
        demoteSpeedEvidenceForConnectionLoss()
        demotePowerEvidenceForConnectionLoss()
        connectionGeneration &+= 1
        state.connectionIssue = issue
        state.connection = .disconnected
        // Connection failures carry no new telemetry evidence. Keep the last
        // confirmed vehicle values intact and let connection state mark them stale.
        publish()
    }

    public func simulateConnectionDrop() {
        demoteSpeedEvidenceForConnectionLoss()
        demotePowerEvidenceForConnectionLoss()
        connectionGeneration &+= 1
        state.connection = .reconnecting
        state.lastUpdated = .now
        publish()
    }

    public func simulateReconnected() {
        demoteSpeedEvidenceForConnectionLoss()
        demotePowerEvidenceForConnectionLoss()
        connectionGeneration &+= 1
        state.connectionIssue = nil
        state.connection = .connected
        beginSpeedEvidenceForConnectedGeneration(connectionGeneration)
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

    private func cancelConnectionAttemptIfCurrent(_ attemptGeneration: UInt64) {
        guard connectionGeneration == attemptGeneration, state.connection == .connecting else { return }
        demoteSpeedEvidenceForConnectionLoss()
        demotePowerEvidenceForConnectionLoss()
        connectionGeneration &+= 1
        state.connection = .disconnected
        publish()
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

    private func ensureQualifiedLiveStoppedSpeed() throws {
        guard profile == .simulatorQA,
              case let .live(sample) = speedEvidenceTruth.availability,
              sample.source == .simulatorQA,
              sample.provenance == .absoluteMeasurement else {
            throw ScooterCommandError.commandRejected
        }
        let speedKilometersPerHour = sample.kilometersPerHour
        guard speedKilometersPerHour.isFinite,
              speedKilometersPerHour >= 0,
              speedKilometersPerHour < 0.5 else {
            throw ScooterCommandError.commandRejected
        }
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

    private func beginSpeedEvidenceForConnectedGeneration(_ rawGeneration: UInt64) {
        let generation = SpeedEvidenceConnectionGeneration(rawValue: rawGeneration)
        _ = speedEvidenceTruth.beginConnectedGeneration(generation)
        publishSpeedEvidenceAvailability()
    }

    private func demoteSpeedEvidenceForConnectionLoss() {
        guard let generation = speedEvidenceTruth.activeConnectionGeneration else { return }
        _ = speedEvidenceTruth.endConnectedGeneration(generation)
        publishSpeedEvidenceAvailability()
    }

    private func demotePowerEvidenceForConnectionLoss() {
        guard case let .live(sample) = powerEvidenceAvailability else { return }
        powerEvidenceAvailability = .retained(sample)
        publishPowerEvidenceAvailability()
    }

    private func recordSyntheticSpeedObservation(
        _ speedKilometersPerHour: Double,
        publishRawTelemetry: Bool
    ) {
        guard speedKilometersPerHour.isFinite, speedKilometersPerHour >= 0,
              let token = speedEvidenceTruth.activeContinuityToken,
              let sample = makeSyntheticSpeedSample(speedKilometersPerHour: speedKilometersPerHour) else {
            return
        }

        if case .success = speedEvidenceTruth.accept(sample, attributedTo: token) {
            publishSpeedEvidenceAvailability()
        }
        if publishRawTelemetry {
            publishSpeedTelemetry(sample)
        }
    }

    private func recordSyntheticPowerObservation(_ watts: Double) {
        guard profile == .simulatorQA,
              profile.capabilities.supportsPowerWatts,
              state.connection == .connected,
              let sample = makeSyntheticPowerSample(watts: watts) else {
            return
        }
        powerEvidenceAvailability = .live(sample)
        publishPowerEvidenceAvailability()
    }

    private func makeSyntheticSpeedSample(
        speedKilometersPerHour: Double
    ) -> SpeedTelemetrySample? {
        let currentUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        let sampleUptimeNanoseconds: UInt64
        if currentUptimeNanoseconds > lastTelemetryUptimeNanoseconds {
            sampleUptimeNanoseconds = currentUptimeNanoseconds
        } else if lastTelemetryUptimeNanoseconds < UInt64.max {
            sampleUptimeNanoseconds = lastTelemetryUptimeNanoseconds + 1
        } else {
            return nil
        }

        guard let sample = try? SpeedTelemetrySample(
            source: .simulatorQA,
            provenance: .absoluteMeasurement,
            metersPerSecond: speedKilometersPerHour / 3.6,
            receivedAtUptimeNanoseconds: sampleUptimeNanoseconds,
            receivedAtDate: .now
        ) else {
            return nil
        }
        lastTelemetryUptimeNanoseconds = sampleUptimeNanoseconds
        return sample
    }

    private func makeSyntheticPowerSample(watts: Double) -> SimulatorPowerEvidenceSample? {
        guard watts.isFinite, watts >= 0 else { return nil }
        let currentUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        let sampleUptimeNanoseconds: UInt64
        if currentUptimeNanoseconds > lastPowerUptimeNanoseconds {
            sampleUptimeNanoseconds = currentUptimeNanoseconds
        } else if lastPowerUptimeNanoseconds < UInt64.max {
            sampleUptimeNanoseconds = lastPowerUptimeNanoseconds + 1
        } else {
            return nil
        }

        guard let sample = SimulatorPowerEvidenceSample(
            watts: watts,
            receivedAtUptimeNanoseconds: sampleUptimeNanoseconds
        ) else {
            return nil
        }
        lastPowerUptimeNanoseconds = sampleUptimeNanoseconds
        return sample
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

    private func publishSpeedEvidenceAvailability() {
        let availability = speedEvidenceTruth.availability
        for continuation in speedEvidenceContinuations.values {
            continuation.yield(availability)
        }
    }

    private func publishPowerEvidenceAvailability() {
        for continuation in powerEvidenceContinuations.values {
            continuation.yield(powerEvidenceAvailability)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func removeSpeedTelemetryContinuation(_ id: UUID) {
        speedTelemetryContinuations[id] = nil
    }

    private func removeSpeedEvidenceContinuation(_ id: UUID) {
        speedEvidenceContinuations[id] = nil
    }

    private func removePowerEvidenceContinuation(_ id: UUID) {
        powerEvidenceContinuations[id] = nil
    }
}
