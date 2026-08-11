import Foundation
import Testing

@Suite("Experiment One coordinator strict rediscovery compatibility")
struct PassiveBluetoothExperimentOneCoordinatorStrictRediscoveryCompatibilityTests {
    private static func packageSource(_ filename: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent(filename),
            encoding: .utf8
        )
    }

    @Test("coordinator preserves retryability only while producer staging authority remains readable")
    func coordinatorUsesNarrowProducerStateInsteadOfRemovedConsumedFlag() throws {
        let coordinator = try Self.packageSource("PassiveBluetoothExperimentOneCoordinator.swift")
        let run = try Self.packageSource("PassiveBluetoothExperimentOneRun.swift")

        let connectStart = try #require(
            coordinator.range(of: "public func connectPreparedCapture(")?.lowerBound
        )
        let connectSection = coordinator[connectStart..<coordinator.endIndex]

        let controllerCall = try #require(
            connectSection.range(of: "controller.connectUsingExperimentOneAdmission(admission")
        )
        let catchStart = try #require(
            connectSection.range(of: "        } catch {", range: controllerCall.upperBound..<connectSection.endIndex)
        )
        let stagingProbe = try #require(
            connectSection.range(
                of: "admission.previewForControllerStaging()",
                range: catchStart.upperBound..<connectSection.endIndex
            )
        )
        let consumedFailure = try #require(
            connectSection.range(
                of: "ConsumptionError.alreadyConsumed",
                range: stagingProbe.upperBound..<connectSection.endIndex
            )
        )
        let clear = try #require(
            connectSection.range(
                of: "pendingCaptureAdmission = nil",
                range: consumedFailure.upperBound..<connectSection.endIndex
            )
        )

        #expect(controllerCall.lowerBound < catchStart.lowerBound)
        #expect(catchStart.lowerBound < stagingProbe.lowerBound)
        #expect(stagingProbe.lowerBound < consumedFailure.lowerBound)
        #expect(consumedFailure.lowerBound < clear.lowerBound)
        #expect(!connectSection.contains("admission.isConsumed"))
        #expect(!run.contains("var isConsumed: Bool"))
        #expect(run.contains("func previewForControllerStaging() throws -> StagingPreview"))
    }
}
