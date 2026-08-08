import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One canonical ES80 coordinator")
struct PassiveBluetoothExperimentOneCoordinatorCanonicalES80Tests {
    @Test @MainActor
    func currentPublicFactoryFailsClosedWhilePhysicalGateIsNoGo() {
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

    @Test @MainActor
    func packageSeamStillOwnsCanonicalCorrelationProducerForDeterministicTests() throws {
        let controller = try ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
        let coordinator = try PassiveBluetoothExperimentOneCoordinator(controller: controller)

        let progress = try #require(coordinator.powerCycleObservationSession.progress)
        #expect(progress.phase == .firstPoweredOff)
        #expect(progress.completedWindowCount == 0)
        #expect(coordinator.hasPreparedCaptureAdmission == false)
        #expect(coordinator.preparedCorrelatedTargetIdentifier == nil)
        #expect(coordinator.controller === controller)
        #expect(coordinator.controller.hasTargetSession == false)
    }

    @Test
    func sourceExposesNoUngatedPublicConstructionPath() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceDirectory = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("NembraBluetoothCapture")
        let coordinatorSource = try String(
            contentsOf: sourceDirectory
                .appendingPathComponent("PassiveBluetoothExperimentOneCoordinator.swift"),
            encoding: .utf8
        )
        let canonicalSource = try String(
            contentsOf: sourceDirectory
                .appendingPathComponent("PassiveBluetoothExperimentOneCoordinator+CanonicalES80.swift"),
            encoding: .utf8
        )

        #expect(coordinatorSource.contains("package init(controller: ForegroundCoreBluetoothCaptureController)"))
        #expect(!coordinatorSource.contains("public init(controller: ForegroundCoreBluetoothCaptureController)"))
        #expect(!canonicalSource.contains("convenience init()"))
        #expect(canonicalSource.contains("static func makeAuthorizedES80()"))
        #expect(canonicalSource.contains("guard PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure"))
    }
}