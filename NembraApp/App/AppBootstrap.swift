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
    private let rideCheckpointStore: (any RideCheckpointStore)?
    private let rideRouteDraftFinalizer: RideRouteDraftFinalizer?
    private var didStart = false
    private var simulatorRideDriverTask: Task<Void, Never>?
    private var rideLocationLifecycleTask: Task<Void, Never>?
    private var activeLocationCaptureSessionID: UUID?

    init(
        vehicleStore: VehicleStore,
        rideStore: RideApplicationStore,
        rideHistoryStore: RideHistoryPresentationStore,
        rideRouteStore: RideRoutePresentationStore,
        simulatorService: SimulatedScooterService?,
        simulationScenario: ScooterSimulationScenario?,
        simulatorAutoCompletesRide: Bool,
        rideLocationCaptureCoordinator: RideLocationCaptureCoordinator?,
        rideCheckpointStore: (any RideCheckpointStore)?,
        rideRouteDraftFinalizer: RideRouteDraftFinalizer?
    ) {
        self.vehicleStore = vehicleStore
        self.rideStore = rideStore
        self.rideHistoryStore = rideHistoryStore
        self.rideRouteStore = rideRouteStore
        self.simulatorService = simulatorService
        self.simulationScenario = simulationScenario
        self.simulatorAutoCompletesRide = simulatorAutoCompletesRide
        self.rideLocationCaptureCoordinator = rideLocationCaptureCoordinator
        self.rideCheckpointStore = rideCheckpointStore
        self.rideRouteDraftFinalizer = rideRouteDraftFinalizer
    }

    deinit {
        simulatorRideDriverTask?.cancel()
        rideLocationLifecycleTask?.cancel()
    }

    func start() async {
        guard !didStart else { return }
        didStart = true

        installRideCompletionBarrierIfAvailable()
        await finalizeRecoveredRouteDraftIfNeeded()

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

    /// If the process stopped after `completedPendingCommit` became durable but
    /// before route-manifest commit, finalize only the already persisted chunks
    /// as partial coverage before RideApplicationStore publishes history. Route
    /// recovery remains additive: failure here never blocks the idempotent ride
    /// history recovery path.
    private func finalizeRecoveredRouteDraftIfNeeded() async {
        guard let rideCheckpointStore,
              let rideRouteDraftFinalizer,
              let checkpoint = try? await rideCheckpointStore.load(),
              case let .completedPendingCommit(evidence) = checkpoint else { return }

        _ = try? await rideRouteDraftFinalizer.finalizePartialDraftIfNeeded(
            sessionID: evidence.sessionID
        )
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

    /// Completed history is not allowed to publish before the additive route
    /// recorder has finalized its manifest. Keeping this barrier on AppRuntime
    /// preserves root ownership while avoiding any SwiftUI lifecycle dependency.
    private func installRideCompletionBarrierIfAvailable() {
        guard let rideLocationCaptureCoordinator else { return }
        rideStore.setRideCompletionBarrier { [weak self] sessionID in
            await self?.finishLocationCaptureBeforeRideCommit(
                sessionID: sessionID,
                coordinator: rideLocationCaptureCoordinator
            )
        }
    }

    private func finishLocationCaptureBeforeRideCommit(
        sessionID: UUID,
        coordinator: RideLocationCaptureCoordinator
    ) async {
        if activeLocationCaptureSessionID == sessionID {
            _ = try? await coordinator.finish()
            activeLocationCaptureSessionID = nil
            return
        }

        // A recovered `completedPendingCommit` session has no active in-process
        // source to finish. Reconcile any durable chunk draft idempotently before
        // history is allowed to clear the checkpoint.
        _ = try? await rideRouteDraftFinalizer?.finalizePartialDraftIfNeeded(
            sessionID: sessionID
        )
    }

    private func handleRideSessionEvent(
        _ event: RideApplicationSessionEvent,
        coordinator: RideLocationCaptureCoordinator
    ) async {
        switch event {
        case let .becameActive(sessionID):
            guard activeLocationCaptureSessionID != sessionID else { return }

            if activeLocationCaptureSessionID != nil {
                _ = try? await coordinator.finish()
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
            _ = try? await coordinator.finish()
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
           let routeStore = persistence?.routeStore {
            do {
                let source = CompletedRideQALocationSource()
                let policy = try RideLocationQualityPolicy.simulatorQA()
                rideLocationCaptureCoordinator = try RideLocationCaptureCoordinator(
                    source: source,
                    qualityPolicy: policy,
                    routeStore: routeStore,
                    routeChunkSize: 2,
                    sessionScopedDistanceSink: { [weak rideStore] sessionID, meters, uptime in
                        await rideStore?.ingestQualityScreenedGPSDistanceDelta(
                            meters,
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

        let rideRouteDraftFinalizer = persistence.map {
            RideRouteDraftFinalizer(routeStore: $0.routeStore)
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
            rideCheckpointStore: persistence?.checkpointStore,
            rideRouteDraftFinalizer: rideRouteDraftFinalizer
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