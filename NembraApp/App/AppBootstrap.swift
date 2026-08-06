import Foundation

@MainActor
final class AppRuntime {
    let vehicleStore: VehicleStore
    let rideStore: RideApplicationStore

    private let simulatorService: SimulatedScooterService?
    private let simulationScenario: ScooterSimulationScenario?
    private var didStart = false
    private var simulatorRideDriverTask: Task<Void, Never>?

    init(
        vehicleStore: VehicleStore,
        rideStore: RideApplicationStore,
        simulatorService: SimulatedScooterService?,
        simulationScenario: ScooterSimulationScenario?
    ) {
        self.vehicleStore = vehicleStore
        self.rideStore = rideStore
        self.simulatorService = simulatorService
        self.simulationScenario = simulationScenario
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

            // Emits one fresh authoritative QA packet without adding distance.
            // This is explicit Simulator plumbing, never production telemetry.
            await simulatorService.simulateRide(
                speedKilometersPerHour: speed,
                elapsedSeconds: 0
            )
        }
    }
}

enum AppBootstrap {
    static let simulationStorageNamespaceEnvironmentKey = "NEMBRA_SIMULATION_STORAGE_NAMESPACE"

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

        let rideStore: RideApplicationStore
        if let scenario = bootstrap.scenario {
            do {
                let configuration = try RideApplicationConfiguration.simulatorQA()
                let persistence = try RidePersistenceFactory.make(
                    scope: .simulation(
                        scenario: scenario,
                        namespace: environment[simulationStorageNamespaceEnvironmentKey]
                    )
                )
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
                    configuration: try? RideApplicationConfiguration.simulatorQA(),
                    checkpointStore: nil,
                    historyStore: nil,
                    startupPersistenceError: "Local ride recovery storage could not be opened."
                )
            }
        } else {
            // No production ride detector policy is selected until real MAXSHOT
            // speed cadence/latency and reconnect behavior are measured.
            rideStore = RideApplicationStore(
                service: bootstrap.service,
                initialState: bootstrap.initialState,
                configuration: nil,
                checkpointStore: nil,
                historyStore: nil
            )
        }

        return AppRuntime(
            vehicleStore: vehicleStore,
            rideStore: rideStore,
            simulatorService: bootstrap.simulatorService,
            simulationScenario: bootstrap.scenario
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
