import Testing
@testable import NembraCore

@Suite("Simulation configuration safety")
struct SimulationConfigurationTests {
    @Test("no explicit configuration keeps simulation disabled")
    func noConfiguration() {
        #expect(ScooterSimulationConfiguration.resolve(arguments: ["Nembra"], environment: [:]) == .disabled)
    }

    @Test("valid environment configuration has priority")
    func environmentPriority() {
        let result = ScooterSimulationConfiguration.resolve(
            arguments: ["Nembra", "--nembra-simulation=riding"],
            environment: [ScooterSimulationConfiguration.environmentKey: "low-battery"]
        )
        #expect(result == .selected(.lowBattery))
    }

    @Test("invalid environment configuration fails closed instead of falling through")
    func invalidEnvironmentDoesNotFallThrough() {
        let result = ScooterSimulationConfiguration.resolve(
            arguments: ["Nembra", "--nembra-simulation=riding"],
            environment: [ScooterSimulationConfiguration.environmentKey: "low-batery"]
        )
        #expect(result == .invalid(source: .environment, rawValue: "low-batery"))
    }

    @Test("valid launch argument selects one exact scenario")
    func validLaunchArgument() {
        let result = ScooterSimulationConfiguration.resolve(
            arguments: ["Nembra", "--nembra-simulation=cold-disconnected"],
            environment: [:]
        )
        #expect(result == .selected(.coldDisconnected))
    }

    @Test("missing or unknown launch argument values fail closed")
    func malformedLaunchArguments() {
        #expect(
            ScooterSimulationConfiguration.resolve(
                arguments: ["Nembra", "--nembra-simulation"],
                environment: [:]
            ) == .invalid(source: .launchArgument, rawValue: "--nembra-simulation")
        )
        #expect(
            ScooterSimulationConfiguration.resolve(
                arguments: ["Nembra", "--nembra-simulation=warp-speed"],
                environment: [:]
            ) == .invalid(source: .launchArgument, rawValue: "warp-speed")
        )
    }

    @Test("duplicate simulation launch arguments are rejected as ambiguous")
    func duplicateArgumentsRejected() {
        let raw = "--nembra-simulation=riding --nembra-simulation=low-battery"
        let result = ScooterSimulationConfiguration.resolve(
            arguments: ["Nembra", "--nembra-simulation=riding", "--nembra-simulation=low-battery"],
            environment: [:]
        )
        #expect(result == .invalid(source: .launchArgument, rawValue: raw))
    }
}
