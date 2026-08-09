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
    @ObservationIgnored private var latestSpeedEvidenceRefreshID: UUID?
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

                let refreshID = self.beginSpeedEvidenceRefresh()
                if state.connection == .connected, let speedEvidenceProvider {
                    // The state and evidence streams are independent. Re-read
                    // source-owned currentness before publishing a connected
                    // state so an already-delivered old `.live` element cannot
                    // combine with a newer reconnect and resurrect authority.
                    let currentAvailability = await speedEvidenceProvider.speedEvidenceSnapshot()
                    guard !Task.isCancelled else { break }
                    self.state = state
                    self.commitSpeedEvidenceRefresh(currentAvailability, id: refreshID)
                } else {
                    self.state = state
                    self.commitSpeedEvidenceRefresh(.unavailable, id: refreshID)
                }
            }
        }

        if let speedEvidenceProvider {
            speedEvidenceTask = Task { [weak self, speedEvidenceProvider] in
                let stream = await speedEvidenceProvider.speedEvidenceUpdates()
                for await _ in stream {
                    guard let self, !Task.isCancelled else { return }

                    // A stream value may have been handed to this task before a
                    // newer source transition reached the independent state task.
                    // Treat the value only as a wake-up signal and query current
                    // source truth again at the point of app projection.
                    let refreshID = self.beginSpeedEvidenceRefresh()
                    let currentAvailability = await speedEvidenceProvider.speedEvidenceSnapshot()
                    guard !Task.isCancelled else { return }
                    self.commitSpeedEvidenceRefresh(currentAvailability, id: refreshID)
                }

                // An ended acquisition stream cannot leave its last `.live`
                // sample authorized indefinitely. Cancellation/deinit needs no
                // state write; any real unexpected/normal end fails closed.
                guard let self, !Task.isCancelled else { return }
                let refreshID = self.beginSpeedEvidenceRefresh()
                self.commitSpeedEvidenceRefresh(.unavailable, id: refreshID)
            }
        } else {
            let refreshID = beginSpeedEvidenceRefresh()
            commitSpeedEvidenceRefresh(.unavailable, id: refreshID)
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

    private func beginSpeedEvidenceRefresh() -> UUID {
        let id = UUID()
        latestSpeedEvidenceRefreshID = id
        return id
    }

    private func commitSpeedEvidenceRefresh(
        _ availability: SpeedEvidenceAvailability,
        id: UUID
    ) {
        guard latestSpeedEvidenceRefreshID == id else { return }
        speedEvidenceAvailability = availability
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
