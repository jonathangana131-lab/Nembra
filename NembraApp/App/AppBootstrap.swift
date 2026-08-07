import Foundation

@MainActor
final class AppRuntime {
    let vehicleStore: VehicleStore
    let rideStore: RideApplicationStore
    let rideHistoryStore: RideHistoryPresentationStore
    let rideRouteStore: RideRoutePresentationStore

    private let simulatorService: SimulatedScooterService?
    private let simulationScenario: ScooterSimulationScenario?
    private let simulatorAutoCompletesRide: Bool
    private let rideLocationCaptureCoordinator: RideLocationCaptureCoordinator?
    private let rideRouteDraftFinalizer: RideRouteDraftFinalizer?
    private let rideRouteOutcomeStore: AtomicRideRouteOutcomeStore?
    private var didStart = false
    private var simulatorRideDriverTask: Task<Void, Never>?
    private var rideLocationLifecycleTask: Task<Void, Never>?
    private var activeLocationCaptureSessionID: UUID?
    private var pendingLocationCaptureSummary: RideLocationCaptureSummary?

    init(
        vehicleStore: VehicleStore,
        rideStore: RideApplicationStore,
        rideHistoryStore: RideHistoryPresentationStore,
        rideRouteStore: RideRoutePresentationStore,
        simulatorService: SimulatedScooterService?,
        simulationScenario: ScooterSimulationScenario?,
        simulatorAutoCompletesRide: Bool,
        rideLocationCaptureCoordinator: RideLocationCaptureCoordinator?,
        rideRouteDraftFinalizer: RideRouteDraftFinalizer?,
        rideRouteOutcomeStore: AtomicRideRouteOutcomeStore?
    ) {
        self.vehicleStore = vehicleStore
        self.rideStore = rideStore
        self.rideHistoryStore = rideHistoryStore
        self.rideRouteStore = rideRouteStore
        self.simulatorService = simulatorService
        self.simulationScenario = simulationScenario
        self.simulatorAutoCompletesRide = simulatorAutoCompletesRide
        self.rideLocationCaptureCoordinator = rideLocationCaptureCoordinator
        self.rideRouteDraftFinalizer = rideRouteDraftFinalizer
        self.rideRouteOutcomeStore = rideRouteOutcomeStore
    }

    deinit {
        simulatorRideDriverTask?.cancel()
        rideLocationLifecycleTask?.cancel()
    }

    func start() async {
        guard !didStart else { return }
        didStart = true

        // The completion barrier is installed before recovery starts so a
        // durable `completedPendingCommit` ride cannot clear its checkpoint
        // until route outcome/repair truth has also reached durable storage.
        installRideCompletionBarrierIfAvailable()

        // Ride evidence subscribes first so explicit QA telemetry emitted after
        // launch cannot race past the automatic ride application layer.
        await rideStore.start()
        startRideLocationLifecycleIfAvailable()
        await vehicleStore.start()

        guard simulationScenario == .riding,
              let simulatorService else { return }

        simulatorRideDriverTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }

            let snapshot = await simulatorService.snapshot()
            guard snapshot.connection == .connected,
                  let speed = snapshot.speedKilometersPerHour,
                  speed > 0 else { return }

            // First establish fresh authoritative motion without advancing the
            // simulated odometer. This lets RideEngine establish the ride's ODO
            // baseline before the completed-history fixture adds movement.
            await simulatorService.simulateRide(
                speedKilometersPerHour: speed,
                elapsedSeconds: 0
            )

            guard simulatorAutoCompletesRide else { return }

            // The opt-in history fixture then advances a real Simulator ODO/trip
            // delta through the production service/ride path. `elapsedSeconds`
            // affects simulated distance only; packet timestamps still use the
            // real monotonic arrival clock and never fabricate cadence.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await simulatorService.simulateRide(
                speedKilometersPerHour: speed,
                elapsedSeconds: 60
            )

            // Location is no longer written directly into route persistence.
            // The root-owned ride lifecycle starts the explicit Simulator source
            // only after RideEngine owns a confirmed UUID. Give its two real-time
            // intervals enough wall-clock time to reach the same quality screen,
            // route recorder, and session-scoped GPS-distance sink before the
            // fixture supplies authoritative ride-end evidence.
            try? await Task.sleep(nanoseconds: 4_250_000_000)
            guard !Task.isCancelled else { return }

            // Explicit end-to-end history fixture used only when a UI/QA launch
            // opts in through the Simulator environment. It drives the real ride
            // engine and persistence path instead of inserting a fake row.
            await simulatorService.simulateRide(
                speedKilometersPerHour: 0,
                elapsedSeconds: 0
            )

            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            await simulatorService.simulateRide(
                speedKilometersPerHour: 0,
                elapsedSeconds: 0
            )
        }
    }

    /// Application/root lifetime owns location capture. SwiftUI navigation and
    /// view appearance never start or stop it. The ride engine's durable session
    /// UUID is the only lifecycle identity accepted by the coordinator.
    private func startRideLocationLifecycleIfAvailable() {
        guard rideLocationLifecycleTask == nil,
              let rideLocationCaptureCoordinator else { return }

        let stream = rideStore.rideSessionEvents()
        rideLocationLifecycleTask = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { break }
                await self?.handleRideSessionEvent(
                    event,
                    coordinator: rideLocationCaptureCoordinator
                )
            }
        }
    }

    /// Completed history is not allowed to publish before route outcome truth is
    /// durable. The barrier is intentionally installed even if no active source
    /// exists because startup recovery may need to salvage persisted chunks or
    /// classify an unavailable route database before clearing the ride checkpoint.
    private func installRideCompletionBarrierIfAvailable() {
        guard rideRouteOutcomeStore != nil else { return }
        rideStore.setRideCompletionBarrier { [weak self] sessionID in
            guard let self else { return }
            try await self.finishLocationCaptureBeforeRideCommit(sessionID: sessionID)
        }
    }

    private func finishLocationCaptureBeforeRideCommit(sessionID: UUID) async throws {
        if let pendingLocationCaptureSummary,
           pendingLocationCaptureSummary.sessionID == sessionID {
            try await persistRouteOutcome(for: pendingLocationCaptureSummary)
            self.pendingLocationCaptureSummary = nil
            activeLocationCaptureSessionID = nil
            return
        }

        if activeLocationCaptureSessionID == sessionID,
           let rideLocationCaptureCoordinator {
            let summary = try await rideLocationCaptureCoordinator.finish()
            // Keep the in-memory summary until its independent outcome ledger is
            // durable. If that write fails, the ride checkpoint remains pending
            // and a later retry can finish this exact obligation without asking
            // an already-finished location source to replay evidence.
            pendingLocationCaptureSummary = summary
            try await persistRouteOutcome(for: summary)
            pendingLocationCaptureSummary = nil
            activeLocationCaptureSessionID = nil
            return
        }

        // Recovery after a process boundary has no active source/summary. Only
        // durable route evidence may improve the classification. A verified
        // manifest promotes to recorded; surviving chunks are finalized partial;
        // no chunks without a prior outcome remain explicitly unknown.
        try await reconcileRecoveredRouteOutcome(sessionID: sessionID)
    }

    private func persistRouteOutcome(for summary: RideLocationCaptureSummary) async throws {
        guard let rideRouteOutcomeStore else { return }

        if !summary.routePersistenceFailed,
           let manifest = summary.routeManifest {
            try await commitRouteOutcome(
                sessionID: summary.sessionID,
                state: manifest.pointCount > 0 ? .recorded : .noRecordedGeometry,
                acceptedPointCount: summary.acceptedPointCount,
                store: rideRouteOutcomeStore
            )
            return
        }

        // A failed normal manifest write can still leave already-durable chunks.
        // Salvage those immediately, before completed history is allowed to clear
        // its checkpoint. If salvage fails, keep an explicit repair obligation.
        if let rideRouteDraftFinalizer {
            do {
                if let manifest = try await rideRouteDraftFinalizer.finalizePartialDraftIfNeeded(
                    sessionID: summary.sessionID
                ) {
                    try await commitRouteOutcome(
                        sessionID: summary.sessionID,
                        state: manifest.pointCount > 0 ? .recorded : .noRecordedGeometry,
                        acceptedPointCount: summary.acceptedPointCount,
                        store: rideRouteOutcomeStore
                    )
                    return
                }
            } catch {
                // The durable outcome below preserves failure truth and remains
                // repairable on a later launch; ride history stays independent.
            }
        }

        try await commitRouteOutcome(
            sessionID: summary.sessionID,
            state: .storageFailed,
            acceptedPointCount: summary.acceptedPointCount,
            store: rideRouteOutcomeStore
        )
    }

    private func reconcileRecoveredRouteOutcome(sessionID: UUID) async throws {
        guard let rideRouteOutcomeStore else { return }
        let existing = try await rideRouteOutcomeStore.record(sessionID: sessionID)

        switch existing?.state {
        case .recorded, .noRecordedGeometry:
            return
        case .storageFailed, .unknown, .none:
            break
        }

        if let rideRouteDraftFinalizer {
            do {
                if let manifest = try await rideRouteDraftFinalizer.finalizePartialDraftIfNeeded(
                    sessionID: sessionID
                ) {
                    try await commitRouteOutcome(
                        sessionID: sessionID,
                        state: manifest.pointCount > 0 ? .recorded : .noRecordedGeometry,
                        acceptedPointCount: existing?.acceptedPointCount ?? manifest.pointCount,
                        store: rideRouteOutcomeStore
                    )
                    return
                }
            } catch {
                try await commitRouteOutcome(
                    sessionID: sessionID,
                    state: .storageFailed,
                    acceptedPointCount: existing?.acceptedPointCount,
                    store: rideRouteOutcomeStore
                )
                return
            }

            // A prior failure/unknown classification remains truthful when no
            // salvageable chunks exist. For legacy pending checkpoints that have
            // no outcome at all, do not invent "no route" after a process gap.
            if existing != nil { return }
            try await commitRouteOutcome(
                sessionID: sessionID,
                state: .unknown,
                acceptedPointCount: nil,
                store: rideRouteOutcomeStore
            )
            return
        }

        // If the optional route database cannot even open during recovery, that
        // is explicit route-storage failure rather than evidence of zero geometry.
        try await commitRouteOutcome(
            sessionID: sessionID,
            state: .storageFailed,
            acceptedPointCount: existing?.acceptedPointCount,
            store: rideRouteOutcomeStore
        )
    }

    private func commitRouteOutcome(
        sessionID: UUID,
        state: RideRouteOutcomeState,
        acceptedPointCount: Int?,
        store: AtomicRideRouteOutcomeStore
    ) async throws {
        let record = try RideRouteOutcomeRecord(
            sessionID: sessionID,
            state: state,
            acceptedPointCount: acceptedPointCount
        )
        _ = try await store.commit(record)
    }

    private func handleRideSessionEvent(
        _ event: RideApplicationSessionEvent,
        coordinator: RideLocationCaptureCoordinator
    ) async {
        switch event {
        case let .becameActive(sessionID):
            guard activeLocationCaptureSessionID != sessionID else { return }

            if activeLocationCaptureSessionID != nil {
                if let summary = try? await coordinator.finish() {
                    try? await persistRouteOutcome(for: summary)
                }
                activeLocationCaptureSessionID = nil
            }

            do {
                // Capture begins only after ride confirmation, so the candidate
                // interval before this point is known missing coverage.
                try await coordinator.begin(
                    sessionID: sessionID,
                    requestedCoverage: .partial
                )
                activeLocationCaptureSessionID = sessionID
            } catch {
                activeLocationCaptureSessionID = nil
            }

        case let .ended(sessionID):
            // Normal completion already flushed through the awaited completion
            // barrier before RideApplicationStore released this UUID. Keep this
            // as a fail-safe for any non-completion transition that still ends a
            // previously active session.
            guard activeLocationCaptureSessionID == sessionID else { return }
            if let summary = try? await coordinator.finish() {
                try? await persistRouteOutcome(for: summary)
            }
            activeLocationCaptureSessionID = nil
        }
    }
}

enum AppBootstrap {
    static let simulationStorageNamespaceEnvironmentKey = "NEMBRA_SIMULATION_STORAGE_NAMESPACE"
    static let simulationAutoCompleteRideEnvironmentKey = "NEMBRA_SIMULATION_AUTOCOMPLETE_RIDE"

    private struct VehicleBootstrap {
        let service: any ScooterService
        let simulatorService: SimulatedScooterService?
        let initialState: VehicleState
        let scenario: ScooterSimulationScenario?
        let shouldAutoConnectOnStart: Bool
        let speedInterpolationPolicy: SpeedInstrumentInterpolationPolicy
    }

    @MainActor
    static func makeVehicleStore(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> VehicleStore {
        let bootstrap = makeVehicleBootstrap(arguments: arguments, environment: environment)
        return VehicleStore(
            service: bootstrap.service,
            initialState: bootstrap.initialState,
            shouldAutoConnectOnStart: bootstrap.shouldAutoConnectOnStart,
            speedInstrumentInterpolationPolicy: bootstrap.speedInterpolationPolicy
        )
    }

    @MainActor
    static func makeRuntime(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppRuntime {
        let bootstrap = makeVehicleBootstrap(arguments: arguments, environment: environment)
        let vehicleStore = VehicleStore(
            service: bootstrap.service,
            initialState: bootstrap.initialState,
            shouldAutoConnectOnStart: bootstrap.shouldAutoConnectOnStart,
            speedInstrumentInterpolationPolicy: bootstrap.speedInterpolationPolicy
        )

        let persistenceScope: RidePersistenceScope
        if let scenario = bootstrap.scenario {
            persistenceScope = .simulation(
                scenario: scenario,
                namespace: environment[simulationStorageNamespaceEnvironmentKey]
            )
        } else {
            persistenceScope = .production
        }

        let persistence: RidePersistenceStack?
        let persistenceError: String?
        do {
            persistence = try RidePersistenceFactory.make(scope: persistenceScope)
            persistenceError = nil
        } catch {
            persistence = nil
            persistenceError = "Local ride storage could not be opened."
        }

        let rideHistoryStore = RideHistoryPresentationStore(
            historyStore: persistence?.historyStore,
            startupPersistenceError: persistenceError
        )
        let rideRouteStore = RideRoutePresentationStore(
            routeStore: persistence?.routeStore,
            outcomeStore: persistence?.routeOutcomeStore,
            startupPersistenceError: persistenceError
        )

        let rideStore: RideApplicationStore
        if bootstrap.scenario != nil {
            if let persistence {
                do {
                    let configuration = try RideApplicationConfiguration.simulatorQA()
                    rideStore = RideApplicationStore(
                        service: bootstrap.service,
                        initialState: bootstrap.initialState,
                        configuration: configuration,
                        checkpointStore: persistence.checkpointStore,
                        historyStore: persistence.historyStore
                    )
                } catch {
                    rideStore = RideApplicationStore(
                        service: bootstrap.service,
                        initialState: bootstrap.initialState,
                        configuration: nil,
                        checkpointStore: nil,
                        historyStore: nil,
                        startupPersistenceError: "Simulator ride tracking could not be configured."
                    )
                }
            } else {
                rideStore = RideApplicationStore(
                    service: bootstrap.service,
                    initialState: bootstrap.initialState,
                    configuration: try? RideApplicationConfiguration.simulatorQA(),
                    checkpointStore: nil,
                    historyStore: nil,
                    startupPersistenceError: persistenceError ?? "Local ride recovery storage could not be opened."
                )
            }
        } else {
            // Production history/route storage may be opened for truthful
            // read-only presentation, but no production ride detector or
            // location-capture policy is selected until real AOVOPRO ES80 timing
            // and field location behavior are measured.
            rideStore = RideApplicationStore(
                service: bootstrap.service,
                initialState: bootstrap.initialState,
                configuration: nil,
                checkpointStore: nil,
                historyStore: nil
            )
        }

        let simulatorAutoCompletesRide = bootstrap.scenario == .riding
            && environment[simulationAutoCompleteRideEnvironmentKey] == "1"

        let rideLocationCaptureCoordinator: RideLocationCaptureCoordinator?
        if simulatorAutoCompletesRide,
           let persistence {
            do {
                let source = SimulatorRideLocationSource.completedRideQA()
                let policy = try RideLocationQualityPolicy.simulatorQA()
                rideLocationCaptureCoordinator = try RideLocationCaptureCoordinator(
                    source: source,
                    qualityPolicy: policy,
                    routeStore: persistence.routeStore,
                    routeChunkSize: 2,
                    sessionScopedEvidenceAdmissionSink: { [weak rideStore] sessionID, meters, uptime in
                        guard let rideStore else { return false }
                        return await rideStore.admitQualityScreenedLocationEvidence(
                            distanceDeltaMeters: meters,
                            receivedAtUptimeNanoseconds: uptime,
                            for: sessionID
                        )
                    }
                )
            } catch {
                rideLocationCaptureCoordinator = nil
            }
        } else {
            rideLocationCaptureCoordinator = nil
        }

        let rideRouteDraftFinalizer: RideRouteDraftFinalizer?
        if let routeStore = persistence?.routeStore {
            rideRouteDraftFinalizer = RideRouteDraftFinalizer(routeStore: routeStore)
        } else {
            rideRouteDraftFinalizer = nil
        }

        return AppRuntime(
            vehicleStore: vehicleStore,
            rideStore: rideStore,
            rideHistoryStore: rideHistoryStore,
            rideRouteStore: rideRouteStore,
            simulatorService: bootstrap.simulatorService,
            simulationScenario: bootstrap.scenario,
            simulatorAutoCompletesRide: simulatorAutoCompletesRide,
            rideLocationCaptureCoordinator: rideLocationCaptureCoordinator,
            rideRouteDraftFinalizer: rideRouteDraftFinalizer,
            rideRouteOutcomeStore: persistence?.routeOutcomeStore
        )
    }

    static func simulationScenario(
        arguments: [String],
        environment: [String: String]
    ) -> ScooterSimulationScenario? {
        switch ScooterSimulationConfiguration.resolve(
            arguments: arguments,
            environment: environment
        ) {
        case .selected(let scenario):
            return scenario
        case .disabled, .invalid:
            return nil
        }
    }

    @MainActor
    private static func makeVehicleBootstrap(
        arguments: [String],
        environment: [String: String]
    ) -> VehicleBootstrap {
        guard let scenario = simulationScenario(arguments: arguments, environment: environment) else {
            let service = UnverifiedScooterService()
            return VehicleBootstrap(
                service: service,
                simulatorService: nil,
                initialState: UnverifiedScooterService.initialState(),
                scenario: nil,
                shouldAutoConnectOnStart: false,
                speedInterpolationPolicy: .disabled
            )
        }

        let state = SimulatedScooterService.state(for: scenario)
        let service = SimulatedScooterService(initialState: state)
        return VehicleBootstrap(
            service: service,
            simulatorService: service,
            initialState: state,
            scenario: scenario,
            shouldAutoConnectOnStart: scenario.shouldAutoConnectOnLaunch,
            speedInterpolationPolicy: .simulatorQA
        )
    }
}