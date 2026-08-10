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

/// App-session currentness after Store-owned negative lifecycle vetoes.
/// Positive authority still originates only in the source-file-sealed
/// `SimulatorPowerEvidenceAvailability`; this type cannot mint a source receipt.
enum SimulatorPowerStoreFencedCurrentness: Equatable, Sendable {
    case unavailable
    case retained
    case live
}

/// Read-only Store projection consumed by Dashboard presentation.
/// The exact immutable source observation is preserved rather than reconstructed.
struct SimulatorPowerStoreFencedProjection: Equatable, Sendable {
    let currentness: SimulatorPowerStoreFencedCurrentness
    let observation: SimulatorPowerObservation?

    static let unavailable = SimulatorPowerStoreFencedProjection(
        currentness: .unavailable,
        observation: nil
    )

    fileprivate static func retained(
        _ observation: SimulatorPowerObservation
    ) -> SimulatorPowerStoreFencedProjection {
        SimulatorPowerStoreFencedProjection(
            currentness: .retained,
            observation: observation
        )
    }

    fileprivate static func live(
        _ observation: SimulatorPowerObservation
    ) -> SimulatorPowerStoreFencedProjection {
        SimulatorPowerStoreFencedProjection(
            currentness: .live,
            observation: observation
        )
    }

    private init(
        currentness: SimulatorPowerStoreFencedCurrentness,
        observation: SimulatorPowerObservation?
    ) {
        self.currentness = currentness
        self.observation = observation
    }
}

/// Stateful custody for the Store-facing Simulator propulsion projection.
///
/// Transport loss and source-retained/unavailable transitions fence the exact source
/// receipt that lost LIVE authority. Aggregate reconnect never clears that fence.
/// A replay of the same or an older authentic source receipt therefore cannot become
/// LIVE again; only a strictly newer source receipt can reopen positive authority.
/// This remains Simulator QA software truth only.
struct SimulatorPowerReceiptFenceAuthority: Sendable {
    private struct SourceIdentity: Equatable, Sendable {
        let continuityGeneration: UInt64
        let receiptSequenceNumber: UInt64
        let receivedAtUptimeNanoseconds: UInt64

        init(_ observation: SimulatorPowerObservation) {
            continuityGeneration = observation.continuityGeneration
            receiptSequenceNumber = observation.receiptSequenceNumber
            receivedAtUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
        }
    }

    private enum IdentityComparison {
        case older
        case identical
        case contradictory
        case newer
    }

    private(set) var projection: SimulatorPowerStoreFencedProjection = .unavailable
    private var newestSourceObservation: SimulatorPowerObservation?
    private var negativeAuthorityFenceIdentity: SourceIdentity?
    private var sourceProviderIsAvailable = true

    mutating func applySource(
        _ sourceAvailability: SimulatorPowerEvidenceAvailability,
        transportIsConnected: Bool
    ) {
        switch sourceAvailability.currentness {
        case .unavailable:
            guard sourceAvailability.observation == nil else {
                failClosed()
                return
            }
            failClosed()

        case .retained:
            guard let observation = sourceAvailability.observation else {
                failClosed()
                return
            }
            applyRetainedSource(observation)

        case .live:
            guard let observation = sourceAvailability.observation else {
                failClosed()
                return
            }
            applyLiveSource(observation, transportIsConnected: transportIsConnected)
        }
    }

    /// Must run before aggregate non-connected state is published so the app cannot
    /// transiently expose OFFLINE + LIVE propulsion presentation.
    mutating func transportBecameUnavailable() {
        guard projection.currentness == .live,
              let observation = projection.observation else {
            return
        }
        rememberNegativeFence(for: observation)
        projection = .retained(observation)
    }

    /// Provider termination fails closed and fences the newest accepted receipt so
    /// an already queued older callback cannot resurrect a dead source owner.
    mutating func sourceBecameUnavailable() {
        sourceProviderIsAvailable = false
        failClosed()
    }

    private mutating func applyRetainedSource(_ observation: SimulatorPowerObservation) {
        guard sourceProviderIsAvailable else { return }

        switch compare(observation, to: newestSourceObservation) {
        case .older:
            return
        case .contradictory:
            failClosed()
            return
        case .identical:
            projection = .retained(observation)
            rememberNegativeFence(for: observation)
        case .newer:
            newestSourceObservation = observation
            projection = .retained(observation)
            rememberNegativeFence(for: observation)
        }
    }

    private mutating func applyLiveSource(
        _ observation: SimulatorPowerObservation,
        transportIsConnected: Bool
    ) {
        guard sourceProviderIsAvailable else { return }

        switch compare(observation, to: newestSourceObservation) {
        case .older:
            return
        case .contradictory:
            failClosed()
            return
        case .identical:
            break
        case .newer:
            newestSourceObservation = observation
        }

        guard transportIsConnected else {
            projection = .retained(observation)
            rememberNegativeFence(for: observation)
            return
        }

        if let fence = negativeAuthorityFenceIdentity {
            switch compare(SourceIdentity(observation), to: fence) {
            case .older, .identical:
                if projection.currentness != .unavailable {
                    projection = .retained(observation)
                }
                return
            case .contradictory:
                failClosed()
                return
            case .newer:
                negativeAuthorityFenceIdentity = nil
            }
        }

        projection = .live(observation)
    }

    private mutating func rememberNegativeFence(for observation: SimulatorPowerObservation) {
        let candidate = SourceIdentity(observation)
        guard let current = negativeAuthorityFenceIdentity else {
            negativeAuthorityFenceIdentity = candidate
            return
        }

        switch compare(candidate, to: current) {
        case .newer:
            negativeAuthorityFenceIdentity = candidate
        case .older, .identical:
            break
        case .contradictory:
            projection = .unavailable
        }
    }

    private mutating func failClosed() {
        fenceNewestObservationWithoutRecursion()
        projection = .unavailable
    }

    private mutating func fenceNewestObservationWithoutRecursion() {
        guard let observation = newestSourceObservation else { return }
        let candidate = SourceIdentity(observation)
        guard let current = negativeAuthorityFenceIdentity else {
            negativeAuthorityFenceIdentity = candidate
            return
        }
        if case .newer = compare(candidate, to: current) {
            negativeAuthorityFenceIdentity = candidate
        }
    }

    private func compare(
        _ observation: SimulatorPowerObservation,
        to previous: SimulatorPowerObservation?
    ) -> IdentityComparison {
        guard let previous else { return .newer }

        let identityComparison = compare(
            SourceIdentity(observation),
            to: SourceIdentity(previous)
        )
        if case .identical = identityComparison,
           observation != previous {
            return .contradictory
        }
        return identityComparison
    }

    private func compare(
        _ incoming: SourceIdentity,
        to previous: SourceIdentity
    ) -> IdentityComparison {
        if incoming.continuityGeneration < previous.continuityGeneration {
            return .older
        }
        if incoming.continuityGeneration > previous.continuityGeneration {
            return .newer
        }

        if incoming.receiptSequenceNumber < previous.receiptSequenceNumber {
            return .older
        }
        if incoming.receiptSequenceNumber > previous.receiptSequenceNumber {
            return incoming.receivedAtUptimeNanoseconds > previous.receivedAtUptimeNanoseconds
                ? .newer
                : .contradictory
        }

        if incoming.receivedAtUptimeNanoseconds == previous.receivedAtUptimeNanoseconds {
            return .identical
        }
        return .contradictory
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
    /// True only when the app owns the explicit Simulator QA profile, that profile
    /// declares synthetic power support, and the injected service is the exact
    /// synthetic source actor. Provider conformance or profile metadata alone cannot
    /// transfer source ownership through a forwarding wrapper. This is app capability
    /// authority for mounting Simulator QA instrumentation, not physical ES80 proof.
    let hasSimulatorPowerEvidenceSource: Bool
    private let service: any ScooterService
    private let retainedBatteryStorage: (any RetainedBatterySnapshotStorage)?
    private let batteryObservationAuthority: BatteryObservationAuthority?

    var state: VehicleState
    /// Source-owned currentness for speed. Cached `VehicleState` speed never
    /// promotes this value by itself.
    private(set) var speedEvidenceAvailability: SpeedEvidenceAvailability = .unavailable

    /// Persistent app-session custody for Simulator power. Unlike the previous
    /// read-time join, this remembers negative receipt fences across disconnect /
    /// reconnect so an old authentic LIVE receipt cannot be replayed as current.
    private var simulatorPowerStoreAuthority = SimulatorPowerReceiptFenceAuthority()

    /// The only Store-facing Simulator power authority. Positive state can enter only
    /// through the exact source actor admitted by `hasSimulatorPowerEvidenceSource`.
    var simulatorPowerStoreProjection: SimulatorPowerStoreFencedProjection {
        simulatorPowerStoreAuthority.projection
    }

    var pendingCommands: Set<PendingCommand> = []
    var pendingRideMode: RideMode?
    var pendingCruiseValue: Bool?
    var pendingStartMode: StartMode?
    var pendingSpeedLimit: (slot: SpeedLimitSlot, kilometersPerHour: Int)?
    var lastErrorMessage: String?
    private(set) var retainedBatteryObservedAt: Date?
    private(set) var retainedBatteryAuthority: BatteryObservationAuthority?
    private var lastConfirmedBatteryPercent: Int?
    private var lastConfirmedBatteryObservedAt: Date?
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

    /// Simulator-only qualified live speed for truth-sensitive presentation and
    /// stopped-control admission. Aggregate connection can only remove authority;
    /// it never promotes a cached speed number into current evidence.
    var simulatorQualifiedLiveSpeedKilometersPerHour: Double? {
        guard state.connection == .connected,
              profile == .simulatorQA,
              case let .live(sample) = speedEvidenceAvailability,
              sample.source == .simulatorQA,
              sample.provenance == .absoluteMeasurement else {
            return nil
        }
        let speed = sample.kilometersPerHour
        guard speed.isFinite, speed >= 0 else { return nil }
        return speed
    }

    /// Current software authority for a stopped-only lock request. Physical and
    /// otherwise-unverified profiles intentionally remain unavailable until a
    /// verified source policy exists; the real ES80 capture must establish that.
    var canLockFromCurrentSpeedEvidence: Bool {
        guard let speed = simulatorQualifiedLiveSpeedKilometersPerHour else { return false }
        return speed < 0.5
    }

    var isVehicleCommandPending: Bool {
        pendingCommands.contains { $0 != .connect }
    }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var speedEvidenceTask: Task<Void, Never>?
    @ObservationIgnored private var simulatorPowerEvidenceTask: Task<Void, Never>?
    @ObservationIgnored private var speedEvidenceConsumerAuthority = SpeedEvidenceConsumerAuthority()
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
        self.hasSimulatorPowerEvidenceSource = service.profile == .simulatorQA
            && service.profile.capabilities.supportsPowerWatts
            && service is SimulatedScooterService
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

        // The shared vehicle state is itself a product boundary. Do not let an
        // unclassified transport integer enter it and rely on every downstream
        // screen to remember a separate battery gate. A connected initial value
        // crosses only when its authority is explicit.
        if resolvedState.connection == .connected,
           let percent = resolvedState.batteryPercent,
           AuthoritativeBatteryObservation(
               percent: percent,
               authority: batteryObservationAuthority,
               observedAt: resolvedState.lastUpdated
           ) == nil {
            resolvedState.batteryPercent = nil
        }

        // A disconnected initial state is lifecycle/cache state, not a new battery
        // observation. Never admit an arbitrary disconnected transport integer. The
        // only disconnected battery value that may enter shared state is a validated
        // retained snapshot loaded through the persistence boundary below.
        if resolvedState.connection != .connected {
            resolvedState.batteryPercent = nil
        }

        if resolvedState.connection != .connected,
           let snapshot = try? retainedBatteryStorage?.load() {
            resolvedState.batteryPercent = snapshot.percent
            resolvedState.lastUpdated = snapshot.observedAt
            retainedBatteryObservedAt = snapshot.observedAt
            retainedBatteryAuthority = snapshot.authority
            lastConfirmedBatteryPercent = snapshot.percent
            lastConfirmedBatteryObservedAt = snapshot.observedAt
            lastConfirmedBatteryAuthority = snapshot.authority
        }

        self.state = resolvedState

        // A connected authoritative initial state is already confirmed evidence.
        // Seed the same chronology used by later stream updates so an immediate
        // disconnect cannot discard or re-date it.
        if resolvedState.connection == .connected,
           let percent = resolvedState.batteryPercent,
           let observation = AuthoritativeBatteryObservation(
               percent: percent,
               authority: batteryObservationAuthority,
               observedAt: resolvedState.lastUpdated
           ) {
            lastConfirmedBatteryPercent = observation.percent
            lastConfirmedBatteryObservedAt = observation.observedAt
            lastConfirmedBatteryAuthority = observation.authority
            if let snapshot = observation.retained() {
                try? retainedBatteryStorage?.save(snapshot)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
        speedEvidenceTask?.cancel()
        simulatorPowerEvidenceTask?.cancel()
    }

    func start() async {
        guard !didStart else { return }
        didStart = true

        let speedEvidenceProvider = service as? any SpeedEvidenceProvider
        let simulatorPowerEvidenceProvider: (any SimulatorPowerEvidenceProvider)?
        if hasSimulatorPowerEvidenceSource {
            simulatorPowerEvidenceProvider = service as? any SimulatorPowerEvidenceProvider
        } else {
            simulatorPowerEvidenceProvider = nil
        }

        updatesTask = Task { [weak self, service, speedEvidenceProvider] in
            let stream = await service.stateUpdates()
            for await incomingState in stream {
                guard let self, !Task.isCancelled else { break }
                let previousConnection = self.state.connection

                // Negative power authority is retired before aggregate transport
                // state becomes visible. Reconnect has deliberately no matching
                // positive action; only a strictly newer sealed source receipt may
                // clear the remembered receipt fence.
                if incomingState.connection != .connected {
                    self.simulatorPowerStoreAuthority.transportBecameUnavailable()
                }

                self.apply(incomingState)

                if let speedEvidenceProvider {
                    // Transport transitions revoke projected field authority first.
                    // Revalidation samples current service state and then the current
                    // source-owned speed snapshot; connection alone never revives a
                    // cached pre-gap speed.
                    if incomingState.connection != previousConnection {
                        self.invalidateSpeedEvidenceAuthority()
                        await self.refreshSpeedEvidenceAuthority(using: speedEvidenceProvider)
                    } else if incomingState.connection != .connected {
                        self.invalidateSpeedEvidenceAuthority()
                    }
                } else if incomingState.connection != .connected {
                    self.invalidateSpeedEvidenceAuthority()
                }
            }
        }

        if let speedEvidenceProvider {
            speedEvidenceTask = Task { [weak self, speedEvidenceProvider] in
                let stream = await speedEvidenceProvider.speedEvidenceUpdates()
                for await _ in stream {
                    guard let self, !Task.isCancelled else { return }

                    // Stream values are wake-up triggers only. They may already be
                    // obsolete when this task resumes, so current app authority is
                    // rebuilt from the provider's current source-owned snapshot.
                    await self.refreshSpeedEvidenceAuthority(using: speedEvidenceProvider)
                }

                guard let self, !Task.isCancelled else { return }
                self.invalidateSpeedEvidenceAuthority()
            }
        } else {
            speedEvidenceAvailability = .unavailable
        }

        if let simulatorPowerEvidenceProvider {
            simulatorPowerEvidenceTask = Task { [weak self, simulatorPowerEvidenceProvider] in
                let stream = await simulatorPowerEvidenceProvider.simulatorPowerEvidenceUpdates()
                for await _ in stream {
                    guard let self, !Task.isCancelled else { return }

                    // Stream values are wake-ups only. Re-snapshot the exact source
                    // actor, then let stateful Store custody reject stale/replayed
                    // chronology. Aggregate connection is a negative veto only.
                    let current = await simulatorPowerEvidenceProvider.simulatorPowerEvidenceSnapshot()
                    guard !Task.isCancelled else { return }
                    self.simulatorPowerStoreAuthority.applySource(
                        current,
                        transportIsConnected: self.state.connection == .connected
                    )
                }

                guard let self, !Task.isCancelled else { return }
                self.simulatorPowerStoreAuthority.sourceBecameUnavailable()
            }
        } else {
            simulatorPowerStoreAuthority.sourceBecameUnavailable()
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
        if locked && !canLockFromCurrentSpeedEvidence {
            lastErrorMessage = "Live stopped-speed evidence is required before locking."
            return
        }
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

            if let observation = AuthoritativeBatteryObservation(
                percent: batteryPercent,
                authority: batteryObservationAuthority,
                observedAt: incomingState.lastUpdated
            ) {
                if shouldAcceptConfirmedBatteryObservation(observation) {
                    lastConfirmedBatteryPercent = observation.percent
                    lastConfirmedBatteryObservedAt = observation.observedAt
                    lastConfirmedBatteryAuthority = observation.authority
                    if let snapshot = observation.retained() {
                        do {
                            try retainedBatteryStorage?.save(snapshot)
                        } catch {
                            // Persistence must never turn confirmed live telemetry into an error state.
                            // The current session remains authoritative even if local continuity storage fails.
                        }
                    }
                } else if let previousPercent = lastConfirmedBatteryPercent {
                    // A replayed aggregate publication or delayed older battery value does not
                    // manufacture newer evidence or roll shared Battery truth backward. Keep the
                    // previously confirmed value while unrelated live vehicle fields may advance.
                    nextState.batteryPercent = previousPercent
                }
            } else {
                // An unclassified or invalid transport value does not enter shared product state.
                // This prevents Home, Dashboard, Vehicle, Rides, or any future consumer from
                // accidentally treating a raw integer as Battery truth before hardware evidence
                // establishes its meaning. Previously confirmed retained evidence stays intact.
                nextState.batteryPercent = nil
            }
        } else if incomingState.connection != .connected {
            // A disconnect/reconnect lifecycle update is not a battery observation. Its payload
            // cannot replace the last confirmed value or create a new one. Preserve the prior
            // confirmed value and its original battery chronology when one exists; otherwise fail closed.
            if let previousPercent = lastConfirmedBatteryPercent,
               let observedAt = lastConfirmedBatteryObservedAt,
               let authority = lastConfirmedBatteryAuthority {
                nextState.batteryPercent = previousPercent
                nextState.lastUpdated = observedAt
                retainedBatteryObservedAt = observedAt
                retainedBatteryAuthority = authority
            } else {
                nextState.batteryPercent = nil
                retainedBatteryObservedAt = nil
                retainedBatteryAuthority = nil
            }
        }

        state = nextState
    }

    /// Runtime uses the same evidence chronology rule as durable retained storage:
    /// exact value/authority replays are not new observations, and delayed older
    /// evidence cannot replace newer confirmed truth.
    private func shouldAcceptConfirmedBatteryObservation(
        _ candidate: AuthoritativeBatteryObservation
    ) -> Bool {
        guard let previousPercent = lastConfirmedBatteryPercent,
              let previousObservedAt = lastConfirmedBatteryObservedAt,
              let previousAuthority = lastConfirmedBatteryAuthority else {
            return true
        }

        if candidate.percent == previousPercent,
           candidate.authority == previousAuthority {
            return false
        }

        return candidate.observedAt > previousObservedAt
    }

    /// Retires current speed authority and invalidates every in-flight refresh.
    private func invalidateSpeedEvidenceAuthority() {
        speedEvidenceConsumerAuthority.invalidate()
        speedEvidenceAvailability = speedEvidenceConsumerAuthority.availability
    }

    /// Rebuilds the app projection from current source-owned state instead of
    /// trusting whichever availability event happened to wake the consumer.
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