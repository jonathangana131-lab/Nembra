import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One canonical ES80 coordinator")
struct PassiveBluetoothExperimentOneCoordinatorCanonicalES80Tests {
    @Test @MainActor
    func publicFactoryFailsClosedForOrdinaryTestHost() {
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure == false)

        do {
            _ = try PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()
            Issue.record("ordinary test host must not construct a field Experiment One coordinator")
        } catch let error as PassiveBluetoothExperimentOneCoordinator.CanonicalES80ConstructionError {
            #expect(error == .fieldExecutionNotAuthorized)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func sourceExposesNoPublicInjectedControllerInitializerOrUngatedConvenienceInit() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("NembraBluetoothCapture")
        let coordinatorSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("PassiveBluetoothExperimentOneCoordinator.swift"),
            encoding: .utf8
        )
        let canonicalSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("PassiveBluetoothExperimentOneCoordinator+CanonicalES80.swift"),
            encoding: .utf8
        )

        #expect(coordinatorSource.contains("package init(controller: ForegroundCoreBluetoothCaptureController) throws"))
        #expect(!coordinatorSource.contains("public init(controller: ForegroundCoreBluetoothCaptureController) throws"))
        #expect(canonicalSource.contains("static func makeAuthorizedES80()"))
        #expect(
            canonicalSource.contains(
                "guard case .researchBuildAuthorized = PassiveBluetoothExperimentOneFieldExecutionGate.status"
            )
        )
        #expect(canonicalSource.contains("PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure"))
        #expect(!canonicalSource.contains("convenience init()"))
    }
}
