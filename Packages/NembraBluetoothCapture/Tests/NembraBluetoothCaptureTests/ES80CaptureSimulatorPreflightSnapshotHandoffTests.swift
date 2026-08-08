import Foundation
import Testing

@Suite("ES80 Capture Simulator preflight snapshot handoff")
struct ES80CaptureSimulatorPreflightSnapshotHandoffTests {
    private static func appSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("App")
                .appendingPathComponent("NembraApp.swift"),
            encoding: .utf8
        )
    }

    private static func section(
        _ source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        let start = try #require(source.range(of: startMarker)?.lowerBound)
        let end = try #require(
            source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound
        )
        return source[start..<end]
    }

    @Test("stationary Simulator QA passes the package-owned snapshot into preflight")
    func launchRetainsExactFixtureAuthority() throws {
        let source = try Self.appSource()
        let launch = try Self.section(
            source,
            from: "case let .es80PassiveCaptureSimulatorQA(rawScenario):",
            to: "    /// Routes the exact field-build recipe marker"
        )

        #expect(launch.contains("let snapshot = PassiveBluetoothExperimentOneSimulatorQAFixture.snapshot(for: scenario)"))
        #expect(launch.contains("if scenario == .stationaryPreflight"))
        #expect(launch.contains("ES80ExperimentOneStationaryPreflightView("))
        #expect(launch.contains("simulatorQASnapshot: snapshot"))
    }

    @Test("preflight stores synthetic authority only in DEBUG Simulator builds")
    func preflightKeepsSyntheticStateOutOfProductionInitializer() throws {
        let source = try Self.appSource()
        let preflight = try Self.section(
            source,
            from: "private struct ES80ExperimentOneStationaryPreflightView: View",
            to: "private struct ES80ExperimentOneFieldNoGoView: View"
        )

        #expect(preflight.contains("#if DEBUG && targetEnvironment(simulator)"))
        #expect(preflight.contains("private let simulatorQASnapshot: PassiveBluetoothExperimentOneSimulatorQAFixture.Snapshot?"))
        #expect(preflight.contains("simulatorQASnapshot = nil"))
        #expect(preflight.contains("simulatorQAEvidenceLabel = simulatorQASnapshot.evidenceLabel"))
    }

    @Test("accepted charger preflight forwards the same snapshot into the Capture shell")
    func acceptedPreflightDoesNotDropSyntheticScenario() throws {
        let source = try Self.appSource()
        let preflight = try Self.section(
            source,
            from: "private struct ES80ExperimentOneStationaryPreflightView: View",
            to: "private struct ES80ExperimentOneFieldNoGoView: View"
        )

        #expect(preflight.contains("if disconnectedDeclarationAccepted"))
        #expect(preflight.contains("if let simulatorQASnapshot"))
        #expect(preflight.contains("simulatorQASnapshot: simulatorQASnapshot"))
        #expect(preflight.contains("onFreshExperimentRequested: makeFreshExperimentCoordinator"))
    }
}
