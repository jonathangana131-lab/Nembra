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

    @Test("Simulator runtime cannot receive the production retained battery store")
    func simulatorRuntimeKeepsRetainedBatteryStorageProductionOnly() throws {
        let source = try readRepositoryFile("NembraApp/App/AppBootstrap.swift")
        let runtime = try section(
            in: source,
            from: "static func makeRuntime(",
            to: "private static func makeVehicleBootstrap"
        )
        let body = String(runtime)
        let retainedStorageDeclaration = try section(
            in: body,
            from: "let retainedBatteryStorage:",
            to: "let vehicleStore = VehicleStore("
        )
        let storage = String(retainedStorageDeclaration)
        let compactedStorage = storage
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        #expect(
            compactedStorage.contains(
                "let retainedBatteryStorage: (any RetainedBatterySnapshotStorage)? = bootstrap.scenario == nil ? UserDefaultsRetainedBatterySnapshotStorage() : nil"
            )
        )
        #expect(
            storage.components(separatedBy: "UserDefaultsRetainedBatterySnapshotStorage()").count - 1 == 1
        )
        #expect(
            body.components(separatedBy: "retainedBatteryStorage: retainedBatteryStorage").count - 1 == 1
        )
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
        to end: String
    ) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected bounded source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
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
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
        return String(decoding: data, as: UTF8.self)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
