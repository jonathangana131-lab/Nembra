import Foundation

enum AppBootstrap {
    @MainActor
    static func makeVehicleStore(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> VehicleStore {
        guard let scenario = simulationScenario(arguments: arguments, environment: environment) else {
            let state = UnverifiedScooterService.initialState()
            return VehicleStore(
                service: UnverifiedScooterService(),
                initialState: state,
                shouldAutoConnectOnStart: false,
                speedInstrumentInterpolationPolicy: .disabled
            )
        }

        let state = SimulatedScooterService.state(for: scenario)
        let service = SimulatedScooterService(initialState: state)
        return VehicleStore(
            service: service,
            initialState: state,
            shouldAutoConnectOnStart: scenario.shouldAutoConnectOnLaunch,
            speedInstrumentInterpolationPolicy: .simulatorQA
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
}
