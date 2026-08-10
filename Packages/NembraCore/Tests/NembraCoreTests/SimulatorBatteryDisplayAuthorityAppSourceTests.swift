import Foundation
import Testing
@testable import NembraCore

@Suite("Simulator battery display authority app boundary")
struct SimulatorBatteryDisplayAuthorityAppSourceTests {
    @Test("Simulator bootstrap carries display-only battery authority into every VehicleStore construction")
    func simulatorBootstrapCarriesDisplayOnlyAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/AppBootstrap.swift")

        #expect(source.contains("let batteryObservationAuthority: BatteryObservationAuthority?"))
        #expect(source.contains("batteryObservationAuthority: .displayOnly"))
        #expect(source.contains("batteryObservationAuthority: nil"))

        let forwardedAuthorityCount = source.components(
            separatedBy: "batteryObservationAuthority: bootstrap.batteryObservationAuthority"
        ).count - 1
        #expect(forwardedAuthorityCount == 2)
    }

    @Test("display-only Simulator battery can render but cannot become physical or range evidence")
    func displayOnlyAuthorityCannotBecomePhysicalRangeEvidence() throws {
        let observation = try #require(
            AuthoritativeBatteryObservation(
                percent: 68,
                authority: .displayOnly,
                observedAt: Date(timeIntervalSince1970: 1)
            )
        )

        #expect(observation.percent == 68)
        #expect(observation.authority == .displayOnly)
        #expect(observation.physicalMeasurement == nil)
        #expect(observation.rangeEligible(currentness: .live) == nil)
    }

    @Test("production bootstrap must never opt into synthetic battery display authority")
    func productionBootstrapKeepsBatteryAuthorityUnavailable() throws {
        let source = try readRepositoryFile("NembraApp/App/AppBootstrap.swift")
        let bootstrap = try section(
            in: source,
            from: "private static func makeVehicleBootstrap",
            toEnd: true
        )
        let body = String(bootstrap)

        let productionStart = try #require(body.range(of: "guard let scenario = simulationScenario"))
        let simulatorStart = try #require(body.range(of: "let state = SimulatedScooterService.state", range: productionStart.upperBound..<body.endIndex))
        let productionBranch = body[productionStart.lowerBound..<simulatorStart.lowerBound]
        let simulatorBranch = body[simulatorStart.lowerBound..<body.endIndex]

        #expect(productionBranch.contains("batteryObservationAuthority: nil"))
        #expect(!productionBranch.contains("batteryObservationAuthority: .displayOnly"))
        #expect(!productionBranch.contains("batteryObservationAuthority: .measured"))
        #expect(simulatorBranch.contains("batteryObservationAuthority: .displayOnly"))
        #expect(!simulatorBranch.contains("batteryObservationAuthority: .measured"))
    }

    private func section(
        in source: String,
        from start: String,
        toEnd: Bool
    ) throws -> Substring {
        guard toEnd, let startRange = source.range(of: start) else {
            Issue.record("Expected source section missing: \(start)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<source.endIndex]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
