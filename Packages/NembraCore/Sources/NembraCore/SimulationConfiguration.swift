import Foundation

public enum ScooterSimulationConfigurationSource: String, Equatable, Codable, Sendable {
    case environment
    case launchArgument
}

public enum ScooterSimulationConfigurationResolution: Equatable, Sendable {
    case disabled
    case selected(ScooterSimulationScenario)
    case invalid(source: ScooterSimulationConfigurationSource, rawValue: String)
}

/// Resolves explicit QA simulation configuration without ever guessing.
///
/// Configuration is fail-closed: a present-but-invalid higher-priority value
/// does not fall through to a lower-priority source. This prevents a typo from
/// silently launching a different convincing simulator state.
public enum ScooterSimulationConfiguration {
    public static let environmentKey = "NEMBRA_SIMULATION_SCENARIO"
    public static let launchArgumentPrefix = "--nembra-simulation="
    public static let launchArgumentName = "--nembra-simulation"

    public static func resolve(
        arguments: [String],
        environment: [String: String]
    ) -> ScooterSimulationConfigurationResolution {
        if let rawEnvironmentValue = environment[environmentKey] {
            guard let scenario = ScooterSimulationScenario(rawValue: rawEnvironmentValue) else {
                return .invalid(source: .environment, rawValue: rawEnvironmentValue)
            }
            return .selected(scenario)
        }

        let matchingArguments = arguments.filter {
            $0 == launchArgumentName || $0.hasPrefix(launchArgumentPrefix)
        }
        guard !matchingArguments.isEmpty else { return .disabled }
        guard matchingArguments.count == 1, let argument = matchingArguments.first else {
            return .invalid(source: .launchArgument, rawValue: matchingArguments.joined(separator: " "))
        }
        guard argument.hasPrefix(launchArgumentPrefix) else {
            return .invalid(source: .launchArgument, rawValue: argument)
        }

        let rawValue = String(argument.dropFirst(launchArgumentPrefix.count))
        guard let scenario = ScooterSimulationScenario(rawValue: rawValue) else {
            return .invalid(source: .launchArgument, rawValue: rawValue)
        }
        return .selected(scenario)
    }
}
