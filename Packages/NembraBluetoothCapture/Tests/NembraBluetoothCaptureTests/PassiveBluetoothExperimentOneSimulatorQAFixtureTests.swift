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
    @Test("every scenario pins an exact truthful tuple and remains non-authorizing")
    @MainActor
    func everyScenarioStaysNonAuthorizing() {
        typealias Fixture = PassiveBluetoothExperimentOneSimulatorQAFixture
        typealias Correlation = PassiveBluetoothExperimentOneCoordinator.CorrelationStatus
        typealias Connection = PassiveBluetoothExperimentOneCoordinator.ConnectionStatus

        func assertSnapshot(
            _ snapshot: Fixture.Snapshot,
            correlation: Correlation,
            connection: Connection,
            admissionPrepared: Bool,
            targetRediscovered: Bool,
            observationReady: Bool,
            canFinalize: Bool,
            artifactState: Fixture.ArtifactState
        ) {
            #expect(snapshot.evidenceLabel == "SIMULATOR / QA")
            #expect(snapshot.recipeID == .es80FingerprintV1)
            #expect(
                snapshot.fieldExecutionStatus
                    == .noGo(.finalComposedBuildNotAuthorized)
            )
            #expect(!snapshot.physicalProcedurePermitted)
            #expect(!snapshot.mayUseBluetoothTransport)
            #expect(snapshot.correlation == correlation)
            #expect(snapshot.connection == connection)
            #expect(snapshot.hasPreparedCaptureAdmission == admissionPrepared)
            #expect(snapshot.isCorrelatedTargetRediscovered == targetRediscovered)
            #expect(snapshot.observationReady == observationReady)
            #expect(snapshot.canFinalizeObservationHorizon == canFinalize)
            #expect(snapshot.artifactState == artifactState)
        }

        #expect(Fixture.Scenario.allCases == Fixture.happyPathScenarios + [.foregroundInterrupted])

        let fixture = Fixture.make()
        var visited: [Fixture.Scenario] = []

        for expected in Fixture.happyPathScenarios {
            let snapshot = fixture.snapshot
            visited.append(snapshot.scenario)
            #expect(snapshot.scenario == expected)

            switch expected {
            case .stationaryPreflight,
                 .firstPoweredOff,
                 .firstPoweredOn,
                 .secondPoweredOff:
                assertSnapshot(snapshot, correlation: .incomplete, connection: .idle, admissionPrepared: false, targetRediscovered: false, observationReady: false, canFinalize: false, artifactState: .unavailable)
            case .secondPoweredOn:
                assertSnapshot(snapshot, correlation: .singleRepeatableCandidate, connection: .idle, admissionPrepared: false, targetRediscovered: false, observationReady: false, canFinalize: false, artifactState: .unavailable)
            case .targetConfirmation:
                assertSnapshot(snapshot, correlation: .singleRepeatableCandidate, connection: .idle, admissionPrepared: true, targetRediscovered: false, observationReady: false, canFinalize: false, artifactState: .unavailable)
            case .passiveDiscovery:
                assertSnapshot(snapshot, correlation: .singleRepeatableCandidate, connection: .connecting, admissionPrepared: true, targetRediscovered: true, observationReady: false, canFinalize: false, artifactState: .unavailable)
            case .observationReady, .captureInProgress:
                assertSnapshot(snapshot, correlation: .singleRepeatableCandidate, connection: .connected, admissionPrepared: false, targetRediscovered: false, observationReady: true, canFinalize: false, artifactState: .unavailable)
            case .observationHorizonReady:
                assertSnapshot(snapshot, correlation: .singleRepeatableCandidate, connection: .connected, admissionPrepared: false, targetRediscovered: false, observationReady: true, canFinalize: true, artifactState: .unavailable)
            case .horizonSealed:
                assertSnapshot(snapshot, correlation: .singleRepeatableCandidate, connection: .idle, admissionPrepared: false, targetRediscovered: false, observationReady: true, canFinalize: false, artifactState: .sealed)
            case .captureComplete:
                assertSnapshot(snapshot, correlation: .singleRepeatableCandidate, connection: .idle, admissionPrepared: false, targetRediscovered: false, observationReady: true, canFinalize: false, artifactState: .completeReadyForAnalysis)
            case .shareRetry:
                assertSnapshot(snapshot, correlation: .singleRepeatableCandidate, connection: .idle, admissionPrepared: false, targetRediscovered: false, observationReady: true, canFinalize: false, artifactState: .shareRetry)
            case .foregroundInterrupted:
                Issue.record("foreground interruption must not enter the happy path")
            }
            _ = fixture.advance()
        }

        #expect(visited == Fixture.happyPathScenarios)
        #expect(fixture.snapshot.scenario == .shareRetry)

        let interrupted = Fixture.make(scenario: .foregroundInterrupted).snapshot
        assertSnapshot(interrupted, correlation: .invalidEvidence, connection: .unavailable, admissionPrepared: false, targetRediscovered: false, observationReady: false, canFinalize: false, artifactState: .invalidated)
        #expect(fixture.reset().scenario == .stationaryPreflight)
    }
    #endif

    private func fixtureSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent("Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneSimulatorQAFixture.swift"), encoding: .utf8)
    }
}
