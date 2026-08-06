import Foundation

@MainActor
final class AppRuntime {
    let vehicleStore: VehicleStore
    let rideStore: RideApplicationStore
    let rideHistoryStore: RideHistoryPresentationStore

    private let simulatorService: SimulatedScooterService?
    private let simulationScenario: ScooterSimulationScenario?
    private let simulatorAutoCompletesRide: Bool
    private var didStart = false
    private var simulatorRideDriverTask: Task<Void, Never>?

    init(
        vehicleStore: VehicleStore,
        rideStore: RideApplicationStore,
        rideHistoryStore: RideHistoryPresentationStore,
        simulatorService: SimulatedScooterService?,
        simulationScenario: ScooterSimulationScenario?,
        simulatorAutoCompletesRide: Bool
    ) {
        self.vehicleStore = vehicleStore
        self.rideStore = rideStore
        self.rideHistoryStore = rideHistoryStore
        self.simulatorService = simulatorService
        self.simulationScenario = simulationScenario
        self.simulatorAutoCompletesRide = simulatorAutoCompletesRide
    }

    deinit {
        simulatorRideDriverTask?.cancel()
    }

    func start() async {
        guard !didStart else { return }
        didStart = true

        // Ride evidence subscribes first so explicit QA telemetry emitted after
        // launch cannot race past the automatic ride application layer.
        await rideStore.start()
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

            // Explicit end-to-end history fixture used only when a UI/QA launch
            // opts in through the Simulator environment. It drives the real ride
            // engine and persistence path instead of inserting a fake row.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
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
            // Production history storage may be opened for truthful read-only
            // presentation, but no production ride detector policy is selected
            // until real MAXSHOT speed cadence/latency/reconnect is measured.
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

        return AppRuntime(
            vehicleStore: vehicleStore,
            rideStore: rideStore,
            rideHistoryStore: rideHistoryStore,
            simulatorService: bootstrap.simulatorService,
            simulationScenario: bootstrap.scenario,
            simulatorAutoCompletesRide: simulatorAutoCompletesRide
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
