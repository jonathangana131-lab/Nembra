import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One coordinator field construction")
@MainActor
struct PassiveBluetoothExperimentOneCoordinatorFieldGateTests {
    @Test("current V14 public ES80 factory fails closed while physical gate is NO-GO")
    func publicFactoryRespectsMechanicalNoGo() {
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure == false)

        do {
            _ = try PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()
            Issue.record("current V14 NO-GO build must not construct an app-facing physical Experiment One coordinator")
        } catch let error as PassiveBluetoothExperimentOneCoordinator.CoordinatorError {
            #expect(error == .fieldExecutionNotAuthorized)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("source exposes no public caller-supplied controller/vehicle initializer")
    func productionConstructionSurfaceIsSealed() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("PassiveBluetoothExperimentOneCoordinator.swift"),
            encoding: .utf8
        )

        #expect(source.contains("public static func makeAuthorizedES80()"))
        #expect(source.contains("guard PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure"))
        #expect(source.contains("package init(\n        controller: ForegroundCoreBluetoothCaptureController"))
        #expect(!source.contains("public init(\n        controller: ForegroundCoreBluetoothCaptureController"))
    }
}