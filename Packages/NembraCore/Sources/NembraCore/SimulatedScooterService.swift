import Foundation

public actor SimulatedScooterService: ScooterService, SpeedEvidenceProvider {
    private var state: VehicleState
    private var continuations: [UUID: AsyncStream<VehicleState>.Continuation] = [:]
    private var speedTelemetryContinuations: [UUID: AsyncStream<SpeedTelemetrySample>.Continuation] = [:]
    private var speedEvidenceContinuations: [UUID: AsyncStream<SpeedEvidenceAvailability>.Continuation] = [:]
    private var commandInProgress = false
    private var connectionGeneration: UInt64 = 0
    private var speedEvidenceTruth: SpeedEvidenceLiveTruth
    private var nextSpeedObservationSequence: UInt64
    private var lastSpeedObservationUptimeNanoseconds: UInt64?

    public let profile: VehicleProfile
    private let commandLatencyNanoseconds: UInt64

    public init(
        profile: VehicleProfile = .simulatorQA,
        initialState: VehicleState = .simulatorFixture(),
        commandLatencyNanoseconds: UInt64 = 250_000_000
    ) {
        self.profile = profile
        self.state = initialState
        self.commandLatencyNanoseconds = commandLatencyNanoseconds
        let seededTruth = Self.makeInitialSpeedEvidenceTruth(from: initialState)
        self.speedEvidenceTruth = seededTruth.truth
        self.nextSpeedObservationSequence = seededTruth.nextSequence
        self.lastSpeedObservationUptimeNanoseconds = seededTruth.lastUptime
    }

    public static func state(for scenario: SimulationScenario) -> VehicleState {
        switch scenario {
        case .connectedStopped:
            return VehicleState(
                connection: .connected,
                connectionIssue: nil,
                batteryPercent: 73,
                speedKilometersPerHour: 0,
                odometerKilometers: 1_842.7,
                tripKilometers: 0,
                rideMode: .drive,
                startMode: .kick,
                speedLimitsKilometersPerHour: [.drive: 19],
                isLocked: false,
                isHeadlightOn: true,
                isCruiseEnabled: false,
                powerWatts: 0,
                currentAmps: nil
            )
        case .connectedMoving:
            return VehicleState(
                connection: .connected,
                connectionIssue: nil,
                batteryPercent: 68,
                speedKilometersPerHour: 17.5,
                odometerKilometers: 1_845.4,
                tripKilometers: 6.8,
                rideMode: .drive,
                startMode: .kick,
                speedLimitsKilometersPerHour: [.drive: 19],
                isLocked: false,
                isHeadlightOn: true,
                isCruiseEnabled: true,
                powerWatts: 312,
                currentAmps: nil
            )
        case .connecting:
            return VehicleState(
                connection: .connecting,
                connectionIssue: nil,
                batteryPercent: 71,
                speedKilometersPerHour: 0,
                odometerKilometers: 1_842.7,
                tripKilometers: 0,
                rideMode: .drive,
                startMode: .kick,
                speedLimitsKilometersPerHour: [.drive: 19],
                isLocked: false,
                isHeadlightOn: false,
                isCruiseEnabled: false,
                powerWatts: 0,
                currentAmps: nil
            )
        case .disconnectedRetained:
            return VehicleState(
                connection: .disconnected,
                connectionIssue: .linkLost,
                batteryPercent: 64,
                speedKilometersPerHour: 12.4,
                odometerKilometers: 1_846.2,
                tripKilometers: 7.6,
                rideMode: .drive,
                startMode: .kick,
                speedLimitsKilometersPerHour: [.drive: 19],
                isLocked: false,
                isHeadlightOn: true,
                isCruiseEnabled: false,
                powerWatts: 118,
                currentAmps: nil
            )
        case .connectionFailed:
            return VehicleState(
                connection: .disconnected,
                connectionIssue: .connectionFailed,
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

    public static func simulatorQADriveCycleState(for frameIndex: Int) -> VehicleState {
        let clampedIndex = max(frameIndex, 0)
        let phase = Double(clampedIndex % 360) / 360.0
        let speedKilometersPerHour: Double
        let powerWatts: Double

        switch phase {
        case 0..<0.2:
            let t = phase / 0.2
            speedKilometersPerHour = 17.5 * t
            powerWatts = 420 * t
        case 0.2..<0.55:
            let t = (phase - 0.2) / 0.35
            speedKilometersPerHour = 17.5 + (2.5 * t)
            powerWatts = 420 - (130 * t)
        case 0.55..<0.78:
            speedKilometersPerHour = 20
            powerWatts = 290
        default:
            let t = (phase - 0.78) / 0.22
            speedKilometersPerHour = max(0, 20 * (1 - t))
            powerWatts = max(0, 290 * (1 - t))
        }

        return VehicleState(
            connection: .connected,
            connectionIssue: nil,
            batteryPercent: 68,
            speedKilometersPerHour: speedKilometersPerHour,
            odometerKilometers: 1_845.4,
            tripKilometers: 6.8,
            rideMode: .drive,
            startMode: .kick,
            speedLimitsKilometersPerHour: [.drive: 19],
            isLocked: false,
            isHeadlightOn: true,
            isCruiseEnabled: phase >= 0.4 && phase < 0.7,
            powerWatts: powerWatts,
            currentAmps: nil
        )
    }

    public func installSimulatorQADriveCycleFrame(_ frameIndex: Int) {
        state = Self.simulatorQADriveCycleState(for: frameIndex)
        guard state.connection == .connected else {
            demoteSpeedEvidenceForConnectionLoss()
            publish()
            return
        }
        let generation = ensureConnectedGeneration()
        beginSpeedEvidenceForConnectedGeneration(generation)
        if let speed = state.speedKilometersPerHour {
            recordSyntheticSpeedObservation(speed, publishRawTelemetry: true)
        }
        state.lastUpdated = .now
        publish()
    }

    public func simulateRide(speedKilometersPerHour: Double, elapsedSeconds: TimeInterval) {
        guard state.connection == .connected else { return }
        let generation = ensureConnectedGeneration()
        beginSpeedEvidenceForConnectedGeneration(generation)
        state.speedKilometersPerHour = speedKilometersPerHour
        state.tripKilometers = (state.tripKilometers ?? 0) + speedKilometersPerHour * elapsedSeconds / 3_600
        recordSyntheticSpeedObservation(speedKilometersPerHour, publishRawTelemetry: true)
        state.lastUpdated = .now
        publish()
    }

    public func simulateConnectionDrop() {
        demoteSpeedEvidenceForConnectionLoss()
        connectionGeneration &+= 1
        state.connection = .disconnected
        state.connectionIssue = .linkLost
        state.lastUpdated = .now
        publish()
    }

    public func simulateConnectionFailure() {
        demoteSpeedEvidenceForConnectionLoss()
        connectionGeneration &+= 1
        state.connection = .disconnected
        state.connectionIssue = .connectionFailed
        state.batteryPercent = nil
        state.speedKilometersPerHour = nil
        state.odometerKilometers = nil
        state.tripKilometers = nil
        state.rideMode = nil
        state.startMode = nil
        state.speedLimitsKilometersPerHour = [:]
        state.isLocked = nil
        state.isHeadlightOn = nil
        state.isCruiseEnabled = nil
        state.powerWatts = nil
        state.currentAmps = nil
        state.lastUpdated = .now
        publish()
    }

    public func simulateReconnected() {
        connectionGeneration &+= 1
        let generation = connectionGeneration
        state.connection = .connected
        state.connectionIssue = nil
        hydrateMissingVehicleDataAfterSuccessfulConnection()
        beginSpeedEvidenceForConnectedGeneration(generation)
        state.lastUpdated = .now
        publish()
    }

    public func simulateSpeedEvidenceGap() {
        guard state.connection == .connected else { return }
        guard speedEvidenceTruth.invalidateLiveEvidence() else { return }
        publishSpeedEvidenceAvailability()
    }

    /// Deterministic adversarial hook: preserves the aggregate connected state
    /// while ending the current speed-source continuity generation. This models
    /// the speed characteristic/source becoming unavailable without pretending
    /// that the whole vehicle disconnected or that a zero-speed packet arrived.
    public func simulateSpeedSourceContinuityLossWhileConnected() {
        guard state.connection == .connected else { return }
        guard let token = speedEvidenceTruth.activeContinuityToken else { return }
        guard speedEvidenceTruth.endContinuity(token) else { return }
        publishSpeedEvidenceAvailability()
    }

    /// Deterministic adversarial hook: starts a fresh speed-source continuity
    /// generation while aggregate transport remains connected. Currentness is
    /// still retained/unavailable until a new observation is accepted in this
    /// generation.
    public func simulateSpeedSourceContinuityRestartWhileConnected() {
        guard state.connection == .connected else { return }
        _ = speedEvidenceTruth.beginContinuity()
        publishSpeedEvidenceAvailability()
    }

    public func simulateFreshSpeedObservation(_ speedKilometersPerHour: Double) {
        guard state.connection == .connected else { return }
        recordSyntheticSpeedObservation(speedKilometersPerHour, publishRawTelemetry: true)
        state.lastUpdated = .now
        publish()
    }

    private static func makeInitialSpeedEvidenceTruth(
        from state: VehicleState
    ) -> (truth: SpeedEvidenceLiveTruth, nextSequence: UInt64, lastUptime: UInt64?) {
        var truth = SpeedEvidenceLiveTruth(source: .simulatorQA)
        guard state.connection == .connected else {
            return (truth, 0, nil)
        }

        let generation = UInt64(1)
        guard let token = truth.beginConnectedGeneration(generation) else {
            return (truth, 0, nil)
        }

        var lastUptime: UInt64?
        if let speed = state.speedKilometersPerHour, speed.isFinite, speed >= 0 {
            let uptime = DispatchTime.now().uptimeNanoseconds
            if let sample = try? SpeedTelemetrySample(
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

    /// Source-current speed authority for truth-sensitive cross-stream joins.
    /// Unlike the protocol's generic replay-based default, this actor already
    /// owns the canonical currentness state and can expose it directly without
    /// allocating a transient continuation for every refresh.
    public func speedEvidenceSnapshot() -> SpeedEvidenceAvailability {
        speedEvidenceTruth.availability
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
        state.lastUpdated = .now
        publish()
    }

    public func disconnect() async {
        demoteSpeedEvidenceForConnectionLoss()
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
        guard profile.capabilities.supportedStartModes.contains(mode) else {
            throw ScooterCommandError.unsupportedCapability
        }
        let generation = try beginCommand()
        defer { finishCommand() }
        try await acknowledgeLatency(expectedConnectionGeneration: generation)
        state.startMode = mode
        publish()
    }

    public func setSpeedLimit(kilometersPerHour: Int, slot: SpeedLimitSlot) async throws {
        guard profile.capabilities.supportsSpeedLimit else { throw ScooterCommandError.unsupportedCapability }
        guard profile.capabilities.speedLimitSlots.contains(slot) else {
            throw ScooterCommandError.unsupportedSpeedLimitSlot(slot)
        }
        guard kilometersPerHour > 0, kilometersPerHour <= 80 else {
            throw ScooterCommandError.valueOutOfRange
        }
        let generation = try beginCommand()
        defer { finishCommand() }
        try await acknowledgeLatency(expectedConnectionGeneration: generation)
        state.speedLimitsKilometersPerHour[slot] = kilometersPerHour
        publish()
    }

    private func beginCommand() throws -> UInt64 {
        guard state.connection == .connected else { throw ScooterCommandError.disconnected }
        guard !commandInProgress else { throw ScooterCommandError.commandInProgress }
        commandInProgress = true
        return connectionGeneration
    }

    private func finishCommand() {
        commandInProgress = false
    }

    private func acknowledgeLatency(expectedConnectionGeneration: UInt64) async throws {
        do {
            try await Task.sleep(nanoseconds: commandLatencyNanoseconds)
        } catch {
            throw ScooterCommandError.commandRejected
        }
        guard !Task.isCancelled else { throw ScooterCommandError.commandRejected }
        guard state.connection == .connected,
              connectionGeneration == expectedConnectionGeneration else {
            throw ScooterCommandError.disconnected
        }
    }

    private func ensureQualifiedLiveStoppedSpeed() throws {
        guard let sample = speedEvidenceTruth.qualifiedLiveSample,
              sample.source == .simulatorQA,
              sample.kilometersPerHour.isFinite,
              sample.kilometersPerHour >= 0,
              sample.kilometersPerHour <= 0.1 else {
            throw ScooterCommandError.commandRejected
        }
    }

    private func hydrateMissingVehicleDataAfterSuccessfulConnection() {
        let defaults = Self.state(for: .connectedStopped)
        if state.batteryPercent == nil { state.batteryPercent = defaults.batteryPercent }
        if state.speedKilometersPerHour == nil { state.speedKilometersPerHour = defaults.speedKilometersPerHour }
        if state.odometerKilometers == nil { state.odometerKilometers = defaults.odometerKilometers }
        if state.tripKilometers == nil { state.tripKilometers = defaults.tripKilometers }
        if state.rideMode == nil { state.rideMode = defaults.rideMode }
        if state.startMode == nil { state.startMode = defaults.startMode }
        if state.speedLimitsKilometersPerHour.isEmpty {
            state.speedLimitsKilometersPerHour = defaults.speedLimitsKilometersPerHour
        }
        if state.isLocked == nil { state.isLocked = defaults.isLocked }
        if state.isHeadlightOn == nil { state.isHeadlightOn = defaults.isHeadlightOn }
        if state.isCruiseEnabled == nil { state.isCruiseEnabled = defaults.isCruiseEnabled }
        if state.powerWatts == nil { state.powerWatts = defaults.powerWatts }
    }

    private func ensureConnectedGeneration() -> UInt64 {
        if connectionGeneration == 0 {
            connectionGeneration = 1
        }
        return connectionGeneration
    }

    private func beginSpeedEvidenceForConnectedGeneration(_ generation: UInt64) {
        if speedEvidenceTruth.connectedGeneration != generation || speedEvidenceTruth.activeContinuityToken == nil {
            _ = speedEvidenceTruth.beginConnectedGeneration(generation)
        }
    }

    private func demoteSpeedEvidenceForConnectionLoss() {
        if let generation = speedEvidenceTruth.connectedGeneration {
            _ = speedEvidenceTruth.endConnectedGeneration(generation)
        } else {
            _ = speedEvidenceTruth.invalidateLiveEvidence()
        }
        publishSpeedEvidenceAvailability()
    }

    private func recordSyntheticSpeedObservation(
        _ speedKilometersPerHour: Double,
        publishRawTelemetry: Bool
    ) {
        guard state.connection == .connected,
              speedKilometersPerHour.isFinite,
              speedKilometersPerHour >= 0 else {
            return
        }
        let generation = ensureConnectedGeneration()
        beginSpeedEvidenceForConnectedGeneration(generation)

        let uptime = nextSpeedObservationUptimeNanoseconds()
        guard let sample = try? SpeedTelemetrySample(
            source: .simulatorQA,
            provenance: .absoluteMeasurement,
            metersPerSecond: speedKilometersPerHour / 3.6,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: .now
        ) else {
            return
        }
        guard let token = speedEvidenceTruth.activeContinuityToken,
              speedEvidenceTruth.accept(sample, attributedTo: token) else {
            return
        }
        nextSpeedObservationSequence &+= 1
        if publishRawTelemetry {
            publishSpeedTelemetry(sample)
        }
        publishSpeedEvidenceAvailability()
    }

    private func nextSpeedObservationUptimeNanoseconds() -> UInt64 {
        let now = DispatchTime.now().uptimeNanoseconds
        let minimumNext = (lastSpeedObservationUptimeNanoseconds ?? 0) &+ 1
        let next = max(now, minimumNext)
        lastSpeedObservationUptimeNanoseconds = next
        return next
    }

    private func publishSpeedTelemetry(_ sample: SpeedTelemetrySample) {
        speedTelemetryContinuations.values.forEach { $0.yield(sample) }
    }

    private func publishSpeedEvidenceAvailability() {
        let availability = speedEvidenceTruth.availability
        speedEvidenceContinuations.values.forEach { $0.yield(availability) }
    }

    private func publish() {
        let current = state
        continuations.values.forEach { $0.yield(current) }
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
}
