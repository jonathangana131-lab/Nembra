import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One canonical ES80 construction authority")
struct PassiveBluetoothExperimentOneCanonicalES80ConstructionTests {
    private typealias Coordinator = PassiveBluetoothExperimentOneCoordinator
    private typealias ConstructionError = Coordinator.CanonicalES80ConstructionError

    private static func factorySource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("PassiveBluetoothExperimentOneCoordinator+CanonicalES80.swift"),
            encoding: .utf8
        )
    }

    @Test("ordinary test-host NO-GO prevents canonical live-controller construction")
    @MainActor
    func currentNoGoStopsFactoryBeforeControllerExists() {
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure == false)

        do {
            _ = try Coordinator.makeAuthorizedES80()
            Issue.record("expected ordinary test-host construction to remain field-locked")
        } catch let error as ConstructionError {
            #expect(error == .fieldExecutionNotAuthorized)
        } catch {
            Issue.record("unexpected canonical ES80 construction error: \(error)")
        }
    }

    @Test("TODAY factory requires package research authority before CoreBluetooth construction")
    func fieldGatePrecedesCanonicalControllerCreation() throws {
        let source = try Self.factorySource()
        let researchStatus = try #require(
            source.range(
                of: "guard case .researchBuildAuthorized = PassiveBluetoothExperimentOneFieldExecutionGate.status"
            )
        )
        let permit = try #require(
            source.range(of: "PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure")
        )
        let controller = try #require(
            source.range(of: "ForegroundCoreBluetoothCaptureController(")
        )
        let initializer = try #require(
            source.range(of: "PassiveBluetoothExperimentOneCoordinator(controller: controller)")
        )

        #expect(researchStatus.lowerBound < permit.lowerBound)
        #expect(permit.lowerBound < controller.lowerBound)
        #expect(controller.lowerBound < initializer.lowerBound)
        #expect(source.contains("throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized"))
        #expect(!source.contains("try? ForegroundCoreBluetoothCaptureController("))
    }
}
