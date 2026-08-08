import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One Simulator QA fixture boundary")
struct PassiveBluetoothExperimentOneSimulatorQAFixtureTests {
    @Test("fixture source is compile-bounded and cannot own physical transport or field GO")
    func sourceBoundaryIsMechanical() throws {
        let source = try fixtureSource()

        #expect(source.hasPrefix("#if DEBUG && targetEnvironment(simulator)\n"))
        #expect(source.hasSuffix("#endif\n"))
        #expect(source.contains("public static let evidenceLabel = \"SIMULATOR / QA\""))
        #expect(source.contains("physicalProcedurePermitted: false"))
        #expect(source.contains("mayUseBluetoothTransport: false"))
        #expect(!source.contains("import CoreBluetooth"))
        #expect(!source.contains("ForegroundCoreBluetoothCaptureController"))
        #expect(!source.contains("PassiveBluetoothExperimentOneCoordinator("))
        #expect(!source.contains("UserDefaults"))
        #expect(!source.contains("ProcessInfo"))
        #expect(!source.contains("case go"))
        #expect(!source.contains("permitsPhysicalProcedure = true"))
    }

    @Test("production field gate remains NO-GO independently of fixture source")
    func productionGateRemainsClosed() {
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.status
                == .noGo(.finalComposedBuildNotAuthorized)
        )
        #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
    }

    #if DEBUG && targetEnvironment(simulator)
    @Test("every positive scenario stays labeled and mechanically non-authorizing")
    @MainActor
    func everyScenarioStaysNonAuthorizing() {
        let fixture = PassiveBluetoothExperimentOneSimulatorQAFixture.make()
        var visited: [PassiveBluetoothExperimentOneSimulatorQAFixture.Scenario] = []

        for expected in PassiveBluetoothExperimentOneSimulatorQAFixture.happyPathScenarios {
            let snapshot = fixture.snapshot
            visited.append(snapshot.scenario)

            #expect(snapshot.scenario == expected)
            #expect(snapshot.evidenceLabel == "SIMULATOR / QA")
            #expect(snapshot.recipeID == .es80FingerprintV1)
            #expect(
                snapshot.fieldExecutionStatus
                    == .noGo(.finalComposedBuildNotAuthorized)
            )
            #expect(!snapshot.physicalProcedurePermitted)
            #expect(!snapshot.mayUseBluetoothTransport)

            _ = fixture.advance()
        }

        #expect(visited == PassiveBluetoothExperimentOneSimulatorQAFixture.happyPathScenarios)
        #expect(fixture.snapshot.scenario == .shareRetry)

        let interrupted = PassiveBluetoothExperimentOneSimulatorQAFixture.snapshot(
            for: .foregroundInterrupted
        )
        #expect(interrupted.artifactState == .invalidated)
        #expect(interrupted.correlation == .invalidEvidence)
        #expect(interrupted.connection == .unavailable)
        #expect(!interrupted.physicalProcedurePermitted)
        #expect(!interrupted.mayUseBluetoothTransport)

        let reset = fixture.reset()
        #expect(reset.scenario == .stationaryPreflight)
        #expect(reset.artifactState == .unavailable)
    }
    #endif

    private func fixtureSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot
            .appendingPathComponent("Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneSimulatorQAFixture.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
