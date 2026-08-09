import Foundation
import Observation

/// Presentation timing is injected explicitly so Simulator QA can exercise the
/// speed animation without silently choosing an unverified production hardware cadence.
struct SpeedInstrumentInterpolationPolicy: Equatable, Sendable {
    let minimumTransitionNanoseconds: UInt64
    let maximumContinuousSampleIntervalNanoseconds: UInt64
    let intervalFraction: Double

    static let disabled = SpeedInstrumentInterpolationPolicy(
        minimumTransitionNanoseconds: 0,
        maximumContinuousSampleIntervalNanoseconds: 0,
        intervalFraction: 0
    )

    /// QA-only profile. These values are not a claim about any physical scooter hardware.
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

    var state: VehicleState
    /// Source-owned currentness for speed. Cached `VehicleState` speed never
    /// promotes this value by itself.
    private(set) var speedEvidenceAvailability: SpeedEvidenceAvailability = .unavailable
    var pendingCommands: Set<PendingCommand> = []
    var pendingRideMode: RideMode?
    var pendingCruiseValue: Bool?
    var pendingStartMode: StartMode?
    var pendingSpeedLimit: (slot: SpeedLimitSlot, kilometersPerHour: Int)?
    var lastErrorMessage: String?

    var isVehicleCommandPending: Bool {
        pendingCommands.contains { $0 != .connect }
    }

    /// Simulator-only qualified live speed for truth-sensitive QA/control gates.
    /// Aggregate connection can only remove authority here; it never promotes a
    /// cached number into current speed evidence.
    var simulatorQualifiedLiveSpeedKilometersPerHour: Double? {
        guard state.connection == .connected,
              profile == .simulatorQA,
              case let .live(sample) = speedEvidenceAvailability,
              sample.source == .simulatorQA else {
            return nil
        }
        let speed = sample.kilometersPerHour
        guard speed.isFinite, speed >= 0 else { return nil }
        return speed
    }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var speedEvidenceTask: Task<Void, Never>?
    @ObservationIgnored private var speedEvidenceConsumerAuthority = SpeedEvidenceConsumerAuthority()
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private let shouldAutoConnectOnStart: Bool

    init(
        service: any ScooterService,
        initialState: VehicleState? = nil,
        shouldAutoConnectOnStart: Bool = true,
        speedInstrumentInterpolationPolicy: SpeedInstrumentInterpolationPolicy = .disabled
    ) {
        self.service = service
        self.profile = service.profile
        self.shouldAutoConnectOnStart = shouldAutoConnectOnStart
        self.speedInstrumentInterpolationPolicy = speedInstrumentInterpolationPolicy
        self.state = initialState ?? VehicleState(
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
    }

    deinit {
        updatesTask?.cancel()
        speedEvidenceTask?.cancel()
    }

    func start() async {
        guard !didStart else { return }
        didStart = true

        let speedEvidenceProvider = service as? any SpeedEvidenceProvider

        updatesTask = Task { [weak self, service, speedEvidenceProvider] in
            let stream = await service.stateUpdates()
            for await state in stream {
                guard let self, !Task.isCancelled else { break }
                let previousConnection = self.state.connection
                self.state = state

                guard let speedEvidenceProvider else {
                    if state.connection != .connected {
                        self.invalidateSpeedEvidenceAuthority()
                    }
                    continue
                }

                // A transport transition immediately revokes any previously
                // projected speed authority. Revalidation below samples current
                // service state first and current source-owned speed state second.
                // The consumer authority token also prevents an older suspended
                // refresh from publishing after this transition has been observed.
                if state.connection != previousConnection {
                    self.invalidateSpeedEvidenceAuthority()
                    await self.refreshSpeedEvidenceAuthority(using: speedEvidenceProvider)
                } else if state.connection != .connected {
                    self.invalidateSpeedEvidenceAuthority()
                }
            }
        }

        if let speedEvidenceProvider {
            speedEvidenceTask = Task { [weak self, speedEvidenceProvider] in
                let stream = await speedEvidenceProvider.speedEvidenceUpdates()
                for await _ in stream {
                    guard let self, !Task.isCancelled else { return }

                    // The dequeued value is only a trigger. It may already be
                    // obsolete by the time this task runs, so current app authority
                    // is rebuilt from source-owned snapshots rather than copied
                    // directly from that event.
                    await self.refreshSpeedEvidenceAuthority(using: speedEvidenceProvider)
                }

                // An ended acquisition stream cannot leave its last `.live`
                // sample authorized indefinitely. Cancellation/deinit needs no
                // state write; any real unexpected/normal end fails closed.
                guard let self, !Task.isCancelled else { return }
                self.invalidateSpeedEvidenceAuthority()
            }
        } else {
            speedEvidenceAvailability = .unavailable
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

    /// Retires current speed authority and invalidates every in-flight refresh.
    private func invalidateSpeedEvidenceAuthority() {
        speedEvidenceConsumerAuthority.invalidate()
        speedEvidenceAvailability = speedEvidenceConsumerAuthority.availability
    }

    /// Rebuilds the app projection from current source-owned state instead of
    /// trusting whichever availability event happened to wake the consumer.
    ///
    /// Service connection is sampled before field availability. If a newer
    /// connection transition is observed by either consumer task while these
    /// awaits are suspended, its invalidation rotates the opaque refresh token;
    /// this older refresh then cannot publish when it resumes.
    private func refreshSpeedEvidenceAuthority(
        using speedEvidenceProvider: any SpeedEvidenceProvider
    ) async {
        let refreshToken = speedEvidenceConsumerAuthority.beginRefresh()
        speedEvidenceAvailability = speedEvidenceConsumerAuthority.availability

        let connection = await service.snapshot().connection
        let currentAvailability = await speedEvidenceProvider.speedEvidenceSnapshot()

        guard !Task.isCancelled else { return }
        guard speedEvidenceConsumerAuthority.commit(
            currentAvailability,
            connectionIsConnected: connection == .connected,
            for: refreshToken
        ) else {
            return
        }
        speedEvidenceAvailability = speedEvidenceConsumerAuthority.availability
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
