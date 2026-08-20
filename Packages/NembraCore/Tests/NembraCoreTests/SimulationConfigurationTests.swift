import Foundation
import Testing
@testable import NembraCore

@Suite("Simulation configuration safety")
struct SimulationConfigurationTests {
    private func expectExplicitResolution(
        _ actual: ScooterSimulationConfigurationResolution,
        hostOrSimulator expected: ScooterSimulationConfigurationResolution
    ) {
#if os(iOS) && !targetEnvironment(simulator)
        #expect(actual == .disabled)
#else
        #expect(actual == expected)
#endif
    }

    @Test("no explicit configuration keeps simulation disabled")
    func noConfiguration() {
        #expect(ScooterSimulationConfiguration.resolve(arguments: ["Nembra"], environment: [:]) == .disabled)
    }

    @Test("valid environment configuration has priority where synthetic scenarios are allowed")
    func environmentPriority() {
        let result = ScooterSimulationConfiguration.resolve(
            arguments: ["Nembra", "--nembra-simulation=riding"],
            environment: [ScooterSimulationConfiguration.environmentKey: "low-battery"]
        )
        expectExplicitResolution(result, hostOrSimulator: .selected(.lowBattery))
    }

    @Test("invalid environment configuration fails closed instead of falling through")
    func invalidEnvironmentDoesNotFallThrough() {
        let result = ScooterSimulationConfiguration.resolve(
            arguments: ["Nembra", "--nembra-simulation=riding"],
            environment: [ScooterSimulationConfiguration.environmentKey: "low-batery"]
        )
        expectExplicitResolution(
            result,
            hostOrSimulator: .invalid(source: .environment, rawValue: "low-batery")
        )
    }

    @Test("valid launch argument selects one exact scenario only where synthetic scenarios are allowed")
    func validLaunchArgument() {
        let result = ScooterSimulationConfiguration.resolve(
            arguments: ["Nembra", "--nembra-simulation=cold-disconnected"],
            environment: [:]
        )
        expectExplicitResolution(result, hostOrSimulator: .selected(.coldDisconnected))
    }

    @Test("missing or unknown launch argument values fail closed")
    func malformedLaunchArguments() {
        expectExplicitResolution(
            ScooterSimulationConfiguration.resolve(
                arguments: ["Nembra", "--nembra-simulation"],
                environment: [:]
            ),
            hostOrSimulator: .invalid(source: .launchArgument, rawValue: "--nembra-simulation")
        )
        expectExplicitResolution(
            ScooterSimulationConfiguration.resolve(
                arguments: ["Nembra", "--nembra-simulation=warp-speed"],
                environment: [:]
            ),
            hostOrSimulator: .invalid(source: .launchArgument, rawValue: "warp-speed")
        )
    }

    @Test("duplicate simulation launch arguments are rejected as ambiguous where parsing is allowed")
    func duplicateArgumentsRejected() {
        let raw = "--nembra-simulation=riding --nembra-simulation=low-battery"
        let result = ScooterSimulationConfiguration.resolve(
            arguments: ["Nembra", "--nembra-simulation=riding", "--nembra-simulation=low-battery"],
            environment: [:]
        )
        expectExplicitResolution(
            result,
            hostOrSimulator: .invalid(source: .launchArgument, rawValue: raw)
        )
    }

    @Test("physical iOS simulation authority remains compile-time fenced")
    func physicalIOSAuthorityFenceSourceContract() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("Packages/NembraCore/Sources/NembraCore/SimulationConfiguration.swift")
        let source = String(decoding: try Data(contentsOf: sourceURL), as: UTF8.self)

        #expect(source.contains("#if os(iOS) && !targetEnvironment(simulator)"))
        #expect(source.contains("private static let runtimeAllowsSyntheticScenarios"))
        #expect(source.contains("guard runtimeAllowsSyntheticScenarios else { return .disabled }"))
        #expect(source.contains("Synthetic vehicle authority is a Simulator/host-test facility only."))
    }

#if os(iOS) && !targetEnvironment(simulator)
    @Test("physical iOS rejects every explicit synthetic configuration before parsing")
    func physicalIOSRejectsExplicitSyntheticConfiguration() {
        let environmentResult = ScooterSimulationConfiguration.resolve(
            arguments: ["Nembra", "--nembra-simulation=riding"],
            environment: [ScooterSimulationConfiguration.environmentKey: "low-battery"]
        )
        let malformedResult = ScooterSimulationConfiguration.resolve(
            arguments: ["Nembra", "--nembra-simulation=warp-speed"],
            environment: [:]
        )
        let duplicateResult = ScooterSimulationConfiguration.resolve(
            arguments: ["Nembra", "--nembra-simulation=riding", "--nembra-simulation=low-battery"],
            environment: [:]
        )

        #expect(environmentResult == .disabled)
        #expect(malformedResult == .disabled)
        #expect(duplicateResult == .disabled)
    }
#endif
}
