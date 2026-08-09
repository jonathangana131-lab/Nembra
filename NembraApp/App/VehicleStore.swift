import Foundation
import Observation

/// Presentation timing is injected explicitly so Simulator QA can exercise the
/// speed animation without silently choosing a production MAXSHOT cadence.
struct SpeedInstrumentInterpolationPolicy: Equatable, Sendable {
    let minimumTransitionNanoseconds: UInt64
    let maximumContinuousSampleIntervalNanoseconds: UInt64
    let intervalFraction: Double

    static let disabled = SpeedInstrumentInterpolationPolicy(
        minimumTransitionNanoseconds: 0,
        maximumContinuousSampleIntervalNanoseconds: 0,
        intervalFraction: 0
    )

    /// QA-only profile. These values are not a claim about MAXSHOT hardware.
    static let simulatorQA = SpeedInstrumentInterpolationPolicy(
        minimumTransitionNanoseconds: 50_000_000,
        maximumContinuousSampleIntervalNanoseconds: 300_000_000,
        intervalFraction: 0.8
    )

    var isEnabled: Bool {
        maximumContinuousSampleIntervalNanoseconds > 0
            && intervalFraction > 0
            && intervalFraction <= 1
    }
}

@MainActor
@Observable
final class VehicleStore {
    enum PendingCommand: Hashable {
        case headlight
        case lock
        case cruise
        case mode
        case startMode
        case speedLimit
        case connect
    }

    let profile: VehicleProfile
    let speedInstrumentInterpolationPolicy: SpeedInstrumentInterpolationPolicy
    private let service: any ScooterService
    private let retainedBatteryStorage: (any RetainedBatterySnapshotStorage)?
    private let batteryObservationAuthority: BatteryObservationAuthority?

    var state: VehicleState
    var pendingCommands: Set<PendingCommand> = []
    var pendingRideMode: RideMode?
    var pendingCruiseValue: Bool?
    var pendingStartMode: StartMode?
    var pendingSpeedLimit: (slot: SpeedLimitSlot, kilometersPerHour: Int)?
    var lastErrorMessage: String?
    private(set) var retainedBatteryObservedAt: Date?
    private(set) var retainedBatteryAuthority: BatteryObservationAuthority?
    private var lastConfirmedBatteryAuthority: BatteryObservationAuthority?

    /// Battery truth is deliberately joined separately from vehicle-wide data
    /// availability. A connected transport does not make an unclassified battery
    /// number display-authoritative. Production keeps `batteryObservationAuthority`
    /// nil until hardware evidence establishes what the ES80 value actually means.
    var batteryDisplayPercent: Int? {
        guard let percent = state.batteryPercent,
              (0...100).contains(percent),
              batteryDisplayAuthority != nil else {
            return nil
        }
        return percent
    }

    /// Authority for the battery value currently eligible for user-facing display.
    /// A connected value requires an explicitly configured current-session authority;
    /// a disconnected value may carry only the authority retained with that snapshot.
    var batteryDisplayAuthority: BatteryObservationAuthority? {
        if state.connection == .connected {
            return batteryObservationAuthority
        }
        return retainedBatteryAuthority
    }

    /// Battery-specific availability. This must be used by Battery/Range consumers
    /// instead of `VehicleState.dataAvailability`, which intentionally describes the
    /// aggregate vehicle state and can be live because of unrelated telemetry.
    var batteryDataAvailability: VehicleDataAvailability {
        guard batteryDisplayPercent != nil else { return .unavailable }
        return state.connection == .connected ? .live : .retained
    }

    var isVehicleCommandPending: Bool {
        pendingCommands.contains { $0 != .connect }
    }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private let shouldAutoConnectOnStart: Bool

    init(
        service: any ScooterService,
        initialState: VehicleState? = nil,
        shouldAutoConnectOnStart: Bool = true,
        speedInstrumentInterpolationPolicy: SpeedInstrumentInterpolationPolicy = .disabled,
        retainedBatteryStorage: (any RetainedBatterySnapshotStorage)? = nil,
        batteryObservationAuthority: BatteryObservationAuthority? = nil
    ) {
        self.service = service
        self.profile = service.profile
        self.shouldAutoConnectOnStart = shouldAutoConnectOnStart
        self.speedInstrumentInterpolationPolicy = speedInstrumentInterpolationPolicy
        self.retainedBatteryStorage = retainedBatteryStorage
        self.batteryObservationAuthority = batteryObservationAuthority

        var resolvedState = initialState ?? VehicleState(
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

        if resolvedState.connection != .connected,
           resolvedState.batteryPercent == nil,
           let snapshot = try? retainedBatteryStorage?.load() {
            resolvedState.batteryPercent = snapshot.percent
            resolvedState.lastUpdated = snapshot.observedAt
            retainedBatteryObservedAt = snapshot.observedAt
            retainedBatteryAuthority = snapshot.authority
            lastConfirmedBatteryAuthority = snapshot.authority
        }

        self.state = resolvedState
    }

    deinit {
        updatesTask?.cancel()
    }

    func start() async {
        guard !didStart else { return }
        didStart = true

        updatesTask = Task { [weak self, service] in
            let stream = await service.stateUpdates()
            for await state in stream {
                guard let self, !Task.isCancelled else { break }
                self.apply(state)
            }
        }

        if shouldAutoConnectOnStart {
            await connect()
        }
    }

    /// Exposes raw speed evidence independently from `VehicleState` so the
    /// Dashboard can animate locally without publishing render frames back into
    /// globally observed vehicle state, ride history, distance, or diagnostics.
    func speedTelemetryUpdates() async -> AsyncStream<SpeedTelemetrySample> {
        await service.speedTelemetryUpdates()
    }

    func connect() async {
        guard !pendingCommands.contains(.connect), !isVehicleCommandPending else { return }
        pendingCommands.insert(.connect)
        lastErrorMessage = nil
        defer { pendingCommands.remove(.connect) }
        await service.connect()
    }

    func setHeadlight(_ enabled: Bool) async {
        guard canBeginVehicleCommand else { return }
        await perform(.headlight) { try await service.setHeadlight(enabled) }
    }

    func setLocked(_ locked: Bool) async {
        guard canBeginVehicleCommand else { return }
        await perform(.lock) { try await service.setLocked(locked) }
    }

    func setCruise(_ enabled: Bool) async {
        guard canBeginVehicleCommand else { return }
        pendingCruiseValue = enabled
        defer { pendingCruiseValue = nil }
        await perform(.cruise) { try await service.setCruise(enabled) }
    }

    func setMode(_ mode: RideMode) async {
        guard canBeginVehicleCommand else { return }
        pendingRideMode = mode
        defer { pendingRideMode = nil }
        await perform(.mode) { try await service.setRideMode(mode) }
    }

    func setStartMode(_ mode: StartMode) async {
        guard canBeginVehicleCommand else { return }
        pendingStartMode = mode
        defer { pendingStartMode = nil }
        await perform(.startMode) { try await service.setStartMode(mode) }
    }

    func setSpeedLimit(kilometersPerHour: Int, slot: SpeedLimitSlot) async {
        guard canBeginVehicleCommand else { return }
        pendingSpeedLimit = (slot, kilometersPerHour)
        defer { pendingSpeedLimit = nil }
        await perform(.speedLimit) {
            try await service.setSpeedLimit(kilometersPerHour: kilometersPerHour, slot: slot)
        }
    }

    private var canBeginVehicleCommand: Bool {
        !pendingCommands.contains(.connect) && !isVehicleCommandPending
    }

    private func apply(_ incomingState: VehicleState) {
        var nextState = incomingState

        if incomingState.connection == .connected,
           let batteryPercent = incomingState.batteryPercent {
            retainedBatteryObservedAt = nil
            retainedBatteryAuthority = nil

            if let authority = batteryObservationAuthority {
                lastConfirmedBatteryAuthority = authority
                if let snapshot = RetainedBatterySnapshot(
                    percent: batteryPercent,
                    authority: authority,
                    observedAt: incomingState.lastUpdated
                ) {
                    do {
                        try retainedBatteryStorage?.save(snapshot)
                    } catch {
                        // Persistence must never turn confirmed live telemetry into an error state.
                        // The current session remains authoritative even if local continuity storage fails.
                    }
                }
            } else {
                // A new live value with no configured authority must not inherit the provenance
                // of an older retained observation merely because the numeric percent matches.
                lastConfirmedBatteryAuthority = nil
            }
        } else if incomingState.connection != .connected,
                  let previousPercent = state.batteryPercent {
            if incomingState.batteryPercent == nil {
                nextState.batteryPercent = previousPercent
            }

            // Disconnect/reconnect lifecycle events are not battery measurements. Preserve the
            // observation timestamp and authority only when the stale value is the same confirmed
            // value we already held; a different incoming value cannot borrow prior provenance.
            if nextState.batteryPercent == previousPercent,
               let authority = lastConfirmedBatteryAuthority {
                nextState.lastUpdated = state.lastUpdated
                retainedBatteryObservedAt = retainedBatteryObservedAt ?? state.lastUpdated
                retainedBatteryAuthority = authority
            }
        }

        state = nextState
    }

    private func perform(_ command: PendingCommand, operation: () async throws -> Void) async {
        guard command != .connect, canBeginVehicleCommand else { return }
        pendingCommands.insert(command)
        lastErrorMessage = nil
        defer { pendingCommands.remove(command) }

        do {
            try await operation()
        } catch ScooterCommandError.disconnected {
            lastErrorMessage = "Scooter disconnected before the command was confirmed."
        } catch ScooterCommandError.commandRejected {
            lastErrorMessage = "The scooter rejected that command in its current state."
        } catch ScooterCommandError.commandInProgress {
            lastErrorMessage = "Another scooter change is still being confirmed."
        } catch ScooterCommandError.valueOutOfRange {
            lastErrorMessage = "That value is outside the scooter’s verified supported range."
        } catch ScooterCommandError.unsupportedCapability {
            lastErrorMessage = "This scooter does not expose that control."
        } catch ScooterCommandError.unsupportedMode {
            lastErrorMessage = "That ride mode is not supported by this scooter."
        } catch ScooterCommandError.unsupportedSpeedLimitSlot {
            lastErrorMessage = "That speed-limit setting is not supported by this scooter."
        } catch {
            lastErrorMessage = "That change could not be confirmed."
        }
    }
}
