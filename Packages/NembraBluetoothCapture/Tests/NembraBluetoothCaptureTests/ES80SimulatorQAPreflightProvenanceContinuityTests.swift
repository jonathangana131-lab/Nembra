import Foundation
import Testing

@Suite("ES80 Simulator QA preflight provenance continuity")
struct ES80SimulatorQAPreflightProvenanceContinuityTests {
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

    private static func preflightSource(in source: String) throws -> Substring {
        let start = try #require(
            source.range(of: "private struct ES80ExperimentOneStationaryPreflightView: View {")
        )
        let end = try #require(
            source.range(
                of: "@MainActor\nprivate struct ES80ExperimentOneFieldNoGoView: View {",
                range: start.upperBound..<source.endIndex
            )
        )
        return source[start.lowerBound..<end.lowerBound]
    }

    @Test("stationary Simulator QA carries the full synthetic snapshot through charger preflight")
    func simulatorSnapshotSurvivesPreflightTransition() throws {
        let source = try Self.appSource()
        let preflight = try Self.preflightSource(in: source)

        #expect(source.contains("simulatorQASnapshot: snapshot"))
        #expect(!source.contains("simulatorQAEvidenceLabel: snapshot.evidenceLabel"))
        #expect(preflight.contains("private let simulatorQASnapshot: PassiveBluetoothExperimentOneSimulatorQAFixture.Snapshot?"))
        #expect(preflight.contains("self.simulatorQAEvidenceLabel = simulatorQASnapshot.evidenceLabel"))
        #expect(preflight.contains("self.simulatorQASnapshot = simulatorQASnapshot"))

        let transition = try #require(preflight.range(of: "if disconnectedDeclarationAccepted {"))
        let normalContent = try #require(
            preflight.range(
                of: "} else {\n            ScrollView {",
                range: transition.upperBound..<preflight.endIndex
            )
        )
        let acceptedPath = preflight[transition.lowerBound..<normalContent.lowerBound]

        #expect(acceptedPath.contains("if let simulatorQASnapshot"))
        #expect(acceptedPath.contains("ES80CaptureShellView("))
        #expect(acceptedPath.contains("simulatorQASnapshot: simulatorQASnapshot"))
        #expect(acceptedPath.contains("onFreshExperimentRequested: makeFreshExperimentCoordinator"))
    }

    @Test("production preflight remains fail-closed and does not gain synthetic authority")
    func productionConstructionRemainsIndependent() throws {
        let source = try Self.appSource()
        let preflight = try Self.preflightSource(in: source)

        #expect(preflight.contains("try PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()"))
        #expect(preflight.contains("self.simulatorQAEvidenceLabel = nil"))
        #expect(preflight.contains("self.simulatorQASnapshot = nil"))
        #expect(source.contains("case .es80PassiveCapture:"))
        #expect(source.contains("if PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure"))
        #expect(source.contains("initialResearchCoordinator = try? PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()"))
        #expect(source.contains("initialResearchCoordinator = try? PassiveBluetoothExperimentOneCoordinator()"))
    }
}
