import Foundation
import Testing

@Suite("Experiment One software export setup truth")
struct PassiveBluetoothExperimentOneSoftwareExportSetupTruthTests {
    private static func source() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneSoftwareExport.swift"),
            encoding: .utf8
        )
    }

    @Test("software export requires operator-declared stationary setup")
    func setupIsExplicitAtEveryPublicExportBoundary() throws {
        let source = try Self.source()

        #expect(source.contains("runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,\n        setup: PassiveBluetoothStationaryCaptureSetup"))
        #expect(source.contains("finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,\n        setup: PassiveBluetoothStationaryCaptureSetup"))
        #expect(source.contains("func finalizedSoftwareExportForCurrentApplication(\n        setup: PassiveBluetoothStationaryCaptureSetup"))
        #expect(source.contains("func encodedFinalizedSoftwareExportForCurrentApplication(\n        setup: PassiveBluetoothStationaryCaptureSetup,"))
        #expect(source.contains("setup: setup"))
    }

    @Test("software export never invents stationary setup declarations")
    func noHardcodedSetupAuthority() throws {
        let source = try Self.source()
        #expect(!source.contains("chargerState: .disconnected"))
        #expect(!source.contains("executionContext: .foregroundUnlockedScreenOn"))
        #expect(!source.contains("stockAppReferenceSetup: .none"))
    }

    @Test("closed-world verifier remains recursive after setup repair")
    func recursiveClosedWorldValidationIsPreserved() throws {
        let source = try Self.source()
        #expect(source.contains("try validateClosedWorldShape(data)"))
        #expect(source.contains("path: \"build\""))
        #expect(source.contains("path: \"correlationWindows[\\(index)]\""))
        #expect(source.contains("path: \"correlationWindows[\\(index)].candidates[\\(candidateIndex)]\""))
        #expect(source.contains("unexpectedWireField(qualified)"))
    }
}
